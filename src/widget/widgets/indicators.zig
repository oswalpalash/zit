const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const theme = @import("../theme.zig");
const input = @import("../../input/input.zig");

/// Battery indicator with charge/alert visuals.
pub const BatteryIndicator = struct {
    widget: base.Widget,
    level: f32 = 0.5,
    charging: bool = false,
    theme_value: theme.Theme = theme.Theme.dark(),
    allocator: std.mem.Allocator,

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = preferredFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator) !*BatteryIndicator {
        const self = try allocator.create(BatteryIndicator);
        self.* = .{
            .widget = base.Widget.init(&vtable),
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *BatteryIndicator) void {
        self.allocator.destroy(self);
    }

    pub fn setTheme(self: *BatteryIndicator, t: theme.Theme) void {
        self.theme_value = t;
    }

    pub fn setLevel(self: *BatteryIndicator, level: f32) void {
        self.level = std.math.clamp(level, 0, 1);
    }

    pub fn setCharging(self: *BatteryIndicator, charging: bool) void {
        self.charging = charging;
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*BatteryIndicator, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;

        const rect = self.widget.rect;
        if (rect.width < 6 or rect.height < 3) return;

        const fg = self.theme_value.color(.text);
        const bg = self.theme_value.color(.surface);
        const accent = self.theme_value.color(.accent);
        const warning = self.theme_value.color(.warning);

        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', fg, bg, render.Style{});

        // Main body with a small positive terminal.
        const body_width = rect.width - 2;
        renderer.drawBox(rect.x, rect.y, body_width, rect.height, .single, fg, bg, render.Style{});
        const nub_x = rect.x + body_width;
        const nub_y = rect.y + rect.height / 3;
        renderer.drawVLine(nub_x, nub_y, @max(@as(u16, 1), rect.height / 3), '│', fg, bg, render.Style{ .bold = true });

        const inset_x = rect.x + 1;
        const inset_y = rect.y + 1;
        const inset_w = if (body_width > 2) body_width - 2 else 0;
        const inset_h = if (rect.height > 2) rect.height - 2 else 0;
        if (inset_w == 0 or inset_h == 0) return;

        const charge_color = if (self.level < 0.15) warning else accent;
        const fill_w = @as(u16, @intFromFloat(@round(self.level * @as(f32, @floatFromInt(inset_w)))));
        if (fill_w > 0) {
            renderer.fillRect(inset_x, inset_y, fill_w, inset_h, ' ', fg, charge_color, render.Style{});
        }

        if (self.charging and inset_w > 2 and inset_h > 1) {
            const bolt_x = inset_x + inset_w / 2;
            const bolt_y = inset_y + inset_h / 2;
            renderer.drawChar(bolt_x, bolt_y, '⚡', fg, charge_color, render.Style{ .bold = true });
        }
    }

    fn handleEventFn(_: *anyopaque, _: input.Event) anyerror!bool {
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*BatteryIndicator, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    fn preferredFn(_: *anyopaque) anyerror!layout_module.Size {
        return layout_module.Size.init(12, 3);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*BatteryIndicator, @ptrCast(@alignCast(widget_ptr)));
        return self.widget.enabled and self.widget.visible;
    }
};

/// Wireless signal strength indicator.
pub const SignalStrength = struct {
    widget: base.Widget,
    strength: f32 = 0.5,
    bars: usize = 4,
    theme_value: theme.Theme = theme.Theme.dark(),
    allocator: std.mem.Allocator,

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = preferredFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator) !*SignalStrength {
        const self = try allocator.create(SignalStrength);
        self.* = .{
            .widget = base.Widget.init(&vtable),
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *SignalStrength) void {
        self.allocator.destroy(self);
    }

    pub fn setTheme(self: *SignalStrength, t: theme.Theme) void {
        self.theme_value = t;
    }

    pub fn setStrength(self: *SignalStrength, value: f32) void {
        self.strength = std.math.clamp(value, 0, 1);
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*SignalStrength, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;

        const rect = self.widget.rect;
        if (rect.width == 0 or rect.height == 0) return;

        const fg = self.theme_value.color(.text);
        const bg = self.theme_value.color(.surface);
        const accent = self.theme_value.color(.accent);
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', fg, bg, render.Style{});

        const usable_bars = @max(self.bars, @as(usize, 1));
        const max_height = rect.height;
        const bar_width: u16 = @max(1, rect.width / @as(u16, @intCast(usable_bars)));
        for (0..usable_bars) |i| {
            const threshold = @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(usable_bars));
            const active = self.strength >= threshold - 0.0001;
            const height = @max(@as(u16, 1), @as(u16, @intFromFloat(@floor(@as(f32, @floatFromInt(max_height)) * threshold))));
            const x = rect.x + @as(u16, @intCast(i)) * bar_width;
            const y = rect.y + rect.height - height;
            const color = if (active) accent else fg;
            renderer.fillRect(x, y, bar_width, height, ' ', fg, color, render.Style{});
        }
    }

    fn handleEventFn(_: *anyopaque, _: input.Event) anyerror!bool {
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*SignalStrength, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    fn preferredFn(_: *anyopaque) anyerror!layout_module.Size {
        return layout_module.Size.init(10, 4);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*SignalStrength, @ptrCast(@alignCast(widget_ptr)));
        return self.widget.enabled and self.widget.visible;
    }
};

