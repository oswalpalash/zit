const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const testing = @import("../../testing/testing.zig");

/// Toggle switch renders a compact on/off control with keyboard and mouse support.
pub const ToggleSwitch = struct {
    widget: base.Widget,
    label: []const u8,
    on: bool = false,
    on_fg: render.Color = render.Color.named(render.NamedColor.black),
    on_bg: render.Color = render.Color.named(render.NamedColor.green),
    off_fg: render.Color = render.Color.named(render.NamedColor.black),
    off_bg: render.Color = render.Color.named(render.NamedColor.bright_black),
    track_style: render.Style = render.Style{},
    on_toggle: ?*const fn (bool) void = null,
    allocator: std.mem.Allocator,

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator, label: []const u8) !*ToggleSwitch {
        const self = try allocator.create(ToggleSwitch);
        self.* = ToggleSwitch{
            .widget = base.Widget.init(&vtable),
            .label = try allocator.dupe(u8, label),
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *ToggleSwitch) void {
        self.allocator.free(self.label);
        self.allocator.destroy(self);
    }

    pub fn set(self: *ToggleSwitch, value: bool) void {
        if (self.on != value) {
            self.on = value;
            if (self.on_toggle) |cb| cb(self.on);
        }
    }

    pub fn toggle(self: *ToggleSwitch) void {
        self.set(!self.on);
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*ToggleSwitch, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;

        const rect = self.widget.rect;
        const fg = if (self.on) self.on_fg else self.off_fg;
        const bg = if (self.on) self.on_bg else self.off_bg;

        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', fg, bg, self.track_style);

        // Switch pill representation: [ ON ]
        const pill_width: u16 = 6;
        const pill_x = rect.x;
        renderer.drawChar(pill_x, rect.y, '[', fg, bg, self.track_style);
        renderer.drawChar(pill_x + pill_width - 1, rect.y, ']', fg, bg, self.track_style);
        const text = if (self.on) " ON " else " OFF";
        renderer.drawStr(pill_x + 1, rect.y, text, fg, bg, render.Style{ .bold = true });

        if (rect.width > pill_width and self.label.len > 0) {
            const available = rect.width - pill_width - 1;
            if (available > 0) {
                const draw_text = self.label[0..@min(self.label.len, available)];
                renderer.drawStr(pill_x + pill_width + 1, rect.y, draw_text, fg, bg, self.track_style);
            }
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*ToggleSwitch, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible or !self.widget.enabled) return false;

        switch (event) {
            .mouse => |mouse| {
                if (mouse.action == .press and mouse.button == 1 and self.widget.rect.contains(mouse.x, mouse.y)) {
                    self.toggle();
                    return true;
                }
            },
            .key => |key| {
                if (self.widget.focused and (key.key == ' ' or key.key == '\n')) {
                    self.toggle();
                    return true;
                }
            },
            else => {},
        }
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*ToggleSwitch, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*ToggleSwitch, @ptrCast(@alignCast(widget_ptr)));
        const width = @as(u16, @intCast(@min(self.label.len + 8, 60)));
        return layout_module.Size.init(width, 1);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*ToggleSwitch, @ptrCast(@alignCast(widget_ptr)));
        return self.widget.enabled;
    }
};

