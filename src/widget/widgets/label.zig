const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const text_metrics = @import("../../render/text_metrics.zig");
const input = @import("../../input/input.zig");
const theme = @import("../theme.zig");

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
        self.setTheme(theme.Theme.dark());

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

    /// Apply theme defaults for label colors and text style.
    pub fn setTheme(self: *Label, theme_value: theme.Theme) void {
        const colors = theme.textColors(theme_value);
        self.fg = colors.fg;
        self.bg = colors.bg;
        self.style = colors.style;
    }

    /// Draw implementation for Label
    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*Label, @ptrCast(@alignCast(widget_ptr)));

        if (!self.widget.visible) {
            return;
        }

        const rect = self.widget.rect;
        const styled = self.widget.applyStyle(
            "label",
            .{ .focus = self.widget.focused, .disabled = !self.widget.enabled },
            self.style,
            self.fg,
            self.bg,
        );
        const fg = styled.fg;
        const bg = styled.bg;
        const style = styled.style;

        if (self.text.len == 0 or rect.height == 0) {
            return;
        }

        var line_idx: u16 = 0;
        var start: usize = 0;
        var i: usize = 0;
        while (i <= self.text.len) : (i += 1) {
            const at_end = i == self.text.len;
            if (!at_end and self.text[i] != '\n') continue;
            if (line_idx >= rect.height) break;

            const line = self.text[start..i];
            const y = rect.y + line_idx;

            var truncated_text: [256]u8 = undefined;
            const draw_text = text_metrics.truncateToWidth(line, rect.width, &truncated_text, true);
            const draw_width = text_metrics.measureWidth(draw_text).width;

            // Calculate x position based on alignment
            var x: u16 = rect.x;
            if (self.alignment == .center) {
                if (draw_width < rect.width) {
                    x = rect.x + (rect.width - draw_width) / 2;
                }
            } else if (self.alignment == .right) {
                if (draw_width < rect.width) {
                    x = rect.x + rect.width - draw_width;
                }
            }

            // Draw the line
            renderer.drawStr(x, y, draw_text, fg, bg, style);

            line_idx += 1;
            if (!at_end) {
                start = i + 1;
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

        if (self.text.len == 0) {
            return layout_module.Size.zero();
        }

        var max_width: u16 = 0;
        var lines: u16 = 0;
        var start: usize = 0;
        var i: usize = 0;
        while (i <= self.text.len) : (i += 1) {
            const at_end = i == self.text.len;
            if (!at_end and self.text[i] != '\n') continue;
            const line = self.text[start..i];
            const line_width = text_metrics.measureWidth(line).width;
            max_width = @max(max_width, line_width);
            lines += 1;
            if (!at_end) {
                start = i + 1;
            }
        }

        return layout_module.Size.init(max_width, lines);
    }

    /// Can focus implementation for Label
    fn canFocusFn(widget_ptr: *anyopaque) bool {
        _ = widget_ptr;
        return false; // Labels can't be focused
    }
};

test "label init/deinit" {
    const alloc = std.testing.allocator;
    var label = try Label.init(alloc, "Hello");
    defer label.deinit();

    try std.testing.expectEqualStrings("Hello", label.text);
}

test "label setText updates preferred size" {
    const alloc = std.testing.allocator;
    var label = try Label.init(alloc, "Hi");
    defer label.deinit();

    try label.setText("hi\nworld");
    const size = try label.widget.getPreferredSize();
    try std.testing.expectEqual(@as(u16, 5), size.width);
    try std.testing.expectEqual(@as(u16, 2), size.height);
}

test "label handles empty text" {
    const alloc = std.testing.allocator;
    var label = try Label.init(alloc, "");
    defer label.deinit();

    const size = try label.widget.getPreferredSize();
    try std.testing.expectEqual(@as(u16, 0), size.width);
    try std.testing.expectEqual(@as(u16, 0), size.height);
}
