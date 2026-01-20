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
                .background = Color.named(NamedColor.white),
                .surface = Color.named(NamedColor.bright_white),
                .text = Color.named(NamedColor.black),
                .muted = Color.named(NamedColor.bright_black),
                .accent = Color.named(NamedColor.blue),
                .success = Color.named(NamedColor.green),
                .warning = Color.named(NamedColor.yellow),
                .danger = Color.named(NamedColor.red),
                .border = Color.named(NamedColor.black),
            },
        };
    }

    /// Standard dark theme.
    pub fn dark() Theme {
        return Theme{
            .palette = Palette{
                .background = Color.named(NamedColor.black),
                .surface = Color.named(NamedColor.bright_black),
                .text = Color.named(NamedColor.white),
                .muted = Color.named(NamedColor.bright_black),
                .accent = Color.named(NamedColor.cyan),
                .success = Color.named(NamedColor.green),
                .warning = Color.named(NamedColor.yellow),
                .danger = Color.named(NamedColor.red),
                .border = Color.named(NamedColor.bright_black),
            },
        };
    }

    /// High contrast theme for accessibility.
    pub fn highContrast() Theme {
        return Theme{
            .palette = Palette{
                .background = Color.named(NamedColor.black),
                .surface = Color.named(NamedColor.black),
                .text = Color.named(NamedColor.bright_white),
                .muted = Color.named(NamedColor.white),
                .accent = Color.named(NamedColor.bright_cyan),
                .success = Color.named(NamedColor.bright_green),
                .warning = Color.named(NamedColor.bright_yellow),
                .danger = Color.named(NamedColor.bright_red),
                .border = Color.named(NamedColor.white),
            },
            .style = render.Style{
                .bold = true,
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
    };
}
