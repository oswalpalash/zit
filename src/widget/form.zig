const std = @import("std");

/// Declarative validation rules and helpers for form-style widgets.
pub const Rule = struct {
    kind: RuleKind,
    message: []const u8,
    min: usize = 0,
    max: usize = 0,
    needle: []const u8 = "",
    pattern: []const u8 = "",
    regex: []const u8 = "",
    case_insensitive: bool = false,
    predicate: ?*const fn ([]const u8) bool = null,

    pub fn required(message: []const u8) Rule {
        return .{ .kind = .required, .message = message };
    }

    pub fn minLength(min: usize, message: []const u8) Rule {
        return .{ .kind = .min_length, .message = message, .min = min };
    }

    pub fn maxLength(max: usize, message: []const u8) Rule {
        return .{ .kind = .max_length, .message = message, .max = max };
    }

    pub fn contains(substr: []const u8, message: []const u8) Rule {
        return .{ .kind = .contains, .message = message, .needle = substr };
    }

    pub fn patternRule(glob: []const u8, message: []const u8) Rule {
        return .{ .kind = .pattern, .message = message, .pattern = glob };
    }

    pub fn regexRule(pattern_text: []const u8, message: []const u8) Rule {
        return .{ .kind = .regex, .message = message, .regex = pattern_text };
    }

    pub fn regexCaseInsensitive(pattern_text: []const u8, message: []const u8) Rule {
        return .{
            .kind = .regex,
            .message = message,
            .regex = pattern_text,
            .case_insensitive = true,
        };
    }

    pub fn custom(message: []const u8, predicate: *const fn ([]const u8) bool) Rule {
        return .{ .kind = .custom, .message = message, .predicate = predicate };
    }
};

pub const RuleKind = enum {
    required,
    min_length,
    max_length,
    contains,
    pattern,
    regex,
    custom,
};

/// Shorthand constructors for readable call sites.
pub fn required(message: []const u8) Rule {
    return Rule.required(message);
}

pub fn minLength(min: usize, message: []const u8) Rule {
    return Rule.minLength(min, message);
}

pub fn maxLength(max: usize, message: []const u8) Rule {
    return Rule.maxLength(max, message);
}

pub fn contains(substr: []const u8, message: []const u8) Rule {
    return Rule.contains(substr, message);
}

pub fn patternRule(glob: []const u8, message: []const u8) Rule {
    return Rule.patternRule(glob, message);
}

pub fn regexRule(pattern_text: []const u8, message: []const u8) Rule {
    return Rule.regexRule(pattern_text, message);
}

pub fn regexCaseInsensitive(pattern_text: []const u8, message: []const u8) Rule {
    return Rule.regexCaseInsensitive(pattern_text, message);
}

pub fn rule(message: []const u8, predicate: *const fn ([]const u8) bool) Rule {
    return Rule.custom(message, predicate);
}

/// Collected validation errors for one or more fields.
pub const ValidationResult = struct {
    allocator: std.mem.Allocator,
    errors: std.ArrayList(FieldError),

    pub fn init(allocator: std.mem.Allocator) ValidationResult {
        return .{
            .allocator = allocator,
            .errors = std.ArrayList(FieldError).empty,
        };
    }

    pub fn deinit(self: *ValidationResult) void {
        for (self.errors.items) |err| {
            self.allocator.free(err.field);
            self.allocator.free(err.message);
        }
        self.errors.deinit(self.allocator);
    }

    pub fn isValid(self: ValidationResult) bool {
        return self.errors.items.len == 0;
    }

    pub fn firstError(self: ValidationResult) ?FieldError {
        if (self.errors.items.len == 0) return null;
        return self.errors.items[0];
    }

    pub fn addError(self: *ValidationResult, field: []const u8, message: []const u8) !void {
        const field_copy = try self.allocator.dupe(u8, field);
        errdefer self.allocator.free(field_copy);
        const message_copy = try self.allocator.dupe(u8, message);
        errdefer self.allocator.free(message_copy);

        try self.errors.append(self.allocator, .{
            .field = field_copy,
            .message = message_copy,
        });
    }
};

