const std = @import("std");
const grapheme_data = @import("unicode_grapheme_data.zig");

pub const grapheme_unicode_version = grapheme_data.unicode_version;

/// Metrics describing how a string will occupy terminal cells.
pub const Metrics = struct {
    width: u16,
    has_bidi: bool,
    has_emoji: bool,
    has_ligatures: bool,
    has_combining: bool,
};

const Range = struct { start: u21, end: u21 };

fn inRange(cp: u21, ranges: []const Range) bool {
    for (ranges) |r| {
        if (cp >= r.start and cp <= r.end) return true;
    }
    return false;
}

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

/// wcwidth implementation tuned for terminals: returns 0, 1, or 2 cells.
pub fn wcwidth(cp: u21) u3 {
    return wcwidthClassified(cp, classifyGrapheme(cp));
}

/// Return whether a codepoint has a control grapheme-break property.
pub fn isControl(cp: u21) bool {
    return isBreakControl(classifyGrapheme(cp));
}

/// Identify whether a codepoint is right-to-left or bidi-relevant.
pub fn isBidi(cp: u21) bool {
    return (cp >= 0x0590 and cp <= 0x08FF) or (cp >= 0xFB1D and cp <= 0xFEFC);
}

pub const EmojiProperties = struct {
    emoji_candidate: bool,
    emoji_presentation: bool,
    extended_pictographic: bool,
};

/// Classify the emoji properties needed by capability and grapheme handling.
pub fn emojiProperties(cp: u21) EmojiProperties {
    return .{
        .emoji_candidate = grapheme_data.isEmoji(cp),
        .emoji_presentation = grapheme_data.isEmojiPresentation(cp),
        .extended_pictographic = grapheme_data.isExtendedPictographic(cp),
    };
}

/// Identify codepoints whose default presentation is emoji.
pub fn isEmoji(cp: u21) bool {
    return emojiProperties(cp).emoji_presentation;
}

pub fn isKeycapBase(cp: u21) bool {
    return cp == '#' or cp == '*' or (cp >= '0' and cp <= '9');
}

pub fn isKeycapMark(cp: u21) bool {
    return cp == 0x20E3;
}

pub fn isEmojiVariationSelector(cp: u21) bool {
    return cp == 0xFE0F;
}

pub fn isTextVariationSelector(cp: u21) bool {
    return cp == 0xFE0E;
}

/// Identify combining/zero-width marks that should not advance width.
pub fn isCombining(cp: u21) bool {
    const class = classifyGrapheme(cp);
    return class == .extend or class == .zwj or class == .spacing_mark;
}

pub const GraphemeClass = grapheme_data.GraphemeClass;
pub const IndicConjunctBreak = grapheme_data.IndicConjunctBreak;

pub const GraphemeProperties = struct {
    class: GraphemeClass,
    indic: IndicConjunctBreak,
    emoji_candidate: bool,
    emoji_presentation: bool,
    extended_pictographic: bool,
};

pub fn classifyGrapheme(cp: u21) GraphemeClass {
    return grapheme_data.graphemeClass(cp);
}

pub fn graphemeProperties(cp: u21) GraphemeProperties {
    // Printable ASCII is overwhelmingly common in TUI chrome. Only keycap
    // bases carry an Emoji property in this range.
    if (cp >= 0x20 and cp <= 0x7E) {
        return .{
            .class = .other,
            .indic = .none,
            .emoji_candidate = isKeycapBase(cp),
            .emoji_presentation = false,
            .extended_pictographic = false,
        };
    }

    const emoji = emojiProperties(cp);
    return .{
        .class = classifyGrapheme(cp),
        .indic = grapheme_data.indicConjunctBreak(cp),
        .emoji_candidate = emoji.emoji_candidate,
        .emoji_presentation = emoji.emoji_presentation,
        .extended_pictographic = emoji.extended_pictographic,
    };
}

pub fn wcwidthClassified(cp: u21, class: GraphemeClass) u3 {
    return switch (class) {
        .cr, .lf, .control, .extend, .zwj, .prepend, .spacing_mark => 0,
        else => if (inRange(cp, wide_ranges[0..])) 2 else 1,
    };
}

fn isBreakControl(class: GraphemeClass) bool {
    return class == .cr or class == .lf or class == .control;
}

/// Allocation-free Unicode extended-grapheme boundary state used by both
/// measurement and renderer cell iteration.
pub const GraphemeBreakState = struct {
    previous: ?GraphemeClass = null,
    regional_count: u8 = 0,
    pictograph_before_extends: bool = false,
    join_next_pictograph: bool = false,
    indic_consonant_active: bool = false,
    indic_linker_seen: bool = false,

    pub fn breaksBefore(self: GraphemeBreakState, next: GraphemeProperties) bool {
        const previous = self.previous orelse return false;

        if (previous == .cr and next.class == .lf) return false;
        if (isBreakControl(previous) or isBreakControl(next.class)) return true;

        if (previous == .hangul_l and (next.class == .hangul_l or next.class == .hangul_v or next.class == .hangul_lv or next.class == .hangul_lvt)) return false;
        if ((previous == .hangul_lv or previous == .hangul_v) and (next.class == .hangul_v or next.class == .hangul_t)) return false;
        if ((previous == .hangul_lvt or previous == .hangul_t) and next.class == .hangul_t) return false;

        if (next.class == .extend or next.class == .zwj or next.class == .spacing_mark) return false;
        if (previous == .prepend) return false;
        if (next.indic == .consonant and self.indic_consonant_active and self.indic_linker_seen) return false;
        if (previous == .zwj and self.join_next_pictograph and next.extended_pictographic) return false;
        if (previous == .regional_indicator and next.class == .regional_indicator) {
            return self.regional_count % 2 == 0;
        }
        return true;
    }

    pub fn advance(self: *GraphemeBreakState, properties: GraphemeProperties) void {
        if (properties.class == .regional_indicator) {
            self.regional_count +|= 1;
        } else {
            self.regional_count = 0;
        }

        switch (properties.indic) {
            .consonant => {
                self.indic_consonant_active = true;
                self.indic_linker_seen = false;
            },
            .linker => {
                if (self.indic_consonant_active) self.indic_linker_seen = true;
            },
            .extend => {},
            .none => {
                self.indic_consonant_active = false;
                self.indic_linker_seen = false;
            },
        }

        switch (properties.class) {
            .extend => {},
            .zwj => {
                self.join_next_pictograph = self.pictograph_before_extends;
                self.pictograph_before_extends = false;
            },
            else => {
                self.pictograph_before_extends = properties.extended_pictographic;
                self.join_next_pictograph = false;
            },
        }
        self.previous = properties.class;
    }
};

