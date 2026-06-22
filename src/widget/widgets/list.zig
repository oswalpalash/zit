const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const animation = @import("../animation.zig");
const event_module = @import("../../event/event.zig");
const theme = @import("../theme.zig");
const accessibility = @import("../accessibility.zig");
const compat = @import("../../compat.zig");

const ActiveDrag = struct {
    source: *List,
    from_index: usize,
    text: []const u8,
};

var active_drag: ?ActiveDrag = null;

pub const ItemProvider = struct {
    ctx: ?*anyopaque = null,
    count: *const fn (?*anyopaque) usize,
    item_at: *const fn (usize, ?*anyopaque) []const u8,
};

pub const CrossDropMode = enum { move, copy };

/// List widget for displaying and selecting items with incremental typeahead search
pub const List = struct {
    /// Base widget
    widget: base.Widget,
    /// List items
    items: std.ArrayList([]const u8),
    /// Optional virtual data provider (avoids storing all items)
    item_provider: ?ItemProvider = null,
    /// Selected item index
    selected_index: usize = 0,
    /// First visible item index
    first_visible_index: usize = 0,
    /// Visible items count
    visible_items_count: usize = 0,
    /// Normal foreground color
    fg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    /// Normal background color
    bg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    /// Selected foreground color
    selected_fg: render.Color = render.Color{ .named_color = render.NamedColor.black },
    /// Selected background color
    selected_bg: render.Color = render.Color{ .named_color = render.NamedColor.cyan },
    /// Focused foreground color
    focused_fg: render.Color = render.Color{ .named_color = render.NamedColor.black },
    /// Focused background color
    focused_bg: render.Color = render.Color{ .named_color = render.NamedColor.white },
    /// On selection callback
    on_select: ?*const fn (usize, []const u8) void = null,
    /// On item activate callback
    on_item_activate: ?*const fn (usize) void = null,
    /// Allocator for list operations
    allocator: std.mem.Allocator,
    /// Border style
    border: render.BorderStyle = .none,
    /// Rolling buffer for incremental search
    search_buffer: [64]u8 = undefined,
    /// Current length of the incremental search query
    search_len: usize = 0,
    /// Timestamp of the last search keystroke in milliseconds
    last_search_ms: ?i64 = null,
    /// How long to keep appending to the search buffer (in milliseconds)
    search_timeout_ms: u64 = 900,
    /// Clock source (primarily overridden in tests)
    clock: *const fn () i64 = compat.nowMillis,
    /// Optional shared animator for smooth scrolling
    animator: ?*animation.Animator = null,
    /// Smooth scroll driver
    scroll_driver: animation.ValueDriver = .{},
    /// Duration for scroll easing
    scroll_duration_ms: u64 = 120,
    /// Momentum multiplier applied to wheel deltas
    momentum_multiplier: f32 = 3,
    /// Limit how many virtual rows are sampled for preferred size calculations
    virtual_sample_limit: usize = 256,
    /// Enable drag-to-reorder
    enable_reorder: bool = false,
    /// Whether the current drag originated from this list
    dragging: bool = false,
    /// Drag origin index
    drag_start_index: ?usize = null,
    /// Current drop preview index
    drag_hover_index: ?usize = null,
    /// Whether this list can accept drops from other lists
    accept_external_drops: bool = true,
    /// Buffer that owns the active drag payload text
    drag_payload: ?[]u8 = null,
    /// Callback fired after a reorder happens (local or external)
    on_reorder: ?*const fn (from: usize, to: usize, source: *List, target: *List) void = null,
    /// Behavior for external drops
    cross_drop_mode: CrossDropMode = .move,

    /// Virtual method table for List
    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    fn fromWidgetPtr(widget_ptr: *anyopaque) *List {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        return @fieldParentPtr("widget", widget_ref);
    }

    fn addOffsetClamped(origin: u16, offset: u16) u16 {
        const value = @as(u32, origin) + @as(u32, offset);
        return @intCast(@min(value, @as(u32, std.math.maxInt(u16))));
    }

    fn addU16Clamped(a: u16, b: u16) u16 {
        const value = @as(u32, a) + @as(u32, b);
        return @intCast(@min(value, @as(u32, std.math.maxInt(u16))));
    }

    fn addUsizeSaturating(a: usize, b: usize) usize {
        return std.math.add(usize, a, b) catch std.math.maxInt(usize);
    }

    fn clampUsizeToU16(value: usize) u16 {
        return @intCast(@min(value, @as(usize, std.math.maxInt(u16))));
    }

    fn normalizedScrollValue(value: f32, max_offset: usize) f32 {
        const max_value = @as(f32, @floatFromInt(max_offset));
        if (std.math.isPositiveInf(value)) return max_value;
        if (!std.math.isFinite(value)) return 0;
        return std.math.clamp(value, 0, max_value);
    }

    fn scrollIndexFromValue(value: f32, max_offset: usize) usize {
        const clamped = normalizedScrollValue(value, max_offset);
        return @as(usize, @intFromFloat(std.math.floor(clamped)));
    }

    /// Initialize a new list
    pub fn init(allocator: std.mem.Allocator) !*List {
        const self = try allocator.create(List);

        self.* = List{
            .widget = base.Widget.init(&vtable),
            .items = std.ArrayList([]const u8).empty,
            .allocator = allocator,
        };
        self.setTheme(theme.Theme.dark());
        self.item_provider = null;
        self.scroll_driver.snap(0);
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.list), "List", "");

        return self;
    }

    /// Clean up list resources
    pub fn deinit(self: *List) void {
        self.cancelDragFromSelf();
        // Free all items
        for (self.items.items) |item| {
            self.allocator.free(item);
        }
        self.items.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    /// Add an item to the list
    pub fn addItem(self: *List, item: []const u8) !void {
        if (self.item_provider != null) return error.VirtualDataActive;
        try self.items.ensureUnusedCapacity(self.allocator, 1);
        const item_copy = try self.allocator.dupe(u8, item);
        self.items.appendAssumeCapacity(item_copy);
        self.widget.markDirty();
    }

    /// Remove an item from the list
    pub fn removeItem(self: *List, index: usize) void {
        if (self.item_provider != null) return;
        if (index >= self.items.items.len) {
            return;
        }
        self.cancelDragFromSelf();

        const previous_selected_index = self.selected_index;
        const previous_first_visible_index = self.first_visible_index;

        // Free the item
        self.allocator.free(self.items.items[index]);

        // Remove the item
        _ = self.items.orderedRemove(index);

        // Update selected index if needed
        if (self.items.items.len == 0) {
            self.selected_index = 0;
        } else if (index < previous_selected_index) {
            self.selected_index = previous_selected_index - 1;
            self.ensureItemVisible(self.selected_index);
        } else if (self.selected_index >= self.items.items.len) {
            self.setSelectedIndex(self.items.items.len - 1);
        }

        if (index < previous_first_visible_index and previous_first_visible_index > 0) {
            self.scrollTo(@floatFromInt(previous_first_visible_index - 1));
        } else {
            self.clampScroll();
        }
        self.widget.markDirty();
    }

    /// Clear all items from the list
    pub fn clear(self: *List) void {
        const had_items = self.items.items.len > 0;
        self.cancelDragFromSelf();
        // Free all items
        for (self.items.items) |item| {
            self.allocator.free(item);
        }
        self.items.clearRetainingCapacity();
        self.setSelectedIndex(0);
        self.resetTypeahead();
        if (had_items) self.widget.markDirty();
    }

    /// Set the selected item
    pub fn setSelectedIndex(self: *List, index: usize) void {
        _ = self.trySetSelectedIndex(index);
    }

    fn trySetSelectedIndex(self: *List, index: usize) bool {
        const previous_selected_index = self.selected_index;
        const previous_first_visible_index = self.first_visible_index;
        const previous_scroll_current = self.scroll_driver.current;
        const previous_scroll_target = self.scroll_driver.target;

        const count = self.itemCount();
        if (count == 0) {
            if (self.selected_index != 0) {
                self.selected_index = 0;
                self.widget.markDirty();
                return true;
            }
            self.selected_index = 0;
            return false;
        }

        const clamped_index = @min(index, count - 1);
        if (clamped_index == self.selected_index) {
            self.ensureItemVisible(self.selected_index);
            return previous_first_visible_index != self.first_visible_index or
                previous_scroll_current != self.scroll_driver.current or
                previous_scroll_target != self.scroll_driver.target;
        }

        const old_index = self.selected_index;
        self.selected_index = clamped_index;

        // Ensure the selected item is visible
        self.ensureItemVisible(self.selected_index);
        self.widget.markDirty();

        // Call the selection changed callback
        if (old_index != self.selected_index and self.on_select != null) {
            self.on_select.?(self.selected_index, self.getSelectedItem() orelse "");
        }
        return previous_selected_index != self.selected_index or
            previous_first_visible_index != self.first_visible_index or
            previous_scroll_current != self.scroll_driver.current or
            previous_scroll_target != self.scroll_driver.target;
    }

    /// Get the selected item
    pub fn getSelectedIndex(self: *List) usize {
        return self.selected_index;
    }

    /// Get the selected item text
    pub fn getSelectedItem(self: *List) ?[]const u8 {
        if (self.itemCount() == 0) {
            return null;
        }
        self.clampSelection();
        return self.itemAt(self.selected_index);
    }

    /// Ensure the item at the given index is visible
    fn ensureItemVisible(self: *List, index: usize) void {
        if (index < self.first_visible_index) {
            self.scrollTo(@floatFromInt(index));
        } else if (self.visible_items_count > 0 and index >= self.first_visible_index + self.visible_items_count) {
            self.scrollTo(@floatFromInt(index - self.visible_items_count + 1));
        }
    }

    /// Set the list colors
    pub fn setColors(self: *List, fg: render.Color, bg: render.Color, selected_fg: render.Color, selected_bg: render.Color) void {
        if (std.meta.eql(self.fg, fg) and
            std.meta.eql(self.bg, bg) and
            std.meta.eql(self.selected_fg, selected_fg) and
            std.meta.eql(self.selected_bg, selected_bg)) return;

        self.fg = fg;
        self.bg = bg;
        self.selected_fg = selected_fg;
        self.selected_bg = selected_bg;
        self.widget.markDirty();
    }

    /// Apply theme defaults for list colors.
    pub fn setTheme(self: *List, theme_value: theme.Theme) void {
        const surface = theme.surfaceColors(theme_value);
        const selected = theme.selectionColors(theme_value);
        if (std.meta.eql(self.fg, surface.fg) and
            std.meta.eql(self.bg, surface.bg) and
            std.meta.eql(self.selected_fg, selected.fg) and
            std.meta.eql(self.selected_bg, selected.bg) and
            std.meta.eql(self.focused_fg, selected.focused_fg) and
            std.meta.eql(self.focused_bg, selected.focused_bg)) return;

        self.fg = surface.fg;
        self.bg = surface.bg;
        self.selected_fg = selected.fg;
        self.selected_bg = selected.bg;
        self.focused_fg = selected.focused_fg;
        self.focused_bg = selected.focused_bg;
        self.widget.markDirty();
    }

    /// Set the on-select callback
    pub fn setOnSelect(self: *List, callback: *const fn (usize, []const u8) void) void {
        self.on_select = callback;
    }

    /// Set the on-item-activate callback
    pub fn setOnItemActivate(self: *List, callback: *const fn (usize) void) void {
        self.on_item_activate = callback;
    }

    /// Set the border style
    pub fn setBorder(self: *List, border: render.BorderStyle) void {
        if (self.border == border) return;
        self.border = border;
        self.widget.markDirty();
    }

    /// Configure how long to keep accumulating typeahead search input.
    pub fn setTypeaheadTimeout(self: *List, timeout_ms: u64) void {
        self.search_timeout_ms = timeout_ms;
    }

    /// Clear any buffered typeahead query.
    pub fn resetTypeahead(self: *List) void {
        self.search_len = 0;
        self.last_search_ms = null;
    }

    /// Override the timing source used for typeahead (test-only hook).
    pub fn setTypeaheadClock(self: *List, clock: *const fn () i64) void {
        self.clock = clock;
    }

    /// Attach a shared animator to enable smooth scrolling and drop previews.
    pub fn attachAnimator(self: *List, animator: *animation.Animator) void {
        self.animator = animator;
        self.scroll_driver.snap(@floatFromInt(self.first_visible_index));
    }

    /// Enable virtualized rendering with an external item provider.
    pub fn useItemProvider(self: *List, provider: ItemProvider) void {
        self.clear();
        self.items.clearRetainingCapacity();
        self.item_provider = provider;
        self.syncScrollFromDriver();
        self.widget.markDirty();
    }

    /// Return to the owned item storage model.
    pub fn clearItemProvider(self: *List) void {
        if (self.item_provider == null) return;
        self.item_provider = null;
        self.syncScrollFromDriver();
        self.widget.markDirty();
    }

    /// Enable or disable drag-to-reorder behavior.
    pub fn setReorderable(self: *List, enabled: bool) void {
        if (!enabled) self.cancelDragFromSelf();
        self.enable_reorder = enabled;
    }

    /// Decide how cross-list drops are handled (move vs copy).
    pub fn setCrossDropMode(self: *List, mode: CrossDropMode) void {
        self.cross_drop_mode = mode;
    }

    /// Allow or block drops coming from other lists.
    pub fn setAcceptExternalDrops(self: *List, enabled: bool) void {
        self.accept_external_drops = enabled;
    }

    /// Notify consumers when a reorder happens.
    pub fn setOnReorder(self: *List, callback: *const fn (from: usize, to: usize, source: *List, target: *List) void) void {
        self.on_reorder = callback;
    }

    fn clearDragPayload(self: *List) void {
        if (self.drag_payload) |buf| {
            self.allocator.free(buf);
            self.drag_payload = null;
        }
    }

    fn resetDragState(self: *List) void {
        self.dragging = false;
        self.drag_start_index = null;
        self.drag_hover_index = null;
        self.clearDragPayload();
    }

    fn cancelDragFromSelf(self: *List) void {
        if (active_drag) |drag| {
            if (drag.source == self) {
                active_drag = null;
            }
        }
        self.resetDragState();
    }

    fn cancelActiveDrag() void {
        if (active_drag) |drag| {
            drag.source.resetDragState();
            active_drag = null;
        }
    }

    fn itemCount(self: *List) usize {
        if (self.item_provider) |provider| {
            return provider.count(provider.ctx);
        }
        return self.items.items.len;
    }

    fn itemAt(self: *List, index: usize) []const u8 {
        if (self.item_provider) |provider| {
            return provider.item_at(index, provider.ctx);
        }
        return self.items.items[index];
    }

    fn maxScrollOffset(self: *List) usize {
        const count = self.itemCount();
        return if (self.visible_items_count > 0 and count > self.visible_items_count)
            count - self.visible_items_count
        else
            0;
    }

    fn clampScroll(self: *List) void {
        const max_offset = self.maxScrollOffset();
        const clamped = normalizedScrollValue(self.scroll_driver.current, max_offset);
        self.scroll_driver.current = clamped;
        self.first_visible_index = scrollIndexFromValue(clamped, max_offset);
    }

    fn clampSelection(self: *List) void {
        const count = self.itemCount();
        if (count == 0) {
            self.selected_index = 0;
        } else if (self.selected_index >= count) {
            self.selected_index = count - 1;
        }
    }

    fn syncScrollFromDriver(self: *List) void {
        self.clampScroll();
    }

    fn scrollTo(self: *List, target: f32) void {
        const max_offset = self.maxScrollOffset();
        const clamped = normalizedScrollValue(target, max_offset);
        const start = normalizedScrollValue(self.scroll_driver.current, max_offset);
        self.scroll_driver.current = start;
        if (self.animator) |anim| {
            const onChange = struct {
                fn apply(value: f32, ctx: ?*anyopaque) void {
                    const list = @as(*List, @ptrCast(@alignCast(ctx.?)));
                    list.scroll_driver.current = value;
                    list.syncScrollFromDriver();
                    list.widget.markDirty();
                }
            }.apply;

            _ = self.scroll_driver.animate(
                anim,
                start,
                clamped,
                self.scroll_duration_ms,
                animation.Easing.easeInOutQuad,
                onChange,
                @ptrCast(self),
            ) catch {
                self.scroll_driver.snap(clamped);
                self.syncScrollFromDriver();
                if (clamped != start) self.widget.markDirty();
            };
            if (clamped != start) self.widget.markDirty();
        } else {
            self.scroll_driver.snap(clamped);
            self.syncScrollFromDriver();
            if (clamped != start) self.widget.markDirty();
        }
    }

    fn scrollBy(self: *List, delta: f32) void {
        self.scrollTo(self.scroll_driver.current + delta * self.momentum_multiplier);
    }

    fn startDrag(self: *List, index: usize) void {
        if (!self.enable_reorder) return;
        cancelActiveDrag();

        self.dragging = true;
        self.drag_start_index = index;
        self.drag_hover_index = index;
        self.clearDragPayload();

        const owned = self.allocator.dupe(u8, self.itemAt(index)) catch null;
        if (owned) |buf| {
            self.drag_payload = buf;
            active_drag = ActiveDrag{ .source = self, .from_index = index, .text = buf };
        } else {
            active_drag = ActiveDrag{ .source = self, .from_index = index, .text = self.itemAt(index) };
        }
    }

    fn endDrag(self: *List) void {
        if (active_drag) |drag| {
            if (drag.source == self) {
                active_drag = null;
            }
        }
        self.dragging = false;
        self.drag_start_index = null;
        self.drag_hover_index = null;
        self.clearDragPayload();
    }

    fn reorderInPlace(self: *List, from: usize, to_unclamped: usize) void {
        if (self.item_provider != null) {
            if (self.on_reorder) |cb| cb(from, to_unclamped, self, self);
            return;
        }
        if (from >= self.items.items.len) return;

        const target_cap = @min(to_unclamped, self.items.items.len);
        var to = target_cap;
        if (to == from or (from + 1 == to)) {
            return;
        }

        const moved = self.items.orderedRemove(from);
        if (to > from) {
            to -= 1;
        }

        self.items.insertAssumeCapacity(to, moved);

        self.setSelectedIndex(to);
        if (self.on_reorder) |cb| cb(from, to, self, self);
        active_drag = null;
    }

    fn acceptExternalDrop(self: *List, drag: ActiveDrag, drop_index: usize) !void {
        if (!self.accept_external_drops) return;

        if (self.item_provider == null) {
            const target_idx = @min(drop_index, self.itemCount());
            const copy = try self.allocator.dupe(u8, drag.text);
            errdefer self.allocator.free(copy);
            try self.items.insert(self.allocator, target_idx, copy);
            errdefer {
                self.allocator.free(copy);
                _ = self.items.orderedRemove(target_idx);
            }
            if (self.cross_drop_mode == .move and drag.source.item_provider == null) {
                drag.source.removeItem(drag.from_index);
            }
            self.setSelectedIndex(target_idx);
        }

        if (self.on_reorder) |cb| {
            cb(drag.from_index, drop_index, drag.source, self);
        }

        drag.source.resetDragState();
        active_drag = null;
    }

    fn hasDrawableBorder(self: *const List) bool {
        const rect = self.widget.rect;
        return self.border != .none and rect.width >= 2 and rect.height >= 2;
    }

    fn contentRect(self: *const List) layout_module.Rect {
        const rect = self.widget.rect;
        if (self.hasDrawableBorder() and rect.width > 2 and rect.height > 2) {
            return layout_module.Rect.init(addOffsetClamped(rect.x, 1), addOffsetClamped(rect.y, 1), rect.width - 2, rect.height - 2);
        }
        return rect;
    }

    fn rowOffsetAtY(content_rect: layout_module.Rect, y: u16) usize {
        if (y <= content_rect.y) return 0;
        return @intCast(@as(u32, y) - @as(u32, content_rect.y));
    }

    fn itemIndexAtY(self: *const List, content_rect: layout_module.Rect, y: u16) usize {
        return addUsizeSaturating(self.first_visible_index, rowOffsetAtY(content_rect, y));
    }

    fn dropIndexAtY(self: *const List, content_rect: layout_module.Rect, y: u16) usize {
        const rel_y = @min(rowOffsetAtY(content_rect, y), @as(usize, content_rect.height));
        return addUsizeSaturating(self.first_visible_index, rel_y);
    }

    /// Draw implementation for List
    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = fromWidgetPtr(widget_ptr);

        if (!self.widget.visible) {
            return;
        }

        const rect = self.widget.rect;
        const styled = self.widget.applyStyle(
            "list",
            .{ .focus = self.widget.focused, .disabled = !self.widget.enabled },
            render.Style{},
            self.fg,
            self.bg,
        );
        const fg = styled.fg;
        const bg = styled.bg;
        const style = styled.style;

        const has_border = self.hasDrawableBorder();
        const content_rect = self.contentRect();

        // Fill list background
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', fg, bg, style);
        if (has_border) {
            renderer.drawBox(rect.x, rect.y, rect.width, rect.height, self.border, fg, bg, style);
        }

        // Calculate visible items
        self.visible_items_count = @intCast(@as(usize, content_rect.height));
        if (self.visible_items_count == 0 or content_rect.height == 0 or content_rect.width == 0) {
            self.widget.drawFocusRing(renderer);
            return;
        }

        self.clampScroll();

        // Ensure the first visible index is valid
        const total_items = self.itemCount();
        if (addUsizeSaturating(self.first_visible_index, self.visible_items_count) > total_items) {
            self.first_visible_index = if (total_items > self.visible_items_count)
                total_items - self.visible_items_count
            else
                0;
            self.scroll_driver.snap(@floatFromInt(self.first_visible_index));
        }

        // Draw visible items
        const last_visible_index = @min(addUsizeSaturating(self.first_visible_index, self.visible_items_count), total_items);

        var y = content_rect.y;
        var i = self.first_visible_index;
        while (i < last_visible_index) : (i += 1) {
            const item = self.itemAt(i);
            const is_selected = i == self.selected_index;

            // Choose colors based on selection and focus state
            const item_fg = if (is_selected)
                (if (self.widget.focused) self.focused_fg else self.selected_fg)
            else
                fg;

            const item_bg = if (is_selected)
                (if (self.widget.focused) self.focused_bg else self.selected_bg)
            else
                bg;

            // Draw item background
            renderer.fillRect(content_rect.x, y, content_rect.width, 1, ' ', item_fg, item_bg, style);

            // Draw item text
            var col: u16 = 0;
            for (item) |char| {
                if (col >= content_rect.width) {
                    break;
                }

                const x = addOffsetClamped(content_rect.x, col);
                renderer.drawChar(x, y, char, item_fg, item_bg, style);
                col += 1;
            }

            y = addOffsetClamped(y, 1);
        }

        // Draw drop preview indicator for reorder/drops
        if (self.drag_hover_index) |hover| {
            const clamped_hover = @min(hover, total_items);
            const relative_hover = clamped_hover - @min(clamped_hover, self.first_visible_index);
            const indicator_y = addOffsetClamped(content_rect.y, clampUsizeToU16(relative_hover));
            const content_end_y = @as(u32, content_rect.y) + @as(u32, content_rect.height);
            if (indicator_y >= content_rect.y and @as(u32, indicator_y) < content_end_y) {
                const state = if (active_drag != null and active_drag.?.source != self)
                    event_module.DropVisuals.State.valid
                else
                    event_module.DropVisuals.State.idle;
                const colors = event_module.DropVisuals.Colors{
                    .border = fg,
                    .fill = bg,
                    .valid = render.Color{ .named_color = render.NamedColor.green },
                    .invalid = render.Color{ .named_color = render.NamedColor.red },
                    .text = fg,
                };
                event_module.DropVisuals.outline(renderer, layout_module.Rect{
                    .x = content_rect.x,
                    .y = indicator_y,
                    .width = content_rect.width,
                    .height = 1,
                }, state, colors);
            }
        }

        self.widget.drawFocusRing(renderer);
    }

    /// Event handling implementation for List
    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = fromWidgetPtr(widget_ptr);
        const total_items = self.itemCount();

        if (!self.widget.visible or !self.widget.enabled) {
            return false;
        }

        // Handle mouse events
        if (event == .mouse) {
            const mouse_event = event.mouse;
            const rect = self.widget.rect;
            const content_rect = self.contentRect();
            const inside = rect.contains(mouse_event.x, mouse_event.y);
            const inside_content = content_rect.contains(mouse_event.x, mouse_event.y);

            // External drag hover/drop
            if (active_drag) |drag| {
                if (inside_content and self.accept_external_drops and (drag.source != self or self.enable_reorder)) {
                    const drop_index = self.dropIndexAtY(content_rect, mouse_event.y);
                    self.drag_hover_index = @min(drop_index, total_items);

                    if (mouse_event.action == .release) {
                        if (drag.source == self) {
                            if (self.drag_start_index) |start_idx| {
                                self.reorderInPlace(start_idx, self.drag_hover_index.?);
                            }
                        } else {
                            try self.acceptExternalDrop(drag, self.drag_hover_index.?);
                        }
                        self.endDrag();
                        return true;
                    }
                } else if (!self.dragging) {
                    self.drag_hover_index = null;
                }
            }

            // Check if mouse is within list bounds
            if (inside and total_items > 0) {
                // Mouse wheel scrolls list even when the pointer is on the border.
                if (mouse_event.action == .scroll_up or mouse_event.action == .scroll_down) {
                    const scroll_step: i16 = if (mouse_event.scroll_delta != 0)
                        mouse_event.scroll_delta
                    else if (mouse_event.action == .scroll_up)
                        -1
                    else
                        1;

                    self.scrollBy(@as(f32, @floatFromInt(scroll_step)));
                    return true;
                }

                if (!inside_content) return true;

                // Convert y position to item index
                const item_index = self.itemIndexAtY(content_rect, mouse_event.y);

                if (item_index < total_items) {
                    // Mouse click selects item
                    if (mouse_event.action == .press and mouse_event.button == 1) {
                        self.setSelectedIndex(item_index);
                        if (self.enable_reorder) {
                            self.startDrag(item_index);
                        }
                        if (self.on_item_activate != null and !self.dragging) {
                            self.on_item_activate.?(self.selected_index);
                        }
                        return true;
                    }
                }

                // Drag updates
                if (mouse_event.action == .move and self.dragging) {
                    const drop_index = self.dropIndexAtY(content_rect, mouse_event.y);
                    self.drag_hover_index = @min(drop_index, total_items);
                    return true;
                }

                // Finish drag
                if (mouse_event.action == .release and self.dragging) {
                    const drop_index = self.drag_hover_index orelse item_index;
                    self.reorderInPlace(self.drag_start_index orelse item_index, drop_index);
                    self.endDrag();
                    return true;
                }

                return true; // Capture all mouse events within bounds
            } else if (mouse_event.action == .release and self.dragging) {
                // Cancel drag if released outside
                self.endDrag();
            }
        }

        // Handle key events
        if (event == .key and self.widget.focused and total_items > 0) {
            const key_event = event.key;
            const previous_selected_index = self.selected_index;
            self.clampSelection();
            const selection_was_clamped = previous_selected_index != self.selected_index;
            if (selection_was_clamped) self.widget.markDirty();
            const profiles = [_]input.KeybindingProfile{
                input.KeybindingProfile.commonEditing(),
                input.KeybindingProfile.emacs(),
                input.KeybindingProfile.vi(),
            };

            if (input.editorActionForEvent(key_event, &profiles)) |action| {
                switch (action) {
                    .cursor_down => {
                        const changed = if (self.selected_index + 1 < total_items)
                            self.trySetSelectedIndex(self.selected_index + 1)
                        else
                            false;
                        const handled = changed or selection_was_clamped;
                        if (handled) self.resetTypeahead();
                        return handled;
                    },
                    .cursor_up => {
                        const changed = if (self.selected_index > 0)
                            self.trySetSelectedIndex(self.selected_index - 1)
                        else
                            false;
                        const handled = changed or selection_was_clamped;
                        if (handled) self.resetTypeahead();
                        return handled;
                    },
                    .page_down => {
                        const next = addUsizeSaturating(self.selected_index, self.visible_items_count);
                        const new_index = @min(next, total_items - 1);
                        const changed = self.trySetSelectedIndex(new_index);
                        const handled = changed or selection_was_clamped;
                        if (handled) self.resetTypeahead();
                        return handled;
                    },
                    .page_up => {
                        const new_index = if (self.selected_index > self.visible_items_count)
                            self.selected_index - self.visible_items_count
                        else
                            0;
                        const changed = self.trySetSelectedIndex(new_index);
                        const handled = changed or selection_was_clamped;
                        if (handled) self.resetTypeahead();
                        return handled;
                    },
                    .line_start => {
                        const changed = self.trySetSelectedIndex(0);
                        const handled = changed or selection_was_clamped;
                        if (handled) self.resetTypeahead();
                        return handled;
                    },
                    .line_end => {
                        const changed = self.trySetSelectedIndex(total_items - 1);
                        const handled = changed or selection_was_clamped;
                        if (handled) self.resetTypeahead();
                        return handled;
                    },
                    else => {},
                }
            }

            if (key_event.key == '\r' or key_event.key == '\n') { // Enter
                if (self.on_item_activate != null) {
                    self.on_item_activate.?(self.selected_index);
                }
                self.resetTypeahead();
                return true;
            } else if (key_event.key == input.KeyCode.ESCAPE) {
                self.resetTypeahead();
                return false;
            } else if (key_event.isPrintable() and !key_event.modifiers.ctrl and !key_event.modifiers.alt) {
                if (self.handleTypeaheadKey(@as(u8, @intCast(key_event.key)))) {
                    return true;
                }
            }
        }

        return false;
    }

    fn handleTypeaheadKey(self: *List, byte: u8) bool {
        if (self.itemCount() == 0) {
            return false;
        }
        self.clampSelection();

        const now = self.clock();
        if (self.last_search_ms) |last| {
            if (now < last or @as(u64, @intCast(now - last)) > self.search_timeout_ms) {
                self.resetTypeahead();
            }
        }
        self.last_search_ms = now;

        if (self.search_len < self.search_buffer.len) {
            self.search_buffer[self.search_len] = std.ascii.toLower(byte);
            self.search_len += 1;
        } else {
            // Keep the most recent portion of the query to avoid unbounded growth.
            std.mem.copyForwards(u8, self.search_buffer[0 .. self.search_buffer.len - 1], self.search_buffer[1..]);
            self.search_buffer[self.search_buffer.len - 1] = std.ascii.toLower(byte);
            self.search_len = self.search_buffer.len;
        }

        const needle = self.search_buffer[0..self.search_len];
        if (needle.len == 0) return false;

        const start = self.selected_index;
        var i: usize = 0;
        const total = self.itemCount();
        while (i < total) : (i += 1) {
            const idx = (start + i) % total;
            if (startsWithIgnoreCase(self.itemAt(idx), needle)) {
                self.setSelectedIndex(idx);
                return true;
            }
        }

        return false;
    }

    fn startsWithIgnoreCase(haystack: []const u8, needle: []const u8) bool {
        if (needle.len == 0 or needle.len > haystack.len) {
            return false;
        }

        var i: usize = 0;
        while (i < needle.len) : (i += 1) {
            if (std.ascii.toLower(haystack[i]) != needle[i]) {
                return false;
            }
        }
        return true;
    }

    /// Layout implementation for List
    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = fromWidgetPtr(widget_ptr);
        self.widget.rect = rect;

        // Update visible items count
        const content_rect = self.contentRect();
        self.visible_items_count = @intCast(@as(usize, content_rect.height));

        self.clampScroll();
        // Ensure selected item is visible
        self.ensureItemVisible(self.selected_index);
    }

    /// Get preferred size implementation for List
    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = fromWidgetPtr(widget_ptr);

        // Find the longest item
        var max_width: u16 = 10; // Minimum width
        const total = self.itemCount();
        const sample_len = @min(total, self.virtual_sample_limit);
        var i: usize = 0;
        while (i < sample_len) : (i += 1) {
            max_width = @max(max_width, clampUsizeToU16(self.itemAt(i).len));
        }

        // Preferred height depends on number of items, with a minimum of 1
        const preferred_height = @as(u16, @intCast(@max(@as(usize, 1), @min(@as(usize, 10), total))));

        const border_extra: u16 = if (self.border == .none) 0 else 2;
        return layout_module.Size.init(addU16Clamped(max_width, border_extra), addU16Clamped(preferred_height, border_extra));
    }

    /// Can focus implementation for List
    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = fromWidgetPtr(widget_ptr);
        return self.widget.enabled and self.itemCount() > 0;
    }
};

