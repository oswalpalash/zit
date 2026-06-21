const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const theme = @import("../theme.zig");
const accessibility = @import("../accessibility.zig");

/// Item entry for context menus.
pub const MenuItem = struct {
    label: []const u8,
    enabled: bool = true,
    data: ?*anyopaque = null,
};

/// Lightweight context menu that can be opened at an arbitrary position.
pub const ContextMenu = struct {
    widget: base.Widget,
    allocator: std.mem.Allocator,
    items: std.ArrayList(MenuItem),
    theme_value: theme.Theme,
    open: bool = false,
    selected: usize = 0,
    max_visible: usize = 8,
    on_select: ?*const fn (usize, MenuItem) void = null,
    on_select_with_ctx: ?*const fn (usize, MenuItem, ?*anyopaque) void = null,
    on_select_ctx: ?*anyopaque = null,

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator) !*ContextMenu {
        const self = try allocator.create(ContextMenu);
        errdefer allocator.destroy(self);

        var items = try std.ArrayList(MenuItem).initCapacity(allocator, 0);
        errdefer items.deinit(allocator);

        self.* = ContextMenu{
            .widget = base.Widget.init(&vtable),
            .allocator = allocator,
            .items = items,
            .theme_value = theme.Theme.dark(),
        };
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.menu), "Context menu", "");
        return self;
    }

    pub fn deinit(self: *ContextMenu) void {
        self.clear();
        self.items.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn addItem(self: *ContextMenu, label: []const u8, enabled: bool, data: ?*anyopaque) !void {
        try self.items.ensureUnusedCapacity(self.allocator, 1);
        const copy = try self.allocator.dupe(u8, label);
        self.items.appendAssumeCapacity(.{ .label = copy, .enabled = enabled, .data = data });
        self.widget.markDirty();
    }

    pub fn clear(self: *ContextMenu) void {
        const previous_height = self.widget.rect.height;
        const changed = self.items.items.len != 0 or self.selected != 0;
        for (self.items.items) |item| {
            self.allocator.free(item.label);
        }
        self.items.clearRetainingCapacity();
        self.selected = 0;
        if (self.open) self.widget.rect.height = self.computedHeight();
        if (changed or (self.open and previous_height != self.widget.rect.height)) self.widget.markDirty();
    }

    pub fn setTheme(self: *ContextMenu, t: theme.Theme) !void {
        self.theme_value = t;
        self.widget.markDirty();
    }

    pub fn setOnSelect(self: *ContextMenu, callback: *const fn (usize, MenuItem) void) void {
        self.on_select = callback;
        self.on_select_with_ctx = null;
        self.on_select_ctx = null;
    }

    pub fn setOnSelectWithContext(self: *ContextMenu, callback: *const fn (usize, MenuItem, ?*anyopaque) void, ctx: ?*anyopaque) void {
        self.on_select_with_ctx = callback;
        self.on_select_ctx = ctx;
        self.on_select = null;
    }

    pub fn setMaxVisible(self: *ContextMenu, count: usize) void {
        const next = @max(@as(usize, 1), count);
        const previous_height = self.widget.rect.height;
        const previous_selected = self.selected;
        const changed = self.max_visible != next;
        self.max_visible = next;
        _ = self.clampSelection();
        if (self.open) self.widget.rect.height = self.computedHeight();
        if (changed or previous_selected != self.selected or (self.open and previous_height != self.widget.rect.height)) self.widget.markDirty();
    }

    pub fn openAt(self: *ContextMenu, x: u16, y: u16) void {
        const previous_rect = self.widget.rect;
        const was_open = self.open;
        const previous_selected = self.selected;
        self.open = true;
        self.selected = 0;
        self.widget.rect.x = x;
        self.widget.rect.y = y;
        self.widget.rect.height = self.computedHeight();
        const changed = !was_open or
            previous_selected != self.selected or
            previous_rect.x != self.widget.rect.x or
            previous_rect.y != self.widget.rect.y or
            previous_rect.height != self.widget.rect.height;
        if (changed) self.widget.markDirty();
    }

    pub fn close(self: *ContextMenu) void {
        if (!self.open) return;
        self.open = false;
        self.widget.markDirty();
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *ContextMenu = @fieldParentPtr("widget", widget_ref);
        if (!self.open or !self.widget.visible) return;
        const rect = self.widget.rect;
        if (rect.width == 0 or rect.height == 0) return;

        const fg = self.theme_value.color(.text);
        const bg = self.theme_value.color(.surface);
        const highlight_fg = self.theme_value.color(.background);
        const highlight_bg = self.theme_value.color(.accent);
        const disabled = self.theme_value.color(.muted);

        const visible_rows: usize = @intCast(@min(self.items.items.len, self.max_visible));
        if (visible_rows == 0) return;

        renderer.drawBox(rect.x, rect.y, rect.width, rect.height, render.BorderStyle.single, fg, bg, render.Style{});
        if (rect.width <= 2 or rect.height <= 2) return;

        const right = rectRight(rect);
        const bottom = rectBottom(rect);
        const inner_x = u16Coord(@as(u32, rect.x) + 1) orelse return;
        const inner_y = u16Coord(@as(u32, rect.y) + 1) orelse return;
        renderer.fillRect(inner_x, inner_y, rect.width - 2, rect.height - 2, ' ', fg, bg, render.Style{});

        var row: usize = 0;
        const drawable_rows = @min(visible_rows, @as(usize, rect.height - 2));
        while (row < drawable_rows) : (row += 1) {
            const item_y_u32 = @as(u32, rect.y) + 1 + @as(u32, @intCast(row));
            if (item_y_u32 + 1 >= bottom) break;
            const item_y = u16Coord(item_y_u32) orelse break;
            const idx = row;
            const item = self.items.items[idx];
            const is_selected = idx == self.selected;
            const row_fg = if (!item.enabled) disabled else if (is_selected) highlight_fg else fg;
            const row_bg = if (is_selected) highlight_bg else bg;
            renderer.fillRect(inner_x, item_y, rect.width - 2, 1, ' ', row_fg, row_bg, render.Style{});
            const text_x_u32 = @as(u32, rect.x) + 2;
            if (text_x_u32 < right) {
                if (u16Coord(text_x_u32)) |text_x| {
                    renderer.drawSmartStr(text_x, item_y, item.label, row_fg, row_bg, render.Style{ .bold = is_selected });
                }
            }
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *ContextMenu = @fieldParentPtr("widget", widget_ref);
        if (!self.open or !self.widget.enabled) return false;

        switch (event) {
            .key => |key_event| {
                if (!self.widget.focused) return false;
                const selection_was_clamped = self.clampSelection();
                if (selection_was_clamped) self.widget.markDirty();
                switch (key_event.key) {
                    input.KeyCode.UP => {
                        const changed = if (self.selected > 0) self.setSelectedVisibleIndex(self.selected - 1) else false;
                        return changed or selection_was_clamped;
                    },
                    input.KeyCode.DOWN => {
                        const changed = self.setSelectedVisibleIndex(self.selected + 1);
                        return changed or selection_was_clamped;
                    },
                    input.KeyCode.ENTER, input.KeyCode.SPACE => {
                        return self.activateSelected();
                    },
                    input.KeyCode.ESCAPE => {
                        self.close();
                        return true;
                    },
                    else => {},
                }
            },
            .mouse => |mouse_event| {
                const rect = self.widget.rect;
                const mouse_x: u32 = mouse_event.x;
                const mouse_y: u32 = mouse_event.y;
                const right = rectRight(rect);
                const bottom = rectBottom(rect);
                const inside_x = mouse_x >= rect.x and mouse_x < right;
                const inside_y = mouse_y >= rect.y and mouse_y < bottom;
                if (inside_x and inside_y) {
                    const inner_top: u32 = @as(u32, rect.y) + 1;
                    const inner_bottom: u32 = if (bottom > 0) bottom - 1 else 0;
                    if (mouse_y >= inner_top and mouse_y < inner_bottom) {
                        const idx: usize = @intCast(mouse_y - inner_top);
                        if (idx < self.items.items.len and idx < self.max_visible) {
                            _ = self.setSelectedVisibleIndex(idx);
                            if (mouse_event.action == .press and mouse_event.button == 1) {
                                return self.activateSelected();
                            }
                        }
                    }
                    return true;
                }

                if (mouse_event.action == .press) {
                    self.close();
                }
                return false;
            },
            else => {},
        }

        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *ContextMenu = @fieldParentPtr("widget", widget_ref);
        self.widget.rect = rect;
        if (self.open) self.widget.rect.height = self.computedHeight();
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *ContextMenu = @fieldParentPtr("widget", widget_ref);
        const width = self.preferredWidth();
        const height = self.computedHeight();
        return layout_module.Size.init(width, if (height == 0) 2 else height);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *ContextMenu = @fieldParentPtr("widget", widget_ref);
        return self.widget.enabled and self.open;
    }

    fn preferredWidth(self: *const ContextMenu) u16 {
        var max_len: usize = 4; // padding + border
        for (self.items.items) |item| {
            max_len = @max(max_len, saturatedLenWithPadding(item.label.len, 4));
        }
        return @intCast(@min(max_len, @as(usize, std.math.maxInt(u16))));
    }

    fn computedHeight(self: *const ContextMenu) u16 {
        const visible_rows: usize = @min(self.items.items.len, self.max_visible);
        if (visible_rows == 0) return 0;
        return @intCast(@min(visible_rows +| 2, @as(usize, std.math.maxInt(u16))));
    }

    fn clampSelection(self: *ContextMenu) bool {
        const previous = self.selected;
        const visible_items = @min(self.items.items.len, self.max_visible);
        if (visible_items == 0) {
            self.selected = 0;
        } else if (self.selected >= visible_items) {
            self.selected = visible_items - 1;
        }
        return previous != self.selected;
    }

    fn setSelectedVisibleIndex(self: *ContextMenu, index: usize) bool {
        const visible_items = @min(self.items.items.len, self.max_visible);
        if (index >= visible_items or self.selected == index) return false;
        self.selected = index;
        self.widget.markDirty();
        return true;
    }

    fn activateSelected(self: *ContextMenu) !bool {
        if (self.items.items.len == 0 or self.selected >= self.items.items.len) return false;
        const item = self.items.items[self.selected];
        if (!item.enabled) return false;
        if (self.on_select) |cb| {
            cb(self.selected, item);
        }
        if (self.on_select_with_ctx) |cb| {
            cb(self.selected, item, self.on_select_ctx);
        }
        self.close();
        return true;
    }

    fn rectRight(rect: layout_module.Rect) u32 {
        return @as(u32, rect.x) + @as(u32, rect.width);
    }

    fn rectBottom(rect: layout_module.Rect) u32 {
        return @as(u32, rect.y) + @as(u32, rect.height);
    }

    fn u16Coord(value: u32) ?u16 {
        if (value > std.math.maxInt(u16)) return null;
        return @intCast(value);
    }

    fn saturatedLenWithPadding(len: usize, padding: usize) usize {
        return len +| padding;
    }
};

test "context menu selection via keyboard" {
    const alloc = std.testing.allocator;
    var menu = try ContextMenu.init(alloc);
    defer menu.deinit();
    try menu.addItem("One", true, null);
    try menu.addItem("Two", true, null);

    const pref = try menu.widget.getPreferredSize();
    try menu.widget.layout(layout_module.Rect.init(0, 0, pref.width, pref.height));
    menu.widget.setFocus(true);
    menu.openAt(0, 0);

    var selection: usize = 0;
    const Callbacks = struct {
        fn onSelect(idx: usize, _: MenuItem, ctx: ?*anyopaque) void {
            if (ctx) |ptr| {
                const slot = @as(*usize, @ptrCast(@alignCast(ptr)));
                slot.* = idx;
            }
        }
    };
    menu.setOnSelectWithContext(Callbacks.onSelect, &selection);

    const down = input.Event{ .key = input.KeyEvent.init(input.KeyCode.DOWN, .{}) };
    try std.testing.expect(try menu.widget.handleEvent(down));
    const enter = input.Event{ .key = input.KeyEvent.init(input.KeyCode.ENTER, .{}) };
    try std.testing.expect(try menu.widget.handleEvent(enter));
    try std.testing.expectEqual(@as(usize, 1), selection);
    try std.testing.expect(!menu.open);
}

test "context menu clamps stale selection before keyboard navigation" {
    const alloc = std.testing.allocator;
    var menu = try ContextMenu.init(alloc);
    defer menu.deinit();
    try menu.addItem("One", true, null);
    try menu.addItem("Two", true, null);
    try menu.addItem("Three", true, null);
    menu.setMaxVisible(2);
    menu.openAt(0, 0);
    menu.widget.setFocus(true);
    menu.selected = std.math.maxInt(usize);

    const down = input.Event{ .key = input.KeyEvent.init(input.KeyCode.DOWN, .{}) };
    try std.testing.expect(try menu.widget.handleEvent(down));
    try std.testing.expectEqual(@as(usize, 1), menu.selected);

    const up = input.Event{ .key = input.KeyEvent.init(input.KeyCode.UP, .{}) };
    try std.testing.expect(try menu.widget.handleEvent(up));
    try std.testing.expectEqual(@as(usize, 0), menu.selected);
}

test "context menu ignores saturated keyboard navigation" {
    const alloc = std.testing.allocator;
    var menu = try ContextMenu.init(alloc);
    defer menu.deinit();
    try menu.addItem("One", true, null);
    try menu.addItem("Two", true, null);

    var renderer = try render.Renderer.init(alloc, 16, 4);
    defer renderer.deinit();

    menu.openAt(0, 0);
    try menu.widget.layout(layout_module.Rect.init(0, 0, 16, 4));
    menu.widget.setFocus(true);
    try menu.widget.draw(&renderer);
    try std.testing.expect(!menu.widget.dirty);

    const up = input.Event{ .key = input.KeyEvent.init(input.KeyCode.UP, .{}) };
    try std.testing.expect(!try menu.widget.handleEvent(up));
    try std.testing.expectEqual(@as(usize, 0), menu.selected);
    try std.testing.expect(!menu.widget.dirty);

    const down = input.Event{ .key = input.KeyEvent.init(input.KeyCode.DOWN, .{}) };
    try std.testing.expect(try menu.widget.handleEvent(down));
    try std.testing.expectEqual(@as(usize, 1), menu.selected);
    try std.testing.expect(menu.widget.dirty);
    try menu.widget.draw(&renderer);
    try std.testing.expect(!menu.widget.dirty);

    try std.testing.expect(!try menu.widget.handleEvent(down));
    try std.testing.expectEqual(@as(usize, 1), menu.selected);
    try std.testing.expect(!menu.widget.dirty);
}

test "context menu keyboard handles empty items" {
    const alloc = std.testing.allocator;
    var menu = try ContextMenu.init(alloc);
    defer menu.deinit();
    menu.openAt(0, 0);
    menu.widget.setFocus(true);
    menu.selected = std.math.maxInt(usize);

    const down = input.Event{ .key = input.KeyEvent.init(input.KeyCode.DOWN, .{}) };
    try std.testing.expect(try menu.widget.handleEvent(down));
    try std.testing.expectEqual(@as(usize, 0), menu.selected);

    try std.testing.expect(!try menu.widget.handleEvent(down));
    try std.testing.expectEqual(@as(usize, 0), menu.selected);

    const enter = input.Event{ .key = input.KeyEvent.init(input.KeyCode.ENTER, .{}) };
    try std.testing.expect(!try menu.widget.handleEvent(enter));
    try std.testing.expect(menu.open);
}

fn contextMenuAddItemAllocationFailureHarness(allocator: std.mem.Allocator) !void {
    var menu = try ContextMenu.init(allocator);
    defer menu.deinit();

    try menu.addItem("One", true, null);
    try menu.addItem("Two", true, null);
}

test "context menu addItem cleans up every allocation failure path" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, contextMenuAddItemAllocationFailureHarness, .{});
}

