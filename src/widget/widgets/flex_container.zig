const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const accessibility = @import("../accessibility.zig");
const layout_transaction = @import("layout_transaction.zig");

/// Flex container widget that arranges children using FlexLayout.
pub const FlexContainer = struct {
    widget: base.Widget,
    layout: *layout_module.FlexLayout,
    children: std.ArrayList(*base.Widget),
    layout_snapshots: std.ArrayList(layout_transaction.Snapshot),
    allocator: std.mem.Allocator,
    const LayoutContext = struct {
        err: ?anyerror = null,
    };

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator, direction: layout_module.FlexDirection) !*FlexContainer {
        const self = try allocator.create(FlexContainer);
        errdefer allocator.destroy(self);

        const layout = try layout_module.FlexLayout.init(allocator, direction);
        errdefer layout.deinit();

        self.* = FlexContainer{
            .widget = base.Widget.init(&vtable),
            .layout = layout,
            .children = std.ArrayList(*base.Widget).empty,
            .layout_snapshots = std.ArrayList(layout_transaction.Snapshot).empty,
            .allocator = allocator,
        };
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.container), "Flex container", "");
        return self;
    }

    pub fn deinit(self: *FlexContainer) void {
        self.detachChildren();
        self.children.deinit(self.allocator);
        self.layout_snapshots.deinit(self.allocator);
        self.layout.deinit();
        self.allocator.destroy(self);
    }

    pub fn addChild(self: *FlexContainer, child: *base.Widget, flex: u16) !void {
        const has_child = self.childIndex(child) != null;
        const has_layout_child = self.layoutChildIndex(child) != null;
        const target_layout_len = self.layout.children.items.len + if (has_layout_child) @as(usize, 0) else 1;

        if (!has_child) {
            try self.children.ensureUnusedCapacity(self.allocator, 1);
            try self.layout_snapshots.ensureTotalCapacity(self.allocator, self.children.items.len + 1);
        }
        try self.layout.naturals_scratch.ensureTotalCapacity(self.layout.base.allocator, target_layout_len);
        try self.layout.assigned_scratch.ensureTotalCapacity(self.layout.base.allocator, target_layout_len);
        if (!has_layout_child) {
            try self.layout.children.ensureUnusedCapacity(self.layout.base.allocator, 1);
        }

        try child.attachTo(&self.widget);
        _ = self.removeChildEntries(child);

        self.layout.children.appendAssumeCapacity(layout_module.FlexChild.init(child.asLayoutElement(), flex));
        self.layout.cache.valid = false;
        self.children.appendAssumeCapacity(child);
        self.widget.markDirty();
    }

    fn childIndex(self: *const FlexContainer, child: *const base.Widget) ?usize {
        for (self.children.items, 0..) |entry, idx| {
            if (entry == child) return idx;
        }
        return null;
    }

    fn layoutChildIndex(self: *const FlexContainer, child: *const base.Widget) ?usize {
        const child_ctx: *anyopaque = @ptrCast(@constCast(child));
        for (self.layout.children.items, 0..) |entry, idx| {
            if (entry.element.ctx == child_ctx) return idx;
        }
        return null;
    }

    pub fn removeChild(self: *FlexContainer, child: *base.Widget) void {
        const changed = self.removeChildEntries(child);
        if (changed) _ = child.detachFrom(&self.widget);
        if (changed) self.widget.markDirty();
    }

    fn removeChildEntries(self: *FlexContainer, child: *base.Widget) bool {
        var changed = false;
        for (self.children.items, 0..) |entry, idx| {
            if (entry == child) {
                _ = self.children.orderedRemove(idx);
                changed = true;
                break;
            }
        }

        const child_ctx: *anyopaque = @ptrCast(child);
        for (self.layout.children.items, 0..) |entry, idx| {
            if (entry.element.ctx == child_ctx) {
                _ = self.layout.children.orderedRemove(idx);
                self.layout.cache.valid = false;
                changed = true;
                break;
            }
        }
        return changed;
    }

    pub fn clearChildren(self: *FlexContainer) void {
        const changed = self.children.items.len != 0 or self.layout.children.items.len != 0;
        self.detachChildren();
        self.children.clearRetainingCapacity();
        self.layout.children.clearRetainingCapacity();
        self.layout.cache.valid = false;
        if (changed) self.widget.markDirty();
    }

    fn detachChildren(self: *FlexContainer) void {
        for (self.children.items) |child| {
            _ = child.detachFrom(&self.widget);
        }
    }

    pub fn setDirection(self: *FlexContainer, direction: layout_module.FlexDirection) void {
        if (self.layout.direction == direction) return;
        self.layout.direction = direction;
        self.layout.cache.valid = false;
        self.widget.markDirty();
    }

    pub fn setLayoutDirection(self: *FlexContainer, direction: layout_module.LayoutDirection) void {
        if (self.layout.layout_direction == direction) return;
        _ = self.layout.layoutDirection(direction);
        self.widget.markDirty();
    }

    pub fn setMainAlignment(self: *FlexContainer, alignment: layout_module.FlexAlignment) void {
        if (self.layout.main_alignment == alignment) return;
        _ = self.layout.mainAlignment(alignment);
        self.widget.markDirty();
    }

    pub fn setCrossAlignment(self: *FlexContainer, alignment: layout_module.FlexAlignment) void {
        if (self.layout.cross_alignment == alignment) return;
        _ = self.layout.crossAlignment(alignment);
        self.widget.markDirty();
    }

    pub fn setPadding(self: *FlexContainer, padding_value: layout_module.EdgeInsets) void {
        if (std.meta.eql(self.layout.padding_insets, padding_value)) return;
        _ = self.layout.padding(padding_value);
        self.widget.markDirty();
    }

    pub fn setGap(self: *FlexContainer, gap_value: u16) void {
        if (self.layout.gap_size == gap_value) return;
        _ = self.layout.gap(gap_value);
        self.widget.markDirty();
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *FlexContainer = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible) return;

        self.layout.renderLayout(renderer, self.widget.rect);
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *FlexContainer = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible or !self.widget.enabled) return false;

        var idx: usize = self.children.items.len;
        while (idx > 0) {
            idx -= 1;
            const child = self.children.items[idx];
            if (try child.handleEvent(event)) {
                return true;
            }
        }

        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *FlexContainer = @fieldParentPtr("widget", widget_ref);
        self.widget.rect = rect;

        try self.layout_snapshots.ensureTotalCapacity(self.allocator, self.children.items.len);
        self.layout_snapshots.clearRetainingCapacity();
        defer self.layout_snapshots.clearRetainingCapacity();
        for (self.children.items) |child| {
            self.layout_snapshots.appendAssumeCapacity(layout_transaction.Snapshot.capture(child));
        }

        var ctx = LayoutContext{};
        self.layout.forEachChildRect(rect, &ctx, layoutChild);
        if (ctx.err) |err| {
            layout_transaction.rollback(self.layout_snapshots.items);
            return err;
        }
    }

    fn layoutChild(ctx_ptr: *anyopaque, child: *layout_module.FlexChild, rect: layout_module.Rect) void {
        const ctx = @as(*LayoutContext, @ptrCast(@alignCast(ctx_ptr)));
        if (ctx.err != null) return;

        const widget = @as(*base.Widget, @ptrCast(@alignCast(child.element.ctx)));
        widget.layout(rect) catch |err| {
            ctx.err = err;
        };
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *FlexContainer = @fieldParentPtr("widget", widget_ref);
        return self.layout.calculateLayout(layout_module.Constraints.loose(0, 0));
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *FlexContainer = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.enabled) return false;

        for (self.children.items) |child| {
            if (child.canFocus()) return true;
        }

        return false;
    }
};

