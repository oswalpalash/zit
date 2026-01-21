const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const theme = @import("../theme.zig");

/// Minimal-yet-solid charting primitives for dashboards: bar, line, and area.
pub const ChartType = enum { bar, line, area };

pub const Series = struct {
    label: []u8,
    values: std.ArrayList(f32),
    color: render.Color,
    fill: render.Color,
};

pub const Chart = struct {
    widget: base.Widget,
    chart_type: ChartType = .line,
    series: std.ArrayList(Series),
    allocator: std.mem.Allocator,
    theme_value: theme.Theme,
    padding: u16 = 1,
    show_axes: bool = true,

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator) !*Chart {
        const default_theme = theme.Theme.dark();
        const self = try allocator.create(Chart);
        self.* = Chart{
            .widget = base.Widget.init(&vtable),
            .chart_type = .line,
            .series = try std.ArrayList(Series).initCapacity(allocator, 0),
            .allocator = allocator,
            .theme_value = default_theme,
            .padding = 1,
            .show_axes = true,
        };
        return self;
    }

    pub fn deinit(self: *Chart) void {
        for (self.series.items) |*s| {
            self.allocator.free(s.label);
            s.values.deinit(self.allocator);
        }
        self.series.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn setTheme(self: *Chart, t: theme.Theme) !void {
        self.theme_value = t;
    }

    pub fn setType(self: *Chart, chart_type: ChartType) void {
        self.chart_type = chart_type;
    }

    pub fn setPadding(self: *Chart, padding: u16) void {
        self.padding = padding;
    }

    pub fn setShowAxes(self: *Chart, show_axes: bool) void {
        self.show_axes = show_axes;
    }

    pub fn addSeries(self: *Chart, label: []const u8, values: []const f32, color: ?render.Color, fill: ?render.Color) !void {
        const series_label = try self.allocator.dupe(u8, label);
        var copied_values = try std.ArrayList(f32).initCapacity(self.allocator, values.len);
        try copied_values.appendSlice(self.allocator, values);

        const palette_color = color orelse self.theme_value.color(.accent);
        const fill_color = fill orelse palette_color;

        const s = Series{
            .label = series_label,
            .values = copied_values,
            .color = palette_color,
            .fill = fill_color,
        };

        try self.series.append(self.allocator, s);
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*Chart, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;

        const rect = self.widget.rect;
        if (rect.width == 0 or rect.height == 0) return;

        const bg = self.theme_value.color(.surface);
        const fg = self.theme_value.color(.text);
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', fg, bg, render.Style{});

        if (self.series.items.len == 0 or self.maxSampleCount() == 0) return;

        const inner = self.innerRect(rect);
        if (inner.width == 0 or inner.height == 0) return;

        if (self.show_axes) {
            self.drawAxes(renderer, inner, fg, bg);
        }

        switch (self.chart_type) {
            .bar => self.drawBars(renderer, inner),
            .line => self.drawLines(renderer, inner, false),
            .area => self.drawLines(renderer, inner, true),
        }
    }

    fn drawAxes(self: *Chart, renderer: *render.Renderer, inner: layout_module.Rect, fg: render.Color, bg: render.Color) void {
        _ = self;
        if (inner.height <= 1 or inner.width <= 1) return;
        const axis_style = render.Style{ .bold = true };
        renderer.drawHLine(inner.x, inner.y + inner.height - 1, inner.width, '─', fg, bg, axis_style);
        renderer.drawVLine(inner.x, inner.y, inner.height, '│', fg, bg, axis_style);
        renderer.drawChar(inner.x, inner.y + inner.height - 1, '└', fg, bg, axis_style);
    }

    fn drawBars(self: *Chart, renderer: *render.Renderer, inner: layout_module.Rect) void {
        const sample_count = self.maxSampleCount();
        if (sample_count == 0) return;
        const bar_width: u16 = @max(1, inner.width / @as(u16, @intCast(sample_count)));
        if (bar_width == 0 or inner.height == 0) return;

        const value_range = self.valueRange(true);
        if (value_range.max == 0 and value_range.min == 0) return;

        for (0..sample_count) |sample_idx| {
            const x_start = inner.x + @as(u16, @intCast(sample_idx)) * bar_width;
            const x_end = @min(x_start + bar_width, inner.x + inner.width);
            const stacked_max = self.sumAt(sample_idx);
            if (stacked_max <= 0) continue;

            var filled_height: u16 = 0;
            for (self.series.items) |s| {
                const value = if (sample_idx < s.values.items.len) s.values.items[sample_idx] else 0;
                if (value <= 0) continue;

                const proportional = if (value_range.max == 0) 0 else value / value_range.max;
                const desired_height = @as(u16, @intCast(@round(proportional * @as(f32, @floatFromInt(inner.height)))));
                const h: u16 = @max(1, @min(desired_height, inner.height));

                var remaining: u16 = h;
                var y = inner.y + inner.height - 1 - filled_height;
                while (remaining > 0 and y >= inner.y) : (y -= 1) {
                    for (x_start..x_end) |x| {
                        renderer.drawChar(@intCast(x), y, '█', s.color, self.theme_value.color(.surface), render.Style{});
                    }
                    remaining -= 1;
                    if (y == inner.y) break;
                }

                filled_height = @min(inner.height - 1, filled_height + h);
                if (filled_height >= inner.height) break;
            }
        }
    }

    fn drawLines(self: *Chart, renderer: *render.Renderer, inner: layout_module.Rect, fill: bool) void {
        const sample_count = self.maxSampleCount();
        if (sample_count == 0 or inner.height == 0 or inner.width == 0) return;

        const value_range = self.valueRange(false);
        const denom: f32 = if (value_range.max - value_range.min == 0) 1 else value_range.max - value_range.min;

        const axis_height: f32 = @floatFromInt(inner.height - 1);

        for (self.series.items) |s| {
            var prev_y: ?u16 = null;
            var prev_x: ?u16 = null;

            var x: u16 = 0;
            while (x < inner.width) : (x += 1) {
                const sample_idx = self.sampleIndexForColumn(x, inner.width, s.values.items.len);
                const v = s.values.items[sample_idx];
                const normalized = (v - value_range.min) / denom;
                const y = inner.y + inner.height - 1 - @as(u16, @intCast(@round(normalized * axis_height)));
                const draw_x = inner.x + x;

                if (fill) {
                    var row: u16 = y;
                    while (row < inner.y + inner.height) : (row += 1) {
                        renderer.drawChar(draw_x, row, ' ', render.Color.named(render.NamedColor.default), s.fill, render.Style{});
                    }
                }

                renderer.drawChar(draw_x, y, '•', s.color, self.theme_value.color(.surface), render.Style{ .bold = true });

                if (prev_y) |py| {
                    const start = @min(py, y);
                    const end = @max(py, y);
                    var row = start;
                    while (row <= end) : (row += 1) {
                        renderer.drawChar(draw_x, row, '│', s.color, self.theme_value.color(.surface), render.Style{});
                    }
                    if (prev_x) |px| {
                        const span_start = @min(px, draw_x);
                        const span_end = @max(px, draw_x);
                        if (span_end > span_start + 1) {
                            renderer.drawHLine(span_start + 1, y, span_end - span_start - 1, '─', s.color, self.theme_value.color(.surface), render.Style{});
                        }
                    }
                }

                prev_y = y;
                prev_x = draw_x;
            }
        }
    }

    fn handleEventFn(_: *anyopaque, _: input.Event) anyerror!bool {
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*Chart, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(_: *anyopaque) anyerror!layout_module.Size {
        return layout_module.Size.init(32, 8);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*Chart, @ptrCast(@alignCast(widget_ptr)));
        return self.widget.visible and self.widget.enabled;
    }

    fn innerRect(self: *Chart, rect: layout_module.Rect) layout_module.Rect {
        const pad = self.padding;
        const padded_width = if (rect.width > pad * 2) rect.width - pad * 2 else 0;
        const padded_height = if (rect.height > pad * 2) rect.height - pad * 2 else 0;

        return layout_module.Rect.init(rect.x + pad, rect.y + pad, padded_width, padded_height);
    }

    fn maxSampleCount(self: *const Chart) usize {
        var max_len: usize = 0;
        for (self.series.items) |s| {
            max_len = @max(max_len, s.values.items.len);
        }
        return max_len;
    }

    fn sumAt(self: *const Chart, idx: usize) f32 {
        var total: f32 = 0;
        for (self.series.items) |s| {
            if (idx < s.values.items.len) {
                total += s.values.items[idx];
            }
        }
        return total;
    }

    const Range = struct { min: f32, max: f32 };

    fn valueRange(self: *const Chart, stacked: bool) Range {
        var min_v: f32 = 0;
        var max_v: f32 = 0;

        if (stacked) {
            const count = self.maxSampleCount();
            for (0..count) |i| {
                const total = self.sumAt(i);
                min_v = @min(min_v, total);
                max_v = @max(max_v, total);
            }
        } else {
            for (self.series.items) |s| {
                for (s.values.items) |v| {
                    min_v = @min(min_v, v);
                    max_v = @max(max_v, v);
                }
            }
        }

        if (max_v == min_v) {
            max_v = min_v + 1;
        }

        return Range{ .min = min_v, .max = max_v };
    }

    fn sampleIndexForColumn(_: *const Chart, x: u16, width: u16, count: usize) usize {
        if (width == 0 or count == 0) return 0;
        const scaled = @as(usize, @intCast(x)) * count / @max(@as(usize, @intCast(width)), 1);
        return @min(scaled, count - 1);
    }
};

