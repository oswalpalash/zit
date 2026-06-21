const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const testing = @import("../../testing/testing.zig");
const accessibility = @import("../accessibility.zig");

fn appendOwnedString(list: *std.ArrayListUnmanaged([]const u8), allocator: std.mem.Allocator, value: []const u8) !void {
    try list.ensureUnusedCapacity(allocator, 1);
    const copy = try allocator.dupe(u8, value);
    list.appendAssumeCapacity(copy);
}

fn freeStringList(list: *std.ArrayListUnmanaged([]const u8), allocator: std.mem.Allocator) void {
    for (list.items) |item| allocator.free(item);
    list.clearRetainingCapacity();
}

fn appendOwnedPart(list: *std.ArrayListUnmanaged(Breadcrumbs.Part), allocator: std.mem.Allocator, part: Breadcrumbs.Part) !void {
    try list.ensureUnusedCapacity(allocator, 1);
    const label = try allocator.dupe(u8, part.label);
    errdefer allocator.free(label);
    const icon = if (part.icon) |ic| try allocator.dupe(u8, ic) else null;
    errdefer if (icon) |ic| allocator.free(ic);
    list.appendAssumeCapacity(.{ .label = label, .icon = icon });
}

fn freePartList(list: *std.ArrayListUnmanaged(Breadcrumbs.Part), allocator: std.mem.Allocator) void {
    for (list.items) |part| {
        allocator.free(part.label);
        if (part.icon) |ic| allocator.free(ic);
    }
    list.clearRetainingCapacity();
}

fn partListsEql(existing: []const Breadcrumbs.Part, next: []const Breadcrumbs.Part) bool {
    if (existing.len != next.len) return false;
    for (existing, next) |a, b| {
        if (!std.mem.eql(u8, a.label, b.label)) return false;
        if (a.icon == null and b.icon == null) continue;
        if (a.icon == null or b.icon == null) return false;
        if (!std.mem.eql(u8, a.icon.?, b.icon.?)) return false;
    }
    return true;
}

fn appendOwnedSection(list: *std.ArrayListUnmanaged(Accordion.Section), allocator: std.mem.Allocator, section: Accordion.Section) !void {
    try list.ensureUnusedCapacity(allocator, 1);
    const title = try allocator.dupe(u8, section.title);
    errdefer allocator.free(title);
    const body = try allocator.dupe(u8, section.body);
    list.appendAssumeCapacity(.{
        .title = title,
        .body = body,
        .expanded = section.expanded,
    });
}

fn freeSectionList(list: *std.ArrayListUnmanaged(Accordion.Section), allocator: std.mem.Allocator) void {
    for (list.items) |section| {
        allocator.free(section.title);
        allocator.free(section.body);
    }
    list.clearRetainingCapacity();
}

fn normalizedRangeValue(value: f32, min: f32, max: f32) f32 {
    if (!std.math.isFinite(min) or !std.math.isFinite(max) or !(max > min)) return 0;
    if (std.math.isPositiveInf(value)) return max;
    if (!std.math.isFinite(value)) return min;
    return std.math.clamp(value, min, max);
}

fn normalizedRangeRatio(value: f32, min: f32, max: f32) f32 {
    if (!std.math.isFinite(min) or !std.math.isFinite(max) or !(max > min)) return 0;
    if (std.math.isPositiveInf(value)) return 1;
    if (!std.math.isFinite(value)) return 0;

    const clamped = std.math.clamp(value, min, max);
    const ratio = (clamped - min) / (max - min);
    if (!std.math.isFinite(ratio)) return 0;
    return std.math.clamp(ratio, 0, 1);
}

fn normalizedRatingValue(value: f32, max_stars: u8) f32 {
    const max = @as(f32, @floatFromInt(max_stars));
    if (std.math.isPositiveInf(value)) return max;
    if (!std.math.isFinite(value)) return 0;
    return std.math.clamp(value, 0, max);
}

fn offsetCoord(origin: u16, offset: usize) u16 {
    return @intCast(@min(@as(usize, origin) + offset, std.math.maxInt(u16)));
}

fn addUsizeClamped(a: usize, b: usize) usize {
    return std.math.add(usize, a, b) catch std.math.maxInt(usize);
}

fn clampUsizeToU16(value: usize) u16 {
    return @intCast(@min(value, @as(usize, std.math.maxInt(u16))));
}

fn cappedPaddedWidth(content_len: usize, padding: usize, cap: u16) u16 {
    return @intCast(@min(addUsizeClamped(content_len, padding), @as(usize, cap)));
}

fn addPaddedLenClamped(width: usize, content_len: usize, padding: usize) usize {
    return addUsizeClamped(width, addUsizeClamped(content_len, padding));
}

fn accordionPreferredHeight(section_count: usize) u16 {
    return clampUsizeToU16(addUsizeClamped(section_count, section_count));
}

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
        errdefer allocator.destroy(self);

        const label_copy = try allocator.dupe(u8, label);
        self.* = ToggleSwitch{
            .widget = base.Widget.init(&vtable),
            .label = label_copy,
            .allocator = allocator,
        };
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.checkbox), self.label, "");
        return self;
    }

    pub fn deinit(self: *ToggleSwitch) void {
        self.allocator.free(self.label);
        self.allocator.destroy(self);
    }

    pub fn set(self: *ToggleSwitch, value: bool) void {
        if (self.on != value) {
            self.on = value;
            self.widget.markDirty();
            if (self.on_toggle) |cb| cb(self.on);
        }
    }

    pub fn toggle(self: *ToggleSwitch) void {
        self.set(!self.on);
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *ToggleSwitch = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible) return;

        const rect = self.widget.rect;
        const fg = if (self.on) self.on_fg else self.off_fg;
        const bg = if (self.on) self.on_bg else self.off_bg;

        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', fg, bg, self.track_style);
        if (rect.width == 0 or rect.height == 0) return;

        // Switch pill representation: [ ON ]
        const width: usize = rect.width;
        const pill_width: usize = 6;
        renderer.drawChar(rect.x, rect.y, '[', fg, bg, self.track_style);
        if (width >= pill_width) {
            renderer.drawChar(offsetCoord(rect.x, pill_width - 1), rect.y, ']', fg, bg, self.track_style);
        }
        const text = if (self.on) " ON " else " OFF";
        if (width > 1) {
            renderer.drawStr(offsetCoord(rect.x, 1), rect.y, text[0..@min(text.len, width - 1)], fg, bg, render.Style{ .bold = true });
        }

        if (width > pill_width and self.label.len > 0) {
            const available = width - pill_width - 1;
            if (available > 0) {
                const draw_text = self.label[0..@min(self.label.len, available)];
                renderer.drawStr(offsetCoord(rect.x, pill_width + 1), rect.y, draw_text, fg, bg, self.track_style);
            }
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *ToggleSwitch = @fieldParentPtr("widget", widget_ref);
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
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *ToggleSwitch = @fieldParentPtr("widget", widget_ref);
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *ToggleSwitch = @fieldParentPtr("widget", widget_ref);
        const width = cappedPaddedWidth(self.label.len, 8, 60);
        return layout_module.Size.init(width, 1);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *ToggleSwitch = @fieldParentPtr("widget", widget_ref);
        return self.widget.enabled;
    }
};

