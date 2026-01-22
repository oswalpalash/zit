const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const theme = @import("../theme.zig");
const accessibility = @import("../accessibility.zig");

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
    /// Callback function for button click
    on_click: ?*const fn () void = null,
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
        self.setTheme(theme.Theme.dark());
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.button), self.button_text, "");

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
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.button), self.button_text, "");
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

    /// Set the on-click callback
    pub fn setOnClick(self: *Button, callback: *const fn () void) void {
        self.on_click = callback;
    }

    /// Apply theme defaults for button colors and text style.
    pub fn setTheme(self: *Button, theme_value: theme.Theme) void {
        const colors = theme.controlColors(theme_value);
        self.fg = colors.fg;
        self.bg = colors.bg;
        self.focused_fg = colors.focused_fg;
        self.focused_bg = colors.focused_bg;
        self.disabled_fg = colors.disabled_fg;
        self.disabled_bg = colors.disabled_bg;
        self.style = theme_value.style;
    }

    /// Draw implementation for Button
    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*Button, @ptrCast(@alignCast(widget_ptr)));

        if (!self.widget.visible) {
            return;
        }

        const rect = self.widget.rect;

        // Choose colors based on state
        const base_fg = if (!self.widget.enabled)
            self.disabled_fg
        else if (self.widget.focused)
            self.focused_fg
        else
            self.fg;

        const base_bg = if (!self.widget.enabled)
            self.disabled_bg
        else if (self.widget.focused)
            self.focused_bg
        else
            self.bg;

        const styled = self.widget.applyStyle(
            "button",
            .{ .focus = self.widget.focused, .disabled = !self.widget.enabled },
            self.style,
            base_fg,
            base_bg,
        );
        const fg = styled.fg;
        const bg = styled.bg;
        const style = styled.style;

        // Fill button background
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', fg, bg, style);

        // Draw border
        renderer.drawBox(rect.x, rect.y, rect.width, rect.height, self.border, fg, bg, style);

        // Draw text centered
        if (self.button_text.len > 0 and rect.width > 2 and rect.height > 2) {
            const inner_width = rect.width - 2;
            var truncated_text: [256]u8 = undefined;
            const max_width = @min(@as(usize, inner_width), truncated_text.len);
            if (max_width > 3 and self.button_text.len > max_width - 3) {
                @memcpy(truncated_text[0 .. max_width - 3], self.button_text[0 .. max_width - 3]);
                @memcpy(truncated_text[max_width - 3 .. max_width], "...");
                // Safely calculate text position to avoid overflow
                const text_len = @as(u16, @intCast(max_width));
                const text_x = if (inner_width > text_len)
                    rect.x + 1 + (inner_width - text_len) / 2
                else
                    rect.x + 1;
                const text_y = rect.y + rect.height / 2;
                renderer.drawStr(text_x, text_y, truncated_text[0..max_width], fg, bg, style);
            } else {
                // Safely calculate text position to avoid overflow
                const text_len = @as(u16, @intCast(@min(@as(usize, inner_width), self.button_text.len)));
                const text_x = if (inner_width > text_len)
                    rect.x + 1 + (inner_width - text_len) / 2
                else
                    rect.x + 1;
                const text_y = rect.y + rect.height / 2;
                renderer.drawStr(text_x, text_y, self.button_text, fg, bg, style);
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
                        if (self.on_click) |callback| {
                            callback();
                        }
                        return true;
                    }
                }
            },
            .key => |key| {
                if (self.widget.focused and (key.key == '\n' or key.key == ' ')) {
                    if (self.on_click) |callback| {
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

        // Calculate the preferred height based on text length
        const height: u16 = if (self.button_text.len > 30) 5 else 3; // Use taller button for longer text

        // Button size should accommodate text plus borders
        return layout_module.Size.init(@as(u16, @intCast(@min(self.button_text.len + 4, 40))), // Cap width at 40 chars
            height // Adjustable height
        );
    }

    /// Can focus implementation for Button
    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*Button, @ptrCast(@alignCast(widget_ptr)));
        return self.widget.enabled;
    }
};

var test_button_presses: usize = 0;

test "button init/deinit" {
    const alloc = std.testing.allocator;
    var button = try Button.init(alloc, "OK");
    defer button.deinit();

    try std.testing.expectEqualStrings("OK", button.button_text);
}

test "button triggers callback on press" {
    const alloc = std.testing.allocator;
    var button = try Button.init(alloc, "Go");
    defer button.deinit();

    test_button_presses = 0;
    const callback = struct {
        fn call() void {
            test_button_presses += 1;
        }
    }.call;
    button.setOnClick(callback);
    button.widget.rect = layout_module.Rect.init(0, 0, 6, 3);

    const click_event = input.Event{ .mouse = input.MouseEvent.init(.press, 1, 1, 1, 0) };
    try std.testing.expect(try button.widget.handleEvent(click_event));
    try std.testing.expectEqual(@as(usize, 1), test_button_presses);

    button.widget.focused = true;
    const key_event = input.Event{ .key = input.KeyEvent.init(' ', input.KeyModifiers{}) };
    try std.testing.expect(try button.widget.handleEvent(key_event));
    try std.testing.expectEqual(@as(usize, 2), test_button_presses);
}

test "button ignores presses when bounds are zero" {
    const alloc = std.testing.allocator;
    var button = try Button.init(alloc, "");
    defer button.deinit();

    test_button_presses = 0;
    const callback = struct {
        fn call() void {
            test_button_presses += 1;
        }
    }.call;
    button.setOnClick(callback);
    button.widget.rect = layout_module.Rect.init(0, 0, 0, 0);

    const click_event = input.Event{ .mouse = input.MouseEvent.init(.press, 0, 0, 1, 0) };
    try std.testing.expect(!try button.widget.handleEvent(click_event));
    try std.testing.expectEqual(@as(usize, 0), test_button_presses);
}