/// Generic horizontal meter suitable for CPU/memory dashboards.
pub const ResourceMeter = struct {
    widget: base.Widget,
    label: []const u8 = "meter",
    owns_label: bool = false,
    value: f32 = 0.5,
    fg: render.Color = render.Color.named(render.NamedColor.default),
    bg: render.Color = render.Color.named(render.NamedColor.black),
    fill: render.Color = render.Color.named(render.NamedColor.green),
    allocator: std.mem.Allocator,

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = preferredFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator) !*ResourceMeter {
        const self = try allocator.create(ResourceMeter);
        self.* = .{
            .widget = base.Widget.init(&vtable),
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *ResourceMeter) void {
        if (self.owns_label and self.label.len > 0) {
            self.allocator.free(self.label);
        }
        self.allocator.destroy(self);
    }

    pub fn setLabel(self: *ResourceMeter, label: []const u8) !void {
        if (self.owns_label and self.label.len > 0) {
            self.allocator.free(self.label);
        }
        self.label = try self.allocator.dupe(u8, label);
        self.owns_label = true;
    }

    pub fn setValue(self: *ResourceMeter, value: f32) void {
        self.value = std.math.clamp(value, 0, 1);
    }

    pub fn setTheme(self: *ResourceMeter, t: theme.Theme) void {
        self.fg = t.color(.text);
        self.bg = t.color(.surface);
        self.fill = t.color(.accent);
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*ResourceMeter, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;
        const rect = self.widget.rect;
        if (rect.width < 4 or rect.height == 0) return;

        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', self.fg, self.bg, render.Style{});
        const fill_width = @as(u16, @intFromFloat(@round(self.value * @as(f32, @floatFromInt(rect.width)))));
        if (fill_width > 0) {
            renderer.fillRect(rect.x, rect.y, fill_width, rect.height, ' ', self.fg, self.fill, render.Style{});
        }

        var buf: [32]u8 = undefined;
        const percent = @as(u8, @intFromFloat(self.value * 100));
        const text = std.fmt.bufPrint(&buf, "{s}: {d}%", .{ self.label, percent }) catch "meter";
        if (text.len > 0 and rect.height > 0) {
            renderer.drawStr(rect.x + 1, rect.y + rect.height / 2, text[0..@min(text.len, @as(usize, @intCast(rect.width - 2)))], self.fg, self.bg, render.Style{ .bold = true });
        }
    }

    fn handleEventFn(_: *anyopaque, _: input.Event) anyerror!bool {
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*ResourceMeter, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    fn preferredFn(_: *anyopaque) anyerror!layout_module.Size {
        return layout_module.Size.init(18, 3);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*ResourceMeter, @ptrCast(@alignCast(widget_ptr)));
        return self.widget.enabled and self.widget.visible;
    }
};