/// Radio group displays mutually exclusive options with keyboard navigation.
pub const RadioGroup = struct {
    widget: base.Widget,
    options: std.ArrayListUnmanaged([]const u8),
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
            .options = .empty,
            .allocator = allocator,
        };
        errdefer self.deinit();

        for (opts) |opt| {
            try appendOwnedString(&self.options, self.allocator, opt);
        }

        self.widget.setAccessibility(@intFromEnum(accessibility.Role.list), "Radio group", "");
        return self;
    }

    pub fn deinit(self: *RadioGroup) void {
        freeStringList(&self.options, self.allocator);
        self.options.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn setSelected(self: *RadioGroup, idx: usize) void {
        if (idx < self.options.items.len and self.selected != idx) {
            self.selected = idx;
            self.widget.markDirty();
            if (self.on_change) |cb| cb(idx, self.options.items[idx]);
        }
    }

    fn clampSelection(self: *RadioGroup) void {
        if (self.options.items.len == 0) {
            self.selected = 0;
        } else if (self.selected >= self.options.items.len) {
            self.selected = self.options.items.len - 1;
        }
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *RadioGroup = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible) return;
        const rect = self.widget.rect;
        const fg = render.Color.named(render.NamedColor.default);
        const bg = render.Color.named(render.NamedColor.default);
        self.clampSelection();

        const max_visible = @min(clampUsizeToU16(self.options.items.len), rect.height);
        var y: u16 = 0;
        while (y < max_visible) : (y += 1) {
            const idx = @as(usize, @intCast(y));
            const option = self.options.items[idx];
            const marker = if (idx == self.selected) "(*)" else "( )";
            const row_y = offsetCoord(rect.y, y);
            renderer.drawStr(rect.x, row_y, marker[0..@min(marker.len, rect.width)], fg, bg, render.Style{});
            if (rect.width > marker.len + 1) {
                const available = rect.width - @as(u16, @intCast(marker.len)) - 1;
                const draw_text = option[0..@min(option.len, available)];
                renderer.drawStr(offsetCoord(rect.x, 4), row_y, draw_text, fg, bg, render.Style{});
            }
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *RadioGroup = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible or !self.widget.enabled) return false;

        switch (event) {
            .key => |key| {
                if (!self.widget.focused) return false;
                self.clampSelection();
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
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *RadioGroup = @fieldParentPtr("widget", widget_ref);
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *RadioGroup = @fieldParentPtr("widget", widget_ref);
        var max_len: usize = 0;
        for (self.options.items) |opt| {
            max_len = @max(max_len, opt.len);
        }
        const width = cappedPaddedWidth(max_len, 5, 80);
        const height = clampUsizeToU16(self.options.items.len);
        return layout_module.Size.init(width, height);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *RadioGroup = @fieldParentPtr("widget", widget_ref);
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
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.slider), "Slider", "");
        return self;
    }

    pub fn deinit(self: *Slider) void {
        self.allocator.destroy(self);
    }

    pub fn setValue(self: *Slider, value: f32) void {
        _ = self.trySetValue(value);
    }

    fn trySetValue(self: *Slider, value: f32) bool {
        const clamped = normalizedRangeValue(value, self.min, self.max);
        if (clamped != self.value) {
            self.value = clamped;
            self.widget.markDirty();
            return true;
        }
        return false;
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Slider = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible) return;
        const rect = self.widget.rect;
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', self.fg, self.bg, render.Style{});

        const width: usize = rect.width;
        if (width < 4) return;
        const track_start_offset: usize = 1;
        const track_end_offset: usize = width - 2;
        var x_offset: usize = track_start_offset;
        while (x_offset <= track_end_offset) : (x_offset += 1) {
            renderer.drawChar(offsetCoord(rect.x, x_offset), rect.y, '-', self.fg, self.bg, render.Style{});
        }

        const ratio = normalizedRangeRatio(self.value, self.min, self.max);
        const track_span = track_end_offset - track_start_offset;
        const pos_offset = track_start_offset + @as(usize, @intFromFloat(@floor(ratio * @as(f32, @floatFromInt(track_span)))));
        renderer.drawChar(offsetCoord(rect.x, pos_offset), rect.y, '|', render.Color.named(render.NamedColor.white), self.bg, render.Style{ .bold = true });

        if (self.show_value and width > 6) {
            var buf: [16]u8 = undefined;
            const rendered = std.fmt.bufPrint(&buf, "{d:.2}", .{self.value}) catch buf[0..0];
            if (rendered.len + 1 < width) {
                const value_offset = width - rendered.len - 1;
                renderer.drawStr(offsetCoord(rect.x, value_offset), rect.y, rendered, self.fg, self.bg, render.Style{});
            }
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Slider = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible or !self.widget.enabled) return false;

        const adjust = struct {
            fn apply(slider: *Slider, delta: f32) bool {
                return slider.trySetValue(slider.value + delta);
            }
        };

        switch (event) {
            .key => |key| {
                if (!self.widget.focused) return false;
                switch (key.key) {
                    'h', 'H', input.KeyCode.LEFT => {
                        return adjust.apply(self, -self.step);
                    },
                    'l', 'L', input.KeyCode.RIGHT => {
                        return adjust.apply(self, self.step);
                    },
                    else => {},
                }
            },
            .mouse => |mouse| {
                if (mouse.action == .press and mouse.button == 1 and self.widget.rect.contains(mouse.x, mouse.y)) {
                    const rect = self.widget.rect;
                    if (rect.width < 4) return false;
                    const track_width = rect.width - 3;
                    const track_start = offsetCoord(rect.x, 1);
                    const offset = if (mouse.x <= track_start) 0 else @min(mouse.x - track_start, track_width);
                    const ratio = @as(f32, @floatFromInt(offset)) / @as(f32, @floatFromInt(track_width));
                    return self.trySetValue(self.min + ratio * (self.max - self.min));
                }
            },
            else => {},
        }
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Slider = @fieldParentPtr("widget", widget_ref);
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(_: *anyopaque) anyerror!layout_module.Size {
        return layout_module.Size.init(12, 1);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Slider = @fieldParentPtr("widget", widget_ref);
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
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.slider), "Rating", "");
        return self;
    }

    pub fn deinit(self: *RatingStars) void {
        self.allocator.destroy(self);
    }

    pub fn setValue(self: *RatingStars, value: f32) void {
        _ = self.trySetValue(value);
    }

    fn trySetValue(self: *RatingStars, value: f32) bool {
        const normalized = normalizedRatingValue(value, self.max_stars);
        if (normalized != self.value) {
            self.value = normalized;
            self.widget.markDirty();
            return true;
        }
        return false;
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *RatingStars = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible) return;
        const rect = self.widget.rect;
        if (rect.width == 0 or rect.height == 0) return;
        const filled = normalizedRatingValue(self.value, self.max_stars);
        var x_offset: usize = 0;
        var i: u8 = 0;
        while (i < self.max_stars and x_offset < rect.width) : (i += 1) {
            const star_char: []const u8 = if (@as(f32, @floatFromInt(i)) + 0.5 <= filled) "★" else "☆";
            const color = if (@as(f32, @floatFromInt(i)) + 0.5 <= filled) self.filled_color else self.empty_color;
            renderer.drawStr(offsetCoord(rect.x, x_offset), rect.y, star_char, color, render.Color.named(render.NamedColor.default), render.Style{});
            x_offset += 1;
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *RatingStars = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible or !self.widget.enabled) return false;
        switch (event) {
            .mouse => |mouse| {
                if (mouse.action == .press and mouse.button == 1 and self.widget.rect.contains(mouse.x, mouse.y)) {
                    const offset = mouse.x - self.widget.rect.x;
                    return self.trySetValue(@floatFromInt(offset + 1));
                }
            },
            .key => |key| {
                if (!self.widget.focused) return false;
                switch (key.key) {
                    'h', 'H', input.KeyCode.LEFT => {
                        return self.trySetValue(self.value - 1);
                    },
                    'l', 'L', input.KeyCode.RIGHT => {
                        return self.trySetValue(self.value + 1);
                    },
                    else => {},
                }
            },
            else => {},
        }
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *RatingStars = @fieldParentPtr("widget", widget_ref);
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *RatingStars = @fieldParentPtr("widget", widget_ref);
        return layout_module.Size.init(self.max_stars, 1);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *RatingStars = @fieldParentPtr("widget", widget_ref);
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
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.status), "Status bar", "");
        return self;
    }

    pub fn deinit(self: *StatusBar) void {
        self.allocator.destroy(self);
    }

    pub fn setSegments(self: *StatusBar, left: []const u8, center: []const u8, right: []const u8) void {
        const changed = !std.mem.eql(u8, self.left, left) or
            !std.mem.eql(u8, self.center, center) or
            !std.mem.eql(u8, self.right, right);
        self.left = left;
        self.center = center;
        self.right = right;
        if (changed) self.widget.markDirty();
    }

    fn xOffset(rect_x: u16, offset: usize) u16 {
        return @intCast(@min(@as(usize, rect_x) + offset, std.math.maxInt(u16)));
    }

    fn drawBoundedText(
        renderer: *render.Renderer,
        x: u16,
        y: u16,
        text: []const u8,
        max_width: usize,
        fg: render.Color,
        bg: render.Color,
        style: render.Style,
    ) void {
        if (max_width == 0 or text.len == 0) return;
        renderer.drawStr(x, y, text[0..@min(text.len, max_width)], fg, bg, style);
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *StatusBar = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible) return;
        const rect = self.widget.rect;
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', self.fg, self.bg, render.Style{ .bold = true });
        if (rect.width == 0) return;

        const width: usize = rect.width;
        const left_padding: usize = if (width > 1) 1 else 0;
        drawBoundedText(
            renderer,
            xOffset(rect.x, left_padding),
            rect.y,
            self.left,
            width - left_padding,
            self.fg,
            self.bg,
            render.Style{},
        );

        if (self.center.len > 0) {
            const display_len = @min(self.center.len, width);
            const center_offset = (width - display_len) / 2;
            drawBoundedText(
                renderer,
                xOffset(rect.x, center_offset),
                rect.y,
                self.center,
                display_len,
                self.fg,
                self.bg,
                render.Style{ .bold = true },
            );
        }

        if (self.right.len > 0) {
            const display_len = @min(self.right.len, width);
            const right_padding: usize = if (width > display_len) 1 else 0;
            const right_offset = width - display_len - right_padding;
            drawBoundedText(
                renderer,
                xOffset(rect.x, right_offset),
                rect.y,
                self.right,
                display_len,
                self.fg,
                self.bg,
                render.Style{},
            );
        }
    }

    fn handleEventFn(_: *anyopaque, _: input.Event) anyerror!bool {
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *StatusBar = @fieldParentPtr("widget", widget_ref);
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
    items: std.ArrayListUnmanaged([]const u8),
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
            .items = .empty,
            .allocator = allocator,
        };
        errdefer self.deinit();

        for (labels) |lbl| {
            try appendOwnedString(&self.items, self.allocator, lbl);
        }
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.menu), "Toolbar", "");
        return self;
    }

    pub fn deinit(self: *Toolbar) void {
        freeStringList(&self.items, self.allocator);
        self.items.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn setActive(self: *Toolbar, idx: usize) void {
        if (idx < self.items.items.len and self.active != idx) {
            self.active = idx;
            self.widget.markDirty();
        }
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Toolbar = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible) return;
        const rect = self.widget.rect;
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', render.Color.named(.default), render.Color.named(.bright_black), render.Style{});

        const limit = offsetCoord(rect.x, rect.width);
        var cursor = offsetCoord(rect.x, 1);
        for (self.items.items, 0..) |item, idx| {
            if (cursor >= limit) break;
            const display = try std.fmt.allocPrint(self.allocator, "[{s}]", .{item});
            defer self.allocator.free(display);
            const draw_len = @min(display.len, @as(usize, @intCast(limit - cursor)));
            const fg = if (idx == self.active) render.Color.named(.black) else render.Color.named(.white);
            const bg = if (idx == self.active) render.Color.named(.cyan) else render.Color.named(.bright_black);
            renderer.drawStr(cursor, rect.y, display[0..draw_len], fg, bg, render.Style{ .bold = idx == self.active });
            cursor = offsetCoord(cursor, draw_len + 1);
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Toolbar = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible or !self.widget.enabled) return false;

        switch (event) {
            .key => |key| {
                if (!self.widget.focused) return false;
                switch (key.key) {
                    'h', 'H', input.KeyCode.LEFT => {
                        if (self.active > 0) self.setActive(self.active - 1);
                        return true;
                    },
                    'l', 'L', input.KeyCode.RIGHT => {
                        if (self.active + 1 < self.items.items.len) self.setActive(self.active + 1);
                        return true;
                    },
                    else => {},
                }
            },
            .mouse => |mouse| {
                if (mouse.action == .press and mouse.button == 1 and self.widget.rect.contains(mouse.x, mouse.y)) {
                    const limit = offsetCoord(self.widget.rect.x, self.widget.rect.width);
                    var cursor = offsetCoord(self.widget.rect.x, 1);
                    for (self.items.items, 0..) |item, idx| {
                        if (cursor >= limit) break;
                        const width: u16 = @intCast(@min(item.len +| 2, @as(usize, std.math.maxInt(u16))));
                        const end = offsetCoord(cursor, width);
                        if (mouse.x >= cursor and mouse.x < end) {
                            self.setActive(idx);
                            return true;
                        }
                        cursor = offsetCoord(cursor, @as(usize, width) + 1);
                    }
                }
            },
            else => {},
        }
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Toolbar = @fieldParentPtr("widget", widget_ref);
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Toolbar = @fieldParentPtr("widget", widget_ref);
        var width: usize = 1;
        for (self.items.items) |item| width = addPaddedLenClamped(width, item.len, 3);
        return layout_module.Size.init(@min(clampUsizeToU16(width), 120), 1);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Toolbar = @fieldParentPtr("widget", widget_ref);
        return self.widget.enabled;
    }
};