var test_list_activated_index: ?usize = null;

fn recordListActivation(index: usize) void {
    test_list_activated_index = index;
}

test "list typeahead search cycles through matches" {
    const alloc = std.testing.allocator;
    var list = try List.init(alloc);
    defer list.deinit();

    try list.addItem("Alpha");
    try list.addItem("Garden");
    try list.addItem("Gamma");
    try list.addItem("Zzz");

    list.widget.focused = true;
    try list.widget.layout(layout_module.Rect.init(0, 0, 10, 4));

    const TestClock = struct {
        var now: i64 = 0;
        fn tick() i64 {
            return now;
        }
    };

    list.setTypeaheadClock(TestClock.tick);
    list.setTypeaheadTimeout(1_000);

    _ = try list.widget.handleEvent(.{ .key = .{ .key = 'g', .modifiers = .{} } });
    try std.testing.expectEqual(@as(usize, 1), list.selected_index); // Garden

    _ = try list.widget.handleEvent(.{ .key = .{ .key = 'a', .modifiers = .{} } });
    try std.testing.expectEqual(@as(usize, 1), list.selected_index); // "ga" still Garden

    TestClock.now = 5_000; // Exceeds timeout, clears buffer.
    _ = try list.widget.handleEvent(.{ .key = .{ .key = 'z', .modifiers = .{} } });
    try std.testing.expectEqual(@as(usize, 3), list.selected_index); // Zzz
}

