// Terminal test: explores raw terminal capabilities, colors, and cursor movement.

const std = @import("std");
const zit = @import("zit");

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    // Initialize terminal
    var term = (try zit.terminal.initInteractive(allocator, "terminal-test")) orelse return;
    defer term.deinit() catch {};

    // Clear screen
    try term.clear();

    // Display terminal information
    const io = std.Io.Threaded.global_single_threaded.io();
    var stdout_file = std.Io.File.stdout();
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = stdout_file.writerStreaming(io, &stdout_buffer);
    var writer = &stdout_writer.interface;
    defer stdout_writer.flush() catch {};
    try writer.print("Terminal size: {d}x{d}\n", .{ term.width, term.height });
    try writer.print("256 colors support: {}\n", .{term.supports256Colors()});
    try writer.print("True color support: {}\n\n", .{term.supportsTrueColor()});

    // Enable raw mode
    try term.enableRawMode();
    defer term.disableRawMode() catch {};
    try writer.writeAll("Raw mode enabled. Press 'q' to quit.\n\n");

    // Demonstrate cursor movement and colors
    try writer.writeAll("Testing cursor movement and colors:\n");

    // Move cursor and show colored text
    try term.moveCursor(5, 10);
    try term.setForegroundColor(196); // Red
    try writer.writeAll("This text is red");

    try term.moveCursor(5, 11);
    try term.setForegroundColor(46); // Green
    try writer.writeAll("This text is green");

    try term.moveCursor(5, 12);
    try term.setForegroundColor(21); // Blue
    try writer.writeAll("This text is blue");

    // Test RGB colors if supported
    if (term.supportsTrueColor()) {
        try term.moveCursor(5, 14);
        try term.setRgbColor(255, 100, 0, true); // Orange-ish
        try writer.writeAll("This text uses RGB color (255,100,0)");
    }

    // Test text styles
    try term.moveCursor(5, 16);
    try term.resetFormatting();
    try term.setStyle(true, false, false);
    try writer.writeAll("Bold text");

    try term.moveCursor(5, 17);
    try term.resetFormatting();
    try term.setStyle(false, true, false);
    try writer.writeAll("Italic text");

    try term.moveCursor(5, 18);
    try term.resetFormatting();
    try term.setStyle(false, false, true);
    try writer.writeAll("Underlined text");

    try term.moveCursor(5, 19);
    try term.resetFormatting();
    try term.setStyle(true, true, true);
    try writer.writeAll("Bold, italic, and underlined text");

    // Reset formatting
    try term.resetFormatting();

    // Move cursor to bottom for input prompt
    try term.moveCursor(0, term.height - 2);
    try writer.writeAll("Press any key to see its ASCII value (press 'q' to quit)");
    try stdout_writer.flush();

    var input_handler = zit.input.InputHandler.init(allocator, &term);
    while (true) {
        const event = try input_handler.pollEvent(100) orelse continue;
        switch (event) {
            .key => |key| {
                try term.moveCursor(0, if (term.height > 0) term.height - 1 else 0);
                try writer.print("Key codepoint: {d}   ", .{key.key});
                try stdout_writer.flush();

                if (key.key == 'q') break;
            },
            .resize => |resize| {
                const prompt_y: u16 = if (resize.height > 1) resize.height - 2 else 0;
                const status_y: u16 = if (resize.height > 0) resize.height - 1 else 0;
                try term.moveCursor(0, prompt_y);
                try writer.writeAll("Press any key to see its codepoint (press 'q' to quit)");
                try term.moveCursor(0, status_y);
                try writer.print("resize: {d}x{d}   ", .{ resize.width, resize.height });
                try stdout_writer.flush();
            },
            else => {},
        }
    }

    // Clean up
    try term.resetFormatting();
    try term.clear();
    try term.moveCursor(0, 0);
}