/// Breadcrumbs print hierarchical navigation with separators.
pub const Breadcrumbs = struct {
    widget: base.Widget,
    parts: std.ArrayListUnmanaged(Part),
    separator: []const u8 = " / ",
    overflow_token: []const u8 = "...",
    on_click: ?*const fn (usize) void = null,
    allocator: std.mem.Allocator,

    pub const Part = struct { label: []const u8, icon: ?[]const u8 = null };

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
            .parts = .empty,
            .allocator = allocator,
        };
        errdefer self.deinit();

        for (parts) |part| {
            try appendOwnedPart(&self.parts, self.allocator, .{ .label = part });
        }
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.list), "Breadcrumbs", "");
        return self;
    }

    pub fn deinit(self: *Breadcrumbs) void {
        freePartList(&self.parts, self.allocator);
        self.parts.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn setOnClick(self: *Breadcrumbs, cb: *const fn (usize) void) void {
        self.on_click = cb;
    }

    pub fn setParts(self: *Breadcrumbs, parts: []const Part) !void {
        const changed = !partListsEql(self.parts.items, parts);
        var next = std.ArrayListUnmanaged(Part).empty;
        errdefer {
            freePartList(&next, self.allocator);
            next.deinit(self.allocator);
        }

        for (parts) |p| {
            try appendOwnedPart(&next, self.allocator, p);
        }

        freePartList(&self.parts, self.allocator);
        self.parts.deinit(self.allocator);
        self.parts = next;
        if (changed) self.widget.markDirty();
    }

    fn segmentWidth(part: Part) u16 {
        const icon_width = if (part.icon) |ic| addUsizeClamped(ic.len, 1) else 0;
        return clampUsizeToU16(addUsizeClamped(icon_width, part.label.len));
    }

    const VisibleSegment = struct {
        idx: ?usize,
        width: u16,
    };

    fn remaining(cursor: u16, limit: u16) usize {
        if (cursor >= limit) return 0;
        return @intCast(limit - cursor);
    }

    fn computeVisible(self: *Breadcrumbs, available: u16, visible: *std.ArrayListUnmanaged(VisibleSegment)) !void {
        visible.clearRetainingCapacity();
        if (self.parts.items.len == 0 or available == 0) return;
        const available_width: usize = available;
        const sep_width = self.separator.len;
        var used: usize = 0;
        var idx: usize = self.parts.items.len;
        while (idx > 0) {
            idx -= 1;
            const width = segmentWidth(self.parts.items[idx]);
            const width_usize: usize = width;
            const extra = if (visible.items.len > 0) sep_width else 0;
            const needed = addUsizeClamped(addUsizeClamped(used, width_usize), extra);
            if (visible.items.len > 0 and needed > available_width) break;
            used = needed;
            try visible.append(self.allocator, .{ .idx = idx, .width = width });
        }
        std.mem.reverse(VisibleSegment, visible.items);
        if (visible.items.len < self.parts.items.len and visible.items.len > 0) {
            const overflow_width: u16 = @intCast(@min(self.overflow_token.len, @as(usize, available)));
            try visible.insert(self.allocator, 0, .{ .idx = null, .width = overflow_width });
        }
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Breadcrumbs = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible) return;
        const rect = self.widget.rect;
        var segments = std.ArrayListUnmanaged(VisibleSegment).empty;
        defer segments.deinit(self.allocator);
        try self.computeVisible(rect.width, &segments);

        var cursor: u16 = rect.x;
        const limit = offsetCoord(rect.x, rect.width);
        for (segments.items, 0..) |seg, idx| {
            if (seg.idx) |real_idx| {
                const part = self.parts.items[real_idx];
                if (part.icon) |icon_text| {
                    const icon_draw_len = @min(icon_text.len, remaining(cursor, limit));
                    const icon_draw = icon_text[0..icon_draw_len];
                    renderer.drawStr(cursor, rect.y, icon_draw, render.Color.named(.bright_black), render.Color.named(.default), render.Style{ .bold = true });
                    cursor = offsetCoord(cursor, icon_draw_len);
                    if (cursor < limit and remaining(cursor, limit) > 0) {
                        renderer.drawChar(cursor, rect.y, ' ', render.Color.named(.default), render.Color.named(.default), render.Style{});
                        cursor = offsetCoord(cursor, 1);
                    }
                }

                const draw_part = part.label[0..@min(part.label.len, remaining(cursor, limit))];
                const is_last = idx == segments.items.len - 1;
                const color = if (is_last) render.Color.named(.white) else render.Color.named(.cyan);
                const style = if (is_last) render.Style{ .bold = true } else render.Style{};
                renderer.drawStr(cursor, rect.y, draw_part, color, render.Color.named(.default), style);
                cursor = offsetCoord(cursor, draw_part.len);
            } else {
                const overflow_draw = self.overflow_token[0..@min(self.overflow_token.len, remaining(cursor, limit))];
                renderer.drawStr(cursor, rect.y, overflow_draw, render.Color.named(.bright_black), render.Color.named(.default), render.Style{ .bold = true });
                cursor = offsetCoord(cursor, overflow_draw.len);
            }

            if (idx + 1 < segments.items.len and cursor < limit) {
                const sep_draw = self.separator[0..@min(self.separator.len, remaining(cursor, limit))];
                renderer.drawStr(cursor, rect.y, sep_draw, render.Color.named(.bright_black), render.Color.named(.default), render.Style{});
                cursor = offsetCoord(cursor, sep_draw.len);
            }
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Breadcrumbs = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.enabled or self.on_click == null or self.parts.items.len == 0) return false;
        if (event != .mouse) return false;
        const mouse = event.mouse;
        if (mouse.action != .press or mouse.button != 1) return false;
        const mx = mouse.x;
        const my = mouse.y;
        if (my != self.widget.rect.y) return false;

        var segments = std.ArrayListUnmanaged(VisibleSegment).empty;
        defer segments.deinit(self.allocator);
        try self.computeVisible(self.widget.rect.width, &segments);

        var cursor: u16 = self.widget.rect.x;
        const limit = offsetCoord(self.widget.rect.x, self.widget.rect.width);
        for (segments.items) |seg| {
            if (seg.idx) |idx| {
                const start = cursor;
                const end = offsetCoord(cursor, seg.width);
                if (mx >= start and mx < end) {
                    self.on_click.?(idx);
                    return true;
                }
            }
            cursor = offsetCoord(cursor, seg.width);
            if (cursor < limit) {
                cursor = offsetCoord(cursor, @min(self.separator.len, remaining(cursor, limit)));
            }
        }
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Breadcrumbs = @fieldParentPtr("widget", widget_ref);
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Breadcrumbs = @fieldParentPtr("widget", widget_ref);
        var width: usize = 0;
        for (self.parts.items, 0..) |part, idx| {
            const icon_width = if (part.icon) |ic| addUsizeClamped(ic.len, 1) else 0;
            width = addUsizeClamped(width, addUsizeClamped(part.label.len, icon_width));
            if (idx + 1 < self.parts.items.len) width = addUsizeClamped(width, self.separator.len);
        }
        return layout_module.Size.init(@min(clampUsizeToU16(width), 200), 1);
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
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.menu), "Pagination", "");
        return self;
    }

    pub fn deinit(self: *Pagination) void {
        self.allocator.destroy(self);
    }

    pub fn setPage(self: *Pagination, page: usize) void {
        const clamped = if (page < 1) 1 else if (page > self.total) self.total else page;
        if (clamped != self.current) {
            self.current = clamped;
            self.widget.markDirty();
            if (self.on_change) |cb| cb(self.current);
        }
    }

    fn previousPage(self: *Pagination) void {
        self.setPage(self.current -| 1);
    }

    fn nextPage(self: *Pagination) void {
        self.setPage(addUsizeClamped(self.current, 1));
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Pagination = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible) return;
        const rect = self.widget.rect;
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', render.Color.named(.default), render.Color.named(.default), render.Style{});
        if (rect.width == 0 or rect.height == 0) return;

        const prev = "<";
        const next = ">";
        const fg = render.Color.named(.white);
        renderer.drawStr(rect.x, rect.y, prev, fg, render.Color.named(.default), render.Style{ .bold = self.current > 1 });

        const width: usize = rect.width;
        var cursor_offset: usize = @min(width, 2);
        const page_limit = if (width > 2) width - 2 else width;
        var page: usize = 1;
        while (page <= self.total and cursor_offset < page_limit) : (page += 1) {
            var buf: [8]u8 = undefined;
            const rendered = std.fmt.bufPrint(&buf, "{d}", .{page}) catch buf[0..0];
            const remaining_width = page_limit - cursor_offset;
            const draw_text = rendered[0..@min(rendered.len, remaining_width)];
            const fg_page = if (page == self.current) render.Color.named(.black) else fg;
            const bg_page = if (page == self.current) render.Color.named(.green) else render.Color.named(.default);
            renderer.drawStr(offsetCoord(rect.x, cursor_offset), rect.y, draw_text, fg_page, bg_page, render.Style{ .bold = page == self.current });
            cursor_offset += rendered.len + 1;
        }
        if (width > 1) {
            const next_offset = if (width > 2) width - 2 else width - 1;
            renderer.drawStr(offsetCoord(rect.x, next_offset), rect.y, next, fg, render.Color.named(.default), render.Style{ .bold = self.current < self.total });
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Pagination = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible or !self.widget.enabled) return false;

        switch (event) {
            .key => |key| {
                if (!self.widget.focused) return false;
                switch (key.key) {
                    'h', 'H', input.KeyCode.LEFT => {
                        self.previousPage();
                        return true;
                    },
                    'l', 'L', input.KeyCode.RIGHT => {
                        self.nextPage();
                        return true;
                    },
                    else => {},
                }
            },
            .mouse => |mouse| {
                if (mouse.action == .press and mouse.button == 1 and self.widget.rect.contains(mouse.x, mouse.y)) {
                    const rect = self.widget.rect;
                    const prev_end = if (rect.width > 1) offsetCoord(rect.x, 1) else rect.x;
                    if (mouse.x <= prev_end) {
                        self.previousPage();
                        return true;
                    }
                    const next_offset = if (rect.width > 2) rect.width - 2 else if (rect.width > 1) rect.width - 1 else 0;
                    const next_start = offsetCoord(rect.x, next_offset);
                    if (mouse.x >= next_start) {
                        self.nextPage();
                        return true;
                    }
                }
            },
            else => {},
        }
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Pagination = @fieldParentPtr("widget", widget_ref);
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(_: *anyopaque) anyerror!layout_module.Size {
        return layout_module.Size.init(20, 1);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Pagination = @fieldParentPtr("widget", widget_ref);
        return self.widget.enabled;
    }
};

