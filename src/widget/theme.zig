const std = @import("std");
const render = @import("../render/render.zig");
const Color = render.Color;
const NamedColor = render.NamedColor;

/// Roles that can be themed across widgets.
pub const ThemeRole = enum {
    background,
    surface,
    text,
    muted,
    accent,
    success,
    warning,
    danger,
    border,
};

/// Core palette used to paint widgets.
pub const Palette = struct {
    background: Color,
    surface: Color,
    text: Color,
    muted: Color,
    accent: Color,
    success: Color,
    warning: Color,
    danger: Color,
    border: Color,
};

/// A theme combines a palette and a default text style.
pub const Theme = struct {
    palette: Palette,
    style: render.Style = render.Style{},

    /// Standard light theme.
    pub fn light() Theme {
        return Theme{
            .palette = Palette{
                .background = Color.rgb(245, 247, 251),
                .surface = Color.rgb(255, 255, 255),
                .text = Color.rgb(27, 36, 48),
                .muted = Color.rgb(104, 116, 139),
                .accent = Color.rgb(59, 130, 246),
                .success = Color.rgb(16, 185, 129),
                .warning = Color.rgb(234, 179, 8),
                .danger = Color.rgb(239, 68, 68),
                .border = Color.rgb(209, 213, 219),
            },
        };
    }

    /// Standard dark theme.
    pub fn dark() Theme {
        return Theme{
            .palette = Palette{
                .background = Color.rgb(10, 14, 22),
                .surface = Color.rgb(19, 27, 38),
                .text = Color.rgb(229, 231, 235),
                .muted = Color.rgb(136, 146, 166),
                .accent = Color.rgb(88, 166, 255),
                .success = Color.rgb(63, 185, 80),
                .warning = Color.rgb(210, 153, 34),
                .danger = Color.rgb(244, 112, 103),
                .border = Color.rgb(35, 45, 60),
            },
        };
    }

    /// High contrast theme for accessibility.
    pub fn highContrast() Theme {
        return Theme{
            .palette = Palette{
                .background = Color.rgb(0, 0, 0),
                .surface = Color.rgb(10, 10, 10),
                .text = Color.rgb(255, 255, 255),
                .muted = Color.rgb(230, 230, 230),
                .accent = Color.rgb(255, 213, 0),
                .success = Color.rgb(0, 255, 140),
                .warning = Color.rgb(255, 191, 0),
                .danger = Color.rgb(255, 85, 85),
                .border = Color.rgb(255, 255, 255),
            },
            .style = render.Style{
                .bold = true,
            },
        };
    }

    /// Dracula-inspired theme with saturated accents.
    pub fn dracula() Theme {
        return Theme{
            .palette = Palette{
                .background = Color.rgb(26, 27, 38),
                .surface = Color.rgb(40, 42, 54),
                .text = Color.rgb(248, 248, 242),
                .muted = Color.rgb(124, 127, 156),
                .accent = Color.rgb(189, 147, 249),
                .success = Color.rgb(80, 250, 123),
                .warning = Color.rgb(241, 250, 140),
                .danger = Color.rgb(255, 85, 85),
                .border = Color.rgb(68, 71, 90),
            },
        };
    }

    /// Nord-inspired cool theme.
    pub fn nord() Theme {
        return Theme{
            .palette = Palette{
                .background = Color.rgb(46, 52, 64),
                .surface = Color.rgb(59, 66, 82),
                .text = Color.rgb(229, 233, 240),
                .muted = Color.rgb(167, 173, 186),
                .accent = Color.rgb(136, 192, 208),
                .success = Color.rgb(143, 188, 187),
                .warning = Color.rgb(235, 203, 139),
                .danger = Color.rgb(191, 97, 106),
                .border = Color.rgb(76, 86, 106),
            },
        };
    }

    /// Gruvbox-inspired warm theme.
    pub fn gruvbox() Theme {
        return Theme{
            .palette = Palette{
                .background = Color.rgb(29, 32, 33),
                .surface = Color.rgb(50, 48, 47),
                .text = Color.rgb(235, 219, 178),
                .muted = Color.rgb(189, 174, 147),
                .accent = Color.rgb(215, 153, 33),
                .success = Color.rgb(184, 187, 38),
                .warning = Color.rgb(250, 189, 47),
                .danger = Color.rgb(251, 73, 52),
                .border = Color.rgb(80, 73, 69),
            },
        };
    }

    /// Solarized Dark palette.
    pub fn solarizedDark() Theme {
        return Theme{
            .palette = Palette{
                .background = Color.rgb(0, 43, 54),
                .surface = Color.rgb(7, 54, 66),
                .text = Color.rgb(238, 232, 213),
                .muted = Color.rgb(147, 161, 161),
                .accent = Color.rgb(38, 139, 210),
                .success = Color.rgb(133, 153, 0),
                .warning = Color.rgb(181, 137, 0),
                .danger = Color.rgb(220, 50, 47),
                .border = Color.rgb(88, 110, 117),
            },
        };
    }

    /// Solarized Light palette.
    pub fn solarizedLight() Theme {
        return Theme{
            .palette = Palette{
                .background = Color.rgb(253, 246, 227),
                .surface = Color.rgb(238, 232, 213),
                .text = Color.rgb(101, 123, 131),
                .muted = Color.rgb(147, 161, 161),
                .accent = Color.rgb(38, 139, 210),
                .success = Color.rgb(133, 153, 0),
                .warning = Color.rgb(181, 137, 0),
                .danger = Color.rgb(220, 50, 47),
                .border = Color.rgb(131, 148, 150),
            },
            .style = render.Style{},
        };
    }

    /// Monokai palette with punchy neon accents.
    pub fn monokai() Theme {
        return Theme{
            .palette = Palette{
                .background = Color.rgb(39, 40, 34),
                .surface = Color.rgb(49, 50, 43),
                .text = Color.rgb(248, 248, 242),
                .muted = Color.rgb(117, 113, 94),
                .accent = Color.rgb(166, 226, 46),
                .success = Color.rgb(166, 226, 46),
                .warning = Color.rgb(253, 151, 31),
                .danger = Color.rgb(249, 38, 114),
                .border = Color.rgb(73, 72, 62),
            },
        };
    }

    /// Catppuccin Mocha (dark) palette.
    pub fn catppuccinMocha() Theme {
        return Theme{
            .palette = Palette{
                .background = Color.rgb(24, 24, 37),
                .surface = Color.rgb(30, 30, 46),
                .text = Color.rgb(205, 214, 244),
                .muted = Color.rgb(166, 173, 200),
                .accent = Color.rgb(137, 180, 250),
                .success = Color.rgb(166, 227, 161),
                .warning = Color.rgb(249, 226, 175),
                .danger = Color.rgb(243, 139, 168),
                .border = Color.rgb(108, 112, 134),
            },
        };
    }

    /// Catppuccin Latte (light) palette.
    pub fn catppuccinLatte() Theme {
        return Theme{
            .palette = Palette{
                .background = Color.rgb(239, 241, 245),
                .surface = Color.rgb(230, 233, 239),
                .text = Color.rgb(76, 79, 105),
                .muted = Color.rgb(156, 160, 176),
                .accent = Color.rgb(114, 135, 253),
                .success = Color.rgb(64, 160, 43),
                .warning = Color.rgb(223, 142, 29),
                .danger = Color.rgb(230, 69, 83),
                .border = Color.rgb(178, 181, 194),
            },
        };
    }

    /// Look up a color for a themed role.
    pub fn color(self: Theme, role: ThemeRole) Color {
        return switch (role) {
            .background => self.palette.background,
            .surface => self.palette.surface,
            .text => self.palette.text,
            .muted => self.palette.muted,
            .accent => self.palette.accent,
            .success => self.palette.success,
            .warning => self.palette.warning,
            .danger => self.palette.danger,
            .border => self.palette.border,
        };
    }

    /// Resolve a builtin theme by name (case-insensitive, dashes/underscores ignored).
    pub fn fromName(name: []const u8) ?Theme {
        var buf: [64]u8 = undefined;
        const normal = normalize(name, &buf) catch return null;

        if (std.mem.eql(u8, normal, "light")) return light();
        if (std.mem.eql(u8, normal, "dark")) return dark();
        if (std.mem.eql(u8, normal, "highcontrast")) return highContrast();
        if (std.mem.eql(u8, normal, "dracula")) return dracula();
        if (std.mem.eql(u8, normal, "nord")) return nord();
        if (std.mem.eql(u8, normal, "gruvbox")) return gruvbox();
        if (std.mem.eql(u8, normal, "solarizeddark") or std.mem.eql(u8, normal, "solarized")) return solarizedDark();
        if (std.mem.eql(u8, normal, "solarizedlight")) return solarizedLight();
        if (std.mem.eql(u8, normal, "monokai")) return monokai();
        if (std.mem.eql(u8, normal, "catppuccin") or std.mem.eql(u8, normal, "catppuccinmocha")) return catppuccinMocha();
        if (std.mem.eql(u8, normal, "catppuccinlatte")) return catppuccinLatte();

        return null;
    }
};

