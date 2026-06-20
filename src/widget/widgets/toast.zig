const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const accessibility = @import("../accessibility.zig");

pub const ToastLevel = enum {
    info,
    success,
    warning,
    danger,
};

const ToastEntry = struct {
    message: []const u8,
    level: ToastLevel,
    remaining_ticks: u32,
};

/// Toast notification stack that renders floating messages in a corner.
pub const ToastManager = struct {
    widget: base.Widget,
    toasts: std.ArrayList(ToastEntry),
    max_visible: u8 = 5,
    fg: render.Color = render.Color.named(render.NamedColor.white),
    bg: render.Color = render.Color.named(render.NamedColor.black),
    allocator: std.mem.Allocator,

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator) !*ToastManager {
        const self = try allocator.create(ToastManager);
        self.* = ToastManager{
            .widget = base.Widget.init(&vtable),
            .toasts = std.ArrayList(ToastEntry).empty,
            .allocator = allocator,
        };
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.alert), "Toast notifications", "");
        return self;
    }

    pub fn deinit(self: *ToastManager) void {
        for (self.toasts.items) |toast| {
            self.allocator.free(toast.message);
        }
        self.toasts.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn push(self: *ToastManager, msg: []const u8, level: ToastLevel, lifespan_ticks: u32) !void {
        try self.toasts.ensureUnusedCapacity(self.allocator, 1);
        const toast = ToastEntry{
            .message = try self.allocator.dupe(u8, msg),
            .level = level,
            .remaining_ticks = @max(lifespan_ticks, 1),
        };
        self.toasts.appendAssumeCapacity(toast);
        self.trimOverflow();
    }

    /// Advance lifetimes and drop expired toasts.
    pub fn tick(self: *ToastManager, ticks: u32) void {
        var i: usize = 0;
        while (i < self.toasts.items.len) {
            var entry = &self.toasts.items[i];
            if (entry.remaining_ticks > ticks) {
                entry.remaining_ticks -= ticks;
                i += 1;
            } else {
                self.allocator.free(entry.message);
                _ = self.toasts.orderedRemove(i);
            }
        }
    }

    fn levelColors(self: *ToastManager, level: ToastLevel) struct { fg: render.Color, bg: render.Color } {
        return switch (level) {
            .info => .{ .fg = self.fg, .bg = render.Color.named(render.NamedColor.blue) },
            .success => .{ .fg = self.fg, .bg = render.Color.named(render.NamedColor.green) },
            .warning => .{ .fg = self.fg, .bg = render.Color.named(render.NamedColor.yellow) },
            .danger => .{ .fg = self.fg, .bg = render.Color.named(render.NamedColor.red) },
        };
    }

    fn addOffsetClamped(origin: u16, offset: u16) u16 {
        const value = @as(u32, origin) + @as(u32, offset);
        return @intCast(@min(value, @as(u32, std.math.maxInt(u16))));
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *ToastManager = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible) return;

        const rect = self.widget.rect;
        const limit = @min(self.toasts.items.len, @as(usize, self.max_visible));
        var y_offset: u16 = 0;
        var idx: usize = 0;
        while (idx < limit) : (idx += 1) {
            if (rect.width < 4 or rect.height < 3) break;

            const toast = self.toasts.items[idx];
            const colors = self.levelColors(toast.level);
            const text_len = @as(u16, @intCast(@min(toast.message.len, rect.width - 2)));
            const box_height: u16 = 3;
            if (y_offset > rect.height - box_height) break;
            const y = addOffsetClamped(rect.y, y_offset);

            renderer.drawBox(rect.x, y, rect.width, box_height, .rounded, colors.fg, colors.bg, render.Style{});
            renderer.drawStr(addOffsetClamped(rect.x, 1), addOffsetClamped(y, 1), toast.message[0..text_len], colors.fg, colors.bg, render.Style{});
            y_offset += box_height;
        }
    }

    fn handleEventFn(_: *anyopaque, _: input.Event) anyerror!bool {
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *ToastManager = @fieldParentPtr("widget", widget_ref);
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(_: *anyopaque) anyerror!layout_module.Size {
        // Default footprint is narrow; host container should position it.
        return layout_module.Size.init(24, 8);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *ToastManager = @fieldParentPtr("widget", widget_ref);
        return self.widget.visible and self.widget.enabled;
    }

    fn trimOverflow(self: *ToastManager) void {
        while (self.toasts.items.len > self.max_visible) {
            const removed = self.toasts.orderedRemove(0);
            self.allocator.free(removed.message);
        }
    }
};

test "toast manager drops expired messages" {
    const alloc = std.testing.allocator;
    var manager = try ToastManager.init(alloc);
    defer manager.deinit();

    try manager.push("one", .info, 2);
    try manager.push("two", .success, 1);

    try manager.widget.layout(layout_module.Rect.init(0, 0, 20, 6));

    manager.tick(1);
    try std.testing.expectEqual(@as(usize, 1), manager.toasts.items.len);
    try std.testing.expectEqualStrings("one", manager.toasts.items[0].message);

    manager.tick(2);
    try std.testing.expectEqual(@as(usize, 0), manager.toasts.items.len);
}

test "toast manager clamps edge draw coordinates" {
    const alloc = std.testing.allocator;
    var manager = try ToastManager.init(alloc);
    defer manager.deinit();

    try manager.push("edge", .info, 4);
    try manager.widget.layout(layout_module.Rect.init(std.math.maxInt(u16), std.math.maxInt(u16), 8, 3));

    var renderer = try render.Renderer.init(alloc, 2, 2);
    defer renderer.deinit();

    try manager.widget.draw(&renderer);
    try std.testing.expectEqual(@as(u21, ' '), renderer.back.getCell(0, 0).codepoint());
    try std.testing.expectEqual(@as(u21, ' '), renderer.back.getCell(1, 1).codepoint());
}

test "toast manager clips stack height without absolute coordinate overflow" {
    const alloc = std.testing.allocator;
    var manager = try ToastManager.init(alloc);
    defer manager.deinit();

    try manager.push("first", .info, 4);
    try manager.push("second", .success, 4);
    try manager.widget.layout(layout_module.Rect.init(0, std.math.maxInt(u16), 10, 3));

    var renderer = try render.Renderer.init(alloc, 10, 3);
    defer renderer.deinit();

    try manager.widget.draw(&renderer);
    try std.testing.expectEqual(@as(u21, ' '), renderer.back.getCell(0, 0).codepoint());
}

fn toastPushAllocationFailureHarness(allocator: std.mem.Allocator) !void {
    var manager = try ToastManager.init(allocator);
    defer manager.deinit();

    try manager.push("one", .info, 2);
    try manager.push("two", .success, 1);
}

test "toast manager push cleans up every allocation failure path" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, toastPushAllocationFailureHarness, .{});
}

test "toast manager push preserves toasts on allocation failure" {
    const alloc = std.testing.allocator;
    var manager = try ToastManager.init(alloc);
    defer manager.deinit();

    try manager.push("stable", .info, 2);

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = manager.allocator;
    manager.allocator = failing.allocator();
    defer manager.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, manager.push("replacement", .success, 1));
    try std.testing.expectEqual(@as(usize, 1), manager.toasts.items.len);
    try std.testing.expectEqualStrings("stable", manager.toasts.items[0].message);
}
