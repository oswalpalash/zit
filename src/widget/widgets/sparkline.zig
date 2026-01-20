const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const theme = @import("../theme.zig");

/// Tiny sparkline chart for quick trend visualization.
pub const Sparkline = struct {
    widget: base.Widget,
    values: std.ArrayList(f32),
    max_samples: usize = 64,
    fg: render.Color,
    bg: render.Color,
    theme_value: theme.Theme,
    allocator: std.mem.Allocator,

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator) !*Sparkline {
        const self = try allocator.create(Sparkline);
        const default_theme = theme.Theme.dark();
        self.* = Sparkline{
            .widget = base.Widget.init(&vtable),
            .values = std.ArrayList(f32).empty,
            .fg = default_theme.color(.accent),
            .bg = default_theme.color(.surface),
            .theme_value = default_theme,
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *Sparkline) void {
        self.values.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn setTheme(self: *Sparkline, theme_value: theme.Theme) void {
        self.theme_value = theme_value;
        self.fg = theme_value.color(.accent);
        self.bg = theme_value.color(.surface);
    }

    pub fn setMaxSamples(self: *Sparkline, max_samples: usize) void {
        self.max_samples = @max(max_samples, @as(usize, 1));
        if (self.values.items.len > self.max_samples) {
            const trim = self.values.items.len - self.max_samples;
            std.mem.copyForwards(f32, self.values.items[0 .. self.values.items.len - trim], self.values.items[trim..]);
            self.values.shrinkRetainingCapacity(self.max_samples);
        }
    }

    pub fn push(self: *Sparkline, value: f32) !void {
        if (self.values.items.len >= self.max_samples) {
            // Drop the oldest sample.
            std.mem.copyForwards(f32, self.values.items[0 .. self.values.items.len - 1], self.values.items[1..]);
            self.values.items[self.values.items.len - 1] = value;
        } else {
            try self.values.append(self.allocator, value);
        }
    }

    pub fn setValues(self: *Sparkline, data: []const f32) !void {
        self.values.clearRetainingCapacity();
        const count = @min(data.len, self.max_samples);
        try self.values.appendSlice(self.allocator, data[0..count]);
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*Sparkline, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;
        const rect = self.widget.rect;
        if (rect.width == 0 or rect.height == 0) return;

        // Fill background.
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', self.fg, self.bg, render.Style{});

        if (self.values.items.len == 0) return;

        const min_max = calcRange(self.values.items);
        const min_val = min_max[0];
        const max_val = min_max[1];
        const range: f32 = if (max_val - min_val == 0) 1 else max_val - min_val;

        const steps = [_]u21{ '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█' };

        const available_width: usize = @intCast(rect.width);
        var x: usize = 0;
        while (x < available_width) : (x += 1) {
            const sample_index = (x * self.values.items.len) / @max(available_width, 1);
            const clamped_index = @min(sample_index, self.values.items.len - 1);
            const value = self.values.items[clamped_index];
            const normalized = (value - min_val) / range;
            const step_count: f32 = @floatFromInt(steps.len);
            const level = @min(steps.len - 1, @as(usize, @intFromFloat(@floor(normalized * step_count))));
            const char = steps[level];
            const draw_y = rect.y + rect.height / 2;
            renderer.drawChar(rect.x + @as(u16, @intCast(x)), draw_y, char, self.fg, self.bg, render.Style{});
        }
    }

    fn handleEventFn(_: *anyopaque, _: input.Event) anyerror!bool {
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*Sparkline, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(_: *anyopaque) anyerror!layout_module.Size {
        return layout_module.Size.init(12, 1);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*Sparkline, @ptrCast(@alignCast(widget_ptr)));
        return self.widget.visible and self.widget.enabled;
    }

    fn calcRange(values: []const f32) [2]f32 {
        var min_val = values[0];
        var max_val = values[0];
        for (values[1..]) |v| {
            min_val = @min(min_val, v);
            max_val = @max(max_val, v);
        }
        return .{ min_val, max_val };
    }
};

test "sparkline draws samples" {
    const alloc = std.testing.allocator;
    var spark = try Sparkline.init(alloc);
    defer spark.deinit();

    const samples = [_]f32{ 0.0, 0.5, 1.0, 0.25, 0.75 };
    try spark.setValues(&samples);
    try spark.widget.layout(layout_module.Rect.init(0, 0, 8, 1));

    var renderer = try render.Renderer.init(alloc, 8, 2);
    defer renderer.deinit();

    try spark.widget.draw(&renderer);

    var non_space: usize = 0;
    for (0..8) |x| {
        const cell = renderer.back.getCell(@intCast(x), 0).*;
        if (cell.char != ' ') {
            non_space += 1;
        }
    }
    try std.testing.expect(non_space > 0);
}