test "chart renders stacked bars" {
    const alloc = std.testing.allocator;
    var chart = try Chart.init(alloc);
    defer chart.deinit();
    chart.setType(.bar);

    try chart.addSeries("a", &[_]f32{ 1, 2, 3 }, null, null);
    try chart.addSeries("b", &[_]f32{ 1, 1, 1 }, null, null);

    try chart.widget.layout(layout_module.Rect.init(0, 0, 12, 6));

    var renderer = try render.Renderer.init(alloc, 12, 6);
    defer renderer.deinit();

    try chart.widget.draw(&renderer);

    var painted: usize = 0;
    for (0..12) |x| {
        for (0..6) |y| {
            const cell = renderer.back.getCell(@intCast(x), @intCast(y));
            if (cell.fg != render.Color.named(render.NamedColor.default) or cell.bg != render.Color.named(render.NamedColor.default)) {
                painted += 1;
            }
        }
    }
    try std.testing.expect(painted > 0);
}

test "chart renders area fill" {
    const alloc = std.testing.allocator;
    var chart = try Chart.init(alloc);
    defer chart.deinit();
    chart.setType(.area);

    try chart.addSeries("trend", &[_]f32{ 0, 1, 0.5, 1.5 }, null, null);
    try chart.widget.layout(layout_module.Rect.init(0, 0, 10, 6));

    var renderer = try render.Renderer.init(alloc, 10, 6);
    defer renderer.deinit();

    try chart.widget.draw(&renderer);

    var filled: usize = 0;
    for (0..10) |x| {
        for (0..6) |y| {
            const cell = renderer.back.getCell(@intCast(x), @intCast(y));
            if (cell.bg != render.Color.named(render.NamedColor.default)) {
                filled += 1;
            }
        }
    }
    try std.testing.expect(filled > 0);
}
