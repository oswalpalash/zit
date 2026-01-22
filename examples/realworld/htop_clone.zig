// Real-world demo: htop-inspired process monitor using tables and sparklines.

const std = @import("std");
const zit = @import("zit");

/// A lightweight, non-interactive htop style snapshot rendered into a mock terminal.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var mock = try zit.testing.MockTerminal.init(allocator, 80, 24);
    defer mock.deinit();

    // CPU and memory bars.
    var cpu = try zit.widget.ProgressBar.init(allocator);
    defer cpu.deinit();
    cpu.setValue(72);
    cpu.setColors(
        zit.render.Color.named(.bright_white),
        zit.render.Color.named(.black),
        zit.render.Color.named(.bright_red),
        zit.render.Color.named(.black),
    );
    try cpu.widget.layout(zit.layout.Rect.init(6, 1, 32, 1));
    try cpu.widget.draw(&mock.renderer);
    mock.renderer.drawStr(1, 1, "CPU", zit.render.Color.named(.bright_white), zit.render.Color.named(.default), zit.render.Style{});

    var mem = try zit.widget.ProgressBar.init(allocator);
    defer mem.deinit();
    mem.setValue(48);
    mem.setColors(
        zit.render.Color.named(.bright_white),
        zit.render.Color.named(.black),
        zit.render.Color.named(.bright_cyan),
        zit.render.Color.named(.black),
    );
    try mem.widget.layout(zit.layout.Rect.init(6, 2, 32, 1));
    try mem.widget.draw(&mock.renderer);
    mock.renderer.drawStr(1, 2, "MEM", zit.render.Color.named(.bright_white), zit.render.Color.named(.default), zit.render.Style{});

    // Process table.
    var table = try zit.widget.Table.init(allocator);
    defer table.deinit();
    try table.addColumn("PID", 6, false);
    try table.addColumn("USER", 8, false);
    try table.addColumn("CPU%", 6, false);
    try table.addColumn("MEM%", 6, false);
    try table.addColumn("COMMAND", 30, true);

    const rows = [_][5][]const u8{
        .{ "1203", "root", "23.1", "12.4", "zig build test --summary" },
        .{ "992", "palash", "12.3", "08.1", "tailscaled" },
        .{ "4431", "palash", "07.9", "02.0", "zit demo render" },
        .{ "331", "root", "01.2", "00.8", "sshd: keepalive" },
        .{ "72", "palash", "00.3", "00.5", "htop-clone" },
    };
    for (rows, 0..) |row, idx| {
        try table.addRow(&row);
        const cpu_value = std.fmt.parseFloat(f32, row[2]) catch 0;
        if (cpu_value >= 20.0) {
            try table.setCell(idx, 2, row[2], zit.render.Color.named(.bright_red), null);
        }
    }
    table.show_grid = false;
    table.setShowHeaders(true);
    table.setBorder(.none);
    table.selected_row = 0;

    const table_frame = zit.layout.Rect.init(1, 4, 78, 16);
    mock.renderer.drawBox(
        table_frame.x,
        table_frame.y,
        table_frame.width,
        table_frame.height,
        .rounded,
        zit.render.Color.named(.bright_black),
        zit.render.Color.named(.black),
        zit.render.Style{},
    );

    try table.widget.layout(zit.layout.Rect.init(2, 5, 76, 14));
    try table.widget.draw(&mock.renderer);

    var status = try zit.widget.StatusBar.init(allocator);
    defer status.deinit();
    status.setSegments("load: 1.04 0.98 0.77", "htop-clone", "q quit  F9 kill");
    try status.widget.layout(zit.layout.Rect.init(0, 22, 80, 1));
    try status.widget.draw(&mock.renderer);

    var snap = try mock.snapshot(allocator);
    defer snap.deinit(allocator);
    std.debug.print("{s}", .{snap.text()});
}
