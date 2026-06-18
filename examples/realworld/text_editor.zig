// Real-world demo: editor workspace with syntax, outline, palette, and status.

const std = @import("std");
const zit = @import("zit");
const render = zit.render;
const layout = zit.layout;
const widget = zit.widget;
const interactive = @import("interactive_snapshot.zig");
const style = @import("realworld_style.zig");

fn editorPalette() style.Palette {
    var palette = style.monitorPalette();
    palette.accent = render.Color.rgb(245, 158, 11);
    palette.accent_text = render.Color.rgb(24, 18, 10);
    palette.success = render.Color.rgb(134, 239, 172);
    return palette;
}

fn drawTab(renderer: *render.Renderer, x: u16, y: u16, label: []const u8, active: bool, palette: style.Palette) void {
    const width: u16 = @intCast(@min(label.len + 4, 24));
    const fg = if (active) palette.accent_text else palette.muted;
    const bg = if (active) palette.accent else palette.surface_alt;
    renderer.fillRect(x, y, width, 1, ' ', fg, bg, render.Style{});
    renderer.drawSmartStr(x + 2, y, label, fg, bg, render.Style{ .bold = active });
}

fn drawFileRow(renderer: *render.Renderer, x: u16, y: u16, width: u16, label: []const u8, active: bool, palette: style.Palette) void {
    const bg = if (active) render.Color.rgb(33, 44, 63) else palette.surface;
    const fg = if (active) palette.accent else palette.muted;
    renderer.fillRect(x, y, width, 1, ' ', fg, bg, render.Style{});
    renderer.drawSmartStr(x + 1, y, label, fg, bg, render.Style{ .bold = active });
}

