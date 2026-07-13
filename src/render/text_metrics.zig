const std = @import("std");
const unicode_width = @import("../terminal/unicode_width.zig");

/// Text shaping utilities focused on terminal friendly output.
pub const Metrics = unicode_width.Metrics;

pub const TextDirection = enum { ltr, rtl, auto };

/// Compact grapheme representation used for width-aware rendering.
pub const Grapheme = struct {
    const length_mask: u8 = 0x3F;
    const control_mask: u8 = 0x40;
    const overflow_mask: u8 = 0x80;

    bytes: [32]u8 = undefined,
    /// Low six bits store length; the high bits record control and fallback state.
    len: u8 = 0,
    width: u3 = 0,
    has_rtl: bool = false,
    has_emoji: bool = false,

    pub fn byteLen(self: *const Grapheme) u8 {
        return self.len & length_mask;
    }

    pub fn hasControl(self: *const Grapheme) bool {
        return self.len & control_mask != 0;
    }

    pub fn overflowed(self: *const Grapheme) bool {
        return self.len & overflow_mask != 0;
    }

    fn markOverflowed(self: *Grapheme) void {
        self.len |= overflow_mask;
    }

    fn markControl(self: *Grapheme) void {
        self.len |= control_mask;
    }

    pub fn slice(self: *const Grapheme) []const u8 {
        return self.bytes[0..self.byteLen()];
    }

    pub fn firstCodepoint(self: *const Grapheme) u21 {
        const byte_len = self.byteLen();
        if (byte_len == 0) return 0;
        return std.unicode.utf8Decode(self.bytes[0..byte_len]) catch 0;
    }

    pub fn eql(a: Grapheme, b: Grapheme) bool {
        if (a.len != b.len or a.width != b.width or a.has_rtl != b.has_rtl or a.has_emoji != b.has_emoji) return false;
        return std.mem.eql(u8, a.slice(), b.slice());
    }
};

fn clusterFallbackCodepoint(first: u21) u21 {
    const width = unicode_width.wcwidth(first);
    return if (width == 0 or unicode_width.isControl(first) or first == 0x200D) '?' else first;
}

pub fn graphemeFromCodepoint(cp: u21) Grapheme {
    var g = Grapheme{};
    var buf: [4]u8 = undefined;
    const len = std.unicode.utf8Encode(cp, &buf) catch 0;
    const to_copy: u8 = @intCast(@min(len, g.bytes.len));
    if (to_copy > 0) {
        std.mem.copyForwards(u8, g.bytes[0..to_copy], buf[0..to_copy]);
        g.len = to_copy;
    }
    const properties = unicode_width.graphemeProperties(cp);
    const width = unicode_width.wcwidthClassified(cp, properties.class);
    g.width = if (width == 0) 1 else width;
    g.has_rtl = unicode_width.isBidi(cp);
    g.has_emoji = properties.emoji_presentation;
    if (properties.class == .control or properties.class == .cr or properties.class == .lf) g.markControl();
    return g;
}

