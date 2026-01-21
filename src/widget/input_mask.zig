const std = @import("std");

/// Declarative formatter that forces user input to conform to a shape.
/// Supported placeholder tokens:
/// - `#` digit
/// - `A`/`a` alphabetic
/// - `X` alphanumeric
/// - `*` any printable
/// All other characters are treated as literals that are injected into the output.
pub const Mask = struct {
    allocator: std.mem.Allocator,
    pattern: []const u8,
    tokens: []Token,

    pub fn init(allocator: std.mem.Allocator, pattern: []const u8) !Mask {
        const copy = try allocator.dupe(u8, pattern);

        const parsed = try allocator.alloc(Token, copy.len);
        var count: usize = 0;
        for (copy) |ch| {
            parsed[count] = .{ .kind = tokenKind(ch), .literal = ch };
            count += 1;
        }

        return .{
            .allocator = allocator,
            .pattern = copy,
            .tokens = parsed[0..count],
        };
    }

    pub fn deinit(self: *Mask) void {
        self.allocator.free(self.pattern);
        self.allocator.free(self.tokens);
    }

    pub fn phoneUs(allocator: std.mem.Allocator) !Mask {
        return init(allocator, "(###) ###-####");
    }

    pub fn date(allocator: std.mem.Allocator) !Mask {
        return init(allocator, "##/##/####");
    }

    pub fn creditCard(allocator: std.mem.Allocator) !Mask {
        return init(allocator, "#### #### #### ####");
    }

    pub fn currency(allocator: std.mem.Allocator, symbol: []const u8) !Mask {
        const pattern = try std.fmt.allocPrint(allocator, "{s}###,###.##", .{symbol});
        return init(allocator, pattern);
    }

    /// Maximum formatted length for this mask.
    pub fn maxLength(self: Mask) usize {
        return self.tokens.len;
    }

    /// Apply the mask to an arbitrary string. Non-matching characters are skipped
    /// and the output is truncated to the mask's pattern.
    pub fn format(self: *const Mask, allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
        var output = try std.ArrayList(u8).initCapacity(allocator, 0);
        errdefer output.deinit(allocator);

        var input_idx: usize = 0;
        var has_written_placeholder = false;

        for (self.tokens, 0..) |token, idx| {
            switch (token.kind) {
                .literal => {
                    if (has_written_placeholder or hasUpcomingInput(raw, input_idx, self.tokens[idx + 1 ..])) {
                        try output.append(allocator, token.literal);
                    }
                },
                else => {
                    const ch = nextMatching(raw, &input_idx, token.kind) orelse break;
                    try output.append(allocator, ch);
                    has_written_placeholder = true;
                },
            }
        }

        return output.toOwnedSlice(allocator);
    }
};

const TokenKind = enum {
    digit,
    alpha,
    alphanumeric,
    any,
    literal,
};

const Token = struct { kind: TokenKind, literal: u8 };

fn tokenKind(ch: u8) TokenKind {
    return switch (ch) {
        '#' => .digit,
        'A', 'a' => .alpha,
        'X', 'x' => .alphanumeric,
        '*' => .any,
        else => .literal,
    };
}

fn matches(kind: TokenKind, ch: u8) bool {
    return switch (kind) {
        .digit => std.ascii.isDigit(ch),
        .alpha => std.ascii.isAlphabetic(ch),
        .alphanumeric => std.ascii.isAlphanumeric(ch),
        .any => std.ascii.isPrint(ch),
        .literal => false,
    };
}

fn nextMatching(raw: []const u8, idx: *usize, kind: TokenKind) ?u8 {
    var i = idx.*;
    while (i < raw.len) : (i += 1) {
        const ch = raw[i];
        if (matches(kind, ch)) {
            idx.* = i + 1;
            return ch;
        }
    }
    return null;
}

fn hasUpcomingInput(raw: []const u8, start_idx: usize, tokens: []const Token) bool {
    if (tokens.len == 0) return false;

    var i = start_idx;
    while (i < raw.len) : (i += 1) {
        const ch = raw[i];
        for (tokens) |token| {
            if (token.kind == .literal) continue;
            if (matches(token.kind, ch)) return true;
        }
    }
    return false;
}

test "mask formats partial and complete phone numbers" {
    const alloc = std.testing.allocator;
    var mask = try Mask.phoneUs(alloc);
    defer mask.deinit();

    const formatted = try mask.format(alloc, "12345");
    defer alloc.free(formatted);
    try std.testing.expectEqualStrings("(123) 45", formatted);

    const full = try mask.format(alloc, "1234567890");
    defer alloc.free(full);
    try std.testing.expectEqualStrings("(123) 456-7890", full);
}

test "custom currency symbol is preserved" {
    const alloc = std.testing.allocator;
    var mask = try Mask.currency(alloc, "$");
    defer mask.deinit();

    const formatted = try mask.format(alloc, "98765");
    defer alloc.free(formatted);
    try std.testing.expectEqualStrings("$98,765", formatted);
}