test "flex container lays out children and forwards events" {
    const Dummy = struct {
        widget: base.Widget = base.Widget.init(&vtable),
        last_rect: ?layout_module.Rect = null,
        handled: bool = false,
        const Self = @This();

        const vtable = base.Widget.VTable{
            .draw = drawFn,
            .handle_event = handleEventFn,
            .layout = layoutFn,
            .get_preferred_size = preferredFn,
            .can_focus = canFocusFn,
        };

        fn drawFn(_: *anyopaque, _: *render.Renderer) anyerror!void {}
        fn handleEventFn(widget_ptr: *anyopaque, _: input.Event) anyerror!bool {
            const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
            const self: *Self = @fieldParentPtr("widget", widget_ref);
            self.handled = true;
            return true;
        }
        fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
            const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
            const self: *Self = @fieldParentPtr("widget", widget_ref);
            self.last_rect = rect;
        }
        fn preferredFn(_: *anyopaque) anyerror!layout_module.Size {
            return layout_module.Size.init(2, 1);
        }
        fn canFocusFn(_: *anyopaque) bool {
            return true;
        }
    };

    const alloc = std.testing.allocator;
    var flex = try FlexContainer.init(alloc, .row);
    defer flex.deinit();

    var left = Dummy{};
    var right = Dummy{};

    try flex.addChild(&left.widget, 0);
    try flex.addChild(&right.widget, 0);
    try std.testing.expectEqual(&flex.widget, left.widget.parent.?);

    try flex.widget.layout(layout_module.Rect.init(0, 0, 6, 1));
    try std.testing.expect(left.last_rect != null);
    try std.testing.expect(right.last_rect != null);

    const left_rect = left.last_rect.?;
    const right_rect = right.last_rect.?;
    try std.testing.expectEqual(@as(u16, 0), left_rect.x);
    try std.testing.expectEqual(@as(u16, 2), left_rect.width);
    try std.testing.expectEqual(@as(u16, 2), right_rect.x);
    try std.testing.expectEqual(@as(u16, 2), right_rect.width);

    const event = input.Event{ .key = input.KeyEvent.init('x', input.KeyModifiers{}) };
    try std.testing.expect(try flex.widget.handleEvent(event));
    try std.testing.expect(!left.handled);
    try std.testing.expect(right.handled);
}

