const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const animation = @import("../animation.zig");
const accessibility = @import("../accessibility.zig");

/// Lifecycle hooks fired as screens are shown/hidden.
pub const ScreenLifecycle = struct {
    on_enter: ?*const fn (*ScreenContext) anyerror!void = null,
    on_exit: ?*const fn (*ScreenContext) anyerror!void = null,
    on_pause: ?*const fn (*ScreenContext) anyerror!void = null,
    on_resume: ?*const fn (*ScreenContext) anyerror!void = null,
};

/// Context passed to lifecycle callbacks.
pub const ScreenContext = struct {
    manager: *ScreenManager,
    widget: *base.Widget,
    label: []const u8,
};

/// A screen describes a root widget plus optional lifecycle.
pub const Screen = struct {
    widget: *base.Widget,
    label: []const u8 = "",
    lifecycle: ScreenLifecycle = .{},
};

/// Transition settings for push/pop animations.
pub const ScreenTransitions = struct {
    push_in: animation.VisibilityOptions = .{ .mode = .slide, .slide_direction = .right, .slide_distance = 8, .duration_ms = 160 },
    push_out: animation.VisibilityOptions = .{ .mode = .fade, .fade_to = render.Color.named(render.NamedColor.default), .duration_ms = 140 },
    pop_in: animation.VisibilityOptions = .{ .mode = .slide, .slide_direction = .left, .slide_distance = 6, .duration_ms = 140 },
    pop_out: animation.VisibilityOptions = .{ .mode = .fade, .fade_to = render.Color.named(render.NamedColor.default), .duration_ms = 120 },
};

const ScreenEntry = struct {
    screen: Screen,
    label_copy: []u8,
    state: State = .steady,

    const State = enum { steady, entering, exiting, paused };

    fn init(allocator: std.mem.Allocator, screen: Screen) !ScreenEntry {
        return ScreenEntry{
            .screen = screen,
            .label_copy = try allocator.dupe(u8, screen.label),
        };
    }

    fn deinit(self: *ScreenEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.label_copy);
    }
};

const TransitionKind = enum { push, pop, replace };

const ActiveTransition = struct {
    kind: TransitionKind,
    entering: ?usize = null,
    exiting: ?usize = null,
};

const CandidateState = struct {
    rect: layout_module.Rect,
    visible: bool,
    dirty: bool,
    dirty_rect: ?layout_module.Rect,
    visibility_transition: animation.VisibilityController,

    fn capture(widget: *const base.Widget) CandidateState {
        return .{
            .rect = widget.rect,
            .visible = widget.visible,
            .dirty = widget.dirty,
            .dirty_rect = widget.dirty_rect,
            .visibility_transition = widget.visibility_transition,
        };
    }

    fn restore(self: CandidateState, widget: *base.Widget, animator: *animation.Animator) void {
        widget.visibility_transition.cancel(animator);
        widget.rect = self.rect;
        widget.setVisible(self.visible);
        widget.dirty = self.dirty;
        widget.dirty_rect = self.dirty_rect;
        widget.visibility_transition = self.visibility_transition;
    }
};