/// Radio group displays mutually exclusive options with keyboard navigation.
pub const RadioGroup = struct {
    widget: base.Widget,
    options: std.ArrayList([]const u8),
    selected: usize = 0,
    on_change: ?*const fn (usize, []const u8) void = null,
    allocator: std.mem.Allocator,

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator, opts: []const []const u8) !*RadioGroup {
        const self = try allocator.create(RadioGroup);
        self.* = RadioGroup{
            .widget = base.Widget.init(&vtable),
            .options = std.ArrayList([]const u8).empty,
            .allocator = allocator,
        };

        for (opts) |opt| {
            try self.options.append(self.allocator, try allocator.dupe(u8, opt));
        }

        return self;
    }

    pub fn deinit(self: *RadioGroup) void {
        for (self.options.items) |opt| self.allocator.free(opt);
        self.options.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn setSelected(self: *RadioGroup, idx: usize) void {
        if (idx < self.options.items.len and self.selected != idx) {
            self.selected = idx;
            if (self.on_change) |cb| cb(idx, self.options.items[idx]);
        }
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*RadioGroup, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;
        const rect = self.widget.rect;
        const fg = render.Color.named(render.NamedColor.default);
        const bg = render.Color.named(render.NamedColor.default);

        const max_visible = @min(@as(u16, @intCast(self.options.items.len)), rect.height);
        var y: u16 = 0;
        while (y < max_visible) : (y += 1) {
            const idx = @as(usize, @intCast(y));
            const option = self.options.items[idx];
            const marker = if (idx == self.selected) "(*)" else "( )";
            renderer.drawStr(rect.x, rect.y + y, marker, fg, bg, render.Style{});
            if (rect.width > marker.len + 1) {
                const available = rect.width - @as(u16, @intCast(marker.len)) - 1;
                const draw_text = option[0..@min(option.len, available)];
                renderer.drawStr(rect.x + 4, rect.y + y, draw_text, fg, bg, render.Style{});
            }
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*RadioGroup, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible or !self.widget.enabled) return false;

        switch (event) {
            .key => |key| {
                if (!self.widget.focused) return false;
                switch (key.key) {
                    'k', 'K', input.KeyCode.PAGE_UP => {
                        if (self.selected > 0) {
                            self.setSelected(self.selected - 1);
                            return true;
                        }
                    },
                    'j', 'J', input.KeyCode.PAGE_DOWN => {
                        if (self.selected + 1 < self.options.items.len) {
                            self.setSelected(self.selected + 1);
                            return true;
                        }
                    },
                    '\n', ' ' => {
                        self.setSelected(self.selected);
                        return true;
                    },
                    else => {},
                }
            },
            .mouse => |mouse| {
                if (mouse.action == .press and mouse.button == 1 and self.widget.rect.contains(mouse.x, mouse.y)) {
                    const idx = mouse.y - self.widget.rect.y;
                    if (idx < self.options.items.len) {
                        self.setSelected(@intCast(idx));
                        return true;
                    }
                }
            },
            else => {},
        }
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*RadioGroup, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*RadioGroup, @ptrCast(@alignCast(widget_ptr)));
        var max_len: usize = 0;
        for (self.options.items) |opt| {
            max_len = @max(max_len, opt.len);
        }
        const width = @as(u16, @intCast(@min(max_len + 5, 80)));
        const height = @as(u16, @intCast(self.options.items.len));
        return layout_module.Size.init(width, height);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*RadioGroup, @ptrCast(@alignCast(widget_ptr)));
        return self.widget.enabled;
    }
};

/// Slider renders a horizontal track with a movable thumb for numeric input.
pub const Slider = struct {
    widget: base.Widget,
    min: f32 = 0,
    max: f32 = 1,
    value: f32 = 0,
    step: f32 = 0.1,
    show_value: bool = true,
    fg: render.Color = render.Color.named(render.NamedColor.cyan),
    bg: render.Color = render.Color.named(render.NamedColor.default),
    allocator: std.mem.Allocator,

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator, min: f32, max: f32) !*Slider {
        const self = try allocator.create(Slider);
        self.* = Slider{
            .widget = base.Widget.init(&vtable),
            .min = min,
            .max = max,
            .value = min,
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *Slider) void {
        self.allocator.destroy(self);
    }

    pub fn setValue(self: *Slider, value: f32) void {
        const clamped = std.math.clamp(value, self.min, self.max);
        if (clamped != self.value) self.value = clamped;
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*Slider, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;
        const rect = self.widget.rect;
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', self.fg, self.bg, render.Style{});

        if (rect.width < 4) return;
        const track_start = rect.x + 1;
        const track_end = rect.x + rect.width - 2;
        var x = track_start;
        while (x <= track_end) : (x += 1) {
            renderer.drawChar(x, rect.y, '-', self.fg, self.bg, render.Style{});
        }

        const ratio = if (self.max - self.min == 0) 0 else (self.value - self.min) / (self.max - self.min);
        const pos = track_start + @as(u16, @intFromFloat(@floor(ratio * @as(f32, @floatFromInt(track_end - track_start)))));
        renderer.drawChar(pos, rect.y, '|', render.Color.named(render.NamedColor.white), self.bg, render.Style{ .bold = true });

        if (self.show_value and rect.width > 6) {
            var buf: [16]u8 = undefined;
            const rendered = std.fmt.bufPrint(&buf, "{d:.2}", .{self.value}) catch buf[0..0];
            const value_x = track_end - @as(u16, @intCast(rendered.len)) + 1;
            if (value_x > rect.x and value_x < rect.x + rect.width) {
                renderer.drawStr(value_x, rect.y, rendered, self.fg, self.bg, render.Style{});
            }
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*Slider, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible or !self.widget.enabled) return false;

        const adjust = struct {
            fn apply(slider: *Slider, delta: f32) void {
                slider.setValue(slider.value + delta);
            }
        };

        switch (event) {
            .key => |key| {
                if (!self.widget.focused) return false;
                switch (key.key) {
                    'h', 'H', input.KeyCode.LEFT => {
                        adjust.apply(self, -self.step);
                        return true;
                    },
                    'l', 'L', input.KeyCode.RIGHT => {
                        adjust.apply(self, self.step);
                        return true;
                    },
                    else => {},
                }
            },
            .mouse => |mouse| {
                if (mouse.action == .press and mouse.button == 1 and self.widget.rect.contains(mouse.x, mouse.y)) {
                    const track_width = self.widget.rect.width - 3;
                    if (track_width > 0) {
                        const offset = mouse.x - (self.widget.rect.x + 1);
                        const ratio = @as(f32, @floatFromInt(offset)) / @as(f32, @floatFromInt(track_width));
                        self.setValue(self.min + ratio * (self.max - self.min));
                        return true;
                    }
                }
            },
            else => {},
        }
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*Slider, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(_: *anyopaque) anyerror!layout_module.Size {
        return layout_module.Size.init(12, 1);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*Slider, @ptrCast(@alignCast(widget_ptr)));
        return self.widget.enabled;
    }
};

