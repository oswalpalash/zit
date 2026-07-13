const std = @import("std");
const grapheme_data = @import("unicode_grapheme_data.zig");

pub const unicode_version = grapheme_data.unicode_version;
pub const grapheme_unicode_version = unicode_version;
pub const width_unicode_version = unicode_version;

/// Metrics describing how a string will occupy terminal cells.
pub const Metrics = struct {
    width: u16,
    has_bidi: bool,
    has_emoji: bool,
    has_ligatures: bool,
    has_combining: bool,
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
    terminal_wide: bool,
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
            .terminal_wide = false,
        };
    }

    const emoji = emojiProperties(cp);
    return .{
        .class = classifyGrapheme(cp),
        .indic = grapheme_data.indicConjunctBreak(cp),
        .emoji_candidate = emoji.emoji_candidate,
        .emoji_presentation = emoji.emoji_presentation,
        .extended_pictographic = emoji.extended_pictographic,
        .terminal_wide = grapheme_data.isTerminalWide(cp),
    };
}

pub fn wcwidthClassified(cp: u21, class: GraphemeClass) u3 {
    return wcwidthKnown(class, grapheme_data.isTerminalWide(cp));
}

pub fn wcwidthProperties(properties: GraphemeProperties) u3 {
    return wcwidthKnown(properties.class, properties.terminal_wide);
}

fn wcwidthKnown(class: GraphemeClass, terminal_wide: bool) u3 {
    return switch (class) {
        .cr, .lf, .control, .extend, .zwj, .prepend, .spacing_mark => 0,
        else => if (terminal_wide) 2 else 1,
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
        const cp_width = wcwidthProperties(properties);
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

test "generated Unicode 17 East Asian width table matches official data" {
    const fixture = @embedFile("testdata/EastAsianWidth-17.0.0.txt");
    try std.testing.expectEqualStrings("17.0.0", width_unicode_version);
    try std.testing.expect(std.mem.indexOf(u8, fixture, "# EastAsianWidth-17.0.0.txt") != null);

    var lines = std.mem.splitScalar(u8, fixture, '\n');
    var next_codepoint: u32 = 0;
    var range_count: usize = 0;

    while (lines.next()) |raw_line| {
        const uncommented = raw_line[0 .. std.mem.indexOfScalar(u8, raw_line, '#') orelse raw_line.len];
        const line = std.mem.trim(u8, uncommented, " \t\r");
        if (line.len == 0) continue;

        var fields = std.mem.splitScalar(u8, line, ';');
        const raw_range = std.mem.trim(u8, fields.next() orelse return error.InvalidEastAsianWidthFixture, " \t");
        const property = std.mem.trim(u8, fields.next() orelse return error.InvalidEastAsianWidthFixture, " \t");
        if (fields.next() != null) return error.InvalidEastAsianWidthFixture;

        const separator = std.mem.indexOf(u8, raw_range, "..") orelse raw_range.len;
        const start = try std.fmt.parseInt(u21, raw_range[0..separator], 16);
        const end = if (separator == raw_range.len)
            start
        else
            try std.fmt.parseInt(u21, raw_range[separator + 2 ..], 16);
        if (start > end or @as(u32, start) < next_codepoint) return error.InvalidEastAsianWidthFixture;

        while (next_codepoint < start) : (next_codepoint += 1) {
            if (grapheme_data.isEastAsianWide(@intCast(next_codepoint))) {
                std.debug.print("unexpected generated wide codepoint U+{X:0>4}\n", .{next_codepoint});
                return error.EastAsianWidthMismatch;
            }
        }

        const expected_wide = std.mem.eql(u8, property, "W") or std.mem.eql(u8, property, "F");
        while (next_codepoint <= end) : (next_codepoint += 1) {
            if (grapheme_data.isEastAsianWide(@intCast(next_codepoint)) != expected_wide) {
                std.debug.print(
                    "generated East Asian width mismatch at U+{X:0>4}: expected {s}\n",
                    .{ next_codepoint, if (expected_wide) "wide" else "narrow" },
                );
                return error.EastAsianWidthMismatch;
            }
        }
        range_count += 1;
    }

    while (next_codepoint <= 0x10FFFF) : (next_codepoint += 1) {
        if (grapheme_data.isEastAsianWide(@intCast(next_codepoint))) {
            std.debug.print("unexpected generated wide codepoint U+{X:0>4}\n", .{next_codepoint});
            return error.EastAsianWidthMismatch;
        }
    }

    try std.testing.expectEqual(@as(usize, 2678), range_count);
    try std.testing.expectEqual(@as(u32, 0x110000), next_codepoint);
}

test "terminal width policy uses W and F plus default emoji" {
    try std.testing.expectEqual(@as(u3, 2), wcwidth(0x2630)); // Trigram for Heaven, W.
    try std.testing.expectEqual(@as(u3, 2), wcwidth(0x4DC0)); // Yijing Hexagram, W.
    try std.testing.expectEqual(@as(u3, 2), wcwidth(0xFF01)); // Fullwidth exclamation, F.
    try std.testing.expectEqual(@as(u3, 1), wcwidth(0xFF61)); // Halfwidth ideographic stop, H.
    try std.testing.expectEqual(@as(u3, 1), wcwidth(0x00A1)); // Ambiguous defaults narrow.
    try std.testing.expectEqual(@as(u3, 1), wcwidth(0x2E9A)); // Unassigned/default neutral.

    try std.testing.expect(!grapheme_data.isEastAsianWide(0x1F1EE));
    try std.testing.expect(grapheme_data.isTerminalWide(0x1F1EE));
    try std.testing.expectEqual(@as(u3, 2), wcwidth(0x1F1EE)); // Regional indicator emoji.
    try std.testing.expectEqual(@as(u16, 5), measure("☰䷀¡").width);
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