/// Iterator that yields grapheme clusters while tracking visual width.
pub const GraphemeIterator = struct {
    it: std.unicode.Utf8Iterator,

    pub fn init(text: []const u8) GraphemeIterator {
        return GraphemeIterator{ .it = .{ .bytes = text, .i = 0 } };
    }

    pub fn next(self: *GraphemeIterator) ?Grapheme {
        var grapheme = Grapheme{};
        var started = false;
        var emoji_candidate = false;
        var keycap_base = false;
        var boundaries = unicode_width.GraphemeBreakState{};
        var first_codepoint: u21 = 0;

        while (true) {
            const cp_start = self.it.i;
            const next_cp = self.it.nextCodepoint() orelse break;
            const cp_end = self.it.i;
            const cp_slice = self.it.bytes[cp_start..cp_end];
            const properties = unicode_width.graphemeProperties(next_cp);
            if (started and boundaries.breaksBefore(properties)) {
                // New grapheme starts here.
                self.it.i = cp_start;
                break;
            }

            if (!started) keycap_base = unicode_width.isKeycapBase(next_cp);
            if (!started) first_codepoint = next_cp;
            const byte_len = grapheme.byteLen();
            const available = grapheme.bytes.len - byte_len;
            if (!grapheme.overflowed() and cp_slice.len <= available) {
                const to_copy: u8 = @intCast(cp_slice.len);
                std.mem.copyForwards(u8, grapheme.bytes[byte_len .. byte_len + to_copy], cp_slice);
                grapheme.len += to_copy;
            } else {
                grapheme.markOverflowed();
            }

            const effective_width = unicode_width.wcwidthClassified(next_cp, properties.class);
            if (effective_width > 0) grapheme.width = @max(grapheme.width, effective_width);
            grapheme.has_rtl = grapheme.has_rtl or unicode_width.isBidi(next_cp);
            emoji_candidate = emoji_candidate or properties.emoji_candidate;
            grapheme.has_emoji = grapheme.has_emoji or properties.emoji_presentation;
            if (unicode_width.isEmojiVariationSelector(next_cp) and emoji_candidate) {
                grapheme.width = 2;
                grapheme.has_emoji = true;
            } else if (unicode_width.isTextVariationSelector(next_cp) and emoji_candidate) {
                grapheme.width = 1;
                grapheme.has_emoji = false;
            }
            if (unicode_width.isKeycapMark(next_cp) and keycap_base) {
                grapheme.width = 2;
                grapheme.has_emoji = true;
            }
            if (properties.class == .control or properties.class == .cr or properties.class == .lf) grapheme.markControl();

            started = true;
            boundaries.advance(properties);
        }

        if (!started) return null;
        // Pure combining clusters should not advance width, but avoid zero-width cursor lock.
        if (grapheme.width == 0) grapheme.width = 1;
        if (grapheme.overflowed()) {
            const width = grapheme.width;
            const has_rtl = grapheme.has_rtl;
            const has_emoji = grapheme.has_emoji;
            const has_control = grapheme.hasControl();
            grapheme = graphemeFromCodepoint(clusterFallbackCodepoint(first_codepoint));
            grapheme.width = width;
            grapheme.has_rtl = has_rtl;
            grapheme.has_emoji = has_emoji;
            if (has_control) grapheme.markControl();
            grapheme.markOverflowed();
        }
        return grapheme;
    }
};

/// Clamp a byte offset to the start or end of a grapheme cluster.
pub fn graphemeBoundaryAtOrBefore(text: []const u8, byte_offset: usize) usize {
    const bounded = @min(byte_offset, text.len);
    var boundary: usize = 0;
    var it = GraphemeIterator.init(text);
    while (it.next()) |_| {
        const next = it.it.i;
        if (next > bounded) break;
        boundary = next;
    }
    return boundary;
}

/// Clamp a byte offset to the next grapheme boundary when it falls inside one.
pub fn graphemeBoundaryAtOrAfter(text: []const u8, byte_offset: usize) usize {
    const bounded = @min(byte_offset, text.len);
    const before = graphemeBoundaryAtOrBefore(text, bounded);
    if (before == bounded) return bounded;
    return nextGraphemeBoundary(text, before);
}

/// Return the grapheme boundary immediately before a normalized byte offset.
pub fn previousGraphemeBoundary(text: []const u8, byte_offset: usize) usize {
    const bounded = graphemeBoundaryAtOrBefore(text, byte_offset);
    if (bounded == 0) return 0;

    var previous: usize = 0;
    var it = GraphemeIterator.init(text);
    while (it.next()) |_| {
        const next = it.it.i;
        if (next >= bounded) break;
        previous = next;
    }
    return previous;
}

/// Return the grapheme boundary immediately after a normalized byte offset.
pub fn nextGraphemeBoundary(text: []const u8, byte_offset: usize) usize {
    const bounded = graphemeBoundaryAtOrBefore(text, byte_offset);
    if (bounded >= text.len) return text.len;

    var it = GraphemeIterator.init(text);
    while (it.next()) |_| {
        if (it.it.i > bounded) return it.it.i;
    }
    return text.len;
}