/// Stable role map for widget defaults.
pub const WidgetRoleMap = struct {
    pub const control_fg: ThemeRole = .text;
    pub const control_bg: ThemeRole = .surface;
    pub const control_focus_fg: ThemeRole = .background;
    pub const control_focus_bg: ThemeRole = .accent;
    pub const control_disabled_fg: ThemeRole = .muted;
    pub const control_disabled_bg: ThemeRole = .surface;
    pub const control_border: ThemeRole = .border;
    pub const selection_fg: ThemeRole = .background;
    pub const selection_bg: ThemeRole = .accent;
    pub const container_fg: ThemeRole = .text;
    pub const container_bg: ThemeRole = .background;
    pub const text_fg: ThemeRole = .text;
    pub const text_bg: ThemeRole = .background;
    pub const muted_fg: ThemeRole = .muted;
    pub const progress_fill: ThemeRole = .accent;
    pub const progress_bg: ThemeRole = .surface;
    pub const table_header_fg: ThemeRole = .background;
    pub const table_header_bg: ThemeRole = .accent;
    pub const table_grid: ThemeRole = .border;
    pub const tab_bar_fg: ThemeRole = .text;
    pub const tab_bar_bg: ThemeRole = .background;
    pub const tab_active_fg: ThemeRole = .background;
    pub const tab_active_bg: ThemeRole = .accent;
    pub const tab_inactive_fg: ThemeRole = .text;
    pub const tab_inactive_bg: ThemeRole = .surface;
    pub const scrollbar_thumb: ThemeRole = .muted;
    pub const modal_title_fg: ThemeRole = .background;
    pub const modal_title_bg: ThemeRole = .accent;
    pub const input_invalid_fg: ThemeRole = .background;
    pub const input_invalid_bg: ThemeRole = .danger;
};