/// Minimal text editor screen with status bar and command palette preview.
pub fn main(init: std.process.Init) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var mock = try zit.testing.MockTerminal.init(allocator, 100, 34);
    defer mock.deinit();

    const palette = editorPalette();
    const renderer = &mock.renderer;
    renderer.back.clear();
    const content = style.drawChrome(renderer, palette, "zit editor", "workspace / q quits");

    const sidebar = layout.Rect.init(content.x, content.y, 24, content.height - 2);
    const editor = layout.Rect.init(content.x + 26, content.y, 48, content.height - 2);
    const inspector = layout.Rect.init(content.x + 76, content.y, content.width - 76, content.height - 2);
    const terminal = layout.Rect.init(content.x, content.y + content.height - 1, content.width, 1);

    style.drawPanel(renderer, sidebar, palette, "Explorer", palette.accent);
    drawFileRow(renderer, sidebar.x + 2, sidebar.y + 3, sidebar.width - 4, "▾ src", false, palette);
    drawFileRow(renderer, sidebar.x + 2, sidebar.y + 4, sidebar.width - 4, "  ▾ widget", false, palette);
    drawFileRow(renderer, sidebar.x + 2, sidebar.y + 5, sidebar.width - 4, "    widget.zig", true, palette);
    drawFileRow(renderer, sidebar.x + 2, sidebar.y + 6, sidebar.width - 4, "    theme.zig", false, palette);
    drawFileRow(renderer, sidebar.x + 2, sidebar.y + 7, sidebar.width - 4, "  ▾ render", false, palette);
    drawFileRow(renderer, sidebar.x + 2, sidebar.y + 8, sidebar.width - 4, "    render.zig", false, palette);
    drawFileRow(renderer, sidebar.x + 2, sidebar.y + 9, sidebar.width - 4, "examples/", false, palette);
    renderer.drawSmartStr(sidebar.x + 3, sidebar.y + sidebar.height - 4, "git: main", palette.success, palette.surface, render.Style{ .bold = true });
    renderer.drawSmartStr(sidebar.x + 3, sidebar.y + sidebar.height - 3, "diagnostics: 0", palette.muted, palette.surface, render.Style{});

    style.drawPanel(renderer, editor, palette, "Editor", palette.accent);
    drawTab(renderer, editor.x + 2, editor.y + 1, "widget.zig", true, palette);
    drawTab(renderer, editor.x + 16, editor.y + 1, "theme.zig", false, palette);
    drawTab(renderer, editor.x + 29, editor.y + 1, "render.zig", false, palette);

    var highlighter = try widget.SyntaxHighlighter.init(allocator);
    defer highlighter.deinit();
    highlighter.border = .none;
    highlighter.setLanguage(.zig);
    highlighter.setColors(
        palette.text,
        palette.surface,
        palette.accent,
        palette.warning,
        palette.muted,
        render.Color.rgb(244, 114, 182),
    );
    try highlighter.setCode(
        \\pub fn draw(self: *Widget, renderer: *Renderer) !void {
        \\    if (!self.visible) return;
        \\    const rect = self.rect;
        \\    try self.layout(rect);
        \\    renderer.pushClip(rect);
        \\    defer renderer.popClip();
        \\    try self.vtable.draw(self.ptr, renderer);
        \\}
        \\
        \\// Press : to open commands
    );
    try highlighter.widget.layout(layout.Rect.init(editor.x + 7, editor.y + 4, editor.width - 9, editor.height - 8));
    try highlighter.widget.draw(renderer);

    var line_no: u16 = 0;
    while (line_no < 10) : (line_no += 1) {
        var buf: [8]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, "{d:>2}", .{line_no + 37}) catch "  ";
        renderer.drawSmartStr(editor.x + 3, editor.y + 4 + line_no, text, palette.muted, palette.surface, render.Style{});
    }
    renderer.drawChar(editor.x + 7, editor.y + 12, '▌', palette.accent, palette.surface, render.Style{ .bold = true });

    style.drawPanel(renderer, inspector, palette, "Outline", palette.success);
    renderer.drawSmartStr(inspector.x + 3, inspector.y + 3, "Symbols", palette.accent, palette.surface, render.Style{ .bold = true });
    renderer.drawSmartStr(inspector.x + 3, inspector.y + 5, "fn draw", palette.text, palette.surface, render.Style{ .bold = true });
    renderer.drawSmartStr(inspector.x + 3, inspector.y + 6, "fn layout", palette.muted, palette.surface, render.Style{});
    renderer.drawSmartStr(inspector.x + 3, inspector.y + 7, "fn handleEvent", palette.muted, palette.surface, render.Style{});
    renderer.drawSmartStr(inspector.x + 3, inspector.y + 9, "Minimap", palette.accent, palette.surface, render.Style{ .bold = true });
    var mini_y: u16 = 0;
    while (mini_y < 8) : (mini_y += 1) {
        const shade = if (mini_y == 4) palette.accent else palette.border;
        renderer.fillRect(inspector.x + 3, inspector.y + 11 + mini_y, inspector.width - 6, 1, '▁', shade, palette.surface, render.Style{});
    }
    renderer.drawSmartStr(inspector.x + 3, inspector.y + inspector.height - 3, "tests: 412 passed", palette.success, palette.surface, render.Style{ .bold = true });

    var command_palette = try widget.CommandPalette.init(allocator, &[_][]const u8{
        "Save file",
        "Format document",
        "Close buffer",
        "Run release-check",
        "Search symbol",
        "Replace in file",
    });
    defer command_palette.deinit();
    command_palette.setQuery(":run");
    command_palette.selected = 3;
    const palette_rect = layout.Rect.init(25, 9, 54, 9);
    renderer.fillRect(
        palette_rect.x,
        palette_rect.y,
        palette_rect.width,
        palette_rect.height,
        ' ',
        palette.text,
        render.Color.rgb(3, 7, 18),
        render.Style{},
    );
    try command_palette.widget.layout(palette_rect);
    try command_palette.widget.draw(renderer);

    renderer.fillRect(terminal.x, terminal.y, terminal.width, terminal.height, ' ', palette.accent_text, palette.accent, render.Style{});
    renderer.drawSmartStr(terminal.x + 2, terminal.y, "widget.zig  UTF-8  LF", palette.accent_text, palette.accent, render.Style{ .bold = true });
    renderer.drawSmartStr(terminal.x + 38, terminal.y, "INSERT", palette.accent_text, palette.accent, render.Style{ .bold = true });
    renderer.drawSmartStr(terminal.x + terminal.width - 18, terminal.y, "Ln 42, Col 3", palette.accent_text, palette.accent, render.Style{ .bold = true });
    style.drawStatus(renderer, palette, "diagnostics: clean | palette open | text-editor | q quit");

    var snap = try mock.snapshot(allocator);
    defer snap.deinit(allocator);
    const frame = try mock.captureOutput();
    try interactive.finishFrames(init, allocator, "text-editor", snap.text(), frame);
}
