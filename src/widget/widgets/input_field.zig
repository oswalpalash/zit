const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");

/// Input field widget for text entry
pub const InputField = struct {
    /// Base widget
    widget: base.Widget,
    /// Text content
    text: []u8,
    /// Current cursor position
    cursor: usize = 0,
    /// Maximum text length
    max_length: usize,
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
    /// Show border
    show_border: bool = true,
    /// Placeholder text
    placeholder: []const u8 = "",
    /// Whether placeholder memory is owned by this widget
    placeholder_owned: bool = false,
    /// On change callback
    on_change: ?*const fn ([]const u8) void = null,
    /// On submit callback
    on_submit: ?*const fn ([]const u8) void = null,
    /// Allocator for text operations
    allocator: std.mem.Allocator,

    /// Virtual method table for InputField
    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    /// Initialize a new input field
    pub fn init(allocator: std.mem.Allocator, max_length: usize) !*InputField {
        const self = try allocator.create(InputField);
        const initial_buffer = try allocator.alloc(u8, max_length);

        @memset(initial_buffer, 0);

        self.* = InputField{
            .widget = base.Widget.init(&vtable),
            .text = initial_buffer,
            .max_length = max_length,
            .allocator = allocator,
        };

        return self;
    }

    /// Clean up input field resources
    pub fn deinit(self: *InputField) void {
        if (self.placeholder_owned and self.placeholder.len > 0) {
            self.allocator.free(self.placeholder);
        }
        self.allocator.free(self.text);
        self.allocator.destroy(self);
    }

    /// Set the input field text
    pub fn setText(self: *InputField, text: []const u8) void {
        const len = @min(text.len, self.max_length);
        @memset(self.text, 0);
        @memcpy(self.text[0..len], text[0..len]);
        self.cursor = len;

        if (self.on_change) |callback| {
            callback(self.getText());
        }
    }

    /// Get the current text
    pub fn getText(self: *InputField) []const u8 {
        // Find the actual length (first null byte)
        var len: usize = 0;
        while (len < self.text.len and self.text[len] != 0) {
            len += 1;
        }
        return self.text[0..len];
    }

    /// Set the placeholder text. Existing owned placeholder memory is released before storing the new value.
    pub fn setPlaceholder(self: *InputField, placeholder: []const u8) !void {
        if (self.placeholder_owned and self.placeholder.len > 0) {
            self.allocator.free(self.placeholder);
        }

        if (placeholder.len == 0) {
            self.placeholder = "";
            self.placeholder_owned = false;
            return;
        }

        self.placeholder = try self.allocator.dupe(u8, placeholder);
        self.placeholder_owned = true;
    }

    /// Set the border style
    pub fn setBorder(self: *InputField, border: render.BorderStyle) void {
        self.border = border;
        self.show_border = border != .none;
    }

    /// Set the input field colors
    pub fn setColors(self: *InputField, fg: render.Color, bg: render.Color, focused_fg: render.Color, focused_bg: render.Color) void {
        self.fg = fg;
        self.bg = bg;
        self.focused_fg = focused_fg;
        self.focused_bg = focused_bg;
    }

    /// Set the on-change callback
    pub fn setOnChange(self: *InputField, callback: *const fn ([]const u8) void) void {
        self.on_change = callback;
    }

    /// Set the on-submit callback
    pub fn setOnSubmit(self: *InputField, callback: *const fn ([]const u8) void) void {
        self.on_submit = callback;
    }

    /// Draw implementation for InputField
    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*InputField, @ptrCast(@alignCast(widget_ptr)));

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

        // Fill input field background
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', fg, bg, self.style);

        // Draw border if enabled
        if (self.show_border) {
            renderer.drawBox(rect.x, rect.y, rect.width, rect.height, self.border, fg, bg, self.style);
        }

        // Get text content
        const content = self.getText();

        // Calculate content area
        const border_adjust: u16 = if (self.show_border) 1 else 0;
        const inner_x = rect.x + border_adjust;
        const inner_y = rect.y + rect.height / 2;
        const inner_width = if (rect.width > 2 * border_adjust) rect.width - 2 * border_adjust else 0;

        // Draw placeholder if no text
        if (content.len == 0 and self.placeholder.len > 0 and inner_width > 0) {
            if (self.placeholder.len <= inner_width) {
                renderer.drawStr(inner_x, inner_y, self.placeholder, fg, bg, self.style);
            } else if (inner_width > 3) {
                var truncated: [256]u8 = undefined;
                const copy_len: usize = @min(@as(usize, inner_width - 3), self.placeholder.len);
                const safe_len = @min(copy_len, truncated.len - 3);
                @memcpy(truncated[0..safe_len], self.placeholder[0..safe_len]);
                @memcpy(truncated[safe_len .. safe_len + 3], "...");
                renderer.drawStr(inner_x, inner_y, truncated[0 .. safe_len + 3], fg, bg, self.style);
            } else {
                const slice_len: usize = @intCast(inner_width);
                renderer.drawStr(inner_x, inner_y, self.placeholder[0..slice_len], fg, bg, self.style);
            }
        }
        // Otherwise draw text
        else if (content.len > 0 and inner_width > 0) {
            var rendered_len: usize = 0;
            if (content.len <= inner_width) {
                renderer.drawStr(inner_x, inner_y, content, fg, bg, self.style);
                rendered_len = content.len;
            } else if (inner_width > 3) {
                var truncated: [256]u8 = undefined;
                const copy_len: usize = @min(@as(usize, inner_width - 3), content.len);
                const safe_len = @min(copy_len, truncated.len - 3);
                @memcpy(truncated[0..safe_len], content[0..safe_len]);
                @memcpy(truncated[safe_len .. safe_len + 3], "...");
                rendered_len = safe_len + 3;
                renderer.drawStr(inner_x, inner_y, truncated[0..rendered_len], fg, bg, self.style);
            } else {
                const slice_len: usize = @intCast(inner_width);
                rendered_len = slice_len;
                renderer.drawStr(inner_x, inner_y, content[0..slice_len], fg, bg, self.style);
            }

            // Draw cursor if focused
            if (self.widget.focused and self.cursor <= rendered_len) {
                const cursor_x = inner_x + @as(u16, @intCast(self.cursor));
                renderer.drawChar(cursor_x, inner_y, '_', fg, bg, render.Style{ .underline = true });
            }
        }
    }

    /// Event handling implementation for InputField
    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*InputField, @ptrCast(@alignCast(widget_ptr)));

        if (!self.widget.visible or !self.widget.enabled) {
            return false;
        }

        // Only handle keyboard events when focused
        if (event == .key and self.widget.focused) {
            const key_event = event.key;
            const current_text = self.getText();

            switch (key_event.key) {
                '\n' => { // Enter
                    if (self.on_submit) |callback| {
                        callback(current_text);
                    }
                    return true;
                },
                8 => { // Backspace
                    if (self.cursor > 0 and current_text.len > 0) {
                        // Remove one character
                        const copy_len = current_text.len - self.cursor;
                        if (copy_len > 0) {
                            std.mem.copyForwards(u8, self.text[self.cursor - 1 ..], self.text[self.cursor .. self.cursor + copy_len]);
                        }
                        self.text[current_text.len - 1] = 0;
                        self.cursor -= 1;

                        if (self.on_change) |callback| {
                            callback(self.getText());
                        }
                    }
                    return true;
                },
                127 => { // Delete
                    if (self.cursor < current_text.len) {
                        // Remove one character at cursor
                        const copy_len = current_text.len - self.cursor - 1;
                        if (copy_len > 0) {
                            std.mem.copyForwards(u8, self.text[self.cursor..], self.text[self.cursor + 1 .. self.cursor + 1 + copy_len]);
                        }
                        self.text[current_text.len - 1] = 0;

                        if (self.on_change) |callback| {
                            callback(self.getText());
                        }
                    }
                    return true;
                },
                4 => { // Right arrow
                    if (self.cursor < current_text.len) {
                        self.cursor += 1;
                    }
                    return true;
                },
                3 => { // Left arrow
                    if (self.cursor > 0) {
                        self.cursor -= 1;
                    }
                    return true;
                },
                1 => { // Home
                    self.cursor = 0;
                    return true;
                },
                5 => { // End
                    self.cursor = current_text.len;
                    return true;
                },
                else => {
                    // Regular character input
                    if (key_event.key >= 32 and key_event.key <= 126 and current_text.len < self.max_length - 1) {
                        // Make room for the new character
                        if (self.cursor < current_text.len) {
                            std.mem.copyBackwards(u8, self.text[self.cursor + 1 .. current_text.len + 1], self.text[self.cursor..current_text.len]);
                        }
                        self.text[self.cursor] = @as(u8, @intCast(key_event.key));
                        self.cursor += 1;

                        if (self.on_change) |callback| {
                            callback(self.getText());
                        }
                        return true;
                    }
                },
            }
        }
        // Handle mouse events
        else if (event == .mouse) {
            const mouse_event = event.mouse;

            // Handle clicks to set focus
            if (mouse_event.action == .press and mouse_event.button == 1) {
                return self.widget.rect.contains(mouse_event.x, mouse_event.y);
            }
        }

        return false;
    }

    /// Layout implementation for InputField
    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*InputField, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    /// Get preferred size implementation for InputField
    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*InputField, @ptrCast(@alignCast(widget_ptr)));

        // Calculate width based on max length plus borders
        const border_adjust: u16 = if (self.show_border) 2 else 0;

        return layout_module.Size.init(@as(u16, @intCast(@min(self.max_length, 40))) + border_adjust, // Cap width at 40 chars
            1 + border_adjust // Default height plus borders
        );
    }

    /// Can focus implementation for InputField
    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*InputField, @ptrCast(@alignCast(widget_ptr)));
        return self.widget.enabled;
    }
};

test "input field placeholder can be replaced safely" {
    const alloc = std.testing.allocator;
    var field = try InputField.init(alloc, 32);
    defer field.deinit();

    try field.setPlaceholder("first");
    try field.setPlaceholder("second");
    try std.testing.expectEqualStrings("second", field.placeholder);
}
