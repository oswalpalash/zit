const std = @import("std");

pub const TimerCallback = *const fn (ctx: ?*anyopaque) void;

pub const TimerHandle = struct {
    id: u32,
};

const TimerEntry = struct {
    id: u32,
    due_ms: u64,
    interval_ms: ?u64,
    callback: TimerCallback,
    ctx: ?*anyopaque,
};

/// Basic timer manager for scheduling delayed or repeating callbacks on the application loop.
pub const TimerManager = struct {
    allocator: std.mem.Allocator,
    timers: std.ArrayList(TimerEntry),
    next_id: u32 = 1,

    pub fn init(allocator: std.mem.Allocator) TimerManager {
        return TimerManager{
            .allocator = allocator,
            .timers = std.ArrayList(TimerEntry).empty,
        };
    }

    pub fn deinit(self: *TimerManager) void {
        self.timers.deinit(self.allocator);
    }

    pub fn schedule(self: *TimerManager, now_ms: u64, delay_ms: u64, interval_ms: ?u64, callback: TimerCallback, ctx: ?*anyopaque) !TimerHandle {
        const handle = TimerHandle{ .id = self.next_id };
        self.next_id += 1;

        const entry = TimerEntry{
            .id = handle.id,
            .due_ms = now_ms + delay_ms,
            .interval_ms = interval_ms,
            .callback = callback,
            .ctx = ctx,
        };

        try self.timers.append(self.allocator, entry);
        return handle;
    }

    pub fn cancel(self: *TimerManager, handle: TimerHandle) bool {
        for (self.timers.items, 0..) |timer, idx| {
            if (timer.id == handle.id) {
                _ = self.timers.orderedRemove(idx);
                return true;
            }
        }
        return false;
    }

    /// Tick the timer manager using a monotonically increasing time in milliseconds.
    pub fn tick(self: *TimerManager, now_ms: u64) void {
        var i: usize = 0;
        while (i < self.timers.items.len) {
            var timer = self.timers.items[i];
            if (now_ms >= timer.due_ms) {
                timer.callback(timer.ctx);

                if (timer.interval_ms) |interval| {
                    timer.due_ms = now_ms + interval;
                    self.timers.items[i] = timer;
                    i += 1;
                } else {
                    _ = self.timers.orderedRemove(i);
                }
            } else {
                i += 1;
            }
        }
    }
};

test "timer manager fires one-shot and repeating timers" {
    const alloc = std.testing.allocator;
    var manager = TimerManager.init(alloc);
    defer manager.deinit();

    var fired: usize = 0;
    const onFire = struct {
        fn cb(ctx: ?*anyopaque) void {
            const counter = @as(*usize, @ptrCast(@alignCast(ctx.?)));
            counter.* += 1;
        }
    }.cb;

    var repeat_fired: usize = 0;

    _ = try manager.schedule(0, 10, null, onFire, @ptrCast(&fired));
    _ = try manager.schedule(0, 5, 5, onFire, @ptrCast(&repeat_fired));

    manager.tick(5);
    try std.testing.expectEqual(@as(usize, 0), fired);
    try std.testing.expectEqual(@as(usize, 1), repeat_fired);

    manager.tick(10);
    try std.testing.expectEqual(@as(usize, 1), fired);
    try std.testing.expectEqual(@as(usize, 2), repeat_fired);

    manager.tick(15);
    try std.testing.expectEqual(@as(usize, 3), repeat_fired);
}
