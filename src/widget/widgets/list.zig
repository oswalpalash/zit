const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const animation = @import("../animation.zig");
const event_module = @import("../../event/event.zig");

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
    clock: *const fn () i64 = std.time.milliTimestamp,
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

    /// Initialize a new list
    pub fn init(allocator: std.mem.Allocator) !*List {
        const self = try allocator.create(List);

        self.* = List{
            .widget = base.Widget.init(&vtable),
            .items = std.ArrayList([]const u8).empty,
            .allocator = allocator,
        };
        self.item_provider = null;
        self.scroll_driver.snap(0);

        return self;
    }

    /// Clean up list resources
    pub fn deinit(self: *List) void {
        self.clearDragPayload();
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
    }

    /// Remove an item from the list
    pub fn removeItem(self: *List, index: usize) void {
        if (self.item_provider != null) return;
        if (index >= self.items.items.len) {
            return;
        }

        // Free the item
        self.allocator.free(self.items.items[index]);

        // Remove the item
        _ = self.items.orderedRemove(index);

        // Update selected index if needed
        if (self.selected_index >= self.items.items.len) {
            self.setSelectedIndex(if (self.items.items.len > 0) self.items.items.len - 1 else 0);
        }
    }

    /// Clear all items from the list
    pub fn clear(self: *List) void {
        self.clearDragPayload();
        // Free all items
        for (self.items.items) |item| {
            self.allocator.free(item);
        }
        self.items.clearRetainingCapacity();
        self.setSelectedIndex(0);
        self.resetTypeahead();
    }

    /// Set the selected item
    pub fn setSelectedIndex(self: *List, index: usize) void {
        const count = self.itemCount();
        if (count == 0) {
            self.selected_index = 0;
            return;
        }

        if (index == self.selected_index) {
            return;
        }

        const old_index = self.selected_index;
        self.selected_index = @min(index, count - 1);

        // Ensure the selected item is visible
        self.ensureItemVisible(self.selected_index);

        // Call the selection changed callback
        if (old_index != self.selected_index and self.on_select != null) {
            self.on_select.?(self.selected_index, self.getSelectedItem() orelse "");
        }
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
        self.fg = fg;
        self.bg = bg;
        self.selected_fg = selected_fg;
        self.selected_bg = selected_bg;
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
        self.border = border;
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
    }

    /// Return to the owned item storage model.
    pub fn clearItemProvider(self: *List) void {
        self.item_provider = null;
        self.syncScrollFromDriver();
    }

    /// Enable or disable drag-to-reorder behavior.
    pub fn setReorderable(self: *List, enabled: bool) void {
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

    fn clampScroll(self: *List) void {
        const max_offset = if (self.visible_items_count > 0 and self.itemCount() > self.visible_items_count)
            self.itemCount() - self.visible_items_count
        else
            0;
        const clamped = std.math.clamp(self.scroll_driver.current, 0, @as(f32, @floatFromInt(max_offset)));
        self.scroll_driver.current = clamped;
        self.first_visible_index = @as(usize, @intFromFloat(std.math.floor(clamped)));
    }

    fn syncScrollFromDriver(self: *List) void {
        self.first_visible_index = @as(usize, @intFromFloat(std.math.floor(self.scroll_driver.current)));
    }

    fn scrollTo(self: *List, target: f32) void {
        const max_offset = if (self.visible_items_count > 0 and self.itemCount() > self.visible_items_count)
            self.itemCount() - self.visible_items_count
        else
            0;
        const clamped = std.math.clamp(target, 0, @as(f32, @floatFromInt(max_offset)));
        if (self.animator) |anim| {
            const onChange = struct {
                fn apply(value: f32, ctx: ?*anyopaque) void {
                    const list = @as(*List, @ptrCast(@alignCast(ctx.?)));
                    list.scroll_driver.current = value;
                    list.syncScrollFromDriver();
                }
            }.apply;

            _ = self.scroll_driver.animate(
                anim,
                self.scroll_driver.current,
                clamped,
                self.scroll_duration_ms,
                animation.Easing.easeInOutQuad,
                onChange,
                @ptrCast(self),
            ) catch {
                self.scroll_driver.snap(clamped);
                self.syncScrollFromDriver();
            };
        } else {
            self.scroll_driver.snap(clamped);
            self.syncScrollFromDriver();
        }
    }

    fn scrollBy(self: *List, delta: f32) void {
        self.scrollTo(self.scroll_driver.current + delta * self.momentum_multiplier);
    }

    fn startDrag(self: *List, index: usize) void {
        if (!self.enable_reorder) return;
        if (active_drag) |_|
            active_drag = null;

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

        self.items.insert(self.allocator, to, moved) catch {
            // Try to restore original ordering if insert fails.
            _ = self.items.insert(self.allocator, from, moved) catch {};
            return;
        };

        self.setSelectedIndex(to);
        if (self.on_reorder) |cb| cb(from, to, self, self);
        active_drag = null;
    }

    fn acceptExternalDrop(self: *List, drag: ActiveDrag, drop_index: usize) void {
        if (!self.accept_external_drops) return;

        if (self.item_provider == null) {
            const target_idx = @min(drop_index, self.itemCount());
            const copy = self.allocator.dupe(u8, drag.text) catch return;
            self.items.insert(self.allocator, target_idx, copy) catch {
                self.allocator.free(copy);
                return;
            };
            if (self.cross_drop_mode == .move and drag.source.item_provider == null) {
                drag.source.removeItem(drag.from_index);
            }
            self.setSelectedIndex(target_idx);
        }

        if (self.on_reorder) |cb| {
            cb(drag.from_index, drop_index, drag.source, self);
        }

        active_drag = null;
    }

    /// Draw implementation for List
    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = fromWidgetPtr(widget_ptr);

        if (!self.widget.visible) {
            return;
        }

        const rect = self.widget.rect;

        // Fill list background
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', self.fg, self.bg, render.Style{});

        // Calculate visible items
        self.visible_items_count = @intCast(@as(usize, rect.height));
        if (self.visible_items_count == 0 or rect.height == 0 or rect.width == 0) {
            return;
        }

        self.clampScroll();

        // Ensure the first visible index is valid
        const total_items = self.itemCount();
        if (self.first_visible_index + self.visible_items_count > total_items) {
            self.first_visible_index = if (total_items > self.visible_items_count)
                total_items - self.visible_items_count
            else
                0;
            self.scroll_driver.snap(@floatFromInt(self.first_visible_index));
        }

        // Draw visible items
        const last_visible_index = @min(self.first_visible_index + self.visible_items_count, total_items);

        var y = rect.y;
        var i = self.first_visible_index;
        while (i < last_visible_index) : (i += 1) {
            const item = self.itemAt(i);
            const is_selected = i == self.selected_index;

            // Choose colors based on selection and focus state
            const item_fg = if (is_selected)
                (if (self.widget.focused) self.focused_fg else self.selected_fg)
            else
                self.fg;

            const item_bg = if (is_selected)
                (if (self.widget.focused) self.focused_bg else self.selected_bg)
            else
                self.bg;

            // Draw item background
            renderer.fillRect(rect.x, y, rect.width, 1, ' ', item_fg, item_bg, render.Style{});

            // Draw item text
            var x = rect.x;
            for (item) |char| {
                if (x - rect.x >= rect.width) {
                    break;
                }

                renderer.drawChar(x, y, char, item_fg, item_bg, render.Style{});
                x += 1;
            }

            y += 1;
        }

        // Draw drop preview indicator for reorder/drops
        if (self.drag_hover_index) |hover| {
            const clamped_hover = @min(hover, total_items);
            const indicator_y: u16 = rect.y + @as(u16, @intCast(clamped_hover - self.first_visible_index));
            if (indicator_y >= rect.y and indicator_y < rect.y + rect.height) {
                const state = if (active_drag != null and active_drag.?.source != self)
                    event_module.DropVisuals.State.valid
                else
                    event_module.DropVisuals.State.idle;
                const colors = event_module.DropVisuals.Colors{
                    .border = self.fg,
                    .fill = self.bg,
                    .valid = render.Color{ .named_color = render.NamedColor.green },
                    .invalid = render.Color{ .named_color = render.NamedColor.red },
                    .text = self.fg,
                };
                event_module.DropVisuals.outline(renderer, layout_module.Rect{
                    .x = rect.x,
                    .y = indicator_y,
                    .width = rect.width,
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
            const inside = rect.contains(mouse_event.x, mouse_event.y);

            // External drag hover/drop
            if (active_drag) |drag| {
                if (inside and self.accept_external_drops and (drag.source != self or self.enable_reorder)) {
                    const rel_y: i16 = @as(i16, @intCast(mouse_event.y)) - @as(i16, @intCast(rect.y));
                    const drop_index = self.first_visible_index + @as(usize, @intCast(std.math.clamp(rel_y, 0, @as(i16, @intCast(rect.height)))));
                    self.drag_hover_index = @min(drop_index, total_items);

                    if (mouse_event.action == .release) {
                        if (drag.source == self) {
                            if (self.drag_start_index) |start_idx| {
                                self.reorderInPlace(start_idx, self.drag_hover_index.?);
                            }
                        } else {
                            self.acceptExternalDrop(drag, self.drag_hover_index.?);
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
                // Convert y position to item index
                const item_index = self.first_visible_index + @as(usize, @intCast(mouse_event.y - rect.y));

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

                // Mouse wheel scrolls list
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

                // Drag updates
                if (mouse_event.action == .move and self.dragging) {
                    const rel_y: i16 = @as(i16, @intCast(mouse_event.y)) - @as(i16, @intCast(rect.y));
                    const drop_index = self.first_visible_index + @as(usize, @intCast(std.math.clamp(rel_y, 0, @as(i16, @intCast(rect.height)))));
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
            const profiles = [_]input.KeybindingProfile{
                input.KeybindingProfile.commonEditing(),
                input.KeybindingProfile.emacs(),
                input.KeybindingProfile.vi(),
            };

            if (input.editorActionForEvent(key_event, &profiles)) |action| {
                switch (action) {
                    .cursor_down => {
                        if (self.selected_index + 1 < total_items) {
                            self.setSelectedIndex(self.selected_index + 1);
                        }
                        self.resetTypeahead();
                        return true;
                    },
                    .cursor_up => {
                        if (self.selected_index > 0) {
                            self.setSelectedIndex(self.selected_index - 1);
                        }
                        self.resetTypeahead();
                        return true;
                    },
                    .page_down => {
                        const new_index = @min(self.selected_index + self.visible_items_count, total_items - 1);
                        self.setSelectedIndex(new_index);
                        self.resetTypeahead();
                        return true;
                    },
                    .page_up => {
                        const new_index = if (self.selected_index > self.visible_items_count)
                            self.selected_index - self.visible_items_count
                        else
                            0;
                        self.setSelectedIndex(new_index);
                        self.resetTypeahead();
                        return true;
                    },
                    .line_start => {
                        self.setSelectedIndex(0);
                        self.resetTypeahead();
                        return true;
                    },
                    .line_end => {
                        self.setSelectedIndex(total_items - 1);
                        self.resetTypeahead();
                        return true;
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
        self.visible_items_count = @intCast(@as(usize, rect.height));

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
            max_width = @max(max_width, @as(u16, @intCast(self.itemAt(i).len)));
        }

        // Preferred height depends on number of items, with a minimum of 1
        const preferred_height = @as(u16, @intCast(@max(1, @min(10, @as(i16, @intCast(total))))));

        return layout_module.Size.init(max_width, preferred_height);
    }

    /// Can focus implementation for List
    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = fromWidgetPtr(widget_ptr);
        return self.widget.enabled and self.itemCount() > 0;
    }
};

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