/// Manage a stack of full-screen widgets with animated transitions.
pub const ScreenManager = struct {
    widget: base.Widget,
    allocator: std.mem.Allocator,
    screens: std.ArrayList(ScreenEntry),
    animator: animation.Animator,
    transitions: ScreenTransitions = .{},
    active_transition: ?ActiveTransition = null,
    last_rect: ?layout_module.Rect = null,

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator) !*ScreenManager {
        const self = try allocator.create(ScreenManager);
        self.* = ScreenManager{
            .widget = base.Widget.init(&vtable),
            .allocator = allocator,
            .screens = std.ArrayList(ScreenEntry).empty,
            .animator = animation.Animator.init(allocator),
        };
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.container), "Screen manager", "");
        return self;
    }

    pub fn deinit(self: *ScreenManager) void {
        for (self.screens.items) |*entry| {
            self.deinitEntry(entry);
        }
        self.screens.deinit(self.allocator);
        self.animator.deinit();
        self.allocator.destroy(self);
    }

    /// Replace the default transition palette.
    pub fn setTransitions(self: *ScreenManager, transitions: ScreenTransitions) void {
        self.transitions = transitions;
    }

    /// Push a new screen onto the stack and animate it in.
    pub fn push(self: *ScreenManager, screen: Screen) !void {
        try self.validateNewScreen(screen.widget);
        try self.screens.ensureUnusedCapacity(self.allocator, 1);
        try self.reserveTransitionCapacity(true, self.screens.items.len > 0);

        var entry = try ScreenEntry.init(self.allocator, screen);
        var entry_owned_by_stack = false;
        errdefer if (!entry_owned_by_stack) entry.deinit(self.allocator);
        const candidate_state = CandidateState.capture(screen.widget);
        var candidate_committed = false;
        errdefer if (!candidate_committed) candidate_state.restore(screen.widget, &self.animator);
        try self.primeEntry(&entry);
        errdefer if (!entry_owned_by_stack) {
            _ = entry.screen.widget.detachFrom(&self.widget);
        };

        try self.settleActiveTransition();

        if (self.topEntry()) |prev| {
            try self.runHook(prev, prev.label_copy, prev.screen.lifecycle.on_pause);
            prev.state = .paused;
        }

        self.screens.appendAssumeCapacity(entry);
        entry_owned_by_stack = true;
        errdefer {
            var removed = self.screens.orderedRemove(self.screens.items.len - 1);
            self.deinitEntry(&removed);
            if (self.topEntry()) |prev| prev.state = .steady;
        }

        const new_idx = self.screens.items.len - 1;
        try self.runHook(&self.screens.items[new_idx], self.screens.items[new_idx].label_copy, self.screens.items[new_idx].screen.lifecycle.on_enter);
        try self.startTransition(.push, new_idx, if (new_idx > 0) new_idx - 1 else null);
        candidate_committed = true;
    }

    /// Pop the active screen and return to the previous one.
    pub fn pop(self: *ScreenManager) !void {
        if (self.screens.items.len <= 1) return;
        try self.reserveTransitionCapacity(true, true);
        try self.settleActiveTransition();
        if (self.screens.items.len <= 1) return;

        const exiting_idx = self.screens.items.len - 1;
        const entering_idx = exiting_idx - 1;
        try self.startTransition(.pop, entering_idx, exiting_idx);
    }

    /// Swap the current screen for a replacement.
    pub fn replace(self: *ScreenManager, screen: Screen) !void {
        try self.validateNewScreen(screen.widget);

        if (self.screens.items.len == 0) {
            return self.push(screen);
        }
        try self.screens.ensureUnusedCapacity(self.allocator, 1);
        try self.reserveTransitionCapacity(true, true);

        var entry = try ScreenEntry.init(self.allocator, screen);
        var entry_owned_by_stack = false;
        errdefer if (!entry_owned_by_stack) entry.deinit(self.allocator);
        const candidate_state = CandidateState.capture(screen.widget);
        var candidate_committed = false;
        errdefer if (!candidate_committed) candidate_state.restore(screen.widget, &self.animator);
        try self.primeEntry(&entry);
        errdefer if (!entry_owned_by_stack) {
            _ = entry.screen.widget.detachFrom(&self.widget);
        };

        try self.settleActiveTransition();
        const exiting_idx = self.screens.items.len - 1;
        try self.runHook(&self.screens.items[exiting_idx], self.screens.items[exiting_idx].label_copy, self.screens.items[exiting_idx].screen.lifecycle.on_pause);

        self.screens.appendAssumeCapacity(entry);
        entry_owned_by_stack = true;
        errdefer {
            var removed = self.screens.orderedRemove(self.screens.items.len - 1);
            self.deinitEntry(&removed);
        }

        const entering_idx = self.screens.items.len - 1;
        try self.runHook(&self.screens.items[entering_idx], self.screens.items[entering_idx].label_copy, self.screens.items[entering_idx].screen.lifecycle.on_enter);
        try self.startTransition(.replace, entering_idx, exiting_idx);
        candidate_committed = true;
    }

    /// Clear all screens.
    pub fn reset(self: *ScreenManager) void {
        const changed = self.screens.items.len != 0 or
            self.active_transition != null or
            self.animator.animations.items.len != 0;
        for (self.screens.items) |*entry| self.deinitEntry(entry);
        self.screens.clearRetainingCapacity();
        self.active_transition = null;
        if (changed) self.widget.markDirty();
    }

    /// Drive animations from the app loop.
    pub fn tick(self: *ScreenManager, delta_ms: u64) !void {
        self.animator.tick(delta_ms);
        try self.finishTransition();
    }

    /// Peek the active screen.
    pub fn active(self: *ScreenManager) ?Screen {
        if (self.screens.items.len == 0) return null;
        const top = self.screens.items[self.screens.items.len - 1];
        return top.screen;
    }

    fn reserveTransitionCapacity(self: *ScreenManager, has_entering: bool, has_exiting: bool) !void {
        var count: usize = 0;
        if (has_entering) count += 1;
        if (has_exiting) count += 1;
        try self.animator.ensureUnusedCapacity(count);
    }

    fn startTransition(self: *ScreenManager, kind: TransitionKind, entering_idx: ?usize, exiting_idx: ?usize) !void {
        if (entering_idx) |idx| {
            var entry = &self.screens.items[idx];
            entry.state = .entering;
            entry.screen.widget.setVisible(true);
            entry.screen.widget.visibility_transition.snap(false);
            try entry.screen.widget.animateVisibility(&self.animator, true, pushInFor(self.transitions, kind));
        }

        if (exiting_idx) |idx| {
            var entry = &self.screens.items[idx];
            entry.state = .exiting;
            try entry.screen.widget.animateVisibility(&self.animator, false, popOutFor(self.transitions, kind));
        }

        self.active_transition = ActiveTransition{ .kind = kind, .entering = entering_idx, .exiting = exiting_idx };
    }

    fn settleActiveTransition(self: *ScreenManager) !void {
        const active_trans = self.active_transition orelse return;
        if (active_trans.entering) |idx| self.settleVisibility(idx, true);
        if (active_trans.exiting) |idx| self.settleVisibility(idx, false);
        try self.finishTransition();
    }

    fn settleVisibility(self: *ScreenManager, idx: usize, visible: bool) void {
        const widget = self.screens.items[idx].screen.widget;
        widget.visibility_transition.cancel(&self.animator);
        widget.setVisible(visible);
        widget.visibility_transition.snap(visible);
        widget.markDirty();
    }

    fn finishTransition(self: *ScreenManager) !void {
        const active_trans = self.active_transition orelse return;

        const entering_done = if (active_trans.entering) |idx| self.screens.items[idx].screen.widget.visibility_transition.handle == null else true;
        const exiting_done = if (active_trans.exiting) |idx| self.screens.items[idx].screen.widget.visibility_transition.handle == null else true;

        if (!entering_done or !exiting_done) return;

        var first_error: ?anyerror = null;
        switch (active_trans.kind) {
            .push => {
                if (active_trans.entering) |idx| {
                    self.screens.items[idx].state = .steady;
                }
                if (active_trans.exiting) |idx| {
                    self.screens.items[idx].state = .paused;
                }
            },
            .pop => {
                if (active_trans.exiting) |idx| {
                    var entry = self.screens.orderedRemove(idx);
                    defer self.deinitEntry(&entry);
                    self.runHook(&entry, entry.label_copy, entry.screen.lifecycle.on_exit) catch |err| {
                        first_error = err;
                    };
                }
                if (self.topEntry()) |top| {
                    top.state = .steady;
                    self.runHook(top, top.label_copy, top.screen.lifecycle.on_resume) catch |err| {
                        if (first_error == null) first_error = err;
                    };
                }
            },
            .replace => {
                if (active_trans.exiting) |idx| {
                    var entry = self.screens.orderedRemove(idx);
                    defer self.deinitEntry(&entry);
                    self.runHook(&entry, entry.label_copy, entry.screen.lifecycle.on_exit) catch |err| {
                        first_error = err;
                    };
                }
                if (active_trans.entering) |idx| {
                    var entering_idx = idx;
                    if (active_trans.exiting) |exiting_idx| {
                        if (exiting_idx < entering_idx) entering_idx -= 1;
                    }
                    if (entering_idx < self.screens.items.len) {
                        self.screens.items[entering_idx].state = .steady;
                    }
                }
            },
        }

        self.active_transition = null;
        if (first_error) |err| return err;
    }

    fn runHook(self: *ScreenManager, entry: *ScreenEntry, label: []const u8, hook: ?*const fn (*ScreenContext) anyerror!void) !void {
        const cb = hook orelse return;
        var ctx = ScreenContext{ .manager = self, .widget = entry.screen.widget, .label = label };
        try cb(&ctx);
    }

    fn deinitEntry(self: *ScreenManager, entry: *ScreenEntry) void {
        entry.screen.widget.visibility_transition.cancel(&self.animator);
        _ = entry.screen.widget.detachFrom(&self.widget);
        entry.deinit(self.allocator);
    }

    fn primeEntry(self: *ScreenManager, entry: *ScreenEntry) !void {
        try entry.screen.widget.attachTo(&self.widget);
        errdefer {
            _ = entry.screen.widget.detachFrom(&self.widget);
        }
        if (self.last_rect) |rect| {
            try entry.screen.widget.layout(rect);
        }
    }

    fn validateNewScreen(self: *const ScreenManager, widget: *const base.Widget) !void {
        if (widget.parent != null) return error.WidgetAlreadyAttached;
        if (widget.visibility_transition.isAnimating()) return error.WidgetAnimationInProgress;
        for (self.screens.items) |entry| {
            if (entry.screen.widget == widget) return error.WidgetAlreadyAttached;
        }
    }

    fn topEntry(self: *ScreenManager) ?*ScreenEntry {
        if (self.screens.items.len == 0) return null;
        return &self.screens.items[self.screens.items.len - 1];
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *ScreenManager = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible or self.screens.items.len == 0) return;

        const rect = self.widget.rect;
        const active_trans = self.active_transition;

        var draw_indices = std.ArrayList(usize).empty;
        defer draw_indices.deinit(self.allocator);

        if (active_trans) |t| {
            if (t.exiting) |idx| try draw_indices.append(self.allocator, idx);
            if (t.entering) |idx| try draw_indices.append(self.allocator, idx);
        } else {
            try draw_indices.append(self.allocator, self.screens.items.len - 1);
        }

        std.mem.sort(usize, draw_indices.items, {}, comptime std.sort.asc(usize));

        for (draw_indices.items) |idx| {
            const entry = &self.screens.items[idx];
            entry.screen.widget.asLayoutElement().render(renderer, rect);
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *ScreenManager = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible or self.screens.items.len == 0) return false;

        const target_idx = blk: {
            if (self.active_transition) |t| {
                if (t.entering) |idx| break :blk idx;
                if (t.exiting) |idx| break :blk idx;
            }
            break :blk self.screens.items.len - 1;
        };

        return self.screens.items[target_idx].screen.widget.handleEvent(event);
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *ScreenManager = @fieldParentPtr("widget", widget_ref);
        self.widget.rect = rect;
        self.last_rect = rect;
        for (self.screens.items) |entry| {
            try entry.screen.widget.layout(rect);
        }
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *ScreenManager = @fieldParentPtr("widget", widget_ref);
        var pref = layout_module.Size.init(40, 12);
        for (self.screens.items) |entry| {
            const child_pref = try entry.screen.widget.getPreferredSize();
            pref.width = @max(pref.width, child_pref.width);
            pref.height = @max(pref.height, child_pref.height);
        }
        return pref;
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *ScreenManager = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.enabled) return false;
        const entry = self.topEntry() orelse return false;
        return entry.screen.widget.canFocus();
    }
};

