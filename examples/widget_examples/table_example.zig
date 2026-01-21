// Example: sortable/typeahead table with keyboard navigation.

const std = @import("std");
const zit = @import("zit");

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
    table.setHeaderColors(
        zit.render.Color{ .named_color = zit.render.NamedColor.black },
        zit.render.Color{ .named_color = zit.render.NamedColor.bright_white },
    );
    table.setSelectedColors(
        zit.render.Color{ .named_color = zit.render.NamedColor.black },
        zit.render.Color{ .named_color = zit.render.NamedColor.cyan },
    );

    try table.addColumn("Service", 18, true);
    try table.addColumn("Status", 10, true);
    try table.addColumn("Owner", 12, true);

    try table.addRow(&.{ "API Gateway", "Healthy", "Alice" });
    try table.addRow(&.{ "Billing", "Degraded", "Bob" });
    try table.addRow(&.{ "Catalog", "Healthy", "Carmen" });
    try table.addRow(&.{ "Fulfillment", "Deploying", "Daphne" });
    try table.addRow(&.{ "Search", "Healthy", "Evan" });
    table.setSelectedRow(0);

    const onSelectCtx = struct {
        fn logSelection(idx: usize) void {
            std.debug.print("Selected row {d}\n", .{idx});
        }
    };
    table.setOnRowSelected(onSelectCtx.logSelection);

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

        // Fill the background and show a one-line hint.
        renderer.fillRect(0, 0, term.width, term.height, ' ', zit.render.Color{ .named_color = zit.render.NamedColor.black }, zit.render.Color{ .named_color = zit.render.NamedColor.white }, zit.render.Style{});
        const hint = "Table demo: type to jump rows, arrows/page navigate, Enter selects, q quits";
        const hint_slice = hint[0..@min(hint.len, @as(usize, term.width))];
        renderer.drawStr(0, 0, hint_slice, zit.render.Color{ .named_color = zit.render.NamedColor.bright_black }, zit.render.Color{ .named_color = zit.render.NamedColor.white }, zit.render.Style{});

        const table_height: u16 = if (term.height > 2) term.height - 2 else term.height;
        if (table_height > 0) {
            try table.widget.layout(zit.layout.Rect.init(0, 1, term.width, table_height));
            try table.widget.draw(&renderer);
        }

        // Status line with current selection.
        if (term.height > 0 and term.width > 0) {
            const status_y: u16 = term.height - 1;
            var status_buf: [160]u8 = undefined;
            const selected = if (table.selected_row) |idx|
                table.rows.items[idx].items[0].text
            else
                "None";
            const status = std.fmt.bufPrint(&status_buf, "Selected: {s}", .{selected}) catch "Selected: ?";
            const status_slice = status[0..@min(status.len, @as(usize, term.width - 1))];
            renderer.drawStr(1, status_y, status_slice, zit.render.Color{ .named_color = zit.render.NamedColor.black }, zit.render.Color{ .named_color = zit.render.NamedColor.white }, zit.render.Style{});
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
                    term.width = resize.width;
                    term.height = resize.height;
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
