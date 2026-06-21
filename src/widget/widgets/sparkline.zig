const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const theme = @import("../theme.zig");
const accessibility = @import("../accessibility.zig");

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
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.status), "Sparkline", "");
        return self;
    }

    pub fn deinit(self: *Sparkline) void {
        self.values.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn setTheme(self: *Sparkline, theme_value: theme.Theme) !void {
        const next_fg = theme_value.color(.accent);
        const next_bg = theme_value.color(.surface);
        if (std.meta.eql(self.fg, next_fg) and std.meta.eql(self.bg, next_bg)) {
            self.theme_value = theme_value;
            return;
        }

        self.theme_value = theme_value;
        self.fg = next_fg;
        self.bg = next_bg;
        self.widget.markDirty();
    }

    pub fn setMaxSamples(self: *Sparkline, max_samples: usize) void {
        self.max_samples = @max(max_samples, @as(usize, 1));
        if (self.values.items.len > self.max_samples) {
            const trim = self.values.items.len - self.max_samples;
            std.mem.copyForwards(f32, self.values.items[0 .. self.values.items.len - trim], self.values.items[trim..]);
            self.values.shrinkRetainingCapacity(self.max_samples);
            self.widget.markDirty();
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
        self.widget.markDirty();
    }

    pub fn setValues(self: *Sparkline, data: []const f32) !void {
        const count = @min(data.len, self.max_samples);
        if (samplesEqual(self.values.items, data[0..count])) return;

        var next_values = std.ArrayList(f32).empty;
        errdefer next_values.deinit(self.allocator);

        try next_values.appendSlice(self.allocator, data[0..count]);

        self.values.deinit(self.allocator);
        self.values = next_values;
        self.widget.markDirty();
    }

    fn samplesEqual(lhs: []const f32, rhs: []const f32) bool {
        if (lhs.len != rhs.len) return false;
        for (lhs, rhs) |l, r| {
            if (l == r) continue;
            if (std.math.isNan(l) and std.math.isNan(r)) continue;
            return false;
        }
        return true;
    }

    fn addOffsetClamped(origin: u16, offset: u16) u16 {
        const value = @as(u32, origin) + @as(u32, offset);
        return @intCast(@min(value, @as(u32, std.math.maxInt(u16))));
    }

    fn normalizedSample(value: f32, min_val: f32, max_val: f32) f32 {
        if (std.math.isPositiveInf(value)) return 1;
        if (!std.math.isFinite(value)) return 0;

        const range = max_val - min_val;
        if (!std.math.isFinite(range) or range <= 0) return 0;

        const ratio = (value - min_val) / range;
        if (!std.math.isFinite(ratio)) return 0;
        return std.math.clamp(ratio, 0, 1);
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Sparkline = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible) return;
        const rect = self.widget.rect;
        if (rect.width == 0 or rect.height == 0) return;

        // Fill background.
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', self.fg, self.bg, render.Style{});

        if (self.values.items.len == 0) return;

        const min_max = calcRange(self.values.items);
        const min_val = min_max[0];
        const max_val = min_max[1];

        const steps = [_]u21{ '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█' };

        const available_width: usize = @intCast(rect.width);
        var x: usize = 0;
        while (x < available_width) : (x += 1) {
            const sample_index = (x * self.values.items.len) / @max(available_width, 1);
            const clamped_index = @min(sample_index, self.values.items.len - 1);
            const value = self.values.items[clamped_index];
            const normalized = normalizedSample(value, min_val, max_val);
            const step_count: f32 = @floatFromInt(steps.len);
            const level = @min(steps.len - 1, @as(usize, @intFromFloat(@floor(normalized * step_count))));
            const char = steps[level];
            const draw_y = addOffsetClamped(rect.y, rect.height / 2);
            renderer.drawChar(addOffsetClamped(rect.x, @intCast(x)), draw_y, char, self.fg, self.bg, render.Style{});
        }
    }

    fn handleEventFn(_: *anyopaque, _: input.Event) anyerror!bool {
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Sparkline = @fieldParentPtr("widget", widget_ref);
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(_: *anyopaque) anyerror!layout_module.Size {
        return layout_module.Size.init(12, 1);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Sparkline = @fieldParentPtr("widget", widget_ref);
        return self.widget.visible and self.widget.enabled;
    }

    fn calcRange(values: []const f32) [2]f32 {
        var min_val: f32 = 0;
        var max_val: f32 = 0;
        var found_finite = false;

        for (values) |v| {
            if (!std.math.isFinite(v)) continue;
            if (!found_finite) {
                min_val = v;
                max_val = v;
                found_finite = true;
                continue;
            }
            min_val = @min(min_val, v);
            max_val = @max(max_val, v);
        }

        if (!found_finite) return .{ 0, 1 };
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
        if (cell.codepoint() != ' ') {
            non_space += 1;
        }
    }
    try std.testing.expect(non_space > 0);
}

test "sparkline clamps edge draw coordinates" {
    const alloc = std.testing.allocator;
    var spark = try Sparkline.init(alloc);
    defer spark.deinit();

    const samples = [_]f32{ 0.0, 1.0 };
    try spark.setValues(&samples);
    try spark.widget.layout(layout_module.Rect.init(std.math.maxInt(u16), std.math.maxInt(u16), 2, 2));

    var renderer = try render.Renderer.init(alloc, 2, 2);
    defer renderer.deinit();

    try spark.widget.draw(&renderer);

    try std.testing.expectEqual(@as(u21, ' '), renderer.back.getCell(0, 0).codepoint());
    try std.testing.expectEqual(@as(u21, ' '), renderer.back.getCell(1, 1).codepoint());
}

test "sparkline renders non-finite samples deterministically" {
    const alloc = std.testing.allocator;
    var spark = try Sparkline.init(alloc);
    defer spark.deinit();

    const samples = [_]f32{ std.math.nan(f32), std.math.inf(f32), -std.math.inf(f32), 1.0 };
    try spark.setValues(&samples);
    try spark.widget.layout(layout_module.Rect.init(0, 0, 4, 1));

    var renderer = try render.Renderer.init(alloc, 4, 1);
    defer renderer.deinit();

    try spark.widget.draw(&renderer);

    try std.testing.expectEqual(@as(u21, '▁'), renderer.back.getCell(0, 0).*.codepoint());
    try std.testing.expectEqual(@as(u21, '█'), renderer.back.getCell(1, 0).*.codepoint());
    try std.testing.expectEqual(@as(u21, '▁'), renderer.back.getCell(2, 0).*.codepoint());
    try std.testing.expectEqual(@as(u21, '▁'), renderer.back.getCell(3, 0).*.codepoint());
}

test "sparkline marks dirty when samples change" {
    const alloc = std.testing.allocator;
    var spark = try Sparkline.init(alloc);
    defer spark.deinit();

    try spark.widget.layout(layout_module.Rect.init(0, 0, 8, 1));
    var renderer = try render.Renderer.init(alloc, 8, 1);
    defer renderer.deinit();

    try spark.widget.draw(&renderer);
    try std.testing.expect(!spark.widget.dirty);

    try spark.push(1.0);
    try std.testing.expect(spark.widget.dirty);

    try spark.widget.draw(&renderer);
    try std.testing.expect(!spark.widget.dirty);

    const samples = [_]f32{ 2.0, 3.0, 4.0 };
    try spark.setValues(&samples);
    try std.testing.expect(spark.widget.dirty);
}

test "sparkline skips unchanged values without allocating or dirtying" {
    const alloc = std.testing.allocator;
    var spark = try Sparkline.init(alloc);
    defer spark.deinit();

    const samples = [_]f32{ 1.0, std.math.nan(f32), 3.0 };
    try spark.setValues(&samples);
    try spark.widget.layout(layout_module.Rect.init(0, 0, 8, 1));
    var renderer = try render.Renderer.init(alloc, 8, 1);
    defer renderer.deinit();
    try spark.widget.draw(&renderer);
    try std.testing.expect(!spark.widget.dirty);

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = spark.allocator;
    spark.allocator = failing.allocator();
    defer spark.allocator = original_allocator;

    try spark.setValues(&samples);
    try std.testing.expect(!spark.widget.dirty);
    try std.testing.expectEqual(@as(usize, samples.len), spark.values.items.len);
    try std.testing.expectEqual(samples[0], spark.values.items[0]);
    try std.testing.expect(std.math.isNan(spark.values.items[1]));
    try std.testing.expectEqual(samples[2], spark.values.items[2]);
}

test "sparkline setTheme marks dirty only when rendered colors change" {
    const alloc = std.testing.allocator;
    var spark = try Sparkline.init(alloc);
    defer spark.deinit();

    try spark.widget.layout(layout_module.Rect.init(0, 0, 8, 1));
    var renderer = try render.Renderer.init(alloc, 8, 1);
    defer renderer.deinit();
    try spark.widget.draw(&renderer);
    try std.testing.expect(!spark.widget.dirty);

    try spark.setTheme(theme.Theme.dark());
    try std.testing.expect(!spark.widget.dirty);

    try spark.setTheme(theme.Theme.light());
    try std.testing.expect(spark.widget.dirty);
}

test "sparkline marks dirty when max samples trims visible data" {
    const alloc = std.testing.allocator;
    var spark = try Sparkline.init(alloc);
    defer spark.deinit();

    const samples = [_]f32{ 1.0, 2.0, 3.0, 4.0 };
    try spark.setValues(&samples);
    try spark.widget.layout(layout_module.Rect.init(0, 0, 8, 1));

    var renderer = try render.Renderer.init(alloc, 8, 1);
    defer renderer.deinit();
    try spark.widget.draw(&renderer);
    try std.testing.expect(!spark.widget.dirty);

    spark.setMaxSamples(2);
    try std.testing.expect(spark.widget.dirty);
    try std.testing.expectEqualSlices(f32, samples[2..], spark.values.items);
}

test "sparkline leaves dirty state unchanged when max samples does not trim" {
    const alloc = std.testing.allocator;
    var spark = try Sparkline.init(alloc);
    defer spark.deinit();

    try spark.push(1.0);
    try spark.widget.layout(layout_module.Rect.init(0, 0, 8, 1));
    var renderer = try render.Renderer.init(alloc, 8, 1);
    defer renderer.deinit();
    try spark.widget.draw(&renderer);
    try std.testing.expect(!spark.widget.dirty);

    spark.setMaxSamples(16);
    try std.testing.expect(!spark.widget.dirty);
    try std.testing.expectEqual(@as(usize, 16), spark.max_samples);
}

test "sparkline setValues preserves samples on allocation failure" {
    const alloc = std.testing.allocator;
    var spark = try Sparkline.init(alloc);
    defer spark.deinit();

    const stable = [_]f32{ 1.0, 2.0, 3.0 };
    const replacement = [_]f32{ 4.0, 5.0, 6.0, 7.0 };
    try spark.setValues(&stable);

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = spark.allocator;
    spark.allocator = failing.allocator();
    defer spark.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, spark.setValues(&replacement));
    try std.testing.expectEqualSlices(f32, &stable, spark.values.items);
}
