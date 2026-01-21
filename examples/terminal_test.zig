// Terminal test: explores raw terminal capabilities, colors, and cursor movement.

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

    // Clear screen
    try term.clear();

    // Display terminal information
    var stdout_file = std.fs.File.stdout();
    var stdout_buffer: [512]u8 = undefined;
    var writer = stdout_file.writer(&stdout_buffer).interface;
    try writer.print("Terminal size: {d}x{d}\n", .{ term.width, term.height });
    try writer.print("256 colors support: {}\n", .{term.supports256Colors()});
    try writer.print("True color support: {}\n\n", .{term.supportsTrueColor()});

    // Enable raw mode
    try term.enableRawMode();
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

    // Input loop
    const stdin_file = std.fs.File.stdin();

    while (true) {
        var byte_buf: [1]u8 = undefined;
        const read = stdin_file.read(&byte_buf) catch continue;
        if (read == 0) continue;
        const byte = byte_buf[0];

        try term.moveCursor(0, term.height - 1);
        try writer.print("Key pressed: '{c}' (ASCII: {d})   ", .{ byte, byte });

        if (byte == 'q') break;
    }

    // Clean up
    try term.resetFormatting();
    try term.clear();
    try term.moveCursor(0, 0);
}