fn pushInFor(self: ScreenTransitions, kind: TransitionKind) animation.VisibilityOptions {
    return switch (kind) {
        .push => self.push_in,
        .replace => self.push_in,
        .pop => self.pop_in,
    };
}

fn popOutFor(self: ScreenTransitions, kind: TransitionKind) animation.VisibilityOptions {
    return switch (kind) {
        .push => self.push_out,
        .replace => self.pop_out,
        .pop => self.pop_out,
    };
}

const FailingLayoutWidget = struct {
    widget: base.Widget,

    const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    fn init() FailingLayoutWidget {
        return .{ .widget = base.Widget.init(&vtable) };
    }

    fn drawFn(_: *anyopaque, _: *render.Renderer) anyerror!void {}

    fn handleEventFn(_: *anyopaque, _: input.Event) anyerror!bool {
        return false;
    }

    fn layoutFn(_: *anyopaque, _: layout_module.Rect) anyerror!void {
        return error.LayoutFailed;
    }

    fn getPreferredSizeFn(_: *anyopaque) anyerror!layout_module.Size {
        return layout_module.Size.init(1, 1);
    }

    fn canFocusFn(_: *anyopaque) bool {
        return false;
    }
};

test "screen manager runs lifecycle hooks on push/pop" {
    const alloc = std.testing.allocator;
    var manager = try ScreenManager.init(alloc);
    defer manager.deinit();

    var block_a = try @import("block.zig").Block.init(alloc);
    defer block_a.deinit();
    var block_b = try @import("block.zig").Block.init(alloc);
    defer block_b.deinit();

    var order = std.ArrayList([]const u8).empty;
    defer order.deinit(alloc);
    const recorder = struct {
        var events: *std.ArrayList([]const u8) = undefined;
        var allocator: std.mem.Allocator = undefined;
        fn push(tag: []const u8) !void {
            try events.append(allocator, tag);
        }
        fn enter(_: *ScreenContext) anyerror!void {
            try push("enter");
        }
        fn exit(_: *ScreenContext) anyerror!void {
            try push("exit");
        }
        fn pause(_: *ScreenContext) anyerror!void {
            try push("pause");
        }
        fn resume_cb(_: *ScreenContext) anyerror!void {
            try push("resume");
        }
    };

    recorder.events = &order;
    recorder.allocator = alloc;
    const hooks = ScreenLifecycle{
        .on_enter = recorder.enter,
        .on_exit = recorder.exit,
        .on_pause = recorder.pause,
        .on_resume = recorder.resume_cb,
    };

    try manager.push(.{ .widget = &block_a.widget, .label = "a", .lifecycle = hooks });
    try manager.widget.layout(layout_module.Rect.init(0, 0, 40, 10));
    try manager.tick(500);

    try manager.push(.{ .widget = &block_b.widget, .label = "b", .lifecycle = hooks });
    try manager.tick(500);
    try manager.pop();
    try manager.tick(500);

    try std.testing.expect(order.items.len >= 4);
}

