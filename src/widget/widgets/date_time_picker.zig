const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");

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
        return self;
    }

    pub fn deinit(self: *DateTimePicker) void {
        self.allocator.destroy(self);
    }

    pub fn setColors(self: *DateTimePicker, fg: render.Color, bg: render.Color, accent_fg: render.Color, accent_bg: render.Color) void {
        self.fg = fg;
        self.bg = bg;
        self.accent_fg = accent_fg;
        self.accent_bg = accent_bg;
    }

    pub fn setBorder(self: *DateTimePicker, border: render.BorderStyle) void {
        self.border = border;
    }

    pub fn setDateTime(self: *DateTimePicker, value: DateTime) void {
        self.value = value;
        self.value.day = clampDay(self.value.year, self.value.month, self.value.day);
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
        return if (day > max_day) max_day else day;
    }

    fn moveField(self: *DateTimePicker, forward: bool) void {
        self.selected_field = switch (self.selected_field) {
            .year => if (forward) .month else .minute,
            .month => if (forward) .day else .year,
            .day => if (forward) .hour else .month,
            .hour => if (forward) .minute else .day,
            .minute => if (forward) .year else .hour,
        };
    }

    fn adjust(self: *DateTimePicker, delta: i32) void {
        switch (self.selected_field) {
            .year => self.adjustYear(delta),
            .month => self.adjustMonth(delta),
            .day => self.adjustDay(delta),
            .hour => self.adjustHour(delta),
            .minute => self.adjustMinute(delta),
        }
        self.notifyChange();
    }

    fn adjustYear(self: *DateTimePicker, delta: i32) void {
        var year: i32 = self.value.year;
        year = @max(1, year + delta);
        self.value.year = @intCast(year);
        self.value.day = clampDay(self.value.year, self.value.month, self.value.day);
    }

    fn adjustMonth(self: *DateTimePicker, delta: i32) void {
        var total: i32 = @as(i32, self.value.month) - 1 + delta;
        while (total < 0) : (total += 12) {
            self.adjustYear(-1);
        }
        while (total >= 12) : (total -= 12) {
            self.adjustYear(1);
        }
        self.value.month = @intCast(total + 1);
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
                        month = 1;
                        year = @max(1, year + 1);
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
                        month = 12;
                        year = @max(1, year - 1);
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
            self.adjustDay(-1);
        }
        while (total >= 24) : (total -= 24) {
            self.adjustDay(1);
        }
        self.value.hour = @intCast(total);
    }

    fn adjustMinute(self: *DateTimePicker, delta: i32) void {
        var total: i32 = @as(i32, self.value.minute) + delta;
        while (total < 0) : (total += 60) {
            self.adjustHour(-1);
        }
        while (total >= 60) : (total -= 60) {
            self.adjustHour(1);
        }
        self.value.minute = @intCast(total);
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*DateTimePicker, @ptrCast(@alignCast(widget_ptr)));
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

        const start_x = rect.x + inset + 1;
        const start_y = rect.y + inset + (rect.height - inset * 2) / 2;
        const max_width = rect.width - inset * 2 - 1;

        var utf8_it = std.unicode.Utf8Iterator{
            .bytes = text,
            .i = 0,
        };

        var i: usize = 0;
        while (utf8_it.nextCodepoint()) |codepoint| {
            if (i >= max_width) break;
            const pos_x = start_x + @as(u16, @intCast(i));
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
        const self = @as(*DateTimePicker, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible or !self.widget.enabled) return false;

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
        const self = @as(*DateTimePicker, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(_: *anyopaque) anyerror!layout_module.Size {
        return layout_module.Size.init(22, 3);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*DateTimePicker, @ptrCast(@alignCast(widget_ptr)));
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
    _ = try picker.handleEvent(.{ .key = .{ .key = input.KeyCode.UP, .modifiers = .{} } });
    try std.testing.expectEqual(@as(u8, 59), picker.value.minute);
    _ = try picker.handleEvent(.{ .key = .{ .key = input.KeyCode.UP, .modifiers = .{} } });
    try std.testing.expectEqual(@as(u8, 0), picker.value.minute);
    try std.testing.expectEqual(@as(u8, 0), picker.value.hour);
    try std.testing.expectEqual(@as(u8, 1), picker.value.day);
    try std.testing.expectEqual(@as(u8, 1), picker.value.month);
    try std.testing.expectEqual(@as(u16, 2025), picker.value.year);
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
