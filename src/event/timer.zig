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

        const entry = TimerEntry{
            .id = handle.id,
            .due_ms = now_ms + delay_ms,
            .interval_ms = interval_ms,
            .callback = callback,
            .ctx = ctx,
        };

        try self.timers.append(self.allocator, entry);
        self.next_id += 1;
        return handle;
    }

    pub fn cancel(self: *TimerManager, handle: TimerHandle) bool {
        if (self.findTimerIndex(handle.id)) |idx| {
            _ = self.timers.orderedRemove(idx);
            return true;
        }
        return false;
    }

    /// Tick the timer manager using a monotonically increasing time in milliseconds.
    pub fn tick(self: *TimerManager, now_ms: u64) void {
        var i: usize = 0;
        while (i < self.timers.items.len) {
            const timer = self.timers.items[i];
            if (now_ms >= timer.due_ms) {
                timer.callback(timer.ctx);
                const idx = self.findTimerIndex(timer.id) orelse continue;

                if (timer.interval_ms) |interval| {
                    var current = self.timers.items[idx];
                    current.due_ms = now_ms + interval;
                    self.timers.items[idx] = current;
                    i = idx + 1;
                } else {
                    _ = self.timers.orderedRemove(idx);
                    i = idx;
                }
            } else {
                i += 1;
            }
        }
    }

    fn findTimerIndex(self: *TimerManager, id: u32) ?usize {
        for (self.timers.items, 0..) |timer, idx| {
            if (timer.id == id) return idx;
        }
        return null;
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

test "timer schedule preserves next id on allocation failure" {
    const alloc = std.testing.allocator;
    var manager = TimerManager.init(alloc);
    defer manager.deinit();

    const onFire = struct {
        fn cb(_: ?*anyopaque) void {}
    }.cb;

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = manager.allocator;
    manager.allocator = failing.allocator();
    defer manager.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, manager.schedule(0, 10, null, onFire, null));
    try std.testing.expectEqual(@as(u32, 1), manager.next_id);
    try std.testing.expectEqual(@as(usize, 0), manager.timers.items.len);
}

test "one shot timer self cancel preserves following timers" {
    const alloc = std.testing.allocator;
    var manager = TimerManager.init(alloc);
    defer manager.deinit();

    const Ctx = struct {
        manager: *TimerManager,
        handle: TimerHandle = .{ .id = 0 },
        fired: usize = 0,
    };

    const SelfCancel = struct {
        fn cb(raw: ?*anyopaque) void {
            const ctx = @as(*Ctx, @ptrCast(@alignCast(raw.?)));
            ctx.fired += 1;
            _ = ctx.manager.cancel(ctx.handle);
        }
    }.cb;

    const Count = struct {
        fn cb(raw: ?*anyopaque) void {
            const fired = @as(*usize, @ptrCast(@alignCast(raw.?)));
            fired.* += 1;
        }
    }.cb;

    var ctx = Ctx{ .manager = &manager };
    ctx.handle = try manager.schedule(0, 5, null, SelfCancel, @ptrCast(&ctx));
    var later_fired: usize = 0;
    const later = try manager.schedule(0, 10, null, Count, @ptrCast(&later_fired));

    manager.tick(5);
    try std.testing.expectEqual(@as(usize, 1), ctx.fired);
    try std.testing.expectEqual(@as(usize, 1), manager.timers.items.len);
    try std.testing.expectEqual(later.id, manager.timers.items[0].id);

    manager.tick(10);
    try std.testing.expectEqual(@as(usize, 1), later_fired);
    try std.testing.expectEqual(@as(usize, 0), manager.timers.items.len);
}

test "repeating timer self cancel is not rearmed" {
    const alloc = std.testing.allocator;
    var manager = TimerManager.init(alloc);
    defer manager.deinit();

    const Ctx = struct {
        manager: *TimerManager,
        handle: TimerHandle = .{ .id = 0 },
        fired: usize = 0,
    };

    const SelfCancel = struct {
        fn cb(raw: ?*anyopaque) void {
            const ctx = @as(*Ctx, @ptrCast(@alignCast(raw.?)));
            ctx.fired += 1;
            _ = ctx.manager.cancel(ctx.handle);
        }
    }.cb;

    var ctx = Ctx{ .manager = &manager };
    ctx.handle = try manager.schedule(0, 5, 5, SelfCancel, @ptrCast(&ctx));

    manager.tick(5);
    try std.testing.expectEqual(@as(usize, 1), ctx.fired);
    try std.testing.expectEqual(@as(usize, 0), manager.timers.items.len);

    manager.tick(10);
    try std.testing.expectEqual(@as(usize, 1), ctx.fired);
    try std.testing.expectEqual(@as(usize, 0), manager.timers.items.len);
}