test "context menu addItem preserves items on allocation failure" {
    const alloc = std.testing.allocator;
    var menu = try ContextMenu.init(alloc);
    defer menu.deinit();
    try menu.addItem("One", true, null);

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = menu.allocator;
    menu.allocator = failing.allocator();
    defer menu.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, menu.addItem("Two", true, null));
    try std.testing.expectEqual(@as(usize, 1), menu.items.items.len);
    try std.testing.expectEqualStrings("One", menu.items.items[0].label);
}

test "context menu closes on outside click" {
    const alloc = std.testing.allocator;
    var menu = try ContextMenu.init(alloc);
    defer menu.deinit();
    try menu.addItem("Exit", true, null);
    menu.openAt(0, 0);
    try menu.widget.layout(layout_module.Rect.init(0, 0, 12, 3));

    const click = input.Event{ .mouse = input.MouseEvent.init(input.MouseAction.press, 20, 20, 1, 0) };
    _ = try menu.widget.handleEvent(click);
    try std.testing.expect(!menu.open);
}

test "context menu direct state changes mark dirty" {
    const alloc = std.testing.allocator;
    var menu = try ContextMenu.init(alloc);
    defer menu.deinit();
    try menu.addItem("One", true, null);
    try menu.addItem("Two", true, null);

    var renderer = try render.Renderer.init(alloc, 16, 4);
    defer renderer.deinit();

    menu.openAt(0, 0);
    try menu.widget.layout(layout_module.Rect.init(0, 0, 16, 4));
    try menu.widget.draw(&renderer);
    try std.testing.expect(!menu.widget.dirty);

    menu.close();
    try std.testing.expect(menu.widget.dirty);
    try menu.widget.draw(&renderer);
    try std.testing.expect(!menu.widget.dirty);

    menu.close();
    try std.testing.expect(!menu.widget.dirty);

    menu.openAt(0, 0);
    try std.testing.expect(menu.widget.dirty);
    try menu.widget.draw(&renderer);
    try std.testing.expect(!menu.widget.dirty);

    menu.openAt(0, 0);
    try std.testing.expect(!menu.widget.dirty);

    menu.setMaxVisible(1);
    try std.testing.expect(menu.widget.dirty);
    try menu.widget.draw(&renderer);
    try std.testing.expect(!menu.widget.dirty);

    menu.setMaxVisible(1);
    try std.testing.expect(!menu.widget.dirty);

    try menu.setTheme(theme.Theme.light());
    try std.testing.expect(menu.widget.dirty);
    try menu.widget.draw(&renderer);
    try std.testing.expect(!menu.widget.dirty);

    menu.clear();
    try std.testing.expect(menu.widget.dirty);
    try std.testing.expectEqual(@as(usize, 0), menu.items.items.len);
    try std.testing.expectEqual(@as(u16, 0), menu.widget.rect.height);
    try menu.widget.draw(&renderer);
    try std.testing.expect(!menu.widget.dirty);

    menu.clear();
    try std.testing.expect(!menu.widget.dirty);
}

