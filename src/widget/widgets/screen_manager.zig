const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const animation = @import("../animation.zig");

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
        return self;
    }

    pub fn deinit(self: *ScreenManager) void {
        for (self.screens.items) |*entry| {
            entry.deinit(self.allocator);
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
        if (self.active_transition != null) {
            try self.finishTransition();
        }

        if (self.topEntry()) |prev| {
            try self.runHook(prev, prev.label_copy, prev.screen.lifecycle.on_pause);
            prev.state = .paused;
        }

        var entry = try ScreenEntry.init(self.allocator, screen);
        self.primeEntry(&entry);

        try self.screens.append(self.allocator, entry);
        const new_idx = self.screens.items.len - 1;
        try self.runHook(&self.screens.items[new_idx], self.screens.items[new_idx].label_copy, self.screens.items[new_idx].screen.lifecycle.on_enter);
        try self.startTransition(.push, new_idx, if (new_idx > 0) new_idx - 1 else null);
    }

    /// Pop the active screen and return to the previous one.
    pub fn pop(self: *ScreenManager) !void {
        if (self.screens.items.len <= 1) return;
        if (self.active_transition != null) {
            try self.finishTransition();
        }

        const exiting_idx = self.screens.items.len - 1;
        const entering_idx = exiting_idx - 1;
        try self.startTransition(.pop, entering_idx, exiting_idx);
    }

    /// Swap the current screen for a replacement.
    pub fn replace(self: *ScreenManager, screen: Screen) !void {
        if (self.screens.items.len == 0) {
            return self.push(screen);
        }

        if (self.active_transition != null) {
            try self.finishTransition();
        }

        const exiting_idx = self.screens.items.len - 1;
        var entry = try ScreenEntry.init(self.allocator, screen);
        self.primeEntry(&entry);
        try self.runHook(&self.screens.items[exiting_idx], self.screens.items[exiting_idx].label_copy, self.screens.items[exiting_idx].screen.lifecycle.on_pause);

        try self.screens.append(self.allocator, entry);
        const entering_idx = self.screens.items.len - 1;
        try self.runHook(&self.screens.items[entering_idx], self.screens.items[entering_idx].label_copy, self.screens.items[entering_idx].screen.lifecycle.on_enter);
        try self.startTransition(.replace, entering_idx, exiting_idx);
    }

    /// Clear all screens.
    pub fn reset(self: *ScreenManager) void {
        for (self.screens.items) |*entry| entry.deinit(self.allocator);
        self.screens.clearRetainingCapacity();
        self.active_transition = null;
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

    fn startTransition(self: *ScreenManager, kind: TransitionKind, entering_idx: ?usize, exiting_idx: ?usize) !void {
        if (entering_idx) |idx| {
            var entry = &self.screens.items[idx];
            entry.state = .entering;
            entry.screen.widget.visible = true;
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

    fn finishTransition(self: *ScreenManager) !void {
        const active_trans = self.active_transition orelse return;

        const entering_done = if (active_trans.entering) |idx| self.screens.items[idx].screen.widget.visibility_transition.handle == null else true;
        const exiting_done = if (active_trans.exiting) |idx| self.screens.items[idx].screen.widget.visibility_transition.handle == null else true;

        if (!entering_done or !exiting_done) return;

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
                    defer entry.deinit(self.allocator);
                    try self.runHook(&entry, entry.label_copy, entry.screen.lifecycle.on_exit);
                }
                if (self.topEntry()) |top| {
                    top.state = .steady;
                    try self.runHook(top, top.label_copy, top.screen.lifecycle.on_resume);
                }
            },
            .replace => {
                if (active_trans.exiting) |idx| {
                    var entry = self.screens.orderedRemove(idx);
                    defer entry.deinit(self.allocator);
                    try self.runHook(&entry, entry.label_copy, entry.screen.lifecycle.on_exit);
                }
                if (active_trans.entering) |idx| {
                    self.screens.items[idx].state = .steady;
                }
            },
        }

        self.active_transition = null;
    }

    fn runHook(self: *ScreenManager, entry: *ScreenEntry, label: []const u8, hook: ?*const fn (*ScreenContext) anyerror!void) !void {
        const cb = hook orelse return;
        var ctx = ScreenContext{ .manager = self, .widget = entry.screen.widget, .label = label };
        try cb(&ctx);
    }

    fn primeEntry(self: *ScreenManager, entry: *ScreenEntry) void {
        entry.screen.widget.setParent(&self.widget);
        if (self.last_rect) |rect| {
            entry.screen.widget.layout(rect) catch {};
        }
        entry.screen.widget.visibility_transition.snap(false);
        entry.screen.widget.visible = false;
    }

    fn topEntry(self: *ScreenManager) ?*ScreenEntry {
        if (self.screens.items.len == 0) return null;
        return &self.screens.items[self.screens.items.len - 1];
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*ScreenManager, @ptrCast(@alignCast(widget_ptr)));
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
        const self = @as(*ScreenManager, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible or self.screens.items.len == 0) return false;

        const target_idx = blk: {
            if (self.active_transition) |t| {
                if (t.entering) break :blk t.entering.?;
                if (t.exiting) break :blk t.exiting.?;
            }
            break :blk self.screens.items.len - 1;
        };

        return self.screens.items[target_idx].screen.widget.handleEvent(event);
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*ScreenManager, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
        self.last_rect = rect;
        for (self.screens.items) |entry| {
            entry.screen.widget.layout(rect) catch {};
        }
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*ScreenManager, @ptrCast(@alignCast(widget_ptr)));
        var pref = layout_module.Size.init(40, 12);
        for (self.screens.items) |entry| {
            const child_pref = try entry.screen.widget.getPreferredSize();
            pref.width = @max(pref.width, child_pref.width);
            pref.height = @max(pref.height, child_pref.height);
        }
        return pref;
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*ScreenManager, @ptrCast(@alignCast(widget_ptr)));
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
    try manager.layout(layout_module.Rect.init(0, 0, 40, 10));
    try manager.tick(500);

    try manager.push(.{ .widget = &block_b.widget, .label = "b", .lifecycle = hooks });
    try manager.tick(500);
    try manager.pop();
    try manager.tick(500);

    try std.testing.expect(order.items.len >= 4);
}