/// CommandPalette surfaces a list of actions filtered by a query.
pub const CommandPalette = struct {
    widget: base.Widget,
    title: []const u8 = "Command Palette",
    query: []const u8 = "",
    commands: std.ArrayListUnmanaged([]const u8),
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
            .commands = .empty,
            .allocator = allocator,
        };
        errdefer self.deinit();

        for (commands) |cmd| {
            try appendOwnedString(&self.commands, self.allocator, cmd);
        }
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.menu), self.title, "");
        return self;
    }

    pub fn deinit(self: *CommandPalette) void {
        freeStringList(&self.commands, self.allocator);
        self.commands.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn setQuery(self: *CommandPalette, query: []const u8) void {
        const changed = !std.mem.eql(u8, self.query, query);
        self.query = query;
        if (changed) self.widget.markDirty();
    }

    fn clampSelection(self: *CommandPalette) void {
        if (self.commands.items.len == 0) {
            self.selected = 0;
        } else if (self.selected >= self.commands.items.len) {
            self.selected = self.commands.items.len - 1;
        }
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *CommandPalette = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible) return;
        const rect = self.widget.rect;
        const fg = render.Color.named(.white);
        const bg = render.Color.named(.black);
        if (rect.width == 0 or rect.height == 0) return;

        self.clampSelection();
        renderer.drawBox(rect.x, rect.y, rect.width, rect.height, .rounded, fg, bg, render.Style{ .bold = true });
        if (rect.height < 3) return;

        const width: usize = rect.width;
        const content_offset: usize = if (width > 2) 2 else 0;
        const content_width: usize = if (width > 4) width - 4 else width - content_offset;
        if (content_width == 0) return;

        const content_x = offsetCoord(rect.x, content_offset);
        renderer.drawStr(content_x, offsetCoord(rect.y, 1), self.title[0..@min(self.title.len, content_width)], fg, bg, render.Style{ .bold = true });
        renderer.drawStr(content_x, offsetCoord(rect.y, 2), self.query[0..@min(self.query.len, content_width)], render.Color.named(.bright_cyan), bg, render.Style{});

        const max_rows = if (rect.height > 4) rect.height - 4 else 0;
        for (self.commands.items, 0..) |cmd, idx| {
            if (idx >= max_rows) break;
            const cmd_fg = if (idx == self.selected) render.Color.named(.black) else fg;
            const cmd_bg = if (idx == self.selected) render.Color.named(.cyan) else bg;
            renderer.drawStr(content_x, offsetCoord(rect.y, 3 + idx), cmd[0..@min(cmd.len, content_width)], cmd_fg, cmd_bg, render.Style{});
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *CommandPalette = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible or !self.widget.enabled) return false;

        switch (event) {
            .key => |key| {
                if (!self.widget.focused) return false;
                self.clampSelection();
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
                        if (self.commands.items.len == 0) return false;
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
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *CommandPalette = @fieldParentPtr("widget", widget_ref);
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(_: *anyopaque) anyerror!layout_module.Size {
        return layout_module.Size.init(30, 8);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *CommandPalette = @fieldParentPtr("widget", widget_ref);
        return self.widget.enabled;
    }
};

/// Notification center stacks transient and sticky messages.
pub const NotificationCenter = struct {
    widget: base.Widget,
    notifications: std.ArrayListUnmanaged(Notification),
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
            .notifications = .empty,
            .allocator = allocator,
        };
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.alert), "Notification center", "");
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
        try self.notifications.ensureUnusedCapacity(self.allocator, 1);
        const title_copy = try self.allocator.dupe(u8, title);
        errdefer self.allocator.free(title_copy);
        const body_copy = try self.allocator.dupe(u8, body);
        const duped = Notification{
            .title = title_copy,
            .body = body_copy,
            .level = level,
        };
        self.notifications.appendAssumeCapacity(duped);
        self.widget.markDirty();
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *NotificationCenter = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible) return;
        const rect = self.widget.rect;
        if (rect.width == 0 or rect.height == 0) return;

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
            const row_y = offsetCoord(rect.y, y);
            renderer.fillRect(rect.x, row_y, rect.width, 1, ' ', colors[0], colors[1], render.Style{});

            const text_x = if (rect.width > 1) offsetCoord(rect.x, 1) else rect.x;
            const title_width: usize = if (rect.width > 1) rect.width - 1 else rect.width;
            const title = note.title[0..@min(note.title.len, title_width)];
            renderer.drawStr(text_x, row_y, title, colors[0], colors[1], render.Style{ .bold = true });

            const body_offset = title.len + 1;
            if (rect.width > 2 and body_offset < rect.width - 1) {
                const space_left = rect.width - 1 - body_offset;
                const body = note.body[0..@min(note.body.len, space_left)];
                renderer.drawStr(offsetCoord(text_x, body_offset), row_y, body, colors[0], colors[1], render.Style{});
            }
            _ = idx;
            y += 1;
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *NotificationCenter = @fieldParentPtr("widget", widget_ref);
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
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *NotificationCenter = @fieldParentPtr("widget", widget_ref);
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(_: *anyopaque) anyerror!layout_module.Size {
        return layout_module.Size.init(30, 3);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *NotificationCenter = @fieldParentPtr("widget", widget_ref);
        return self.widget.enabled;
    }
};

/// Accordion groups panels that expand and collapse.
pub const Accordion = struct {
    widget: base.Widget,
    sections: std.ArrayListUnmanaged(Section),
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
            .sections = .empty,
            .allocator = allocator,
        };
        errdefer self.deinit();

        for (sections) |section| {
            try appendOwnedSection(&self.sections, self.allocator, section);
        }
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.list), "Accordion", "");
        return self;
    }

    pub fn deinit(self: *Accordion) void {
        freeSectionList(&self.sections, self.allocator);
        self.sections.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Accordion = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible) return;
        const rect = self.widget.rect;
        if (rect.width == 0 or rect.height == 0) return;

        var row: u16 = 0;
        for (self.sections.items, 0..) |section, idx| {
            if (row >= rect.height) break;
            const y = offsetCoord(rect.y, row);
            const prefix = if (section.expanded) "▼" else "►";
            renderer.drawStr(rect.x, y, prefix, render.Color.named(.yellow), render.Color.named(.default), render.Style{ .bold = true });
            if (rect.width > 2) {
                const title = section.title[0..@min(section.title.len, rect.width - 2)];
                renderer.drawStr(offsetCoord(rect.x, 2), y, title, render.Color.named(.white), render.Color.named(.default), render.Style{});
            }
            row += 1;
            if (section.expanded and row < rect.height) {
                const body_y = offsetCoord(rect.y, row);
                if (rect.width > 2) {
                    const body = section.body[0..@min(section.body.len, rect.width - 2)];
                    renderer.drawStr(offsetCoord(rect.x, 2), body_y, body, render.Color.named(.bright_white), render.Color.named(.default), render.Style{});
                }
                row += 1;
            }
            _ = idx;
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Accordion = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible or !self.widget.enabled) return false;
        switch (event) {
            .mouse => |mouse| {
                if (mouse.action == .press and mouse.button == 1 and self.widget.rect.contains(mouse.x, mouse.y)) {
                    const offset: usize = mouse.y - self.widget.rect.y;
                    var y: usize = 0;
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
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Accordion = @fieldParentPtr("widget", widget_ref);
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Accordion = @fieldParentPtr("widget", widget_ref);
        const height = accordionPreferredHeight(self.sections.items.len);
        return layout_module.Size.init(20, height);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Accordion = @fieldParentPtr("widget", widget_ref);
        return self.widget.enabled;
    }
};

/// WizardStepper shows progress across multiple steps.
pub const WizardStepper = struct {
    widget: base.Widget,
    steps: std.ArrayListUnmanaged([]const u8),
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
            .steps = .empty,
            .allocator = allocator,
        };
        errdefer self.deinit();

        for (steps) |step| {
            try appendOwnedString(&self.steps, self.allocator, step);
        }
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.list), "Wizard stepper", "");
        return self;
    }

    pub fn deinit(self: *WizardStepper) void {
        freeStringList(&self.steps, self.allocator);
        self.steps.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn setStep(self: *WizardStepper, idx: usize) void {
        if (idx < self.steps.items.len and self.current != idx) {
            self.current = idx;
            self.widget.markDirty();
        }
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *WizardStepper = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible) return;
        const rect = self.widget.rect;
        if (self.steps.items.len == 0 or rect.width == 0 or rect.height == 0) return;
        const active = @min(self.current, self.steps.items.len - 1);

        var cursor_offset: usize = 0;
        for (self.steps.items, 0..) |step, idx| {
            if (cursor_offset >= rect.width) break;
            var buf: [32]u8 = undefined;
            const rendered = std.fmt.bufPrint(&buf, "{d}. {s}", .{ idx + 1, step }) catch buf[0..0];
            const slice = rendered;
            const remaining_width = rect.width - cursor_offset;
            const selected = idx == active;
            const fg = if (selected) render.Color.named(.black) else render.Color.named(.white);
            const bg = if (selected) render.Color.named(.green) else render.Color.named(.default);
            renderer.drawStr(offsetCoord(rect.x, cursor_offset), rect.y, slice[0..@min(slice.len, remaining_width)], fg, bg, render.Style{ .bold = selected });
            cursor_offset += slice.len + 2;
        }

        // Progress bar along bottom if height > 1
        if (rect.height > 1 and self.steps.items.len > 0) {
            const progress = @as(f32, @floatFromInt(active + 1)) / @as(f32, @floatFromInt(self.steps.items.len));
            const fill = @as(usize, @intFromFloat(progress * @as(f32, @floatFromInt(rect.width))));
            const progress_y = offsetCoord(rect.y, rect.height - 1);
            var x_offset: usize = 0;
            while (x_offset < rect.width) : (x_offset += 1) {
                const filled = x_offset < fill;
                renderer.drawChar(offsetCoord(rect.x, x_offset), progress_y, if (filled) '█' else '░', render.Color.named(.green), render.Color.named(.default), render.Style{});
            }
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *WizardStepper = @fieldParentPtr("widget", widget_ref);
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
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *WizardStepper = @fieldParentPtr("widget", widget_ref);
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *WizardStepper = @fieldParentPtr("widget", widget_ref);
        var width: usize = 0;
        for (self.steps.items) |step| width = addPaddedLenClamped(width, step.len, 4);
        return layout_module.Size.init(@min(clampUsizeToU16(width), 200), 2);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *WizardStepper = @fieldParentPtr("widget", widget_ref);
        return self.widget.enabled;
    }
};

test "advanced control preferred sizing saturates before capping" {
    try std.testing.expectEqual(@as(u16, 60), cappedPaddedWidth(std.math.maxInt(usize), 8, 60));
    try std.testing.expectEqual(@as(u16, 80), cappedPaddedWidth(std.math.maxInt(usize) - 1, 5, 80));
    try std.testing.expectEqual(@as(u16, 6), accordionPreferredHeight(3));
    try std.testing.expectEqual(@as(u16, std.math.maxInt(u16)), accordionPreferredHeight(std.math.maxInt(usize)));

    var width = addPaddedLenClamped(std.math.maxInt(usize) - 1, std.math.maxInt(usize) - 2, 4);
    try std.testing.expectEqual(std.math.maxInt(usize), width);

    width = addPaddedLenClamped(1, 116, 3);
    try std.testing.expectEqual(@as(usize, 120), width);
}

