const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const theme = @import("../theme.zig");

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
        return self;
    }

    pub fn deinit(self: *SplitPane) void {
        self.allocator.destroy(self);
    }

    pub fn setTheme(self: *SplitPane, value: theme.Theme) !void {
        self.palette = value;
        self.divider_color = value.color(.border);
    }

    pub fn setFirst(self: *SplitPane, widget: *base.Widget) void {
        self.first = widget;
        widget.parent = &self.widget;
    }

    pub fn setSecond(self: *SplitPane, widget: *base.Widget) void {
        self.second = widget;
        widget.parent = &self.widget;
    }

    pub fn setRatio(self: *SplitPane, ratio: f32) void {
        self.ratio = std.math.clamp(ratio, 0.05, 0.95);
    }

    pub fn setOrientation(self: *SplitPane, orientation: SplitOrientation) void {
        self.orientation = orientation;
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*SplitPane, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;

        const rect = self.widget.rect;
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', self.palette.color(.text), self.palette.color(.surface), self.palette.style);

        if (self.orientation == .horizontal) {
            const divider_x = rect.x + @as(u16, @intFromFloat(self.ratio * @as(f32, @floatFromInt(rect.width))));
            renderer.drawVLine(divider_x, rect.y, rect.height, '│', self.divider_color, self.palette.color(.surface), render.Style{});
        } else {
            const divider_y = rect.y + @as(u16, @intFromFloat(self.ratio * @as(f32, @floatFromInt(rect.height))));
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
        const self = @as(*SplitPane, @ptrCast(@alignCast(widget_ptr)));
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
        const self = @as(*SplitPane, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;

        if (self.orientation == .horizontal) {
            const available = if (rect.width > 1) rect.width - 1 else rect.width;
            const first_width = @max(self.min_child_size, @as(u16, @intFromFloat(self.ratio * @as(f32, @floatFromInt(available)))));
            const second_width = if (available > first_width) available - first_width else 0;
            if (self.first) |child| {
                try child.layout(layout_module.Rect.init(rect.x, rect.y, first_width, rect.height));
            }
            if (self.second) |child| {
                try child.layout(layout_module.Rect.init(rect.x + first_width + 1, rect.y, second_width, rect.height));
            }
        } else {
            const available = if (rect.height > 1) rect.height - 1 else rect.height;
            const first_height = @max(self.min_child_size, @as(u16, @intFromFloat(self.ratio * @as(f32, @floatFromInt(available)))));
            const second_height = if (available > first_height) available - first_height else 0;
            if (self.first) |child| {
                try child.layout(layout_module.Rect.init(rect.x, rect.y, rect.width, first_height));
            }
            if (self.second) |child| {
                try child.layout(layout_module.Rect.init(rect.x, rect.y + first_height + 1, rect.width, second_height));
            }
        }
    }

    fn getPreferredSizeFn(_: *anyopaque) anyerror!layout_module.Size {
        return layout_module.Size.init(20, 6);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*SplitPane, @ptrCast(@alignCast(widget_ptr)));
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
