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

/// Write all bytes to an explicit file handle without taking ownership of it.
pub fn fileWriteAll(handle: std.Io.File.Handle, bytes: []const u8) !void {
    const io = std.Io.Threaded.global_single_threaded.io();
    const file = std.Io.File{
        .handle = handle,
        .flags = .{ .nonblocking = false },
    };
    try file.writeStreamingAll(io, bytes);
}

pub fn getEnv(allocator: std.mem.Allocator, key: []const u8) !?[]u8 {
    const environ = if (comptime builtin.is_test)
        std.testing.environ
    else
        std.Io.Threaded.global_single_threaded.environ.process_environ;
    return environ.getAlloc(allocator, key) catch |err| switch (err) {
        error.EnvironmentVariableMissing => null,
        else => |e| return e,
    };
}

pub fn sleepMillisChecked(ms: u64) !void {
    const io = std.Io.Threaded.global_single_threaded.io();
    try std.Io.sleep(io, .{ .nanoseconds = @as(i96, ms) * std.time.ns_per_ms }, .awake);
}

pub fn sleepMillis(ms: u64) void {
    sleepMillisChecked(ms) catch return;
}

test "sleepMillisChecked accepts zero-duration sleep" {
    try sleepMillisChecked(0);
}

test "getEnv reads and owns startup environment values" {
    const allocator = std.testing.allocator;
    const path = try getEnv(allocator, "PATH") orelse return error.SkipZigTest;
    defer allocator.free(path);

    try std.testing.expect(path.len > 0);
    try std.testing.expect(try getEnv(allocator, "ZIT_TEST_ENVIRONMENT_VALUE_THAT_MUST_NOT_EXIST") == null);
}
