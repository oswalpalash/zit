const std = @import("std");
const zit = @import("zit");

pub fn finish(init: std.process.Init, allocator: std.mem.Allocator, example_name: []const u8, text: []const u8) !void {
    const mode = try snapshotMode(init, allocator);
    if (mode != .interactive) {
        std.debug.print("{s}", .{text});
        return;
    }

    try runText(allocator, example_name, text);
}

pub fn finishFrames(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    example_name: []const u8,
    snapshot_text: []const u8,
    terminal_frame: []const u8,
) !void {
    switch (try snapshotMode(init, allocator)) {
        .text => {
            std.debug.print("{s}", .{snapshot_text});
            return;
        },
        .ansi => {
            std.debug.print("{s}", .{terminal_frame});
            return;
        },
        .interactive => {},
    }

    try runText(allocator, example_name, terminal_frame);
}

const SnapshotMode = enum {
    interactive,
    text,
    ansi,
};

fn snapshotMode(init: std.process.Init, allocator: std.mem.Allocator) !SnapshotMode {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args.deinit();

    _ = args.skip();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--snapshot")) return .text;
        if (std.mem.eql(u8, arg, "--ansi-snapshot")) return .ansi;
    }
    return .interactive;
}

fn writeFrame(term: *zit.terminal.Terminal, text: []const u8) !void {
    const chunk_size = 512;
    var offset: usize = 0;
    while (offset < text.len) {
        const end = @min(offset + chunk_size, text.len);
        term.writeUtf8(text[offset..end]) catch |err| switch (err) {
            error.WouldBlock => {
                const io = std.Io.Threaded.global_single_threaded.io();
                try std.Io.sleep(io, .{ .nanoseconds = 2 * std.time.ns_per_ms }, .awake);
                continue;
            },
            else => return err,
        };
        offset = end;
    }
}

fn writeResizeStatus(term: *zit.terminal.Terminal) !void {
    if (term.height == 0) return;

    var line_buf: [96]u8 = undefined;
    const line = try std.fmt.bufPrint(&line_buf, "resize: {d}x{d} | q quit", .{ term.width, term.height });
    try term.moveCursor(0, term.height - 1);
    try term.writeUtf8(line);
}

fn runText(allocator: std.mem.Allocator, example_name: []const u8, text: []const u8) !void {
    var term = (try zit.terminal.initInteractive(allocator, example_name)) orelse return;
    defer term.deinit() catch |err| zit.terminal.reportCleanupError("term.deinit", err);

    var input_handler = zit.input.InputHandler.init(allocator, &term);

    try term.enterAlternateScreen();
    defer term.exitAlternateScreen() catch |err| zit.terminal.reportCleanupError("term.exitAlternateScreen", err);

    try term.enableRawMode();
    defer term.disableRawMode() catch |err| zit.terminal.reportCleanupError("term.disableRawMode", err);

    try term.hideCursor();
    defer term.showCursor() catch |err| zit.terminal.reportCleanupError("term.showCursor", err);

    var running = true;
    var dirty = true;
    while (running) {
        if (try term.takeResize()) |_| {
            dirty = true;
        }

        if (dirty) {
            try term.clear();
            try term.moveCursor(0, 0);
            try writeFrame(&term, text);
            try writeResizeStatus(&term);
            dirty = false;
        }

        if (try input_handler.pollEvent(100)) |event| {
            switch (event) {
                .key => |key| {
                    if (key.key == 'q' or key.key == 'Q' or key.key == zit.input.KeyCode.ESCAPE) {
                        running = false;
                    }
                },
                .resize => dirty = true,
                else => {},
            }
        }
    }
}