test "screen manager replace updates active screen" {
    const alloc = std.testing.allocator;
    var manager = try ScreenManager.init(alloc);
    defer manager.deinit();

    var block_a = try @import("block.zig").Block.init(alloc);
    defer block_a.deinit();
    var block_b = try @import("block.zig").Block.init(alloc);
    defer block_b.deinit();

    try manager.push(.{ .widget = &block_a.widget, .label = "a" });
    try manager.replace(.{ .widget = &block_b.widget, .label = "b" });

    const active_before = manager.active().?;
    try std.testing.expectEqual(&block_b.widget, active_before.widget);

    try manager.tick(1000);
    try std.testing.expectEqual(@as(usize, 1), manager.screens.items.len);

    const active_after = manager.active().?;
    try std.testing.expectEqual(&block_b.widget, active_after.widget);
}

test "screen manager settles rapid navigation without orphaned transitions" {
    const alloc = std.testing.allocator;
    var manager = try ScreenManager.init(alloc);
    var block_a = try @import("block.zig").Block.init(alloc);
    var block_b = try @import("block.zig").Block.init(alloc);
    var block_c = try @import("block.zig").Block.init(alloc);
    defer {
        manager.deinit();
        block_a.deinit();
        block_b.deinit();
        block_c.deinit();
    }

    try manager.push(.{ .widget = &block_a.widget, .label = "a" });
    try std.testing.expectEqual(@as(usize, 1), manager.animator.animations.items.len);

    try manager.push(.{ .widget = &block_b.widget, .label = "b" });
    try std.testing.expectEqual(@as(usize, 2), manager.screens.items.len);
    try std.testing.expectEqual(@as(usize, 2), manager.animator.animations.items.len);
    try std.testing.expectEqual(TransitionKind.push, manager.active_transition.?.kind);
    try std.testing.expectEqual(ScreenEntry.State.exiting, manager.screens.items[0].state);
    try std.testing.expectEqual(ScreenEntry.State.entering, manager.screens.items[1].state);

    try manager.pop();
    try std.testing.expectEqual(@as(usize, 2), manager.screens.items.len);
    try std.testing.expectEqual(@as(usize, 2), manager.animator.animations.items.len);
    try std.testing.expectEqual(TransitionKind.pop, manager.active_transition.?.kind);
    try std.testing.expectEqual(ScreenEntry.State.entering, manager.screens.items[0].state);
    try std.testing.expectEqual(ScreenEntry.State.exiting, manager.screens.items[1].state);

    try manager.replace(.{ .widget = &block_c.widget, .label = "c" });
    try std.testing.expectEqual(@as(usize, 2), manager.screens.items.len);
    try std.testing.expectEqual(@as(usize, 2), manager.animator.animations.items.len);
    try std.testing.expectEqual(TransitionKind.replace, manager.active_transition.?.kind);
    try std.testing.expectEqual(&block_c.widget, manager.active().?.widget);
    try std.testing.expect(block_b.widget.parent == null);

    try manager.tick(1000);
    try std.testing.expectEqual(@as(usize, 1), manager.screens.items.len);
    try std.testing.expectEqual(@as(usize, 0), manager.animator.animations.items.len);
    try std.testing.expect(manager.active_transition == null);
    try std.testing.expectEqual(&block_c.widget, manager.active().?.widget);
    try std.testing.expectEqual(ScreenEntry.State.steady, manager.screens.items[0].state);
    try std.testing.expect(block_a.widget.parent == null);
    try std.testing.expect(block_b.widget.parent == null);
    try std.testing.expectEqual(&manager.widget, block_c.widget.parent.?);
}