/// Measure complete grapheme cells ending at or before a byte offset.
pub fn cellWidthThroughByte(text: []const u8, byte_offset: usize) usize {
    const bounded = @min(byte_offset, text.len);
    var cells: usize = 0;
    var it = GraphemeIterator.init(text);
    while (it.next()) |grapheme| {
        if (it.it.i > bounded) break;
        cells = std.math.add(usize, cells, grapheme.width) catch std.math.maxInt(usize);
    }
    return cells;
}

/// Map a terminal-cell column to the last complete grapheme byte boundary.
pub fn byteOffsetForCellColumn(text: []const u8, target_col: usize) usize {
    var cells: usize = 0;
    var boundary: usize = 0;
    var it = GraphemeIterator.init(text);
    while (it.next()) |grapheme| {
        const next_cells = std.math.add(usize, cells, grapheme.width) catch std.math.maxInt(usize);
        if (next_cells > target_col) break;
        cells = next_cells;
        boundary = it.it.i;
    }
    return boundary;
}

/// Round a terminal-cell column up when it falls inside a wide grapheme.
pub fn cellColumnAtOrAfter(text: []const u8, target_col: usize) usize {
    var cells: usize = 0;
    var it = GraphemeIterator.init(text);
    while (it.next()) |grapheme| {
        if (cells >= target_col) return cells;
        cells = std.math.add(usize, cells, grapheme.width) catch return std.math.maxInt(usize);
    }
    return cells;
}

/// Width calculation using wcwidth semantics to match terminal rendering.
pub fn measureWidth(str: []const u8) Metrics {
    return unicode_width.measure(str);
}

/// Truncate text to a max column width, preserving UTF-8 boundaries.
/// When with_ellipsis is true, "..." is appended if truncation occurs.
pub fn truncateToWidth(text: []const u8, max_cols: u16, buffer: []u8, with_ellipsis: bool) []const u8 {
    if (max_cols == 0 or buffer.len == 0) return buffer[0..0];

    const metrics = measureWidth(text);
    if (metrics.width <= max_cols) return text;

    const ellipsis = "...";
    const add_ellipsis = with_ellipsis and max_cols > ellipsis.len;
    var available: u16 = max_cols;
    if (add_ellipsis) {
        available -= @as(u16, @intCast(ellipsis.len));
    }

    var it = GraphemeIterator.init(text);
    var used_cols: u16 = 0;
    var len: usize = 0;
    while (it.next()) |g| {
        if (used_cols + g.width > available) break;
        const grapheme_len = g.byteLen();
        if (len + grapheme_len > buffer.len) break;
        std.mem.copyForwards(u8, buffer[len .. len + grapheme_len], g.slice());
        len += grapheme_len;
        used_cols += g.width;
    }

    if (add_ellipsis and len + ellipsis.len <= buffer.len) {
        std.mem.copyForwards(u8, buffer[len .. len + ellipsis.len], ellipsis);
        len += ellipsis.len;
    }

    return buffer[0..len];
}

pub const ClipResult = struct {
    text: []const u8,
    width: u16,
    clipped: bool,
};