/// Pair a value with a set of rules for bulk validation.
pub const Field = struct {
    name: []const u8,
    value: []const u8,
    rules: []const Rule,
};

pub const FieldError = struct {
    field: []const u8,
    message: []const u8,
};

/// Validate a single field against its rules.
pub fn validateField(allocator: std.mem.Allocator, field_name: []const u8, value: []const u8, rules: []const Rule) !ValidationResult {
    var result = ValidationResult.init(allocator);
    errdefer result.deinit();

    for (rules) |rule_item| {
        if (!checkRule(rule_item, value)) try result.addError(field_name, rule_item.message);
    }

    return result;
}

/// Validate multiple fields, accumulating all failures.
pub fn validateForm(allocator: std.mem.Allocator, fields: []const Field) !ValidationResult {
    var result = ValidationResult.init(allocator);
    errdefer result.deinit();

    for (fields) |field| {
        for (field.rules) |rule_item| {
            if (!checkRule(rule_item, field.value)) try result.addError(field.name, rule_item.message);
        }
    }

    return result;
}

fn checkRule(r: Rule, value: []const u8) bool {
    return switch (r.kind) {
        .required => value.len > 0,
        .min_length => value.len >= r.min,
        .max_length => value.len <= r.max,
        .contains => std.mem.indexOf(u8, value, r.needle) != null,
        .pattern => matchGlob(r.pattern, value),
        .regex => matchSimpleRegex(r.regex, value, r.case_insensitive),
        .custom => if (r.predicate) |pred| pred(value) else false,
    };
}

/// Simple glob matcher that understands `*` (multi) and `?` (single).
fn matchGlob(pattern_text: []const u8, value: []const u8) bool {
    var p_idx: usize = 0;
    var v_idx: usize = 0;
    var star_idx: ?usize = null;
    var match_idx: usize = 0;

    while (v_idx < value.len) {
        if (p_idx < pattern_text.len and (pattern_text[p_idx] == '?' or pattern_text[p_idx] == value[v_idx])) {
            p_idx += 1;
            v_idx += 1;
        } else if (p_idx < pattern_text.len and pattern_text[p_idx] == '*') {
            star_idx = p_idx;
            match_idx = v_idx;
            p_idx += 1;
        } else if (star_idx) |star| {
            p_idx = star + 1;
            match_idx += 1;
            v_idx = match_idx;
        } else {
            return false;
        }
    }

    while (p_idx < pattern_text.len and pattern_text[p_idx] == '*') {
        p_idx += 1;
    }

    return p_idx == pattern_text.len;
}

const Quantifier = enum {
    one,
    zero_or_one,
    zero_or_more,
    one_or_more,
};

const TokenKind = enum {
    literal,
    any,
    digit,
    word,
    whitespace,
    char_class,
};

const Token = struct {
    kind: TokenKind,
    slice: []const u8,
    quantifier: Quantifier = .one,
    consumed: usize,
};

