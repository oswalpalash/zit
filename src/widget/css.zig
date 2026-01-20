const std = @import("std");
const render = @import("../render/render.zig");
const Theme = @import("theme.zig").Theme;
const ThemeRole = @import("theme.zig").ThemeRole;
const BaseWidget = @import("widgets/base_widget.zig").Widget;

/// Target metadata used to match stylesheet rules.
pub const StyleTarget = struct {
    id: ?[]const u8 = null,
    class: ?[]const u8 = null,
    type_name: ?[]const u8 = null,
};

/// Convenience helper to build a target from a widget instance and type name.
pub fn targetFromWidget(widget: *const BaseWidget, type_name: []const u8) StyleTarget {
    return StyleTarget{
        .id = if (widget.id.len > 0) widget.id else null,
        .class = widget.style_class,
        .type_name = type_name,
    };
}

/// Color value that can be sourced from the theme, a named color, or an RGB literal.
pub const ColorValue = union(enum) {
    named: render.NamedColor,
    rgb: render.RgbColor,
    role: ThemeRole,
};

/// Properties that can be applied from a rule.
pub const StyleProperty = struct {
    fg: ?ColorValue = null,
    bg: ?ColorValue = null,
    bold: ?bool = null,
    italic: ?bool = null,
    underline: ?bool = null,
};

/// Simple selector supporting ids, classes, and type names.
pub const Selector = union(enum) {
    any,
    id: []const u8,
    class: []const u8,
    type_name: []const u8,
};

pub const StyleRule = struct {
    selector: Selector,
    properties: StyleProperty,
};

/// CSS-like stylesheet for applying render styles to widgets.
pub const StyleSheet = struct {
    allocator: std.mem.Allocator,
    rules: std.ArrayList(StyleRule),

    pub const Resolved = struct {
        fg: ?render.Color = null,
        bg: ?render.Color = null,
        style: render.Style = render.Style{},
    };

    pub fn init(allocator: std.mem.Allocator) StyleSheet {
        return StyleSheet{
            .allocator = allocator,
            .rules = std.ArrayList(StyleRule).empty,
        };
    }

    pub fn deinit(self: *StyleSheet) void {
        for (self.rules.items) |rule| {
            switch (rule.selector) {
                .id => |id_text| self.allocator.free(id_text),
                .class => |class_text| self.allocator.free(class_text),
                .type_name => |type_text| self.allocator.free(type_text),
                .any => {},
            }
        }
        self.rules.deinit(self.allocator);
    }

    pub fn addRule(self: *StyleSheet, rule: StyleRule) !void {
        try self.rules.append(self.allocator, rule);
    }

    /// Resolve the final colors and style for a target against the rule set.
    pub fn resolve(self: *StyleSheet, target: StyleTarget, theme: ?Theme, base_style: render.Style) Resolved {
        var resolved = Resolved{ .style = base_style };

        for (self.rules.items) |rule| {
            if (!matches(rule.selector, target)) continue;

            if (rule.properties.fg) |fg_value| {
                resolved.fg = colorFromValue(fg_value, theme);
            }
            if (rule.properties.bg) |bg_value| {
                resolved.bg = colorFromValue(bg_value, theme);
            }

            applyFlags(&resolved.style, rule.properties);
        }

        return resolved;
    }

    /// Parse a small CSS-like string into a stylesheet.
    pub fn parse(allocator: std.mem.Allocator, css: []const u8) !StyleSheet {
        var sheet = StyleSheet.init(allocator);
        errdefer sheet.deinit();

        var i: usize = 0;
        while (i < css.len) {
            skipWhitespace(css, &i);
            if (i >= css.len) break;

            const selector_start = i;
            while (i < css.len and css[i] != '{' and css[i] != '\n') : (i += 1) {}
            const selector_text = std.mem.trim(u8, css[selector_start..i], " \t\r\n");
            if (selector_text.len == 0) break;

            while (i < css.len and css[i] != '{') : (i += 1) {}
            if (i >= css.len) break;
            i += 1; // skip '{'

            var props = StyleProperty{};
            while (i < css.len and css[i] != '}') {
                skipWhitespace(css, &i);
                if (i >= css.len or css[i] == '}') break;

                const key_start = i;
                while (i < css.len and css[i] != ':' and css[i] != '}') : (i += 1) {}
                if (i >= css.len or css[i] == '}') break;

                const key = std.mem.trim(u8, css[key_start..i], " \t\r\n");
                i += 1; // skip ':'

                const value_start = i;
                while (i < css.len and css[i] != ';' and css[i] != '}') : (i += 1) {}
                const value = std.mem.trim(u8, css[value_start..i], " \t\r\n");
                if (i < css.len and css[i] == ';') {
                    i += 1;
                }

                applyProperty(&props, key, value);
            }

            if (i < css.len and css[i] == '}') {
                i += 1;
            }

            const selector = try parseSelector(allocator, selector_text);
            try sheet.addRule(StyleRule{ .selector = selector, .properties = props });
        }

        return sheet;
    }
};

