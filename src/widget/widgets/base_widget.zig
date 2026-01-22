const std = @import("std");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const event_module = @import("../../event/event.zig");
const animation = @import("../animation.zig");
const container_widget = @import("container.zig");
const scroll_container_widget = @import("scroll_container.zig");
const split_pane_widget = @import("split_pane.zig");
const tab_view_widget = @import("tab_view.zig");
const block_widget = @import("block.zig");
const modal_widget = @import("modal.zig");
const screen_manager_widget = @import("screen_manager.zig");
const flex_container_widget = @import("flex_container.zig");
const grid_container_widget = @import("grid_container.zig");

/// Focus direction for navigation
pub const FocusDirection = enum {
    next,
    previous,
    up,
    down,
    left,
    right,
};

/// Base widget interface
pub const Widget = struct {
    /// Rectangle defining the widget's position and size
    rect: layout_module.Rect = layout_module.Rect.init(0, 0, 0, 0),
    /// Whether the widget is focused
    focused: bool = false,
    /// Whether the widget is visible
    visible: bool = true,
    /// Whether the widget is enabled
    enabled: bool = true,
    /// Widget ID for identification
    id: []const u8 = "",
    /// Optional style class used by stylesheet helpers
    style_class: ?[]const u8 = null,
    /// Optional focus ring styling
    focus_ring: ?render.FocusRingStyle = null,
    /// Animated visibility controller for show/hide transitions
    visibility_transition: animation.VisibilityController = .{},
    /// Parent widget, used primarily for modal dialogs and layout containment
    parent: ?*Widget = null,

    /// Virtual table for widget methods
    vtable: *const VTable,

    /// Virtual method table
    pub const VTable = struct {
        /// Draw the widget
        draw: *const fn (widget: *anyopaque, renderer: *render.Renderer) anyerror!void,
        /// Handle an input event
        handle_event: *const fn (widget: *anyopaque, event: input.Event) anyerror!bool,
        /// Layout the widget
        layout: *const fn (widget: *anyopaque, rect: layout_module.Rect) anyerror!void,
        /// Get preferred size
        get_preferred_size: *const fn (widget: *anyopaque) anyerror!layout_module.Size,
        /// Can focus
        can_focus: *const fn (widget: *anyopaque) bool,
    };

    /// Initialize a new widget
    pub fn init(vtable: *const VTable) Widget {
        return Widget{
            .vtable = vtable,
        };
    }

    /// Draw the widget
    pub fn draw(self: *Widget, renderer: *render.Renderer) !void {
        return self.vtable.draw(self, renderer);
    }

    /// Handle an input event
    pub fn handleEvent(self: *Widget, event: input.Event) !bool {
        if (!self.visible or !self.enabled or self.visibility_transition.isHiding()) {
            return false;
        }
        return self.vtable.handle_event(self, event);
    }

    /// Layout the widget
    pub fn layout(self: *Widget, rect: layout_module.Rect) !void {
        self.rect = rect;
        return self.vtable.layout(self, rect);
    }

    /// Get preferred size
    pub fn getPreferredSize(self: *Widget) !layout_module.Size {
        return self.vtable.get_preferred_size(self);
    }

    /// Check if widget can receive focus
    pub fn canFocus(self: *Widget) bool {
        if (!self.visible or !self.enabled) {
            return false;
        }
        return self.vtable.can_focus(self);
    }

    /// Set focus state
    pub fn setFocus(self: *Widget, focused: bool) void {
        self.focused = focused;
    }

    /// Set visibility
    pub fn setVisible(self: *Widget, visible: bool) void {
        self.visible = visible;
        self.visibility_transition.snap(visible);
    }

    /// Set enabled state
    pub fn setEnabled(self: *Widget, enabled: bool) void {
        self.enabled = enabled;
    }

    /// Set widget ID
    pub fn setId(self: *Widget, id: []const u8) void {
        self.id = id;
    }

    /// Set widget style class for CSS-like styling
    pub fn setClass(self: *Widget, class: ?[]const u8) void {
        self.style_class = class;
    }

    /// Set focus ring styling.
    pub fn setFocusRing(self: *Widget, ring: ?render.FocusRingStyle) void {
        self.focus_ring = ring;
    }

    /// Animate visibility using configured transitions. This keeps the widget
    /// renderable while fading/sliding out, then hides it when complete.
    pub fn animateVisibility(self: *Widget, animator: *animation.Animator, visible: bool, opts: animation.VisibilityOptions) !void {
        if (visible) {
            self.visible = true;
        }
        _ = try self.visibility_transition.animate(animator, visible, opts);
    }

    /// Current visibility alpha (1 when fully visible, 0 when hidden).
    pub fn visibilityAlpha(self: *Widget) f32 {
        return self.visibility_transition.alpha();
    }

    /// Set parent widget
    pub fn setParent(self: *Widget, parent: ?*Widget) void {
        self.parent = parent;
    }

    /// Traverse widget children depth-first and invoke a callback for each child.
    pub fn traverseChildren(widget: *Widget, callback: *const fn (*Widget) void) void {
        traverseChildrenImpl(widget, callback);
    }

    /// Draw a configurable focus ring if one is configured and the widget is focused.
    pub fn drawFocusRing(self: *Widget, renderer: *render.Renderer) void {
        if (!self.focused) return;
        const ring = self.focus_ring orelse return;

        if (self.rect.width <= ring.inset * 2 or self.rect.height <= ring.inset * 2) return;

        const ring_x = self.rect.x + ring.inset;
        const ring_y = self.rect.y + ring.inset;
        const ring_width = self.rect.width - ring.inset * 2;
        const ring_height = self.rect.height - ring.inset * 2;

        if (ring_width < 2 or ring_height < 2) return;

        if (ring.fill) |fill| {
            renderer.fillRect(ring_x, ring_y, ring_width, ring_height, ' ', ring.color, fill, ring.style);
        }

        renderer.drawBox(
            ring_x,
            ring_y,
            ring_width,
            ring_height,
            ring.border,
            ring.color,
            ring.fill orelse render.Color.named(render.NamedColor.default),
            ring.style,
        );
    }

    /// Adapter to create a LayoutElement from a Widget
    pub fn asLayoutElement(self: *Widget) layout_module.LayoutElement {
        return layout_module.LayoutElement{
            .layoutFn = widgetLayoutAdapter,
            .renderFn = widgetRenderAdapter,
            .ctx = @ptrCast(@alignCast(self)),
        };
    }
};