test "screen manager preflight failure preserves an active transition" {
    const alloc = std.testing.allocator;
    var manager = try ScreenManager.init(alloc);
    var block_a = try @import("block.zig").Block.init(alloc);
    var block_b = try @import("block.zig").Block.init(alloc);
    const original_allocator = manager.allocator;
    defer {
        manager.allocator = original_allocator;
        manager.deinit();
        block_a.deinit();
        block_b.deinit();
    }

    try manager.push(.{ .widget = &block_a.widget, .label = "a" });
    const transition_before = manager.active_transition.?;
    const handle_before = block_a.widget.visibility_transition.handle.?;
    const animation_count_before = manager.animator.animations.items.len;
    manager.widget.clearDirty();

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    manager.allocator = failing.allocator();
    try std.testing.expectError(error.OutOfMemory, manager.push(.{ .widget = &block_b.widget, .label = "b" }));
    manager.allocator = original_allocator;

    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectEqual(@as(usize, 1), manager.screens.items.len);
    try std.testing.expect(std.meta.eql(transition_before, manager.active_transition.?));
    try std.testing.expect(std.meta.eql(handle_before, block_a.widget.visibility_transition.handle.?));
    try std.testing.expectEqual(animation_count_before, manager.animator.animations.items.len);
    try std.testing.expectEqual(ScreenEntry.State.entering, manager.screens.items[0].state);
    try std.testing.expectEqual(&manager.widget, block_a.widget.parent.?);
    try std.testing.expect(block_b.widget.parent == null);
    try std.testing.expect(!manager.widget.dirty);
}

test "screen manager rejects duplicate and cross-parent pushes before transition mutation" {
    const alloc = std.testing.allocator;
    var owner = try ScreenManager.init(alloc);
    var manager = try ScreenManager.init(alloc);
    var current = try @import("block.zig").Block.init(alloc);
    var attached = try @import("block.zig").Block.init(alloc);
    defer {
        manager.deinit();
        owner.deinit();
        current.deinit();
        attached.deinit();
    }

    try owner.push(.{ .widget = &attached.widget, .label = "owner" });
    try manager.push(.{ .widget = &current.widget, .label = "current" });
    const transition_before = manager.active_transition.?;
    const animation_count_before = manager.animator.animations.items.len;
    const visibility_handle_before = current.widget.visibility_transition.handle.?;
    manager.widget.clearDirty();

    try std.testing.expectError(error.WidgetAlreadyAttached, manager.push(.{ .widget = &current.widget, .label = "duplicate" }));
    try std.testing.expectError(error.WidgetAlreadyAttached, manager.push(.{ .widget = &attached.widget, .label = "foreign" }));

    try std.testing.expectEqual(@as(usize, 1), manager.screens.items.len);
    try std.testing.expectEqualStrings("current", manager.screens.items[0].label_copy);
    try std.testing.expect(std.meta.eql(transition_before, manager.active_transition.?));
    try std.testing.expectEqual(animation_count_before, manager.animator.animations.items.len);
    try std.testing.expect(std.meta.eql(visibility_handle_before, current.widget.visibility_transition.handle.?));
    try std.testing.expectEqual(&manager.widget, current.widget.parent.?);
    try std.testing.expectEqual(&owner.widget, attached.widget.parent.?);
    try std.testing.expect(!manager.widget.dirty);
}