/// Clip text to a terminal-cell width without splitting UTF-8 or grapheme clusters.
///
/// When clipping is required and at least four cells are available, the result
/// reserves three cells for "...". Narrower widths receive only as many dots as
/// fit. The returned slice either aliases `text` when no clipping is needed or
/// points into `buffer`.
pub fn clipWithEllipsis(text: []const u8, max_width: u16, buffer: []u8) ClipResult {
    if (max_width == 0 or buffer.len == 0) {
        return .{ .text = "", .width = 0, .clipped = text.len > 0 };
    }

    const measured = measureWidth(text);
    if (measured.width <= max_width) {
        return .{ .text = text, .width = measured.width, .clipped = false };
    }

    const ellipsis = "...";
    if (max_width <= ellipsis.len) {
        const dot_count = @min(@as(usize, max_width), buffer.len);
        @memset(buffer[0..dot_count], '.');
        return .{ .text = buffer[0..dot_count], .width = @intCast(dot_count), .clipped = true };
    }

    const target_width: u16 = max_width - @as(u16, @intCast(ellipsis.len));
    var out_len: usize = 0;
    var out_width: u16 = 0;
    var it = GraphemeIterator.init(text);
    while (it.next()) |g| {
        const next_width = out_width + @as(u16, g.width);
        if (next_width > target_width) break;
        const slice = g.slice();
        if (out_len + slice.len > buffer.len) break;
        @memcpy(buffer[out_len .. out_len + slice.len], slice);
        out_len += slice.len;
        out_width = next_width;
    }

    const dots_to_copy = @min(ellipsis.len, buffer.len - out_len);
    if (dots_to_copy > 0) {
        @memcpy(buffer[out_len .. out_len + dots_to_copy], ellipsis[0..dots_to_copy]);
        out_len += dots_to_copy;
        out_width += @intCast(dots_to_copy);
    }

    return .{ .text = buffer[0..out_len], .width = out_width, .clipped = true };
}

/// Detect a dominant text direction using a simple RTL majority heuristic.
pub fn detectDirection(str: []const u8) TextDirection {
    var rtl: usize = 0;
    var total: usize = 0;
    var it = std.unicode.Utf8Iterator{ .bytes = str, .i = 0 };
    while (it.nextCodepoint()) |cp| {
        if (unicode_width.isBidi(cp)) rtl += 1;
        total += 1;
    }
    if (rtl == 0) return .ltr;
    return if (rtl * 2 >= total) .rtl else .ltr;
}

pub fn resolveDirection(requested: TextDirection, text: []const u8) TextDirection {
    return switch (requested) {
        .ltr => .ltr,
        .rtl => .rtl,
        .auto => detectDirection(text),
    };
}

/// Collect graphemes in visual order based on the requested direction.
pub fn collectVisualOrder(text: []const u8, direction: TextDirection, list: *std.ArrayListUnmanaged(Grapheme), allocator: std.mem.Allocator) !TextDirection {
    list.clearRetainingCapacity();

    var it = GraphemeIterator.init(text);
    while (it.next()) |g| {
        try list.append(allocator, g);
    }

    const resolved = resolveDirection(direction, text);
    if (resolved == .rtl and list.items.len > 1) {
        std.mem.reverse(Grapheme, list.items);
    }

    return resolved;
}

/// Basic bidi sanitizer: reorders graphemes for simple terminals while preserving combining marks.
pub fn sanitizeBidi(str: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var graphemes = std.ArrayListUnmanaged(Grapheme).empty;
    defer graphemes.deinit(allocator);
    _ = try collectVisualOrder(str, .auto, &graphemes, allocator);

    var out = try allocator.alloc(u8, str.len);
    var cursor: usize = 0;
    for (graphemes.items) |g| {
        const g_slice = g.slice();
        if (cursor + g_slice.len > out.len) break;
        @memcpy(out[cursor .. cursor + g_slice.len], g_slice);
        cursor += g_slice.len;
    }

    return out[0..cursor];
}

/// Detect whether the current terminal advertises true-color support.
pub fn detectTrueColor() bool {
    const colorterm = std.process.getEnvVarOwned(std.heap.page_allocator, "COLORTERM") catch null;
    defer if (colorterm) |buf| std.heap.page_allocator.free(buf);
    if (colorterm) |buf| {
        if (std.mem.indexOf(u8, buf, "truecolor") != null or std.mem.indexOf(u8, buf, "24bit") != null) {
            return true;
        }
    }

    const term = std.process.getEnvVarOwned(std.heap.page_allocator, "TERM") catch null;
    defer if (term) |buf| std.heap.page_allocator.free(buf);
    if (term) |buf| {
        return std.mem.indexOf(u8, buf, "direct") != null or std.mem.indexOf(u8, buf, "truecolor") != null;
    }

    return false;
}

