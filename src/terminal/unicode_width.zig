const std = @import("std");

/// Metrics describing how a string will occupy terminal cells.
pub const Metrics = struct {
    width: u16,
    has_bidi: bool,
    has_emoji: bool,
    has_ligatures: bool,
};

const Range = struct { start: u21, end: u21 };

fn inRange(cp: u21, ranges: []const Range) bool {
    for (ranges) |r| {
        if (cp >= r.start and cp <= r.end) return true;
    }
    return false;
}

// Combining marks and zero-width modifiers (subset sufficient for terminals).
const combining_ranges = [_]Range{
    .{ .start = 0x0300, .end = 0x036F },
    .{ .start = 0x0483, .end = 0x0489 },
    .{ .start = 0x0591, .end = 0x05BD },
    .{ .start = 0x05BF, .end = 0x05BF },
    .{ .start = 0x05C1, .end = 0x05C2 },
    .{ .start = 0x05C4, .end = 0x05C5 },
    .{ .start = 0x05C7, .end = 0x05C7 },
    .{ .start = 0x0610, .end = 0x061A },
    .{ .start = 0x064B, .end = 0x065F },
    .{ .start = 0x0670, .end = 0x0670 },
    .{ .start = 0x06D6, .end = 0x06DD },
    .{ .start = 0x06DF, .end = 0x06E4 },
    .{ .start = 0x06E7, .end = 0x06E8 },
    .{ .start = 0x06EA, .end = 0x06ED },
    .{ .start = 0x0711, .end = 0x0711 },
    .{ .start = 0x0730, .end = 0x074A },
    .{ .start = 0x07A6, .end = 0x07B0 },
    .{ .start = 0x07EB, .end = 0x07F3 },
    .{ .start = 0x07FD, .end = 0x07FD },
    .{ .start = 0x0816, .end = 0x0819 },
    .{ .start = 0x081B, .end = 0x0823 },
    .{ .start = 0x0825, .end = 0x0827 },
    .{ .start = 0x0829, .end = 0x082D },
    .{ .start = 0x0859, .end = 0x085B },
    .{ .start = 0x08D3, .end = 0x0903 },
    .{ .start = 0x093A, .end = 0x093C },
    .{ .start = 0x093E, .end = 0x094F },
    .{ .start = 0x0951, .end = 0x0957 },
    .{ .start = 0x0962, .end = 0x0963 },
    .{ .start = 0x0981, .end = 0x0983 },
    .{ .start = 0x09BC, .end = 0x09BC },
    .{ .start = 0x09BE, .end = 0x09C4 },
    .{ .start = 0x09C7, .end = 0x09C8 },
    .{ .start = 0x09CB, .end = 0x09CD },
    .{ .start = 0x09D7, .end = 0x09D7 },
    .{ .start = 0x09E2, .end = 0x09E3 },
    .{ .start = 0x0A01, .end = 0x0A03 },
    .{ .start = 0x0A3C, .end = 0x0A3C },
    .{ .start = 0x0A3E, .end = 0x0A42 },
    .{ .start = 0x0A47, .end = 0x0A48 },
    .{ .start = 0x0A4B, .end = 0x0A4D },
    .{ .start = 0x0A51, .end = 0x0A51 },
    .{ .start = 0x0A70, .end = 0x0A71 },
    .{ .start = 0x0A75, .end = 0x0A75 },
    .{ .start = 0x0A81, .end = 0x0A83 },
    .{ .start = 0x0ABC, .end = 0x0ABC },
    .{ .start = 0x0ABE, .end = 0x0AC5 },
    .{ .start = 0x0AC7, .end = 0x0AC9 },
    .{ .start = 0x0ACB, .end = 0x0ACD },
    .{ .start = 0x0AE2, .end = 0x0AE3 },
    .{ .start = 0x0AFA, .end = 0x0AFF },
    .{ .start = 0x0B01, .end = 0x0B03 },
    .{ .start = 0x0B3C, .end = 0x0B3C },
    .{ .start = 0x0B3E, .end = 0x0B44 },
    .{ .start = 0x0B47, .end = 0x0B48 },
    .{ .start = 0x0B4B, .end = 0x0B4D },
    .{ .start = 0x0B56, .end = 0x0B57 },
    .{ .start = 0x0B62, .end = 0x0B63 },
    .{ .start = 0x0B82, .end = 0x0B82 },
    .{ .start = 0x0BBE, .end = 0x0BC2 },
    .{ .start = 0x0BC6, .end = 0x0BC8 },
    .{ .start = 0x0BCA, .end = 0x0BCD },
    .{ .start = 0x0BD7, .end = 0x0BD7 },
    .{ .start = 0x0C00, .end = 0x0C04 },
    .{ .start = 0x0C3E, .end = 0x0C44 },
    .{ .start = 0x0C46, .end = 0x0C48 },
    .{ .start = 0x0C4A, .end = 0x0C4D },
    .{ .start = 0x0C55, .end = 0x0C56 },
    .{ .start = 0x0C62, .end = 0x0C63 },
    .{ .start = 0x0C81, .end = 0x0C83 },
    .{ .start = 0x0CBC, .end = 0x0CBC },
    .{ .start = 0x0CBE, .end = 0x0CC4 },
    .{ .start = 0x0CC6, .end = 0x0CC8 },
    .{ .start = 0x0CCA, .end = 0x0CCD },
    .{ .start = 0x0CD5, .end = 0x0CD6 },
    .{ .start = 0x0CE2, .end = 0x0CE3 },
    .{ .start = 0x0D00, .end = 0x0D03 },
    .{ .start = 0x0D3B, .end = 0x0D3C },
    .{ .start = 0x0D3E, .end = 0x0D44 },
    .{ .start = 0x0D46, .end = 0x0D48 },
    .{ .start = 0x0D4A, .end = 0x0D4D },
    .{ .start = 0x0D57, .end = 0x0D57 },
    .{ .start = 0x0D62, .end = 0x0D63 },
    .{ .start = 0x0D81, .end = 0x0D83 },
    .{ .start = 0x0DCA, .end = 0x0DCA },
    .{ .start = 0x0DCF, .end = 0x0DD4 },
    .{ .start = 0x0DD6, .end = 0x0DD6 },
    .{ .start = 0x0DD8, .end = 0x0DDF },
    .{ .start = 0x0DF2, .end = 0x0DF3 },
    .{ .start = 0x0E31, .end = 0x0E31 },
    .{ .start = 0x0E34, .end = 0x0E3A },
    .{ .start = 0x0E47, .end = 0x0E4E },
    .{ .start = 0x0EB1, .end = 0x0EB1 },
    .{ .start = 0x0EB4, .end = 0x0EBC },
    .{ .start = 0x0EC8, .end = 0x0ECD },
    .{ .start = 0x0F18, .end = 0x0F19 },
    .{ .start = 0x0F35, .end = 0x0F35 },
    .{ .start = 0x0F37, .end = 0x0F37 },
    .{ .start = 0x0F39, .end = 0x0F39 },
    .{ .start = 0x0F3E, .end = 0x0F3F },
    .{ .start = 0x0F71, .end = 0x0F84 },
    .{ .start = 0x0F86, .end = 0x0F87 },
    .{ .start = 0x0F8D, .end = 0x0F97 },
    .{ .start = 0x0F99, .end = 0x0FBC },
    .{ .start = 0x0FC6, .end = 0x0FC6 },
    .{ .start = 0x102B, .end = 0x103E },
    .{ .start = 0x1056, .end = 0x1059 },
    .{ .start = 0x105E, .end = 0x1060 },
    .{ .start = 0x1062, .end = 0x1064 },
    .{ .start = 0x1067, .end = 0x106D },
    .{ .start = 0x1071, .end = 0x1074 },
    .{ .start = 0x1082, .end = 0x108D },
    .{ .start = 0x108F, .end = 0x108F },
    .{ .start = 0x109A, .end = 0x109D },
    .{ .start = 0x135D, .end = 0x135F },
    .{ .start = 0x1712, .end = 0x1715 },
    .{ .start = 0x1732, .end = 0x1734 },
    .{ .start = 0x1752, .end = 0x1753 },
    .{ .start = 0x1772, .end = 0x1773 },
    .{ .start = 0x17B4, .end = 0x17D3 },
    .{ .start = 0x17DD, .end = 0x17DD },
    .{ .start = 0x180B, .end = 0x180D },
    .{ .start = 0x180F, .end = 0x180F },
    .{ .start = 0x1885, .end = 0x1886 },
    .{ .start = 0x18A9, .end = 0x18A9 },
    .{ .start = 0x1920, .end = 0x1932 },
    .{ .start = 0x1939, .end = 0x193B },
    .{ .start = 0x1A17, .end = 0x1A1B },
    .{ .start = 0x1A55, .end = 0x1A7F },
    .{ .start = 0x1AB0, .end = 0x1ACE },
    .{ .start = 0x1B00, .end = 0x1B04 },
    .{ .start = 0x1B34, .end = 0x1B44 },
    .{ .start = 0x1B6B, .end = 0x1B73 },
    .{ .start = 0x1B80, .end = 0x1B82 },
    .{ .start = 0x1BA1, .end = 0x1BAD },
    .{ .start = 0x1BE6, .end = 0x1BF3 },
    .{ .start = 0x1C24, .end = 0x1C37 },
    .{ .start = 0x1CD0, .end = 0x1CD2 },
    .{ .start = 0x1CD4, .end = 0x1CE8 },
    .{ .start = 0x1CED, .end = 0x1CED },
    .{ .start = 0x1CF2, .end = 0x1CF4 },
    .{ .start = 0x1CF7, .end = 0x1CF9 },
    .{ .start = 0x1DC0, .end = 0x1DFF },
    .{ .start = 0x200C, .end = 0x200D },
    .{ .start = 0x20D0, .end = 0x20FF },
    .{ .start = 0xFE00, .end = 0xFE0F },
    .{ .start = 0xFE20, .end = 0xFE2F },
    .{ .start = 0xE0100, .end = 0xE01EF },
    .{ .start = 0x1F3FB, .end = 0x1F3FF }, // Emoji skin tone modifiers
};

