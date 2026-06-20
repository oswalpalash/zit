const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const theme = @import("../theme.zig");
const accessibility = @import("../accessibility.zig");

/// Orientation for the split pane divider.
pub const SplitOrientation = enum {
    horizontal, // left/right
    vertical, // top/bottom
};

/// Two-way split container with a draggable ratio (keyboard-adjustable).
pub const SplitPane = struct {
    widget: base.Widget,
    first: ?*base.Widget = null,
    second: ?*base.Widget = null,
    orientation: SplitOrientation = .horizontal,
    ratio: f32 = 0.5,
    min_child_size: u16 = 3,
    divider_color: render.Color,
    palette: theme.Theme,
    allocator: std.mem.Allocator,

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator) !*SplitPane {
        const self = try allocator.create(SplitPane);
        const default_theme = theme.Theme.light();
        self.* = SplitPane{
            .widget = base.Widget.init(&vtable),
            .divider_color = default_theme.color(.border),
            .palette = default_theme,
            .allocator = allocator,
        };
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.container), "Split pane", "");
        return self;
    }

    pub fn deinit(self: *SplitPane) void {
        self.detachChildren();
        self.allocator.destroy(self);
    }

    pub fn setTheme(self: *SplitPane, value: theme.Theme) !void {
        self.palette = value;
        self.divider_color = value.color(.border);
    }

    pub fn setFirst(self: *SplitPane, widget: *base.Widget) void {
        if (self.first != widget) {
            self.detachSlot(&self.first);
            self.first = widget;
        }
        if (self.second == widget) {
            self.second = null;
        }
        widget.parent = &self.widget;
    }

    pub fn setSecond(self: *SplitPane, widget: *base.Widget) void {
        if (self.second != widget) {
            self.detachSlot(&self.second);
            self.second = widget;
        }
        if (self.first == widget) {
            self.first = null;
        }
        widget.parent = &self.widget;
    }

    fn detachChildren(self: *SplitPane) void {
        self.detachSlot(&self.first);
        self.detachSlot(&self.second);
    }

    fn detachSlot(self: *SplitPane, slot: *?*base.Widget) void {
        if (slot.*) |current| {
            if (current.parent == &self.widget) {
                current.parent = null;
            }
        }
        slot.* = null;
    }

    pub fn setRatio(self: *SplitPane, ratio: f32) void {
        self.ratio = std.math.clamp(ratio, 0.05, 0.95);
    }

    pub fn setOrientation(self: *SplitPane, orientation: SplitOrientation) void {
        self.orientation = orientation;
    }

    fn normalizedRatio(ratio: f32) f32 {
        if (!std.math.isFinite(ratio)) return 0.5;
        return std.math.clamp(ratio, 0.0, 1.0);
    }

    fn scaledSpan(ratio: f32, span: u16) u16 {
        if (span == 0) return 0;
        const scaled = normalizedRatio(ratio) * @as(f32, @floatFromInt(span));
        if (scaled <= 0) return 0;
        if (scaled >= @as(f32, @floatFromInt(span))) return span;
        return @intFromFloat(scaled);
    }

    fn dividerOffset(ratio: f32, span: u16) u16 {
        if (span == 0) return 0;
        return @min(scaledSpan(ratio, span), span - 1);
    }

    fn firstChildSpan(ratio: f32, available: u16, min_child_size: u16) u16 {
        if (available == 0) return 0;
        const min_size = @min(min_child_size, available);
        return @min(available, @max(min_size, scaledSpan(ratio, available)));
    }

    fn addOffsetClamped(origin: u16, offset: u16) u16 {
        const value = @as(u32, origin) + @as(u32, offset);
        return @intCast(@min(value, @as(u32, std.math.maxInt(u16))));
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *SplitPane = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible) return;

        const rect = self.widget.rect;
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', self.palette.color(.text), self.palette.color(.surface), self.palette.style);

        if (self.orientation == .horizontal) {
            const divider_x = addOffsetClamped(rect.x, dividerOffset(self.ratio, rect.width));
            renderer.drawVLine(divider_x, rect.y, rect.height, '│', self.divider_color, self.palette.color(.surface), render.Style{});
        } else {
            const divider_y = addOffsetClamped(rect.y, dividerOffset(self.ratio, rect.height));
            renderer.drawHLine(rect.x, divider_y, rect.width, '─', self.divider_color, self.palette.color(.surface), render.Style{});
        }

        if (self.first) |child| {
            try child.draw(renderer);
        }
        if (self.second) |child| {
            try child.draw(renderer);
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *SplitPane = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.enabled or !self.widget.visible) return false;

        // Allow keyboard nudging of divider.
        if (event == .key) {
            const key = event.key;
            const delta: f32 = 0.05;
            var changed = false;
            switch (key.key) {
                input.KeyCode.LEFT => {
                    if (self.orientation == .horizontal) {
                        self.setRatio(self.ratio - delta);
                        changed = true;
                    }
                },
                input.KeyCode.RIGHT => {
                    if (self.orientation == .horizontal) {
                        self.setRatio(self.ratio + delta);
                        changed = true;
                    }
                },
                input.KeyCode.UP => {
                    if (self.orientation == .vertical) {
                        self.setRatio(self.ratio - delta);
                        changed = true;
                    }
                },
                input.KeyCode.DOWN => {
                    if (self.orientation == .vertical) {
                        self.setRatio(self.ratio + delta);
                        changed = true;
                    }
                },
                else => {},
            }
            if (changed) return true;
        }

        // Pass through to children.
        if (self.first) |child| {
            if (try child.handleEvent(event)) return true;
        }
        if (self.second) |child| {
            if (try child.handleEvent(event)) return true;
        }
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *SplitPane = @fieldParentPtr("widget", widget_ref);
        self.widget.rect = rect;

        if (self.orientation == .horizontal) {
            const available = if (rect.width > 1) rect.width - 1 else rect.width;
            const first_width = firstChildSpan(self.ratio, available, self.min_child_size);
            const second_width = available - first_width;
            if (self.first) |child| {
                try child.layout(layout_module.Rect.init(rect.x, rect.y, first_width, rect.height));
            }
            if (self.second) |child| {
                const second_x = addOffsetClamped(addOffsetClamped(rect.x, first_width), if (rect.width > 1) 1 else 0);
                try child.layout(layout_module.Rect.init(second_x, rect.y, second_width, rect.height));
            }
        } else {
            const available = if (rect.height > 1) rect.height - 1 else rect.height;
            const first_height = firstChildSpan(self.ratio, available, self.min_child_size);
            const second_height = available - first_height;
            if (self.first) |child| {
                try child.layout(layout_module.Rect.init(rect.x, rect.y, rect.width, first_height));
            }
            if (self.second) |child| {
                const second_y = addOffsetClamped(addOffsetClamped(rect.y, first_height), if (rect.height > 1) 1 else 0);
                try child.layout(layout_module.Rect.init(rect.x, second_y, rect.width, second_height));
            }
        }
    }

    fn getPreferredSizeFn(_: *anyopaque) anyerror!layout_module.Size {
        return layout_module.Size.init(20, 6);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *SplitPane = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.enabled or !self.widget.visible) return false;
        const first_focusable = if (self.first) |child| child.canFocus() else false;
        const second_focusable = if (self.second) |child| child.canFocus() else false;
        return first_focusable or second_focusable;
    }
};