pub const TextColors = struct {
    fg: Color,
    bg: Color,
    style: render.Style,
};

pub const SurfaceColors = struct {
    fg: Color,
    bg: Color,
    style: render.Style,
};

pub const ControlColors = struct {
    fg: Color,
    bg: Color,
    focused_fg: Color,
    focused_bg: Color,
    disabled_fg: Color,
    disabled_bg: Color,
    border: Color,
};

pub const InputColors = struct {
    fg: Color,
    bg: Color,
    focused_fg: Color,
    focused_bg: Color,
    disabled_fg: Color,
    disabled_bg: Color,
    invalid_fg: Color,
    invalid_bg: Color,
    placeholder_fg: Color,
    style: render.Style,
};

pub const SelectionColors = struct {
    fg: Color,
    bg: Color,
    focused_fg: Color,
    focused_bg: Color,
};

pub const ProgressColors = struct {
    fg: Color,
    bg: Color,
    fill_fg: Color,
    fill_bg: Color,
};

pub const ScrollbarColors = struct {
    fg: Color,
    bg: Color,
    thumb_fg: Color,
    focused_fg: Color,
    focused_bg: Color,
};

pub const TableColors = struct {
    fg: Color,
    bg: Color,
    header_fg: Color,
    header_bg: Color,
    selected_fg: Color,
    selected_bg: Color,
    focused_fg: Color,
    focused_bg: Color,
    grid_fg: Color,
};

pub const TabColors = struct {
    fg: Color,
    bg: Color,
    active_fg: Color,
    active_bg: Color,
    inactive_fg: Color,
    inactive_bg: Color,
    border_fg: Color,
};

pub const ModalColors = struct {
    title_fg: Color,
    title_bg: Color,
    fg: Color,
    bg: Color,
    border_fg: Color,
};

pub fn textColors(theme_value: Theme) TextColors {
    return .{
        .fg = theme_value.color(WidgetRoleMap.text_fg),
        .bg = theme_value.color(WidgetRoleMap.text_bg),
        .style = theme_value.style,
    };
}