// Characters typically rendered as double-width in terminals.
const wide_ranges = [_]Range{
    .{ .start = 0x1100, .end = 0x115F },
    .{ .start = 0x231A, .end = 0x231B },
    .{ .start = 0x2329, .end = 0x232A },
    .{ .start = 0x23E9, .end = 0x23EC },
    .{ .start = 0x23F0, .end = 0x23F0 },
    .{ .start = 0x23F3, .end = 0x23F3 },
    .{ .start = 0x25FD, .end = 0x25FE },
    .{ .start = 0x2614, .end = 0x2615 },
    .{ .start = 0x2648, .end = 0x2653 },
    .{ .start = 0x267F, .end = 0x267F },
    .{ .start = 0x2693, .end = 0x2693 },
    .{ .start = 0x26A1, .end = 0x26A1 },
    .{ .start = 0x26AA, .end = 0x26AB },
    .{ .start = 0x26BD, .end = 0x26BE },
    .{ .start = 0x26C4, .end = 0x26C5 },
    .{ .start = 0x26CE, .end = 0x26CE },
    .{ .start = 0x26D4, .end = 0x26D4 },
    .{ .start = 0x26EA, .end = 0x26EA },
    .{ .start = 0x26F2, .end = 0x26F3 },
    .{ .start = 0x26F5, .end = 0x26F5 },
    .{ .start = 0x26FA, .end = 0x26FA },
    .{ .start = 0x26FD, .end = 0x26FD },
    .{ .start = 0x2705, .end = 0x2705 },
    .{ .start = 0x270A, .end = 0x270B },
    .{ .start = 0x2728, .end = 0x2728 },
    .{ .start = 0x274C, .end = 0x274C },
    .{ .start = 0x274E, .end = 0x274E },
    .{ .start = 0x2753, .end = 0x2755 },
    .{ .start = 0x2757, .end = 0x2757 },
    .{ .start = 0x2795, .end = 0x2797 },
    .{ .start = 0x27B0, .end = 0x27B0 },
    .{ .start = 0x27BF, .end = 0x27BF },
    .{ .start = 0x2B1B, .end = 0x2B1C },
    .{ .start = 0x2B50, .end = 0x2B50 },
    .{ .start = 0x2B55, .end = 0x2B55 },
    .{ .start = 0x2E80, .end = 0x2FDF },
    .{ .start = 0x2FF0, .end = 0x303E },
    .{ .start = 0x3040, .end = 0x3247 },
    .{ .start = 0x3250, .end = 0x4DBF },
    .{ .start = 0x4E00, .end = 0xA4CF },
    .{ .start = 0xA960, .end = 0xA97C },
    .{ .start = 0xAC00, .end = 0xD7A3 },
    .{ .start = 0xF900, .end = 0xFAFF },
    .{ .start = 0xFE10, .end = 0xFE6F },
    .{ .start = 0xFF00, .end = 0xFF60 },
    .{ .start = 0xFFE0, .end = 0xFFE6 },
    .{ .start = 0x1F004, .end = 0x1F004 },
    .{ .start = 0x1F0CF, .end = 0x1F0CF },
    .{ .start = 0x1F170, .end = 0x1F251 },
    .{ .start = 0x1F260, .end = 0x1F6D7 },
    .{ .start = 0x1F6DC, .end = 0x1F6EC },
    .{ .start = 0x1F6F4, .end = 0x1F6FC },
    .{ .start = 0x1F7E0, .end = 0x1F7EB },
    .{ .start = 0x1F7F0, .end = 0x1F7F0 },
    .{ .start = 0x1F90C, .end = 0x1F9FF },
    .{ .start = 0x1FA70, .end = 0x1FAFF },
    .{ .start = 0x20000, .end = 0x3FFFD },
};