test "split pane lays out children" {
    const alloc = std.testing.allocator;
    var pane = try SplitPane.init(alloc);
    defer pane.deinit();

    var left = try @import("label.zig").Label.init(alloc, "left");
    defer left.deinit();

    var right = try @import("label.zig").Label.init(alloc, "right");
    defer right.deinit();

    pane.setFirst(&left.widget);
    pane.setSecond(&right.widget);
    pane.setRatio(0.4);
    try pane.widget.layout(layout_module.Rect.init(0, 0, 30, 4));

    try std.testing.expectEqual(@as(u16, 30), pane.widget.rect.width);
    try std.testing.expect(left.widget.rect.width > 0);
    try std.testing.expect(right.widget.rect.width > 0);
}

test "split pane clamps horizontal edge layout and draw coordinates" {
    const alloc = std.testing.allocator;
    var pane = try SplitPane.init(alloc);
    defer pane.deinit();

    var first = try @import("label.zig").Label.init(alloc, "first");
    defer first.deinit();
    var second = try @import("label.zig").Label.init(alloc, "second");
    defer second.deinit();

    pane.setFirst(&first.widget);
    pane.setSecond(&second.widget);
    pane.min_child_size = std.math.maxInt(u16);
    pane.setRatio(0.5);

    try pane.widget.layout(layout_module.Rect.init(std.math.maxInt(u16), 0, 4, 1));
    try std.testing.expectEqual(@as(u16, 3), first.widget.rect.width);
    try std.testing.expectEqual(@as(u16, 0), second.widget.rect.width);
    try std.testing.expectEqual(std.math.maxInt(u16), second.widget.rect.x);

    var renderer = try render.Renderer.init(alloc, 2, 1);
    defer renderer.deinit();
    try pane.widget.draw(&renderer);
}