test "list visible mutations mark dirty" {
    const alloc = std.testing.allocator;
    var list = try List.init(alloc);
    defer list.deinit();

    list.widget.clearDirty();
    try list.addItem("one");
    try std.testing.expect(list.widget.dirty);

    try list.addItem("two");
    try list.addItem("three");
    try list.widget.layout(layout_module.Rect.init(0, 0, 8, 1));

    list.widget.clearDirty();
    list.setSelectedIndex(1);
    try std.testing.expect(list.widget.dirty);
    list.widget.clearDirty();
    list.setSelectedIndex(1);
    try std.testing.expect(!list.widget.dirty);

    list.first_visible_index = 0;
    list.scroll_driver.snap(0);
    list.visible_items_count = 1;
    list.selected_index = 2;
    list.widget.clearDirty();
    list.setSelectedIndex(2);
    try std.testing.expect(list.widget.dirty);
    try std.testing.expectEqual(@as(usize, 2), list.first_visible_index);

    list.widget.clearDirty();
    list.setColors(render.Color.named(.white), render.Color.named(.black), render.Color.named(.black), render.Color.named(.green));
    try std.testing.expect(list.widget.dirty);
    list.widget.clearDirty();
    list.setColors(render.Color.named(.white), render.Color.named(.black), render.Color.named(.black), render.Color.named(.green));
    try std.testing.expect(!list.widget.dirty);

    list.setTheme(theme.Theme.light());
    try std.testing.expect(list.widget.dirty);
    list.widget.clearDirty();
    list.setTheme(theme.Theme.light());
    try std.testing.expect(!list.widget.dirty);

    list.setBorder(.rounded);
    try std.testing.expect(list.widget.dirty);
    list.widget.clearDirty();
    list.setBorder(.rounded);
    try std.testing.expect(!list.widget.dirty);

    list.removeItem(1);
    try std.testing.expect(list.widget.dirty);
    list.widget.clearDirty();
    list.removeItem(99);
    try std.testing.expect(!list.widget.dirty);

    list.clear();
    try std.testing.expect(list.widget.dirty);
    list.widget.clearDirty();
    list.clear();
    try std.testing.expect(!list.widget.dirty);
}

