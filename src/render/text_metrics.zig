const std = @import("std");

/// Text shaping utilities focused on terminal friendly output.
pub const Metrics = struct {
    /// Total display cells consumed by the input string.
    width: u16,
    /// Whether the string contained bidirectional markers.
    has_bidi: bool,
    /// Whether the string contained emoji codepoints.
    has_emoji: bool,
    /// Whether the string contained characters that typically render as ligatures.
    has_ligatures: bool,
};

/// Heuristic width calculation that treats common double-width ranges properly and
/// falls back to single cell for everything else.
pub fn measureWidth(str: []const u8) Metrics {
    var utf8 = std.unicode.Utf8Iterator{ .bytes = str, .i = 0 };
    var width: u16 = 0;
    var has_bidi = false;
    var has_emoji = false;
    var has_ligatures = false;

    while (utf8.nextCodepoint()) |cp| {
        const cp_width: u16 = switch (cp) {
            // East Asian Wide and Fullwidth blocks plus a few emoji ranges.
            0x1100...0x115F, 0x2329, 0x232A, 0x2E80...0xA4CF, 0xAC00...0xD7A3,
            0xF900...0xFAFF, 0xFE10...0xFE6F, 0xFF00...0xFF60, 0xFFE0...0xFFE6,
            0x1F300...0x1FAFF => 2,
            else => 1,
        };

        width +%= cp_width;

        if (!has_bidi and (cp >= 0x0590 and cp <= 0x08FF)) {
            has_bidi = true;
        }

        if (!has_emoji and cp >= 0x1F300 and cp <= 0x1FAFF) {
            has_emoji = true;
        }

        // Ligature friendly pairs (fi, fl, ff, ffi, ffl) live in Latin ranges.
        if (!has_ligatures and (cp == 'f' or cp == 'i' or cp == 'l')) {
            has_ligatures = true;
        }
    }

    return Metrics{ .width = width, .has_bidi = has_bidi, .has_emoji = has_emoji, .has_ligatures = has_ligatures };
}

/// Basic bidi sanitizer: reverse RTL-only sequences so they render coherently in simple terminals.
pub fn sanitizeBidi(str: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var utf8 = std.unicode.Utf8Iterator{ .bytes = str, .i = 0 };
    var codepoints = std.ArrayListUnmanaged(u21){};
    defer codepoints.deinit(allocator);

    while (utf8.nextCodepoint()) |cp| {
        try codepoints.append(allocator, cp);
    }

    // Simple heuristic: reverse if majority of codepoints are RTL.
    var rtl_count: usize = 0;
    for (codepoints.items) |cp| {
        if (cp >= 0x0590 and cp <= 0x08FF) rtl_count += 1;
    }

    if (rtl_count > codepoints.items.len / 2) {
        std.mem.reverse(u21, codepoints.items);
    }

    const out = try allocator.alloc(u8, str.len);
    var idx: usize = 0;
    for (codepoints.items) |cp| {
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(cp, &buf) catch {
            return error.InvalidCodepoint;
        };
        if (idx + len > out.len) {
            return error.BufferTooSmall;
        }
        @memcpy(out[idx .. idx + len], buf[0..len]);
        idx += len;
    }

    return out[0..idx];
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
    const metrics = measureWidth(str);
    return metrics.width != str.len or metrics.has_bidi or metrics.has_emoji;
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
