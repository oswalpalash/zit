const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");

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
        self.* = Popup{
            .widget = base.Widget.init(&vtable),
            .message = try allocator.dupe(u8, message),
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *Popup) void {
        self.allocator.free(self.message);
        self.allocator.destroy(self);
    }

    pub fn setMessage(self: *Popup, message: []const u8) !void {
        self.allocator.free(self.message);
        self.message = try self.allocator.dupe(u8, message);
    }

    pub fn setColors(self: *Popup, fg: render.Color, bg: render.Color) void {
        self.fg = fg;
        self.bg = bg;
    }

    pub fn setBorder(self: *Popup, border: render.BorderStyle) void {
        self.border = border;
    }

    pub fn setDismissOnAnyKey(self: *Popup, enabled: bool) void {
        self.dismiss_on_any_key = enabled;
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*Popup, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;

        const rect = self.widget.rect;
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', self.fg, self.bg, render.Style{});
        if (self.border != .none) {
            renderer.drawBox(rect.x, rect.y, rect.width, rect.height, self.border, self.fg, self.bg, render.Style{});
        }

        if (rect.width <= 2 or rect.height <= 2) return;

        const inner_width = rect.width - 2;
        const text_len = @as(u16, @intCast(@min(self.message.len, inner_width)));
        const text_x = rect.x + 1 + (inner_width - text_len) / 2;
        const text_y = rect.y + rect.height / 2;
        renderer.drawStr(text_x, text_y, self.message[0..text_len], self.fg, self.bg, render.Style{ .bold = true });
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*Popup, @ptrCast(@alignCast(widget_ptr)));
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
        const self = @as(*Popup, @ptrCast(@alignCast(widget_ptr)));
        const preferred = try getPreferredSizeFn(widget_ptr);
        const actual_width = @min(rect.width, preferred.width);
        const actual_height = @min(rect.height, preferred.height);

        self.widget.rect = layout_module.Rect{
            .x = rect.x + @divTrunc(rect.width - actual_width, 2),
            .y = rect.y + @divTrunc(rect.height - actual_height, 2),
            .width = actual_width,
            .height = actual_height,
        };
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*Popup, @ptrCast(@alignCast(widget_ptr)));
        const min_width: u16 = 10;
        const text_width = @as(u16, @intCast(self.message.len + 4));
        return layout_module.Size.init(@max(min_width, @min(text_width, self.width)), self.height);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*Popup, @ptrCast(@alignCast(widget_ptr)));
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
