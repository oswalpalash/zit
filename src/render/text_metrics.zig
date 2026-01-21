const std = @import("std");
const unicode_width = @import("../terminal/unicode_width.zig");

/// Text shaping utilities focused on terminal friendly output.
pub const Metrics = unicode_width.Metrics;

/// Width calculation using wcwidth semantics to match terminal rendering.
pub fn measureWidth(str: []const u8) Metrics {
    return unicode_width.measure(str);
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
