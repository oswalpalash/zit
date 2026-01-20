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

    // Clear screen
    try term.clear();

    // Draw UI elements
    drawUI(&renderer);

    // Render initial state
    try renderer.render();

    // Main event loop
    while (true) {
        // Poll for events with a 100ms timeout
        const event = try input_handler.pollEvent(100);

        if (event) |e| {
            switch (e) {
                .key => |key| {
                    // Exit on 'q' key
                    if (key.key == 'q' and !key.modifiers.ctrl and !key.modifiers.alt) {
                        break;
                    }

                    // Handle other keys
                    handleKeyEvent(&renderer, key);
                },
                .mouse => |mouse| {
                    handleMouseEvent(&renderer, mouse);
                },
                .resize => |resize| {
                    // Resize renderer
                    try renderer.resize(resize.width, resize.height);

                    // Redraw UI
                    drawUI(&renderer);
                },
                .unknown => {},
            }

            // Render updated state
            try renderer.render();
        }
    }

    // Clean up
    try term.clear();
    try term.moveCursor(0, 0);
}

fn drawUI(renderer: *zit.render.Renderer) void {
    // Clear the buffer
    renderer.back.clear();

    // Get buffer dimensions
    const width = renderer.back.width;
    const height = renderer.back.height;

    // Draw title
    const title = "Zit Rendering Test";
    const title_len = @as(u16, @intCast(title.len));
    const title_x = if (width > title_len)
        (width - title_len) / 2
    else
        0;

    renderer.drawStr(title_x, 0, title, zit.render.Color.named(zit.render.NamedColor.bright_white), zit.render.Color.named(zit.render.NamedColor.blue), zit.render.Style.init(true, false, false));

    // Draw border around the screen
    renderer.drawBox(0, 1, width, height - 1, zit.render.BorderStyle.single, zit.render.Color.named(zit.render.NamedColor.white), zit.render.Color.named(zit.render.NamedColor.default), zit.render.Style{});

    // Draw color palette
    drawColorPalette(renderer, 2, 3);

    // Draw text styles
    drawTextStyles(renderer, 2, 12);

    // Draw box styles
    drawBoxStyles(renderer, 40, 3);

    // Draw RGB color gradient
    drawRgbGradient(renderer, 40, 12, 30, 5);

    // Draw instructions
    renderer.drawStr(2, height - 2, "Press 'q' to quit", zit.render.Color.named(zit.render.NamedColor.bright_white), zit.render.Color.named(zit.render.NamedColor.default), zit.render.Style{});
}

fn drawColorPalette(renderer: *zit.render.Renderer, x: u16, y: u16) void {
    // Draw title
    renderer.drawStr(x, y, "Standard Colors:", zit.render.Color.named(zit.render.NamedColor.bright_white), zit.render.Color.named(zit.render.NamedColor.default), zit.render.Style.init(true, false, false));

    // Draw standard colors
    const colors = [_]zit.render.NamedColor{
        .black,        .red,        .green,        .yellow,        .blue,        .magenta,        .cyan,        .white,
        .bright_black, .bright_red, .bright_green, .bright_yellow, .bright_blue, .bright_magenta, .bright_cyan, .bright_white,
    };

    // Draw foreground colors
    renderer.drawStr(x, y + 1, "Foreground: ", zit.render.Color.named(zit.render.NamedColor.default), zit.render.Color.named(zit.render.NamedColor.default), zit.render.Style{});

    for (colors, 0..) |color, i| {
        const col_x = x + 12 + @as(u16, @intCast(i)) * 3;
        if (i == 8) { // Start a new row for bright colors
            renderer.drawStr(x, y + 2, "            ", zit.render.Color.named(zit.render.NamedColor.default), zit.render.Color.named(zit.render.NamedColor.default), zit.render.Style{});
        }
        const row_y = if (i < 8) y + 1 else y + 2;
        const col_x_adjusted = if (i < 8) col_x else x + 12 + @as(u16, @intCast(i - 8)) * 3;

        renderer.drawStr(col_x_adjusted, row_y, "A", zit.render.Color.named(color), zit.render.Color.named(zit.render.NamedColor.default), zit.render.Style{});
    }

    // Draw background colors
    renderer.drawStr(x, y + 4, "Background: ", zit.render.Color.named(zit.render.NamedColor.default), zit.render.Color.named(zit.render.NamedColor.default), zit.render.Style{});

    for (colors, 0..) |color, i| {
        const col_x = x + 12 + @as(u16, @intCast(i)) * 3;
        if (i == 8) { // Start a new row for bright colors
            renderer.drawStr(x, y + 5, "            ", zit.render.Color.named(zit.render.NamedColor.default), zit.render.Color.named(zit.render.NamedColor.default), zit.render.Style{});
        }
        const row_y = if (i < 8) y + 4 else y + 5;
        const col_x_adjusted = if (i < 8) col_x else x + 12 + @as(u16, @intCast(i - 8)) * 3;

        renderer.drawStr(col_x_adjusted, row_y, "A", zit.render.Color.named(zit.render.NamedColor.white), zit.render.Color.named(color), zit.render.Style{});
    }
}

