// Example: sortable/typeahead table with keyboard navigation.

const std = @import("std");
const zit = @import("zit");
const theme = zit.widget.theme;

const TableNotice = struct {
    buffer: [120]u8 = undefined,
    text: []const u8 = "Last selection: none",
};

var table_notice = TableNotice{};

fn onRowSelect(idx: usize) void {
    table_notice.text = std.fmt.bufPrint(&table_notice.buffer, "Last selection: row {d}", .{idx}) catch table_notice.text;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var term = try zit.terminal.init(allocator);
    defer term.deinit() catch {};

    var renderer = try zit.render.Renderer.init(allocator, term.width, term.height);
    defer renderer.deinit();

    var input_handler = zit.input.InputHandler.init(allocator, &term);
    try input_handler.enableMouse();

    var table = try zit.widget.Table.init(allocator);
    defer table.deinit();
    table.widget.focused = true;
    table.setShowHeaders(true);
    table.setBorder(.single);
    const ui_theme = theme.Theme.dark();
    const bg = ui_theme.color(.background);
    const text = ui_theme.color(.text);
    const muted = ui_theme.color(.muted);
    const surface = ui_theme.color(.surface);
    table.setTheme(ui_theme);

    try table.addColumn("Service", 18, true);
    try table.addColumn("Status", 10, true);
    try table.addColumn("Owner", 12, true);

    try table.addRow(&.{ "API Gateway", "Healthy", "Alice" });
    try table.addRow(&.{ "Billing", "Degraded", "Bob" });
    try table.addRow(&.{ "Catalog", "Healthy", "Carmen" });
    try table.addRow(&.{ "Fulfillment", "Deploying", "Daphne" });
    try table.addRow(&.{ "Search", "Healthy", "Evan" });
    table.setSelectedRow(0);

    table.setOnRowSelect(onRowSelect);

    try term.enableRawMode();
    try term.hideCursor();
    defer {
        input_handler.disableMouse() catch {};
        term.showCursor() catch {};
        term.disableRawMode() catch {};
    }

    var running = true;
    while (running) {
        renderer.back.clear();

        const width = renderer.back.width;
        const height = renderer.back.height;

        // Fill the background and show a one-line hint.
        renderer.fillRect(0, 0, width, height, ' ', text, bg, zit.render.Style{});
        const hint = "Table demo: type to jump rows, arrows/page navigate, Enter selects, q quits";
        const hint_slice = hint[0..@min(hint.len, @as(usize, width))];
        renderer.drawStr(0, 0, hint_slice, muted, bg, zit.render.Style{});

        const table_height: u16 = if (height > 2) height - 2 else height;
        if (table_height > 0) {
            try table.widget.layout(zit.layout.Rect.init(0, 1, width, table_height));
            try table.widget.draw(&renderer);
        }

        // Status line with current selection.
        if (height > 0 and width > 0) {
            const status_y: u16 = height - 1;
            var status_buf: [160]u8 = undefined;
            const selected = if (table.selected_row) |idx|
                table.rows.items[idx].items[0].text
            else
                "None";
            const status = std.fmt.bufPrint(&status_buf, "Selected: {s} | {s}", .{ selected, table_notice.text }) catch "Selected: ?";
            const status_slice = status[0..@min(status.len, @as(usize, width - 1))];
            renderer.drawStr(1, status_y, status_slice, text, surface, zit.render.Style{});
        }

        try renderer.render();

        const event = try input_handler.pollEvent(120);
        if (event) |e| {
            switch (e) {
                .key => |key| {
                    if (key.key == 'q' and !key.modifiers.ctrl and !key.modifiers.alt) {
                        running = false;
                    } else {
                        _ = try table.widget.handleEvent(e);
                    }
                },
                .resize => |resize| {
                    try renderer.resize(resize.width, resize.height);
                },
                else => {
                    _ = try table.widget.handleEvent(e);
                },
            }
        }
    }

    try term.clear();
    try term.moveCursor(0, 0);
}
