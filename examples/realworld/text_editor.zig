// Real-world demo: minimal text editor with cursor movement and save prompts.

const std = @import("std");
const zit = @import("zit");

/// Minimal text editor screen with status bar and command palette preview.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var mock = try zit.testing.MockTerminal.init(allocator, 80, 20);
    defer mock.deinit();

    // Paint editor background and syntax-highlighted text.
    mock.renderer.fillRect(0, 0, 80, 16, ' ', zit.render.Color.named(.bright_white), zit.render.Color.named(.black), zit.render.Style{});
    var highlighter = try zit.widget.SyntaxHighlighter.init(allocator);
    defer highlighter.deinit();
    highlighter.border = .none;
    highlighter.setLanguage(.zig);
    highlighter.setColors(
        zit.render.Color.named(.bright_white),
        zit.render.Color.named(.black),
        zit.render.Color.named(.bright_cyan),
        zit.render.Color.named(.bright_yellow),
        zit.render.Color.named(.bright_black),
        zit.render.Color.named(.magenta),
    );
    try highlighter.setCode(
        \\fn main() !void {
        \\    var app = try zit.quickstart.renderText("Hello", .{});
        \\    _ = app;
        \\}
        \\
        \\// Press : to open the palette
    );
    try highlighter.widget.layout(zit.layout.Rect.init(2, 1, 76, 14));
    try highlighter.widget.draw(&mock.renderer);

    var palette = try zit.widget.CommandPalette.init(allocator, &[_][]const u8{
        "Save file",
        "Close buffer",
        "Toggle minimap",
        "Search symbol",
        "Replace in file",
    });
    defer palette.deinit();
    palette.setQuery(":");
    palette.selected = 3;
    const palette_rect = zit.layout.Rect.init(10, 7, 60, 8);
    mock.renderer.fillRect(
        palette_rect.x,
        palette_rect.y,
        palette_rect.width,
        palette_rect.height,
        ' ',
        zit.render.Color.named(.bright_white),
        zit.render.Color.named(.black),
        zit.render.Style{},
    );
    try palette.widget.layout(palette_rect);
    try palette.widget.draw(&mock.renderer);

    var status = try zit.widget.StatusBar.init(allocator);
    defer status.deinit();
    status.setSegments("main.zig  UTF-8  LF", "INSERT", "Ln 42, Col 3");
    try status.widget.layout(zit.layout.Rect.init(0, 18, 80, 1));
    try status.widget.draw(&mock.renderer);

    var snap = try mock.snapshot(allocator);
    defer snap.deinit(allocator);
    std.debug.print("{s}", .{snap.text()});
}