pub fn surfaceColors(theme_value: Theme) SurfaceColors {
    return .{
        .fg = theme_value.color(WidgetRoleMap.control_fg),
        .bg = theme_value.color(WidgetRoleMap.control_bg),
        .style = theme_value.style,
    };
}

pub fn containerColors(theme_value: Theme) SurfaceColors {
    return .{
        .fg = theme_value.color(WidgetRoleMap.container_fg),
        .bg = theme_value.color(WidgetRoleMap.container_bg),
        .style = theme_value.style,
    };
}

pub fn controlColors(theme_value: Theme) ControlColors {
    return .{
        .fg = theme_value.color(WidgetRoleMap.control_fg),
        .bg = theme_value.color(WidgetRoleMap.control_bg),
        .focused_fg = theme_value.color(WidgetRoleMap.control_focus_fg),
        .focused_bg = theme_value.color(WidgetRoleMap.control_focus_bg),
        .disabled_fg = theme_value.color(WidgetRoleMap.control_disabled_fg),
        .disabled_bg = theme_value.color(WidgetRoleMap.control_disabled_bg),
        .border = theme_value.color(WidgetRoleMap.control_border),
    };
}

pub fn inputColors(theme_value: Theme) InputColors {
    const base = controlColors(theme_value);
    return .{
        .fg = base.fg,
        .bg = base.bg,
        .focused_fg = base.focused_fg,
        .focused_bg = base.focused_bg,
        .disabled_fg = base.disabled_fg,
        .disabled_bg = base.disabled_bg,
        .invalid_fg = theme_value.color(WidgetRoleMap.input_invalid_fg),
        .invalid_bg = theme_value.color(WidgetRoleMap.input_invalid_bg),
        .placeholder_fg = theme_value.color(WidgetRoleMap.muted_fg),
        .style = theme_value.style,
    };
}

pub fn selectionColors(theme_value: Theme) SelectionColors {
    const selected_bg = theme_value.color(WidgetRoleMap.selection_bg);
    return .{
        .fg = theme_value.color(WidgetRoleMap.selection_fg),
        .bg = selected_bg,
        .focused_fg = theme_value.color(WidgetRoleMap.selection_fg),
        .focused_bg = adjust(selected_bg, -12),
    };
}

pub fn progressColors(theme_value: Theme) ProgressColors {
    return .{
        .fg = theme_value.color(WidgetRoleMap.control_fg),
        .bg = theme_value.color(WidgetRoleMap.progress_bg),
        .fill_fg = theme_value.color(WidgetRoleMap.progress_fill),
        .fill_bg = theme_value.color(WidgetRoleMap.progress_fill),
    };
}

pub fn scrollbarColors(theme_value: Theme) ScrollbarColors {
    const base = controlColors(theme_value);
    return .{
        .fg = base.fg,
        .bg = base.bg,
        .thumb_fg = theme_value.color(WidgetRoleMap.scrollbar_thumb),
        .focused_fg = base.focused_fg,
        .focused_bg = base.focused_bg,
    };
}

pub fn tableColors(theme_value: Theme) TableColors {
    const surface = surfaceColors(theme_value);
    const selected = selectionColors(theme_value);
    return .{
        .fg = surface.fg,
        .bg = surface.bg,
        .header_fg = theme_value.color(WidgetRoleMap.table_header_fg),
        .header_bg = theme_value.color(WidgetRoleMap.table_header_bg),
        .selected_fg = selected.fg,
        .selected_bg = selected.bg,
        .focused_fg = selected.focused_fg,
        .focused_bg = selected.focused_bg,
        .grid_fg = theme_value.color(WidgetRoleMap.table_grid),
    };
}

pub fn tabColors(theme_value: Theme) TabColors {
    return .{
        .fg = theme_value.color(WidgetRoleMap.tab_bar_fg),
        .bg = theme_value.color(WidgetRoleMap.tab_bar_bg),
        .active_fg = theme_value.color(WidgetRoleMap.tab_active_fg),
        .active_bg = theme_value.color(WidgetRoleMap.tab_active_bg),
        .inactive_fg = theme_value.color(WidgetRoleMap.tab_inactive_fg),
        .inactive_bg = theme_value.color(WidgetRoleMap.tab_inactive_bg),
        .border_fg = theme_value.color(WidgetRoleMap.control_border),
    };
}

