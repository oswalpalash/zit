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

    // Create a label
    var title = try zit.widget.Label.init(allocator, "Zit TUI Library");
    defer title.deinit();
    title.setAlignment(.center);
    title.setColor(
        zit.render.Color{ .named_color = zit.render.NamedColor.bright_white },
        zit.render.Color{ .named_color = zit.render.NamedColor.blue }
    );
    title.setStyle(zit.render.Style.init(true, false, true));

    // Create a button
    var button = try zit.widget.Button.init(allocator, "Click Me!");
    defer button.deinit();
    button.setColors(
        zit.render.Color{ .named_color = zit.render.NamedColor.black },
        zit.render.Color{ .named_color = zit.render.NamedColor.green },
        zit.render.Color{ .named_color = zit.render.NamedColor.white },
        zit.render.Color{ .named_color = zit.render.NamedColor.bright_green }
    );
    button.setBorder(.rounded);
    button.setOnPress(onButtonPress);

    // Create a checkbox
    var checkbox = try zit.widget.Checkbox.init(allocator, "Enable Feature");
    defer checkbox.deinit();
    checkbox.setColors(
        zit.render.Color{ .named_color = zit.render.NamedColor.bright_white },
        zit.render.Color{ .named_color = zit.render.NamedColor.blue },
        zit.render.Color{ .named_color = zit.render.NamedColor.white },
        zit.render.Color{ .named_color = zit.render.NamedColor.cyan }
    );
    checkbox.setOnChange(onCheckboxChange);

    // Create a progress bar
    var progress_bar = try zit.widget.ProgressBar.init(allocator);
    defer progress_bar.deinit();
    progress_bar.setValue(30);
    progress_bar.setShowPercentage(true);
    progress_bar.setColors(
        zit.render.Color{ .named_color = zit.render.NamedColor.black },
        zit.render.Color{ .named_color = zit.render.NamedColor.green },
        zit.render.Color{ .named_color = zit.render.NamedColor.bright_black },
        zit.render.Color{ .named_color = zit.render.NamedColor.blue }
    );
    progress_bar.setBorder(.single);

    // Create a list
    var list = try zit.widget.List.init(allocator);
    defer list.deinit();
    try list.addItem("Option 1");
    try list.addItem("Option 2");
    try list.addItem("Option 3");
    list.setSelectedIndex(0);
    list.setOnSelect(onListSelect);
    list.setColors(
        zit.render.Color{ .named_color = zit.render.NamedColor.bright_white },
        zit.render.Color{ .named_color = zit.render.NamedColor.blue },
        zit.render.Color{ .named_color = zit.render.NamedColor.black },
        zit.render.Color{ .named_color = zit.render.NamedColor.cyan }
    );
    list.setBorder(.single);

    // Create a status label
    var status = try zit.widget.Label.init(allocator, "Press 'q' to quit");
    defer status.deinit();
    status.setAlignment(.center);
    status.setColor(
        zit.render.Color{ .named_color = zit.render.NamedColor.bright_white },
        zit.render.Color{ .named_color = zit.render.NamedColor.blue }
    );

    // Variables for dynamic updates
    var progress_value: u8 = 0;
    var progress_increasing = true;

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

        // Create the window title
        const title_rect = zit.layout.Rect.init(
            // Use a safe division approach to prevent overflow
            if (width > 20) (width - 20) / 2 else 0,
            2,
            20,
            1
        );
        try title.widget.layout(title_rect);
        try title.widget.draw(&renderer);

        // Draw the button
        const button_rect = zit.layout.Rect.init(
            // Use a safe division approach to prevent overflow
            if (width > 12) (width - 12) / 2 else 0,
            if (height > 10) height / 2 - 4 else 0,
            12,
            3
        );
        try button.widget.layout(button_rect);
        try button.widget.draw(&renderer);

        // Draw the checkbox
        const checkbox_rect = zit.layout.Rect.init(
            // Use a safe division approach to prevent overflow
            if (width > 20) (width - 20) / 2 else 0,
            if (height > 10) height / 2 else 0,
            20,
            1
        );
        try checkbox.widget.layout(checkbox_rect);
        try checkbox.widget.draw(&renderer);

        // Draw the progress bar
        const progress_rect = zit.layout.Rect.init(
            // Use a safe division approach to prevent overflow
            if (width > 30) (width - 30) / 2 else 0,
            if (height > 10) height / 2 + 2 else 0,
            30,
            3
        );
        try progress_bar.widget.layout(progress_rect);
        try progress_bar.widget.draw(&renderer);

        // Draw the list
        const list_rect = zit.layout.Rect.init(
            // Use a safe division approach to prevent overflow
            if (width > 20) (width - 20) / 2 else 0,
            if (height > 10) height / 2 + 6 else 0,
            20,
            5
        );
        try list.widget.layout(list_rect);
        try list.widget.draw(&renderer);

        // Draw the status at the bottom
        const status_rect = zit.layout.Rect.init(
            // Use a safe division approach to prevent overflow
            if (width > 20) (width - 20) / 2 else 0,
            if (height > 2) height - 2 else 0,
            20,
            1
        );
        try status.widget.layout(status_rect);
        try status.widget.draw(&renderer);

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
                    } else {
                        // Pass the event to the widgets
                        _ = try button.widget.handleEvent(e);
                        _ = try checkbox.widget.handleEvent(e);
                        _ = try list.widget.handleEvent(e);
                    }
                },
                .resize => |resize| {
                    // Resize renderer
                    try renderer.resize(resize.width, resize.height);
                },
                .mouse => {
                    // Pass the event to the widgets
                    _ = try button.widget.handleEvent(e);
                    _ = try checkbox.widget.handleEvent(e);
                    _ = try list.widget.handleEvent(e);
                },
                else => {},
            }
        }
    }

    // Clean up
    try term.clear();
    try term.moveCursor(0, 0);
}

// Button press handler
fn onButtonPress() void {
    std.debug.print("Button clicked!\n", .{});
}

// Checkbox change handler
fn onCheckboxChange(checked: bool) void {
    std.debug.print("Checkbox changed: {}\n", .{checked});
}

// List selection handler
fn onListSelect(index: usize, text: []const u8) void {
    std.debug.print("List selection: {d} - {s}\n", .{ index, text });
}
