const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const theme = @import("../theme.zig");
const input = @import("../../input/input.zig");

/// Gauge orientation.
pub const GaugeOrientation = enum {
    horizontal,
    vertical,
};

/// Meter-style gauge that can display progress with a label.
pub const Gauge = struct {
    widget: base.Widget,
    value: f32,
    min: f32,
    max: f32,
    label: []const u8,
    fg: render.Color,
    bg: render.Color,
    fill: render.Color,
    border: render.BorderStyle = .single,
    orientation: GaugeOrientation = .horizontal,
    allocator: std.mem.Allocator,

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator) !*Gauge {
        const self = try allocator.create(Gauge);
        self.* = Gauge{
            .widget = base.Widget.init(&vtable),
            .value = 0,
            .min = 0,
            .max = 100,
            .label = "",
            .fg = render.Color.named(render.NamedColor.default),
            .bg = render.Color.named(render.NamedColor.black),
            .fill = render.Color.named(render.NamedColor.green),
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *Gauge) void {
        if (self.label.len > 0) {
            self.allocator.free(self.label);
        }
        self.allocator.destroy(self);
    }

    pub fn setTheme(self: *Gauge, theme_value: theme.Theme) void {
        self.fg = theme_value.color(.text);
        self.bg = theme_value.color(.surface);
        self.fill = theme_value.color(.accent);
    }

    pub fn setValue(self: *Gauge, value: f32) void {
        self.value = value;
    }

    pub fn setRange(self: *Gauge, min: f32, max: f32) void {
        self.min = min;
        self.max = max;
    }

    pub fn setLabel(self: *Gauge, text: []const u8) !void {
        if (self.label.len > 0) {
            self.allocator.free(self.label);
        }
        self.label = try self.allocator.dupe(u8, text);
    }

    pub fn setOrientation(self: *Gauge, orientation: GaugeOrientation) void {
        self.orientation = orientation;
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*Gauge, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;

        const rect = self.widget.rect;
        if (rect.width == 0 or rect.height == 0) return;

        // Clamp ratio between 0 and 1.
        const clamped = std.math.clamp(self.value, self.min, self.max);
        const ratio = if (self.max - self.min == 0) 0 else (clamped - self.min) / (self.max - self.min);

        // Draw background.
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', self.fg, self.bg, render.Style{});

        if (self.border != .none and rect.width > 2 and rect.height > 2) {
            renderer.drawBox(rect.x, rect.y, rect.width, rect.height, self.border, self.fg, self.bg, render.Style{});
        }

        // Compute inner area.
        const inset: u16 = if (self.border == .none) 0 else 1;
        const inner_width = if (rect.width > inset * 2) rect.width - inset * 2 else 0;
        const inner_height = if (rect.height > inset * 2) rect.height - inset * 2 else 0;
        const inner_x = rect.x + inset;
        const inner_y = rect.y + inset;

        if (inner_width == 0 or inner_height == 0) return;

        if (self.orientation == .horizontal) {
            const filled = @as(u16, @intFromFloat(ratio * @as(f32, @floatFromInt(inner_width))));
            if (filled > 0) {
                renderer.fillRect(inner_x, inner_y, filled, inner_height, ' ', self.fg, self.fill, render.Style{});
            }
        } else {
            const filled = @as(u16, @intFromFloat(ratio * @as(f32, @floatFromInt(inner_height))));
            if (filled > 0) {
                const start_y = inner_y + inner_height - filled;
                renderer.fillRect(inner_x, start_y, inner_width, filled, ' ', self.fg, self.fill, render.Style{});
            }
        }

        // Render label centered.
        if (self.label.len > 0 and inner_width > 2 and inner_height > 0) {
            const text_x = inner_x + (inner_width - @as(u16, @intCast(@min(self.label.len, inner_width)))) / 2;
            const text_y = inner_y + inner_height / 2;
            renderer.drawStr(text_x, text_y, self.label, self.fg, self.bg, render.Style{ .bold = true });
        }
    }

    fn handleEventFn(_: *anyopaque, _: input.Event) anyerror!bool {
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*Gauge, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(_: *anyopaque) anyerror!layout_module.Size {
        // Default footprint leaves room for a label and border.
        return layout_module.Size.init(16, 3);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*Gauge, @ptrCast(@alignCast(widget_ptr)));
        return self.widget.enabled and self.widget.visible;
    }
};

test "gauge fills proportionally" {
    const alloc = std.testing.allocator;
    var gauge = try Gauge.init(alloc);
    defer gauge.deinit();

    gauge.setRange(0, 100);
    gauge.setValue(50);
    try gauge.widget.layout(layout_module.Rect.init(0, 0, 20, 3));

    var renderer = try render.Renderer.init(alloc, 20, 3);
    defer renderer.deinit();

    try gauge.widget.draw(&renderer);

    var filled: usize = 0;
    var empty: usize = 0;
    for (0..20) |x| {
        const cell = renderer.back.getCell(@intCast(x), 1).*;
        if (std.meta.eql(cell.bg, gauge.fill)) {
            filled += 1;
        } else {
            empty += 1;
        }
    }

    try std.testing.expect(filled > 0);
    try std.testing.expect(empty > 0);
}
