const std = @import("std");

/// Declarative validation rules and helpers for form-style widgets.
pub const Rule = struct {
    kind: RuleKind,
    message: []const u8,
    min: usize = 0,
    max: usize = 0,
    needle: []const u8 = "",
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

    pub fn custom(message: []const u8, predicate: *const fn ([]const u8) bool) Rule {
        return .{ .kind = .custom, .message = message, .predicate = predicate };
    }
};

pub const RuleKind = enum {
    required,
    min_length,
    max_length,
    contains,
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
        .custom => if (r.predicate) |pred| pred(value) else false,
    };
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
