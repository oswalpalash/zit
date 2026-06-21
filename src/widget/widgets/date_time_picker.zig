const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const accessibility = @import("../accessibility.zig");

/// Interactive date/time picker with keyboard navigation.
pub const DateTimePicker = struct {
    widget: base.Widget,
    allocator: std.mem.Allocator,
    value: DateTime = .{},
    selected_field: Field = .month,
    border: render.BorderStyle = .rounded,
    fg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    bg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    accent_fg: render.Color = render.Color{ .named_color = render.NamedColor.black },
    accent_bg: render.Color = render.Color{ .named_color = render.NamedColor.cyan },
    on_change: ?*const fn (DateTime) void = null,

    pub const DateTime = struct {
        year: u16 = 2024,
        month: u8 = 1,
        day: u8 = 1,
        hour: u8 = 0,
        minute: u8 = 0,
    };

    pub const Field = enum { year, month, day, hour, minute };
    const min_year: u16 = 1;
    const max_year: u16 = std.math.maxInt(u16);

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator) !*DateTimePicker {
        const self = try allocator.create(DateTimePicker);
        self.* = DateTimePicker{
            .widget = base.Widget.init(&vtable),
            .allocator = allocator,
        };
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.input), "Date time picker", "");
        return self;
    }

    pub fn deinit(self: *DateTimePicker) void {
        self.allocator.destroy(self);
    }

    pub fn setColors(self: *DateTimePicker, fg: render.Color, bg: render.Color, accent_fg: render.Color, accent_bg: render.Color) void {
        if (std.meta.eql(self.fg, fg) and
            std.meta.eql(self.bg, bg) and
            std.meta.eql(self.accent_fg, accent_fg) and
            std.meta.eql(self.accent_bg, accent_bg))
        {
            return;
        }

        self.fg = fg;
        self.bg = bg;
        self.accent_fg = accent_fg;
        self.accent_bg = accent_bg;
        self.widget.markDirty();
    }

    pub fn setBorder(self: *DateTimePicker, border: render.BorderStyle) void {
        if (self.border == border) return;
        self.border = border;
        self.widget.markDirty();
    }

    pub fn setDateTime(self: *DateTimePicker, value: DateTime) void {
        const previous = self.value;
        self.value = value;
        self.normalizeValue();
        if (!std.meta.eql(previous, self.value)) {
            self.widget.markDirty();
        }
        self.notifyChange();
    }

    pub fn setOnChange(self: *DateTimePicker, callback: *const fn (DateTime) void) void {
        self.on_change = callback;
    }

    fn notifyChange(self: *DateTimePicker) void {
        if (self.on_change) |cb| {
            cb(self.value);
        }
    }

    fn daysInMonth(year: u16, month: u8) u8 {
        return switch (month) {
            1, 3, 5, 7, 8, 10, 12 => 31,
            4, 6, 9, 11 => 30,
            2 => if (isLeapYear(year)) 29 else 28,
            else => 30,
        };
    }

    fn isLeapYear(year: u16) bool {
        return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);
    }

    fn clampDay(year: u16, month: u8, day: u8) u8 {
        const max_day = daysInMonth(year, month);
        return std.math.clamp(day, 1, max_day);
    }

    fn normalizeValue(self: *DateTimePicker) void {
        if (self.value.year < min_year) {
            self.value.year = min_year;
        }
        self.value.month = std.math.clamp(self.value.month, 1, 12);
        self.value.day = clampDay(self.value.year, self.value.month, self.value.day);
        self.value.hour = @min(self.value.hour, 23);
        self.value.minute = @min(self.value.minute, 59);
    }

    fn moveField(self: *DateTimePicker, forward: bool) void {
        const previous = self.selected_field;
        self.selected_field = switch (self.selected_field) {
            .year => if (forward) .month else .minute,
            .month => if (forward) .day else .year,
            .day => if (forward) .hour else .month,
            .hour => if (forward) .minute else .day,
            .minute => if (forward) .year else .hour,
        };
        if (previous != self.selected_field) {
            self.widget.markDirty();
        }
    }

    fn adjust(self: *DateTimePicker, delta: i32) void {
        self.normalizeValue();
        const previous = self.value;
        switch (self.selected_field) {
            .year => self.adjustYear(delta),
            .month => self.adjustMonth(delta),
            .day => self.adjustDay(delta),
            .hour => self.adjustHour(delta),
            .minute => self.adjustMinute(delta),
        }
        self.normalizeValue();
        if (!std.meta.eql(previous, self.value)) {
            self.widget.markDirty();
        }
        self.notifyChange();
    }

    fn adjustYear(self: *DateTimePicker, delta: i32) void {
        const year = std.math.clamp(
            @as(i64, self.value.year) + @as(i64, delta),
            @as(i64, min_year),
            @as(i64, max_year),
        );
        self.value.year = @intCast(year);
        self.value.day = clampDay(self.value.year, self.value.month, self.value.day);
    }

    fn adjustMonth(self: *DateTimePicker, delta: i32) void {
        const month_index = (@as(i64, self.value.year) - 1) * 12 + (@as(i64, self.value.month) - 1);
        const max_index = (@as(i64, max_year) - 1) * 12 + 11;
        const next_index = std.math.clamp(month_index + @as(i64, delta), 0, max_index);
        self.value.year = @intCast(@divTrunc(next_index, 12) + 1);
        self.value.month = @intCast(@mod(next_index, 12) + 1);
        self.value.day = clampDay(self.value.year, self.value.month, self.value.day);
    }

    fn adjustDay(self: *DateTimePicker, delta: i32) void {
        var day: i32 = self.value.day;
        var month: i32 = self.value.month;
        var year: i32 = self.value.year;

        var remaining = delta;
        while (remaining != 0) {
            if (remaining > 0) {
                const max_day: i32 = daysInMonth(@intCast(year), @intCast(month));
                if (day + remaining <= max_day) {
                    day += remaining;
                    remaining = 0;
                } else {
                    remaining -= (max_day - day + 1);
                    day = 1;
                    month += 1;
                    if (month > 12) {
                        if (year >= max_year) {
                            month = 12;
                            day = 31;
                            remaining = 0;
                            break;
                        }
                        month = 1;
                        year += 1;
                    }
                }
            } else {
                if (day + remaining >= 1) {
                    day += remaining;
                    remaining = 0;
                } else {
                    remaining += day;
                    month -= 1;
                    if (month < 1) {
                        if (year <= min_year) {
                            month = 1;
                            day = 1;
                            remaining = 0;
                            break;
                        }
                        month = 12;
                        year -= 1;
                    }
                    day = daysInMonth(@intCast(year), @intCast(month));
                }
            }
        }

        self.value.year = @intCast(year);
        self.value.month = @intCast(month);
        self.value.day = @intCast(day);
    }

    fn adjustHour(self: *DateTimePicker, delta: i32) void {
        var total: i32 = @as(i32, self.value.hour) + delta;
        while (total < 0) : (total += 24) {
            if (self.isAtMinDate()) {
                total = 0;
                break;
            }
            self.adjustDay(-1);
        }
        while (total >= 24) : (total -= 24) {
            if (self.isAtMaxDate()) {
                total = 23;
                break;
            }
            self.adjustDay(1);
        }
        self.value.hour = @intCast(total);
    }

    fn adjustMinute(self: *DateTimePicker, delta: i32) void {
        var total: i32 = @as(i32, self.value.minute) + delta;
        while (total < 0) : (total += 60) {
            if (self.isAtMinDate() and self.value.hour == 0) {
                total = 0;
                break;
            }
            self.adjustHour(-1);
        }
        while (total >= 60) : (total -= 60) {
            if (self.isAtMaxDate() and self.value.hour == 23) {
                total = 59;
                break;
            }
            self.adjustHour(1);
        }
        self.value.minute = @intCast(total);
    }

    fn isAtMinDate(self: *const DateTimePicker) bool {
        return self.value.year == min_year and self.value.month == 1 and self.value.day == 1;
    }

    fn isAtMaxDate(self: *const DateTimePicker) bool {
        return self.value.year == max_year and self.value.month == 12 and self.value.day == 31;
    }

    fn addOffsetClamped(origin: u16, offset: u16) u16 {
        const value = @as(u32, origin) + @as(u32, offset);
        return @intCast(@min(value, @as(u32, std.math.maxInt(u16))));
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *DateTimePicker = @fieldParentPtr("widget", widget_ref);
        self.normalizeValue();
        if (!self.widget.visible) return;

        const rect = self.widget.rect;
        if (rect.width == 0 or rect.height == 0) return;

        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', self.fg, self.bg, render.Style{});

        const has_border = self.border != .none and rect.width >= 2 and rect.height >= 2;
        const inset: u16 = if (has_border) 1 else 0;
        if (has_border) {
            renderer.drawBox(rect.x, rect.y, rect.width, rect.height, self.border, self.fg, self.bg, render.Style{});
        }

        if (rect.width <= inset * 2 + 1 or rect.height <= inset) return;

        var buf: [32]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}", .{
            self.value.year,
            self.value.month,
            self.value.day,
            self.value.hour,
            self.value.minute,
        }) catch return;

        const start_x = addOffsetClamped(rect.x, inset + 1);
        const start_y = addOffsetClamped(rect.y, inset + (rect.height - inset * 2) / 2);
        const max_width = rect.width - inset * 2 - 1;

        var utf8_it = std.unicode.Utf8Iterator{
            .bytes = text,
            .i = 0,
        };

        var i: usize = 0;
        while (utf8_it.nextCodepoint()) |codepoint| {
            if (i >= max_width) break;
            const pos_x = addOffsetClamped(start_x, @intCast(i));
            const highlight = self.isHighlighted(i);
            const fg = if (highlight) self.accent_fg else self.fg;
            const bg = if (highlight) self.accent_bg else self.bg;
            const style = if (highlight) render.Style{ .bold = true } else render.Style{};
            renderer.drawChar(pos_x, start_y, codepoint, fg, bg, style);
            i += 1;
        }
    }

    fn isHighlighted(self: *DateTimePicker, index: usize) bool {
        return switch (self.selected_field) {
            .year => index < 4,
            .month => index >= 5 and index < 7,
            .day => index >= 8 and index < 10,
            .hour => index >= 11 and index < 13,
            .minute => index >= 14 and index < 16,
        };
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *DateTimePicker = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible or !self.widget.enabled) return false;
        self.normalizeValue();

        switch (event) {
            .key => |key_event| {
                if (!self.widget.focused) return false;
                const key = key_event.key;

                if (key == input.KeyCode.LEFT) {
                    self.moveField(false);
                    return true;
                } else if (key == input.KeyCode.RIGHT) {
                    self.moveField(true);
                    return true;
                } else if (key == input.KeyCode.UP or key == '+') {
                    self.adjust(1);
                    return true;
                } else if (key == input.KeyCode.DOWN or key == '-') {
                    self.adjust(-1);
                    return true;
                } else if (key == input.KeyCode.PAGE_UP) {
                    self.adjust(5);
                    return true;
                } else if (key == input.KeyCode.PAGE_DOWN) {
                    self.adjust(-5);
                    return true;
                }
            },
            else => {},
        }

        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *DateTimePicker = @fieldParentPtr("widget", widget_ref);
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(_: *anyopaque) anyerror!layout_module.Size {
        return layout_module.Size.init(22, 3);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *DateTimePicker = @fieldParentPtr("widget", widget_ref);
        return self.widget.enabled and self.widget.visible;
    }
};

