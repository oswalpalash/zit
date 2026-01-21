const std = @import("std");
const render = @import("../render/render.zig");

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

/// Helper to animate a scalar value and fire change callbacks as it progresses.
pub const ValueDriver = struct {
    current: f32 = 0,
    start: f32 = 0,
    target: f32 = 0,
    handle: ?AnimationHandle = null,
    on_change: ?ValueChangeFn = null,
    user_ctx: ?*anyopaque = null,
    duration_ms: u64 = 0,
    easing: AnimationEasingFn = Easing.linear,

    pub const ValueChangeFn = *const fn (value: f32, ctx: ?*anyopaque) void;

    /// Snap to a value immediately and clear any in-flight animation.
    pub fn snap(self: *ValueDriver, value: f32) void {
        self.current = value;
        self.start = value;
        self.target = value;
        self.handle = null;
    }

    /// Start a value animation, cancelling any previous handle on the same driver.
    pub fn animate(self: *ValueDriver, animator: *Animator, start_value: f32, target_value: f32, duration_ms: u64, easing: AnimationEasingFn, on_change: ValueChangeFn, user_ctx: ?*anyopaque) !AnimationHandle {
        if (self.handle) |h| {
            _ = animator.cancel(h);
            self.handle = null;
        }

        self.start = start_value;
        self.target = target_value;
        self.duration_ms = duration_ms;
        self.easing = easing;
        self.on_change = on_change;
        self.user_ctx = user_ctx;

        const spec = AnimationSpec{
            .duration_ms = duration_ms,
            .easing = easing,
            .on_update = ValueDriver.onUpdate,
            .on_complete = ValueDriver.onComplete,
            .context = self,
        };

        const handle = try animator.add(spec);
        self.handle = handle;
        return handle;
    }

    /// Cancel a running animation and keep the current value.
    pub fn cancel(self: *ValueDriver, animator: *Animator) void {
        if (self.handle) |h| {
            _ = animator.cancel(h);
            self.handle = null;
        }
    }

    /// Return true when the value is currently being animated.
    pub fn isAnimating(self: ValueDriver) bool {
        return self.handle != null;
    }

    fn onUpdate(progress: f32, ctx: ?*anyopaque) void {
        const self = @as(*ValueDriver, @ptrCast(@alignCast(ctx.?)));
        const value = self.start + (self.target - self.start) * progress;
        self.current = value;

        if (self.on_change) |cb| {
            cb(value, self.user_ctx);
        }
    }

    fn onComplete(ctx: ?*anyopaque) void {
        const self = @as(*ValueDriver, @ptrCast(@alignCast(ctx.?)));
        self.current = self.target;
        self.handle = null;

        if (self.on_change) |cb| {
            cb(self.current, self.user_ctx);
        }
    }
};

/// Smoothly transitions between two colors using a backing scalar driver.
pub const ColorTransition = struct {
    driver: ValueDriver = .{},
    start: render.Color = render.Color.named(render.NamedColor.default),
    target: render.Color = render.Color.named(render.NamedColor.default),
    current: render.Color = render.Color.named(render.NamedColor.default),

    pub fn init(color: render.Color) ColorTransition {
        return ColorTransition{
            .start = color,
            .target = color,
            .current = color,
        };
    }

    /// Immediately set the color and reset any animation.
    pub fn snap(self: *ColorTransition, color: render.Color) void {
        self.start = color;
        self.target = color;
        self.current = color;
        self.driver.snap(1);
    }

    /// Begin a transition to a new target color.
    pub fn animateTo(self: *ColorTransition, animator: *Animator, to: render.Color, duration_ms: u64, easing: AnimationEasingFn) !void {
        // If the target is unchanged, just sync the state.
        if (std.meta.eql(self.target, to) and std.meta.eql(self.current, to)) {
            self.snap(to);
            return;
        }

        const update = struct {
            fn onChange(new_value: f32, ctx: ?*anyopaque) void {
                const transition = @as(*ColorTransition, @ptrCast(@alignCast(ctx.?)));
                transition.current = render.mixColor(transition.start, transition.target, new_value);
            }
        }.onChange;

        self.start = self.current;
        self.target = to;
        _ = try self.driver.animate(animator, 0, 1, duration_ms, easing, update, self);
    }

    /// Get the current blended color.
    pub fn value(self: ColorTransition) render.Color {
        return self.current;
    }
};

pub const VisibilityMode = enum { fade, slide };
pub const SlideDirection = enum { up, down, left, right };

pub const VisibilityOptions = struct {
    mode: VisibilityMode = .fade,
    slide_direction: SlideDirection = .up,
    slide_distance: u16 = 2,
    duration_ms: u64 = 180,
    easing: AnimationEasingFn = Easing.easeInOutQuad,
    fade_to: render.Color = render.Color.named(render.NamedColor.default),
};