/// RatingStars renders filled and empty stars for qualitative ratings.
pub const RatingStars = struct {
    widget: base.Widget,
    max_stars: u8 = 5,
    value: f32 = 0,
    filled_color: render.Color = render.Color.named(render.NamedColor.yellow),
    empty_color: render.Color = render.Color.named(render.NamedColor.bright_black),
    allocator: std.mem.Allocator,

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator, max_stars: u8) !*RatingStars {
        const self = try allocator.create(RatingStars);
        self.* = RatingStars{
            .widget = base.Widget.init(&vtable),
            .max_stars = max_stars,
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *RatingStars) void {
        self.allocator.destroy(self);
    }

    pub fn setValue(self: *RatingStars, value: f32) void {
        self.value = std.math.clamp(value, 0, @as(f32, @floatFromInt(self.max_stars)));
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*RatingStars, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;
        const rect = self.widget.rect;
        const filled = self.value;
        var x = rect.x;
        var i: u8 = 0;
        while (i < self.max_stars and x < rect.x + rect.width) : (i += 1) {
            const star_char: []const u8 = if (@as(f32, @floatFromInt(i)) + 0.5 <= filled) "★" else "☆";
            const color = if (@as(f32, @floatFromInt(i)) + 0.5 <= filled) self.filled_color else self.empty_color;
            renderer.drawStr(x, rect.y, star_char, color, render.Color.named(render.NamedColor.default), render.Style{});
            x += 1;
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*RatingStars, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible or !self.widget.enabled) return false;
        switch (event) {
            .mouse => |mouse| {
                if (mouse.action == .press and mouse.button == 1 and self.widget.rect.contains(mouse.x, mouse.y)) {
                    const offset = mouse.x - self.widget.rect.x;
                    self.setValue(@floatFromInt(offset + 1));
                    return true;
                }
            },
            .key => |key| {
                if (!self.widget.focused) return false;
                switch (key.key) {
                    'h', 'H', input.KeyCode.LEFT => {
                        self.setValue(self.value - 1);
                        return true;
                    },
                    'l', 'L', input.KeyCode.RIGHT => {
                        self.setValue(self.value + 1);
                        return true;
                    },
                    else => {},
                }
            },
            else => {},
        }
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*RatingStars, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*RatingStars, @ptrCast(@alignCast(widget_ptr)));
        return layout_module.Size.init(self.max_stars, 1);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*RatingStars, @ptrCast(@alignCast(widget_ptr)));
        return self.widget.enabled;
    }
};