fn parseToken(pattern_text: []const u8, start: usize) ?Token {
    if (start >= pattern_text.len) return null;

    var idx = start;
    var token_kind: TokenKind = .literal;
    var consumed: usize = 1;

    if (pattern_text[idx] == '\\') {
        if (idx + 1 >= pattern_text.len) return null;
        const esc = pattern_text[idx + 1];
        token_kind = switch (esc) {
            'd' => .digit,
            'w' => .word,
            's' => .whitespace,
            else => .literal,
        };
        idx += 1;
        consumed = 2;
    } else if (pattern_text[idx] == '.') {
        token_kind = .any;
    } else if (pattern_text[idx] == '[') {
        var end = idx + 1;
        while (end < pattern_text.len and pattern_text[end] != ']') : (end += 1) {}
        if (end >= pattern_text.len or pattern_text[end] != ']') return null;
        token_kind = .char_class;
        consumed = end - idx + 1;
    }

    var quantifier: Quantifier = .one;
    const quant_idx = start + consumed;
    if (quant_idx < pattern_text.len) {
        switch (pattern_text[quant_idx]) {
            '*' => {
                quantifier = .zero_or_more;
                consumed += 1;
            },
            '+' => {
                quantifier = .one_or_more;
                consumed += 1;
            },
            '?' => {
                quantifier = .zero_or_one;
                consumed += 1;
            },
            else => {},
        }
    }

    return Token{
        .kind = token_kind,
        .slice = pattern_text[start .. start + consumed],
        .quantifier = quantifier,
        .consumed = consumed,
    };
}

fn classMatch(token_slice: []const u8, ch: u8) bool {
    var idx: usize = 1; // skip '['
    var negate = false;
    if (idx < token_slice.len and token_slice[idx] == '^') {
        negate = true;
        idx += 1;
    }

    var matched = false;
    while (idx < token_slice.len and token_slice[idx] != ']') {
        if (idx + 2 < token_slice.len and token_slice[idx + 1] == '-') {
            const start = token_slice[idx];
            const end = token_slice[idx + 2];
            matched = matched or (ch >= start and ch <= end);
            idx += 3;
        } else {
            matched = matched or (token_slice[idx] == ch);
            idx += 1;
        }
    }

    return if (negate) !matched else matched;
}

fn tokenMatches(token: Token, ch: u8, case_insensitive: bool) bool {
    const c = if (case_insensitive) std.ascii.toLower(ch) else ch;
    return switch (token.kind) {
        .literal => blk: {
            const lit_char = if (token.slice.len > 1 and token.slice[0] == '\\') token.slice[1] else token.slice[0];
            const expected = if (case_insensitive) std.ascii.toLower(lit_char) else lit_char;
            break :blk expected == c;
        },
        .any => true,
        .digit => std.ascii.isDigit(ch),
        .word => std.ascii.isAlphanumeric(ch) or ch == '_',
        .whitespace => std.ascii.isWhitespace(ch),
        .char_class => classMatch(token.slice, ch),
    };
}

/// Lightweight regex matcher supporting `.`, `?`, `*`, `+`, character classes,
/// and escapes `\d`, `\w`, `\s`. It performs a full-string match.
fn matchSimpleRegex(pattern_text: []const u8, value: []const u8, case_insensitive: bool) bool {
    var pattern_str = pattern_text;

    if (pattern_str.len > 0 and pattern_str[0] == '^') {
        pattern_str = pattern_str[1..];
    }
    if (pattern_str.len > 0 and pattern_str[pattern_str.len - 1] == '$') {
        pattern_str = pattern_str[0 .. pattern_str.len - 1];
    }

    return regexInner(pattern_str, value, case_insensitive);
}

fn regexInner(regex_pat: []const u8, value: []const u8, case_insensitive: bool) bool {
    var p_idx: usize = 0;
    var v_idx: usize = 0;

    while (true) {
        if (p_idx == regex_pat.len) return v_idx == value.len;

        const token = parseToken(regex_pat, p_idx) orelse return false;
        p_idx += token.consumed;

        switch (token.quantifier) {
            .one => {
                if (v_idx >= value.len) return false;
                if (!tokenMatches(token, value[v_idx], case_insensitive)) return false;
                v_idx += 1;
            },
            .zero_or_one => {
                if (v_idx < value.len and tokenMatches(token, value[v_idx], case_insensitive)) {
                    if (regexInner(regex_pat[p_idx..], value[v_idx + 1 ..], case_insensitive)) return true;
                }
                return regexInner(regex_pat[p_idx..], value[v_idx..], case_insensitive);
            },
            .zero_or_more => {
                var offset: usize = v_idx;
                while (offset <= value.len) : (offset += 1) {
                    if (regexInner(regex_pat[p_idx..], value[offset..], case_insensitive)) return true;
                    if (offset == value.len) break;
                    if (!tokenMatches(token, value[offset], case_insensitive)) break;
                }
                return false;
            },
            .one_or_more => {
                if (v_idx >= value.len or !tokenMatches(token, value[v_idx], case_insensitive)) return false;
                var offset: usize = v_idx + 1;
                while (offset <= value.len) : (offset += 1) {
                    if (regexInner(regex_pat[p_idx..], value[offset..], case_insensitive)) return true;
                    if (offset == value.len) break;
                    if (!tokenMatches(token, value[offset], case_insensitive)) break;
                }
                return false;
            },
        }
    }
}