fn asWidget(comptime T: type, base_ptr: *Widget) ?*T {
    if (!@hasDecl(T, "vtable") or !@hasField(T, "widget")) return null;
    if (base_ptr.vtable == &T.vtable) {
        return @alignCast(@fieldParentPtr("widget", base_ptr));
    }
    return null;
}

fn traverseChildrenImpl(widget: *Widget, callback: *const fn (*Widget) void) void {
    if (asWidget(container_widget.Container, widget)) |container| {
        for (container.children.items) |child| {
            callback(child);
            traverseChildrenImpl(child, callback);
        }
        return;
    }

    if (asWidget(flex_container_widget.FlexContainer, widget)) |container| {
        for (container.children.items) |child| {
            callback(child);
            traverseChildrenImpl(child, callback);
        }
        return;
    }

    if (asWidget(grid_container_widget.GridContainer, widget)) |grid| {
        for (grid.children.items) |entry| {
            const child = entry.widget;
            callback(child);
            traverseChildrenImpl(child, callback);
        }
        return;
    }

    if (asWidget(scroll_container_widget.ScrollContainer, widget)) |container| {
        if (container.content) |child| {
            callback(child);
            traverseChildrenImpl(child, callback);
        }
        if (container.h_scrollbar) |bar| {
            const child = &bar.widget;
            callback(child);
            traverseChildrenImpl(child, callback);
        }
        if (container.v_scrollbar) |bar| {
            const child = &bar.widget;
            callback(child);
            traverseChildrenImpl(child, callback);
        }
        return;
    }

    if (asWidget(split_pane_widget.SplitPane, widget)) |pane| {
        if (pane.first) |child| {
            callback(child);
            traverseChildrenImpl(child, callback);
        }
        if (pane.second) |child| {
            callback(child);
            traverseChildrenImpl(child, callback);
        }
        return;
    }

    if (asWidget(tab_view_widget.TabView, widget)) |tabs| {
        const tab_bar_child = &tabs.tab_bar.widget;
        callback(tab_bar_child);
        traverseChildrenImpl(tab_bar_child, callback);
        for (tabs.tabs.items) |tab| {
            if (tab.content) |child| {
                callback(child);
                traverseChildrenImpl(child, callback);
            }
        }
        return;
    }

    if (asWidget(block_widget.Block, widget)) |block| {
        if (block.child) |child| {
            callback(child);
            traverseChildrenImpl(child, callback);
        }
        return;
    }

    if (asWidget(modal_widget.Modal, widget)) |modal| {
        if (modal.content) |child| {
            callback(child);
            traverseChildrenImpl(child, callback);
        }
        return;
    }

    if (asWidget(screen_manager_widget.ScreenManager, widget)) |manager| {
        for (manager.screens.items) |entry| {
            const child = entry.screen.widget;
            callback(child);
            traverseChildrenImpl(child, callback);
        }
    }
}