test "context menu clear collapses open hit area" {
    const alloc = std.testing.allocator;
    var menu = try ContextMenu.init(alloc);
    defer menu.deinit();

    try menu.addItem("One", true, null);
    try menu.addItem("Two", true, null);
    menu.openAt(4, 3);
    try menu.widget.layout(layout_module.Rect.init(4, 3, 12, 4));
    try std.testing.expectEqual(@as(u16, 4), menu.widget.rect.height);

    menu.clear();
    try std.testing.expect(menu.open);
    try std.testing.expectEqual(@as(u16, 0), menu.widget.rect.height);

    const old_inside_click = input.Event{ .mouse = input.MouseEvent.init(.press, 5, 4, 1, 0) };
    try std.testing.expect(!try menu.widget.handleEvent(old_inside_click));
    try std.testing.expect(!menu.open);
}

test "context menu tolerates tiny and edge render rectangles" {
    const alloc = std.testing.allocator;
    var menu = try ContextMenu.init(alloc);
    defer menu.deinit();
    try menu.addItem("One", true, null);
    try menu.addItem("Two", true, null);

    var renderer = try render.Renderer.init(alloc, 4, 3);
    defer renderer.deinit();

    menu.openAt(0, 0);
    try menu.widget.layout(layout_module.Rect.init(0, 0, 1, 1));
    try menu.widget.draw(&renderer);

    try menu.widget.layout(layout_module.Rect.init(std.math.maxInt(u16) - 1, std.math.maxInt(u16) - 1, 4, 4));
    try menu.widget.draw(&renderer);

    const item_click = input.Event{ .mouse = input.MouseEvent.init(.press, std.math.maxInt(u16), std.math.maxInt(u16), 1, 0) };
    try std.testing.expect(try menu.widget.handleEvent(item_click));
    try std.testing.expectEqual(@as(usize, 0), menu.selected);
    try std.testing.expect(!menu.open);
}

test "context menu preferred width saturates long labels" {
    const alloc = std.testing.allocator;
    var menu = try ContextMenu.init(alloc);
    defer menu.deinit();

    const long_label = try alloc.alloc(u8, @as(usize, std.math.maxInt(u16)) + 256);
    defer alloc.free(long_label);
    @memset(long_label, 'x');

    try menu.addItem(long_label, true, null);
    const size = try menu.widget.getPreferredSize();

    try std.testing.expectEqual(@as(u16, std.math.maxInt(u16)), size.width);
    try std.testing.expectEqual(@as(u16, 3), size.height);
}