/// StatusBar renders left, center, and right-aligned fields.
pub const StatusBar = struct {
    widget: base.Widget,
    left: []const u8 = "",
    center: []const u8 = "",
    right: []const u8 = "",
    fg: render.Color = render.Color.named(render.NamedColor.black),
    bg: render.Color = render.Color.named(render.NamedColor.bright_white),
    allocator: std.mem.Allocator,

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator) !*StatusBar {
        const self = try allocator.create(StatusBar);
        self.* = StatusBar{
            .widget = base.Widget.init(&vtable),
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *StatusBar) void {
        self.allocator.destroy(self);
    }

    pub fn setSegments(self: *StatusBar, left: []const u8, center: []const u8, right: []const u8) void {
        self.left = left;
        self.center = center;
        self.right = right;
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*StatusBar, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;
        const rect = self.widget.rect;
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', self.fg, self.bg, render.Style{ .bold = true });
        if (rect.width == 0) return;

        renderer.drawStr(rect.x + 1, rect.y, self.left[0..@min(self.left.len, rect.width)], self.fg, self.bg, render.Style{});

        if (self.center.len > 0) {
            const center_x = rect.x + (rect.width / 2) - @as(u16, @intCast(self.center.len / 2));
            if (center_x >= rect.x and center_x < rect.x + rect.width) {
                const clipped = self.center[0..@min(self.center.len, rect.width)];
                renderer.drawStr(center_x, rect.y, clipped, self.fg, self.bg, render.Style{ .bold = true });
            }
        }

        if (self.right.len > 0 and rect.width > self.right.len) {
            const right_x = rect.x + rect.width - @as(u16, @intCast(self.right.len)) - 1;
            renderer.drawStr(right_x, rect.y, self.right[0..@min(self.right.len, rect.width)], self.fg, self.bg, render.Style{});
        }
    }

    fn handleEventFn(_: *anyopaque, _: input.Event) anyerror!bool {
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*StatusBar, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(_: *anyopaque) anyerror!layout_module.Size {
        return layout_module.Size.init(20, 1);
    }

    fn canFocusFn(_: *anyopaque) bool {
        return false;
    }
};

/// Toolbar lays out a horizontal list of actions.
pub const Toolbar = struct {
    widget: base.Widget,
    items: std.ArrayList([]const u8),
    active: usize = 0,
    allocator: std.mem.Allocator,

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator, labels: []const []const u8) !*Toolbar {
        const self = try allocator.create(Toolbar);
        self.* = Toolbar{
            .widget = base.Widget.init(&vtable),
            .items = std.ArrayList([]const u8).empty,
            .allocator = allocator,
        };
        for (labels) |lbl| {
            try self.items.append(self.allocator, try allocator.dupe(u8, lbl));
        }
        return self;
    }

    pub fn deinit(self: *Toolbar) void {
        for (self.items.items) |item| self.allocator.free(item);
        self.items.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn setActive(self: *Toolbar, idx: usize) void {
        if (idx < self.items.items.len) self.active = idx;
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*Toolbar, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;
        const rect = self.widget.rect;
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', render.Color.named(.default), render.Color.named(.bright_black), render.Style{});

        var cursor = rect.x + 1;
        for (self.items.items, 0..) |item, idx| {
            if (cursor >= rect.x + rect.width) break;
            const display = try std.fmt.allocPrint(self.allocator, "[{s}]", .{item});
            defer self.allocator.free(display);
            const draw_len = @min(display.len, rect.width - (cursor - rect.x));
            const fg = if (idx == self.active) render.Color.named(.black) else render.Color.named(.white);
            const bg = if (idx == self.active) render.Color.named(.cyan) else render.Color.named(.bright_black);
            renderer.drawStr(cursor, rect.y, display[0..draw_len], fg, bg, render.Style{ .bold = idx == self.active });
            cursor += @intCast(draw_len + 1);
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*Toolbar, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible or !self.widget.enabled) return false;

        switch (event) {
            .key => |key| {
                if (!self.widget.focused) return false;
                switch (key.key) {
                    'h', 'H', input.KeyCode.LEFT => {
                        if (self.active > 0) self.active -= 1;
                        return true;
                    },
                    'l', 'L', input.KeyCode.RIGHT => {
                        if (self.active + 1 < self.items.items.len) self.active += 1;
                        return true;
                    },
                    else => {},
                }
            },
            .mouse => |mouse| {
                if (mouse.action == .press and mouse.button == 1 and self.widget.rect.contains(mouse.x, mouse.y)) {
                    var cursor = self.widget.rect.x + 1;
                    for (self.items.items, 0..) |item, idx| {
                        const width = @as(u16, @intCast(item.len + 2));
                        if (mouse.x >= cursor and mouse.x < cursor + width) {
                            self.active = idx;
                            return true;
                        }
                        cursor += width + 1;
                    }
                }
            },
            else => {},
        }
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*Toolbar, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*Toolbar, @ptrCast(@alignCast(widget_ptr)));
        var width: usize = 1;
        for (self.items.items) |item| width += item.len + 3;
        return layout_module.Size.init(@intCast(@min(width, 120)), 1);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*Toolbar, @ptrCast(@alignCast(widget_ptr)));
        return self.widget.enabled;
    }
};