test "toggle switch renders state" {
    const alloc = std.testing.allocator;

    var toggle = try ToggleSwitch.init(alloc, "Turbo");
    defer toggle.deinit();
    toggle.set(true);

    var snap = try testing.renderWidget(alloc, &toggle.widget, layout_module.Size.init(16, 1));
    defer snap.deinit(alloc);
    try snap.expectEqual("[ ON ] Turbo    \n");
}

test "toggle switch marks dirty when visible state changes" {
    const alloc = std.testing.allocator;

    var toggle = try ToggleSwitch.init(alloc, "Turbo");
    defer toggle.deinit();

    try toggle.widget.layout(layout_module.Rect.init(0, 0, 16, 1));
    var renderer = try render.Renderer.init(alloc, 16, 1);
    defer renderer.deinit();

    try toggle.widget.draw(&renderer);
    try std.testing.expect(!toggle.widget.dirty);

    toggle.set(true);
    try std.testing.expect(toggle.widget.dirty);
    try toggle.widget.draw(&renderer);
    try std.testing.expect(!toggle.widget.dirty);

    toggle.set(true);
    try std.testing.expect(!toggle.widget.dirty);

    toggle.toggle();
    try std.testing.expect(!toggle.on);
    try std.testing.expect(toggle.widget.dirty);
}

test "toggle switch mouse toggles rendered row only" {
    const alloc = std.testing.allocator;
    var toggle = try ToggleSwitch.init(alloc, "Turbo");
    defer toggle.deinit();

    toggle.widget.rect = layout_module.Rect.init(4, 3, 14, 1);

    try std.testing.expect(!try toggle.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 6, 2, 1, 0) }));
    try std.testing.expect(!toggle.on);

    try std.testing.expect(try toggle.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 6, 3, 1, 0) }));
    try std.testing.expect(toggle.on);
}

test "toggle switch draws narrow edge rectangles" {
    const alloc = std.testing.allocator;
    var toggle = try ToggleSwitch.init(alloc, "Turbo");
    defer toggle.deinit();

    {
        var snap = try testing.renderWidget(alloc, &toggle.widget, layout_module.Size.init(1, 1));
        defer snap.deinit(alloc);
        try snap.expectWellFormed();
    }

    var renderer = try render.Renderer.init(alloc, 4, 1);
    defer renderer.deinit();

    try toggle.widget.layout(layout_module.Rect.init(std.math.maxInt(u16) - 1, std.math.maxInt(u16), 1, 1));
    try toggle.widget.draw(&renderer);
}

test "radio group updates selection" {
    const alloc = std.testing.allocator;

    var radio = try RadioGroup.init(alloc, &[_][]const u8{ "A", "B", "C" });
    defer radio.deinit();
    radio.setSelected(2);

    var snap = try testing.renderWidget(alloc, &radio.widget, layout_module.Size.init(6, 3));
    defer snap.deinit(alloc);
    try snap.expectEqual("( ) A \n( ) B \n(*) C \n");
}

test "radio group marks dirty when selection changes" {
    const alloc = std.testing.allocator;

    var radio = try RadioGroup.init(alloc, &[_][]const u8{ "A", "B", "C" });
    defer radio.deinit();

    try radio.widget.layout(layout_module.Rect.init(0, 0, 6, 3));
    var renderer = try render.Renderer.init(alloc, 6, 3);
    defer renderer.deinit();

    try radio.widget.draw(&renderer);
    try std.testing.expect(!radio.widget.dirty);

    radio.setSelected(2);
    try std.testing.expect(radio.widget.dirty);
    try radio.widget.draw(&renderer);
    try std.testing.expect(!radio.widget.dirty);

    radio.setSelected(2);
    try std.testing.expect(!radio.widget.dirty);
    radio.setSelected(99);
    try std.testing.expect(!radio.widget.dirty);
}

test "radio group mouse selects rendered option rows" {
    const alloc = std.testing.allocator;
    var radio = try RadioGroup.init(alloc, &[_][]const u8{ "A", "B", "C" });
    defer radio.deinit();

    radio.widget.rect = layout_module.Rect.init(5, 4, 8, 3);

    try std.testing.expect(!try radio.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 6, 3, 1, 0) }));
    try std.testing.expectEqual(@as(usize, 0), radio.selected);

    try std.testing.expect(try radio.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 6, 5, 1, 0) }));
    try std.testing.expectEqual(@as(usize, 1), radio.selected);
}

test "radio group keyboard clamps stale selection" {
    const alloc = std.testing.allocator;
    var radio = try RadioGroup.init(alloc, &[_][]const u8{ "A", "B", "C" });
    defer radio.deinit();

    radio.widget.focused = true;
    radio.selected = std.math.maxInt(usize);

    try std.testing.expect(!try radio.widget.handleEvent(.{ .key = input.KeyEvent.init('j', .{}) }));
    try std.testing.expectEqual(@as(usize, 2), radio.selected);

    try std.testing.expect(try radio.widget.handleEvent(.{ .key = input.KeyEvent.init('k', .{}) }));
    try std.testing.expectEqual(@as(usize, 1), radio.selected);
}

test "radio group draw clamps stale selection" {
    const alloc = std.testing.allocator;
    var radio = try RadioGroup.init(alloc, &[_][]const u8{ "A", "B", "C" });
    defer radio.deinit();

    radio.selected = std.math.maxInt(usize);

    var snap = try testing.renderWidget(alloc, &radio.widget, layout_module.Size.init(6, 3));
    defer snap.deinit(alloc);
    try snap.expectEqual("( ) A \n( ) B \n(*) C \n");
    try std.testing.expectEqual(@as(usize, 2), radio.selected);
}

test "radio group keyboard handles empty options" {
    const alloc = std.testing.allocator;
    var radio = try RadioGroup.init(alloc, &[_][]const u8{});
    defer radio.deinit();

    radio.widget.focused = true;
    radio.selected = std.math.maxInt(usize);

    try std.testing.expect(!try radio.widget.handleEvent(.{ .key = input.KeyEvent.init('j', .{}) }));
    try std.testing.expectEqual(@as(usize, 0), radio.selected);
}

test "radio group draws narrow edge rectangles" {
    const alloc = std.testing.allocator;
    var radio = try RadioGroup.init(alloc, &[_][]const u8{ "Alpha", "Beta" });
    defer radio.deinit();

    {
        var snap = try testing.renderWidget(alloc, &radio.widget, layout_module.Size.init(1, 2));
        defer snap.deinit(alloc);
        try snap.expectWellFormed();
    }

    var renderer = try render.Renderer.init(alloc, 4, 2);
    defer renderer.deinit();

    try radio.widget.layout(layout_module.Rect.init(std.math.maxInt(u16) - 1, std.math.maxInt(u16) - 1, 1, 2));
    try radio.widget.draw(&renderer);
}

test "slider clamps values" {
    const alloc = std.testing.allocator;
    var slider = try Slider.init(alloc, 0, 10);
    defer slider.deinit();
    slider.setValue(15);
    try std.testing.expectEqual(@as(f32, 10), slider.value);
}

test "slider normalizes non-finite values and ranges" {
    const alloc = std.testing.allocator;
    var slider = try Slider.init(alloc, 0, 10);
    defer slider.deinit();

    slider.setValue(std.math.nan(f32));
    try std.testing.expectEqual(@as(f32, 0), slider.value);

    slider.setValue(std.math.inf(f32));
    try std.testing.expectEqual(@as(f32, 10), slider.value);

    slider.setValue(-std.math.inf(f32));
    try std.testing.expectEqual(@as(f32, 0), slider.value);

    slider.min = std.math.nan(f32);
    slider.max = 10;
    slider.setValue(5);
    try std.testing.expectEqual(@as(f32, 0), slider.value);
}

test "slider marks dirty when normalized value changes" {
    const alloc = std.testing.allocator;
    var slider = try Slider.init(alloc, 0, 10);
    defer slider.deinit();

    try slider.widget.layout(layout_module.Rect.init(0, 0, 12, 1));
    var renderer = try render.Renderer.init(alloc, 12, 1);
    defer renderer.deinit();

    try slider.widget.draw(&renderer);
    try std.testing.expect(!slider.widget.dirty);

    slider.setValue(5);
    try std.testing.expect(slider.widget.dirty);
    try slider.widget.draw(&renderer);
    try std.testing.expect(!slider.widget.dirty);

    slider.setValue(5);
    try std.testing.expect(!slider.widget.dirty);

    slider.setValue(15);
    try std.testing.expect(slider.widget.dirty);
    try slider.widget.draw(&renderer);
    try std.testing.expect(!slider.widget.dirty);

    slider.setValue(std.math.inf(f32));
    try std.testing.expect(!slider.widget.dirty);

    slider.setValue(std.math.nan(f32));
    try std.testing.expect(slider.widget.dirty);
}

test "slider mouse maps rendered track to value" {
    const alloc = std.testing.allocator;
    var slider = try Slider.init(alloc, 0, 10);
    defer slider.deinit();

    slider.widget.rect = layout_module.Rect.init(3, 6, 12, 1);

    try std.testing.expect(!try slider.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 8, 5, 1, 0) }));
    try std.testing.expectEqual(@as(f32, 0), slider.value);

    try std.testing.expect(try slider.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 8, 6, 1, 0) }));
    try std.testing.expect(slider.value > 0);
    try std.testing.expect(slider.value < 10);
}

test "slider saturated input does not consume unchanged events" {
    const alloc = std.testing.allocator;
    var slider = try Slider.init(alloc, 0, 10);
    defer slider.deinit();

    slider.widget.focused = true;
    slider.widget.clearDirty();
    try std.testing.expect(!try slider.widget.handleEvent(.{ .key = input.KeyEvent.init(input.KeyCode.LEFT, .{}) }));
    try std.testing.expect(!slider.widget.dirty);
    try std.testing.expectEqual(@as(f32, 0), slider.value);

    try std.testing.expect(try slider.widget.handleEvent(.{ .key = input.KeyEvent.init(input.KeyCode.RIGHT, .{}) }));
    try std.testing.expect(slider.widget.dirty);

    slider.setValue(10);
    slider.widget.clearDirty();
    try std.testing.expect(!try slider.widget.handleEvent(.{ .key = input.KeyEvent.init(input.KeyCode.RIGHT, .{}) }));
    try std.testing.expect(!slider.widget.dirty);
    try std.testing.expectEqual(@as(f32, 10), slider.value);

    slider.widget.rect = layout_module.Rect.init(0, 0, 12, 1);
    slider.widget.clearDirty();
    try std.testing.expect(!try slider.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 10, 0, 1, 0) }));
    try std.testing.expect(!slider.widget.dirty);
}

test "slider draws with non-finite internal state" {
    const alloc = std.testing.allocator;
    var slider = try Slider.init(alloc, 0, 10);
    defer slider.deinit();

    slider.value = std.math.nan(f32);
    {
        var snap = try testing.renderWidget(alloc, &slider.widget, layout_module.Size.init(12, 1));
        defer snap.deinit(alloc);
        try snap.expectWellFormed();
    }

    slider.min = 0;
    slider.max = std.math.nan(f32);
    {
        var snap = try testing.renderWidget(alloc, &slider.widget, layout_module.Size.init(12, 1));
        defer snap.deinit(alloc);
        try snap.expectWellFormed();
    }
}

