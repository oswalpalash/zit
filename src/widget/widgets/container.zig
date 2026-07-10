const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const theme = @import("../theme.zig");
const accessibility = @import("../accessibility.zig");

/// Container widget for holding and arranging other widgets
pub const Container = struct {
    /// Base widget
    widget: base.Widget,
    /// Child widgets
    children: std.ArrayList(*base.Widget),
    /// Foreground color
    fg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    /// Background color
    bg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    /// Border style
    border: render.BorderStyle = .none,
    /// Show border
    show_border: bool = false,
    /// Allocator for container operations
    allocator: std.mem.Allocator,

    /// Virtual method table for Container
    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    /// Initialize a new container
    pub fn init(allocator: std.mem.Allocator) !*Container {
        const self = try allocator.create(Container);

        self.* = Container{
            .widget = base.Widget.init(&vtable),
            .children = std.ArrayList(*base.Widget).empty,
            .allocator = allocator,
        };
        self.setTheme(theme.Theme.dark());
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.container), "Container", "");

        return self;
    }

    /// Clean up container resources
    pub fn deinit(self: *Container) void {
        for (self.children.items) |child| {
            if (child.parent == &self.widget) {
                child.parent = null;
            }
        }
        self.children.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    /// Add a child widget to the container
    pub fn addChild(self: *Container, child: *base.Widget) !void {
        const existing_index = self.childIndex(child);
        if (existing_index == null) {
            try self.children.ensureUnusedCapacity(self.allocator, 1);
        }

        const was_last = if (existing_index) |idx| idx + 1 == self.children.items.len else false;
        const parent_changed = child.parent != &self.widget;
        try child.attachTo(&self.widget);
        if (existing_index) |idx| {
            _ = self.children.orderedRemove(idx);
        }
        self.children.appendAssumeCapacity(child);
        if (parent_changed or !was_last) self.widget.markDirty();
    }

    fn childIndex(self: *const Container, child: *const base.Widget) ?usize {
        for (self.children.items, 0..) |entry, idx| {
            if (entry == child) return idx;
        }
        return null;
    }

    /// Remove a child widget from the container
    pub fn removeChild(self: *Container, child: *base.Widget) void {
        for (self.children.items, 0..) |c, i| {
            if (c == child) {
                _ = self.children.orderedRemove(i);
                if (child.parent == &self.widget) {
                    child.parent = null;
                }
                self.widget.markDirty();
                break;
            }
        }
    }

    /// Set the container colors
    pub fn setColors(self: *Container, fg: render.Color, bg: render.Color) void {
        if (std.meta.eql(self.fg, fg) and std.meta.eql(self.bg, bg)) return;
        self.fg = fg;
        self.bg = bg;
        self.widget.markDirty();
    }

    /// Set the border style
    pub fn setBorder(self: *Container, border: render.BorderStyle) void {
        if (self.border == border and self.show_border == (border != .none)) return;
        self.border = border;
        self.show_border = border != .none;
        self.widget.markDirty();
    }

    /// Apply theme defaults for container colors.
    pub fn setTheme(self: *Container, theme_value: theme.Theme) void {
        const colors = theme.containerColors(theme_value);
        if (std.meta.eql(self.fg, colors.fg) and std.meta.eql(self.bg, colors.bg)) return;
        self.fg = colors.fg;
        self.bg = colors.bg;
        self.widget.markDirty();
    }

    fn addOffsetClamped(origin: u16, offset: u16) u16 {
        const value = @as(u32, origin) + @as(u32, offset);
        return @intCast(@min(value, @as(u32, std.math.maxInt(u16))));
    }

    /// Draw implementation for Container
    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Container = @fieldParentPtr("widget", widget_ref);

        if (!self.widget.visible) {
            return;
        }

        const rect = self.widget.rect;

        const styled = self.widget.applyStyle(
            "container",
            .{ .focus = self.widget.focused, .disabled = !self.widget.enabled },
            render.Style{},
            self.fg,
            self.bg,
        );
        const fg = styled.fg;
        const bg = styled.bg;
        const style = styled.style;

        // Fill container background
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', fg, bg, style);

        // Draw border if enabled
        if (self.show_border) {
            renderer.drawBox(rect.x, rect.y, rect.width, rect.height, self.border, fg, bg, style);
        }

        // Draw children
        for (self.children.items) |child| {
            try child.*.draw(renderer);
        }
    }

    /// Event handling implementation for Container
    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Container = @fieldParentPtr("widget", widget_ref);

        if (!self.widget.visible or !self.widget.enabled) {
            return false;
        }

        // Pass event to children in reverse order (top-most first)
        var i: usize = self.children.items.len;
        while (i > 0) {
            i -= 1;
            const child = self.children.items[i];
            if (try child.*.handleEvent(event)) {
                return true;
            }
        }

        return false;
    }

    /// Layout implementation for Container
    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Container = @fieldParentPtr("widget", widget_ref);
        self.widget.rect = rect;

        // Simple layout: just give each child the full container area
        // (can be overridden by more sophisticated container implementations)
        const border_adjust: u16 = if (self.show_border) 1 else 0;
        const inner_rect = layout_module.Rect.init(
            addOffsetClamped(rect.x, border_adjust),
            addOffsetClamped(rect.y, border_adjust),
            if (rect.width > 2 * border_adjust) rect.width - 2 * border_adjust else 0,
            if (rect.height > 2 * border_adjust) rect.height - 2 * border_adjust else 0,
        );

        for (self.children.items) |child| {
            try child.*.layout(inner_rect);
        }
    }

    /// Get preferred size implementation for Container
    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Container = @fieldParentPtr("widget", widget_ref);

        // Start with minimum size
        var width: u16 = 0;
        var height: u16 = 0;

        // Calculate maximum size of all children
        for (self.children.items) |child| {
            const child_size = try child.*.getPreferredSize();
            width = @max(width, child_size.width);
            height = @max(height, child_size.height);
        }

        // Add border if needed
        const border_adjust: u16 = if (self.show_border) 2 else 0;
        width = addOffsetClamped(width, border_adjust);
        height = addOffsetClamped(height, border_adjust);

        return layout_module.Size.init(width, height);
    }

    /// Can focus implementation for Container
    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Container = @fieldParentPtr("widget", widget_ref);

        if (!self.widget.enabled) {
            return false;
        }

        // Container can be focused if any child can be focused
        for (self.children.items) |child| {
            if (child.*.canFocus()) {
                return true;
            }
        }

        return false;
    }
};

