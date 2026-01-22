const std = @import("std");
const unicode_width = @import("../terminal/unicode_width.zig");

/// Text shaping utilities focused on terminal friendly output.
pub const Metrics = unicode_width.Metrics;

pub const TextDirection = enum { ltr, rtl, auto };

/// Compact grapheme representation used for width-aware rendering.
pub const Grapheme = struct {
    bytes: [32]u8 = undefined,
    len: u8 = 0,
    width: u3 = 0,
    has_rtl: bool = false,
    has_emoji: bool = false,

    pub fn slice(self: Grapheme) []const u8 {
        return self.bytes[0..self.len];
    }

    pub fn firstCodepoint(self: Grapheme) u21 {
        if (self.len == 0) return 0;
        return std.unicode.utf8Decode(self.bytes[0..self.len]) catch 0;
    }

    pub fn eql(a: Grapheme, b: Grapheme) bool {
        if (a.len != b.len or a.width != b.width or a.has_rtl != b.has_rtl or a.has_emoji != b.has_emoji) return false;
        return std.mem.eql(u8, a.slice(), b.slice());
    }
};

pub fn graphemeFromCodepoint(cp: u21) Grapheme {
    var g = Grapheme{};
    var buf: [4]u8 = undefined;
    const len = std.unicode.utf8Encode(cp, &buf) catch 0;
    const to_copy: u8 = @intCast(@min(len, g.bytes.len));
    if (to_copy > 0) {
        std.mem.copyForwards(u8, g.bytes[0..to_copy], buf[0..to_copy]);
        g.len = to_copy;
    }
    const width: u3 = unicode_width.wcwidth(cp);
    g.width = if (width == 0) 1 else width;
    g.has_rtl = unicode_width.isBidi(cp);
    g.has_emoji = unicode_width.isEmoji(cp);
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
        var pending_join = false;

        while (true) {
            const cp_start = self.it.i;
            const next_cp = self.it.nextCodepoint() orelse break;
            const cp_end = self.it.i;
            const cp_slice = self.it.bytes[cp_start..cp_end];
            const cp_width: u3 = unicode_width.wcwidth(next_cp);
            const combine_like = cp_width == 0 or next_cp == 0x200D;

            if (started and !pending_join and !combine_like and cp_width > 0) {
                // New grapheme starts here.
                self.it.i = cp_start;
                break;
            }

            const available = grapheme.bytes.len - grapheme.len;
            const to_copy: u8 = @intCast(@min(cp_slice.len, available));
            if (to_copy > 0) {
                std.mem.copyForwards(u8, grapheme.bytes[grapheme.len .. grapheme.len + to_copy], cp_slice[0..to_copy]);
                grapheme.len += to_copy;
            }

            const metrics = unicode_width.measure(cp_slice);
            const effective_width: u3 = @intCast(@min(metrics.width, 2));
            if (effective_width > 0) grapheme.width = @max(grapheme.width, effective_width);
            grapheme.has_rtl = grapheme.has_rtl or metrics.has_bidi;
            grapheme.has_emoji = grapheme.has_emoji or metrics.has_emoji;

            started = true;
            pending_join = next_cp == 0x200D;
        }

        if (!started) return null;
        // Pure combining clusters should not advance width, but avoid zero-width cursor lock.
        if (grapheme.width == 0) grapheme.width = 1;
        return grapheme;
    }
};

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
        if (len + g.len > buffer.len) break;
        std.mem.copyForwards(u8, buffer[len .. len + g.len], g.slice());
        len += g.len;
        used_cols += g.width;
    }

    if (add_ellipsis and len + ellipsis.len <= buffer.len) {
        std.mem.copyForwards(u8, buffer[len .. len + ellipsis.len], ellipsis);
        len += ellipsis.len;
    }

    return buffer[0..len];
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
    var graphemes = std.ArrayListUnmanaged(Grapheme){};
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