test "flex container direct layout mutations mark dirty" {
    const Dummy = struct {
        widget: base.Widget = base.Widget.init(&vtable),

        const vtable = base.Widget.VTable{
            .draw = drawFn,
            .handle_event = handleEventFn,
            .layout = layoutFn,
            .get_preferred_size = preferredFn,
            .can_focus = canFocusFn,
        };

        fn drawFn(_: *anyopaque, _: *render.Renderer) anyerror!void {}
        fn handleEventFn(_: *anyopaque, _: input.Event) anyerror!bool {
            return false;
        }
        fn layoutFn(_: *anyopaque, _: layout_module.Rect) anyerror!void {}
        fn preferredFn(_: *anyopaque) anyerror!layout_module.Size {
            return layout_module.Size.init(1, 1);
        }
        fn canFocusFn(_: *anyopaque) bool {
            return false;
        }
    };

    const alloc = std.testing.allocator;
    var flex = try FlexContainer.init(alloc, .row);
    defer flex.deinit();

    try flex.widget.layout(layout_module.Rect.init(0, 0, 10, 2));
    var renderer = try render.Renderer.init(alloc, 10, 2);
    defer renderer.deinit();

    try flex.widget.draw(&renderer);
    try std.testing.expect(!flex.widget.dirty);

    var child = Dummy{};
    try flex.addChild(&child.widget, 1);
    try std.testing.expect(flex.widget.dirty);

    try flex.widget.draw(&renderer);
    try std.testing.expect(!flex.widget.dirty);

    flex.setGap(1);
    try std.testing.expect(flex.widget.dirty);

    try flex.widget.draw(&renderer);
    try std.testing.expect(!flex.widget.dirty);

    flex.setGap(1);
    try std.testing.expect(!flex.widget.dirty);

    flex.setDirection(.column);
    try std.testing.expect(flex.widget.dirty);

    try flex.widget.draw(&renderer);
    try std.testing.expect(!flex.widget.dirty);

    flex.setDirection(.column);
    try std.testing.expect(!flex.widget.dirty);

    flex.removeChild(&child.widget);
    try std.testing.expect(flex.widget.dirty);
    try std.testing.expect(child.widget.parent == null);

    try flex.widget.draw(&renderer);
    try std.testing.expect(!flex.widget.dirty);

    flex.removeChild(&child.widget);
    try std.testing.expect(!flex.widget.dirty);

    try flex.addChild(&child.widget, 1);
    try flex.widget.draw(&renderer);
    try std.testing.expect(!flex.widget.dirty);

    flex.clearChildren();
    try std.testing.expect(flex.widget.dirty);
    try std.testing.expect(child.widget.parent == null);

    try flex.widget.draw(&renderer);
    try std.testing.expect(!flex.widget.dirty);

    flex.clearChildren();
    try std.testing.expect(!flex.widget.dirty);
}