test "date time picker rolls over time correctly" {
    const alloc = std.testing.allocator;
    var picker = try DateTimePicker.init(alloc);
    defer picker.deinit();

    picker.setDateTime(.{ .year = 2024, .month = 12, .day = 31, .hour = 23, .minute = 58 });
    picker.widget.focused = true;
    try picker.widget.layout(layout_module.Rect.init(0, 0, 30, 4));

    picker.selected_field = .minute;
    _ = try picker.widget.handleEvent(.{ .key = .{ .key = input.KeyCode.UP, .modifiers = .{} } });
    try std.testing.expectEqual(@as(u8, 59), picker.value.minute);
    _ = try picker.widget.handleEvent(.{ .key = .{ .key = input.KeyCode.UP, .modifiers = .{} } });
    try std.testing.expectEqual(@as(u8, 0), picker.value.minute);
    try std.testing.expectEqual(@as(u8, 0), picker.value.hour);
    try std.testing.expectEqual(@as(u8, 1), picker.value.day);
    try std.testing.expectEqual(@as(u8, 1), picker.value.month);
    try std.testing.expectEqual(@as(u16, 2025), picker.value.year);
}

test "date time picker normalizes invalid setDateTime values" {
    const alloc = std.testing.allocator;
    var picker = try DateTimePicker.init(alloc);
    defer picker.deinit();

    picker.setDateTime(.{ .year = 0, .month = 0, .day = 0, .hour = 99, .minute = 99 });
    try std.testing.expectEqual(@as(u16, 1), picker.value.year);
    try std.testing.expectEqual(@as(u8, 1), picker.value.month);
    try std.testing.expectEqual(@as(u8, 1), picker.value.day);
    try std.testing.expectEqual(@as(u8, 23), picker.value.hour);
    try std.testing.expectEqual(@as(u8, 59), picker.value.minute);

    picker.setDateTime(.{ .year = 2024, .month = 2, .day = 31, .hour = 12, .minute = 30 });
    try std.testing.expectEqual(@as(u8, 29), picker.value.day);
}

