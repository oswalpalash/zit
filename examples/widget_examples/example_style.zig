const zit = @import("zit");
const render = zit.render;
const layout = zit.layout;
const theme = zit.widget.theme;

pub const Palette = struct {
    bg: render.Color,
    surface: render.Color,
    surface_alt: render.Color,
    border: render.Color,
    text: render.Color,
    muted: render.Color,
    accent: render.Color,
    accent_text: render.Color,
    success: render.Color,
    warning: render.Color,
    danger: render.Color,
};

pub fn monitorPalette() Palette {
    return .{
        .bg = render.Color.rgb(5, 7, 11),
        .surface = render.Color.rgb(11, 17, 28),
        .surface_alt = render.Color.rgb(17, 26, 42),
        .border = render.Color.rgb(35, 48, 71),
        .text = render.Color.rgb(232, 240, 251),
        .muted = render.Color.rgb(143, 163, 189),
        .accent = render.Color.rgb(125, 211, 252),
        .accent_text = render.Color.rgb(6, 16, 24),
        .success = render.Color.rgb(52, 211, 153),
        .warning = render.Color.rgb(251, 191, 36),
        .danger = render.Color.rgb(251, 113, 133),
    };
}

pub fn filePalette() Palette {
    var palette = monitorPalette();
    palette.accent = render.Color.rgb(134, 239, 172);
    palette.accent_text = render.Color.rgb(5, 24, 15);
    palette.success = render.Color.rgb(134, 239, 172);
    return palette;
}

pub fn showcasePalette() Palette {
    var palette = monitorPalette();
    palette.accent = render.Color.rgb(245, 158, 11);
    palette.accent_text = render.Color.rgb(24, 18, 10);
    palette.success = render.Color.rgb(134, 239, 172);
    return palette;
}

pub fn asTheme(palette: Palette) theme.Theme {
    return .{
        .palette = .{
            .background = palette.bg,
            .surface = palette.surface,
            .text = palette.text,
            .muted = palette.muted,
            .accent = palette.accent,
            .success = palette.success,
            .warning = palette.warning,
            .danger = palette.danger,
            .border = palette.border,
        },
    };
}

pub fn drawChrome(renderer: *render.Renderer, palette: Palette, title: []const u8, subtitle: []const u8) layout.Rect {
    const width = renderer.back.width;
    const height = renderer.back.height;
    renderer.fillRect(0, 0, width, height, ' ', palette.text, palette.bg, render.Style{});
    if (width == 0 or height == 0) return layout.Rect.init(0, 0, 0, 0);

    renderer.drawBox(0, 0, width, height, .rounded, palette.border, palette.bg, render.Style{});
    if (width > 2 and height > 3) {
        renderer.fillRect(1, 1, width - 2, 2, ' ', palette.accent_text, palette.accent, render.Style{});
        renderer.drawStr(3, 1, "● ● ●", palette.accent_text, palette.accent, render.Style{});
        renderer.drawSmartStr(11, 1, title, palette.accent_text, palette.accent, render.Style{ .bold = true });
        if (width > 48) {
            const subtitle_x: u16 = if (subtitle.len + 4 < width) @intCast(width - subtitle.len - 4) else 12;
            renderer.drawSmartStr(subtitle_x, 1, subtitle, palette.accent_text, palette.accent, render.Style{});
        }
    }

    return if (width > 4 and height > 6)
        layout.Rect.init(2, 4, width - 4, height - 6)
    else
        layout.Rect.init(1, 3, if (width > 2) width - 2 else width, if (height > 4) height - 4 else 0);
}

pub fn drawPanel(renderer: *render.Renderer, rect: layout.Rect, palette: Palette, title: []const u8, accent: render.Color) void {
    if (rect.width == 0 or rect.height == 0) return;
    renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', palette.text, palette.surface, render.Style{});
    renderer.drawBox(rect.x, rect.y, rect.width, rect.height, .rounded, palette.border, palette.surface, render.Style{});
    if (rect.width > 2 and rect.height > 2) {
        renderer.fillRect(rect.x + 1, rect.y + 1, rect.width - 2, 1, ' ', palette.text, palette.surface_alt, render.Style{});
        renderer.drawChar(rect.x + 2, rect.y + 1, '■', accent, palette.surface_alt, render.Style{ .bold = true });
        renderer.drawSmartStr(rect.x + 4, rect.y + 1, title, palette.text, palette.surface_alt, render.Style{ .bold = true });
    }
}

pub fn drawStatus(renderer: *render.Renderer, palette: Palette, text: []const u8) void {
    if (renderer.back.height < 2 or renderer.back.width < 3) return;
    const y = renderer.back.height - 2;
    renderer.fillRect(1, y, renderer.back.width - 2, 1, ' ', palette.accent_text, palette.accent, render.Style{});
    renderer.drawSmartStr(3, y, text, palette.accent_text, palette.accent, render.Style{ .bold = true });
}

pub fn drawMeter(renderer: *render.Renderer, x: u16, y: u16, width: u16, label: []const u8, value: f32, palette: Palette, fill: render.Color) void {
    if (width < 6) return;
    renderer.drawSmartStr(x, y, label, palette.muted, palette.surface, render.Style{ .bold = true });
    const bar_y = y + 1;
    const filled: u16 = @intFromFloat(@as(f32, @floatFromInt(width)) * @max(@as(f32, 0), @min(@as(f32, 1), value)));
    renderer.fillRect(x, bar_y, width, 1, '░', palette.border, palette.surface, render.Style{});
    if (filled > 0) renderer.fillRect(x, bar_y, filled, 1, '█', fill, palette.surface, render.Style{ .bold = true });
}

pub fn drawBadge(renderer: *render.Renderer, x: u16, y: u16, label: []const u8, fg: render.Color, bg: render.Color) void {
    const width: u16 = @intCast(label.len + 4);
    renderer.fillRect(x, y, width, 1, ' ', fg, bg, render.Style{});
    renderer.drawSmartStr(x + 2, y, label, fg, bg, render.Style{ .bold = true });
}