test "flex container add child preserves state when child list allocation fails" {
    const Dummy = struct {
        widget: base.Widget = base.Widget.init(&vtable),

        const vtable = base.Widget.VTable{
            .draw = drawFn,
            .handle_event = handleEventFn,
            .layout = layoutFn,
            .get_preferred_size = preferredFn,
            .can_focus = canFocusFn,
        };

        fn drawFn(_: *anyopaque, _: *render.Renderer) anyerror!void {}
        fn handleEventFn(_: *anyopaque, _: input.Event) anyerror!bool {
            return false;
        }
        fn layoutFn(_: *anyopaque, _: layout_module.Rect) anyerror!void {}
        fn preferredFn(_: *anyopaque) anyerror!layout_module.Size {
            return layout_module.Size.init(1, 1);
        }
        fn canFocusFn(_: *anyopaque) bool {
            return false;
        }
    };

    const alloc = std.testing.allocator;
    var flex = try FlexContainer.init(alloc, .row);
    defer flex.deinit();

    var child = Dummy{};
    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = flex.allocator;
    flex.allocator = failing.allocator();
    defer flex.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, flex.addChild(&child.widget, 1));
    try std.testing.expectEqual(@as(usize, 0), flex.children.items.len);
    try std.testing.expectEqual(@as(usize, 0), flex.layout.children.items.len);
    try std.testing.expect(child.widget.parent == null);
}

test "flex container re-adds existing child without growing child list" {
    const Dummy = struct {
        widget: base.Widget = base.Widget.init(&vtable),

        const vtable = base.Widget.VTable{
            .draw = drawFn,
            .handle_event = handleEventFn,
            .layout = layoutFn,
            .get_preferred_size = preferredFn,
            .can_focus = canFocusFn,
        };

        fn drawFn(_: *anyopaque, _: *render.Renderer) anyerror!void {}
        fn handleEventFn(_: *anyopaque, _: input.Event) anyerror!bool {
            return false;
        }
        fn layoutFn(_: *anyopaque, _: layout_module.Rect) anyerror!void {}
        fn preferredFn(_: *anyopaque) anyerror!layout_module.Size {
            return layout_module.Size.init(1, 1);
        }
        fn canFocusFn(_: *anyopaque) bool {
            return false;
        }
    };

    const alloc = std.testing.allocator;
    var flex = try FlexContainer.init(alloc, .row);
    defer flex.deinit();

    var child = Dummy{};
    try flex.addChild(&child.widget, 1);

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = flex.allocator;
    flex.allocator = failing.allocator();
    defer flex.allocator = original_allocator;

    try flex.addChild(&child.widget, 3);
    try std.testing.expectEqual(@as(usize, 1), flex.children.items.len);
    try std.testing.expectEqual(@as(usize, 1), flex.layout.children.items.len);
    try std.testing.expectEqual(@as(u16, 3), flex.layout.children.items[0].flex_grow);
    try std.testing.expectEqual(&flex.widget, child.widget.parent.?);
}