/// Adapter function to convert Widget layout to LayoutElement layout
fn widgetLayoutAdapter(ctx: *anyopaque, constraints: layout_module.Constraints) layout_module.Size {
    const widget = @as(*Widget, @ptrCast(@alignCast(ctx)));

    // Create a rect from the constraints
    const rect = layout_module.Rect{
        .x = 0,
        .y = 0,
        .width = constraints.max_width,
        .height = constraints.max_height,
    };

    // Layout the widget
    widget.layout(rect) catch |err| {
        logWidgetError(widget, "layout", err);
        return layout_module.Size.zero();
    };

    // Return the preferred size constrained by the constraints
    const preferred_size = widget.getPreferredSize() catch |err| {
        logWidgetError(widget, "preferred size", err);
        return layout_module.Size.zero();
    };
    return layout_module.Size{
        .width = @min(preferred_size.width, constraints.max_width),
        .height = @min(preferred_size.height, constraints.max_height),
    };
}

/// Adapter function to convert Widget draw to LayoutElement render
fn widgetRenderAdapter(ctx: *anyopaque, renderer: *render.Renderer, rect: layout_module.Rect) void {
    const widget = @as(*Widget, @ptrCast(@alignCast(ctx)));

    var draw_rect = rect;
    const disp = widget.visibility_transition.displacement();
    if (disp.dx != 0 or disp.dy != 0) {
        const new_x_i32: i32 = @as(i32, @intCast(rect.x)) + disp.dx;
        const new_y_i32: i32 = @as(i32, @intCast(rect.y)) + disp.dy;
        const new_x: u16 = if (new_x_i32 < 0) 0 else @intCast(new_x_i32);
        const new_y: u16 = if (new_y_i32 < 0) 0 else @intCast(new_y_i32);
        draw_rect = layout_module.Rect.init(new_x, new_y, rect.width, rect.height);
    }

    // Set widget rect
    widget.rect = draw_rect;

    // Draw the widget
    widget.draw(renderer) catch |err| {
        logWidgetError(widget, "draw", err);
    };

    // Apply fade after drawing so we tint the rendered cells instead of erasing them.
    const alpha = widget.visibility_transition.alpha();
    if (widget.visibility_transition.options.mode == .fade and alpha < 0.999 and draw_rect.width > 0 and draw_rect.height > 0) {
        const fade_to = widget.visibility_transition.options.fade_to;
        const max_x = @min(draw_rect.x + draw_rect.width, renderer.back.width);
        const max_y = @min(draw_rect.y + draw_rect.height, renderer.back.height);
        var y: u16 = draw_rect.y;
        while (y < max_y) : (y += 1) {
            var x: u16 = draw_rect.x;
            while (x < max_x) : (x += 1) {
                const cell = renderer.back.getCell(x, y);
                cell.fg = render.mixColor(fade_to, cell.fg, alpha);
                cell.bg = render.mixColor(fade_to, cell.bg, alpha);
            }
        }
    }

    // When the hide animation completes, stop drawing and reject input.
    if (!widget.visibility_transition.target_visible and alpha <= 0.001) {
        widget.visible = false;
    }
}

fn logWidgetError(widget: *Widget, action: []const u8, err: anyerror) void {
    const builtin = @import("builtin");
    if (builtin.is_test) {
        return;
    }
    const id = if (widget.id.len > 0) widget.id else "<anonymous>";
    std.log.err(
        "zit.widget: {s} {s} failed with {s} (rect={d}x{d}+{d},{d}, visible={any}, enabled={any}). Tip: set an id for easier tracing and use zit.debug.LayoutDebugger to visualize bounds.",
        .{ id, action, @errorName(err), widget.rect.width, widget.rect.height, widget.rect.x, widget.rect.y, widget.visible, widget.enabled },
    );
}

test "layout adapter returns safe defaults on failure" {
    const failing_vtable = Widget.VTable{
        .draw = struct {
            fn draw(_: *anyopaque, _: *render.Renderer) anyerror!void {
                return error.ForcedDraw;
            }
        }.draw,
        .handle_event = struct {
            fn handle(_: *anyopaque, _: input.Event) anyerror!bool {
                return false;
            }
        }.handle,
        .layout = struct {
            fn layout(_: *anyopaque, _: layout_module.Rect) anyerror!void {
                return error.ForcedLayout;
            }
        }.layout,
        .get_preferred_size = struct {
            fn preferred(_: *anyopaque) anyerror!layout_module.Size {
                return error.ForcedPreferred;
            }
        }.preferred,
        .can_focus = struct {
            fn can(_: *anyopaque) bool {
                return true;
            }
        }.can,
    };

    const TestWidget = struct {
        widget: Widget = Widget.init(&failing_vtable),
    };

    var instance = TestWidget{};
    instance.widget.id = "failing";

    const element = instance.widget.asLayoutElement();
    const tight = layout_module.Constraints.tight(2, 2);
    const measured = element.layout(tight);
    try std.testing.expectEqual(layout_module.Size.zero(), measured);

    var renderer = try render.Renderer.init(std.testing.allocator, 2, 2);
    defer renderer.deinit();
    element.render(&renderer, layout_module.Rect.init(0, 0, 2, 2));

    // Buffer remains untouched because draw failed gracefully.
    try std.testing.expectEqual(@as(u21, ' '), renderer.back.getCell(0, 0).codepoint());
}