fn drawTextStyles(renderer: *zit.render.Renderer, x: u16, y: u16) void {
    // Draw title
    renderer.drawStr(x, y, "Text Styles:", zit.render.Color.named(zit.render.NamedColor.bright_white), zit.render.Color.named(zit.render.NamedColor.default), zit.render.Style.init(true, false, false));

    // Draw normal text
    renderer.drawStr(x, y + 1, "Normal Text", zit.render.Color.named(zit.render.NamedColor.default), zit.render.Color.named(zit.render.NamedColor.default), zit.render.Style{});

    // Draw bold text
    renderer.drawStr(x, y + 2, "Bold Text", zit.render.Color.named(zit.render.NamedColor.default), zit.render.Color.named(zit.render.NamedColor.default), zit.render.Style.init(true, false, false));

    // Draw italic text
    renderer.drawStr(x, y + 3, "Italic Text", zit.render.Color.named(zit.render.NamedColor.default), zit.render.Color.named(zit.render.NamedColor.default), zit.render.Style.init(false, true, false));

    // Draw underlined text
    renderer.drawStr(x, y + 4, "Underlined Text", zit.render.Color.named(zit.render.NamedColor.default), zit.render.Color.named(zit.render.NamedColor.default), zit.render.Style.init(false, false, true));

    // Draw combined styles
    renderer.drawStr(x, y + 5, "Combined Styles", zit.render.Color.named(zit.render.NamedColor.default), zit.render.Color.named(zit.render.NamedColor.default), zit.render.Style.init(true, true, true));

    // Draw blinking text
    var blink_style = zit.render.Style{};
    blink_style.blink = true;
    renderer.drawStr(x, y + 6, "Blinking Text", zit.render.Color.named(zit.render.NamedColor.default), zit.render.Color.named(zit.render.NamedColor.default), blink_style);

    // Draw reversed text
    var reverse_style = zit.render.Style{};
    reverse_style.reverse = true;
    renderer.drawStr(x, y + 7, "Reversed Text", zit.render.Color.named(zit.render.NamedColor.default), zit.render.Color.named(zit.render.NamedColor.default), reverse_style);

    // Draw strikethrough text
    var strike_style = zit.render.Style{};
    strike_style.strikethrough = true;
    renderer.drawStr(x, y + 8, "Strikethrough Text", zit.render.Color.named(zit.render.NamedColor.default), zit.render.Color.named(zit.render.NamedColor.default), strike_style);
}

fn drawBoxStyles(renderer: *zit.render.Renderer, x: u16, y: u16) void {
    // Draw title
    renderer.drawStr(x, y, "Box Styles:", zit.render.Color.named(zit.render.NamedColor.bright_white), zit.render.Color.named(zit.render.NamedColor.default), zit.render.Style.init(true, false, false));

    // Draw single line box
    renderer.drawBox(x, y + 1, 15, 3, zit.render.BorderStyle.single, zit.render.Color.named(zit.render.NamedColor.white), zit.render.Color.named(zit.render.NamedColor.default), zit.render.Style{});
    renderer.drawStr(x + 2, y + 2, "Single", zit.render.Color.named(zit.render.NamedColor.white), zit.render.Color.named(zit.render.NamedColor.default), zit.render.Style{});

    // Draw double line box
    renderer.drawBox(x + 16, y + 1, 15, 3, zit.render.BorderStyle.double, zit.render.Color.named(zit.render.NamedColor.white), zit.render.Color.named(zit.render.NamedColor.default), zit.render.Style{});
    renderer.drawStr(x + 18, y + 2, "Double", zit.render.Color.named(zit.render.NamedColor.white), zit.render.Color.named(zit.render.NamedColor.default), zit.render.Style{});

    // Draw rounded box
    renderer.drawBox(x, y + 5, 15, 3, zit.render.BorderStyle.rounded, zit.render.Color.named(zit.render.NamedColor.white), zit.render.Color.named(zit.render.NamedColor.default), zit.render.Style{});
    renderer.drawStr(x + 2, y + 6, "Rounded", zit.render.Color.named(zit.render.NamedColor.white), zit.render.Color.named(zit.render.NamedColor.default), zit.render.Style{});

    // Draw thick box
    renderer.drawBox(x + 16, y + 5, 15, 3, zit.render.BorderStyle.thick, zit.render.Color.named(zit.render.NamedColor.white), zit.render.Color.named(zit.render.NamedColor.default), zit.render.Style{});
    renderer.drawStr(x + 18, y + 6, "Thick", zit.render.Color.named(zit.render.NamedColor.white), zit.render.Color.named(zit.render.NamedColor.default), zit.render.Style{});
}

fn drawRgbGradient(renderer: *zit.render.Renderer, x: u16, y: u16, width: u16, height: u16) void {
    // Draw title
    renderer.drawStr(x, y, "RGB Color Gradient:", zit.render.Color.named(zit.render.NamedColor.bright_white), zit.render.Color.named(zit.render.NamedColor.default), zit.render.Style.init(true, false, false));

    // Draw RGB gradient
    for (0..@min(width, renderer.back.width - x)) |i| {
        const r: u8 = @intCast(@min(255, (i * 255) / width));

        for (0..@min(height, renderer.back.height - y - 1)) |j| {
            const g: u8 = @intCast(@min(255, (j * 255) / height));
            const b: u8 = @intCast(@min(255, ((i + j) * 255) / (width + height)));

            renderer.drawChar(x + @as(u16, @intCast(i)), y + 1 + @as(u16, @intCast(j)), '▒', zit.render.Color.rgb(r, g, b), zit.render.Color.named(zit.render.NamedColor.default), zit.render.Style{});
        }
    }
}

fn handleKeyEvent(renderer: *zit.render.Renderer, key: zit.input.KeyEvent) void {
    // This is a placeholder for key event handling
    // In a real application, we would update the UI based on key events
    _ = renderer;
    _ = key;
}

fn handleMouseEvent(renderer: *zit.render.Renderer, mouse: zit.input.MouseEvent) void {
    // This is a placeholder for mouse event handling
    // In a real application, we would update the UI based on mouse events
    _ = renderer;
    _ = mouse;
}
