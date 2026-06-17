const std = @import("std");
const builtin = @import("builtin");

pub const Mutex = struct {
    inner: std.Io.Mutex = .init,

    pub fn lock(self: *Mutex) void {
        const io = std.Io.Threaded.global_single_threaded.io();
        self.inner.lockUncancelable(io);
    }

    pub fn unlock(self: *Mutex) void {
        const io = std.Io.Threaded.global_single_threaded.io();
        self.inner.unlock(io);
    }
};

pub fn nowMillis() i64 {
    const io = std.Io.Threaded.global_single_threaded.io();
    return std.Io.Clock.real.now(io).toMilliseconds();
}

pub fn nowNanos() i96 {
    const io = std.Io.Threaded.global_single_threaded.io();
    return std.Io.Clock.awake.now(io).toNanoseconds();
}

pub fn stdoutWriteAll(bytes: []const u8) !void {
    const io = std.Io.Threaded.global_single_threaded.io();
    try std.Io.File.stdout().writeStreamingAll(io, bytes);
}

pub fn getEnv(allocator: std.mem.Allocator, key: []const u8) !?[]u8 {
    if (builtin.os.tag == .windows) {
        return std.process.Environ.getAlloc(.{ .block = .global }, allocator, key) catch |err| switch (err) {
            error.EnvironmentVariableMissing => null,
            else => |e| return e,
        };
    }

    if (!builtin.link_libc or !@hasDecl(std.c, "environ")) return null;

    var index: usize = 0;
    while (std.c.environ[index]) |entry_ptr| : (index += 1) {
        const entry = std.mem.span(entry_ptr);
        if (entry.len <= key.len or entry[key.len] != '=') continue;
        if (std.mem.eql(u8, entry[0..key.len], key)) {
            return try allocator.dupe(u8, entry[key.len + 1 ..]);
        }
    }
    return null;
}

pub fn sleepMillis(ms: u64) void {
    const io = std.Io.Threaded.global_single_threaded.io();
    std.Io.sleep(io, .{ .nanoseconds = @as(i96, ms) * std.time.ns_per_ms }, .awake) catch {};
}