test "list provider switches mark dirty" {
    const Provider = struct {
        fn count(_: ?*anyopaque) usize {
            return 2;
        }

        fn itemAt(index: usize, _: ?*anyopaque) []const u8 {
            return if (index == 0) "virtual one" else "virtual two";
        }
    };

    const alloc = std.testing.allocator;
    var list = try List.init(alloc);
    defer list.deinit();

    list.widget.clearDirty();
    list.useItemProvider(.{
        .count = Provider.count,
        .item_at = Provider.itemAt,
    });
    try std.testing.expect(list.widget.dirty);
    try std.testing.expectEqual(@as(usize, 2), list.itemCount());

    list.widget.clearDirty();
    list.clearItemProvider();
    try std.testing.expect(list.widget.dirty);
    try std.testing.expectEqual(@as(usize, 0), list.itemCount());

    list.widget.clearDirty();
    list.clearItemProvider();
    try std.testing.expect(!list.widget.dirty);
}

test "list clamps stale selection before keyboard navigation" {
    const alloc = std.testing.allocator;
    var list = try List.init(alloc);
    defer list.deinit();

    try list.addItem("Alpha");
    try list.addItem("Beta");
    try list.addItem("Gamma");
    list.widget.focused = true;
    try list.widget.layout(layout_module.Rect.init(0, 0, 12, 2));
    list.selected_index = std.math.maxInt(usize);

    try std.testing.expect(try list.widget.handleEvent(.{ .key = .{ .key = input.KeyCode.DOWN, .modifiers = .{} } }));
    try std.testing.expectEqual(@as(usize, 2), list.selected_index);

    try std.testing.expect(try list.widget.handleEvent(.{ .key = .{ .key = input.KeyCode.UP, .modifiers = .{} } }));
    try std.testing.expectEqual(@as(usize, 1), list.selected_index);
}

