const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");

/// Tab item structure
pub const TabItem = struct {
    /// Tab title
    title: []const u8,
    /// Tab content widget
    content: *base.Widget,
};

/// Tab view widget for managing tabbed interfaces
pub const TabView = struct {
    /// Base widget
    widget: base.Widget,
    /// Tabs
    tabs: std.ArrayList(TabItem),
    /// Active tab index
    active_tab: usize = 0,
    /// Tab height
    tab_height: i16 = 1,
    /// Tab padding
    tab_padding: i16 = 1,
    /// Normal foreground color
    fg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    /// Normal background color
    bg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    /// Active tab foreground color
    active_fg: render.Color = render.Color{ .named_color = render.NamedColor.black },
    /// Active tab background color
    active_bg: render.Color = render.Color{ .named_color = render.NamedColor.cyan },
    /// Inactive tab foreground color
    inactive_fg: render.Color = render.Color{ .named_color = render.NamedColor.white },
    /// Inactive tab background color
    inactive_bg: render.Color = render.Color{ .named_color = render.NamedColor.blue },
    /// Border color
    border_fg: render.Color = render.Color{ .named_color = render.NamedColor.white },
    /// Show border
    show_border: bool = true,
    /// On tab changed callback
    on_tab_changed: ?*const fn (usize) void = null,
    /// Allocator for tab view operations
    allocator: std.mem.Allocator,
    
    /// Virtual method table for TabView
    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };
    
    /// Initialize a new tab view
    pub fn init(allocator: std.mem.Allocator) !*TabView {
        const self = try allocator.create(TabView);
        
        self.* = TabView{
            .widget = base.Widget.init(&vtable),
            .tabs = std.ArrayList(TabItem).init(allocator),
            .allocator = allocator,
        };
        
        return self;
    }
    
    /// Clean up tab view resources
    pub fn deinit(self: *TabView) void {
        for (self.tabs.items) |tab| {
            self.allocator.free(tab.title);
        }
        self.tabs.deinit();
        self.allocator.destroy(self);
    }
    
    /// Add a tab to the tab view
    pub fn addTab(self: *TabView, title: []const u8, content: *base.Widget) !void {
        // Copy the title
        const title_copy = try self.allocator.alloc(u8, title.len);
        std.mem.copy(u8, title_copy, title);
        
        // Add the tab
        try self.tabs.append(TabItem{
            .title = title_copy,
            .content = content,
        });
        
        // If this is the first tab, make it active
        if (self.tabs.items.len == 1) {
            self.setActiveTab(0);
        }
    }
    
    /// Remove a tab from the tab view
    pub fn removeTab(self: *TabView, index: usize) void {
        if (index >= self.tabs.items.len) {
            return;
        }
        
        // Free the title
        self.allocator.free(self.tabs.items[index].title);
        
        // Remove the tab
        _ = self.tabs.orderedRemove(index);
        
        // Update active tab if needed
        if (self.tabs.items.len == 0) {
            self.active_tab = 0;
        } else if (self.active_tab >= self.tabs.items.len) {
            self.setActiveTab(self.tabs.items.len - 1);
        } else if (self.active_tab == index) {
            self.setActiveTab(self.active_tab);
        }
    }
    
    /// Set the active tab
    pub fn setActiveTab(self: *TabView, index: usize) void {
        if (self.tabs.items.len == 0) {
            self.active_tab = 0;
            return;
        }
        
        const old_active = self.active_tab;
        self.active_tab = @min(index, self.tabs.items.len - 1);
        
        // Hide all tabs except the active one
        for (self.tabs.items, 0..) |tab, i| {
            tab.content.visible = (i == self.active_tab);
        }
        
        // Call the tab changed callback
        if (old_active != self.active_tab and self.on_tab_changed != null) {
            self.on_tab_changed.?(self.active_tab);
        }
    }
    
    /// Get the active tab index
    pub fn getActiveTab(self: *TabView) usize {
        return self.active_tab;
    }
    
    /// Get the active tab content widget
    pub fn getActiveContent(self: *TabView) ?*base.Widget {
        if (self.tabs.items.len == 0) {
            return null;
        }
        return self.tabs.items[self.active_tab].content;
    }
    
    /// Set the tab view colors
    pub fn setColors(self: *TabView, fg: render.Color, bg: render.Color, active_fg: render.Color, active_bg: render.Color, inactive_fg: render.Color, inactive_bg: render.Color) void {
        self.fg = fg;
        self.bg = bg;
        self.active_fg = active_fg;
        self.active_bg = active_bg;
        self.inactive_fg = inactive_fg;
        self.inactive_bg = inactive_bg;
    }
    
    /// Set the border options
    pub fn setBorder(self: *TabView, show_border: bool, border_fg: render.Color) void {
        self.show_border = show_border;
        self.border_fg = border_fg;
    }
    
    /// Set the on-tab-changed callback
    pub fn setOnTabChanged(self: *TabView, callback: *const fn (usize) void) void {
        self.on_tab_changed = callback;
    }
    
    /// Draw implementation for TabView
    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*TabView, @ptrCast(widget_ptr));
        
        if (!self.widget.visible) {
            return;
        }
        
        const rect = self.widget.rect;
        
        // Fill background
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', self.fg, self.bg, render.Style{});
        
        // Draw tabs
        var x = rect.x;
        for (self.tabs.items, 0..) |tab, i| {
            const is_active = i == self.active_tab;
            const tab_fg = if (is_active) self.active_fg else self.inactive_fg;
            const tab_bg = if (is_active) self.active_bg else self.inactive_bg;
            
            // Calculate tab width
            const tab_width = @as(i16, @intCast(tab.title.len)) + self.tab_padding * 2;
            
            // Draw tab background
            renderer.fillRect(x, rect.y, tab_width, self.tab_height, ' ', tab_fg, tab_bg, render.Style{});
            
            // Draw tab title
            const title_x = x + self.tab_padding;
            for (tab.title, 0..) |char, j| {
                if (j < tab_width - self.tab_padding * 2) {
                    renderer.drawChar(title_x + @as(i16, @intCast(j)), rect.y, char, tab_fg, tab_bg, render.Style{});
                }
            }
            
            x += tab_width + 1; // Space between tabs
            
            // If we've run out of space, stop drawing tabs
            if (x >= rect.x + rect.width) {
                break;
            }
        }
        
        // Calculate content area
        const content_y = rect.y + self.tab_height;
        const content_height = rect.height - self.tab_height;
        
        // Draw border if enabled
        if (self.show_border and content_height >= 2) {
            const style = render.Style{};
            
            // Top border
            renderer.drawChar(rect.x, content_y, '+', self.border_fg, self.bg, style);
            renderer.drawChar(rect.x + rect.width - 1, content_y, '+', self.border_fg, self.bg, style);
            for (0..@as(usize, rect.width - 2)) |i| {
                renderer.drawChar(rect.x + 1 + @as(i16, @intCast(i)), content_y, '-', self.border_fg, self.bg, style);
            }
            
            // Side borders
            for (0..@as(usize, content_height - 2)) |i| {
                renderer.drawChar(rect.x, content_y + 1 + @as(i16, @intCast(i)), '|', self.border_fg, self.bg, style);
                renderer.drawChar(rect.x + rect.width - 1, content_y + 1 + @as(i16, @intCast(i)), '|', self.border_fg, self.bg, style);
            }
            
            // Bottom border
            renderer.drawChar(rect.x, rect.y + rect.height - 1, '+', self.border_fg, self.bg, style);
            renderer.drawChar(rect.x + rect.width - 1, rect.y + rect.height - 1, '+', self.border_fg, self.bg, style);
            for (0..@as(usize, rect.width - 2)) |i| {
                renderer.drawChar(rect.x + 1 + @as(i16, @intCast(i)), rect.y + rect.height - 1, '-', self.border_fg, self.bg, style);
            }
        }
        
        // Draw active tab content
        if (self.tabs.items.len > 0) {
            try self.tabs.items[self.active_tab].content.draw(renderer);
        }
    }
    
    /// Calculate the index of the tab at the given position
    fn getTabIndexAt(self: *TabView, x: i16, y: i16) ?usize {
        if (y < self.widget.rect.y or y >= self.widget.rect.y + self.tab_height) {
            return null;
        }
        
        var tab_x = self.widget.rect.x;
        for (self.tabs.items, 0..) |tab, i| {
            const tab_width = @as(i16, @intCast(tab.title.len)) + self.tab_padding * 2;
            
            if (x >= tab_x and x < tab_x + tab_width) {
                return i;
            }
            
            tab_x += tab_width + 1; // Space between tabs
        }
        
        return null;
    }
    
    /// Event handling implementation for TabView
    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*TabView, @ptrCast(widget_ptr));
        
        if (!self.widget.visible or !self.widget.enabled or self.tabs.items.len == 0) {
            return false;
        }
        
        // First, check if the active tab content handles the event
        const active_content = self.tabs.items[self.active_tab].content;
        if (try active_content.handle_event(event)) {
            return true;
        }
        
        // If the content didn't handle it, check if we should
        if (event == .mouse) {
            const mouse_event = event.mouse;
            
            // Handle tab selection
            if (mouse_event.action == .press and mouse_event.button == 1) {
                if (self.getTabIndexAt(mouse_event.x, mouse_event.y)) |tab_index| {
                    self.setActiveTab(tab_index);
                    return true;
                }
            }
        }
        
        // Handle keyboard navigation between tabs
        if (event == .key and self.widget.focused) {
            const key_event = event.key;
            
            // Left/right arrows or h/l keys to change tabs
            if (key_event.key == 'h' or key_event.key == 'H' or key_event.key == 3) { // Left
                if (self.active_tab > 0) {
                    self.setActiveTab(self.active_tab - 1);
                    return true;
                }
            } else if (key_event.key == 'l' or key_event.key == 'L' or key_event.key == 4) { // Right
                if (self.active_tab < self.tabs.items.len - 1) {
                    self.setActiveTab(self.active_tab + 1);
                    return true;
                }
            } else if (key_event.key == '1' or key_event.key >= '1' and key_event.key <= '9') {
                // Number keys 1-9 to switch to specific tabs
                const tab_index = @as(usize, @intCast(key_event.key - '1'));
                if (tab_index < self.tabs.items.len) {
                    self.setActiveTab(tab_index);
                    return true;
                }
            }
        }
        
        return false;
    }
    
    /// Layout implementation for TabView
    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*TabView, @ptrCast(widget_ptr));
        self.widget.rect = rect;
        
        // Calculate content area
        var content_rect = rect;
        content_rect.y += self.tab_height;
        content_rect.height -= self.tab_height;
        
        // Adjust for border if enabled
        if (self.show_border and content_rect.height >= 2) {
            content_rect.x += 1;
            content_rect.y += 1;
            content_rect.width -= 2;
            content_rect.height -= 2;
        }
        
        // Layout all tab contents
        for (self.tabs.items) |tab| {
            try tab.content.layout(content_rect);
        }
    }
    
    /// Get preferred size implementation for TabView
    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*TabView, @ptrCast(widget_ptr));
        
        // Start with a minimum size
        var width: i16 = 20;
        var height: i16 = self.tab_height;
        
        // Calculate width needed for all tabs
        var tabs_width: i16 = 0;
        for (self.tabs.items) |tab| {
            tabs_width += @as(i16, @intCast(tab.title.len)) + self.tab_padding * 2 + 1; // +1 for space between tabs
        }
        width = @max(width, tabs_width);
        
        // Get preferred size of the active content
        if (self.tabs.items.len > 0) {
            const content = self.tabs.items[self.active_tab].content;
            const content_size = try content.get_preferred_size();
            
            // Add border space if enabled
            const border_space: i16 = if (self.show_border) 2 else 0;
            
            width = @max(width, content_size.width + border_space * 2);
            height += content_size.height + border_space * 2;
        } else {
            // Default minimum content height
            height += 10;
        }
        
        return layout_module.Size.init(width, height);
    }
    
    /// Can focus implementation for TabView
    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*TabView, @ptrCast(widget_ptr));
        
        if (!self.widget.enabled or self.tabs.items.len == 0) {
            return false;
        }
        
        // Check if any tab content can be focused
        for (self.tabs.items) |tab| {
            if (tab.content.can_focus()) {
                return true;
            }
        }
        
        return true; // We can still focus to switch tabs even if no content can focus
    }
}; 