/// Breadcrumbs print hierarchical navigation with separators.
pub const Breadcrumbs = struct {
    widget: base.Widget,
    parts: std.ArrayList([]const u8),
    separator: []const u8 = " / ",
    allocator: std.mem.Allocator,

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator, parts: []const []const u8) !*Breadcrumbs {
        const self = try allocator.create(Breadcrumbs);
        self.* = Breadcrumbs{
            .widget = base.Widget.init(&vtable),
            .parts = std.ArrayList([]const u8).empty,
            .allocator = allocator,
        };
        for (parts) |part| {
            try self.parts.append(self.allocator, try allocator.dupe(u8, part));
        }
        return self;
    }

    pub fn deinit(self: *Breadcrumbs) void {
        for (self.parts.items) |p| self.allocator.free(p);
        self.parts.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*Breadcrumbs, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;
        const rect = self.widget.rect;
        var cursor = rect.x;
        for (self.parts.items, 0..) |part, idx| {
            if (cursor >= rect.x + rect.width) break;
            const draw_part = part[0..@min(part.len, rect.width - (cursor - rect.x))];
            renderer.drawStr(cursor, rect.y, draw_part, render.Color.named(.cyan), render.Color.named(.default), render.Style{ .bold = true });
            cursor += @as(u16, @intCast(draw_part.len));
            if (idx + 1 < self.parts.items.len and cursor < rect.x + rect.width) {
                const sep_draw = self.separator[0..@min(self.separator.len, rect.width - (cursor - rect.x))];
                renderer.drawStr(cursor, rect.y, sep_draw, render.Color.named(.bright_black), render.Color.named(.default), render.Style{});
                cursor += @as(u16, @intCast(sep_draw.len));
            }
        }
    }

    fn handleEventFn(_: *anyopaque, _: input.Event) anyerror!bool {
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*Breadcrumbs, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*Breadcrumbs, @ptrCast(@alignCast(widget_ptr)));
        var width: usize = 0;
        for (self.parts.items, 0..) |part, idx| {
            width += part.len;
            if (idx + 1 < self.parts.items.len) width += self.separator.len;
        }
        return layout_module.Size.init(@intCast(@min(width, 200)), 1);
    }

    fn canFocusFn(_: *anyopaque) bool {
        return false;
    }
};

/// Pagination shows page numbers with previous/next affordances.
pub const Pagination = struct {
    widget: base.Widget,
    current: usize = 1,
    total: usize = 1,
    on_change: ?*const fn (usize) void = null,
    allocator: std.mem.Allocator,

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator, total: usize) !*Pagination {
        const self = try allocator.create(Pagination);
        self.* = Pagination{
            .widget = base.Widget.init(&vtable),
            .total = if (total == 0) 1 else total,
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *Pagination) void {
        self.allocator.destroy(self);
    }

    pub fn setPage(self: *Pagination, page: usize) void {
        const clamped = if (page < 1) 1 else if (page > self.total) self.total else page;
        if (clamped != self.current) {
            self.current = clamped;
            if (self.on_change) |cb| cb(self.current);
        }
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*Pagination, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;
        const rect = self.widget.rect;
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', render.Color.named(.default), render.Color.named(.default), render.Style{});
        var cursor = rect.x;
        const prev = "<";
        const next = ">";
        const fg = render.Color.named(.white);
        renderer.drawStr(cursor, rect.y, prev, fg, render.Color.named(.default), render.Style{ .bold = self.current > 1 });
        cursor += 2;
        var page: usize = 1;
        while (page <= self.total and cursor < rect.x + rect.width - 2) : (page += 1) {
            var buf: [8]u8 = undefined;
            const rendered = std.fmt.bufPrint(&buf, "{d}", .{page}) catch buf[0..0];
            const fg_page = if (page == self.current) render.Color.named(.black) else fg;
            const bg_page = if (page == self.current) render.Color.named(.green) else render.Color.named(.default);
            renderer.drawStr(cursor, rect.y, rendered, fg_page, bg_page, render.Style{ .bold = page == self.current });
            cursor += @as(u16, @intCast(rendered.len + 1));
        }
        if (cursor < rect.x + rect.width) {
            renderer.drawStr(rect.x + rect.width - 2, rect.y, next, fg, render.Color.named(.default), render.Style{ .bold = self.current < self.total });
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*Pagination, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible or !self.widget.enabled) return false;

        switch (event) {
            .key => |key| {
                if (!self.widget.focused) return false;
                switch (key.key) {
                    'h', 'H', input.KeyCode.LEFT => {
                        self.setPage(self.current - 1);
                        return true;
                    },
                    'l', 'L', input.KeyCode.RIGHT => {
                        self.setPage(self.current + 1);
                        return true;
                    },
                    else => {},
                }
            },
            .mouse => |mouse| {
                if (mouse.action == .press and mouse.button == 1 and self.widget.rect.contains(mouse.x, mouse.y)) {
                    if (mouse.x <= self.widget.rect.x + 1) {
                        self.setPage(self.current - 1);
                        return true;
                    }
                    if (mouse.x >= self.widget.rect.x + self.widget.rect.width - 2) {
                        self.setPage(self.current + 1);
                        return true;
                    }
                }
            },
            else => {},
        }
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*Pagination, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(_: *anyopaque) anyerror!layout_module.Size {
        return layout_module.Size.init(20, 1);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*Pagination, @ptrCast(@alignCast(widget_ptr)));
        return self.widget.enabled;
    }
};