test "date time picker normalizes stale public value before draw and input" {
    const alloc = std.testing.allocator;
    var picker = try DateTimePicker.init(alloc);
    defer picker.deinit();

    picker.value = .{ .year = 0, .month = 99, .day = 0, .hour = 99, .minute = 99 };
    try picker.widget.layout(layout_module.Rect.init(0, 0, 24, 3));

    var renderer = try render.Renderer.init(alloc, 24, 3);
    defer renderer.deinit();
    try picker.widget.draw(&renderer);

    try std.testing.expectEqual(@as(u16, 1), picker.value.year);
    try std.testing.expectEqual(@as(u8, 12), picker.value.month);
    try std.testing.expectEqual(@as(u8, 1), picker.value.day);
    try std.testing.expectEqual(@as(u8, 23), picker.value.hour);
    try std.testing.expectEqual(@as(u8, 59), picker.value.minute);

    picker.value = .{ .year = 0, .month = 0, .day = 0, .hour = 99, .minute = 99 };
    picker.selected_field = .minute;
    picker.widget.focused = true;
    try std.testing.expect(try picker.widget.handleEvent(.{ .key = .{ .key = input.KeyCode.DOWN, .modifiers = .{} } }));
    try std.testing.expectEqual(@as(u16, 1), picker.value.year);
    try std.testing.expectEqual(@as(u8, 1), picker.value.month);
    try std.testing.expectEqual(@as(u8, 1), picker.value.day);
    try std.testing.expectEqual(@as(u8, 23), picker.value.hour);
    try std.testing.expectEqual(@as(u8, 58), picker.value.minute);
}