test "validation collects failures in order" {
    const alloc = std.testing.allocator;
    const rules = [_]Rule{
        Rule.required("required"),
        Rule.minLength(3, "too short"),
    };

    var res = try validateField(alloc, "username", "", &rules);
    defer res.deinit();

    try std.testing.expect(!res.isValid());
    try std.testing.expectEqual(@as(usize, 2), res.errors.items.len);
    try std.testing.expectEqualStrings("username", res.errors.items[0].field);
    try std.testing.expectEqualStrings("required", res.errors.items[0].message);
    try std.testing.expectEqualStrings("too short", res.errors.items[1].message);
}

test "form validation aggregates across fields" {
    const alloc = std.testing.allocator;
    const fields = [_]Field{
        .{ .name = "email", .value = "invalid", .rules = &[_]Rule{Rule.contains("@", "missing at symbol")} },
        .{ .name = "bio", .value = "ok", .rules = &[_]Rule{Rule.minLength(5, "add more detail")} },
    };

    var res = try validateForm(alloc, &fields);
    defer res.deinit();

    try std.testing.expectEqual(@as(usize, 2), res.errors.items.len);
    try std.testing.expectEqualStrings("email", res.errors.items[0].field);
    try std.testing.expectEqualStrings("missing at symbol", res.errors.items[0].message);
    try std.testing.expectEqualStrings("bio", res.errors.items[1].field);
}

test "custom validation rule can succeed and fail" {
    const alloc = std.testing.allocator;
    const rules = [_]Rule{
        rule("must equal zig", struct {
            fn check(value: []const u8) bool {
                return std.mem.eql(u8, value, "zig");
            }
        }.check),
    };

    var good = try validateField(alloc, "lang", "zig", &rules);
    defer good.deinit();
    try std.testing.expect(good.isValid());

    var bad = try validateField(alloc, "lang", "rust", &rules);
    defer bad.deinit();
    try std.testing.expect(!bad.isValid());
    try std.testing.expectEqualStrings("must equal zig", bad.errors.items[0].message);
}

test "pattern and regex validators cover typical inputs" {
    const alloc = std.testing.allocator;

    const rules = [_]Rule{
        Rule.patternRule("??-###", "ticket id shape"),
        Rule.regexRule("^[A-Z][A-Z]-[0-9][0-9][0-9]$", "ticket uppercase"),
    };

    var result = try validateField(alloc, "ticket", "AB-123", &rules);
    defer result.deinit();
    try std.testing.expect(result.isValid());

    var bad = try validateField(alloc, "ticket", "invalid", &rules);
    defer bad.deinit();
    try std.testing.expect(!bad.isValid());
    try std.testing.expectEqualStrings("ticket id shape", bad.errors.items[0].message);
}

test "case-insensitive regexes match mixed-case input" {
    const alloc = std.testing.allocator;
    const rules = [_]Rule{
        Rule.regexCaseInsensitive("^hello$", "must say hello"),
    };

    var result = try validateField(alloc, "greeting", "HeLLo", &rules);
    defer result.deinit();
    try std.testing.expect(result.isValid());
}
