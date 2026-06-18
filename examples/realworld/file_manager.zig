// Real-world demo: dual-pane file manager with previews.

const std = @import("std");
const zit = @import("zit");
const render = zit.render;
const layout = zit.layout;
const widget = zit.widget;
const interactive = @import("interactive_snapshot.zig");
const style = @import("realworld_style.zig");

const FileRow = struct {
    name: []const u8,
    kind: []const u8,
    size: []const u8,
    modified: []const u8,
    selected: bool = false,
};

fn drawPath(renderer: *render.Renderer, x: u16, y: u16, palette: style.Palette) void {
    const parts = [_][]const u8{ "home", "palash", "Learning", "zig", "zit" };
    var cursor = x;
    for (parts, 0..) |part, idx| {
        const bg = if (idx == parts.len - 1) palette.accent else palette.surface_alt;
        const fg = if (idx == parts.len - 1) palette.accent_text else palette.text;
        const width: u16 = @intCast(part.len + 4);
        renderer.fillRect(cursor, y, width, 1, ' ', fg, bg, render.Style{ .bold = true });
        renderer.drawSmartStr(cursor + 2, y, part, fg, bg, render.Style{ .bold = true });
        cursor += width;
        if (idx + 1 < parts.len) {
            renderer.drawSmartStr(cursor, y, "/", palette.muted, palette.surface, render.Style{ .bold = true });
            cursor += 2;
        }
    }
}

fn drawFileRow(renderer: *render.Renderer, rect: layout.Rect, row: FileRow, palette: style.Palette) void {
    const bg = if (row.selected) render.Color.rgb(16, 51, 34) else palette.surface;
    const name_fg = if (std.mem.eql(u8, row.kind, "dir")) palette.accent else palette.text;
    renderer.fillRect(rect.x, rect.y, rect.width, 1, ' ', palette.text, bg, render.Style{});
    renderer.drawSmartStr(rect.x + 1, rect.y, row.name, name_fg, bg, render.Style{ .bold = row.selected });
    if (rect.width > 38) renderer.drawSmartStr(rect.x + 34, rect.y, row.kind, palette.muted, bg, render.Style{});
    if (rect.width > 50) renderer.drawSmartStr(rect.x + 46, rect.y, row.size, palette.text, bg, render.Style{});
    if (rect.width > 64) renderer.drawSmartStr(rect.x + 58, rect.y, row.modified, palette.muted, bg, render.Style{});
}