test "screen manager rejects duplicate and cross-parent replacements before hooks" {
    const alloc = std.testing.allocator;
    var owner = try ScreenManager.init(alloc);
    var manager = try ScreenManager.init(alloc);
    var current = try @import("block.zig").Block.init(alloc);
    var attached = try @import("block.zig").Block.init(alloc);
    defer {
        manager.deinit();
        owner.deinit();
        current.deinit();
        attached.deinit();
    }

    const Hooks = struct {
        var pause_count: usize = 0;

        fn pause(_: *ScreenContext) anyerror!void {
            pause_count += 1;
        }
    };
    Hooks.pause_count = 0;

    try owner.push(.{ .widget = &attached.widget, .label = "owner" });
    try manager.push(.{
        .widget = &current.widget,
        .label = "current",
        .lifecycle = .{ .on_pause = Hooks.pause },
    });
    const transition_before = manager.active_transition.?;
    const animation_count_before = manager.animator.animations.items.len;
    manager.widget.clearDirty();

    try std.testing.expectError(error.WidgetAlreadyAttached, manager.replace(.{ .widget = &current.widget, .label = "duplicate" }));
    try std.testing.expectError(error.WidgetAlreadyAttached, manager.replace(.{ .widget = &attached.widget, .label = "foreign" }));

    try std.testing.expectEqual(@as(usize, 1), manager.screens.items.len);
    try std.testing.expectEqualStrings("current", manager.screens.items[0].label_copy);
    try std.testing.expect(std.meta.eql(transition_before, manager.active_transition.?));
    try std.testing.expectEqual(animation_count_before, manager.animator.animations.items.len);
    try std.testing.expectEqual(@as(usize, 0), Hooks.pause_count);
    try std.testing.expectEqual(&manager.widget, current.widget.parent.?);
    try std.testing.expectEqual(&owner.widget, attached.widget.parent.?);
    try std.testing.expect(!manager.widget.dirty);
}

test "screen manager rejects an independently animating candidate" {
    const alloc = std.testing.allocator;
    var manager = try ScreenManager.init(alloc);
    var candidate = try @import("block.zig").Block.init(alloc);
    var animator = animation.Animator.init(alloc);
    defer {
        candidate.widget.visibility_transition.cancel(&animator);
        animator.deinit();
        manager.deinit();
        candidate.deinit();
    }

    try candidate.widget.animateVisibility(&animator, false, .{});
    const handle_before = candidate.widget.visibility_transition.handle.?;
    manager.widget.clearDirty();

    try std.testing.expectError(error.WidgetAnimationInProgress, manager.push(.{ .widget = &candidate.widget, .label = "animated" }));
    try std.testing.expectEqual(@as(usize, 0), manager.screens.items.len);
    try std.testing.expectEqual(@as(usize, 1), animator.animations.items.len);
    try std.testing.expect(std.meta.eql(handle_before, candidate.widget.visibility_transition.handle.?));
    try std.testing.expect(candidate.widget.parent == null);
    try std.testing.expect(!manager.widget.dirty);
}

fn screenManagerPushAllocationFailureHarness(allocator: std.mem.Allocator) !void {
    var manager = try ScreenManager.init(allocator);
    defer manager.deinit();

    var block_a = try @import("block.zig").Block.init(allocator);
    defer block_a.deinit();
    var block_b = try @import("block.zig").Block.init(allocator);
    defer block_b.deinit();

    try manager.push(.{ .widget = &block_a.widget, .label = "a" });
    try manager.push(.{ .widget = &block_b.widget, .label = "b" });
}

fn screenManagerReplaceAllocationFailureHarness(allocator: std.mem.Allocator) !void {
    var manager = try ScreenManager.init(allocator);
    defer manager.deinit();

    var block_a = try @import("block.zig").Block.init(allocator);
    defer block_a.deinit();
    var block_b = try @import("block.zig").Block.init(allocator);
    defer block_b.deinit();

    try manager.push(.{ .widget = &block_a.widget, .label = "a" });
    try manager.replace(.{ .widget = &block_b.widget, .label = "b" });
}

test "screen manager navigation cleans up every allocation failure path" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, screenManagerPushAllocationFailureHarness, .{});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, screenManagerReplaceAllocationFailureHarness, .{});
}

test "screen manager push propagates priming layout failure" {
    const alloc = std.testing.allocator;
    var manager = try ScreenManager.init(alloc);
    defer manager.deinit();

    try manager.widget.layout(layout_module.Rect.init(0, 0, 20, 6));
    var failing = FailingLayoutWidget.init();
    failing.widget.rect = layout_module.Rect.init(3, 4, 5, 6);
    failing.widget.clearDirty();
    const candidate_before = CandidateState.capture(&failing.widget);

    try std.testing.expectError(error.LayoutFailed, manager.push(.{ .widget = &failing.widget, .label = "bad" }));
    try std.testing.expectEqual(@as(usize, 0), manager.screens.items.len);
    try std.testing.expect(failing.widget.parent == null);
    try std.testing.expect(std.meta.eql(candidate_before, CandidateState.capture(&failing.widget)));
}