test "container init/deinit" {
    const alloc = std.testing.allocator;
    var container = try Container.init(alloc);
    defer container.deinit();

    try std.testing.expectEqual(@as(usize, 0), container.children.items.len);
}

test "container lays out child and forwards events" {
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
            return layout_module.Size.init(4, 2);
        }
        fn canFocusFn(_: *anyopaque) bool {
            return true;
        }
    };

    const alloc = std.testing.allocator;
    var container = try Container.init(alloc);
    defer container.deinit();
    container.setBorder(.single);

    var dummy = Dummy{};
    try container.addChild(&dummy.widget);
    try std.testing.expectEqual(&container.widget, dummy.widget.parent.?);

    try container.widget.layout(layout_module.Rect.init(0, 0, 10, 4));
    try std.testing.expect(dummy.last_rect != null);
    const inner = dummy.last_rect.?;
    try std.testing.expectEqual(@as(u16, 1), inner.x);
    try std.testing.expectEqual(@as(u16, 1), inner.y);
    try std.testing.expectEqual(@as(u16, 8), inner.width);
    try std.testing.expectEqual(@as(u16, 2), inner.height);

    const event = input.Event{ .key = input.KeyEvent.init('x', input.KeyModifiers{}) };
    try std.testing.expect(try container.widget.handleEvent(event));
    try std.testing.expect(dummy.handled);
}

test "container marks dirty when visible state changes" {
    const alloc = std.testing.allocator;
    var container = try Container.init(alloc);
    defer container.deinit();

    var first = try @import("label.zig").Label.init(alloc, "first");
    defer first.deinit();
    var second = try @import("label.zig").Label.init(alloc, "second");
    defer second.deinit();

    try container.addChild(&first.widget);
    try container.widget.layout(layout_module.Rect.init(0, 0, 20, 5));
    var renderer = try render.Renderer.init(alloc, 20, 5);
    defer renderer.deinit();

    try container.widget.draw(&renderer);
    try std.testing.expect(!container.widget.dirty);

    container.setBorder(.single);
    try std.testing.expect(container.widget.dirty);
    try container.widget.draw(&renderer);
    try std.testing.expect(!container.widget.dirty);
    container.setBorder(.single);
    try std.testing.expect(!container.widget.dirty);

    container.setColors(
        render.Color.named(render.NamedColor.white),
        render.Color.named(render.NamedColor.black),
    );
    try std.testing.expect(container.widget.dirty);
    try container.widget.draw(&renderer);
    try std.testing.expect(!container.widget.dirty);
    container.setColors(
        render.Color.named(render.NamedColor.white),
        render.Color.named(render.NamedColor.black),
    );
    try std.testing.expect(!container.widget.dirty);

    container.setTheme(theme.Theme.dark());
    try std.testing.expect(container.widget.dirty);
    try container.widget.draw(&renderer);
    try std.testing.expect(!container.widget.dirty);
    container.setTheme(theme.Theme.dark());
    try std.testing.expect(!container.widget.dirty);

    try container.addChild(&first.widget);
    try std.testing.expect(!container.widget.dirty);

    try container.addChild(&second.widget);
    try std.testing.expect(container.widget.dirty);
    try container.widget.draw(&renderer);
    try std.testing.expect(!container.widget.dirty);

    try container.addChild(&first.widget);
    try std.testing.expect(container.widget.dirty);
    try container.widget.draw(&renderer);
    try std.testing.expect(!container.widget.dirty);

    container.removeChild(&first.widget);
    try std.testing.expect(container.widget.dirty);
}

