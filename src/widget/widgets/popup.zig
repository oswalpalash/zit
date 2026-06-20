const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const accessibility = @import("../accessibility.zig");

/// Lightweight popup panel for transient messages or contextual overlays.
pub const Popup = struct {
    widget: base.Widget,
    message: []const u8,
    width: u16 = 24,
    height: u16 = 5,
    fg: render.Color = render.Color.named(render.NamedColor.white),
    bg: render.Color = render.Color.named(render.NamedColor.blue),
    border: render.BorderStyle = .rounded,
    dismiss_on_any_key: bool = true,
    allocator: std.mem.Allocator,

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator, message: []const u8) !*Popup {
        const self = try allocator.create(Popup);
        errdefer allocator.destroy(self);

        const message_copy = try allocator.dupe(u8, message);
        self.* = Popup{
            .widget = base.Widget.init(&vtable),
            .message = message_copy,
            .allocator = allocator,
        };
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.popup), self.message, "");
        return self;
    }

    pub fn deinit(self: *Popup) void {
        self.allocator.free(self.message);
        self.allocator.destroy(self);
    }

    pub fn setMessage(self: *Popup, message: []const u8) !void {
        const next = try self.allocator.dupe(u8, message);
        self.allocator.free(self.message);
        self.message = next;
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.popup), self.message, "");
        self.widget.markDirty();
    }

    pub fn setColors(self: *Popup, fg: render.Color, bg: render.Color) void {
        self.fg = fg;
        self.bg = bg;
        self.widget.markDirty();
    }

    pub fn setBorder(self: *Popup, border: render.BorderStyle) void {
        if (self.border == border) return;
        self.border = border;
        self.widget.markDirty();
    }

    pub fn setDismissOnAnyKey(self: *Popup, enabled: bool) void {
        self.dismiss_on_any_key = enabled;
    }

    fn addOffsetClamped(origin: u16, offset: u16) u16 {
        const value = @as(u32, origin) + @as(u32, offset);
        return @intCast(@min(value, @as(u32, std.math.maxInt(u16))));
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Popup = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible) return;

        const rect = self.widget.rect;
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', self.fg, self.bg, render.Style{});
        if (self.border != .none) {
            renderer.drawBox(rect.x, rect.y, rect.width, rect.height, self.border, self.fg, self.bg, render.Style{});
        }

        if (rect.width <= 2 or rect.height <= 2) return;

        const inner_width = rect.width - 2;
        const text_len = @as(u16, @intCast(@min(self.message.len, inner_width)));
        const text_x = addOffsetClamped(rect.x, 1 + (inner_width - text_len) / 2);
        const text_y = addOffsetClamped(rect.y, rect.height / 2);
        renderer.drawStr(text_x, text_y, self.message[0..text_len], self.fg, self.bg, render.Style{ .bold = true });
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Popup = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible or !self.widget.enabled) return false;

        switch (event) {
            .key => {
                if (self.dismiss_on_any_key) {
                    self.widget.visible = false;
                    return true;
                }
            },
            .mouse => |mouse| {
                if (mouse.action == .press and !self.widget.rect.contains(mouse.x, mouse.y)) {
                    self.widget.visible = false;
                    return true;
                }
            },
            else => {},
        }

        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Popup = @fieldParentPtr("widget", widget_ref);
        const preferred = try getPreferredSizeFn(widget_ptr);
        const actual_width = @min(rect.width, preferred.width);
        const actual_height = @min(rect.height, preferred.height);

        self.widget.rect = layout_module.Rect{
            .x = addOffsetClamped(rect.x, @divTrunc(rect.width - actual_width, 2)),
            .y = addOffsetClamped(rect.y, @divTrunc(rect.height - actual_height, 2)),
            .width = actual_width,
            .height = actual_height,
        };
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Popup = @fieldParentPtr("widget", widget_ref);
        const min_width: u16 = 10;
        const text_width = @as(u16, @intCast(@min(self.message.len, @as(usize, self.width -| 4)) + 4));
        return layout_module.Size.init(@max(min_width, @min(text_width, self.width)), self.height);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Popup = @fieldParentPtr("widget", widget_ref);
        return self.widget.visible and self.widget.enabled;
    }
};

test "popup centers and dismisses" {
    const alloc = std.testing.allocator;
    var popup = try Popup.init(alloc, "Hello");
    defer popup.deinit();

    try popup.widget.layout(layout_module.Rect.init(0, 0, 30, 10));
    try std.testing.expectEqual(@as(u16, 30 / 2 - popup.widget.rect.width / 2), popup.widget.rect.x);

    const event = input.Event{ .key = input.KeyEvent.init('a', input.KeyModifiers{}) };
    const handled = try popup.widget.handleEvent(event);
    try std.testing.expect(handled);
    try std.testing.expect(!popup.widget.visible);
}

fn popupInitAllocationFailureHarness(allocator: std.mem.Allocator) !void {
    var popup = try Popup.init(allocator, "Hello");
    defer popup.deinit();
}

test "popup init cleans up every allocation failure path" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, popupInitAllocationFailureHarness, .{});
}

test "popup dismisses on outside mouse press" {
    const alloc = std.testing.allocator;
    var popup = try Popup.init(alloc, "Hello");
    defer popup.deinit();

    try popup.widget.layout(layout_module.Rect.init(0, 0, 30, 10));

    try std.testing.expect(!try popup.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, popup.widget.rect.x, popup.widget.rect.y, 1, 0) }));
    try std.testing.expect(popup.widget.visible);

    try std.testing.expect(try popup.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 29, 9, 1, 0) }));
    try std.testing.expect(!popup.widget.visible);
}

test "popup setMessage preserves message on allocation failure" {
    const alloc = std.testing.allocator;
    var popup = try Popup.init(alloc, "Stable");
    defer popup.deinit();

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    popup.allocator = failing.allocator();

    try std.testing.expectError(error.OutOfMemory, popup.setMessage("Replacement"));
    try std.testing.expectEqualStrings("Stable", popup.message);
}

test "popup clamps edge layout and draw coordinates" {
    const alloc = std.testing.allocator;
    const max = std.math.maxInt(u16);
    var popup = try Popup.init(alloc, "Edge");
    defer popup.deinit();

    popup.width = 4;
    popup.height = 3;
    try popup.widget.layout(layout_module.Rect.init(max - 1, max - 1, 12, 12));

    try std.testing.expectEqual(max, popup.widget.rect.x);
    try std.testing.expectEqual(max, popup.widget.rect.y);

    var renderer = try render.Renderer.init(alloc, 2, 2);
    defer renderer.deinit();
    try popup.widget.draw(&renderer);

    try std.testing.expectEqual(@as(u21, ' '), renderer.back.getCell(0, 0).codepoint());
    try std.testing.expectEqual(@as(u21, ' '), renderer.back.getCell(1, 1).codepoint());
}

test "popup preferred size clamps long messages before u16 cast" {
    const alloc = std.testing.allocator;
    const message = try alloc.alloc(u8, std.math.maxInt(u16) + 1);
    defer alloc.free(message);
    @memset(message, 'x');

    var popup = try Popup.init(alloc, message);
    defer popup.deinit();

    const size = try popup.widget.getPreferredSize();
    try std.testing.expectEqual(popup.width, size.width);
    try std.testing.expectEqual(popup.height, size.height);
}