test "list saturated keyboard navigation does not consume unchanged events" {
    const alloc = std.testing.allocator;
    var list = try List.init(alloc);
    defer list.deinit();

    try list.addItem("Alpha");
    try list.addItem("Beta");
    try list.addItem("Gamma");
    list.widget.focused = true;
    try list.widget.layout(layout_module.Rect.init(0, 0, 12, 3));

    list.widget.clearDirty();
    try std.testing.expect(!try list.widget.handleEvent(.{ .key = input.KeyEvent.init(input.KeyCode.UP, .{}) }));
    try std.testing.expect(!try list.widget.handleEvent(.{ .key = input.KeyEvent.init(input.KeyCode.HOME, .{}) }));
    try std.testing.expect(!try list.widget.handleEvent(.{ .key = input.KeyEvent.init(input.KeyCode.PAGE_UP, .{}) }));
    try std.testing.expect(!list.widget.dirty);
    try std.testing.expectEqual(@as(usize, 0), list.selected_index);

    try std.testing.expect(try list.widget.handleEvent(.{ .key = input.KeyEvent.init(input.KeyCode.DOWN, .{}) }));
    try std.testing.expect(list.widget.dirty);

    list.setSelectedIndex(2);
    list.widget.clearDirty();
    try std.testing.expect(!try list.widget.handleEvent(.{ .key = input.KeyEvent.init(input.KeyCode.DOWN, .{}) }));
    try std.testing.expect(!try list.widget.handleEvent(.{ .key = input.KeyEvent.init(input.KeyCode.END, .{}) }));
    try std.testing.expect(!try list.widget.handleEvent(.{ .key = input.KeyEvent.init(input.KeyCode.PAGE_DOWN, .{}) }));
    try std.testing.expect(!list.widget.dirty);
    try std.testing.expectEqual(@as(usize, 2), list.selected_index);
}