test "screen manager replace preserves active screen on priming layout failure" {
    const alloc = std.testing.allocator;
    var manager = try ScreenManager.init(alloc);
    defer manager.deinit();

    var block = try @import("block.zig").Block.init(alloc);
    defer block.deinit();
    try manager.push(.{ .widget = &block.widget, .label = "good" });
    try manager.widget.layout(layout_module.Rect.init(0, 0, 20, 6));

    var failing = FailingLayoutWidget.init();
    try std.testing.expectError(error.LayoutFailed, manager.replace(.{ .widget = &failing.widget, .label = "bad" }));

    try std.testing.expectEqual(@as(usize, 1), manager.screens.items.len);
    try std.testing.expectEqual(&block.widget, manager.active().?.widget);
    try std.testing.expect(failing.widget.parent == null);
}

test "screen manager rejected entering screen is detached" {
    const alloc = std.testing.allocator;
    var manager = try ScreenManager.init(alloc);
    defer manager.deinit();

    var block_a = try @import("block.zig").Block.init(alloc);
    defer block_a.deinit();
    var block_b = try @import("block.zig").Block.init(alloc);
    defer block_b.deinit();

    const FailingEnter = struct {
        fn enter(_: *ScreenContext) anyerror!void {
            return error.EnterFailed;
        }
    };

    try manager.push(.{ .widget = &block_a.widget, .label = "good" });
    try std.testing.expectError(error.EnterFailed, manager.replace(.{
        .widget = &block_b.widget,
        .label = "bad",
        .lifecycle = .{ .on_enter = FailingEnter.enter },
    }));

    try std.testing.expectEqual(@as(usize, 1), manager.screens.items.len);
    try std.testing.expectEqual(&block_a.widget, manager.active().?.widget);
    try std.testing.expect(block_b.widget.parent == null);
}

test "screen manager rejected push after pause failure is detached" {
    const alloc = std.testing.allocator;
    var manager = try ScreenManager.init(alloc);
    defer manager.deinit();

    var block_a = try @import("block.zig").Block.init(alloc);
    defer block_a.deinit();
    var block_b = try @import("block.zig").Block.init(alloc);
    defer block_b.deinit();

    const FailingPause = struct {
        fn pause(_: *ScreenContext) anyerror!void {
            return error.PauseFailed;
        }
    };

    try manager.push(.{
        .widget = &block_a.widget,
        .label = "good",
        .lifecycle = .{ .on_pause = FailingPause.pause },
    });
    try manager.tick(1000);
    try manager.widget.layout(layout_module.Rect.init(0, 0, 20, 6));
    block_b.widget.rect = layout_module.Rect.init(3, 4, 5, 6);
    block_b.widget.clearDirty();
    const candidate_before = CandidateState.capture(&block_b.widget);
    try std.testing.expectError(error.PauseFailed, manager.push(.{ .widget = &block_b.widget, .label = "bad" }));

    try std.testing.expectEqual(@as(usize, 1), manager.screens.items.len);
    try std.testing.expectEqual(&block_a.widget, manager.active().?.widget);
    try std.testing.expectEqual(&manager.widget, block_a.widget.parent.?);
    try std.testing.expect(block_b.widget.parent == null);
    try std.testing.expectEqual(ScreenEntry.State.steady, manager.screens.items[0].state);
    try std.testing.expect(std.meta.eql(candidate_before, CandidateState.capture(&block_b.widget)));
}

test "screen manager rejected replace after pause failure is detached" {
    const alloc = std.testing.allocator;
    var manager = try ScreenManager.init(alloc);
    defer manager.deinit();

    var block_a = try @import("block.zig").Block.init(alloc);
    defer block_a.deinit();
    var block_b = try @import("block.zig").Block.init(alloc);
    defer block_b.deinit();

    const FailingPause = struct {
        fn pause(_: *ScreenContext) anyerror!void {
            return error.PauseFailed;
        }
    };

    try manager.push(.{
        .widget = &block_a.widget,
        .label = "good",
        .lifecycle = .{ .on_pause = FailingPause.pause },
    });
    try manager.tick(1000);
    try std.testing.expectError(error.PauseFailed, manager.replace(.{ .widget = &block_b.widget, .label = "bad" }));

    try std.testing.expectEqual(@as(usize, 1), manager.screens.items.len);
    try std.testing.expectEqual(&block_a.widget, manager.active().?.widget);
    try std.testing.expectEqual(&manager.widget, block_a.widget.parent.?);
    try std.testing.expect(block_b.widget.parent == null);
    try std.testing.expectEqual(ScreenEntry.State.steady, manager.screens.items[0].state);
}

