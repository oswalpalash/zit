const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");

/// Button widget
pub const Button = struct {
    /// Base widget
    widget: base.Widget,
    /// Button label
    button_text: []const u8,
    /// Foreground color
    fg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    /// Background color
    bg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    /// Focused foreground color
    focused_fg: render.Color = render.Color{ .named_color = render.NamedColor.black },
    /// Focused background color
    focused_bg: render.Color = render.Color{ .named_color = render.NamedColor.cyan },
    /// Disabled foreground color
    disabled_fg: render.Color = render.Color{ .named_color = render.NamedColor.bright_black },
    /// Disabled background color
    disabled_bg: render.Color = render.Color{ .named_color = render.NamedColor.black },
    /// Text style
    style: render.Style = render.Style{},
    /// Border style
    border: render.BorderStyle = .single,
    /// Callback function for button press
    on_press: ?*const fn () void = null,
    /// Allocator for button operations
    allocator: std.mem.Allocator,
    
    /// Virtual method table for Button
    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };
    
    /// Initialize a new button
    pub fn init(allocator: std.mem.Allocator, button_text: []const u8) !*Button {
        const self = try allocator.create(Button);
        
        self.* = Button{
            .widget = base.Widget.init(&vtable),
            .button_text = try allocator.dupe(u8, button_text),
            .allocator = allocator,
        };
        
        return self;
    }
    
    /// Clean up button resources
    pub fn deinit(self: *Button) void {
        self.allocator.free(self.button_text);
        self.allocator.destroy(self);
    }
    
    /// Set the button label
    pub fn setText(self: *Button, text: []const u8) !void {
        self.allocator.free(self.button_text);
        self.button_text = try self.allocator.dupe(u8, text);
    }
    
    /// Set the button colors
    pub fn setColors(self: *Button, fg: render.Color, bg: render.Color, focused_fg: render.Color, focused_bg: render.Color) void {
        self.fg = fg;
        self.bg = bg;
        self.focused_fg = focused_fg;
        self.focused_bg = focused_bg;
    }
    
    /// Set the button disabled colors
    pub fn setDisabledColors(self: *Button, disabled_fg: render.Color, disabled_bg: render.Color) void {
        self.disabled_fg = disabled_fg;
        self.disabled_bg = disabled_bg;
    }
    
    /// Set the border style
    pub fn setBorder(self: *Button, border: render.BorderStyle) void {
        self.border = border;
    }
    
    /// Set the on-press callback
    pub fn setOnPress(self: *Button, callback: *const fn () void) void {
        self.on_press = callback;
    }
    
    /// Draw implementation for Button
    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*Button, @ptrCast(@alignCast(widget_ptr)));
        
        if (!self.widget.visible) {
            return;
        }
        
        const rect = self.widget.rect;
        
        // Choose colors based on state
        const fg = if (!self.widget.enabled) 
            self.disabled_fg 
        else if (self.widget.focused) 
            self.focused_fg 
        else 
            self.fg;
            
        const bg = if (!self.widget.enabled) 
            self.disabled_bg 
        else if (self.widget.focused) 
            self.focused_bg 
        else 
            self.bg;
        
        // Fill button background
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', fg, bg, self.style);
        
        // Draw border
        renderer.drawBox(rect.x, rect.y, rect.width, rect.height, self.border, fg, bg, self.style);
        
        // Draw text centered
        if (self.button_text.len > 0 and rect.width > 2 and rect.height > 2) {
            const inner_width = rect.width - 2;
            var truncated_text: [256]u8 = undefined;
            if (inner_width > 3 and self.button_text.len > inner_width - 3) {
                @memcpy(truncated_text[0..inner_width-3], self.button_text[0..inner_width-3]);
                @memcpy(truncated_text[inner_width-3..inner_width], "...");
                // Safely calculate text position to avoid overflow
                const text_len = @as(u16, @intCast(@min(inner_width, truncated_text.len)));
                const text_x = if (inner_width > text_len)
                    rect.x + 1 + (inner_width - text_len) / 2
                else
                    rect.x + 1;
                const text_y = rect.y + rect.height / 2;
                renderer.drawStr(text_x, text_y, truncated_text[0..inner_width], fg, bg, self.style);
            } else {
                // Safely calculate text position to avoid overflow
                const text_len = @as(u16, @intCast(@min(inner_width, self.button_text.len)));
                const text_x = if (inner_width > text_len)
                    rect.x + 1 + (inner_width - text_len) / 2
                else
                    rect.x + 1;
                const text_y = rect.y + rect.height / 2;
                renderer.drawStr(text_x, text_y, self.button_text, fg, bg, self.style);
            }
        }
    }
    
    /// Event handling implementation for Button
    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*Button, @ptrCast(@alignCast(widget_ptr)));
        
        if (!self.widget.visible or !self.widget.enabled) {
            return false;
        }
        
        switch (event) {
            .mouse => |mouse| {
                if (mouse.action == .press and mouse.button == 1) {
                    // Check if click is within button bounds
                    if (self.widget.rect.contains(mouse.x, mouse.y)) {
                        if (self.on_press) |callback| {
                            callback();
                        }
                        return true;
                    }
                }
            },
            .key => |key| {
                if (self.widget.focused and (key.key == '\n' or key.key == ' ')) {
                    if (self.on_press) |callback| {
                        callback();
                    }
                    return true;
                }
            },
            else => {},
        }
        
        return false;
    }
    
    /// Layout implementation for Button
    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*Button, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }
    
    /// Get preferred size implementation for Button
    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*Button, @ptrCast(@alignCast(widget_ptr)));
        
        // Button size should accommodate text plus borders
        return layout_module.Size.init(
            @as(u16, @intCast(@min(self.button_text.len + 4, 40))), // Cap width at 40 chars
            3 // Default height of 3 rows
        );
    }
    
    /// Can focus implementation for Button
    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*Button, @ptrCast(@alignCast(widget_ptr)));
        return self.widget.enabled;
    }
}; 