test "list unchanged selection still consumes keyboard when visibility changes" {
    const alloc = std.testing.allocator;
    var list = try List.init(alloc);
    defer list.deinit();

    try list.addItem("Alpha");
    try list.addItem("Beta");
    try list.addItem("Gamma");
    list.widget.focused = true;
    try list.widget.layout(layout_module.Rect.init(0, 0, 12, 1));

    list.selected_index = 2;
    list.first_visible_index = 0;
    list.scroll_driver.snap(0);
    list.widget.clearDirty();

    try std.testing.expect(try list.widget.handleEvent(.{ .key = input.KeyEvent.init(input.KeyCode.END, .{}) }));
    try std.testing.expect(list.widget.dirty);
    try std.testing.expectEqual(@as(usize, 2), list.selected_index);
    try std.testing.expectEqual(@as(usize, 2), list.first_visible_index);
}

test "list clamps stale selection before typeahead and activation" {
    const alloc = std.testing.allocator;
    var list = try List.init(alloc);
    defer list.deinit();

    try list.addItem("Alpha");
    try list.addItem("Beta");
    list.widget.focused = true;
    try list.widget.layout(layout_module.Rect.init(0, 0, 12, 2));
    list.selected_index = std.math.maxInt(usize);

    try std.testing.expect(try list.widget.handleEvent(.{ .key = .{ .key = 'b', .modifiers = .{} } }));
    try std.testing.expectEqual(@as(usize, 1), list.selected_index);

    test_list_activated_index = null;
    list.setOnItemActivate(recordListActivation);
    list.selected_index = std.math.maxInt(usize);
    try std.testing.expect(try list.widget.handleEvent(.{ .key = .{ .key = input.KeyCode.ENTER, .modifiers = .{} } }));
    try std.testing.expectEqual(@as(?usize, 1), test_list_activated_index);
}

test "list selected item clamps stale state" {
    const alloc = std.testing.allocator;
    var list = try List.init(alloc);
    defer list.deinit();

    try list.addItem("Alpha");
    try list.addItem("Beta");
    list.selected_index = std.math.maxInt(usize);

    try std.testing.expectEqualStrings("Beta", list.getSelectedItem().?);
    try std.testing.expectEqual(@as(usize, 1), list.selected_index);
}

test "list clears selection and ignores events when empty" {
    const alloc = std.testing.allocator;
    var list = try List.init(alloc);
    defer list.deinit();

    try list.addItem("one");
    try list.addItem("two");
    list.setSelectedIndex(1);
    list.clear();

    try std.testing.expectEqual(@as(usize, 0), list.selected_index);

    try list.widget.layout(layout_module.Rect.init(0, 0, 8, 3));
    const handled = try list.widget.handleEvent(.{ .key = .{ .key = input.KeyCode.DOWN, .modifiers = .{} } });
    try std.testing.expectEqual(false, handled);
}

test "list remove before selection preserves selected item" {
    const alloc = std.testing.allocator;
    var list = try List.init(alloc);
    defer list.deinit();

    try list.addItem("Alpha");
    try list.addItem("Beta");
    try list.addItem("Gamma");
    list.setSelectedIndex(2);

    list.removeItem(0);
    try std.testing.expectEqual(@as(usize, 1), list.selected_index);
    try std.testing.expectEqualStrings("Gamma", list.getSelectedItem().?);
}

test "list remove selected last item clamps selection" {
    const alloc = std.testing.allocator;
    var list = try List.init(alloc);
    defer list.deinit();

    try list.addItem("Alpha");
    try list.addItem("Beta");
    list.setSelectedIndex(1);

    list.removeItem(1);
    try std.testing.expectEqual(@as(usize, 0), list.selected_index);
    try std.testing.expectEqualStrings("Alpha", list.getSelectedItem().?);
}

test "list remove above viewport preserves visible item" {
    const alloc = std.testing.allocator;
    var list = try List.init(alloc);
    defer list.deinit();

    try list.addItem("Zero");
    try list.addItem("One");
    try list.addItem("Two");
    try list.addItem("Three");
    try list.addItem("Four");

    try list.widget.layout(layout_module.Rect.init(0, 0, 12, 2));
    list.setSelectedIndex(3);
    try std.testing.expectEqual(@as(usize, 2), list.first_visible_index);
    try std.testing.expectEqualStrings("Two", list.itemAt(list.first_visible_index));

    list.removeItem(0);
    try std.testing.expectEqual(@as(usize, 1), list.first_visible_index);
    try std.testing.expectEqualStrings("Two", list.itemAt(list.first_visible_index));
    try std.testing.expectEqual(@as(usize, 2), list.selected_index);
    try std.testing.expectEqualStrings("Three", list.getSelectedItem().?);
}

