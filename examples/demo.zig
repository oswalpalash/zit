// Demo: multi-widget screen with mouse input, buttons, checkbox, progress, and list on an alternate screen.

const std = @import("std");
const zit = @import("zit");
const render = zit.render;
const layout = zit.layout;
const memory = zit.memory;
const theme = zit.widget.theme;

var demo_status_label: ?*zit.widget.Label = null;
var demo_status_buf: [96]u8 = undefined;

fn updateStatus(comptime fmt: []const u8, args: anytype) void {
    const label = demo_status_label orelse return;
    const text = std.fmt.bufPrint(&demo_status_buf, fmt, args) catch return;
    label.setText(text) catch {};
}

pub fn main() !void {
    // Initialize memory manager
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var memory_manager = try memory.MemoryManager.init(allocator, 1024 * 1024, 100);
    defer memory_manager.deinit();

    // Initialize terminal with memory manager
    var term = try zit.terminal.init(memory_manager.getArenaAllocator());
    defer term.deinit() catch {};

    // Initialize renderer with memory manager
    var renderer = try render.Renderer.init(memory_manager.getArenaAllocator(), term.width, term.height);
    defer renderer.deinit();

    // Initialize input handler with memory manager
    var input_handler = zit.input.InputHandler.init(memory_manager.getArenaAllocator(), &term);

    try term.enterAlternateScreen();
    defer term.exitAlternateScreen() catch {};

    // Enable raw mode
    try term.enableRawMode();
    defer term.disableRawMode() catch {};

    try term.hideCursor();
    try input_handler.enableMouse();
    defer {
        input_handler.disableMouse() catch {};
        term.showCursor() catch {};
    }

    // Create widgets using the widget pool allocator
    const ui_theme = theme.Theme.dark();
    const bg = ui_theme.color(.background);
    const text = ui_theme.color(.text);
    const muted = ui_theme.color(.muted);
    const border = ui_theme.color(.border);

    var title = try zit.widget.Label.init(memory_manager.getWidgetPoolAllocator(), "Zit TUI Library");
    defer title.deinit();
    title.setAlignment(.center);
    title.setTheme(ui_theme);
    title.setStyle(zit.render.Style.init(true, false, true));

    var button = try zit.widget.Button.init(memory_manager.getWidgetPoolAllocator(), "Click Me!");
    defer button.deinit();
    button.setTheme(ui_theme);
    button.setBorder(.rounded);
    button.setOnClick(onButtonPress);

    var checkbox = try zit.widget.Checkbox.init(memory_manager.getWidgetPoolAllocator(), "Enable Feature");
    defer checkbox.deinit();
    checkbox.setTheme(ui_theme);
    checkbox.setOnChange(onCheckboxChange);

    var progress_bar = try zit.widget.ProgressBar.init(memory_manager.getWidgetPoolAllocator());
    defer progress_bar.deinit();
    progress_bar.setValue(30);
    progress_bar.setShowPercentage(true);
    progress_bar.setTheme(ui_theme);
    progress_bar.setBorder(.single);

    var list = try zit.widget.List.init(memory_manager.getWidgetPoolAllocator());
    defer list.deinit();
    try list.addItem("Option 1");
    try list.addItem("Option 2");
    try list.addItem("Option 3");
    list.setSelectedIndex(0);
    list.setOnSelect(onListSelect);
    list.setTheme(ui_theme);
    list.setBorder(.single);

    var status = try zit.widget.Label.init(memory_manager.getWidgetPoolAllocator(), "Press 'q' to quit");
    defer status.deinit();
    status.setAlignment(.center);
    status.setTheme(ui_theme);
    status.setColor(muted, bg);
    demo_status_label = status;

    // Variables for dynamic updates
    var progress_value: u8 = 0;
    var progress_increasing = true;

    // Clear screen
    try term.clear();

    // Main event loop
    var running = true;
    while (running) {
        const width = renderer.back.width;
        const height = renderer.back.height;

        // Clear the buffer
        renderer.back.clear();

        // Fill the background
        renderer.fillRect(0, 0, width, height, ' ', text, bg, render.Style{});

        // Draw border
        renderer.drawBox(0, 0, width, height, render.BorderStyle.single, border, bg, render.Style{});

        // Create the window title
        const title_rect = layout.Rect.init(if (width > 20) (width - 20) / 2 else 0, 2, 20, 1);
        try title.widget.layout(title_rect);
        try title.widget.draw(&renderer);

        // Draw the button
        const button_rect = layout.Rect.init(if (width > 12) (width - 12) / 2 else 0, if (height > 10) height / 2 - 4 else 0, 12, 3);
        try button.widget.layout(button_rect);
        try button.widget.draw(&renderer);

        // Draw the checkbox
        const checkbox_rect = layout.Rect.init(if (width > 20) (width - 20) / 2 else 0, if (height > 10) height / 2 else 0, 20, 1);
        try checkbox.widget.layout(checkbox_rect);
        try checkbox.widget.draw(&renderer);

        // Draw the progress bar
        const progress_rect = layout.Rect.init(if (width > 30) (width - 30) / 2 else 0, if (height > 10) height / 2 + 2 else 0, 30, 3);
        try progress_bar.widget.layout(progress_rect);
        try progress_bar.widget.draw(&renderer);

        // Draw the list
        const list_rect = layout.Rect.init(if (width > 20) (width - 20) / 2 else 0, if (height > 10) height / 2 + 6 else 0, 20, 5);
        try list.widget.layout(list_rect);
        try list.widget.draw(&renderer);

        // Draw the status at the bottom
        const status_rect = layout.Rect.init(if (width > 20) (width - 20) / 2 else 0, if (height > 2) height - 2 else 0, 20, 1);
        try status.widget.layout(status_rect);
        try status.widget.draw(&renderer);

        // Render to screen
        try renderer.render();

        // Update progress bar (animate it)
        if (progress_increasing) {
            if (progress_value >= 100) {
                progress_increasing = false;
            } else {
                progress_value += 1;
            }
        } else if (progress_value == 0) {
            progress_increasing = true;
        } else {
            progress_value -= 1;
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
    updateStatus("Button clicked", .{});
}

// Checkbox change handler
fn onCheckboxChange(checked: bool) void {
    updateStatus("Checkbox: {s}", .{if (checked) "enabled" else "disabled"});
}

// List select handler
fn onListSelect(index: usize, item: []const u8) void {
    updateStatus("Selected {d}: {s}", .{ index, item });
}
