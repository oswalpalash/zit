const std = @import("std");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const event_module = @import("../../event/event.zig");

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
        if (!self.visible or !self.enabled) {
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
    }

    /// Set enabled state
    pub fn setEnabled(self: *Widget, enabled: bool) void {
        self.enabled = enabled;
    }

    /// Set widget ID
    pub fn setId(self: *Widget, id: []const u8) void {
        self.id = id;
    }

    /// Set parent widget
    pub fn setParent(self: *Widget, parent: ?*Widget) void {
        self.parent = parent;
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
    widget.layout(rect) catch {};

    // Return the preferred size constrained by the constraints
    const preferred_size = widget.getPreferredSize() catch layout_module.Size.zero();
    return layout_module.Size{
        .width = @min(preferred_size.width, constraints.max_width),
        .height = @min(preferred_size.height, constraints.max_height),
    };
}

/// Adapter function to convert Widget draw to LayoutElement render
fn widgetRenderAdapter(ctx: *anyopaque, renderer: *render.Renderer, rect: layout_module.Rect) void {
    const widget = @as(*Widget, @ptrCast(@alignCast(ctx)));

    // Set widget rect
    widget.rect = rect;

    // Draw the widget
    widget.draw(renderer) catch {};
}
