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
};

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