const emoji_ranges = [_]Range{
    .{ .start = 0x1F004, .end = 0x1F0CF },
    .{ .start = 0x1F170, .end = 0x1F6FF },
    .{ .start = 0x1F7E0, .end = 0x1F7FF },
    .{ .start = 0x1F90C, .end = 0x1FFFF },
};

/// wcwidth implementation tuned for terminals: returns 0, 1, or 2 cells.
pub fn wcwidth(cp: u21) u3 {
    // Control characters have zero width.
    if (cp == 0) return 0;
    if (cp < 32 or (cp >= 0x7F and cp < 0xA0)) return 0;

    if (inRange(cp, combining_ranges[0..])) return 0;
    if (cp == 0x200D) return 0; // Zero width joiner

    if (inRange(cp, wide_ranges[0..])) return 2;

    return 1;
}

fn isBidi(cp: u21) bool {
    return (cp >= 0x0590 and cp <= 0x08FF) or (cp >= 0xFB1D and cp <= 0xFEFC);
}

fn isEmoji(cp: u21) bool {
    if (inRange(cp, emoji_ranges[0..])) return true;
    return (cp >= 0x1F1E6 and cp <= 0x1F1FF) or (cp >= 0x1F300 and cp <= 0x1FAFF);
}

/// Measure a UTF-8 string using wcwidth semantics.
pub fn measure(str: []const u8) Metrics {
    var utf8 = std.unicode.Utf8Iterator{ .bytes = str, .i = 0 };
    var width: u16 = 0;
    var has_bidi = false;
    var has_emoji = false;
    var has_ligatures = false;
    var pending_join = false;

    while (utf8.nextCodepoint()) |cp| {
        if (cp == 0x200D) { // ZWJ
            pending_join = true;
            continue;
        }

        const cp_width: u3 = wcwidth(cp);
        const emoji_cp = isEmoji(cp);
        if (pending_join and emoji_cp) {
            pending_join = false;
        } else {
            width = addWidthSaturating(width, cp_width);
            pending_join = false;
        }

        if (emoji_cp) has_emoji = true;
        if (!has_bidi and isBidi(cp)) has_bidi = true;
        if (!has_ligatures and (cp == 'f' or cp == 'i' or cp == 'l')) has_ligatures = true;
    }

    return Metrics{
        .width = width,
        .has_bidi = has_bidi,
        .has_emoji = has_emoji,
        .has_ligatures = has_ligatures,
    };
}