/// CommandPalette surfaces a list of actions filtered by a query.
pub const CommandPalette = struct {
    widget: base.Widget,
    title: []const u8 = "Command Palette",
    query: []const u8 = "",
    commands: std.ArrayList([]const u8),
    selected: usize = 0,
    on_execute: ?*const fn (usize, []const u8) void = null,
    allocator: std.mem.Allocator,

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator, commands: []const []const u8) !*CommandPalette {
        const self = try allocator.create(CommandPalette);
        self.* = CommandPalette{
            .widget = base.Widget.init(&vtable),
            .commands = std.ArrayList([]const u8).empty,
            .allocator = allocator,
        };
        for (commands) |cmd| {
            try self.commands.append(self.allocator, try allocator.dupe(u8, cmd));
        }
        return self;
    }

    pub fn deinit(self: *CommandPalette) void {
        for (self.commands.items) |cmd| self.allocator.free(cmd);
        self.commands.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn setQuery(self: *CommandPalette, query: []const u8) void {
        self.query = query;
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*CommandPalette, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;
        const rect = self.widget.rect;
        const fg = render.Color.named(.white);
        const bg = render.Color.named(.black);
        renderer.drawBox(rect.x, rect.y, rect.width, rect.height, .rounded, fg, bg, render.Style{ .bold = true });
        if (rect.height < 3) return;

        renderer.drawStr(rect.x + 2, rect.y + 1, self.title[0..@min(self.title.len, rect.width - 4)], fg, bg, render.Style{ .bold = true });
        renderer.drawStr(rect.x + 2, rect.y + 2, self.query[0..@min(self.query.len, rect.width - 4)], render.Color.named(.bright_cyan), bg, render.Style{});

        var list_y: u16 = rect.y + 3;
        const max_rows = rect.height - 4;
        for (self.commands.items, 0..) |cmd, idx| {
            if (idx >= max_rows) break;
            const cmd_fg = if (idx == self.selected) render.Color.named(.black) else fg;
            const cmd_bg = if (idx == self.selected) render.Color.named(.cyan) else bg;
            renderer.drawStr(rect.x + 2, list_y, cmd[0..@min(cmd.len, rect.width - 4)], cmd_fg, cmd_bg, render.Style{});
            list_y += 1;
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*CommandPalette, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible or !self.widget.enabled) return false;

        switch (event) {
            .key => |key| {
                if (!self.widget.focused) return false;
                switch (key.key) {
                    'k', 'K', input.KeyCode.UP => {
                        if (self.selected > 0) self.selected -= 1;
                        return true;
                    },
                    'j', 'J', input.KeyCode.DOWN => {
                        if (self.selected + 1 < self.commands.items.len) self.selected += 1;
                        return true;
                    },
                    '\n' => {
                        if (self.on_execute) |cb| cb(self.selected, self.commands.items[self.selected]);
                        return true;
                    },
                    else => {},
                }
            },
            else => {},
        }
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*CommandPalette, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(_: *anyopaque) anyerror!layout_module.Size {
        return layout_module.Size.init(30, 8);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*CommandPalette, @ptrCast(@alignCast(widget_ptr)));
        return self.widget.enabled;
    }
};

