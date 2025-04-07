const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");

/// List widget for displaying and selecting items
pub const List = struct {
    /// Base widget
    widget: base.Widget,
    /// List items
    items: std.ArrayList([]const u8),
    /// Selected item index
    selected_index: usize = 0,
    /// First visible item index
    first_visible_index: usize = 0,
    /// Visible items count
    visible_items_count: usize = 0,
    /// Normal foreground color
    fg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    /// Normal background color
    bg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    /// Selected foreground color
    selected_fg: render.Color = render.Color{ .named_color = render.NamedColor.black },
    /// Selected background color
    selected_bg: render.Color = render.Color{ .named_color = render.NamedColor.cyan },
    /// Focused foreground color
    focused_fg: render.Color = render.Color{ .named_color = render.NamedColor.black },
    /// Focused background color
    focused_bg: render.Color = render.Color{ .named_color = render.NamedColor.white },
    /// On selection changed callback
    on_selection_changed: ?*const fn (usize, []const u8) void = null,
    /// On item activated callback
    on_item_activated: ?*const fn (usize) void = null,
    /// Allocator for list operations
    allocator: std.mem.Allocator,
    /// Border style
    border: render.BorderStyle = .none,
    
    /// Virtual method table for List
    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };
    
    /// Initialize a new list
    pub fn init(allocator: std.mem.Allocator) !*List {
        const self = try allocator.create(List);
        
        self.* = List{
            .widget = base.Widget.init(&vtable),
            .items = std.ArrayList([]const u8).init(allocator),
            .allocator = allocator,
        };
        
        return self;
    }
    
    /// Clean up list resources
    pub fn deinit(self: *List) void {
        // Free all items
        for (self.items.items) |item| {
            self.allocator.free(item);
        }
        self.items.deinit();
        self.allocator.destroy(self);
    }
    
    /// Add an item to the list
    pub fn addItem(self: *List, item: []const u8) !void {
        const item_copy = try self.allocator.alloc(u8, item.len);
        @memcpy(item_copy, item);
        try self.items.append(item_copy);
    }
    
    /// Remove an item from the list
    pub fn removeItem(self: *List, index: usize) void {
        if (index >= self.items.items.len) {
            return;
        }
        
        // Free the item
        self.allocator.free(self.items.items[index]);
        
        // Remove the item
        _ = self.items.orderedRemove(index);
        
        // Update selected index if needed
        if (self.selected_index >= self.items.items.len) {
            self.setSelectedIndex(if (self.items.items.len > 0) self.items.items.len - 1 else 0);
        }
    }
    
    /// Clear all items from the list
    pub fn clear(self: *List) void {
        // Free all items
        for (self.items.items) |item| {
            self.allocator.free(item);
        }
        self.items.clearRetainingCapacity();
        self.setSelectedIndex(0);
    }
    
    /// Set the selected item
    pub fn setSelectedIndex(self: *List, index: usize) void {
        if (index == self.selected_index or self.items.items.len == 0) {
            return;
        }
        
        const old_index = self.selected_index;
        self.selected_index = @min(index, self.items.items.len - 1);
        
        // Ensure the selected item is visible
        self.ensureItemVisible(self.selected_index);
        
        // Call the selection changed callback
        if (old_index != self.selected_index and self.on_selection_changed != null) {
            self.on_selection_changed.?(self.selected_index, self.getSelectedItem() orelse "");
        }
    }
    
    /// Get the selected item
    pub fn getSelectedIndex(self: *List) usize {
        return self.selected_index;
    }
    
    /// Get the selected item text
    pub fn getSelectedItem(self: *List) ?[]const u8 {
        if (self.items.items.len == 0) {
            return null;
        }
        return self.items.items[self.selected_index];
    }
    
    /// Ensure the item at the given index is visible
    fn ensureItemVisible(self: *List, index: usize) void {
        if (index < self.first_visible_index) {
            self.first_visible_index = index;
        } else if (index >= self.first_visible_index + self.visible_items_count) {
            self.first_visible_index = index - self.visible_items_count + 1;
        }
    }
    
    /// Set the list colors
    pub fn setColors(self: *List, fg: render.Color, bg: render.Color, selected_fg: render.Color, selected_bg: render.Color) void {
        self.fg = fg;
        self.bg = bg;
        self.selected_fg = selected_fg;
        self.selected_bg = selected_bg;
    }
    
    /// Set the on-selection-changed callback
    pub fn setOnSelect(self: *List, callback: *const fn (usize, []const u8) void) void {
        self.on_selection_changed = callback;
    }
    
    /// Set the on-item-activated callback
    pub fn setOnItemActivated(self: *List, callback: *const fn (usize) void) void {
        self.on_item_activated = callback;
    }
    
    /// Set the border style
    pub fn setBorder(self: *List, border: render.BorderStyle) void {
        self.border = border;
    }
    
    /// Draw implementation for List
    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*List, @alignCast(@ptrCast(widget_ptr)));
        
        if (!self.widget.visible) {
            return;
        }
        
        const rect = self.widget.rect;
        
        // Fill list background
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', self.fg, self.bg, render.Style{});
        
        // Calculate visible items
        self.visible_items_count = @intCast(@as(usize, rect.height));
        if (self.visible_items_count == 0) {
            return;
        }
        
        // Ensure the first visible index is valid
        if (self.first_visible_index + self.visible_items_count > self.items.items.len) {
            self.first_visible_index = if (self.items.items.len > self.visible_items_count)
                self.items.items.len - self.visible_items_count
            else
                0;
        }
        
        // Draw visible items
        const last_visible_index = @min(self.first_visible_index + self.visible_items_count, self.items.items.len);
        
        var y = rect.y;
        var i = self.first_visible_index;
        while (i < last_visible_index) : (i += 1) {
            const item = self.items.items[i];
            const is_selected = i == self.selected_index;
            
            // Choose colors based on selection and focus state
            const item_fg = if (is_selected) 
                (if (self.widget.focused) self.focused_fg else self.selected_fg)
            else 
                self.fg;
            
            const item_bg = if (is_selected) 
                (if (self.widget.focused) self.focused_bg else self.selected_bg)
            else 
                self.bg;
            
            // Draw item background
            renderer.fillRect(rect.x, y, rect.width, 1, ' ', item_fg, item_bg, render.Style{});
            
            // Draw item text
            var x = rect.x;
            for (item) |char| {
                if (x - rect.x >= rect.width) {
                    break;
                }
                
                renderer.drawChar(x, y, char, item_fg, item_bg, render.Style{});
                x += 1;
            }
            
            y += 1;
        }
    }
    
    /// Event handling implementation for List
    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*List, @alignCast(@ptrCast(widget_ptr)));
        
        if (!self.widget.visible or !self.widget.enabled or self.items.items.len == 0) {
            return false;
        }
        
        // Handle mouse events
        if (event == .mouse) {
            const mouse_event = event.mouse;
            const rect = self.widget.rect;
            
            // Check if mouse is within list bounds
            if (rect.contains(mouse_event.x, mouse_event.y)) {
                // Convert y position to item index
                const item_index = self.first_visible_index + @as(usize, @intCast(mouse_event.y - rect.y));
                
                if (item_index < self.items.items.len) {
                    // Mouse click selects item
                    if (mouse_event.action == .press and mouse_event.button == 1) {
                        self.setSelectedIndex(item_index);
                        if (self.on_item_activated != null) {
                            self.on_item_activated.?(self.selected_index);
                        }
                        return true;
                    }
                }
                
                // Mouse wheel scrolls list
                if (mouse_event.action == .press and mouse_event.button == 4) { // Scroll up
                    if (self.first_visible_index > 0) {
                        self.first_visible_index -= 1;
                    }
                    return true;
                } else if (mouse_event.action == .press and mouse_event.button == 5) { // Scroll down
                    if (self.first_visible_index + self.visible_items_count < self.items.items.len) {
                        self.first_visible_index += 1;
                    }
                    return true;
                }
                
                return true; // Capture all mouse events within bounds
            }
        }
        
        // Handle key events
        if (event == .key and self.widget.focused) {
            const key_event = event.key;
            
            if (key_event.key == 'j' or key_event.key == 'J' or key_event.key == 2) { // Down
                if (self.selected_index < self.items.items.len - 1) {
                    self.setSelectedIndex(self.selected_index + 1);
                }
                return true;
            } else if (key_event.key == 'k' or key_event.key == 'K' or key_event.key == 3) { // Up
                if (self.selected_index > 0) {
                    self.setSelectedIndex(self.selected_index - 1);
                }
                return true;
            } else if (key_event.key == 6) { // Page down
                const new_index = @min(self.selected_index + self.visible_items_count, self.items.items.len - 1);
                self.setSelectedIndex(new_index);
                return true;
            } else if (key_event.key == 5) { // Page up
                const new_index = if (self.selected_index > self.visible_items_count)
                    self.selected_index - self.visible_items_count
                else
                    0;
                self.setSelectedIndex(new_index);
                return true;
            } else if (key_event.key == 7) { // Home
                self.setSelectedIndex(0);
                return true;
            } else if (key_event.key == 8) { // End
                self.setSelectedIndex(self.items.items.len - 1);
                return true;
            } else if (key_event.key == '\r' or key_event.key == '\n') { // Enter
                if (self.on_item_activated != null) {
                    self.on_item_activated.?(self.selected_index);
                }
                return true;
            }
        }
        
        return false;
    }
    
    /// Layout implementation for List
    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*List, @alignCast(@ptrCast(widget_ptr)));
        self.widget.rect = rect;
        
        // Update visible items count
        self.visible_items_count = @intCast(@as(usize, rect.height));
        
        // Ensure selected item is visible
        self.ensureItemVisible(self.selected_index);
    }
    
    /// Get preferred size implementation for List
    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*List, @alignCast(@ptrCast(widget_ptr)));
        
        // Find the longest item
        var max_width: u16 = 10; // Minimum width
        for (self.items.items) |item| {
            max_width = @max(max_width, @as(u16, @intCast(item.len)));
        }
        
        // Preferred height depends on number of items, with a minimum of 1
        const preferred_height = @as(u16, @intCast(@max(1, @min(10, @as(i16, @intCast(self.items.items.len))))));
        
        return layout_module.Size.init(max_width, preferred_height);
    }
    
    /// Can focus implementation for List
    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*List, @alignCast(@ptrCast(widget_ptr)));
        return self.widget.enabled and self.items.items.len > 0;
    }
}; 