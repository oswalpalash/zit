const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");

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
        return self;
    }

    pub fn deinit(self: *FlexContainer) void {
        self.children.deinit(self.allocator);
        self.layout.deinit();
        self.allocator.destroy(self);
    }

    pub fn addChild(self: *FlexContainer, child: *base.Widget, flex: u16) !void {
        // Avoid duplicates by removing existing entries first.
        self.removeChild(child);

        try self.layout.addChild(layout_module.FlexChild.init(child.asLayoutElement(), flex));
        try self.children.append(self.allocator, child);
        child.parent = &self.widget;
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
        const self = @as(*FlexContainer, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;

        self.layout.renderLayout(renderer, self.widget.rect);
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*FlexContainer, @ptrCast(@alignCast(widget_ptr)));
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
        const self = @as(*FlexContainer, @ptrCast(@alignCast(widget_ptr)));
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
        const self = @as(*FlexContainer, @ptrCast(@alignCast(widget_ptr)));
        return self.layout.calculateLayout(layout_module.Constraints.loose(0, 0));
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*FlexContainer, @ptrCast(@alignCast(widget_ptr)));
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
            const self = @as(*Self, @ptrCast(@alignCast(widget_ptr)));
            self.handled = true;
            return true;
        }
        fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
            const self = @as(*Self, @ptrCast(@alignCast(widget_ptr)));
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