test "flex container rejects child attached to another collection parent" {
    const alloc = std.testing.allocator;
    var first = try FlexContainer.init(alloc, .row);
    var second = try FlexContainer.init(alloc, .row);
    var child = try @import("block.zig").Block.init(alloc);
    defer {
        first.deinit();
        second.deinit();
        child.deinit();
    }

    try first.addChild(&child.widget, 2);
    try std.testing.expectError(error.WidgetAlreadyAttached, second.addChild(&child.widget, 1));

    try std.testing.expectEqual(@as(usize, 1), first.children.items.len);
    try std.testing.expectEqual(@as(usize, 1), first.layout.children.items.len);
    try std.testing.expectEqual(@as(usize, 0), second.children.items.len);
    try std.testing.expectEqual(@as(usize, 0), second.layout.children.items.len);
    try std.testing.expectEqual(&first.widget, child.widget.parent.?);
}

test "flex container deinit detaches child parent links" {
    const alloc = std.testing.allocator;
    var flex = try FlexContainer.init(alloc, .row);
    var flex_live = true;
    var child = try @import("block.zig").Block.init(alloc);
    defer {
        if (flex_live) flex.deinit();
        child.deinit();
    }

    try flex.addChild(&child.widget, 1);
    try std.testing.expectEqual(&flex.widget, child.widget.parent.?);

    flex.deinit();
    flex_live = false;
    try std.testing.expect(child.widget.parent == null);
}

test "flex container rolls back earlier child layout state on failure" {
    const Child = struct {
        widget: base.Widget = base.Widget.init(&vtable),
        fail_layout: bool = false,

        const vtable = base.Widget.VTable{
            .draw = drawFn,
            .handle_event = handleEventFn,
            .layout = layoutFn,
            .get_preferred_size = preferredFn,
            .can_focus = canFocusFn,
        };

        fn drawFn(_: *anyopaque, _: *render.Renderer) anyerror!void {}
        fn handleEventFn(_: *anyopaque, _: input.Event) anyerror!bool {
            return false;
        }
        fn layoutFn(widget_ptr: *anyopaque, _: layout_module.Rect) anyerror!void {
            const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
            const self: *@This() = @fieldParentPtr("widget", widget_ref);
            if (self.fail_layout) return error.LayoutRejected;
        }
        fn preferredFn(_: *anyopaque) anyerror!layout_module.Size {
            return layout_module.Size.init(2, 1);
        }
        fn canFocusFn(_: *anyopaque) bool {
            return false;
        }
    };

    const alloc = std.testing.allocator;
    var flex = try FlexContainer.init(alloc, .row);
    defer flex.deinit();

    const first_original = layout_module.Rect.init(5, 5, 1, 1);
    const second_original = layout_module.Rect.init(6, 5, 1, 1);
    var first = Child{};
    first.widget.rect = first_original;
    first.widget.dirty = false;
    var second = Child{ .fail_layout = true };
    second.widget.rect = second_original;
    second.widget.dirty = false;
    try flex.addChild(&first.widget, 1);
    try flex.addChild(&second.widget, 1);

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = flex.allocator;
    flex.allocator = failing.allocator();
    defer flex.allocator = original_allocator;

    try std.testing.expectError(error.LayoutRejected, flex.widget.layout(layout_module.Rect.init(0, 0, 8, 2)));
    try std.testing.expectEqual(first_original, first.widget.rect);
    try std.testing.expectEqual(second_original, second.widget.rect);
    try std.testing.expect(!first.widget.dirty);
    try std.testing.expect(!second.widget.dirty);
    try std.testing.expectEqual(@as(usize, 0), flex.layout_snapshots.items.len);
}