/// File manager screen rendered interactively by default and as a deterministic snapshot with --snapshot.
pub fn main(init: std.process.Init) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var mock = try zit.testing.MockTerminal.init(allocator, 120, 35);
    defer mock.deinit();

    const palette = style.filePalette();
    const renderer = &mock.renderer;
    renderer.back.clear();
    const content = style.drawChrome(renderer, palette, "zit file manager", "ranger-style panes / q quits");

    drawPath(renderer, content.x, content.y, palette);
    renderer.drawSmartStr(content.x, content.y + 2, "Tab focus  Enter open  / search  Space mark  m actions", palette.muted, palette.bg, render.Style{ .bold = true });

    const top_offset: u16 = 4;
    const left = layout.Rect.init(content.x, content.y + top_offset, 28, content.height - top_offset);
    const center = layout.Rect.init(content.x + 30, content.y + top_offset, 52, content.height - top_offset);
    const right = layout.Rect.init(content.x + 84, content.y + top_offset, content.width - 84, content.height - top_offset);

    style.drawPanel(renderer, left, palette, "Places", palette.accent);
    style.drawPanel(renderer, center, palette, "Directory", palette.accent);
    style.drawPanel(renderer, right, palette, "Preview", palette.success);

    var places = try widget.List.init(allocator);
    defer places.deinit();
    places.border = .none;
    places.bg = palette.surface;
    places.fg = palette.text;
    places.selected_bg = render.Color.rgb(16, 51, 34);
    places.selected_fg = palette.text;
    try places.addItem("workspace");
    try places.addItem("examples");
    try places.addItem("src");
    try places.addItem("docs");
    try places.addItem("assets");
    places.setSelectedIndex(1);
    try places.widget.layout(layout.Rect.init(left.x + 2, left.y + 3, left.width - 4, left.height - 5));
    places.widget.markDirty();
    try places.widget.draw(renderer);

    const rows = [_]FileRow{
        .{ .name = "../", .kind = "dir", .size = "-", .modified = "now" },
        .{ .name = "realworld/", .kind = "dir", .size = "-", .modified = "now" },
        .{ .name = "widget_examples/", .kind = "dir", .size = "-", .modified = "now" },
        .{ .name = "file_manager.zig", .kind = "file", .size = "9 KB", .modified = "2m", .selected = true },
        .{ .name = "htop_clone.zig", .kind = "file", .size = "8 KB", .modified = "2m" },
        .{ .name = "dashboard_demo.zig", .kind = "file", .size = "7 KB", .modified = "5m" },
        .{ .name = "widget_gallery.zig", .kind = "file", .size = "16 KB", .modified = "8m" },
        .{ .name = "text_editor.zig", .kind = "file", .size = "5 KB", .modified = "12m" },
    };
    renderer.fillRect(center.x + 2, center.y + 3, center.width - 4, 1, ' ', palette.accent, palette.surface_alt, render.Style{ .bold = true });
    renderer.drawSmartStr(center.x + 3, center.y + 3, "NAME", palette.accent, palette.surface_alt, render.Style{ .bold = true });
    renderer.drawSmartStr(center.x + 28, center.y + 3, "TYPE", palette.accent, palette.surface_alt, render.Style{ .bold = true });
    var y = center.y + 5;
    for (rows) |row| {
        drawFileRow(renderer, layout.Rect.init(center.x + 2, y, center.width - 4, 1), row, palette);
        y += 2;
    }

    renderer.drawSmartStr(right.x + 2, right.y + 3, "file_manager.zig", palette.accent, palette.surface, render.Style{ .bold = true });
    renderer.drawSmartStr(right.x + 2, right.y + 5, "dual-pane file manager", palette.text, palette.surface, render.Style{});
    renderer.drawSmartStr(right.x + 2, right.y + 7, "widgets used", palette.muted, palette.surface, render.Style{ .bold = true });
    renderer.drawSmartStr(right.x + 4, right.y + 9, "Tree/List focus", palette.text, palette.surface, render.Style{});
    renderer.drawSmartStr(right.x + 4, right.y + 10, "Context menu", palette.text, palette.surface, render.Style{});
    renderer.drawSmartStr(right.x + 4, right.y + 11, "Typeahead search", palette.text, palette.surface, render.Style{});
    renderer.drawSmartStr(right.x + 4, right.y + 12, "Resize-safe layout", palette.text, palette.surface, render.Style{});
    renderer.fillRect(right.x + 2, right.y + 15, right.width - 4, 1, ' ', palette.accent_text, palette.accent, render.Style{ .bold = true });
    renderer.drawSmartStr(right.x + 3, right.y + 15, "ready", palette.accent_text, palette.accent, render.Style{ .bold = true });

    var table = try widget.Table.init(allocator);
    defer table.deinit();
    try table.addColumn("MARKED", 8, false);
    try table.addColumn("ACTION", 14, false);
    try table.addColumn("TARGET", 18, true);
    try table.addRow(&.{ "[x]", "preview", "file_manager.zig" });
    try table.addRow(&.{ "[ ]", "copy path", "examples/" });
    try table.addRow(&.{ "[ ]", "open", "README.md" });
    table.show_grid = false;
    table.setBorder(.none);
    table.fg = palette.text;
    table.bg = palette.surface;
    table.header_fg = palette.accent;
    table.header_bg = palette.surface_alt;
    table.selected_bg = render.Color.rgb(16, 51, 34);
    table.selected_fg = palette.text;
    table.selected_row = 0;
    try table.widget.layout(layout.Rect.init(right.x + 2, right.y + 18, right.width - 4, 6));
    table.widget.markDirty();
    try table.widget.draw(renderer);

    style.drawStatus(renderer, palette, "8 items | selected examples/realworld/file_manager.zig | F5 refresh | F10 quit | q quit");

    var snap = try mock.snapshot(allocator);
    defer snap.deinit(allocator);
    const frame = try mock.captureOutput();
    try interactive.finishFrames(init, allocator, "file-manager", snap.text(), frame);
}