fn matches(selector: Selector, target: StyleTarget) bool {
    return switch (selector) {
        .any => true,
        .id => |id_text| if (target.id) |id| std.mem.eql(u8, id, id_text) else false,
        .class => |class_text| if (target.class) |class| std.mem.eql(u8, class, class_text) else false,
        .type_name => |type_text| if (target.type_name) |type_name| std.mem.eql(u8, type_name, type_text) else false,
    };
}

fn colorFromValue(value: ColorValue, theme: ?Theme) ?render.Color {
    return switch (value) {
        .named => |named| render.Color.named(named),
        .rgb => |rgb| render.Color.rgb(rgb.r, rgb.g, rgb.b),
        .role => |role| if (theme) |t| t.color(role) else null,
    };
}

fn applyFlags(style: *render.Style, props: StyleProperty) void {
    if (props.bold) |flag| style.bold = flag;
    if (props.italic) |flag| style.italic = flag;
    if (props.underline) |flag| style.underline = flag;
}

fn parseSelector(allocator: std.mem.Allocator, raw: []const u8) !Selector {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0 or (trimmed.len == 1 and trimmed[0] == '*')) return Selector.any;

    if (trimmed[0] == '#') {
        return Selector{ .id = try allocator.dupe(u8, trimmed[1..]) };
    }
    if (trimmed[0] == '.') {
        return Selector{ .class = try allocator.dupe(u8, trimmed[1..]) };
    }

    return Selector{ .type_name = try allocator.dupe(u8, trimmed) };
}

fn applyProperty(props: *StyleProperty, key: []const u8, value: []const u8) void {
    if (key.len == 0) return;
    if (std.mem.eql(u8, key, "color") or std.mem.eql(u8, key, "fg")) {
        if (parseColorValue(value)) |c| props.fg = c;
    } else if (std.mem.eql(u8, key, "background") or std.mem.eql(u8, key, "bg")) {
        if (parseColorValue(value)) |c| props.bg = c;
    } else if (std.mem.eql(u8, key, "bold")) {
        props.bold = parseBool(value);
    } else if (std.mem.eql(u8, key, "italic")) {
        props.italic = parseBool(value);
    } else if (std.mem.eql(u8, key, "underline")) {
        props.underline = parseBool(value);
    }
}

fn parseBool(text: []const u8) ?bool {
    if (std.mem.eql(u8, text, "true")) return true;
    if (std.mem.eql(u8, text, "false")) return false;
    return null;
}

fn parseColorValue(text: []const u8) ?ColorValue {
    if (text.len == 0) return null;
    if (text[0] == '#') {
        if (parseHex(text)) |rgb| return ColorValue{ .rgb = rgb };
        return null;
    }

    if (text.len > 5 and std.mem.startsWith(u8, text, "role(") and text[text.len - 1] == ')') {
        const inner = text[5 .. text.len - 1];
        if (stringToEnum(ThemeRole, inner)) |role| {
            return ColorValue{ .role = role };
        }
    }

    if (stringToEnum(render.NamedColor, text)) |named| {
        return ColorValue{ .named = named };
    }

    return null;
}

fn parseHex(text: []const u8) ?render.RgbColor {
    if (text.len != 7) return null;
    const r = std.fmt.parseInt(u8, text[1..3], 16) catch return null;
    const g = std.fmt.parseInt(u8, text[3..5], 16) catch return null;
    const b = std.fmt.parseInt(u8, text[5..7], 16) catch return null;
    return render.RgbColor.init(r, g, b);
}

fn stringToEnum(comptime T: type, raw: []const u8) ?T {
    var lower_buf: [32]u8 = undefined;
    var len: usize = 0;
    for (raw) |c| {
        if (len >= lower_buf.len) return null;
        lower_buf[len] = std.ascii.toLower(c);
        if (lower_buf[len] == '-') {
            lower_buf[len] = '_';
        }
        len += 1;
    }
    return std.meta.stringToEnum(T, lower_buf[0..len]);
}

fn skipWhitespace(css: []const u8, index: *usize) void {
    while (index.* < css.len and std.ascii.isWhitespace(css[index.*])) : (index.* += 1) {}
}

test "stylesheet parses and resolves rules" {
    const allocator = std.testing.allocator;
    const css_text =
        "#primary { color: #ff0000; background: role(surface); bold: true; }\n" ++
        ".button { color: blue; }\n" ++
        "label { italic: true; }";

    var sheet = try StyleSheet.parse(allocator, css_text);
    defer sheet.deinit();

    const theme = Theme.dark();
    const resolved = sheet.resolve(.{
        .id = "primary",
        .class = "button",
        .type_name = "label",
    }, theme, render.Style{});

    try std.testing.expect(resolved.fg != null);
    try std.testing.expect(resolved.bg != null);
    try std.testing.expect(resolved.style.bold);
    try std.testing.expect(resolved.style.italic);

    const expected_fg = render.Color.rgb(255, 0, 0);
    try std.testing.expect(std.meta.eql(expected_fg, resolved.fg.?));

    const expected_bg = theme.color(.surface);
    try std.testing.expect(std.meta.eql(expected_bg, resolved.bg.?));
}