test "slider handles narrow edge rectangles and mouse input" {
    const alloc = std.testing.allocator;
    var slider = try Slider.init(alloc, 0, 10);
    defer slider.deinit();

    {
        var snap = try testing.renderWidget(alloc, &slider.widget, layout_module.Size.init(1, 1));
        defer snap.deinit(alloc);
        try snap.expectWellFormed();
    }

    slider.widget.rect = layout_module.Rect.init(5, 5, 1, 1);
    try std.testing.expect(!try slider.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 5, 5, 1, 0) }));
    try std.testing.expectEqual(@as(f32, 0), slider.value);

    var renderer = try render.Renderer.init(alloc, 4, 1);
    defer renderer.deinit();

    try slider.widget.layout(layout_module.Rect.init(std.math.maxInt(u16) - 3, std.math.maxInt(u16), 4, 1));
    try slider.widget.draw(&renderer);
}

test "rating stars increments with input" {
    const alloc = std.testing.allocator;
    var stars = try RatingStars.init(alloc, 3);
    defer stars.deinit();
    stars.setValue(2);
    try std.testing.expectEqual(@as(f32, 2), stars.value);
}

test "rating stars normalize non-finite values" {
    const alloc = std.testing.allocator;
    var stars = try RatingStars.init(alloc, 3);
    defer stars.deinit();

    stars.setValue(std.math.nan(f32));
    try std.testing.expectEqual(@as(f32, 0), stars.value);

    stars.setValue(std.math.inf(f32));
    try std.testing.expectEqual(@as(f32, 3), stars.value);

    stars.setValue(-std.math.inf(f32));
    try std.testing.expectEqual(@as(f32, 0), stars.value);
}

test "rating stars marks dirty when normalized value changes" {
    const alloc = std.testing.allocator;
    var stars = try RatingStars.init(alloc, 5);
    defer stars.deinit();

    try stars.widget.layout(layout_module.Rect.init(0, 0, 5, 1));
    var renderer = try render.Renderer.init(alloc, 5, 1);
    defer renderer.deinit();

    try stars.widget.draw(&renderer);
    try std.testing.expect(!stars.widget.dirty);

    stars.setValue(3);
    try std.testing.expect(stars.widget.dirty);
    try stars.widget.draw(&renderer);
    try std.testing.expect(!stars.widget.dirty);

    stars.setValue(3);
    try std.testing.expect(!stars.widget.dirty);

    stars.setValue(99);
    try std.testing.expect(stars.widget.dirty);
    try stars.widget.draw(&renderer);
    try std.testing.expect(!stars.widget.dirty);

    stars.setValue(std.math.inf(f32));
    try std.testing.expect(!stars.widget.dirty);

    stars.setValue(std.math.nan(f32));
    try std.testing.expect(stars.widget.dirty);
}

test "rating stars mouse maps rendered columns to values" {
    const alloc = std.testing.allocator;
    var stars = try RatingStars.init(alloc, 5);
    defer stars.deinit();

    stars.widget.rect = layout_module.Rect.init(7, 4, 5, 1);

    try std.testing.expect(!try stars.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 9, 3, 1, 0) }));
    try std.testing.expectEqual(@as(f32, 0), stars.value);

    try std.testing.expect(try stars.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 9, 4, 1, 0) }));
    try std.testing.expectEqual(@as(f32, 3), stars.value);
}

test "rating stars saturated input does not consume unchanged events" {
    const alloc = std.testing.allocator;
    var stars = try RatingStars.init(alloc, 5);
    defer stars.deinit();

    stars.widget.focused = true;
    stars.widget.clearDirty();
    try std.testing.expect(!try stars.widget.handleEvent(.{ .key = input.KeyEvent.init(input.KeyCode.LEFT, .{}) }));
    try std.testing.expect(!stars.widget.dirty);
    try std.testing.expectEqual(@as(f32, 0), stars.value);

    try std.testing.expect(try stars.widget.handleEvent(.{ .key = input.KeyEvent.init(input.KeyCode.RIGHT, .{}) }));
    try std.testing.expect(stars.widget.dirty);

    stars.setValue(5);
    stars.widget.clearDirty();
    try std.testing.expect(!try stars.widget.handleEvent(.{ .key = input.KeyEvent.init(input.KeyCode.RIGHT, .{}) }));
    try std.testing.expect(!stars.widget.dirty);
    try std.testing.expectEqual(@as(f32, 5), stars.value);

    stars.widget.rect = layout_module.Rect.init(0, 0, 5, 1);
    stars.widget.clearDirty();
    try std.testing.expect(!try stars.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 4, 0, 1, 0) }));
    try std.testing.expect(!stars.widget.dirty);
}

test "rating stars draw with non-finite internal state" {
    const alloc = std.testing.allocator;
    var stars = try RatingStars.init(alloc, 5);
    defer stars.deinit();

    stars.value = std.math.nan(f32);
    var snap = try testing.renderWidget(alloc, &stars.widget, layout_module.Size.init(5, 1));
    defer snap.deinit(alloc);
    try snap.expectWellFormed();
}

test "rating stars draws narrow edge rectangles" {
    const alloc = std.testing.allocator;
    var stars = try RatingStars.init(alloc, 5);
    defer stars.deinit();

    {
        var snap = try testing.renderWidget(alloc, &stars.widget, layout_module.Size.init(1, 1));
        defer snap.deinit(alloc);
        try snap.expectWellFormed();
    }

    var renderer = try render.Renderer.init(alloc, 4, 1);
    defer renderer.deinit();

    try stars.widget.layout(layout_module.Rect.init(std.math.maxInt(u16) - 1, std.math.maxInt(u16), 1, 1));
    try stars.widget.draw(&renderer);
}

test "status bar renders long segments in narrow rects" {
    const alloc = std.testing.allocator;
    var status = try StatusBar.init(alloc);
    defer status.deinit();

    status.setSegments("left", "center text wider than the bar", "right");
    var snap = try testing.renderWidget(alloc, &status.widget, layout_module.Size.init(4, 1));
    defer snap.deinit(alloc);

    try snap.expectWellFormed();
    try std.testing.expectEqual(@as(u16, 4), snap.width);
    try std.testing.expectEqual(@as(u16, 1), snap.height);
}

test "status bar marks dirty when segments change" {
    const alloc = std.testing.allocator;
    var status = try StatusBar.init(alloc);
    defer status.deinit();

    try status.widget.layout(layout_module.Rect.init(0, 0, 20, 1));
    var renderer = try render.Renderer.init(alloc, 20, 1);
    defer renderer.deinit();

    try status.widget.draw(&renderer);
    try std.testing.expect(!status.widget.dirty);

    status.setSegments("left", "center", "right");
    try std.testing.expect(status.widget.dirty);
    try status.widget.draw(&renderer);
    try std.testing.expect(!status.widget.dirty);

    status.setSegments("left", "center", "right");
    try std.testing.expect(!status.widget.dirty);

    status.setSegments("left", "center", "");
    try std.testing.expect(status.widget.dirty);
}

test "status bar clamps far right draw offsets" {
    const alloc = std.testing.allocator;
    var status = try StatusBar.init(alloc);
    defer status.deinit();

    var renderer = try render.Renderer.init(alloc, 4, 1);
    defer renderer.deinit();

    status.setSegments("left", "center", "right");
    try status.widget.layout(layout_module.Rect.init(std.math.maxInt(u16) - 1, 0, 4, 1));
    try status.widget.draw(&renderer);
}

test "notification center draws narrow edge rectangles" {
    const alloc = std.testing.allocator;
    var center = try NotificationCenter.init(alloc);
    defer center.deinit();

    try center.push("Build", "Started", .info);
    try center.push("Deploy", "Finished", .success);

    {
        var snap = try testing.renderWidget(alloc, &center.widget, layout_module.Size.init(1, 2));
        defer snap.deinit(alloc);
        try snap.expectWellFormed();
    }

    var renderer = try render.Renderer.init(alloc, 4, 2);
    defer renderer.deinit();

    try center.widget.layout(layout_module.Rect.init(std.math.maxInt(u16) - 1, std.math.maxInt(u16) - 1, 1, 2));
    try center.widget.draw(&renderer);
}

test "notification center marks dirty when notification is pushed" {
    const alloc = std.testing.allocator;
    var center = try NotificationCenter.init(alloc);
    defer center.deinit();

    try center.widget.layout(layout_module.Rect.init(0, 0, 24, 2));
    var renderer = try render.Renderer.init(alloc, 24, 2);
    defer renderer.deinit();

    try center.widget.draw(&renderer);
    try std.testing.expect(!center.widget.dirty);

    try center.push("Build", "Started", .info);
    try std.testing.expect(center.widget.dirty);
    try center.widget.draw(&renderer);
    try std.testing.expect(!center.widget.dirty);

    try center.push("Deploy", "Finished", .success);
    try std.testing.expect(center.widget.dirty);
}

test "pagination advances pages" {
    const alloc = std.testing.allocator;
    var pager = try Pagination.init(alloc, 5);
    defer pager.deinit();
    pager.setPage(3);
    try std.testing.expectEqual(@as(usize, 3), pager.current);
}

test "pagination draws narrow edge rectangles" {
    const alloc = std.testing.allocator;
    var pager = try Pagination.init(alloc, 5);
    defer pager.deinit();

    {
        var snap = try testing.renderWidget(alloc, &pager.widget, layout_module.Size.init(1, 1));
        defer snap.deinit(alloc);
        try snap.expectWellFormed();
    }

    var renderer = try render.Renderer.init(alloc, 4, 1);
    defer renderer.deinit();

    try pager.widget.layout(layout_module.Rect.init(std.math.maxInt(u16) - 1, std.math.maxInt(u16), 1, 1));
    try pager.widget.draw(&renderer);
}

test "command palette draws narrow edge rectangles" {
    const alloc = std.testing.allocator;
    var palette = try CommandPalette.init(alloc, &[_][]const u8{ "Open file", "Run tests" });
    defer palette.deinit();

    {
        var snap = try testing.renderWidget(alloc, &palette.widget, layout_module.Size.init(1, 3));
        defer snap.deinit(alloc);
        try snap.expectWellFormed();
    }

    var renderer = try render.Renderer.init(alloc, 4, 3);
    defer renderer.deinit();

    try palette.widget.layout(layout_module.Rect.init(std.math.maxInt(u16) - 1, std.math.maxInt(u16) - 2, 1, 3));
    try palette.widget.draw(&renderer);
}

var command_palette_executed_index: ?usize = null;

fn recordCommandPaletteExecution(index: usize, _: []const u8) void {
    command_palette_executed_index = index;
}