/// Notification center stacks transient and sticky messages.
pub const NotificationCenter = struct {
    widget: base.Widget,
    notifications: std.ArrayList(Notification),
    allocator: std.mem.Allocator,

    pub const Notification = struct {
        title: []const u8,
        body: []const u8,
        level: Level = .info,
    };

    pub const Level = enum { info, warning, danger, success };

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator) !*NotificationCenter {
        const self = try allocator.create(NotificationCenter);
        self.* = NotificationCenter{
            .widget = base.Widget.init(&vtable),
            .notifications = std.ArrayList(Notification).empty,
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *NotificationCenter) void {
        for (self.notifications.items) |n| {
            self.allocator.free(n.title);
            self.allocator.free(n.body);
        }
        self.notifications.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn push(self: *NotificationCenter, title: []const u8, body: []const u8, level: Level) !void {
        const duped = Notification{
            .title = try self.allocator.dupe(u8, title),
            .body = try self.allocator.dupe(u8, body),
            .level = level,
        };
        try self.notifications.append(self.allocator, duped);
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*NotificationCenter, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;
        const rect = self.widget.rect;
        const max_rows = rect.height;
        var y: u16 = 0;
        const start = if (self.notifications.items.len > max_rows)
            self.notifications.items.len - max_rows
        else
            0;
        for (self.notifications.items[start..], 0..) |note, idx| {
            if (y >= rect.height) break;
            const colors = switch (note.level) {
                .info => .{ render.Color.named(.white), render.Color.named(.blue) },
                .warning => .{ render.Color.named(.black), render.Color.named(.yellow) },
                .danger => .{ render.Color.named(.white), render.Color.named(.red) },
                .success => .{ render.Color.named(.black), render.Color.named(.green) },
            };
            renderer.fillRect(rect.x, rect.y + y, rect.width, 1, ' ', colors[0], colors[1], render.Style{});
            const title = note.title[0..@min(note.title.len, rect.width)];
            renderer.drawStr(rect.x + 1, rect.y + y, title, colors[0], colors[1], render.Style{ .bold = true });
            const space_left = rect.width - 2 - @as(u16, @intCast(title.len));
            if (space_left > 0) {
                const body = note.body[0..@min(note.body.len, space_left)];
                renderer.drawStr(rect.x + 1 + @as(u16, @intCast(title.len)) + 1, rect.y + y, body, colors[0], colors[1], render.Style{});
            }
            _ = idx;
            y += 1;
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*NotificationCenter, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible or !self.widget.enabled) return false;
        switch (event) {
            .key => |key| {
                if (!self.widget.focused) return false;
                if (key.key == 'c' and key.modifiers.ctrl) {
                    for (self.notifications.items) |note| {
                        self.allocator.free(note.title);
                        self.allocator.free(note.body);
                    }
                    self.notifications.clearRetainingCapacity();
                    return true;
                }
            },
            else => {},
        }
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*NotificationCenter, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(_: *anyopaque) anyerror!layout_module.Size {
        return layout_module.Size.init(30, 3);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*NotificationCenter, @ptrCast(@alignCast(widget_ptr)));
        return self.widget.enabled;
    }
};

/// Accordion groups panels that expand and collapse.
pub const Accordion = struct {
    widget: base.Widget,
    sections: std.ArrayList(Section),
    allocator: std.mem.Allocator,

    pub const Section = struct {
        title: []const u8,
        body: []const u8,
        expanded: bool = false,
    };

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator, sections: []const Section) !*Accordion {
        const self = try allocator.create(Accordion);
        self.* = Accordion{
            .widget = base.Widget.init(&vtable),
            .sections = std.ArrayList(Section).empty,
            .allocator = allocator,
        };
        for (sections) |section| {
            try self.sections.append(self.allocator, .{
                .title = try allocator.dupe(u8, section.title),
                .body = try allocator.dupe(u8, section.body),
                .expanded = section.expanded,
            });
        }
        return self;
    }

    pub fn deinit(self: *Accordion) void {
        for (self.sections.items) |section| {
            self.allocator.free(section.title);
            self.allocator.free(section.body);
        }
        self.sections.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*Accordion, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;
        const rect = self.widget.rect;
        var y = rect.y;
        for (self.sections.items, 0..) |section, idx| {
            if (y >= rect.y + rect.height) break;
            const prefix = if (section.expanded) "▼" else "►";
            renderer.drawStr(rect.x, y, prefix, render.Color.named(.yellow), render.Color.named(.default), render.Style{ .bold = true });
            renderer.drawStr(rect.x + 2, y, section.title[0..@min(section.title.len, rect.width - 2)], render.Color.named(.white), render.Color.named(.default), render.Style{});
            y += 1;
            if (section.expanded and y < rect.y + rect.height) {
                const body = section.body[0..@min(section.body.len, rect.width)];
                renderer.drawStr(rect.x + 2, y, body, render.Color.named(.bright_white), render.Color.named(.default), render.Style{});
                y += 1;
            }
            _ = idx;
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*Accordion, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible or !self.widget.enabled) return false;
        switch (event) {
            .mouse => |mouse| {
                if (mouse.action == .press and mouse.button == 1 and self.widget.rect.contains(mouse.x, mouse.y)) {
                    const offset = mouse.y - self.widget.rect.y;
                    var y: u16 = 0;
                    for (self.sections.items, 0..) |*section, idx| {
                        if (y == offset) {
                            section.expanded = !section.expanded;
                            _ = idx;
                            return true;
                        }
                        y += 1;
                        if (section.expanded and y <= offset) {
                            y += 1;
                        }
                    }
                }
            },
            .key => |key| {
                if (!self.widget.focused) return false;
                if (key.key == '\n' or key.key == ' ') {
                    for (self.sections.items, 0..) |*section, idx| {
                        _ = idx;
                        section.expanded = !section.expanded;
                        return true;
                    }
                }
            },
            else => {},
        }
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*Accordion, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*Accordion, @ptrCast(@alignCast(widget_ptr)));
        const height = @as(u16, @intCast(self.sections.items.len * 2));
        return layout_module.Size.init(20, height);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*Accordion, @ptrCast(@alignCast(widget_ptr)));
        return self.widget.enabled;
    }
};