/// Measure a UTF-8 string using wcwidth semantics.
pub fn measure(str: []const u8) Metrics {
    var utf8 = std.unicode.Utf8Iterator{ .bytes = str, .i = 0 };
    var width: u16 = 0;
    var cluster_width: u3 = 0;
    var cluster_started = false;
    var cluster_emoji_candidate = false;
    var cluster_has_emoji = false;
    var cluster_keycap_base = false;
    var boundaries = GraphemeBreakState{};
    var has_bidi = false;
    var has_emoji = false;
    var has_ligatures = false;
    var has_combining = false;

    while (utf8.nextCodepoint()) |cp| {
        const properties = graphemeProperties(cp);
        if (cluster_started and boundaries.breaksBefore(properties)) {
            width = addWidthSaturating(width, if (cluster_width == 0) 1 else cluster_width);
            has_emoji = has_emoji or cluster_has_emoji;
            cluster_width = 0;
            cluster_started = false;
            cluster_emoji_candidate = false;
            cluster_has_emoji = false;
            cluster_keycap_base = false;
            boundaries = .{};
        }

        if (!cluster_started) cluster_keycap_base = isKeycapBase(cp);
        const cp_width = wcwidthClassified(cp, properties.class);
        cluster_width = @max(cluster_width, cp_width);
        cluster_emoji_candidate = cluster_emoji_candidate or properties.emoji_candidate;
        cluster_has_emoji = cluster_has_emoji or properties.emoji_presentation;
        if (isEmojiVariationSelector(cp) and cluster_emoji_candidate) {
            cluster_width = 2;
            cluster_has_emoji = true;
        } else if (isTextVariationSelector(cp) and cluster_emoji_candidate) {
            cluster_width = 1;
            cluster_has_emoji = false;
        }
        if (isKeycapMark(cp) and cluster_keycap_base) {
            cluster_width = 2;
            cluster_has_emoji = true;
        }
        cluster_started = true;
        boundaries.advance(properties);

        if (properties.class == .extend or properties.class == .zwj or properties.class == .spacing_mark) has_combining = true;
        if (!has_bidi and isBidi(cp)) has_bidi = true;
        if (!has_ligatures and (cp == 'f' or cp == 'i' or cp == 'l')) has_ligatures = true;
    }
    if (cluster_started) {
        width = addWidthSaturating(width, if (cluster_width == 0) 1 else cluster_width);
        has_emoji = has_emoji or cluster_has_emoji;
    }

    return Metrics{
        .width = width,
        .has_bidi = has_bidi,
        .has_emoji = has_emoji,
        .has_ligatures = has_ligatures,
        .has_combining = has_combining,
    };
}

/// Determine if a string needs width-aware rendering (CJK/emoji/bidi).
pub fn needsWidthAccounting(str: []const u8) bool {
    const metrics = measure(str);
    return metrics.width != str.len or metrics.has_bidi or metrics.has_emoji or metrics.has_combining;
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
    try std.testing.expectEqual(@as(u16, 2), metrics.width);
    try std.testing.expect(metrics.has_emoji);
}

test "measure keeps BMP pictograph ZWJ sequences atomic" {
    try std.testing.expectEqual(@as(u16, 2), measure("❤️‍🔥").width);
}

test "measure distinguishes text emoji and keycap presentation" {
    const digits = measure("123");
    try std.testing.expectEqual(@as(u16, 3), digits.width);
    try std.testing.expect(!digits.has_emoji);

    const keycap = measure("1️⃣");
    try std.testing.expectEqual(@as(u16, 2), keycap.width);
    try std.testing.expect(keycap.has_emoji);

    const copyright_text = measure("©");
    try std.testing.expectEqual(@as(u16, 1), copyright_text.width);
    try std.testing.expect(!copyright_text.has_emoji);

    const copyright_emoji = measure("©️");
    try std.testing.expectEqual(@as(u16, 2), copyright_emoji.width);
    try std.testing.expect(copyright_emoji.has_emoji);

    const check_text = measure("✅︎");
    try std.testing.expectEqual(@as(u16, 1), check_text.width);
    try std.testing.expect(!check_text.has_emoji);
}

test "measure keeps regional flags and decomposed Hangul atomic" {
    try std.testing.expectEqual(@as(u16, 2), measure("🇮🇳").width);
    try std.testing.expectEqual(@as(u16, 4), measure("🇮🇳🇦").width);
    try std.testing.expectEqual(@as(u16, 2), measure("각").width);
    try std.testing.expectEqual(@as(u16, 2), measure("각").width);
}

test "control boundaries occupy sanitized cells without looking combining" {
    const metrics = measure("A\x1b[\r\nZ");
    try std.testing.expectEqual(@as(u16, 5), metrics.width);
    try std.testing.expect(!metrics.has_combining);
    try std.testing.expect(isControl(0x009B));
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
