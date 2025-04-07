const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");

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
            .children = std.ArrayList(*base.Widget).init(allocator),
            .allocator = allocator,
        };
        
        return self;
    }
    
    /// Clean up container resources
    pub fn deinit(self: *Container) void {
        self.children.deinit();
        self.allocator.destroy(self);
    }
    
    /// Add a child widget to the container
    pub fn addChild(self: *Container, child: *base.Widget) !void {
        try self.children.append(child);
        child.parent = &self.widget;
    }
    
    /// Remove a child widget from the container
    pub fn removeChild(self: *Container, child: *base.Widget) void {
        for (self.children.items, 0..) |c, i| {
            if (c == child) {
                _ = self.children.orderedRemove(i);
                child.parent = null;
                break;
            }
        }
    }
    
    /// Set the container colors
    pub fn setColors(self: *Container, fg: render.Color, bg: render.Color) void {
        self.fg = fg;
        self.bg = bg;
    }
    
    /// Set the border style
    pub fn setBorder(self: *Container, border: render.BorderStyle) void {
        self.border = border;
        self.show_border = border != .none;
    }
    
    /// Draw implementation for Container
    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*Container, @ptrCast(widget_ptr));
        
        if (!self.widget.visible) {
            return;
        }
        
        const rect = self.widget.rect;
        
        // Fill container background
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', self.fg, self.bg, render.Style{});
        
        // Draw border if enabled
        if (self.show_border) {
            renderer.drawBox(rect.x, rect.y, rect.width, rect.height, self.border, self.fg, self.bg, render.Style{});
        }
        
        // Draw children
        for (self.children.items) |child| {
            try child.draw(renderer);
        }
    }
    
    /// Event handling implementation for Container
    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*Container, @ptrCast(widget_ptr));
        
        if (!self.widget.visible or !self.widget.enabled) {
            return false;
        }
        
        // Pass event to children in reverse order (top-most first)
        var i: usize = self.children.items.len;
        while (i > 0) {
            i -= 1;
            const child = self.children.items[i];
            if (try child.handle_event(event)) {
                return true;
            }
        }
        
        return false;
    }
    
    /// Layout implementation for Container
    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*Container, @ptrCast(widget_ptr));
        self.widget.rect = rect;
        
        // Simple layout: just give each child the full container area
        // (can be overridden by more sophisticated container implementations)
        const border_adjust: u16 = if (self.show_border) 1 else 0;
        const inner_rect = layout_module.Rect.init(
            rect.x + border_adjust,
            rect.y + border_adjust,
            if (rect.width > 2 * border_adjust) rect.width - 2 * border_adjust else 0,
            if (rect.height > 2 * border_adjust) rect.height - 2 * border_adjust else 0
        );
        
        for (self.children.items) |child| {
            try child.layout(inner_rect);
        }
    }
    
    /// Get preferred size implementation for Container
    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*Container, @ptrCast(widget_ptr));
        
        // Start with minimum size
        var width: u16 = 0;
        var height: u16 = 0;
        
        // Calculate maximum size of all children
        for (self.children.items) |child| {
            const child_size = try child.get_preferred_size();
            width = @max(width, child_size.width);
            height = @max(height, child_size.height);
        }
        
        // Add border if needed
        const border_adjust: u16 = if (self.show_border) 2 else 0;
        width += border_adjust;
        height += border_adjust;
        
        return layout_module.Size.init(width, height);
    }
    
    /// Can focus implementation for Container
    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*Container, @ptrCast(widget_ptr));
        
        if (!self.widget.enabled) {
            return false;
        }
        
        // Container can be focused if any child can be focused
        for (self.children.items) |child| {
            if (child.can_focus()) {
                return true;
            }
        }
        
        return false;
    }
}; 