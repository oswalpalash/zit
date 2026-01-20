const std = @import("std");
const zit = @import("zit");

/// A static file manager screen with breadcrumbs, toolbar, and directory table.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var mock = try zit.testing.MockTerminal.init(allocator, 80, 22);
    defer mock.deinit();

    var crumbs = try zit.widget.Breadcrumbs.init(allocator, &[_][]const u8{ "home", "dev", "projects", "zit" });
    defer crumbs.deinit();
    try crumbs.widget.layout(zit.layout.Rect.init(1, 0, 60, 1));
    try crumbs.widget.draw(&mock.renderer);

    var toolbar = try zit.widget.Toolbar.init(allocator, &[_][]const u8{ "Open", "New Folder", "Delete", "Refresh" });
    defer toolbar.deinit();
    toolbar.setActive(1);
    try toolbar.widget.layout(zit.layout.Rect.init(0, 1, 80, 1));
    try toolbar.widget.draw(&mock.renderer);

    var table = try zit.widget.Table.init(allocator);
    defer table.deinit();
    try table.addColumn("Name", 28, true);
    try table.addColumn("Type", 10, true);
    try table.addColumn("Size", 8, true);
    try table.addColumn("Modified", 20, true);
    const rows = [_][4][]const u8{
        .{ "src", "dir", "-", "2024-04-02 10:12" },
        .{ "examples", "dir", "-", "2024-04-01 08:31" },
        .{ "README.md", "file", "12 KB", "2024-03-30 18:04" },
        .{ "build.zig", "file", "6 KB", "2024-03-30 17:59" },
        .{ "zig-out", "dir", "-", "2024-03-29 14:20" },
    };
    for (rows) |row| try table.addRow(&row);
    table.selected_row = 2;
    table.border = .double;
    try table.widget.layout(zit.layout.Rect.init(1, 3, 78, 15));
    try table.widget.draw(&mock.renderer);

    var status = try zit.widget.StatusBar.init(allocator);
    defer status.deinit();
    status.setSegments("5 items", "file manager", "F5 refresh  F10 quit");
    try status.widget.layout(zit.layout.Rect.init(0, 20, 80, 1));
    try status.widget.draw(&mock.renderer);

    var snap = try mock.snapshot(allocator);
    defer snap.deinit(allocator);
    std.debug.print("{s}", .{snap.text()});
}