test "date time picker saturates upper date time adjustments" {
    const alloc = std.testing.allocator;
    var picker = try DateTimePicker.init(alloc);
    defer picker.deinit();

    const max = std.math.maxInt(u16);
    inline for (.{ DateTimePicker.Field.year, .month, .day, .hour, .minute }) |field| {
        picker.setDateTime(.{ .year = max, .month = 12, .day = 31, .hour = 23, .minute = 59 });
        picker.selected_field = field;
        picker.adjust(1);

        try std.testing.expectEqual(@as(u16, max), picker.value.year);
        try std.testing.expectEqual(@as(u8, 12), picker.value.month);
        try std.testing.expectEqual(@as(u8, 31), picker.value.day);
        try std.testing.expectEqual(@as(u8, 23), picker.value.hour);
        try std.testing.expectEqual(@as(u8, 59), picker.value.minute);
    }
}

test "date time picker saturates lower date time adjustments" {
    const alloc = std.testing.allocator;
    var picker = try DateTimePicker.init(alloc);
    defer picker.deinit();

    inline for (.{ DateTimePicker.Field.year, .month, .day, .hour, .minute }) |field| {
        picker.setDateTime(.{ .year = 1, .month = 1, .day = 1, .hour = 0, .minute = 0 });
        picker.selected_field = field;
        picker.adjust(-1);

        try std.testing.expectEqual(@as(u16, 1), picker.value.year);
        try std.testing.expectEqual(@as(u8, 1), picker.value.month);
        try std.testing.expectEqual(@as(u8, 1), picker.value.day);
        try std.testing.expectEqual(@as(u8, 0), picker.value.hour);
        try std.testing.expectEqual(@as(u8, 0), picker.value.minute);
    }
}