test "screen manager pop exit hook failure still completes cleanup" {
    const alloc = std.testing.allocator;
    var manager = try ScreenManager.init(alloc);
    defer manager.deinit();

    var block_a = try @import("block.zig").Block.init(alloc);
    defer block_a.deinit();
    var block_b = try @import("block.zig").Block.init(alloc);
    defer block_b.deinit();

    var resumed = false;
    const Hooks = struct {
        var resumed_ptr: *bool = undefined;

        fn exit(_: *ScreenContext) anyerror!void {
            return error.ExitFailed;
        }

        fn resume_cb(_: *ScreenContext) anyerror!void {
            resumed_ptr.* = true;
        }
    };
    Hooks.resumed_ptr = &resumed;

    try manager.push(.{
        .widget = &block_a.widget,
        .label = "a",
        .lifecycle = .{ .on_resume = Hooks.resume_cb },
    });
    try manager.tick(1000);
    try manager.push(.{
        .widget = &block_b.widget,
        .label = "b",
        .lifecycle = .{ .on_exit = Hooks.exit },
    });
    try manager.tick(1000);

    try manager.pop();
    try std.testing.expectError(error.ExitFailed, manager.tick(1000));

    try std.testing.expectEqual(@as(usize, 1), manager.screens.items.len);
    try std.testing.expectEqual(&block_a.widget, manager.active().?.widget);
    try std.testing.expect(manager.active_transition == null);
    try std.testing.expect(resumed);
    try std.testing.expectEqual(&manager.widget, block_a.widget.parent.?);
    try std.testing.expect(block_b.widget.parent == null);
    try std.testing.expectEqual(ScreenEntry.State.steady, manager.screens.items[0].state);
}

test "screen manager replace exit hook failure keeps replacement active" {
    const alloc = std.testing.allocator;
    var manager = try ScreenManager.init(alloc);
    defer manager.deinit();

    var block_a = try @import("block.zig").Block.init(alloc);
    defer block_a.deinit();
    var block_b = try @import("block.zig").Block.init(alloc);
    defer block_b.deinit();

    const Hooks = struct {
        fn exit(_: *ScreenContext) anyerror!void {
            return error.ExitFailed;
        }
    };

    try manager.push(.{
        .widget = &block_a.widget,
        .label = "a",
        .lifecycle = .{ .on_exit = Hooks.exit },
    });
    try manager.tick(1000);
    try manager.replace(.{ .widget = &block_b.widget, .label = "b" });

    try std.testing.expectError(error.ExitFailed, manager.tick(1000));

    try std.testing.expectEqual(@as(usize, 1), manager.screens.items.len);
    try std.testing.expectEqual(&block_b.widget, manager.active().?.widget);
    try std.testing.expect(manager.active_transition == null);
    try std.testing.expect(block_a.widget.parent == null);
    try std.testing.expectEqual(&manager.widget, block_b.widget.parent.?);
    try std.testing.expectEqual(ScreenEntry.State.steady, manager.screens.items[0].state);
}

test "screen manager reset cancels active transition handles" {
    const alloc = std.testing.allocator;
    var manager = try ScreenManager.init(alloc);
    defer manager.deinit();

    var block_a = try @import("block.zig").Block.init(alloc);
    defer block_a.deinit();
    var block_b = try @import("block.zig").Block.init(alloc);
    defer block_b.deinit();

    try manager.push(.{ .widget = &block_a.widget, .label = "a" });
    try manager.tick(1000);
    try manager.push(.{ .widget = &block_b.widget, .label = "b" });

    try std.testing.expect(manager.animator.animations.items.len > 0);
    try std.testing.expect(block_a.widget.visibility_transition.handle != null);
    try std.testing.expect(block_b.widget.visibility_transition.handle != null);

    manager.reset();

    try std.testing.expectEqual(@as(usize, 0), manager.screens.items.len);
    try std.testing.expectEqual(@as(usize, 0), manager.animator.animations.items.len);
    try std.testing.expect(block_a.widget.visibility_transition.handle == null);
    try std.testing.expect(block_b.widget.visibility_transition.handle == null);
    try std.testing.expect(block_a.widget.parent == null);
    try std.testing.expect(block_b.widget.parent == null);
}

test "screen manager reset marks visible state dirty" {
    const alloc = std.testing.allocator;
    var manager = try ScreenManager.init(alloc);
    defer manager.deinit();

    var block = try @import("block.zig").Block.init(alloc);
    defer block.deinit();

    try manager.push(.{ .widget = &block.widget, .label = "visible" });
    manager.widget.clearDirty();

    manager.reset();
    try std.testing.expect(manager.widget.dirty);
    try std.testing.expectEqual(@as(usize, 0), manager.screens.items.len);

    manager.widget.clearDirty();
    manager.reset();
    try std.testing.expect(!manager.widget.dirty);
}

test "screen manager layout propagates child layout failure" {
    const alloc = std.testing.allocator;
    var manager = try ScreenManager.init(alloc);
    defer manager.deinit();

    var failing = FailingLayoutWidget.init();
    try manager.push(.{ .widget = &failing.widget, .label = "bad" });

    try std.testing.expectError(error.LayoutFailed, manager.widget.layout(layout_module.Rect.init(0, 0, 20, 6)));
}