/// Identify whether unicode width management is needed (double-width or bidi).
pub fn needsWidthAccounting(str: []const u8) bool {
    return unicode_width.needsWidthAccounting(str);
}

test "measureWidth handles mixed scripts" {
    const metrics = measureWidth("abcאבג");
    try std.testing.expect(metrics.width >= 6);
    try std.testing.expect(metrics.has_bidi);
}

test "sanitizeBidi reverses rtl dominant strings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const cleaned = try sanitizeBidi("אבג", alloc);
    defer alloc.free(cleaned);
    try std.testing.expectEqualStrings("גבא", cleaned);
}

test "needsWidthAccounting detects emoji" {
    try std.testing.expect(needsWidthAccounting("hi\xF0\x9F\x98\x81"));
}

test "detectDirection spots rtl dominance" {
    try std.testing.expectEqual(TextDirection.rtl, detectDirection("שלום"));
    try std.testing.expectEqual(TextDirection.ltr, detectDirection("hello"));
}

test "grapheme iterator keeps emoji intact" {
    var it = GraphemeIterator.init("A\u{0301}\xF0\x9F\x98\x81");
    const first = it.next().?;
    try std.testing.expectEqual(@as(u3, 1), first.width);
    const second = it.next().?;
    try std.testing.expectEqual(@as(u3, 2), second.width);
}

test "grapheme byte and cell conversions preserve cluster boundaries" {
    const text = "A界e\u{0301}😁";

    try std.testing.expectEqual(@as(usize, 1), graphemeBoundaryAtOrBefore(text, 2));
    try std.testing.expectEqual(@as(usize, 4), graphemeBoundaryAtOrAfter(text, 2));
    try std.testing.expectEqual(@as(usize, 4), previousGraphemeBoundary(text, 7));
    try std.testing.expectEqual(@as(usize, 7), nextGraphemeBoundary(text, 4));

    try std.testing.expectEqual(@as(usize, 1), cellWidthThroughByte(text, 1));
    try std.testing.expectEqual(@as(usize, 3), cellWidthThroughByte(text, 4));
    try std.testing.expectEqual(@as(usize, 4), cellWidthThroughByte(text, 7));
    try std.testing.expectEqual(@as(usize, 6), cellWidthThroughByte(text, text.len));

    try std.testing.expectEqual(@as(usize, 1), byteOffsetForCellColumn(text, 2));
    try std.testing.expectEqual(@as(usize, 4), byteOffsetForCellColumn(text, 3));
    try std.testing.expectEqual(@as(usize, 7), byteOffsetForCellColumn(text, 5));
    try std.testing.expectEqual(@as(usize, text.len), byteOffsetForCellColumn(text, 6));
    try std.testing.expectEqual(@as(usize, 3), cellColumnAtOrAfter(text, 2));
}

test "grapheme conversions keep joined emoji atomic" {
    const family = "👩‍👩‍👧‍👦";
    try std.testing.expectEqual(@as(usize, 0), graphemeBoundaryAtOrBefore(family, 4));
    try std.testing.expectEqual(family.len, graphemeBoundaryAtOrAfter(family, 4));
    try std.testing.expectEqual(family.len, nextGraphemeBoundary(family, 0));
    try std.testing.expectEqual(@as(usize, 2), cellWidthThroughByte(family, family.len));
}

test "grapheme iterator isolates controls and keeps CRLF atomic" {
    var it = GraphemeIterator.init("A\x1b[\r\nZ");

    try std.testing.expectEqualStrings("A", it.next().?.slice());
    const escape = it.next().?;
    try std.testing.expectEqualStrings("\x1b", escape.slice());
    try std.testing.expect(escape.hasControl());
    try std.testing.expectEqualStrings("[", it.next().?.slice());
    const crlf = it.next().?;
    try std.testing.expectEqualStrings("\r\n", crlf.slice());
    try std.testing.expect(crlf.hasControl());
    try std.testing.expectEqualStrings("Z", it.next().?.slice());
    try std.testing.expect(it.next() == null);
}