test "split pane clamps vertical edge layout and invalid ratios" {
    const alloc = std.testing.allocator;
    var pane = try SplitPane.init(alloc);
    defer pane.deinit();

    var first = try @import("label.zig").Label.init(alloc, "first");
    defer first.deinit();
    var second = try @import("label.zig").Label.init(alloc, "second");
    defer second.deinit();

    pane.setFirst(&first.widget);
    pane.setSecond(&second.widget);
    pane.setOrientation(.vertical);
    pane.min_child_size = std.math.maxInt(u16);
    pane.ratio = std.math.nan(f32);

    try pane.widget.layout(layout_module.Rect.init(0, std.math.maxInt(u16), 1, 4));
    try std.testing.expectEqual(@as(u16, 3), first.widget.rect.height);
    try std.testing.expectEqual(@as(u16, 0), second.widget.rect.height);
    try std.testing.expectEqual(std.math.maxInt(u16), second.widget.rect.y);

    var renderer = try render.Renderer.init(alloc, 1, 2);
    defer renderer.deinit();
    try pane.widget.draw(&renderer);
}

test "split pane replacing first child detaches previous child" {
    const alloc = std.testing.allocator;
    var pane = try SplitPane.init(alloc);
    defer pane.deinit();

    var old_child = try @import("label.zig").Label.init(alloc, "old");
    defer old_child.deinit();
    var new_child = try @import("label.zig").Label.init(alloc, "new");
    defer new_child.deinit();

    pane.setFirst(&old_child.widget);
    pane.setFirst(&new_child.widget);

    try std.testing.expect(pane.first != null);
    try std.testing.expectEqual(&new_child.widget, pane.first.?);
    try std.testing.expect(old_child.widget.parent == null);
    try std.testing.expectEqual(&pane.widget, new_child.widget.parent.?);
}

test "split pane moves child between slots without duplicate ownership" {
    const alloc = std.testing.allocator;
    var pane = try SplitPane.init(alloc);
    defer pane.deinit();

    var child = try @import("label.zig").Label.init(alloc, "child");
    defer child.deinit();

    pane.setFirst(&child.widget);
    pane.setSecond(&child.widget);

    try std.testing.expect(pane.first == null);
    try std.testing.expect(pane.second != null);
    try std.testing.expectEqual(&child.widget, pane.second.?);
    try std.testing.expectEqual(&pane.widget, child.widget.parent.?);
}

test "split pane deinit detaches owned child parent links" {
    const alloc = std.testing.allocator;
    var pane = try SplitPane.init(alloc);

    var first = try @import("label.zig").Label.init(alloc, "first");
    defer first.deinit();
    var second = try @import("label.zig").Label.init(alloc, "second");
    defer second.deinit();

    pane.setFirst(&first.widget);
    pane.setSecond(&second.widget);
    pane.deinit();

    try std.testing.expect(first.widget.parent == null);
    try std.testing.expect(second.widget.parent == null);
}
