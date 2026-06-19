const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const accessibility = @import("../accessibility.zig");

/// Flex container widget that arranges children using FlexLayout.
pub const FlexContainer = struct {
    widget: base.Widget,
    layout: *layout_module.FlexLayout,
    children: std.ArrayList(*base.Widget),
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
            .allocator = allocator,
        };
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.container), "Flex container", "");
        return self;
    }

    pub fn deinit(self: *FlexContainer) void {
        self.children.deinit(self.allocator);
        self.layout.deinit();
        self.allocator.destroy(self);
    }

    pub fn addChild(self: *FlexContainer, child: *base.Widget, flex: u16) !void {
        const has_child = self.childIndex(child) != null;
        const has_layout_child = self.layoutChildIndex(child) != null;
        const target_layout_len = self.layout.children.items.len + if (has_layout_child) @as(usize, 0) else 1;

        if (!has_child) {
            try self.children.ensureUnusedCapacity(self.allocator, 1);
        }
        try self.layout.naturals_scratch.ensureTotalCapacity(self.layout.base.allocator, target_layout_len);
        try self.layout.assigned_scratch.ensureTotalCapacity(self.layout.base.allocator, target_layout_len);
        if (!has_layout_child) {
            try self.layout.children.ensureUnusedCapacity(self.layout.base.allocator, 1);
        }

        // Avoid duplicates by removing existing entries first.
        self.removeChild(child);

        self.layout.children.appendAssumeCapacity(layout_module.FlexChild.init(child.asLayoutElement(), flex));
        self.layout.cache.valid = false;
        self.children.appendAssumeCapacity(child);
        child.parent = &self.widget;
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
        for (self.children.items, 0..) |entry, idx| {
            if (entry == child) {
                _ = self.children.orderedRemove(idx);
                child.parent = null;
                break;
            }
        }

        const child_ctx: *anyopaque = @ptrCast(child);
        for (self.layout.children.items, 0..) |entry, idx| {
            if (entry.element.ctx == child_ctx) {
                _ = self.layout.children.orderedRemove(idx);
                self.layout.cache.valid = false;
                break;
            }
        }
    }

    pub fn clearChildren(self: *FlexContainer) void {
        for (self.children.items) |child| {
            child.parent = null;
        }
        self.children.clearRetainingCapacity();
        self.layout.children.clearRetainingCapacity();
        self.layout.cache.valid = false;
    }

    pub fn setDirection(self: *FlexContainer, direction: layout_module.FlexDirection) void {
        self.layout.direction = direction;
        self.layout.cache.valid = false;
    }

    pub fn setLayoutDirection(self: *FlexContainer, direction: layout_module.LayoutDirection) void {
        _ = self.layout.layoutDirection(direction);
    }

    pub fn setMainAlignment(self: *FlexContainer, alignment: layout_module.FlexAlignment) void {
        _ = self.layout.mainAlignment(alignment);
    }

    pub fn setCrossAlignment(self: *FlexContainer, alignment: layout_module.FlexAlignment) void {
        _ = self.layout.crossAlignment(alignment);
    }

    pub fn setPadding(self: *FlexContainer, padding_value: layout_module.EdgeInsets) void {
        _ = self.layout.padding(padding_value);
    }

    pub fn setGap(self: *FlexContainer, gap_value: u16) void {
        _ = self.layout.gap(gap_value);
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

        var ctx = LayoutContext{};
        self.layout.forEachChildRect(rect, &ctx, layoutChild);
        if (ctx.err) |err| return err;
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
