// Input test: logs keyboard, mouse, and resize events from InputHandler.

const std = @import("std");
const zit = @import("zit");
const memory = zit.memory;

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

    // Initialize input handler with memory manager
    var input_handler = zit.input.InputHandler.init(memory_manager.getArenaAllocator(), &term);

    // Enable raw mode and mouse tracking
    try term.enableRawMode();
    try input_handler.enableMouse();
    defer {
        input_handler.disableMouse() catch {};
        term.disableRawMode() catch {};
    }

    // Clear screen
    try term.clear();

    // Display instructions
    var stdout_file = std.fs.File.stdout();
    var stdout_buffer: [512]u8 = undefined;
    var writer = stdout_file.writer(&stdout_buffer).interface;
    try writer.writeAll("Input Handler Test\n\n");
    try writer.writeAll("Press keys to see their events (press 'q' to quit)\n");
    try writer.writeAll("Click or move mouse to see mouse events\n\n");

    // Event display area
    try term.moveCursor(0, 5);
    try writer.writeAll("Last event: None\n");

    // Stats area
    try term.moveCursor(0, 7);
    try writer.writeAll("Stats:\n");
    try writer.writeAll("  Key events: 0\n");
    try writer.writeAll("  Mouse events: 0\n");
    try writer.writeAll("  Resize events: 0\n");

    // Enable chord mode
    input_handler.chord_mode = true;
    try writer.writeAll("  Chord mode: enabled\n");

    // Event counters
    var key_count: u32 = 0;
    var mouse_count: u32 = 0;
    var resize_count: u32 = 0;

    // Main event loop
    while (true) {
        // Poll for events with a 100ms timeout
        const event = try input_handler.pollEvent(100);

        if (event) |e| {
            // Clear the event display area
            try term.moveCursor(0, 5);
            try writer.writeAll("Last event: ");

            switch (e) {
                .key => |key| {
                    key_count += 1;

                    // Display key information
                    if (key.isSpecialKey()) {
                        const key_name = try key.getName(memory_manager.getArenaAllocator());
                        defer memory_manager.resetArena();

                        const modifiers = try key.modifiers.toString(memory_manager.getArenaAllocator());
                        defer memory_manager.resetArena();

                        try writer.print("Key: {s}{s}", .{ modifiers, key_name });
                    } else {
                        const modifiers = try key.modifiers.toString(memory_manager.getArenaAllocator());
                        defer memory_manager.resetArena();

                        if (key.isPrintable()) {
                            try writer.print("Key: {s}'{c}' (ASCII: {d})", .{ modifiers, @as(u8, @intCast(key.key)), key.key });
                        } else {
                            try writer.print("Key: {s}(ASCII: {d})", .{ modifiers, key.key });
                        }
                    }

                    // Check for quit
                    if (key.key == 'q' and !key.modifiers.ctrl and !key.modifiers.alt) {
                        break;
                    }
                },
                .mouse => |mouse| {
                    mouse_count += 1;

                    // Display mouse information
                    try writer.print("Mouse: {s} at ({d},{d}) button {d}", .{
                        @tagName(mouse.action),
                        mouse.x,
                        mouse.y,
                        mouse.button,
                    });
                },
                .resize => |resize| {
                    resize_count += 1;

                    // Display resize information
                    try writer.print("Resize: {d}x{d}", .{ resize.width, resize.height });

                    // Clear screen on resize
                    try term.clear();

                    // Redraw instructions
                    try term.moveCursor(0, 0);
                    try writer.writeAll("Input Handler Test\n\n");
                    try writer.writeAll("Press keys to see their events (press 'q' to quit)\n");
                    try writer.writeAll("Click or move mouse to see mouse events\n\n");
                },
                .unknown => {
                    try writer.writeAll("Unknown event");
                },
            }

            // Clear to end of line
            try writer.writeAll("                                        ");

            // Update stats
            try term.moveCursor(0, 8);
            try writer.print("  Key events: {d}    ", .{key_count});
            try term.moveCursor(0, 9);
            try writer.print("  Mouse events: {d}    ", .{mouse_count});
            try term.moveCursor(0, 10);
            try writer.print("  Resize events: {d}    ", .{resize_count});
        }
    }

    // Clean up
    try term.clear();
    try term.moveCursor(0, 0);
}