test "list border draws around content without consuming first row" {
    const alloc = std.testing.allocator;
    var list = try List.init(alloc);
    defer list.deinit();

    list.setBorder(.rounded);
    try list.addItem("alpha");
    try list.addItem("beta");

    try list.widget.layout(layout_module.Rect.init(0, 0, 10, 4));

    var renderer = try render.Renderer.init(alloc, 10, 4);
    defer renderer.deinit();
    try list.widget.draw(&renderer);

    try std.testing.expectEqual(@as(u21, '╭'), renderer.back.getCell(0, 0).*.codepoint());
    try std.testing.expectEqual(@as(u21, '╯'), renderer.back.getCell(9, 3).*.codepoint());
    try std.testing.expectEqual(@as(u21, 'a'), renderer.back.getCell(1, 1).*.codepoint());
    try std.testing.expectEqual(@as(usize, 2), list.visible_items_count);
}

test "list clamps bordered edge draw coordinates" {
    const alloc = std.testing.allocator;
    var list = try List.init(alloc);
    defer list.deinit();

    list.setBorder(.rounded);
    try list.addItem("alpha");
    try list.addItem("beta");
    list.drag_hover_index = 1;

    try list.widget.layout(layout_module.Rect.init(std.math.maxInt(u16), std.math.maxInt(u16), 4, 4));

    var renderer = try render.Renderer.init(alloc, 2, 2);
    defer renderer.deinit();
    try list.widget.draw(&renderer);

    try std.testing.expectEqual(std.math.maxInt(u16), list.contentRect().x);
    try std.testing.expectEqual(std.math.maxInt(u16), list.contentRect().y);
    try std.testing.expectEqual(@as(usize, 2), list.visible_items_count);
}

test "list preferred size saturates long rows and huge virtual counts" {
    const alloc = std.testing.allocator;
    var list = try List.init(alloc);
    defer list.deinit();

    const long = try alloc.alloc(u8, @as(usize, std.math.maxInt(u16)) + 128);
    defer alloc.free(long);
    @memset(long, 'x');

    try list.addItem(long);
    list.setBorder(.rounded);

    const stored_size = try list.widget.getPreferredSize();
    try std.testing.expectEqual(@as(u16, std.math.maxInt(u16)), stored_size.width);
    try std.testing.expectEqual(@as(u16, 3), stored_size.height);

    const Provider = struct {
        fn count(_: ?*anyopaque) usize {
            return std.math.maxInt(usize);
        }

        fn itemAt(_: usize, _: ?*anyopaque) []const u8 {
            return "virtual";
        }
    };

    list.virtual_sample_limit = 1;
    list.useItemProvider(.{
        .ctx = null,
        .count = Provider.count,
        .item_at = Provider.itemAt,
    });

    const virtual_size = try list.widget.getPreferredSize();
    try std.testing.expectEqual(@as(u16, 12), virtual_size.height);
}

test "list drag reorder updates item order and selection" {
    const alloc = std.testing.allocator;
    var list = try List.init(alloc);
    defer list.deinit();

    list.setReorderable(true);
    try list.addItem("a");
    try list.addItem("b");
    try list.addItem("c");

    try list.widget.layout(layout_module.Rect.init(0, 0, 4, 3));

    _ = try list.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 0, 0, 1, 0) });
    _ = try list.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.move, 0, 2, 1, 0) });
    _ = try list.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.release, 0, 2, 1, 0) });

    try std.testing.expectEqualStrings("b", list.items.items[0]);
    try std.testing.expectEqualStrings("a", list.items.items[1]);
    try std.testing.expectEqualStrings("c", list.items.items[2]);
    try std.testing.expectEqual(@as(usize, 1), list.selected_index);
    try std.testing.expect(!list.dragging);
    try std.testing.expectEqual(@as(?usize, null), list.drag_hover_index);
}

test "list drag reorder accepts edge row coordinates above i16 max" {
    const alloc = std.testing.allocator;
    var list = try List.init(alloc);
    defer list.deinit();

    list.setReorderable(true);
    try list.addItem("a");
    try list.addItem("b");
    try list.addItem("c");

    try list.widget.layout(layout_module.Rect.init(0, std.math.maxInt(u16) - 2, 4, 3));

    _ = try list.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 0, std.math.maxInt(u16) - 2, 1, 0) });
    try std.testing.expect(list.dragging);

    _ = try list.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.move, 0, std.math.maxInt(u16), 1, 0) });
    try std.testing.expectEqual(@as(?usize, 2), list.drag_hover_index);

    _ = try list.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.release, 0, std.math.maxInt(u16), 1, 0) });
    try std.testing.expectEqualStrings("b", list.items.items[0]);
    try std.testing.expectEqualStrings("a", list.items.items[1]);
    try std.testing.expectEqualStrings("c", list.items.items[2]);
    try std.testing.expect(!list.dragging);
    try std.testing.expectEqual(@as(?usize, null), list.drag_hover_index);
}

test "list starting a new drag cancels previous source state" {
    const alloc = std.testing.allocator;
    var first = try List.init(alloc);
    defer first.deinit();
    var second = try List.init(alloc);
    defer second.deinit();

    first.setReorderable(true);
    second.setReorderable(true);
    try first.addItem("first");
    try second.addItem("second");

    try first.widget.layout(layout_module.Rect.init(0, 0, 8, 1));
    try second.widget.layout(layout_module.Rect.init(0, 2, 8, 1));

    _ = try first.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 0, 0, 1, 0) });
    try std.testing.expect(first.dragging);
    try std.testing.expect(first.drag_payload != null);
    try std.testing.expect(active_drag != null);
    try std.testing.expectEqual(first, active_drag.?.source);

    _ = try second.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 0, 2, 1, 0) });
    try std.testing.expect(!first.dragging);
    try std.testing.expectEqual(@as(?usize, null), first.drag_start_index);
    try std.testing.expectEqual(@as(?usize, null), first.drag_hover_index);
    try std.testing.expect(first.drag_payload == null);
    try std.testing.expect(second.dragging);
    try std.testing.expect(active_drag != null);
    try std.testing.expectEqual(second, active_drag.?.source);
}

test "list clear cancels active drag state" {
    const alloc = std.testing.allocator;
    var list = try List.init(alloc);
    defer list.deinit();

    list.setReorderable(true);
    try list.addItem("alpha");
    try list.addItem("beta");
    try list.widget.layout(layout_module.Rect.init(0, 0, 8, 2));

    _ = try list.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 0, 0, 1, 0) });
    try std.testing.expect(list.dragging);
    try std.testing.expect(active_drag != null);

    list.clear();
    try std.testing.expect(!list.dragging);
    try std.testing.expectEqual(@as(?usize, null), list.drag_start_index);
    try std.testing.expectEqual(@as(?usize, null), list.drag_hover_index);
    try std.testing.expect(list.drag_payload == null);
    try std.testing.expect(active_drag == null);
    try std.testing.expectEqual(@as(usize, 0), list.items.items.len);
}

test "list reorder in place moves items without changing capacity" {
    const alloc = std.testing.allocator;
    var list = try List.init(alloc);
    defer list.deinit();

    try list.addItem("a");
    try list.addItem("b");
    try list.addItem("c");
    try list.addItem("d");
    const capacity = list.items.capacity;

    list.reorderInPlace(0, 3);
    try std.testing.expectEqual(capacity, list.items.capacity);
    try std.testing.expectEqualStrings("b", list.items.items[0]);
    try std.testing.expectEqualStrings("c", list.items.items[1]);
    try std.testing.expectEqualStrings("a", list.items.items[2]);
    try std.testing.expectEqualStrings("d", list.items.items[3]);
    try std.testing.expectEqual(@as(usize, 2), list.selected_index);

    list.reorderInPlace(3, 0);
    try std.testing.expectEqual(capacity, list.items.capacity);
    try std.testing.expectEqualStrings("d", list.items.items[0]);
    try std.testing.expectEqualStrings("b", list.items.items[1]);
    try std.testing.expectEqualStrings("c", list.items.items[2]);
    try std.testing.expectEqualStrings("a", list.items.items[3]);
    try std.testing.expectEqual(@as(usize, 0), list.selected_index);
}