test "date time picker highlights selected field" {
    const alloc = std.testing.allocator;
    var picker = try DateTimePicker.init(alloc);
    defer picker.deinit();

    picker.setDateTime(.{ .year = 2024, .month = 6, .day = 15, .hour = 10, .minute = 30 });
    picker.selected_field = .hour;
    picker.widget.focused = true;
    try picker.widget.layout(layout_module.Rect.init(0, 0, 26, 3));

    var renderer = try render.Renderer.init(alloc, 26, 3);
    defer renderer.deinit();

    try picker.widget.draw(&renderer);

    // Hour field starts at index 11.
    const rect = picker.widget.rect;
    const inset: u16 = if (picker.border != .none and rect.width >= 2 and rect.height >= 2) 1 else 0;
    const x = rect.x + inset + 1 + 11;
    const y = rect.y + inset + (rect.height - inset * 2) / 2;
    const cell = renderer.back.getCell(x, y).*;
    try std.testing.expect(std.meta.eql(cell.bg, picker.accent_bg));
}

test "date time picker clamps edge draw coordinates" {
    const alloc = std.testing.allocator;
    const max = std.math.maxInt(u16);
    var picker = try DateTimePicker.init(alloc);
    defer picker.deinit();

    picker.setDateTime(.{ .year = 2024, .month = 6, .day = 15, .hour = 10, .minute = 30 });
    try picker.widget.layout(layout_module.Rect.init(max - 1, max - 1, 24, 5));

    var renderer = try render.Renderer.init(alloc, 2, 2);
    defer renderer.deinit();
    try picker.widget.draw(&renderer);

    try std.testing.expectEqual(@as(u21, ' '), renderer.back.getCell(0, 0).codepoint());
    try std.testing.expectEqual(@as(u21, ' '), renderer.back.getCell(1, 1).codepoint());
}

test "date time picker marks dirty when visible state changes" {
    const alloc = std.testing.allocator;
    var picker = try DateTimePicker.init(alloc);
    defer picker.deinit();

    try picker.widget.layout(layout_module.Rect.init(0, 0, 26, 3));
    var renderer = try render.Renderer.init(alloc, 26, 3);
    defer renderer.deinit();

    try picker.widget.draw(&renderer);
    try std.testing.expect(!picker.widget.dirty);

    picker.setColors(
        render.Color.named(render.NamedColor.white),
        render.Color.named(render.NamedColor.black),
        render.Color.named(render.NamedColor.yellow),
        render.Color.named(render.NamedColor.blue),
    );
    try std.testing.expect(picker.widget.dirty);
    try picker.widget.draw(&renderer);
    try std.testing.expect(!picker.widget.dirty);
    picker.setColors(
        render.Color.named(render.NamedColor.white),
        render.Color.named(render.NamedColor.black),
        render.Color.named(render.NamedColor.yellow),
        render.Color.named(render.NamedColor.blue),
    );
    try std.testing.expect(!picker.widget.dirty);

    picker.setBorder(.none);
    try std.testing.expect(picker.widget.dirty);
    try picker.widget.draw(&renderer);
    try std.testing.expect(!picker.widget.dirty);
    picker.setBorder(.none);
    try std.testing.expect(!picker.widget.dirty);

    picker.setDateTime(.{ .year = 2024, .month = 6, .day = 15, .hour = 10, .minute = 30 });
    try std.testing.expect(picker.widget.dirty);
    try picker.widget.draw(&renderer);
    try std.testing.expect(!picker.widget.dirty);
    picker.setDateTime(.{ .year = 2024, .month = 6, .day = 15, .hour = 10, .minute = 30 });
    try std.testing.expect(!picker.widget.dirty);

    picker.widget.setFocus(true);
    try picker.widget.draw(&renderer);
    try std.testing.expect(!picker.widget.dirty);
    try std.testing.expect(try picker.widget.handleEvent(.{ .key = .{ .key = input.KeyCode.RIGHT, .modifiers = .{} } }));
    try std.testing.expect(picker.widget.dirty);

    try picker.widget.draw(&renderer);
    try std.testing.expect(!picker.widget.dirty);
    try std.testing.expect(try picker.widget.handleEvent(.{ .key = .{ .key = input.KeyCode.UP, .modifiers = .{} } }));
    try std.testing.expect(picker.widget.dirty);

    picker.setDateTime(.{ .year = 1, .month = 1, .day = 1, .hour = 0, .minute = 0 });
    picker.selected_field = .year;
    try picker.widget.draw(&renderer);
    try std.testing.expect(!picker.widget.dirty);
    picker.adjust(-1);
    try std.testing.expect(!picker.widget.dirty);
}
