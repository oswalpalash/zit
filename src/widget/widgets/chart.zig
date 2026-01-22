const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const theme = @import("../theme.zig");

/// Minimal-yet-solid charting primitives for dashboards: bar, line, area, and more.
pub const ChartType = enum { bar, stacked_bar, line, area, pie, scatter };

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
    x_axis_label: ?[]u8 = null,
    y_axis_label: ?[]u8 = null,
    show_legend: bool = true,

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
            .x_axis_label = null,
            .y_axis_label = null,
            .show_legend = true,
        };
        return self;
    }

    pub fn deinit(self: *Chart) void {
        for (self.series.items) |*s| {
            self.allocator.free(s.label);
            s.values.deinit(self.allocator);
        }
        self.series.deinit(self.allocator);
        if (self.x_axis_label) |label| self.allocator.free(label);
        if (self.y_axis_label) |label| self.allocator.free(label);
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

    pub fn setAxisLabels(self: *Chart, x_label: ?[]const u8, y_label: ?[]const u8) !void {
        if (self.x_axis_label) |label| self.allocator.free(label);
        if (self.y_axis_label) |label| self.allocator.free(label);
        self.x_axis_label = if (x_label) |text| try self.allocator.dupe(u8, text) else null;
        self.y_axis_label = if (y_label) |text| try self.allocator.dupe(u8, text) else null;
    }

    pub fn setShowLegend(self: *Chart, show: bool) void {
        self.show_legend = show;
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
            .bar => self.drawBars(renderer, inner, false),
            .stacked_bar => self.drawBars(renderer, inner, true),
            .line => self.drawLines(renderer, inner, false),
            .area => self.drawLines(renderer, inner, true),
            .pie => self.drawPie(renderer, inner),
            .scatter => self.drawScatter(renderer, inner),
        }

        if (self.show_legend and self.series.items.len > 0) {
            self.drawLegend(renderer, inner, fg);
        }
    }

    fn drawAxes(self: *Chart, renderer: *render.Renderer, inner: layout_module.Rect, fg: render.Color, bg: render.Color) void {
        if (inner.height <= 1 or inner.width <= 1) return;
        const axis_style = render.Style{ .bold = true };
        renderer.drawHLine(inner.x, inner.y + inner.height - 1, inner.width, '─', fg, bg, axis_style);
        renderer.drawVLine(inner.x, inner.y, inner.height, '│', fg, bg, axis_style);
        renderer.drawChar(inner.x, inner.y + inner.height - 1, '└', fg, bg, axis_style);

        if (self.x_axis_label) |label| {
            const label_y = inner.y + inner.height;
            const max_width = (inner.width + self.padding * 2);
            if (label_y < self.widget.rect.y + self.widget.rect.height and max_width > 0) {
                const start_x = inner.x + (inner.width - @as(u16, @intCast(@min(label.len, max_width)))) / 2;
                renderer.drawStr(start_x, label_y, label, fg, bg, render.Style{ .bold = true });
            }
        }

        if (self.y_axis_label) |label| {
            if (inner.x > 0 and inner.height > 0) {
                const start_y = inner.y;
                for (label, 0..) |char, i| {
                    if (start_y + @as(u16, @intCast(i)) >= inner.y + inner.height) break;
                    renderer.drawChar(inner.x - 1, start_y + @as(u16, @intCast(i)), char, fg, bg, render.Style{ .bold = true });
                }
            }
        }
    }

    fn drawBars(self: *Chart, renderer: *render.Renderer, inner: layout_module.Rect, stacked: bool) void {
        const sample_count = self.maxSampleCount();
        if (sample_count == 0) return;
        const bar_width: u16 = @max(1, inner.width / @as(u16, @intCast(sample_count)));
        if (bar_width == 0 or inner.height == 0) return;

        const value_range = self.valueRange(stacked);
        if (value_range.max == 0 and value_range.min == 0) return;

        for (0..sample_count) |sample_idx| {
            const x_start = inner.x + @as(u16, @intCast(sample_idx)) * bar_width;
            const x_end = @min(x_start + bar_width, inner.x + inner.width);
            if (stacked) {
                const stacked_max = self.sumAt(sample_idx);
                if (stacked_max <= 0) continue;

                var filled_height: u16 = 0;
                for (self.series.items) |s| {
                    const value = if (sample_idx < s.values.items.len) s.values.items[sample_idx] else 0;
                    if (value <= 0) continue;

                    const proportional = if (value_range.max == 0) 0 else value / value_range.max;
                    const desired_height = @as(u16, @intFromFloat(@round(proportional * @as(f32, @floatFromInt(inner.height)))));
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
            } else {
                const series_count = @max(self.series.items.len, 1);
                const segment_width = @max(@as(u16, 1), bar_width / @as(u16, @intCast(series_count)));
                var series_idx: usize = 0;
                for (self.series.items) |s| {
                    const value = if (sample_idx < s.values.items.len) s.values.items[sample_idx] else 0;
                    if (value <= 0) {
                        series_idx += 1;
                        continue;
                    }

                    const proportional = if (value_range.max == 0) 0 else (value - value_range.min) / (value_range.max - value_range.min);
                    const desired_height = @as(u16, @intFromFloat(@round(proportional * @as(f32, @floatFromInt(inner.height)))));
                    const h: u16 = @max(1, @min(desired_height, inner.height));

                    const series_start = x_start + @as(u16, @intCast(series_idx)) * segment_width;
                    const series_end = @min(series_start + segment_width, x_end);

                    var remaining: u16 = h;
                    var y = inner.y + inner.height - 1;
                    while (remaining > 0 and y >= inner.y) : (y -= 1) {
                        for (series_start..series_end) |x| {
                            renderer.drawChar(@intCast(x), y, '█', s.color, self.theme_value.color(.surface), render.Style{});
                        }
                        remaining -= 1;
                        if (y == inner.y) break;
                    }
                    series_idx += 1;
                }
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
                const y = inner.y + inner.height - 1 - @as(u16, @intFromFloat(@round(normalized * axis_height)));
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

    fn drawScatter(self: *Chart, renderer: *render.Renderer, inner: layout_module.Rect) void {
        const sample_count = self.maxSampleCount();
        if (sample_count == 0 or inner.height == 0 or inner.width == 0) return;

        const value_range = self.valueRange(false);
        const denom: f32 = if (value_range.max - value_range.min == 0) 1 else value_range.max - value_range.min;
        const axis_height: f32 = @floatFromInt(inner.height - 1);

        for (self.series.items) |s| {
            for (0..inner.width) |col| {
                const sample_idx = self.sampleIndexForColumn(@intCast(col), inner.width, s.values.items.len);
                const v = s.values.items[sample_idx];
                const normalized = (v - value_range.min) / denom;
                const y = inner.y + inner.height - 1 - @as(u16, @intFromFloat(@round(normalized * axis_height)));
                const draw_x = inner.x + @as(u16, @intCast(col));
                renderer.drawChar(draw_x, y, '◆', s.color, self.theme_value.color(.surface), render.Style{ .bold = true });
            }
        }
    }

    fn drawPie(self: *Chart, renderer: *render.Renderer, inner: layout_module.Rect) void {
        if (self.series.items.len == 0 or inner.width == 0 or inner.height == 0) return;

        var totals = std.ArrayList(f32).empty;
        defer totals.deinit(self.allocator);
        totals.ensureTotalCapacityPrecise(self.allocator, self.series.items.len) catch return;
        var total_sum: f32 = 0;
        for (self.series.items) |s| {
            var subtotal: f32 = 0;
            for (s.values.items) |v| subtotal += v;
            totals.appendAssumeCapacity(subtotal);
            total_sum += subtotal;
        }
        if (total_sum == 0) return;

        const center_x: f32 = @as(f32, @floatFromInt(inner.x)) + @as(f32, @floatFromInt(inner.width)) / 2.0;
        const center_y: f32 = @as(f32, @floatFromInt(inner.y)) + @as(f32, @floatFromInt(inner.height)) / 2.0;
        const radius: f32 = @as(f32, @floatFromInt(@min(inner.width, inner.height))) / 2.2;

        // Precompute slice thresholds
        var cumulative: f32 = 0;
        var thresholds = std.ArrayList(f32).empty;
        thresholds.ensureTotalCapacityPrecise(self.allocator, totals.items.len) catch return;
        defer thresholds.deinit(self.allocator);
        for (totals.items) |slice_total| {
            cumulative += slice_total / total_sum;
            thresholds.appendAssumeCapacity(cumulative);
        }

        var y: u16 = inner.y;
        while (y < inner.y + inner.height) : (y += 1) {
            var x: u16 = inner.x;
            while (x < inner.x + inner.width) : (x += 1) {
                const dx = @as(f64, @floatFromInt(x)) - @as(f64, center_x);
                const dy = @as(f64, @floatFromInt(y)) - @as(f64, center_y);
                const distance = std.math.sqrt(dx * dx + dy * dy);
                if (distance > radius) continue;

                const angle = std.math.atan2(dy, dx);
                const normalized_angle = if (angle < 0) (angle + std.math.tau) / std.math.tau else angle / std.math.tau;

                var slice_index: usize = thresholds.items.len - 1;
                for (thresholds.items, 0..) |t, i| {
                    if (normalized_angle <= t) {
                        slice_index = i;
                        break;
                    }
                }

                const color = self.series.items[slice_index].color;
                renderer.drawChar(x, y, ' ', render.Color.named(render.NamedColor.default), color, render.Style{ .bold = true });
            }
        }
    }

    fn drawLegend(self: *Chart, renderer: *render.Renderer, inner: layout_module.Rect, fg: render.Color) void {
        if (inner.width < 10 or inner.height < 3 or self.series.items.len == 0) return;
        var longest: usize = 0;
        for (self.series.items) |s| {
            longest = @max(longest, s.label.len);
        }
        const legend_width: u16 = @min(inner.width, @as(u16, @intCast(longest + 6)));
        const legend_height: u16 = @min(@as(u16, @intCast(self.series.items.len)), inner.height);
        const start_x = inner.x + inner.width - legend_width;
        const start_y = inner.y;
        const bg = self.theme_value.color(.surface);

        renderer.drawBox(start_x, start_y, legend_width, legend_height, .single, fg, bg, render.Style{});

        for (self.series.items, 0..) |s, idx| {
            if (idx >= legend_height) break;
            const row_y = start_y + @as(u16, @intCast(idx));
            renderer.drawChar(start_x + 1, row_y, '■', s.color, bg, render.Style{ .bold = true });
            const available = legend_width - 3;
            const label_slice = s.label[0..@min(s.label.len, @as(usize, @intCast(available)))];
            renderer.drawStr(start_x + 3, row_y, label_slice, fg, bg, render.Style{});
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
        const axis_pad_left: u16 = self.padding + @as(u16, if (self.y_axis_label != null) 2 else 0);
        const axis_pad_bottom: u16 = self.padding + @as(u16, if (self.x_axis_label != null) 1 else 0);
        const pad_right = self.padding;
        const pad_top = self.padding;

        const padded_width = if (rect.width > axis_pad_left + pad_right) rect.width - axis_pad_left - pad_right else 0;
        const padded_height = if (rect.height > pad_top + axis_pad_bottom) rect.height - pad_top - axis_pad_bottom else 0;

        return layout_module.Rect.init(rect.x + axis_pad_left, rect.y + pad_top, padded_width, padded_height);
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
    chart.setType(.stacked_bar);

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

test "chart renders pie slices" {
    const alloc = std.testing.allocator;
    var chart = try Chart.init(alloc);
    defer chart.deinit();
    chart.setType(.pie);

    try chart.addSeries("one", &[_]f32{ 2, 2 }, null, null);
    try chart.addSeries("two", &[_]f32{ 3, 1 }, null, null);
    try chart.widget.layout(layout_module.Rect.init(0, 0, 12, 12));

    var renderer = try render.Renderer.init(alloc, 12, 12);
    defer renderer.deinit();

    try chart.widget.draw(&renderer);

    var colored: usize = 0;
    for (0..12) |x| {
        for (0..12) |y| {
            const cell = renderer.back.getCell(@intCast(x), @intCast(y));
            if (!std.meta.eql(cell.bg, render.Color.named(render.NamedColor.default))) {
                colored += 1;
            }
        }
    }
    try std.testing.expect(colored > 0);
}

test "chart draws scatter points with legend and labels" {
    const alloc = std.testing.allocator;
    var chart = try Chart.init(alloc);
    defer chart.deinit();
    chart.setType(.scatter);
    try chart.setAxisLabels("x", "y");

    try chart.addSeries("s", &[_]f32{ 0, 1, 2, 3 }, null, null);
    try chart.widget.layout(layout_module.Rect.init(0, 0, 16, 8));

    var renderer = try render.Renderer.init(alloc, 16, 8);
    defer renderer.deinit();

    try chart.widget.draw(&renderer);

    var markers: usize = 0;
    var found_label = false;
    for (0..16) |x| {
        for (0..8) |y| {
            const cell = renderer.back.getCell(@intCast(x), @intCast(y)).*;
            if (cell.ch == '◆') markers += 1;
            if (cell.ch == 'x') found_label = true;
        }
    }
    try std.testing.expect(markers > 0);
    try std.testing.expect(found_label);
}

test "chart fills background when empty" {
    const alloc = std.testing.allocator;
    var chart = try Chart.init(alloc);
    defer chart.deinit();

    try chart.widget.layout(layout_module.Rect.init(0, 0, 6, 3));

    var renderer = try render.Renderer.init(alloc, 6, 3);
    defer renderer.deinit();
    try chart.widget.draw(&renderer);

    const cell = renderer.back.getCell(0, 0).*;
    try std.testing.expect(std.meta.eql(cell.bg, chart.theme_value.color(.surface)));
}