test "list accepts cross-list drops and moves items" {
    const alloc = std.testing.allocator;
    var source = try List.init(alloc);
    defer source.deinit();
    var target = try List.init(alloc);
    defer target.deinit();

    source.setReorderable(true);
    try source.addItem("alpha");
    try source.addItem("beta");
    try target.addItem("one");

    try source.widget.layout(layout_module.Rect.init(0, 0, 8, 2));
    try target.widget.layout(layout_module.Rect.init(0, 4, 8, 4));

    _ = try source.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 0, 0, 1, 0) });
    _ = try target.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.release, 0, 4, 1, 0) });
    _ = try source.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.release, 0, 10, 1, 0) });

    try std.testing.expectEqual(@as(usize, 1), source.items.items.len);
    try std.testing.expectEqualStrings("beta", source.items.items[0]);
    try std.testing.expectEqual(@as(usize, 2), target.items.items.len);
    try std.testing.expectEqualStrings("alpha", target.items.items[0]);
    try std.testing.expectEqualStrings("one", target.items.items[1]);
    try std.testing.expect(!source.dragging);
}

test "list copy drop finishes source drag state" {
    const alloc = std.testing.allocator;
    var source = try List.init(alloc);
    defer source.deinit();
    var target = try List.init(alloc);
    defer target.deinit();

    source.setReorderable(true);
    target.setCrossDropMode(.copy);
    try source.addItem("alpha");
    try source.addItem("beta");
    try target.addItem("one");

    try source.widget.layout(layout_module.Rect.init(0, 0, 8, 2));
    try target.widget.layout(layout_module.Rect.init(0, 4, 8, 4));

    _ = try source.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 0, 0, 1, 0) });
    try std.testing.expect(source.dragging);
    try std.testing.expect(source.drag_payload != null);

    _ = try target.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.release, 0, 4, 1, 0) });

    try std.testing.expectEqual(@as(usize, 2), source.items.items.len);
    try std.testing.expectEqualStrings("alpha", source.items.items[0]);
    try std.testing.expectEqualStrings("beta", source.items.items[1]);
    try std.testing.expectEqual(@as(usize, 2), target.items.items.len);
    try std.testing.expectEqualStrings("alpha", target.items.items[0]);
    try std.testing.expectEqualStrings("one", target.items.items[1]);
    try std.testing.expect(!source.dragging);
    try std.testing.expectEqual(@as(?usize, null), source.drag_start_index);
    try std.testing.expectEqual(@as(?usize, null), source.drag_hover_index);
    try std.testing.expect(source.drag_payload == null);
    try std.testing.expect(active_drag == null);
}

test "list external drop reports allocation failure without changing lists" {
    const alloc = std.testing.allocator;
    var source = try List.init(alloc);
    defer source.deinit();
    var target = try List.init(alloc);
    defer target.deinit();

    try source.addItem("alpha");
    try source.addItem("beta");
    try target.addItem("one");

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = target.allocator;
    target.allocator = failing.allocator();
    defer target.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, target.acceptExternalDrop(.{
        .source = source,
        .from_index = 0,
        .text = source.items.items[0],
    }, 0));

    try std.testing.expectEqual(@as(usize, 2), source.items.items.len);
    try std.testing.expectEqualStrings("alpha", source.items.items[0]);
    try std.testing.expectEqualStrings("beta", source.items.items[1]);
    try std.testing.expectEqual(@as(usize, 1), target.items.items.len);
    try std.testing.expectEqualStrings("one", target.items.items[0]);
}

test "list virtual provider samples preferred size within limit" {
    const alloc = std.testing.allocator;
    var list = try List.init(alloc);
    defer list.deinit();

    const Provider = struct {
        items: []const []const u8,
        calls: usize = 0,
        max_index: usize = 0,

        fn count(ctx: ?*anyopaque) usize {
            const self = @as(*@This(), @ptrCast(@alignCast(ctx.?)));
            return self.items.len;
        }

        fn itemAt(index: usize, ctx: ?*anyopaque) []const u8 {
            const self = @as(*@This(), @ptrCast(@alignCast(ctx.?)));
            self.calls += 1;
            self.max_index = @max(self.max_index, index);
            return self.items[index];
        }
    };

    var provider_ctx = Provider{
        .items = &.{ "tiny", "longerword12", "mid", "extraextraextra" },
    };

    list.virtual_sample_limit = 2;
    list.useItemProvider(.{
        .ctx = &provider_ctx,
        .count = Provider.count,
        .item_at = Provider.itemAt,
    });

    const size = try List.getPreferredSizeFn(@ptrCast(@alignCast(&list.widget)));
    try std.testing.expectEqual(@as(u16, 12), size.width);
    try std.testing.expectEqual(@as(usize, 2), provider_ctx.calls);
    try std.testing.expectEqual(@as(usize, 1), provider_ctx.max_index);
}

test "list keeps selected item visible after layout" {
    const alloc = std.testing.allocator;
    var list = try List.init(alloc);
    defer list.deinit();

    try list.addItem("one");
    try list.addItem("two");
    try list.addItem("three");
    try list.addItem("four");
    try list.addItem("five");

    try list.widget.layout(layout_module.Rect.init(0, 0, 8, 2));
    list.setSelectedIndex(4);

    try std.testing.expectEqual(@as(usize, 4), list.selected_index);
    try std.testing.expectEqual(@as(usize, 3), list.first_visible_index);
}

test "list normalizes non-finite scroll targets" {
    const alloc = std.testing.allocator;
    var list = try List.init(alloc);
    defer list.deinit();

    try list.addItem("one");
    try list.addItem("two");
    try list.addItem("three");
    try list.addItem("four");
    try list.addItem("five");

    list.visible_items_count = 2;
    list.scrollTo(std.math.inf(f32));
    try std.testing.expectEqual(@as(usize, 3), list.first_visible_index);
    try std.testing.expectEqual(@as(f32, 3), list.scroll_driver.current);

    list.scrollTo(std.math.nan(f32));
    try std.testing.expectEqual(@as(usize, 0), list.first_visible_index);
    try std.testing.expectEqual(@as(f32, 0), list.scroll_driver.current);
}

test "list draws after non-finite scroll driver state" {
    const alloc = std.testing.allocator;
    var list = try List.init(alloc);
    defer list.deinit();

    try list.addItem("one");
    try list.addItem("two");
    try list.addItem("three");
    try list.addItem("four");
    try list.addItem("five");

    try list.widget.layout(layout_module.Rect.init(0, 0, 8, 2));
    var renderer = try render.Renderer.init(alloc, 8, 2);
    defer renderer.deinit();

    list.first_visible_index = std.math.maxInt(usize);
    list.scroll_driver.current = std.math.nan(f32);
    try list.widget.draw(&renderer);
    try std.testing.expectEqual(@as(usize, 0), list.first_visible_index);
    try std.testing.expectEqual(@as(f32, 0), list.scroll_driver.current);

    list.scroll_driver.current = std.math.inf(f32);
    list.widget.markDirty();
    try list.widget.draw(&renderer);
    try std.testing.expectEqual(@as(usize, 3), list.first_visible_index);
    try std.testing.expectEqual(@as(f32, 3), list.scroll_driver.current);
}
