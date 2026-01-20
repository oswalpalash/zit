const std = @import("std");

pub const AnimationEasingFn = *const fn (t: f32) f32;

/// Common easing helpers.
pub const Easing = struct {
    pub fn linear(t: f32) f32 {
        return t;
    }

    pub fn easeInOutQuad(t: f32) f32 {
        const clamped = std.math.clamp(t, 0, 1);
        return if (clamped < 0.5)
            2 * clamped * clamped
        else
            1 - std.math.pow(f32, -2 * clamped + 2, 2) / 2;
    }
};

pub const AnimationSpec = struct {
    duration_ms: u64,
    repeat: bool = false,
    yoyo: bool = false,
    easing: AnimationEasingFn = Easing.linear,
    on_update: *const fn (progress: f32, ctx: ?*anyopaque) void,
    on_complete: ?*const fn (?*anyopaque) void = null,
    context: ?*anyopaque = null,
};

const AnimationState = struct {
    id: u32,
    elapsed_ms: u64 = 0,
    direction: i8 = 1,
    spec: AnimationSpec,
};

pub const AnimationHandle = struct {
    id: u32,
};

/// Drives scheduled animations; tick this each frame from the application loop.
pub const Animator = struct {
    allocator: std.mem.Allocator,
    animations: std.ArrayList(AnimationState),
    next_id: u32 = 1,

    pub fn init(allocator: std.mem.Allocator) Animator {
        return Animator{
            .allocator = allocator,
            .animations = std.ArrayList(AnimationState).empty,
        };
    }

    pub fn deinit(self: *Animator) void {
        self.animations.deinit(self.allocator);
    }

    pub fn add(self: *Animator, spec: AnimationSpec) !AnimationHandle {
        const id = self.next_id;
        self.next_id += 1;
        try self.animations.append(self.allocator, AnimationState{ .id = id, .spec = spec });
        return AnimationHandle{ .id = id };
    }

    pub fn cancel(self: *Animator, handle: AnimationHandle) bool {
        for (self.animations.items, 0..) |anim, idx| {
            if (anim.id == handle.id) {
                _ = self.animations.orderedRemove(idx);
                return true;
            }
        }
        return false;
    }

    /// Advance animations by `delta_ms` milliseconds.
    pub fn tick(self: *Animator, delta_ms: u64) void {
        if (delta_ms == 0 or self.animations.items.len == 0) return;

        var i: usize = 0;
        while (i < self.animations.items.len) {
            var anim = &self.animations.items[i];
            anim.elapsed_ms += delta_ms;

            const duration = if (anim.spec.duration_ms == 0) 1 else anim.spec.duration_ms;
            var raw_progress = @as(f32, @floatFromInt(anim.elapsed_ms)) / @as(f32, @floatFromInt(duration));

            if (raw_progress > 1) raw_progress = 1;
            const eased = anim.spec.easing(raw_progress);
            const directional = if (anim.direction == 1) eased else (1 - eased);
            anim.spec.on_update(directional, anim.spec.context);

            if (anim.elapsed_ms >= duration) {
                if (anim.spec.yoyo and anim.direction == 1) {
                    anim.direction = -1;
                    anim.elapsed_ms = 0;
                    i += 1;
                    continue;
                }

                if (anim.spec.repeat) {
                    anim.elapsed_ms = 0;
                    anim.direction = 1;
                    i += 1;
                    continue;
                }

                if (anim.spec.on_complete) |cb| {
                    cb(anim.spec.context);
                }
                _ = self.animations.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }
};

test "animator runs callbacks and completes" {
    const alloc = std.testing.allocator;
    var animator = Animator.init(alloc);
    defer animator.deinit();

    var updates: usize = 0;
    var completed: usize = 0;
    const Counters = struct {
        updates: *usize,
        completed: *usize,
    };
    const counts = Counters{ .updates = &updates, .completed = &completed };

    const onUpdate = struct {
        fn callback(_: f32, ctx: ?*anyopaque) void {
            const counters = @as(*Counters, @ptrCast(@alignCast(ctx.?)));
            counters.updates.* += 1;
        }
    }.callback;

    const onComplete = struct {
        fn callback(ctx: ?*anyopaque) void {
            const counters = @as(*Counters, @ptrCast(@alignCast(ctx.?)));
            counters.completed.* += 1;
        }
    }.callback;

    _ = try animator.add(AnimationSpec{
        .duration_ms = 100,
        .on_update = onUpdate,
        .on_complete = onComplete,
        .context = @ptrCast(&counts),
    });

    animator.tick(50);
    try std.testing.expect(updates > 0);
    try std.testing.expectEqual(@as(usize, 0), completed);

    animator.tick(100);
    try std.testing.expect(completed == 1);
    try std.testing.expect(animator.animations.items.len == 0);
}

test "animator supports yoyo" {
    const alloc = std.testing.allocator;
    var animator = Animator.init(alloc);
    defer animator.deinit();

    var values: [2]f32 = .{ 0, 0 };
    const onUpdate = struct {
        fn callback(progress: f32, ctx: ?*anyopaque) void {
            const arr = @as(*[2]f32, @ptrCast(@alignCast(ctx.?)));
            arr[0] = progress;
        }
    }.callback;

    _ = try animator.add(AnimationSpec{
        .duration_ms = 10,
        .yoyo = true,
        .on_update = onUpdate,
        .context = @ptrCast(&values),
    });

    animator.tick(10);
    try std.testing.expect(values[0] >= 1.0 - 0.01);
    animator.tick(10);
    try std.testing.expect(values[0] <= 0.1);
}
