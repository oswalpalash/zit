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

fn drawText(renderer: *render.Renderer, x: u16, y: u16, value: []const u8, fg: render.Color, bg: render.Color, bold: bool) void {
    renderer.drawStr(x, y, value, fg, bg, render.Style.init(bold, false, false));
}

pub fn main() !void {
    // Initialize memory manager
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var memory_manager = try memory.MemoryManager.init(allocator, 1024 * 1024, 100);
    defer memory_manager.deinit();

    // Initialize terminal with memory manager
    var term = (try zit.terminal.initInteractive(memory_manager.getArenaAllocator(), "demo")) orelse return;
    defer term.deinit() catch {};

    // Initialize renderer with the parent allocator
    var renderer = try render.Renderer.init(allocator, term.width, term.height);
    defer renderer.deinit();

    // Initialize input handler with the parent allocator
    var input_handler = zit.input.InputHandler.init(allocator, &term);
    var app = zit.event.Application.init(allocator);
    defer app.deinit();
    app.bindResize(&renderer, null);
    app.bindInput(&input_handler);
    app.setInputPollTimeout(100);

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

        // Draw a stable application frame.
        renderer.drawBox(0, 0, width, height, render.BorderStyle.single, border, bg, render.Style{});
        if (width > 2 and height > 2) {
            renderer.fillRect(1, 1, width - 2, 3, ' ', bg, border, render.Style{});
            drawText(&renderer, 3, 1, "Zit TUI Library", bg, border, true);
            drawText(&renderer, 3, 2, "interactive sampler  |  mouse + keyboard  |  q quits", muted, border, false);
        }

        const inner_x: u16 = 2;
        const inner_y: u16 = 5;
        const inner_w: u16 = if (width > 4) width - 4 else width;
        const inner_h: u16 = if (height > 9) height - 9 else 1;
        const gap: u16 = 2;
        const left_w: u16 = if (inner_w >= 72) 30 else if (inner_w > 6) inner_w / 2 - 1 else inner_w;
        const right_w: u16 = if (inner_w > left_w + gap) inner_w - left_w - gap else 0;
        const left_x = inner_x;
        const right_x = inner_x + left_w + gap;

        renderer.drawBox(left_x, inner_y, left_w, inner_h, render.BorderStyle.rounded, border, bg, render.Style{});
        if (right_w > 4) {
            renderer.drawBox(right_x, inner_y, right_w, inner_h, render.BorderStyle.rounded, border, bg, render.Style{});
        }
        drawText(&renderer, left_x + 2, inner_y, "Controls", text, bg, true);
        if (right_w > 4) drawText(&renderer, right_x + 2, inner_y, "Runtime State", text, bg, true);

        title.widget.markDirty();
        button.widget.markDirty();
        checkbox.widget.markDirty();
        progress_bar.widget.markDirty();
        list.widget.markDirty();
        status.widget.markDirty();

        // Create the window title
        const title_rect = layout.Rect.init(left_x + 2, inner_y + 2, if (left_w > 4) left_w - 4 else left_w, 1);
        try title.widget.layout(title_rect);
        try title.widget.draw(&renderer);

        // Draw the button
        const button_rect = layout.Rect.init(left_x + 2, inner_y + 4, if (left_w > 8) left_w - 4 else left_w, 3);
        try button.widget.layout(button_rect);
        try button.widget.draw(&renderer);

        // Draw the checkbox
        const checkbox_rect = layout.Rect.init(left_x + 3, inner_y + 8, if (left_w > 6) left_w - 6 else left_w, 1);
        try checkbox.widget.layout(checkbox_rect);
        try checkbox.widget.draw(&renderer);

        // Draw the progress bar
        const progress_rect = layout.Rect.init(left_x + 2, inner_y + 11, if (left_w > 4) left_w - 4 else left_w, 3);
        try progress_bar.widget.layout(progress_rect);
        try progress_bar.widget.draw(&renderer);

        // Draw the list
        const list_rect = layout.Rect.init(left_x + 2, inner_y + 15, if (left_w > 4) left_w - 4 else left_w, if (inner_h > 18) inner_h - 17 else 5);
        try list.widget.layout(list_rect);
        try list.widget.draw(&renderer);

        if (right_w > 16 and inner_h > 6) {
            const metric_x = right_x + 3;
            var metric_y = inner_y + 3;
            drawText(&renderer, metric_x, metric_y, "Render loop", muted, bg, false);
            drawText(&renderer, metric_x + 18, metric_y, "steady", text, bg, true);
            metric_y += 2;
            drawText(&renderer, metric_x, metric_y, "Resize binding", muted, bg, false);
            drawText(&renderer, metric_x + 18, metric_y, "active", text, bg, true);
            metric_y += 2;
            drawText(&renderer, metric_x, metric_y, "Input polling", muted, bg, false);
            drawText(&renderer, metric_x + 18, metric_y, "100ms", text, bg, true);
            metric_y += 3;
            renderer.drawBox(metric_x, metric_y, if (right_w > 8) right_w - 6 else right_w, 5, render.BorderStyle.single, border, bg, render.Style{});
            drawText(&renderer, metric_x + 2, metric_y + 1, "Try it:", text, bg, true);
            drawText(&renderer, metric_x + 2, metric_y + 2, "click button, toggle checkbox,", muted, bg, false);
            drawText(&renderer, metric_x + 2, metric_y + 3, "resize terminal, press q.", muted, bg, false);
        }

        // Draw the status at the bottom
        if (height > 2 and width > 4) {
            renderer.fillRect(1, height - 3, width - 2, 2, ' ', bg, border, render.Style{});
        }
        const status_rect = layout.Rect.init(3, if (height > 2) height - 2 else 0, if (width > 6) width - 6 else width, 1);
        try status.widget.layout(status_rect);
        try status.widget.draw(&renderer);
        renderer.drawResizeStatus(muted, bg, render.Style{ .bold = true });

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
        const event = try app.pollInputOnce();

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
                .resize => {},
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