/// Three-light status indicator.
pub const TrafficLight = struct {
    widget: base.Widget,
    state: State = .green,
    theme_value: theme.Theme = theme.Theme.dark(),
    allocator: std.mem.Allocator,

    pub const State = enum { red, yellow, green };

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = preferredFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator) !*TrafficLight {
        const self = try allocator.create(TrafficLight);
        self.* = .{
            .widget = base.Widget.init(&vtable),
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *TrafficLight) void {
        self.allocator.destroy(self);
    }

    pub fn setTheme(self: *TrafficLight, t: theme.Theme) void {
        self.theme_value = t;
    }

    pub fn setState(self: *TrafficLight, state: State) void {
        self.state = state;
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*TrafficLight, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;
        const rect = self.widget.rect;
        if (rect.width < 5 or rect.height < 3) return;

        const fg = self.theme_value.color(.text);
        const bg = self.theme_value.color(.surface);
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', fg, bg, render.Style{});

        const colors = [_]render.Color{
            self.theme_value.color(.danger),
            self.theme_value.color(.warning),
            self.theme_value.color(.success),
        };

        const active_idx: usize = switch (self.state) {
            .red => 0,
            .yellow => 1,
            .green => 2,
        };

        const spacing = rect.width / 3;
        var i: usize = 0;
        while (i < 3) : (i += 1) {
            const center_x = rect.x + spacing * @as(u16, @intCast(i)) + spacing / 2;
            const center_y = rect.y + rect.height / 2;
            const color = if (i == active_idx) colors[i] else self.theme_value.color(.muted);
            renderer.drawChar(center_x, center_y, '●', color, bg, render.Style{ .bold = i == active_idx });
        }
    }

    fn handleEventFn(_: *anyopaque, _: input.Event) anyerror!bool {
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*TrafficLight, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    fn preferredFn(_: *anyopaque) anyerror!layout_module.Size {
        return layout_module.Size.init(12, 3);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*TrafficLight, @ptrCast(@alignCast(widget_ptr)));
        return self.widget.enabled and self.widget.visible;
    }
};

test "battery indicator renders fill" {
    const alloc = std.testing.allocator;
    var battery = try BatteryIndicator.init(alloc);
    defer battery.deinit();

    battery.setLevel(0.8);
    try battery.widget.layout(layout_module.Rect.init(0, 0, 14, 4));

    var renderer = try render.Renderer.init(alloc, 14, 4);
    defer renderer.deinit();
    try battery.widget.draw(&renderer);

    var filled: usize = 0;
    for (0..14) |x| {
        for (0..4) |y| {
            const cell = renderer.back.getCell(@intCast(x), @intCast(y)).*;
            if (cell.bg != render.Color.named(render.NamedColor.default)) filled += 1;
        }
    }
    try std.testing.expect(filled > 0);
}

test "signal strength paints multiple bars" {
    const alloc = std.testing.allocator;
    var signal = try SignalStrength.init(alloc);
    defer signal.deinit();

    signal.setStrength(0.75);
    try signal.widget.layout(layout_module.Rect.init(0, 0, 12, 4));

    var renderer = try render.Renderer.init(alloc, 12, 4);
    defer renderer.deinit();
    try signal.widget.draw(&renderer);

    var bars: usize = 0;
    for (0..12) |x| {
        for (0..4) |y| {
            const cell = renderer.back.getCell(@intCast(x), @intCast(y)).*;
            if (cell.bg != render.Color.named(render.NamedColor.default)) bars += 1;
        }
    }
    try std.testing.expect(bars > 0);
}

test "resource meter writes label text" {
    const alloc = std.testing.allocator;
    var meter = try ResourceMeter.init(alloc);
    defer meter.deinit();

    try meter.setLabel("CPU");
    meter.setValue(0.42);
    try meter.widget.layout(layout_module.Rect.init(0, 0, 18, 3));

    var renderer = try render.Renderer.init(alloc, 18, 3);
    defer renderer.deinit();
    try meter.widget.draw(&renderer);

    var seen_c: bool = false;
    for (0..18) |x| {
        const cell = renderer.back.getCell(@intCast(x), 1).*;
        if (cell.ch == 'C') seen_c = true;
    }
    try std.testing.expect(seen_c);
}

test "traffic light highlights active color" {
    const alloc = std.testing.allocator;
    var light = try TrafficLight.init(alloc);
    defer light.deinit();

    light.setState(.yellow);
    try light.widget.layout(layout_module.Rect.init(0, 0, 12, 3));

    var renderer = try render.Renderer.init(alloc, 12, 3);
    defer renderer.deinit();
    try light.widget.draw(&renderer);

    var highlighted: usize = 0;
    for (0..12) |x| {
        for (0..3) |y| {
            const cell = renderer.back.getCell(@intCast(x), @intCast(y)).*;
            if (cell.ch == '●') highlighted += 1;
        }
    }
    try std.testing.expect(highlighted > 0);
}