/// Track show/hide transitions for a widget and expose alpha/offset helpers.
pub const VisibilityController = struct {
    progress: f32 = 1.0,
    target_visible: bool = true,
    start_progress: f32 = 1.0,
    options: VisibilityOptions = .{},
    handle: ?AnimationHandle = null,

    pub fn snap(self: *VisibilityController, visible: bool) void {
        self.target_visible = visible;
        self.progress = if (visible) 1 else 0;
        self.start_progress = self.progress;
        self.handle = null;
    }

    pub fn animate(self: *VisibilityController, animator: *Animator, visible: bool, opts: VisibilityOptions) !AnimationHandle {
        if (self.handle) |h| {
            _ = animator.cancel(h);
            self.handle = null;
        }

        self.target_visible = visible;
        self.start_progress = self.progress;
        self.options = opts;

        const spec = AnimationSpec{
            .duration_ms = opts.duration_ms,
            .easing = opts.easing,
            .on_update = VisibilityController.onUpdate,
            .on_complete = VisibilityController.onComplete,
            .context = self,
        };

        const handle = try animator.add(spec);
        self.handle = handle;
        return handle;
    }

    pub fn isAnimating(self: VisibilityController) bool {
        return self.handle != null;
    }

    pub fn isHiding(self: VisibilityController) bool {
        return !self.target_visible and self.progress < 1;
    }

    pub fn alpha(self: VisibilityController) f32 {
        return self.progress;
    }

    pub fn displacement(self: VisibilityController) struct { dx: i16, dy: i16 } {
        if (self.options.mode != .slide) return .{ .dx = 0, .dy = 0 };

        const remaining = 1 - self.progress;
        const distance_f: f32 = @floatFromInt(self.options.slide_distance);
        const offset: i16 = @intFromFloat(std.math.round(remaining * distance_f));

        return switch (self.options.slide_direction) {
            .left => .{ .dx = -offset, .dy = 0 },
            .right => .{ .dx = offset, .dy = 0 },
            .up => .{ .dx = 0, .dy = -offset },
            .down => .{ .dx = 0, .dy = offset },
        };
    }

    /// Blend a color towards the configured fade target based on current progress.
    pub fn fadeColor(self: VisibilityController, color: render.Color) render.Color {
        if (self.options.mode != .fade or self.progress >= 0.999) return color;
        return render.mixColor(self.options.fade_to, color, self.progress);
    }

    fn onUpdate(progress: f32, ctx: ?*anyopaque) void {
        const self = @as(*VisibilityController, @ptrCast(@alignCast(ctx.?)));
        const target: f32 = if (self.target_visible) 1 else 0;
        self.progress = self.start_progress + (target - self.start_progress) * progress;
    }

    fn onComplete(ctx: ?*anyopaque) void {
        const self = @as(*VisibilityController, @ptrCast(@alignCast(ctx.?)));
        self.progress = if (self.target_visible) 1 else 0;
        self.handle = null;
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
    var counts = Counters{ .updates = &updates, .completed = &completed };

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

test "value driver animates scalar values" {
    const alloc = std.testing.allocator;
    var animator = Animator.init(alloc);
    defer animator.deinit();

    var driver = ValueDriver{};
    var observed: f32 = 0;
    const update = struct {
        fn onChange(value: f32, ctx: ?*anyopaque) void {
            const slot = @as(*f32, @ptrCast(@alignCast(ctx.?)));
            slot.* = value;
        }
    }.onChange;

    _ = try driver.animate(&animator, 0, 10, 10, Easing.linear, update, @ptrCast(&observed));
    animator.tick(5);
    try std.testing.expect(observed > 0);
    animator.tick(10);
    try std.testing.expect(driver.handle == null);
    try std.testing.expectEqual(@as(f32, 10), driver.current);
}

test "color transition blends colors over time" {
    const alloc = std.testing.allocator;
    var animator = Animator.init(alloc);
    defer animator.deinit();

    var transition = ColorTransition.init(render.Color.rgb(0, 0, 0));
    try transition.animateTo(&animator, render.Color.rgb(0, 0, 255), 20, Easing.linear);

    animator.tick(10);
    const mid = transition.value();
    try std.testing.expect(mid.rgb_color.b > 0);

    animator.tick(20);
    const final = transition.value();
    try std.testing.expectEqual(@as(u8, 255), final.rgb_color.b);
}

test "visibility controller tracks slide offsets and alpha" {
    const alloc = std.testing.allocator;
    var animator = Animator.init(alloc);
    defer animator.deinit();

    var visibility = VisibilityController{};
    _ = try visibility.animate(&animator, false, VisibilityOptions{ .mode = .slide, .slide_direction = .left, .slide_distance = 4, .duration_ms = 10 });
    animator.tick(5);
    const delta = visibility.displacement();
    try std.testing.expect(delta.dx < 0);
    try std.testing.expect(visibility.alpha() < 1);

    animator.tick(10);
    try std.testing.expect(visibility.alpha() == 0);
    try std.testing.expect(visibility.handle == null);
}