test "container preferred size is zero without children" {
    const alloc = std.testing.allocator;
    var container = try Container.init(alloc);
    defer container.deinit();

    const size = try container.widget.getPreferredSize();
    try std.testing.expectEqual(@as(u16, 0), size.width);
    try std.testing.expectEqual(@as(u16, 0), size.height);
}

test "container clamps edge child layout coordinates" {
    const Dummy = struct {
        widget: base.Widget = base.Widget.init(&vtable),
        last_rect: ?layout_module.Rect = null,
        const Self = @This();

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
        fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
            const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
            const self: *Self = @fieldParentPtr("widget", widget_ref);
            self.last_rect = rect;
        }
        fn preferredFn(_: *anyopaque) anyerror!layout_module.Size {
            return layout_module.Size.init(1, 1);
        }
        fn canFocusFn(_: *anyopaque) bool {
            return false;
        }
    };

    const alloc = std.testing.allocator;
    var container = try Container.init(alloc);
    defer container.deinit();
    container.setBorder(.single);

    var child = Dummy{};
    try container.addChild(&child.widget);
    try container.widget.layout(layout_module.Rect.init(std.math.maxInt(u16), std.math.maxInt(u16), 4, 4));

    try std.testing.expect(child.last_rect != null);
    const inner = child.last_rect.?;
    try std.testing.expectEqual(@as(u16, std.math.maxInt(u16)), inner.x);
    try std.testing.expectEqual(@as(u16, std.math.maxInt(u16)), inner.y);
    try std.testing.expectEqual(@as(u16, 2), inner.width);
    try std.testing.expectEqual(@as(u16, 2), inner.height);
}

test "container preferred size saturates border inflation" {
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
            return layout_module.Size.init(std.math.maxInt(u16), std.math.maxInt(u16));
        }
        fn canFocusFn(_: *anyopaque) bool {
            return false;
        }
    };

    const alloc = std.testing.allocator;
    var container = try Container.init(alloc);
    defer container.deinit();
    container.setBorder(.single);

    var child = Dummy{};
    try container.addChild(&child.widget);

    const size = try container.widget.getPreferredSize();
    try std.testing.expectEqual(@as(u16, std.math.maxInt(u16)), size.width);
    try std.testing.expectEqual(@as(u16, std.math.maxInt(u16)), size.height);
}

test "container re-adds existing child without duplicate ownership" {
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
    var container = try Container.init(alloc);
    defer container.deinit();

    var child = Dummy{};
    try container.addChild(&child.widget);

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = container.allocator;
    container.allocator = failing.allocator();
    defer container.allocator = original_allocator;

    try container.addChild(&child.widget);
    try std.testing.expectEqual(@as(usize, 1), container.children.items.len);
    try std.testing.expectEqual(&child.widget, container.children.items[0]);
    try std.testing.expectEqual(&container.widget, child.widget.parent.?);
}

test "container add child preserves existing state when allocation fails" {
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
    var container = try Container.init(alloc);
    defer container.deinit();

    var existing = Dummy{};
    var new_child = Dummy{};
    try container.addChild(&existing.widget);
    container.children.deinit(alloc);
    container.children = .empty;
    try container.children.ensureTotalCapacityPrecise(alloc, 1);
    container.children.appendAssumeCapacity(&existing.widget);
    existing.widget.parent = &container.widget;

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = container.allocator;
    container.allocator = failing.allocator();
    defer container.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, container.addChild(&new_child.widget));
    try std.testing.expectEqual(@as(usize, 1), container.children.items.len);
    try std.testing.expectEqual(&existing.widget, container.children.items[0]);
    try std.testing.expectEqual(&container.widget, existing.widget.parent.?);
    try std.testing.expect(new_child.widget.parent == null);
}

test "container deinit detaches child parent links" {
    const alloc = std.testing.allocator;
    var container = try Container.init(alloc);

    var child = try @import("label.zig").Label.init(alloc, "child");
    defer child.deinit();

    try container.addChild(&child.widget);
    container.deinit();

    try std.testing.expect(child.widget.parent == null);
}

test "container rejects child attached to another collection parent" {
    const alloc = std.testing.allocator;
    var first = try Container.init(alloc);
    var second = try Container.init(alloc);
    var child = try @import("block.zig").Block.init(alloc);
    defer {
        first.deinit();
        second.deinit();
        child.deinit();
    }

    try first.addChild(&child.widget);
    try std.testing.expectError(error.WidgetAlreadyAttached, second.addChild(&child.widget));

    try std.testing.expectEqual(@as(usize, 1), first.children.items.len);
    try std.testing.expectEqual(&child.widget, first.children.items[0]);
    try std.testing.expectEqual(@as(usize, 0), second.children.items.len);
    try std.testing.expectEqual(&first.widget, child.widget.parent.?);
}
