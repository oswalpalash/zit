const std = @import("std");
const render = @import("render/render.zig");

/// Locale metadata used for string bundles and defaults.
pub const Locale = struct {
    language: []const u8,
    region: ?[]const u8 = null,
    direction: render.TextDirection = .auto,
};

/// Simple string catalog for externalized messages.
pub const MessageCatalog = struct {
    allocator: std.mem.Allocator,
    strings: std.StringHashMapUnmanaged([]const u8) = .{},
    locale: Locale,

    pub fn init(allocator: std.mem.Allocator, locale: Locale) MessageCatalog {
        return MessageCatalog{ .allocator = allocator, .locale = locale };
    }

    pub fn deinit(self: *MessageCatalog) void {
        var it = self.strings.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.strings.deinit(self.allocator);
    }

    /// Insert or replace a localized string (copied into catalog memory).
    pub fn set(self: *MessageCatalog, key: []const u8, value: []const u8) !void {
        const duped = try self.allocator.dupe(u8, value);
        if (self.strings.fetchRemove(key)) |removed| {
            self.allocator.free(removed.value);
        }
        try self.strings.put(self.allocator, key, duped);
    }

    /// Resolve a string from the catalog with a fallback.
    pub fn translate(self: *const MessageCatalog, key: []const u8, fallback: []const u8) []const u8 {
        if (self.strings.get(key)) |value| return value;
        return fallback;
    }
};

pub const PluralForms = struct {
    zero: ?[]const u8 = null,
    one: ?[]const u8 = null,
    two: ?[]const u8 = null,
    few: ?[]const u8 = null,
    many: ?[]const u8 = null,
    other: []const u8,
};

/// English-friendly plural selector with optional extra categories.
pub fn selectPlural(count: isize, forms: PluralForms) []const u8 {
    const abs = if (count < 0) -count else count;
    if (abs == 0) {
        if (forms.zero) |v| return v;
    }
    if (abs == 1) {
        if (forms.one) |v| return v;
    }
    if (abs == 2) {
        if (forms.two) |v| return v;
    }
    if (abs >= 3 and abs <= 10) {
        if (forms.few) |v| return v;
    }
    if (abs > 10) {
        if (forms.many) |v| return v;
    }
    return forms.other;
}

pub const NumberFormatOptions = struct {
    grouping: bool = true,
    group_separator: u8 = ',',
    decimal_point: u8 = '.',
    precision: ?u8 = null,
};

/// Locale-aware-ish number formatter that keeps allocations explicit.
pub fn formatNumber(allocator: std.mem.Allocator, value: anytype, opts: NumberFormatOptions) ![]u8 {
    const T = @TypeOf(value);
    const info = @typeInfo(T);
    var raw: []u8 = undefined;
    switch (info) {
        .float, .comptime_float => {
            const precision = opts.precision orelse 2;
            raw = try std.fmt.allocPrint(allocator, "{.{}}", .{ precision, value });
        },
        else => {
            raw = try std.fmt.allocPrint(allocator, "{}", .{value});
        },
    }
    errdefer allocator.free(raw);

    const dot = std.mem.indexOfScalar(u8, raw, '.');
    const int_part = if (dot) |idx| raw[0..idx] else raw;
    const frac_part = if (dot) |idx| raw[idx + 1 ..] else raw[0..0];

    var out = std.ArrayListUnmanaged(u8){};
    errdefer out.deinit(allocator);

    const negative = int_part.len > 0 and int_part[0] == '-';
    const digits = if (negative) int_part[1..] else int_part;

    if (!opts.grouping or digits.len <= 3) {
        if (negative) try out.append(allocator, '-');
        try out.appendSlice(allocator, digits);
    } else {
        if (negative) try out.append(allocator, '-');
        var idx: isize = @intCast(digits.len);
        var group_count: u8 = 0;
        while (idx > 0) {
            idx -= 1;
            try out.append(allocator, digits[@intCast(idx)]);
            group_count += 1;
            if (group_count == 3 and idx > 0) {
                try out.append(allocator, opts.group_separator);
                group_count = 0;
            }
        }
        const start: usize = if (negative) 1 else 0;
        std.mem.reverse(u8, out.items[start..]);
    }

    if (frac_part.len > 0) {
        try out.append(allocator, opts.decimal_point);
        try out.appendSlice(allocator, frac_part);
    }

    allocator.free(raw);
    return out.toOwnedSlice(allocator);
}

pub const DateFormatOptions = struct {
    timezone_offset_s: i64 = 0,
    date_separator: u8 = '-',
    time_separator: u8 = ':',
    include_time: bool = true,
};

/// Minimal ISO-like date/time formatter using UTC math by default.
pub fn formatDateTime(allocator: std.mem.Allocator, epoch_seconds: i64, opts: DateFormatOptions) ![]u8 {
    const adjusted = epoch_seconds + opts.timezone_offset_s;
    if (adjusted < 0) return error.InvalidTimestamp;
    const epoch = std.time.epoch.EpochSeconds{ .secs = @as(u64, @intCast(adjusted)) };
    const year_day = epoch.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch.getDaySeconds();

    if (!opts.include_time) {
        return std.fmt.allocPrint(allocator, "{d:0>4}{c}{d:0>2}{c}{d:0>2}", .{
            year_day.year,
            opts.date_separator,
            month_day.month.numeric(),
            opts.date_separator,
            month_day.day_index + 1,
        });
    }

    return std.fmt.allocPrint(allocator, "{d:0>4}{c}{d:0>2}{c}{d:0>2} {d:0>2}{c}{d:0>2}{c}{d:0>2}", .{
        year_day.year,
        opts.date_separator,
        month_day.month.numeric(),
        opts.date_separator,
        month_day.day_index + 1,
        day_seconds.getHoursIntoDay(),
        opts.time_separator,
        day_seconds.getMinutesIntoHour(),
        opts.time_separator,
        day_seconds.getSecondsIntoMinute(),
    });
}

test "message catalog resolves keys" {
    var catalog = MessageCatalog.init(std.testing.allocator, .{ .language = "en" });
    defer catalog.deinit();

    try catalog.set("hello", "Hello");
    try std.testing.expectEqualStrings("Hello", catalog.translate("hello", "fallback"));
    try std.testing.expectEqualStrings("fallback", catalog.translate("missing", "fallback"));
}

test "plural selection covers common forms" {
    const forms = PluralForms{ .one = "one", .zero = "zero", .other = "other" };
    try std.testing.expectEqualStrings("zero", selectPlural(0, forms));
    try std.testing.expectEqualStrings("one", selectPlural(1, forms));
    try std.testing.expectEqualStrings("other", selectPlural(5, forms));
}

test "number formatting groups digits" {
    const formatted = try formatNumber(std.testing.allocator, 12345, .{});
    defer std.testing.allocator.free(formatted);
    try std.testing.expectEqualStrings("12,345", formatted);
}

test "formatDateTime renders epoch" {
    const formatted = try formatDateTime(std.testing.allocator, 0, .{});
    defer std.testing.allocator.free(formatted);
    try std.testing.expectEqualStrings("1970-01-01 00:00:00", formatted);
}
