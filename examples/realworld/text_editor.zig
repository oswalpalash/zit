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

    // Paint editor background and a few lines of sample text.
    mock.renderer.fillRect(0, 0, 80, 16, ' ', zit.render.Color.named(.bright_white), zit.render.Color.named(.black), zit.render.Style{});
    const lines = [_][]const u8{
        "fn main() !void {",
        "    var app = try zit.quickstart.renderText(\"Hello\", .{});",
        "    _ = app;",
        "}",
        "",
        "// Press : to open the palette",
    };
    for (lines, 0..) |line, idx| {
        mock.renderer.drawStr(2, @intCast(idx + 1), line, zit.render.Color.named(.bright_white), zit.render.Color.named(.black), zit.render.Style{});
    }

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
    try palette.widget.layout(zit.layout.Rect.init(10, 6, 60, 8));
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