/// Determine if a string needs width-aware rendering (CJK/emoji/bidi).
pub fn needsWidthAccounting(str: []const u8) bool {
    const metrics = measure(str);
    return metrics.width != str.len or metrics.has_bidi or metrics.has_emoji;
}

fn addWidthSaturating(current: u16, inc: u3) u16 {
    const widened: u32 = @as(u32, current) + inc;
    if (widened > std.math.maxInt(u16)) return std.math.maxInt(u16);
    return @intCast(widened);
}

test "wcwidth handles emoji and CJK" {
    try std.testing.expectEqual(@as(u3, 2), wcwidth('界'));
    try std.testing.expectEqual(@as(u3, 2), wcwidth(0x1F600)); // 😀
}

test "combining marks add zero width" {
    const acute: u21 = 0x0301;
    const base: u21 = 'e';
    try std.testing.expectEqual(@as(u3, 1), wcwidth(base));
    try std.testing.expectEqual(@as(u3, 0), wcwidth(acute));
}

test "measure collapses zwj emoji sequences" {
    const family = "👩‍👩‍👧‍👦";
    const metrics = measure(family);
    try std.testing.expect(metrics.width <= 4);
    try std.testing.expect(metrics.width >= 2);
    try std.testing.expect(metrics.has_emoji);
}

test "needsWidthAccounting flags emoji" {
    try std.testing.expect(needsWidthAccounting("Hi😀"));
}

test "measure clamps very long strings" {
    const alloc = std.testing.allocator;
    const long_len = 70000;
    const buffer = try alloc.alloc(u8, long_len);
    defer alloc.free(buffer);
    @memset(buffer, 'a');

    const metrics = measure(buffer);
    try std.testing.expectEqual(std.math.maxInt(u16), metrics.width);
    try std.testing.expect(!metrics.has_bidi);
    try std.testing.expect(!metrics.has_emoji);
}
