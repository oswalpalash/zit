const std = @import("std");
const zit = @import("zit");

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize terminal
    var term = try zit.terminal.init(allocator);
    defer term.deinit() catch {};

    // Get terminal size
    const width = term.width;
    const height = term.height;

    // Initialize renderer
    var renderer = try zit.render.Renderer.init(allocator, width, height);
    defer renderer.deinit();

    // Enable raw mode
    try term.enableRawMode();
    defer term.disableRawMode() catch {};

    // Initialize input handler
    var input_handler = zit.input.InputHandler.init(allocator, &term);
    // Enable mouse tracking
    try input_handler.enableMouse();

    // Create a title label
    var title = try zit.widget.Label.init(allocator, "Widget Test - Press 'q' to quit, Tab to navigate");
    defer title.deinit();
    title.setAlignment(.center);
    title.setColor(
        zit.render.Color{ .named_color = zit.render.NamedColor.bright_white },
        zit.render.Color{ .named_color = zit.render.NamedColor.blue }
    );
    title.setStyle(zit.render.Style.init(true, false, false));

    // Create a progress bar
    var progress_bar = try zit.widget.ProgressBar.init(allocator);
    defer progress_bar.deinit();
    progress_bar.setValue(30);
    progress_bar.setShowPercentage(true);
    progress_bar.setColors(
        zit.render.Color{ .named_color = zit.render.NamedColor.black },
        zit.render.Color{ .named_color = zit.render.NamedColor.green },
        zit.render.Color{ .named_color = zit.render.NamedColor.bright_black },
        zit.render.Color{ .named_color = zit.render.NamedColor.bright_black }
    );
    progress_bar.setBorder(.single);

    // Create a dropdown menu
    var dropdown = try zit.widget.DropdownMenu.init(allocator);
    defer dropdown.deinit();
    try dropdown.addItem("Option 1", true, null);
    try dropdown.addItem("Option 2", true, null);
    try dropdown.addItem("Option 3", true, null);
    try dropdown.addItem("Long option that will be truncated", true, null);
    dropdown.setSelectedIndex(0);
    dropdown.setColors(
        zit.render.Color{ .named_color = zit.render.NamedColor.white },
        zit.render.Color{ .named_color = zit.render.NamedColor.blue },
        zit.render.Color{ .named_color = zit.render.NamedColor.black },
        zit.render.Color{ .named_color = zit.render.NamedColor.cyan }
    );

    // Create a table
    var table = try zit.widget.Table.init(allocator);
    defer table.deinit();
    try table.addRow(&.{ "1", "Item 1", "100" });
    try table.addRow(&.{ "2", "Item 2", "200" });
    try table.addRow(&.{ "3", "Item with very long name", "300" });
    try table.addRow(&.{ "4", "Item 4", "400" });
    table.setSelectedRow(0);
    table.setColors(
        zit.render.Color{ .named_color = zit.render.NamedColor.white },
        zit.render.Color{ .named_color = zit.render.NamedColor.blue }
    );
    table.setBorder(.single);

    // Create a list
    var list = try zit.widget.List.init(allocator);
    defer list.deinit();
    try list.addItem("List Item 1");
    try list.addItem("List Item 2");
    try list.addItem("List Item 3 (longer item)");
    try list.addItem("List Item 4");
    list.setSelectedIndex(0);
    list.setColors(
        zit.render.Color{ .named_color = zit.render.NamedColor.white },
        zit.render.Color{ .named_color = zit.render.NamedColor.blue },
        zit.render.Color{ .named_color = zit.render.NamedColor.black },
        zit.render.Color{ .named_color = zit.render.NamedColor.cyan }
    );
    list.setBorder(.single);

    // Create a status label
    var status = try zit.widget.Label.init(allocator, "Tab between widgets, Enter to interact");
    defer status.deinit();
    status.setAlignment(.center);
    status.setColor(
        zit.render.Color{ .named_color = zit.render.NamedColor.bright_white },
        zit.render.Color{ .named_color = zit.render.NamedColor.blue }
    );

    // Create a button to show modal dialog
    var modal_button = try zit.widget.Button.init(allocator, "Show Modal");
    defer modal_button.deinit();
    modal_button.setColors(
        zit.render.Color{ .named_color = zit.render.NamedColor.black },
        zit.render.Color{ .named_color = zit.render.NamedColor.green },
        zit.render.Color{ .named_color = zit.render.NamedColor.white },
        zit.render.Color{ .named_color = zit.render.NamedColor.bright_green }
    );
    modal_button.setBorder(.rounded);
    
    // Create a modal dialog
    var modal = try zit.widget.Modal.init(allocator);
    defer modal.deinit();
    modal.width = 40;
    modal.height = 10;
    try modal.setTitle("Modal Dialog");

    // Create content for the modal
    var modal_content = try zit.widget.Label.init(allocator, "This is a modal dialog.\nPress Escape to close.");
    defer modal_content.deinit();
    modal_content.setAlignment(.center);
    modal_content.setColor(
        zit.render.Color{ .named_color = zit.render.NamedColor.white },
        zit.render.Color{ .named_color = zit.render.NamedColor.blue }
    );
    modal.setContent(&modal_content.widget);
    
    // Set modal button callback
    modal_button.setOnPress(showModal);
    
    // Store the modal in a global variable to access in the callback
    g_modal = modal;

    // Variables for dynamic updates
    var progress_value: u8 = 0;
    var progress_increasing = true;

    // Create widgets array
    const widgets = [_]*zit.widget.Widget{
        &progress_bar.widget,
        &dropdown.widget,
        &table.widget,
        &list.widget,
        &modal_button.widget,
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
        renderer.fillRect(0, 0, width, height, ' ', 
            zit.render.Color{ .named_color = zit.render.NamedColor.white }, 
            zit.render.Color{ .named_color = zit.render.NamedColor.blue }, 
            zit.render.Style{});

        // Draw border
        renderer.drawBox(0, 0, width, height, 
            zit.render.BorderStyle.single, 
            zit.render.Color{ .named_color = zit.render.NamedColor.bright_white }, 
            zit.render.Color{ .named_color = zit.render.NamedColor.blue }, 
            zit.render.Style{});

        // Draw the title
        const title_rect = zit.layout.Rect.init(
            1,
            1,
            width - 2,
            1
        );
        try title.widget.layout(title_rect);
        try title.widget.draw(&renderer);

        // Calculate equal column width
        const col_width = if (width > 6) (width - 6) / 3 else 1;
        
        // Draw the progress bar
        const progress_bar_rect = zit.layout.Rect.init(
            2,
            4,
            col_width,
            3
        );
        try progress_bar.widget.layout(progress_bar_rect);
        try progress_bar.widget.draw(&renderer);

        // Draw the dropdown
        const dropdown_rect = zit.layout.Rect.init(
            2,
            9,
            col_width,
            3
        );
        try dropdown.widget.layout(dropdown_rect);
        try dropdown.widget.draw(&renderer);

        // Draw the list
        const list_rect = zit.layout.Rect.init(
            2 + col_width + 1,
            4,
            col_width,
            8
        );
        try list.widget.layout(list_rect);
        try list.widget.draw(&renderer);

        // Draw the table
        const table_rect = zit.layout.Rect.init(
            2 + 2*col_width + 2,
            4,
            col_width,
            8
        );
        try table.widget.layout(table_rect);
        try table.widget.draw(&renderer);

        // Draw the modal button
        const button_rect = zit.layout.Rect.init(
            2,
            14,
            col_width,
            3
        );
        try modal_button.widget.layout(button_rect);
        try modal_button.widget.draw(&renderer);

        // Draw the status at the bottom
        const status_rect = zit.layout.Rect.init(
            1,
            if (height > 3) height - 2 else 1,
            width - 2,
            1
        );
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
                    } 
                    else {
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
    std.debug.print("Selected option {d}: {s}\n", .{ index, text });
}

// Table selection handler
fn onTableSelect(index: usize) void {
    std.debug.print("Selected table row: {d}\n", .{index});
}

// List selection handler
fn onListSelect(index: usize, text: []const u8) void {
    std.debug.print("Selected list item {d}: {s}\n", .{ index, text });
} 