pub fn modalColors(theme_value: Theme) ModalColors {
    return .{
        .title_fg = theme_value.color(WidgetRoleMap.modal_title_fg),
        .title_bg = theme_value.color(WidgetRoleMap.modal_title_bg),
        .fg = theme_value.color(WidgetRoleMap.control_fg),
        .bg = theme_value.color(WidgetRoleMap.control_bg),
        .border_fg = theme_value.color(WidgetRoleMap.control_border),
    };
}

/// Slightly darken or lighten an RGB color for hover/pressed states.
pub fn adjust(color: Color, amount: i8) Color {
    return switch (color) {
        .named_color => color,
        .rgb_color => |rgb| blk: {
            const clamp = struct {
                fn apply(value: i16) u8 {
                    return @intCast(@max(@min(value, 255), 0));
                }
            };
            const delta: i16 = amount;
            break :blk Color.rgb(
                clamp.apply(@as(i16, rgb.r) + delta),
                clamp.apply(@as(i16, rgb.g) + delta),
                clamp.apply(@as(i16, rgb.b) + delta),
            );
        },
        .ansi_256 => |idx| blk: {
            const base = render.colorToRgb(Color.ansi256(idx));
            const clamp = struct {
                fn apply(value: i16) u8 {
                    return @intCast(@max(@min(value, 255), 0));
                }
            };
            const delta: i16 = amount;
            break :blk Color.rgb(
                clamp.apply(@as(i16, base.r) + delta),
                clamp.apply(@as(i16, base.g) + delta),
                clamp.apply(@as(i16, base.b) + delta),
            );
        },
    };
}

/// Load a theme from a simple config string. Supports `extends=<builtin>` and
/// role assignments like `background=#0a0e16` plus `style.bold=true`.
pub fn loadFromConfig(config: []const u8, fallback: Theme) !Theme {
    var theme_value = fallback;
    var line_it = std.mem.tokenizeAny(u8, config, "\r\n");

    while (line_it.next()) |raw_line| {
        const line = trimComment(raw_line);
        if (line.len == 0) continue;

        const eq_idx = std.mem.indexOfScalar(u8, line, '=') orelse return error.InvalidConfigLine;
        const key = std.mem.trim(u8, line[0..eq_idx], " \t");
        const value = std.mem.trim(u8, line[eq_idx + 1 ..], " \t");
        if (key.len == 0 or value.len == 0) continue;

        if (std.mem.eql(u8, key, "extends")) {
            if (Theme.fromName(value)) |base| {
                theme_value = base;
            }
            continue;
        }

        if (stringToRole(key)) |role| {
            if (parseColor(value)) |color| {
                applyRole(&theme_value, role, color);
            } else return error.InvalidColor;
            continue;
        }

        if (std.mem.startsWith(u8, key, "style.")) {
            const style_key = key[6..];
            if (parseBool(style_key, value)) |set| {
                applyStyleFlag(&theme_value.style, style_key, set);
            } else return error.InvalidStyleValue;
            continue;
        }
    }

    return theme_value;
}

/// Load a theme from a config file on disk, falling back when the file is missing.
pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8, fallback: Theme) !Theme {
    const file = std.fs.cwd().openFile(path, .{}) catch return fallback;
    defer file.close();

    const contents = file.readToEndAlloc(allocator, 16 * 1024) catch return fallback;
    defer allocator.free(contents);

    return loadFromConfig(contents, fallback) catch fallback;
}

fn trimComment(line: []const u8) []const u8 {
    var idx: usize = 0;
    while (idx < line.len) : (idx += 1) {
        if (line[idx] != '#') continue;

        // Skip over hex color literals (e.g. "#aabbcc") so they aren't treated as comments.
        if (idx + 7 <= line.len and isHexColorLiteral(line[idx .. idx + 7])) {
            idx += 6; // advance past the color sequence
            continue;
        }

        return std.mem.trim(u8, line[0..idx], " \t");
    }

    return std.mem.trim(u8, line, " \t");
}

fn isHexColorLiteral(slice: []const u8) bool {
    if (slice.len < 7 or slice[0] != '#') return false;
    for (slice[1..7]) |ch| {
        if (!isHexChar(ch)) return false;
    }
    return true;
}

fn isHexChar(ch: u8) bool {
    return (ch >= '0' and ch <= '9') or (ch >= 'a' and ch <= 'f') or (ch >= 'A' and ch <= 'F');
}

