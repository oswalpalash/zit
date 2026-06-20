const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const accessibility = @import("../accessibility.zig");

pub const MenuItem = struct {
    label: []const u8,
    on_select: ?*const fn () void = null,
};

fn addUsizeSaturating(a: usize, b: usize) usize {
    return std.math.add(usize, a, b) catch std.math.maxInt(usize);
}

fn preferredWidthAfterItem(current: usize, label_len: usize) usize {
    const capped_label_width = @min(label_len, 58);
    const item_width = addUsizeSaturating(capped_label_width, 2);
    return @min(addUsizeSaturating(current, item_width), @as(usize, std.math.maxInt(u16)));
}

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
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.menu), "Menu bar", "");
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
        try self.items.ensureUnusedCapacity(self.allocator, 1);
        const copy = try self.allocator.dupe(u8, label);
        self.items.appendAssumeCapacity(.{ .label = copy, .on_select = on_select });
    }

    pub fn setActive(self: *MenuBar, index: usize) void {
        if (index < self.items.items.len) {
            self.active_index = index;
        }
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *MenuBar = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible) return;

        const rect = self.widget.rect;
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', self.fg, self.bg, render.Style{});

        const right = rectRight(rect);
        var x: u32 = rect.x;
        for (self.items.items, 0..) |item, idx| {
            if (x >= right) break;
            const draw_x = u16Coord(x) orelse break;
            const available: usize = @intCast(@min(right - x, @as(u32, std.math.maxInt(u16))));
            const label_len = @min(item.label.len, available);
            const fg = if (idx == self.active_index) self.active_fg else self.fg;
            const bg = if (idx == self.active_index) self.active_bg else self.bg;
            renderer.drawStr(draw_x, rect.y, item.label[0..label_len], fg, bg, render.Style{ .bold = idx == self.active_index });
            x += @as(u32, @intCast(label_len)) + 2; // add spacing
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *MenuBar = @fieldParentPtr("widget", widget_ref);
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
                    const right = rectRight(self.widget.rect);
                    const mouse_x: u32 = mouse.x;
                    var x: u32 = self.widget.rect.x;
                    for (self.items.items, 0..) |item, idx| {
                        if (x >= right) break;
                        const available: usize = @intCast(@min(right - x, @as(u32, std.math.maxInt(u16))));
                        const label_len = @min(item.label.len, available);
                        const start = x;
                        const end = start + @as(u32, @intCast(label_len));
                        if (mouse_x >= start and mouse_x < end) {
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
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *MenuBar = @fieldParentPtr("widget", widget_ref);
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *MenuBar = @fieldParentPtr("widget", widget_ref);
        var width: usize = 0;
        for (self.items.items) |item| {
            width = preferredWidthAfterItem(width, item.label.len);
        }
        return layout_module.Size.init(@as(u16, @intCast(@max(width, 6))), 1);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *MenuBar = @fieldParentPtr("widget", widget_ref);
        return self.widget.enabled and self.widget.visible and self.items.items.len > 0;
    }

    fn rectRight(rect: layout_module.Rect) u32 {
        return @as(u32, rect.x) + @as(u32, rect.width);
    }

    fn u16Coord(value: u32) ?u16 {
        if (value > std.math.maxInt(u16)) return null;
        return @intCast(value);
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

test "menubar mouse selects rendered item row" {
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

    try bar.widget.layout(layout_module.Rect.init(3, 4, 20, 1));

    try std.testing.expect(!try bar.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 10, 3, 1, 0) }));
    try std.testing.expectEqual(@as(usize, 0), bar.active_index);
    try std.testing.expectEqual(@as(usize, 0), test_menu_bar_calls);

    try std.testing.expect(try bar.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 10, 4, 1, 0) }));
    try std.testing.expectEqual(@as(usize, 1), bar.active_index);
    try std.testing.expectEqual(@as(usize, 1), test_menu_bar_calls);
}

test "menubar clips edge coordinates before u16 overflow" {
    const alloc = std.testing.allocator;
    var bar = try MenuBar.init(alloc);
    defer bar.deinit();

    test_menu_bar_calls = 0;

    try bar.addItem("File", struct {
        fn thunk() void {
            test_menu_bar_calls += 1;
        }
    }.thunk);
    try bar.addItem("Edit", null);

    try bar.widget.layout(layout_module.Rect.init(std.math.maxInt(u16) - 1, 0, 4, 1));

    var renderer = try render.Renderer.init(alloc, 4, 1);
    defer renderer.deinit();
    try bar.widget.draw(&renderer);

    const click = input.Event{ .mouse = input.MouseEvent.init(.press, std.math.maxInt(u16), 0, 1, 0) };
    try std.testing.expect(try bar.widget.handleEvent(click));
    try std.testing.expectEqual(@as(usize, 0), bar.active_index);
    try std.testing.expectEqual(@as(usize, 1), test_menu_bar_calls);
}

fn menuBarAddItemAllocationFailureHarness(allocator: std.mem.Allocator) !void {
    var bar = try MenuBar.init(allocator);
    defer bar.deinit();

    try bar.addItem("File", null);
    try bar.addItem("Edit", null);
}

test "menubar addItem cleans up every allocation failure path" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, menuBarAddItemAllocationFailureHarness, .{});
}

test "menubar preferred width saturates for many items" {
    const alloc = std.testing.allocator;
    var bar = try MenuBar.init(alloc);
    defer bar.deinit();

    const label = "012345678901234567890123456789012345678901234567890123456789";
    var i: usize = 0;
    while (i < 1200) : (i += 1) {
        try bar.addItem(label, null);
    }

    const size = try MenuBar.getPreferredSizeFn(@ptrCast(@alignCast(&bar.widget)));
    try std.testing.expectEqual(std.math.maxInt(u16), size.width);
}

test "menubar preferred width accumulation saturates before clamping" {
    const width = preferredWidthAfterItem(std.math.maxInt(usize) - 1, std.math.maxInt(usize));
    try std.testing.expectEqual(@as(usize, std.math.maxInt(u16)), width);
}

test "menubar addItem preserves items on allocation failure" {
    const alloc = std.testing.allocator;
    var bar = try MenuBar.init(alloc);
    defer bar.deinit();
    try bar.addItem("File", null);

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = bar.allocator;
    bar.allocator = failing.allocator();
    defer bar.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, bar.addItem("Edit", null));
    try std.testing.expectEqual(@as(usize, 1), bar.items.items.len);
    try std.testing.expectEqualStrings("File", bar.items.items[0].label);
}
