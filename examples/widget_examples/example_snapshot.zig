const std = @import("std");
const zit = @import("zit");

pub fn isMode(init: std.process.Init, allocator: std.mem.Allocator) !bool {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args.deinit();

    _ = args.skip();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--snapshot")) return true;
    }
    return false;
}

pub fn print(allocator: std.mem.Allocator, mock: *zit.testing.MockTerminal) !void {
    var snap = try mock.snapshot(allocator);
    defer snap.deinit(allocator);
    try snap.expectWellFormed();
    std.debug.print("{s}", .{snap.text()});
}