test "grapheme iterator pairs regional indicators and Hangul Jamo" {
    const flag = "🇮🇳";
    var flag_it = GraphemeIterator.init(flag ++ "X");
    const flag_grapheme = flag_it.next().?;
    try std.testing.expectEqualStrings(flag, flag_grapheme.slice());
    try std.testing.expectEqual(@as(u3, 2), flag_grapheme.width);
    try std.testing.expectEqual(flag.len, flag_it.it.i);
    try std.testing.expectEqualStrings("X", flag_it.next().?.slice());

    const three_indicators = "🇮🇳🇦";
    var three_it = GraphemeIterator.init(three_indicators);
    try std.testing.expectEqualStrings(flag, three_it.next().?.slice());
    try std.testing.expectEqualStrings("🇦", three_it.next().?.slice());
    try std.testing.expect(three_it.next() == null);

    const hangul = "각";
    var hangul_it = GraphemeIterator.init(hangul ++ "A");
    const syllable = hangul_it.next().?;
    try std.testing.expectEqualStrings(hangul, syllable.slice());
    try std.testing.expectEqual(@as(u3, 2), syllable.width);
    try std.testing.expectEqual(hangul.len, hangul_it.it.i);

    const composed_lv = "각";
    var composed_it = GraphemeIterator.init(composed_lv ++ "A");
    try std.testing.expectEqualStrings(composed_lv, composed_it.next().?.slice());
}

test "non-emoji text after ZWJ starts a new grapheme" {
    const joined = "a\u{200D}";
    var it = GraphemeIterator.init(joined ++ "b");
    try std.testing.expectEqualStrings(joined, it.next().?.slice());
    try std.testing.expectEqualStrings("b", it.next().?.slice());
}

test "BMP pictograph ZWJ sequence stays atomic" {
    const heart_on_fire = "❤️‍🔥";
    var it = GraphemeIterator.init(heart_on_fire ++ "A");
    const grapheme = it.next().?;
    try std.testing.expectEqualStrings(heart_on_fire, grapheme.slice());
    try std.testing.expectEqual(@as(u3, 2), grapheme.width);
    try std.testing.expectEqual(heart_on_fire.len, it.it.i);
}

test "Unicode 17 extended grapheme cluster conformance" {
    const fixture = @embedFile("../terminal/testdata/GraphemeBreakTest-17.0.0.txt");
    try std.testing.expectEqualStrings("17.0.0", unicode_width.grapheme_unicode_version);
    try std.testing.expect(std.mem.indexOf(u8, fixture, "# GraphemeBreakTest-17.0.0.txt") != null);

    var lines = std.mem.splitScalar(u8, fixture, '\n');
    var line_number: usize = 0;
    var case_count: usize = 0;

    while (lines.next()) |raw_line| {
        line_number += 1;
        const uncommented = raw_line[0 .. std.mem.indexOfScalar(u8, raw_line, '#') orelse raw_line.len];
        const line = std.mem.trim(u8, uncommented, " \t\r");
        if (line.len == 0) continue;

        var encoded: [256]u8 = undefined;
        var encoded_len: usize = 0;
        var expected: [128]usize = undefined;
        var expected_len: usize = 0;
        var tokens = std.mem.tokenizeAny(u8, line, " \t");
        while (tokens.next()) |token| {
            if (std.mem.eql(u8, token, "÷")) {
                if (expected_len >= expected.len) return error.UnicodeGraphemeFixtureTooLarge;
                expected[expected_len] = encoded_len;
                expected_len += 1;
                continue;
            }
            if (std.mem.eql(u8, token, "×")) continue;

            const cp = try std.fmt.parseInt(u21, token, 16);
            var cp_bytes: [4]u8 = undefined;
            const cp_len = try std.unicode.utf8Encode(cp, &cp_bytes);
            if (encoded_len + cp_len > encoded.len) return error.UnicodeGraphemeFixtureTooLarge;
            @memcpy(encoded[encoded_len .. encoded_len + cp_len], cp_bytes[0..cp_len]);
            encoded_len += cp_len;
        }

        if (expected_len < 2 or expected[0] != 0 or expected[expected_len - 1] != encoded_len) {
            std.debug.print("invalid Unicode grapheme fixture at line {d}\n", .{line_number});
            return error.InvalidUnicodeGraphemeFixture;
        }

        var actual = GraphemeIterator.init(encoded[0..encoded_len]);
        var boundary_index: usize = 1;
        while (actual.next()) |_| {
            if (boundary_index >= expected_len or actual.it.i != expected[boundary_index]) {
                std.debug.print(
                    "Unicode grapheme mismatch at fixture line {d}: boundary {d}, got byte {d}, expected {d}\n",
                    .{ line_number, boundary_index, actual.it.i, if (boundary_index < expected_len) expected[boundary_index] else encoded_len },
                );
                return error.UnicodeGraphemeConformanceMismatch;
            }
            boundary_index += 1;
        }
        if (boundary_index != expected_len) {
            std.debug.print(
                "Unicode grapheme mismatch at fixture line {d}: produced {d} boundaries, expected {d}\n",
                .{ line_number, boundary_index, expected_len },
            );
            return error.UnicodeGraphemeConformanceMismatch;
        }
        case_count += 1;
    }

    try std.testing.expectEqual(@as(usize, 766), case_count);
}