/// WizardStepper shows progress across multiple steps.
pub const WizardStepper = struct {
    widget: base.Widget,
    steps: std.ArrayList([]const u8),
    current: usize = 0,
    allocator: std.mem.Allocator,

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator, steps: []const []const u8) !*WizardStepper {
        const self = try allocator.create(WizardStepper);
        self.* = WizardStepper{
            .widget = base.Widget.init(&vtable),
            .steps = std.ArrayList([]const u8).empty,
            .allocator = allocator,
        };
        for (steps) |step| {
            try self.steps.append(self.allocator, try allocator.dupe(u8, step));
        }
        return self;
    }

    pub fn deinit(self: *WizardStepper) void {
        for (self.steps.items) |s| self.allocator.free(s);
        self.steps.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn setStep(self: *WizardStepper, idx: usize) void {
        if (idx < self.steps.items.len) self.current = idx;
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*WizardStepper, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;
        const rect = self.widget.rect;
        if (self.steps.items.len == 0) return;

        var cursor = rect.x;
        for (self.steps.items, 0..) |step, idx| {
            if (cursor >= rect.x + rect.width) break;
            var buf: [32]u8 = undefined;
            const rendered = std.fmt.bufPrint(&buf, "{d}. {s}", .{ idx + 1, step }) catch buf[0..0];
            const slice = rendered;
            const fg = if (idx == self.current) render.Color.named(.black) else render.Color.named(.white);
            const bg = if (idx == self.current) render.Color.named(.green) else render.Color.named(.default);
            renderer.drawStr(cursor, rect.y, slice[0..@min(slice.len, rect.width - (cursor - rect.x))], fg, bg, render.Style{ .bold = idx == self.current });
            cursor += @as(u16, @intCast(slice.len + 2));
        }

        // Progress bar along bottom if height > 1
        if (rect.height > 1 and self.steps.items.len > 0) {
            const progress = @as(f32, @floatFromInt(self.current + 1)) / @as(f32, @floatFromInt(self.steps.items.len));
            const fill = @as(u16, @intFromFloat(progress * @as(f32, @floatFromInt(rect.width))));
            var x = rect.x;
            while (x < rect.x + rect.width) : (x += 1) {
                const filled = x - rect.x < fill;
                renderer.drawChar(x, rect.y + rect.height - 1, if (filled) '█' else '░', render.Color.named(.green), render.Color.named(.default), render.Style{});
            }
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*WizardStepper, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible or !self.widget.enabled) return false;

        switch (event) {
            .key => |key| {
                if (!self.widget.focused) return false;
                switch (key.key) {
                    'h', 'H', input.KeyCode.LEFT => {
                        if (self.current > 0) self.current -= 1;
                        return true;
                    },
                    'l', 'L', input.KeyCode.RIGHT => {
                        if (self.current + 1 < self.steps.items.len) self.current += 1;
                        return true;
                    },
                    else => {},
                }
            },
            else => {},
        }
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*WizardStepper, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*WizardStepper, @ptrCast(@alignCast(widget_ptr)));
        var width: usize = 0;
        for (self.steps.items) |step| width += step.len + 4;
        return layout_module.Size.init(@intCast(@min(width, 200)), 2);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*WizardStepper, @ptrCast(@alignCast(widget_ptr)));
        return self.widget.enabled;
    }
};

test "toggle switch renders state" {
    const alloc = std.testing.allocator;

    var toggle = try ToggleSwitch.init(alloc, "Turbo");
    defer toggle.deinit();
    toggle.set(true);

    var snap = try testing.renderWidget(alloc, &toggle.widget, layout_module.Size.init(16, 1));
    defer snap.deinit(alloc);
    try snap.expectEqual("[ ON ] Turbo\n");
}

test "radio group updates selection" {
    const alloc = std.testing.allocator;

    var radio = try RadioGroup.init(alloc, &[_][]const u8{ "A", "B", "C" });
    defer radio.deinit();
    radio.setSelected(2);

    var snap = try testing.renderWidget(alloc, &radio.widget, layout_module.Size.init(6, 3));
    defer snap.deinit(alloc);
    try snap.expectEqual(
        \\( ) A
        \\( ) B
        \\(*) C
        \\
    );
}

test "slider clamps values" {
    const alloc = std.testing.allocator;
    var slider = try Slider.init(alloc, 0, 10);
    defer slider.deinit();
    slider.setValue(15);
    try std.testing.expectEqual(@as(f32, 10), slider.value);
}

test "rating stars increments with input" {
    const alloc = std.testing.allocator;
    var stars = try RatingStars.init(alloc, 3);
    defer stars.deinit();
    stars.setValue(2);
    try std.testing.expectEqual(@as(f32, 2), stars.value);
}

test "pagination advances pages" {
    const alloc = std.testing.allocator;
    var pager = try Pagination.init(alloc, 5);
    defer pager.deinit();
    pager.setPage(3);
    try std.testing.expectEqual(@as(usize, 3), pager.current);
}
