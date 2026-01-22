// Widget test: navigable collection of common widgets (dropdown, table, progress, buttons).

const std = @import("std");
const zit = @import("zit");
const widget_theme = zit.widget.theme;

var widget_status_label: ?*zit.widget.Label = null;
var widget_status_buf: [96]u8 = undefined;

fn updateStatus(comptime fmt: []const u8, args: anytype) void {
    const label = widget_status_label orelse return;
    const text = std.fmt.bufPrint(&widget_status_buf, fmt, args) catch return;
    label.setText(text) catch {};
}

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize terminal
    var term = try zit.terminal.init(allocator);
    defer term.deinit() catch {};

    // Initialize renderer
    var renderer = try zit.render.Renderer.init(allocator, term.width, term.height);
    defer renderer.deinit();

    // Enable raw mode
    try term.enableRawMode();
    defer term.disableRawMode() catch {};

    // Initialize input handler
    var input_handler = zit.input.InputHandler.init(allocator, &term);
    // Enable mouse tracking
    try input_handler.enableMouse();
    defer input_handler.disableMouse() catch {};

    // Create a title label
    var title = try zit.widget.Label.init(allocator, "Widget Test - Press 'q' to quit, Tab to navigate");
    defer title.deinit();
    title.setAlignment(.center);
    const ui_theme = widget_theme.Theme.dark();
    const bg = ui_theme.color(.background);
    const text = ui_theme.color(.text);
    const muted = ui_theme.color(.muted);
    const border = ui_theme.color(.border);
    title.setTheme(ui_theme);
    title.setStyle(zit.render.Style.init(true, false, false));

    // Create a progress bar
    var progress_bar = try zit.widget.ProgressBar.init(allocator);
    defer progress_bar.deinit();
    progress_bar.setValue(30);
    progress_bar.setShowPercentage(true);
    progress_bar.setTheme(ui_theme);
    progress_bar.setBorder(.single);

    // Create a dropdown menu
    var dropdown = try zit.widget.DropdownMenu.init(allocator);
    defer dropdown.deinit();
    try dropdown.addItem("Option 1", true, null);
    try dropdown.addItem("Option 2", true, null);
    try dropdown.addItem("Option 3", true, null);
    try dropdown.addItem("Long option that will be truncated", true, null);
    dropdown.setSelectedIndex(0);
    dropdown.setTheme(ui_theme);

    // Create a table
    var table = try zit.widget.Table.init(allocator);
    defer table.deinit();
    try table.addRow(&.{ "1", "Item 1", "100" });
    try table.addRow(&.{ "2", "Item 2", "200" });
    try table.addRow(&.{ "3", "Item with very long name", "300" });
    try table.addRow(&.{ "4", "Item 4", "400" });
    table.setSelectedRow(0);
    table.setTheme(ui_theme);
    table.setBorder(.single);

    // Create a list
    var list = try zit.widget.List.init(allocator);
    defer list.deinit();
    try list.addItem("List Item 1");
    try list.addItem("List Item 2");
    try list.addItem("List Item 3 (longer item)");
    try list.addItem("List Item 4");
    list.setSelectedIndex(0);
    list.setTheme(ui_theme);
    list.setBorder(.single);

    // Create a status label
    var status = try zit.widget.Label.init(allocator, "Tab between widgets, Enter to interact");
    defer status.deinit();
    status.setAlignment(.center);
    status.setTheme(ui_theme);
    status.setColor(muted, bg);
    widget_status_label = status;

    // Create a button to show modal dialog
    var modal_button = try zit.widget.Button.init(allocator, "Show Modal");
    defer modal_button.deinit();
    modal_button.setTheme(ui_theme);
    modal_button.setBorder(.rounded);

    // Create a modal dialog
    var modal = try zit.widget.Modal.init(allocator);
    defer modal.deinit();
    modal.width = 40;
    modal.height = 10;
    try modal.setTitle("Modal Dialog");
    modal.setTheme(ui_theme);

    // Create content for the modal
    var modal_content = try zit.widget.Label.init(allocator, "This is a modal dialog.\nPress Escape to close.");
    defer modal_content.deinit();
    modal_content.setAlignment(.center);
    modal_content.setTheme(ui_theme);
    modal.setContent(&modal_content.widget);

    // Set modal button callback
    modal_button.setOnClick(showModal);

    // Store the modal in a global variable to access in the callback
    g_modal = modal;

    // Tree view + metrics widgets
    var tree = try zit.widget.TreeView.init(allocator);
    defer tree.deinit();
    const services = try tree.addRoot("Services");
    const api = try tree.addChild(services, "API");
    _ = try tree.addChild(api, "Gateway");
    _ = try tree.addChild(api, "Users");
    const data = try tree.addChild(services, "Data");
    _ = try tree.addChild(data, "Postgres");
    _ = try tree.addChild(data, "Redis");
    tree.nodes.items[services].expanded = true;
    tree.nodes.items[api].expanded = true;
    tree.nodes.items[data].expanded = true;
    try tree.setTheme(widget_theme.Theme.dark());

    var sparkline = try zit.widget.Sparkline.init(allocator);
    defer sparkline.deinit();
    try sparkline.setTheme(widget_theme.Theme.dark());
    sparkline.setMaxSamples(80);

    var gauge = try zit.widget.Gauge.init(allocator);
    defer gauge.deinit();
    gauge.setRange(0, 100);
    try gauge.setTheme(widget_theme.Theme.light());
    try gauge.setLabel("Load 0%");

    var metrics_split = try zit.widget.SplitPane.init(allocator);
    defer metrics_split.deinit();
    metrics_split.setOrientation(.vertical);
    metrics_split.setFirst(&gauge.widget);
    metrics_split.setSecond(&sparkline.widget);
    metrics_split.setRatio(0.35);

    var layout_split = try zit.widget.SplitPane.init(allocator);
    defer layout_split.deinit();
    layout_split.setOrientation(.horizontal);
    layout_split.setFirst(&tree.widget);
    layout_split.setSecond(&metrics_split.widget);
    layout_split.setRatio(0.4);

    // Variables for dynamic updates
    var progress_value: u8 = 0;
    var progress_increasing = true;
    var gauge_value: f32 = 20;
    var gauge_delta: f32 = 2.5;
    const rng_seed: u64 = @bitCast(std.time.timestamp());
    var rng = std.Random.DefaultPrng.init(rng_seed);

    // Create widgets array
    const widgets = [_]*zit.widget.Widget{
        &progress_bar.widget,
        &dropdown.widget,
        &table.widget,
        &list.widget,
        &modal_button.widget,
        &layout_split.widget,
    };
    var current_focus: usize = 0;
    widgets[current_focus].*.focused = true;

    // Clear screen
    try term.clear();

    // Main event loop
    var running = true;
    while (running) {
        // Clear the buffer
        renderer.back.clear();

        // Fill the background
        const width = renderer.back.width;
        const height = renderer.back.height;
        renderer.fillRect(0, 0, width, height, ' ', text, bg, zit.render.Style{});

        // Draw border
        renderer.drawBox(0, 0, width, height, zit.render.BorderStyle.single, border, bg, zit.render.Style{});

        // Draw the title
        const title_rect = zit.layout.Rect.init(1, 1, width - 2, 1);
        try title.widget.layout(title_rect);
        try title.widget.draw(&renderer);

        // Calculate equal column width
        const col_width = if (width > 6) (width - 6) / 3 else 1;

        // Draw the progress bar
        const progress_bar_rect = zit.layout.Rect.init(2, 4, col_width, 3);
        try progress_bar.widget.layout(progress_bar_rect);
        try progress_bar.widget.draw(&renderer);

        // Draw the dropdown
        const dropdown_rect = zit.layout.Rect.init(2, 9, col_width, 3);
        try dropdown.widget.layout(dropdown_rect);
        try dropdown.widget.draw(&renderer);

        // Draw the list
        const list_rect = zit.layout.Rect.init(2 + col_width + 1, 4, col_width, 8);
        try list.widget.layout(list_rect);
        try list.widget.draw(&renderer);

        // Draw the table
        const table_rect = zit.layout.Rect.init(2 + 2 * col_width + 2, 4, col_width, 8);
        try table.widget.layout(table_rect);
        try table.widget.draw(&renderer);

        // Draw the modal button
        const button_rect = zit.layout.Rect.init(2, 14, col_width, 3);
        try modal_button.widget.layout(button_rect);
        try modal_button.widget.draw(&renderer);

        // Tree/sparkline/gauge split area below the primary widgets
        const panel_y: u16 = 18;
        if (height > panel_y + 3 and width > 6) {
            const panel_height: u16 = height - panel_y - 3;
            const panel_width: u16 = width - 4;
            const split_rect = zit.layout.Rect.init(2, panel_y, panel_width, panel_height);
            try layout_split.widget.layout(split_rect);
            sparkline.setMaxSamples(@max(8, @as(usize, @intCast(split_rect.width))));
            try layout_split.widget.draw(&renderer);
        }

        // Draw the status at the bottom
        const status_rect = zit.layout.Rect.init(1, if (height > 3) height - 2 else 1, width - 2, 1);
        try status.widget.layout(status_rect);
        try status.widget.draw(&renderer);

        // Draw the modal dialog if visible
        if (modal.widget.visible) {
            try modal.widget.layout(zit.layout.Rect.init(0, 0, width, height));
            try modal.widget.draw(&renderer);
        }

        // Render to screen
        try renderer.render();

        // Update progress bar (animate it)
        if (progress_increasing) {
            progress_value += 1;
            if (progress_value >= 100) {
                progress_increasing = false;
            }
        } else {
            progress_value -= 1;
            if (progress_value <= 0) {
                progress_increasing = true;
            }
        }
        progress_bar.setValue(progress_value);

        gauge_value += gauge_delta;
        if (gauge_value >= 95 or gauge_value <= 5) {
            gauge_delta = -gauge_delta;
        }
        gauge.setValue(gauge_value);
        var gauge_buf: [24]u8 = undefined;
        const gauge_label = std.fmt.bufPrint(&gauge_buf, "Load {d}%", .{@as(u8, @intFromFloat(std.math.clamp(gauge_value, 0.0, 100.0)))}) catch "Load";
        try gauge.setLabel(gauge_label);

        const jitter = rng.random().float(f32) * 10.0 - 5.0;
        const sample = std.math.clamp(gauge_value + jitter, 0.0, 100.0);
        try sparkline.push(sample);

        // Poll for events with a 100ms timeout
        const event = try input_handler.pollEvent(100);

        if (event) |e| {
            switch (e) {
                .key => |key| {
                    // Exit on 'q' key
                    if (key.key == 'q' and !key.modifiers.ctrl and !key.modifiers.alt) {
                        running = false;
                    }
                    // Tab key to switch focus
                    else if (key.key == '\t' and !modal.widget.visible) {
                        widgets[current_focus].*.focused = false;
                        current_focus = (current_focus + 1) % widgets.len;
                        widgets[current_focus].*.focused = true;
                    } else {
                        // Pass event to the modal first if visible
                        if (modal.widget.visible) {
                            _ = try modal.widget.handleEvent(e);
                        }
                        // Otherwise pass to the focused widget
                        else {
                            _ = try widgets[current_focus].*.handleEvent(e);
                        }
                    }
                },
                .resize => |resize| {
                    // Resize renderer
                    try renderer.resize(resize.width, resize.height);
                },
                .mouse => {
                    // Pass event to the modal first if visible
                    if (modal.widget.visible) {
                        _ = try modal.widget.handleEvent(e);
                    } else {
                        // Pass to all widgets and check if any consumed it
                        var handled = false;
                        for (widgets, 0..) |widget, idx| {
                            if (try widget.*.handleEvent(e)) {
                                // If a widget handled the event, focus on it
                                if (!handled) {
                                    widgets[current_focus].*.focused = false;
                                    current_focus = idx;
                                    widgets[current_focus].*.focused = true;
                                    handled = true;
                                }
                            }
                        }
                    }
                },
                else => {},
            }
        }
    }

    // Clean up
    try term.clear();
    try term.moveCursor(0, 0);
}

// Store modal reference for the callback
var g_modal: ?*zit.widget.Modal = null;

// Show modal callback
fn showModal() void {
    if (g_modal) |modal| {
        modal.widget.visible = true;
    }
}

// Dropdown selection handler
fn onDropdownSelect(index: usize, text: []const u8) void {
    updateStatus("Dropdown {d}: {s}", .{ index, text });
}

// Table selection handler
fn onTableSelect(index: usize) void {
    updateStatus("Table row {d} selected", .{index});
}

// List selection handler
fn onListSelect(index: usize, text: []const u8) void {
    updateStatus("List {d}: {s}", .{ index, text });
}
