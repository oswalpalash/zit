// Real-world demo: htop-inspired process monitor using tables and sparklines.

const std = @import("std");
const zit = @import("zit");
const render = zit.render;
const layout = zit.layout;
const widget = zit.widget;
const interactive = @import("interactive_snapshot.zig");
const style = @import("realworld_style.zig");

const Process = struct {
    pid: []const u8,
    user: []const u8,
    pri: []const u8,
    cpu: []const u8,
    mem: []const u8,
    time: []const u8,
    command: []const u8,
    hot: bool = false,
};

fn drawCore(renderer: *render.Renderer, x: u16, y: u16, label: []const u8, value: f32, palette: style.Palette, fill: render.Color) void {
    renderer.drawSmartStr(x, y, label, palette.muted, palette.surface, render.Style{ .bold = true });
    const width: u16 = 18;
    const filled: u16 = @intFromFloat(@as(f32, @floatFromInt(width)) * std.math.clamp(value, 0.0, 1.0));
    renderer.fillRect(x + 5, y, width, 1, ' ', palette.border, render.Color.rgb(19, 27, 43), render.Style{});
    if (filled > 0) renderer.fillRect(x + 5, y, filled, 1, ' ', palette.text, fill, render.Style{ .bold = true });
    var buf: [8]u8 = undefined;
    const pct = std.fmt.bufPrint(&buf, "{d:>3}%", .{@as(u8, @intFromFloat(value * 100.0))}) catch " --%";
    renderer.drawSmartStr(x + 25, y, pct, palette.text, palette.surface, render.Style{ .bold = true });
}

fn drawStat(renderer: *render.Renderer, x: u16, y: u16, label: []const u8, value: []const u8, palette: style.Palette, accent: render.Color) void {
    renderer.drawSmartStr(x, y, label, palette.muted, palette.surface, render.Style{ .bold = true });
    renderer.drawSmartStr(x, y + 1, value, accent, palette.surface, render.Style{ .bold = true });
}

/// Htop-style screen rendered interactively by default and as a deterministic snapshot with --snapshot.
pub fn main(init: std.process.Init) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var mock = try zit.testing.MockTerminal.init(allocator, 120, 35);
    defer mock.deinit();

    const palette = style.monitorPalette();
    const renderer = &mock.renderer;
    renderer.back.clear();
    const content = style.drawChrome(renderer, palette, "zit process monitor", "htop-style / q quits");

    const left = layout.Rect.init(content.x, content.y, 32, 13);
    const right = layout.Rect.init(content.x + 34, content.y, content.width - 34, 13);
    const table_rect = layout.Rect.init(content.x, content.y + 15, content.width, content.height - 15);

    style.drawPanel(renderer, left, palette, "CPU Cores", palette.danger);
    drawCore(renderer, left.x + 3, left.y + 3, "1", 0.88, palette, palette.danger);
    drawCore(renderer, left.x + 3, left.y + 5, "2", 0.64, palette, palette.warning);
    drawCore(renderer, left.x + 3, left.y + 7, "3", 0.42, palette, palette.success);
    drawCore(renderer, left.x + 3, left.y + 9, "4", 0.31, palette, palette.accent);
    renderer.drawSmartStr(left.x + 3, left.y + 11, "load avg  1.44  1.12  0.88", palette.muted, palette.surface, render.Style{ .bold = true });

    style.drawPanel(renderer, right, palette, "Memory / System", palette.accent);
    style.drawMeter(renderer, right.x + 3, right.y + 3, right.width - 6, "RAM  7.8G / 16.0G", 0.49, palette, palette.accent);
    style.drawMeter(renderer, right.x + 3, right.y + 6, right.width - 6, "Swap 1.1G / 4.0G", 0.28, palette, palette.warning);
    drawStat(renderer, right.x + 3, right.y + 9, "Tasks", "145 total / 2 running", palette, palette.success);
    drawStat(renderer, right.x + 30, right.y + 9, "Uptime", "8d 04:31", palette, palette.accent);
    drawStat(renderer, right.x + 50, right.y + 9, "Temp", "61C", palette, palette.warning);

    var table = try widget.Table.init(allocator);
    defer table.deinit();
    try table.addColumn("PID", 7, false);
    try table.addColumn("USER", 9, false);
    try table.addColumn("PRI", 5, false);
    try table.addColumn("CPU%", 7, true);
    try table.addColumn("MEM%", 7, true);
    try table.addColumn("TIME+", 9, false);
    try table.addColumn("COMMAND", 40, true);

    const rows = [_]Process{
        .{ .pid = "12844", .user = "palash", .pri = "20", .cpu = "82.1", .mem = "12.4", .time = "04:13.55", .command = "zig build release-check --summary none", .hot = true },
        .{ .pid = "11902", .user = "palash", .pri = "20", .cpu = "41.7", .mem = "08.2", .time = "02:48.10", .command = "zit render diff-worker" },
        .{ .pid = "948", .user = "root", .pri = "19", .cpu = "17.5", .mem = "03.1", .time = "31:04.88", .command = "WindowServer" },
        .{ .pid = "7221", .user = "palash", .pri = "20", .cpu = "12.9", .mem = "02.7", .time = "00:58.42", .command = "terminal input pump" },
        .{ .pid = "334", .user = "root", .pri = "20", .cpu = "03.4", .mem = "01.5", .time = "12:18.03", .command = "launchd" },
        .{ .pid = "5102", .user = "palash", .pri = "20", .cpu = "01.8", .mem = "00.9", .time = "00:11.71", .command = "gh run watch" },
        .{ .pid = "71", .user = "root", .pri = "20", .cpu = "00.6", .mem = "00.4", .time = "06:42.00", .command = "syslogd" },
    };
    for (rows, 0..) |row, idx| {
        try table.addRow(&.{ row.pid, row.user, row.pri, row.cpu, row.mem, row.time, row.command });
        if (row.hot) {
            try table.setCell(idx, 3, row.cpu, palette.danger, null);
            try table.setCell(idx, 6, row.command, palette.warning, null);
        }
    }
    table.show_grid = false;
    table.setShowHeaders(true);
    table.setBorder(.none);
    table.selected_row = 1;
    table.fg = palette.text;
    table.bg = palette.surface;
    table.header_bg = palette.surface_alt;
    table.header_fg = palette.accent;
    table.selected_bg = render.Color.rgb(18, 45, 66);
    table.selected_fg = palette.text;
    table.focused_bg = palette.surface_alt;
    table.focused_fg = palette.text;
    table.grid_fg = palette.border;

    style.drawPanel(renderer, table_rect, palette, "Processes", palette.accent);
    try table.widget.layout(layout.Rect.init(table_rect.x + 2, table_rect.y + 3, table_rect.width - 4, table_rect.height - 5));
    table.widget.markDirty();
    try table.widget.draw(renderer);

    renderer.drawSmartStr(table_rect.x + 3, table_rect.y + table_rect.height - 2, "F1 Help  F2 Setup  F3 Search  F4 Filter  F6 SortBy  F9 Kill", palette.muted, palette.surface, render.Style{ .bold = true });
    style.drawStatus(renderer, palette, "load: 1.44 1.12 0.88 | htop-clone | q quit");

    var snap = try mock.snapshot(allocator);
    defer snap.deinit(allocator);
    const frame = try mock.captureOutput();
    try interactive.finishFrames(init, allocator, "htop-clone", snap.text(), frame);
}
