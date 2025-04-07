const std = @import("std");
const base = @import("base_widget.zig");
const Widget = base.Widget;
const layout_module = @import("../../layout/layout.zig");
const Size = layout_module.Size;
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");

/// Modal dialog widget
pub const Modal = struct {
    /// Base widget
    widget: Widget,
    /// Content widget
    content: ?*Widget = null,
    /// Modal title
    title: []const u8 = "",
    /// Modal width
    width: u16 = 40,
    /// Modal height
    height: u16 = 10,
    /// Show title
    show_title: bool = true,
    /// Title foreground color
    title_fg: render.Color = render.Color{ .named_color = render.NamedColor.white },
    /// Title background color
    title_bg: render.Color = render.Color{ .named_color = render.NamedColor.blue },
    /// Foreground color
    fg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    /// Background color
    bg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    /// Border foreground color
    border_fg: render.Color = render.Color{ .named_color = render.NamedColor.white },
    /// Show border
    show_border: bool = true,
    /// Modal is centered
    centered: bool = true,
    /// Close on escape key
    close_on_escape: bool = true,
    /// On close callback
    on_close: ?*const fn () void = null,
    /// Allocator for modal operations
    allocator: std.mem.Allocator,
    
    /// Virtual method table for Modal
    pub const vtable = Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };
    
    /// Initialize a new modal
    pub fn init(allocator: std.mem.Allocator) !*Modal {
        const self = try allocator.create(Modal);
        self.* = Modal{
            .widget = Widget{
                .vtable = &vtable,
            },
            .width = 40,
            .height = 10,
            .allocator = allocator,
            .title = "",
            .content = null,
        };
        return self;
    }
    
    /// Clean up modal resources
    pub fn deinit(self: *Modal) void {
        if (self.title.len > 0) {
            self.allocator.free(self.title);
        }
        self.allocator.destroy(self);
    }
    
    /// Set the modal content
    pub fn setContent(self: *Modal, content: *Widget) void {
        self.content = content;
    }
    
    /// Set the modal title
    pub fn setTitle(self: *Modal, title: []const u8) !void {
        if (self.title.len > 0) {
            self.allocator.free(self.title);
        }
        
        const title_copy = try self.allocator.alloc(u8, title.len);
        @memcpy(title_copy, title);
        self.title = title_copy;
    }
    
    /// Set the modal colors
    pub fn setColors(self: *Modal, fg: render.Color, bg: render.Color, border_fg: render.Color) void {
        self.fg = fg;
        self.bg = bg;
        self.border_fg = border_fg;
    }
    
    /// Set the title colors
    pub fn setTitleColors(self: *Modal, title_fg: render.Color, title_bg: render.Color) void {
        self.title_fg = title_fg;
        self.title_bg = title_bg;
    }
    
    /// Set whether to show the title
    pub fn setShowTitle(self: *Modal, show_title: bool) void {
        self.show_title = show_title;
    }
    
    /// Set whether to show the border
    pub fn setShowBorder(self: *Modal, show_border: bool) void {
        self.show_border = show_border;
    }
    
    /// Set whether the modal is centered
    pub fn setCentered(self: *Modal, centered: bool) void {
        self.centered = centered;
    }
    
    /// Set whether to close on escape key
    pub fn setCloseOnEscape(self: *Modal, close_on_escape: bool) void {
        self.close_on_escape = close_on_escape;
    }
    
    /// Set the on-close callback
    pub fn setOnClose(self: *Modal, callback: *const fn () void) void {
        self.on_close = callback;
    }
    
    /// Close the modal
    pub fn close(self: *Modal) void {
        self.widget.visible = false;
        
        if (self.on_close != null) {
            self.on_close.?();
        }
    }
    
    /// Draw implementation for Modal
    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*Modal, @alignCast(@ptrCast(widget_ptr)));
        
        if (!self.widget.visible) {
            return;
        }
        
        const rect = self.widget.rect;
        const style = render.Style{};
        
        // Draw border
        for (0..rect.width) |i| {
            renderer.drawChar(rect.x + @as(u16, @intCast(i)), rect.y, '-', self.border_fg, self.bg, style);
            renderer.drawChar(rect.x + @as(u16, @intCast(i)), rect.y + rect.height - 1, '-', self.border_fg, self.bg, style);
        }
        
        // Draw title if enabled
        if (self.show_title and self.title.len > 0) {
            const title_y = rect.y;
            
            // Draw title background
            renderer.fillRect(rect.x + 1, title_y, rect.width - 2, 1, ' ', self.title_fg, self.title_bg, style);
            
            // Draw title text
            const title_x = rect.x + @as(u16, @intCast(@divTrunc(@as(i16, @intCast(rect.width)) - @as(i16, @intCast(self.title.len)), 2)));
            for (self.title, 0..) |char, i| {
                renderer.drawChar(title_x + @as(u16, @intCast(i)), title_y, char, self.title_fg, self.title_bg, style);
            }
        }
        
        // Draw content
        if (self.content) |content| {
            try content.draw(renderer);
        }
    }
    
    /// Event handling implementation for Modal
    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*Modal, @alignCast(@ptrCast(widget_ptr)));
        
        if (!self.widget.visible or !self.widget.enabled) {
            return false;
        }
        
        // Pass event to content first
        if (self.content) |content| {
            if (try content.handleEvent(event)) {
                return true;
            }
        }
        
        // Close on escape key if enabled
        if (event == .key and self.close_on_escape) {
            const key_event = event.key;
            
            if (key_event.key == 27) { // Escape key
                self.close();
                return true;
            }
        }
        
        return false;
    }
    
    /// Layout implementation for Modal
    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*Modal, @alignCast(@ptrCast(widget_ptr)));
        
        var modal_rect = rect;
        
        // Center modal in available space
        const pref_size = try self.getPreferredSize();
        modal_rect.width = @min(pref_size.width, rect.width);
        modal_rect.height = @min(pref_size.height, rect.height);
        modal_rect.x = rect.x + @divTrunc(rect.width - modal_rect.width, 2);
        modal_rect.y = rect.y + @divTrunc(rect.height - modal_rect.height, 2);
        
        self.widget.rect = modal_rect;
        
        // Layout content if present
        if (self.content) |content| {
            const content_rect = layout_module.Rect.init(
                modal_rect.x + 1,
                modal_rect.y + 2,
                modal_rect.width - 2,
                modal_rect.height - 3
            );
            try content.layout(content_rect);
        }
    }
    
    /// Get preferred size implementation for Modal
    fn getPreferredSize(self: *Modal) anyerror!layout_module.Size {
        var width: u16 = self.width;
        var height: u16 = self.height;
        
        // Account for content size
        if (self.content) |content| {
            const content_size = try content.getPreferredSize();
            width = @max(width, content_size.width + 2);
            height = @max(height, content_size.height + 3);
        }
        
        return layout_module.Size.init(width, height);
    }
    
    /// Can focus implementation for Modal
    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*Modal, @alignCast(@ptrCast(widget_ptr)));
        
        if (!self.widget.enabled) {
            return false;
        }
        
        // Modal can be focused if it has focusable content
        if (self.content) |content| {
            return content.canFocus();
        }
        
        return false;
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!Size {
        const self = @as(*Modal, @ptrCast(@alignCast(widget_ptr)));
        return Size{ .width = self.width, .height = self.height };
    }
}; 