test "command palette clamps stale selection before execution" {
    const alloc = std.testing.allocator;
    var palette = try CommandPalette.init(alloc, &[_][]const u8{ "Open file", "Run tests" });
    defer palette.deinit();

    command_palette_executed_index = null;
    palette.widget.focused = true;
    palette.selected = std.math.maxInt(usize);
    palette.on_execute = recordCommandPaletteExecution;

    try std.testing.expect(try palette.widget.handleEvent(.{ .key = input.KeyEvent.init('\n', .{}) }));
    try std.testing.expectEqual(@as(usize, 1), palette.selected);
    try std.testing.expectEqual(@as(?usize, 1), command_palette_executed_index);
}

test "command palette draw clamps stale selection" {
    const alloc = std.testing.allocator;
    var palette = try CommandPalette.init(alloc, &[_][]const u8{ "Open file", "Run tests" });
    defer palette.deinit();

    palette.selected = std.math.maxInt(usize);

    var snap = try testing.renderWidget(alloc, &palette.widget, layout_module.Size.init(14, 6));
    defer snap.deinit(alloc);
    try snap.expectWellFormed();
    try std.testing.expectEqual(@as(usize, 1), palette.selected);
}

test "command palette marks dirty when query changes" {
    const alloc = std.testing.allocator;
    var palette = try CommandPalette.init(alloc, &[_][]const u8{ "Open file", "Run tests" });
    defer palette.deinit();

    try palette.widget.layout(layout_module.Rect.init(0, 0, 24, 6));
    var renderer = try render.Renderer.init(alloc, 24, 6);
    defer renderer.deinit();

    try palette.widget.draw(&renderer);
    try std.testing.expect(!palette.widget.dirty);

    palette.setQuery("");
    try std.testing.expect(!palette.widget.dirty);

    palette.setQuery("run");
    try std.testing.expect(palette.widget.dirty);
    try palette.widget.draw(&renderer);
    try std.testing.expect(!palette.widget.dirty);

    palette.setQuery("run");
    try std.testing.expect(!palette.widget.dirty);
}

test "command palette ignores execution without commands" {
    const alloc = std.testing.allocator;
    var palette = try CommandPalette.init(alloc, &[_][]const u8{});
    defer palette.deinit();

    command_palette_executed_index = null;
    palette.widget.focused = true;
    palette.selected = std.math.maxInt(usize);
    palette.on_execute = recordCommandPaletteExecution;

    try std.testing.expect(!try palette.widget.handleEvent(.{ .key = input.KeyEvent.init('\n', .{}) }));
    try std.testing.expectEqual(@as(usize, 0), palette.selected);
    try std.testing.expectEqual(@as(?usize, null), command_palette_executed_index);
}

test "wizard stepper draws with stale current index" {
    const alloc = std.testing.allocator;
    var wizard = try WizardStepper.init(alloc, &[_][]const u8{ "Account", "Billing", "Confirm" });
    defer wizard.deinit();

    wizard.current = std.math.maxInt(usize);
    var snap = try testing.renderWidget(alloc, &wizard.widget, layout_module.Size.init(24, 2));
    defer snap.deinit(alloc);
    try snap.expectWellFormed();
}

test "wizard stepper marks dirty when current step changes" {
    const alloc = std.testing.allocator;
    var wizard = try WizardStepper.init(alloc, &[_][]const u8{ "Account", "Billing", "Confirm" });
    defer wizard.deinit();

    try wizard.widget.layout(layout_module.Rect.init(0, 0, 30, 2));
    var renderer = try render.Renderer.init(alloc, 30, 2);
    defer renderer.deinit();

    try wizard.widget.draw(&renderer);
    try std.testing.expect(!wizard.widget.dirty);

    wizard.setStep(0);
    try std.testing.expect(!wizard.widget.dirty);

    wizard.setStep(2);
    try std.testing.expect(wizard.widget.dirty);
    try wizard.widget.draw(&renderer);
    try std.testing.expect(!wizard.widget.dirty);

    wizard.setStep(2);
    try std.testing.expect(!wizard.widget.dirty);
    wizard.setStep(99);
    try std.testing.expect(!wizard.widget.dirty);
}

test "wizard stepper draws narrow edge rectangles" {
    const alloc = std.testing.allocator;
    var wizard = try WizardStepper.init(alloc, &[_][]const u8{ "Account", "Billing", "Confirm" });
    defer wizard.deinit();

    {
        var snap = try testing.renderWidget(alloc, &wizard.widget, layout_module.Size.init(1, 2));
        defer snap.deinit(alloc);
        try snap.expectWellFormed();
    }

    var renderer = try render.Renderer.init(alloc, 4, 2);
    defer renderer.deinit();

    try wizard.widget.layout(layout_module.Rect.init(std.math.maxInt(u16) - 1, std.math.maxInt(u16) - 1, 1, 2));
    try wizard.widget.draw(&renderer);
}

test "toolbar mouse selects rendered item row" {
    const alloc = std.testing.allocator;
    var toolbar = try Toolbar.init(alloc, &[_][]const u8{ "Open", "Save", "Close" });
    defer toolbar.deinit();

    toolbar.widget.rect = layout_module.Rect.init(5, 8, 30, 1);

    try std.testing.expect(!try toolbar.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 14, 7, 1, 0) }));
    try std.testing.expectEqual(@as(usize, 0), toolbar.active);

    try std.testing.expect(try toolbar.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 14, 8, 1, 0) }));
    try std.testing.expectEqual(@as(usize, 1), toolbar.active);
}

test "toolbar marks dirty when active item changes" {
    const alloc = std.testing.allocator;
    var toolbar = try Toolbar.init(alloc, &[_][]const u8{ "Open", "Save", "Close" });
    defer toolbar.deinit();

    try toolbar.widget.layout(layout_module.Rect.init(0, 0, 30, 1));
    var renderer = try render.Renderer.init(alloc, 30, 1);
    defer renderer.deinit();

    try toolbar.widget.draw(&renderer);
    try std.testing.expect(!toolbar.widget.dirty);

    toolbar.setActive(1);
    try std.testing.expect(toolbar.widget.dirty);
    try toolbar.widget.draw(&renderer);
    try std.testing.expect(!toolbar.widget.dirty);

    toolbar.setActive(1);
    try std.testing.expect(!toolbar.widget.dirty);
    toolbar.setActive(99);
    try std.testing.expect(!toolbar.widget.dirty);

    toolbar.widget.focused = true;
    try std.testing.expect(try toolbar.widget.handleEvent(.{ .key = input.KeyEvent.init(input.KeyCode.RIGHT, .{}) }));
    try std.testing.expectEqual(@as(usize, 2), toolbar.active);
    try std.testing.expect(toolbar.widget.dirty);
    try toolbar.widget.draw(&renderer);
    try std.testing.expect(!toolbar.widget.dirty);

    try std.testing.expect(try toolbar.widget.handleEvent(.{ .key = input.KeyEvent.init(input.KeyCode.RIGHT, .{}) }));
    try std.testing.expectEqual(@as(usize, 2), toolbar.active);
    try std.testing.expect(toolbar.widget.dirty);
    try toolbar.widget.draw(&renderer);
    try std.testing.expect(!toolbar.widget.dirty);

    try std.testing.expect(try toolbar.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 1, 0, 1, 0) }));
    try std.testing.expectEqual(@as(usize, 0), toolbar.active);
    try std.testing.expect(toolbar.widget.dirty);
}

test "toolbar clamps far-edge render coordinates" {
    const alloc = std.testing.allocator;
    var toolbar = try Toolbar.init(alloc, &[_][]const u8{"Open"});
    defer toolbar.deinit();

    try toolbar.widget.layout(layout_module.Rect.init(std.math.maxInt(u16), std.math.maxInt(u16), 2, 1));

    var renderer = try render.Renderer.init(alloc, 4, 2);
    defer renderer.deinit();

    try toolbar.widget.draw(&renderer);
}

test "toolbar clamps far-edge mouse hit coordinates" {
    const alloc = std.testing.allocator;
    var toolbar = try Toolbar.init(alloc, &[_][]const u8{"Open"});
    defer toolbar.deinit();

    toolbar.widget.rect = layout_module.Rect.init(std.math.maxInt(u16), 0, 1, 1);

    try std.testing.expect(!try toolbar.widget.handleEvent(.{
        .mouse = input.MouseEvent.init(.press, std.math.maxInt(u16), 0, 1, 0),
    }));
}

var test_breadcrumb_click_index: ?usize = null;

test "breadcrumbs mouse clicks rendered segment only" {
    const alloc = std.testing.allocator;
    var crumbs = try Breadcrumbs.init(alloc, &[_][]const u8{ "home", "repo" });
    defer crumbs.deinit();

    test_breadcrumb_click_index = null;
    crumbs.setOnClick(struct {
        fn call(idx: usize) void {
            test_breadcrumb_click_index = idx;
        }
    }.call);
    crumbs.widget.rect = layout_module.Rect.init(5, 5, 20, 1);

    try std.testing.expect(!try crumbs.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 12, 4, 1, 0) }));
    try std.testing.expectEqual(@as(?usize, null), test_breadcrumb_click_index);

    try std.testing.expect(!try crumbs.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 10, 5, 1, 0) }));
    try std.testing.expectEqual(@as(?usize, null), test_breadcrumb_click_index);

    try std.testing.expect(try crumbs.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 13, 5, 1, 0) }));
    try std.testing.expectEqual(@as(?usize, 1), test_breadcrumb_click_index);
}

test "breadcrumbs marks dirty when parts change" {
    const alloc = std.testing.allocator;
    var crumbs = try Breadcrumbs.init(alloc, &[_][]const u8{ "home", "repo" });
    defer crumbs.deinit();

    try crumbs.widget.layout(layout_module.Rect.init(0, 0, 24, 1));
    var renderer = try render.Renderer.init(alloc, 24, 1);
    defer renderer.deinit();

    try crumbs.widget.draw(&renderer);
    try std.testing.expect(!crumbs.widget.dirty);

    try crumbs.setParts(&[_]Breadcrumbs.Part{ .{ .label = "home" }, .{ .label = "repo" } });
    try std.testing.expect(!crumbs.widget.dirty);

    try crumbs.setParts(&[_]Breadcrumbs.Part{ .{ .label = "home" }, .{ .label = "docs", .icon = "*" } });
    try std.testing.expect(crumbs.widget.dirty);
}

test "breadcrumbs clamp far-edge render coordinates" {
    const alloc = std.testing.allocator;
    var crumbs = try Breadcrumbs.init(alloc, &[_][]const u8{ "home", "repo" });
    defer crumbs.deinit();

    try crumbs.widget.layout(layout_module.Rect.init(std.math.maxInt(u16), std.math.maxInt(u16), 2, 1));

    var renderer = try render.Renderer.init(alloc, 4, 2);
    defer renderer.deinit();

    try crumbs.widget.draw(&renderer);
}

