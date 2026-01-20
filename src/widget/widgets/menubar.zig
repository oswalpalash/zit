const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");

pub const MenuItem = struct {
    label: []const u8,
    on_select: ?*const fn () void = null,
};

/// Horizontal menu bar with focusable items and keyboard navigation.
pub const MenuBar = struct {
    widget: base.Widget,
    items: std.ArrayList(MenuItem),
    active_index: usize = 0,
    fg: render.Color = render.Color.named(render.NamedColor.white),
    bg: render.Color = render.Color.named(render.NamedColor.black),
    active_fg: render.Color = render.Color.named(render.NamedColor.black),
    active_bg: render.Color = render.Color.named(render.NamedColor.cyan),
    allocator: std.mem.Allocator,

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator) !*MenuBar {
        const self = try allocator.create(MenuBar);
        self.* = MenuBar{
            .widget = base.Widget.init(&vtable),
            .items = std.ArrayList(MenuItem).empty,
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *MenuBar) void {
        for (self.items.items) |item| {
            self.allocator.free(item.label);
        }
        self.items.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn addItem(self: *MenuBar, label: []const u8, on_select: ?*const fn () void) !void {
        try self.items.append(self.allocator, .{ .label = try self.allocator.dupe(u8, label), .on_select = on_select });
    }

    pub fn setActive(self: *MenuBar, index: usize) void {
        if (index < self.items.items.len) {
            self.active_index = index;
        }
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*MenuBar, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;

        const rect = self.widget.rect;
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', self.fg, self.bg, render.Style{});

        var x = rect.x;
        for (self.items.items, 0..) |item, idx| {
            if (x >= rect.x + rect.width) break;
            const label_len = @as(u16, @intCast(@min(item.label.len, rect.width)));
            const fg = if (idx == self.active_index) self.active_fg else self.fg;
            const bg = if (idx == self.active_index) self.active_bg else self.bg;
            renderer.drawStr(x, rect.y, item.label[0..label_len], fg, bg, render.Style{ .bold = idx == self.active_index });
            x += label_len + 2; // add spacing
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*MenuBar, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.enabled or !self.widget.visible) return false;

        switch (event) {
            .key => |key| {
                if (key.key == input.KeyCode.LEFT and self.active_index > 0) {
                    self.active_index -= 1;
                    return true;
                }
                if (key.key == input.KeyCode.RIGHT and self.active_index + 1 < self.items.items.len) {
                    self.active_index += 1;
                    return true;
                }
                if (key.key == '\n') {
                    if (self.items.items.len == 0) return false;
                    if (self.items.items[self.active_index].on_select) |cb| cb();
                    return true;
                }
            },
            .mouse => |mouse| {
                if (mouse.action == .press and mouse.y == self.widget.rect.y) {
                    var x = self.widget.rect.x;
                    for (self.items.items, 0..) |item, idx| {
                        const label_len = @as(u16, @intCast(@min(item.label.len, self.widget.rect.width)));
                        const start = x;
                        const end = start + label_len;
                        if (mouse.x >= start and mouse.x < end) {
                            self.active_index = idx;
                            if (item.on_select) |cb| cb();
                            return true;
                        }
                        x = end + 2;
                    }
                }
            },
            else => {},
        }

        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*MenuBar, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*MenuBar, @ptrCast(@alignCast(widget_ptr)));
        var width: u16 = 0;
        for (self.items.items) |item| {
            const add: u16 = @intCast(@min(item.label.len + 2, 60));
            width = width + add;
        }
        return layout_module.Size.init(@max(width, 6), 1);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*MenuBar, @ptrCast(@alignCast(widget_ptr)));
        return self.widget.enabled and self.widget.visible and self.items.items.len > 0;
    }
};

// Used only by unit tests to observe callbacks without capturing.
var test_menu_bar_calls: usize = 0;

test "menubar navigates and triggers callbacks" {
    const alloc = std.testing.allocator;
    var bar = try MenuBar.init(alloc);
    defer bar.deinit();

    test_menu_bar_calls = 0;

    try bar.addItem("File", null);
    try bar.addItem("Edit", struct {
        fn thunk() void {
            test_menu_bar_calls += 1;
        }
    }.thunk);

    try bar.widget.layout(layout_module.Rect.init(0, 0, 20, 1));

    const right = input.Event{ .key = input.KeyEvent.init(input.KeyCode.RIGHT, input.KeyModifiers{}) };
    _ = try bar.widget.handleEvent(right);
    try std.testing.expectEqual(@as(usize, 1), bar.active_index);

    const enter = input.Event{ .key = input.KeyEvent.init('\n', input.KeyModifiers{}) };
    _ = try bar.widget.handleEvent(enter);
    try std.testing.expectEqual(@as(usize, 1), test_menu_bar_calls);
}
