const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");

/// Label widget for displaying text
pub const Label = struct {
    /// Base widget
    widget: base.Widget,
    /// Text content
    text: []const u8,
    /// Foreground color
    fg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    /// Background color
    bg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    /// Text style
    style: render.Style = render.Style{},
    /// Text alignment
    alignment: TextAlignment = .left,
    /// Allocator for label operations
    allocator: std.mem.Allocator,
    
    /// Text alignment options
    pub const TextAlignment = enum {
        left,
        center,
        right,
    };
    
    /// Virtual method table for Label
    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };
    
    /// Initialize a new label
    pub fn init(allocator: std.mem.Allocator, text: []const u8) !*Label {
        const self = try allocator.create(Label);
        
        self.* = Label{
            .widget = base.Widget.init(&vtable),
            .text = try allocator.dupe(u8, text),
            .allocator = allocator,
        };
        
        return self;
    }
    
    /// Clean up label resources
    pub fn deinit(self: *Label) void {
        self.allocator.free(self.text);
        self.allocator.destroy(self);
    }
    
    /// Set the label text
    pub fn setText(self: *Label, text: []const u8) !void {
        self.allocator.free(self.text);
        self.text = try self.allocator.dupe(u8, text);
    }
    
    /// Set the text alignment
    pub fn setAlignment(self: *Label, alignment: TextAlignment) void {
        self.alignment = alignment;
    }
    
    /// Set the text color
    pub fn setColor(self: *Label, fg: render.Color, bg: render.Color) void {
        self.fg = fg;
        self.bg = bg;
    }
    
    /// Set the text style
    pub fn setStyle(self: *Label, style: render.Style) void {
        self.style = style;
    }
    
    /// Draw implementation for Label
    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*Label, @ptrCast(@alignCast(widget_ptr)));
        
        if (!self.widget.visible) {
            return;
        }
        
        const rect = self.widget.rect;
        
        // Split text into lines
        var lines = std.ArrayList([]const u8).init(self.allocator);
        defer lines.deinit();
        
        var start: usize = 0;
        for (self.text, 0..) |c, i| {
            if (c == '\n') {
                try lines.append(self.text[start..i]);
                start = i + 1;
            }
        }
        if (start < self.text.len) {
            try lines.append(self.text[start..]);
        }
        
        // If no text, nothing to draw
        if (lines.items.len == 0) {
            return;
        }
        
        // Draw each line
        const max_lines = @min(lines.items.len, rect.height);
        for (0..max_lines) |i| {
            const line = lines.items[i];
            const y = rect.y + @as(u16, @intCast(i));
            
            // Calculate x position based on alignment
            var x: u16 = rect.x;
            if (self.alignment == .center) {
                if (line.len < rect.width) {
                    x = rect.x + (rect.width - @as(u16, @intCast(line.len))) / 2;
                }
            } else if (self.alignment == .right) {
                if (line.len < rect.width) {
                    x = rect.x + rect.width - @as(u16, @intCast(line.len));
                }
            }
            
            // Draw the line
            var truncated_text: [256]u8 = undefined;
            if (rect.width > 3 and line.len > rect.width - 3) {
                @memcpy(truncated_text[0..rect.width-3], line[0..rect.width-3]);
                @memcpy(truncated_text[rect.width-3..rect.width], "...");
                renderer.drawStr(x, y, truncated_text[0..rect.width], self.fg, self.bg, self.style);
            } else {
                renderer.drawStr(x, y, line, self.fg, self.bg, self.style);
            }
        }
    }
    
    /// Event handling implementation for Label
    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        _ = widget_ptr;
        _ = event;
        return false; // Labels don't handle events
    }
    
    /// Layout implementation for Label
    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*Label, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }
    
    /// Get preferred size implementation for Label
    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*Label, @ptrCast(@alignCast(widget_ptr)));
        
        // Split text into lines
        var lines = std.ArrayList([]const u8).init(self.allocator);
        defer lines.deinit();
        
        var start: usize = 0;
        for (self.text, 0..) |c, i| {
            if (c == '\n') {
                try lines.append(self.text[start..i]);
                start = i + 1;
            }
        }
        if (start < self.text.len) {
            try lines.append(self.text[start..]);
        }
        
        // Find longest line
        var max_width: usize = 0;
        for (lines.items) |line| {
            max_width = @max(max_width, line.len);
        }
        
        return layout_module.Size.init(
            @intCast(max_width),
            @intCast(lines.items.len)
        );
    }
    
    /// Can focus implementation for Label
    fn canFocusFn(widget_ptr: *anyopaque) bool {
        _ = widget_ptr;
        return false; // Labels can't be focused
    }
}; 