test "breadcrumbs clamp far-edge mouse hit coordinates" {
    const alloc = std.testing.allocator;
    var crumbs = try Breadcrumbs.init(alloc, &[_][]const u8{"home"});
    defer crumbs.deinit();

    test_breadcrumb_click_index = null;
    crumbs.setOnClick(struct {
        fn call(idx: usize) void {
            test_breadcrumb_click_index = idx;
        }
    }.call);
    crumbs.widget.rect = layout_module.Rect.init(std.math.maxInt(u16), 0, 1, 1);

    try std.testing.expect(!try crumbs.widget.handleEvent(.{
        .mouse = input.MouseEvent.init(.press, std.math.maxInt(u16), 0, 1, 0),
    }));
    try std.testing.expectEqual(@as(?usize, null), test_breadcrumb_click_index);
}

test "breadcrumbs preferred size saturates long labels" {
    const alloc = std.testing.allocator;
    const long_label = try alloc.alloc(u8, @as(usize, std.math.maxInt(u16)) + 128);
    defer alloc.free(long_label);
    @memset(long_label, 'x');

    var crumbs = try Breadcrumbs.init(alloc, &[_][]const u8{long_label});
    defer crumbs.deinit();

    const size = try crumbs.widget.getPreferredSize();
    try std.testing.expectEqual(@as(u16, 200), size.width);
    try std.testing.expectEqual(@as(u16, 1), size.height);
}

test "pagination mouse activates rendered arrows" {
    const alloc = std.testing.allocator;
    var pager = try Pagination.init(alloc, 5);
    defer pager.deinit();

    pager.setPage(2);
    pager.widget.rect = layout_module.Rect.init(4, 6, 20, 1);

    try std.testing.expect(!try pager.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 4, 5, 1, 0) }));
    try std.testing.expectEqual(@as(usize, 2), pager.current);

    try std.testing.expect(try pager.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 4, 6, 1, 0) }));
    try std.testing.expectEqual(@as(usize, 1), pager.current);

    try std.testing.expect(try pager.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 22, 6, 1, 0) }));
    try std.testing.expectEqual(@as(usize, 2), pager.current);
}

test "pagination marks dirty when page changes" {
    const alloc = std.testing.allocator;
    var pager = try Pagination.init(alloc, 5);
    defer pager.deinit();

    try pager.widget.layout(layout_module.Rect.init(0, 0, 20, 1));
    var renderer = try render.Renderer.init(alloc, 20, 1);
    defer renderer.deinit();

    try pager.widget.draw(&renderer);
    try std.testing.expect(!pager.widget.dirty);

    pager.setPage(1);
    try std.testing.expect(!pager.widget.dirty);

    pager.setPage(3);
    try std.testing.expect(pager.widget.dirty);
    try pager.widget.draw(&renderer);
    try std.testing.expect(!pager.widget.dirty);

    pager.setPage(99);
    try std.testing.expect(pager.widget.dirty);
    try pager.widget.draw(&renderer);
    try std.testing.expect(!pager.widget.dirty);

    pager.setPage(99);
    try std.testing.expect(!pager.widget.dirty);
}

test "pagination navigation saturates stale current state" {
    const alloc = std.testing.allocator;
    var pager = try Pagination.init(alloc, 5);
    defer pager.deinit();

    pager.widget.focused = true;
    pager.current = 0;
    try std.testing.expect(try pager.widget.handleEvent(.{ .key = input.KeyEvent.init(input.KeyCode.LEFT, .{}) }));
    try std.testing.expectEqual(@as(usize, 1), pager.current);

    pager.current = std.math.maxInt(usize);
    try std.testing.expect(try pager.widget.handleEvent(.{ .key = input.KeyEvent.init(input.KeyCode.RIGHT, .{}) }));
    try std.testing.expectEqual(@as(usize, 5), pager.current);

    pager.widget.rect = layout_module.Rect.init(4, 6, 20, 1);
    pager.current = 0;
    try std.testing.expect(try pager.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 4, 6, 1, 0) }));
    try std.testing.expectEqual(@as(usize, 1), pager.current);

    pager.current = std.math.maxInt(usize);
    try std.testing.expect(try pager.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 22, 6, 1, 0) }));
    try std.testing.expectEqual(@as(usize, 5), pager.current);
}

test "accordion mouse toggles rendered section rows" {
    const alloc = std.testing.allocator;
    var accordion = try Accordion.init(alloc, &[_]Accordion.Section{
        .{ .title = "Build", .body = "Run tests" },
        .{ .title = "Ship", .body = "Push main" },
    });
    defer accordion.deinit();

    accordion.widget.rect = layout_module.Rect.init(2, 7, 30, 5);

    try std.testing.expect(!try accordion.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 4, 6, 1, 0) }));
    try std.testing.expect(!accordion.sections.items[0].expanded);

    try std.testing.expect(try accordion.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 4, 7, 1, 0) }));
    try std.testing.expect(accordion.sections.items[0].expanded);

    try std.testing.expect(!try accordion.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 4, 8, 1, 0) }));
    try std.testing.expect(accordion.sections.items[0].expanded);
}

test "accordion mouse walk does not wrap large expanded section counts" {
    const alloc = std.testing.allocator;
    var accordion = try Accordion.init(alloc, &[_]Accordion.Section{});
    defer accordion.deinit();

    const fake_sections = try alloc.alloc(Accordion.Section, @as(usize, std.math.maxInt(u16)) / 2 + 4);
    defer alloc.free(fake_sections);
    for (fake_sections) |*section| {
        section.* = .{ .title = "", .body = "", .expanded = true };
    }

    const original_sections = accordion.sections.items;
    accordion.sections.items = fake_sections;
    defer accordion.sections.items = original_sections;

    accordion.widget.rect = layout_module.Rect.init(0, 0, 1, std.math.maxInt(u16));

    const skipped_body_row = input.MouseEvent.init(.press, 0, std.math.maxInt(u16) - 2, 1, 0);
    try std.testing.expect(!try accordion.widget.handleEvent(.{ .mouse = skipped_body_row }));
}

test "accordion draws narrow edge rectangles" {
    const alloc = std.testing.allocator;
    var accordion = try Accordion.init(alloc, &[_]Accordion.Section{
        .{ .title = "Build", .body = "Run tests", .expanded = true },
        .{ .title = "Ship", .body = "Push main" },
    });
    defer accordion.deinit();

    {
        var snap = try testing.renderWidget(alloc, &accordion.widget, layout_module.Size.init(1, 2));
        defer snap.deinit(alloc);
        try snap.expectWellFormed();
    }

    var renderer = try render.Renderer.init(alloc, 4, 2);
    defer renderer.deinit();

    try accordion.widget.layout(layout_module.Rect.init(std.math.maxInt(u16) - 1, std.math.maxInt(u16) - 1, 1, 2));
    try accordion.widget.draw(&renderer);
}

fn radioGroupInitAllocationFailureHarness(allocator: std.mem.Allocator) !void {
    var radio = try RadioGroup.init(allocator, &[_][]const u8{ "One", "Two", "Three" });
    defer radio.deinit();
}

fn toolbarInitAllocationFailureHarness(allocator: std.mem.Allocator) !void {
    var toolbar = try Toolbar.init(allocator, &[_][]const u8{ "Open", "Save", "Close" });
    defer toolbar.deinit();
}

fn breadcrumbsInitAllocationFailureHarness(allocator: std.mem.Allocator) !void {
    var crumbs = try Breadcrumbs.init(allocator, &[_][]const u8{ "home", "repo", "src" });
    defer crumbs.deinit();
}

fn commandPaletteInitAllocationFailureHarness(allocator: std.mem.Allocator) !void {
    var palette = try CommandPalette.init(allocator, &[_][]const u8{ "Open file", "Run tests", "Toggle terminal" });
    defer palette.deinit();
}

fn wizardStepperInitAllocationFailureHarness(allocator: std.mem.Allocator) !void {
    var wizard = try WizardStepper.init(allocator, &[_][]const u8{ "Account", "Billing", "Confirm" });
    defer wizard.deinit();
}

fn notificationPushAllocationFailureHarness(allocator: std.mem.Allocator) !void {
    var center = try NotificationCenter.init(allocator);
    defer center.deinit();

    try center.push("Build", "Started", .info);
    try center.push("Build", "Finished", .success);
}

fn toggleSwitchInitAllocationFailureHarness(allocator: std.mem.Allocator) !void {
    var toggle = try ToggleSwitch.init(allocator, "Turbo");
    defer toggle.deinit();
}

fn accordionInitAllocationFailureHarness(allocator: std.mem.Allocator) !void {
    var accordion = try Accordion.init(allocator, &[_]Accordion.Section{
        .{ .title = "Build", .body = "Run tests" },
        .{ .title = "Ship", .body = "Push main", .expanded = true },
    });
    defer accordion.deinit();
}

test "advanced controls clean up every allocation failure path" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, toggleSwitchInitAllocationFailureHarness, .{});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, radioGroupInitAllocationFailureHarness, .{});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, toolbarInitAllocationFailureHarness, .{});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, breadcrumbsInitAllocationFailureHarness, .{});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, commandPaletteInitAllocationFailureHarness, .{});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, wizardStepperInitAllocationFailureHarness, .{});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, notificationPushAllocationFailureHarness, .{});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, accordionInitAllocationFailureHarness, .{});
}

test "breadcrumbs setParts preserves parts on allocation failure" {
    const alloc = std.testing.allocator;
    var crumbs = try Breadcrumbs.init(alloc, &[_][]const u8{ "home", "repo" });
    defer crumbs.deinit();

    const next_parts = [_]Breadcrumbs.Part{
        .{ .label = "home", .icon = "H" },
        .{ .label = "repo", .icon = "R" },
        .{ .label = "src", .icon = "S" },
    };

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = crumbs.allocator;
    crumbs.allocator = failing.allocator();
    defer crumbs.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, crumbs.setParts(&next_parts));
    try std.testing.expectEqual(@as(usize, 2), crumbs.parts.items.len);
    try std.testing.expectEqualStrings("home", crumbs.parts.items[0].label);
    try std.testing.expectEqualStrings("repo", crumbs.parts.items[1].label);
    try std.testing.expectEqual(@as(?[]const u8, null), crumbs.parts.items[0].icon);
}

test "notification center push preserves notifications on allocation failure" {
    const alloc = std.testing.allocator;
    var center = try NotificationCenter.init(alloc);
    defer center.deinit();

    try center.push("Stable", "Body", .info);

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = center.allocator;
    center.allocator = failing.allocator();
    defer center.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, center.push("Replacement", "Body", .success));
    try std.testing.expectEqual(@as(usize, 1), center.notifications.items.len);
    try std.testing.expectEqualStrings("Stable", center.notifications.items[0].title);
    try std.testing.expectEqualStrings("Body", center.notifications.items[0].body);
}
