const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");

/// Scrollbar orientation
pub const ScrollOrientation = enum {
    vertical,
    horizontal,
};

/// Scrollbar widget
pub const Scrollbar = struct {
    /// Base widget
    widget: base.Widget,
    /// Orientation (vertical or horizontal)
    orientation: ScrollOrientation = .vertical,
    /// Current value (0-1)
    value: f32 = 0,
    /// Thumb ratio (0-1)
    thumb_ratio: f32 = 0.1,
    /// Foreground color
    fg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    /// Background color
    bg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    /// Thumb color
    thumb_fg: render.Color = render.Color{ .named_color = render.NamedColor.bright_black },
    /// Focused foreground color
    focused_fg: render.Color = render.Color{ .named_color = render.NamedColor.black },
    /// Focused background color
    focused_bg: render.Color = render.Color{ .named_color = render.NamedColor.cyan },
    /// On value changed callback
    on_value_changed: ?*const fn (f32) void = null,
    /// Dragging state
    dragging: bool = false,
    /// Drag start position
    drag_start_pos: i16 = 0,
    /// Drag start value
    drag_start_value: f32 = 0,
    /// Allocator for scrollbar operations
    allocator: std.mem.Allocator,
    
    /// Virtual method table for Scrollbar
    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };
    
    /// Initialize a new scrollbar
    pub fn init(allocator: std.mem.Allocator, orientation: ScrollOrientation) !*Scrollbar {
        const self = try allocator.create(Scrollbar);
        
        self.* = Scrollbar{
            .widget = base.Widget.init(&vtable),
            .orientation = orientation,
            .allocator = allocator,
        };
        
        return self;
    }
    
    /// Clean up scrollbar resources
    pub fn deinit(self: *Scrollbar) void {
        self.allocator.destroy(self);
    }
    
    /// Set the scrollbar value (0-1)
    pub fn setValue(self: *Scrollbar, value: f32) void {
        const old_value = self.value;
        self.value = std.math.clamp(value, 0, 1);
        
        if (old_value != self.value and self.on_value_changed != null) {
            self.on_value_changed.?(self.value);
        }
    }
    
    /// Get the current value
    pub fn getValue(self: *Scrollbar) f32 {
        return self.value;
    }
    
    /// Set the thumb ratio (0-1)
    pub fn setThumbRatio(self: *Scrollbar, ratio: f32) void {
        self.thumb_ratio = std.math.clamp(ratio, 0.1, 1);
    }
    
    /// Set the scrollbar colors
    pub fn setColors(self: *Scrollbar, fg: render.Color, bg: render.Color, thumb_fg: render.Color) void {
        self.fg = fg;
        self.bg = bg;
        self.thumb_fg = thumb_fg;
    }
    
    /// Set the on-value-changed callback
    pub fn setOnValueChanged(self: *Scrollbar, callback: *const fn (f32) void) void {
        self.on_value_changed = callback;
    }
    
    /// Draw implementation for Scrollbar
    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*Scrollbar, @ptrCast(widget_ptr));
        
        if (!self.widget.visible) {
            return;
        }
        
        const rect = self.widget.rect;
        
        // Choose colors based on state
        const bg = if (!self.widget.enabled) 
            self.bg 
        else if (self.widget.focused) 
            self.focused_bg 
        else 
            self.bg;
        
        const fg = if (!self.widget.enabled) 
            self.fg 
        else if (self.widget.focused) 
            self.focused_fg 
        else 
            self.fg;
        
        // Fill scrollbar background
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', fg, bg, render.Style{});
        
        // Draw thumb
        if (self.orientation == .vertical) {
            if (rect.height > 2) {
                const track_height = @as(f32, @floatFromInt(rect.height));
                const thumb_height = @as(i16, @intFromFloat(@max(1, track_height * self.thumb_ratio)));
                const thumb_pos = @as(i16, @intFromFloat(@min(track_height - @as(f32, @floatFromInt(thumb_height)), track_height * self.value)));
                
                renderer.fillRect(rect.x, rect.y + thumb_pos, rect.width, thumb_height, ' ', self.thumb_fg, self.thumb_fg, render.Style{});
            }
        } else {
            if (rect.width > 2) {
                const track_width = @as(f32, @floatFromInt(rect.width));
                const thumb_width = @as(i16, @intFromFloat(@max(1, track_width * self.thumb_ratio)));
                const thumb_pos = @as(i16, @intFromFloat(@min(track_width - @as(f32, @floatFromInt(thumb_width)), track_width * self.value)));
                
                renderer.fillRect(rect.x + thumb_pos, rect.y, thumb_width, rect.height, ' ', self.thumb_fg, self.thumb_fg, render.Style{});
            }
        }
    }
    
    /// Event handling implementation for Scrollbar
    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*Scrollbar, @ptrCast(widget_ptr));
        
        if (!self.widget.visible or !self.widget.enabled) {
            return false;
        }
        
        // Handle mouse events
        if (event == .mouse) {
            const mouse_event = event.mouse;
            const rect = self.widget.rect;
            
            // Check if mouse is within scrollbar bounds
            if (rect.contains(mouse_event.x, mouse_event.y)) {
                // Mouse press starts dragging
                if (mouse_event.action == .press and mouse_event.button == 1) {
                    self.dragging = true;
                    if (self.orientation == .vertical) {
                        self.drag_start_pos = mouse_event.y;
                    } else {
                        self.drag_start_pos = mouse_event.x;
                    }
                    self.drag_start_value = self.value;
                    return true;
                }
                // Mouse wheel scrolls
                else if (mouse_event.action == .scroll) {
                    if (mouse_event.scroll_y < 0) {
                        self.setValue(self.value + 0.1);
                    } else if (mouse_event.scroll_y > 0) {
                        self.setValue(self.value - 0.1);
                    }
                    return true;
                }
            }
            
            // Handle mouse release (end dragging)
            if (self.dragging and mouse_event.action == .release) {
                self.dragging = false;
                return true;
            }
            
            // Handle mouse movement while dragging
            if (self.dragging and mouse_event.action == .motion) {
                if (self.orientation == .vertical) {
                    const track_height = @as(f32, @floatFromInt(rect.height));
                    const delta = @as(f32, @floatFromInt(mouse_event.y - self.drag_start_pos));
                    const delta_value = delta / track_height;
                    
                    var new_value = self.drag_start_value + delta_value;
                    new_value = std.math.clamp(new_value, 0, 1);
                    
                    self.setValue(new_value);
                } else {
                    const track_width = @as(f32, @floatFromInt(rect.width));
                    const delta = @as(f32, @floatFromInt(mouse_event.x - self.drag_start_pos));
                    const delta_value = delta / track_width;
                    
                    var new_value = self.drag_start_value + delta_value;
                    new_value = std.math.clamp(new_value, 0, 1);
                    
                    self.setValue(new_value);
                }
                return true;
            }
        }
        
        // Handle key events
        if (event == .key and self.widget.focused) {
            const key_event = event.key;
            
            if (self.orientation == .vertical) {
                if (key_event.key == 'j' or key_event.key == 'J' or key_event.key == input.KeyCode.down) { // Down
                    self.setValue(self.value + 0.1);
                    return true;
                } else if (key_event.key == 'k' or key_event.key == 'K' or key_event.key == input.KeyCode.up) { // Up
                    self.setValue(self.value - 0.1);
                    return true;
                } else if (key_event.key == input.KeyCode.page_down) { // Page down
                    self.setValue(self.value + 0.25);
                    return true;
                } else if (key_event.key == input.KeyCode.page_up) { // Page up
                    self.setValue(self.value - 0.25);
                    return true;
                } else if (key_event.key == input.KeyCode.home) { // Home
                    self.setValue(0);
                    return true;
                } else if (key_event.key == input.KeyCode.end) { // End
                    self.setValue(1);
                    return true;
                }
            } else {
                if (key_event.key == 'l' or key_event.key == 'L' or key_event.key == input.KeyCode.right) { // Right
                    self.setValue(self.value + 0.1);
                    return true;
                } else if (key_event.key == 'h' or key_event.key == 'H' or key_event.key == input.KeyCode.left) { // Left
                    self.setValue(self.value - 0.1);
                    return true;
                } else if (key_event.key == input.KeyCode.page_right) { // Page right
                    self.setValue(self.value + 0.25);
                    return true;
                } else if (key_event.key == input.KeyCode.page_left) { // Page left
                    self.setValue(self.value - 0.25);
                    return true;
                } else if (key_event.key == input.KeyCode.home) { // Home
                    self.setValue(0);
                    return true;
                } else if (key_event.key == input.KeyCode.end) { // End
                    self.setValue(1);
                    return true;
                }
            }
        }
        
        return false;
    }
    
    /// Layout implementation for Scrollbar
    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*Scrollbar, @ptrCast(widget_ptr));
        self.widget.rect = rect;
    }
    
    /// Get preferred size implementation for Scrollbar
    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*Scrollbar, @ptrCast(widget_ptr));
        
        if (self.orientation == .vertical) {
            return layout_module.Size.init(1, 10); // Default vertical scrollbar size
        } else {
            return layout_module.Size.init(10, 1); // Default horizontal scrollbar size
        }
    }
    
    /// Can focus implementation for Scrollbar
    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*Scrollbar, @ptrCast(widget_ptr));
        return self.widget.enabled;
    }
}; 