test "overlong grapheme fallback never stores partial UTF-8" {
    var text: [81]u8 = undefined;
    text[0] = 'e';
    var offset: usize = 1;
    while (offset < text.len) : (offset += 2) {
        text[offset] = 0xCC;
        text[offset + 1] = 0x81;
    }

    var it = GraphemeIterator.init(&text);
    const grapheme = it.next().?;
    try std.testing.expect(grapheme.overflowed());
    try std.testing.expectEqualStrings("e", grapheme.slice());
    try std.testing.expect(std.unicode.utf8ValidateSlice(grapheme.slice()));
    try std.testing.expectEqual(@as(u3, 1), grapheme.width);
    try std.testing.expectEqual(text.len, it.it.i);
    try std.testing.expect(it.next() == null);
}

test "overlong zero-width cluster uses printable fallback" {
    var text: [80]u8 = undefined;
    var offset: usize = 0;
    while (offset < text.len) : (offset += 2) {
        text[offset] = 0xCC;
        text[offset + 1] = 0x81;
    }

    var it = GraphemeIterator.init(&text);
    const grapheme = it.next().?;
    try std.testing.expect(grapheme.overflowed());
    try std.testing.expectEqualStrings("?", grapheme.slice());
    try std.testing.expectEqual(@as(u3, 1), grapheme.width);
}

test "clipWithEllipsis preserves exact-fit text" {
    var buffer: [32]u8 = undefined;
    const clipped = clipWithEllipsis("Checks catch clipping.", 22, &buffer);
    try std.testing.expect(!clipped.clipped);
    try std.testing.expectEqualStrings("Checks catch clipping.", clipped.text);
    try std.testing.expectEqual(@as(u16, 22), clipped.width);
}

test "clipWithEllipsis keeps utf8 valid and respects wide glyph width" {
    var buffer: [32]u8 = undefined;
    const clipped = clipWithEllipsis("ab界cd", 5, &buffer);
    try std.testing.expect(clipped.clipped);
    try std.testing.expect(std.unicode.utf8ValidateSlice(clipped.text));
    try std.testing.expect(clipped.width <= 5);
    try std.testing.expectEqualStrings("ab...", clipped.text);
}

test "truncateToWidth does not split a regional flag pair" {
    var buffer: [16]u8 = undefined;
    const truncated = truncateToWidth("🇮🇳A", 2, &buffer, false);
    try std.testing.expectEqualStrings("🇮🇳", truncated);
}