fn stringToRole(raw: []const u8) ?ThemeRole {
    var buf: [32]u8 = undefined;
    var len: usize = 0;
    for (raw) |c| {
        if (len >= buf.len) return null;
        buf[len] = std.ascii.toLower(c);
        if (buf[len] == '-') buf[len] = '_';
        len += 1;
    }
    return std.meta.stringToEnum(ThemeRole, buf[0..len]);
}

fn parseColor(text: []const u8) ?Color {
    if (text.len == 0) return null;
    if (text[0] == '#') {
        if (text.len != 7) return null;
        const r = std.fmt.parseInt(u8, text[1..3], 16) catch return null;
        const g = std.fmt.parseInt(u8, text[3..5], 16) catch return null;
        const b = std.fmt.parseInt(u8, text[5..7], 16) catch return null;
        return Color.rgb(r, g, b);
    }

    if (Theme.fromName(text)) |t| {
        return t.palette.background;
    }

    if (std.meta.stringToEnum(NamedColor, text)) |named| {
        return Color.named(named);
    }
    return null;
}

fn parseBool(key: []const u8, value: []const u8) ?bool {
    _ = key;
    if (std.mem.eql(u8, value, "true")) return true;
    if (std.mem.eql(u8, value, "false")) return false;
    return null;
}

fn applyRole(theme_value: *Theme, role: ThemeRole, color: Color) void {
    switch (role) {
        .background => theme_value.palette.background = color,
        .surface => theme_value.palette.surface = color,
        .text => theme_value.palette.text = color,
        .muted => theme_value.palette.muted = color,
        .accent => theme_value.palette.accent = color,
        .success => theme_value.palette.success = color,
        .warning => theme_value.palette.warning = color,
        .danger => theme_value.palette.danger = color,
        .border => theme_value.palette.border = color,
    }
}

fn applyStyleFlag(style: *render.Style, key: []const u8, value: bool) void {
    if (std.mem.eql(u8, key, "bold")) style.bold = value;
    if (std.mem.eql(u8, key, "italic")) style.italic = value;
    if (std.mem.eql(u8, key, "underline")) style.underline = value;
    if (std.mem.eql(u8, key, "blink")) style.blink = value;
    if (std.mem.eql(u8, key, "reverse")) style.reverse = value;
    if (std.mem.eql(u8, key, "strikethrough")) style.strikethrough = value;
}

fn normalize(name: []const u8, buf: *[64]u8) ![]const u8 {
    if (name.len > buf.len) return error.NameTooLong;
    var out_len: usize = 0;
    for (name) |c| {
        const lowered = std.ascii.toLower(c);
        if (std.ascii.isAlphanumeric(lowered)) {
            buf[out_len] = lowered;
            out_len += 1;
        }
    }
    return buf[0..out_len];
}

fn themeFromNameOrDefault(name: []const u8) Theme {
    return Theme.fromName(name) orelse Theme.dark();
}

test "builtin themes resolve by name" {
    try std.testing.expect(themeFromNameOrDefault("dark").color(.background).rgb_color.r == Theme.dark().color(.background).rgb_color.r);
    try std.testing.expect(themeFromNameOrDefault("Solarized-Light").color(.text).rgb_color.b == Theme.solarizedLight().color(.text).rgb_color.b);
    try std.testing.expect(themeFromNameOrDefault("catppuccin").color(.border).rgb_color.g == Theme.catppuccinMocha().color(.border).rgb_color.g);
    try std.testing.expect(themeFromNameOrDefault("monokai").color(.accent).rgb_color.g == Theme.monokai().color(.accent).rgb_color.g);
}

test "loadFromConfig overrides palette and style" {
    const config =
        "extends=dark\n" ++
        "background=#010101\n" ++
        "accent=#ff00aa\n" ++
        "style.bold=true\n" ++
        "style.underline=true\n" ++
        "# comment line ignored\n";

    const theme_value = try loadFromConfig(config, Theme.light());
    try std.testing.expectEqual(@as(u8, 1), theme_value.palette.background.rgb_color.r);
    try std.testing.expectEqual(@as(u8, 170), theme_value.palette.accent.rgb_color.b);
    try std.testing.expect(theme_value.style.bold);
    try std.testing.expect(theme_value.style.underline);
}
