const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");

/// Progress bar direction
pub const ProgressDirection = enum {
    horizontal,
    vertical,
};

/// Progress bar widget
pub const ProgressBar = struct {
    /// Base widget
    widget: base.Widget,
    /// Direction (horizontal or vertical)
    direction: ProgressDirection = .horizontal,
    /// Current progress (0-100)
    progress: u8 = 0,
    /// Show text percentage
    show_text: bool = true,
    /// Progress character
    fill_char: u21 = '█',
    /// Foreground color
    fg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    /// Background color
    bg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    /// Progress fill color
    fill_fg: render.Color = render.Color{ .named_color = render.NamedColor.green },
    /// Progress background color
    fill_bg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    /// Allocator for progress bar operations
    allocator: std.mem.Allocator,
    /// Border style
    border: render.BorderStyle = .single,

    /// Virtual method table for ProgressBar
    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    /// Initialize a new progress bar
    pub fn init(allocator: std.mem.Allocator) !*ProgressBar {
        const self = try allocator.create(ProgressBar);

        self.* = ProgressBar{
            .widget = base.Widget.init(&vtable),
            .allocator = allocator,
        };

        return self;
    }

    /// Clean up progress bar resources
    pub fn deinit(self: *ProgressBar) void {
        self.allocator.destroy(self);
    }

    /// Set the progress bar direction
    pub fn setDirection(self: *ProgressBar, direction: ProgressDirection) void {
        self.direction = direction;
    }

    /// Set the progress value (0-100)
    pub fn setProgress(self: *ProgressBar, progress: u8) void {
        self.progress = @min(progress, 100);
    }

    /// Set the progress value (0-100)
    pub fn setValue(self: *ProgressBar, value: u8) void {
        self.setProgress(value);
    }

    /// Set whether to show text percentage
    pub fn setShowPercentage(self: *ProgressBar, show_text: bool) void {
        self.show_text = show_text;
    }

    /// Set the fill character
    pub fn setFillChar(self: *ProgressBar, fill_char: u21) void {
        self.fill_char = fill_char;
    }

    /// Set the progress bar colors
    pub fn setColors(self: *ProgressBar, fg: render.Color, bg: render.Color, fill_fg: render.Color, fill_bg: render.Color) void {
        self.fg = fg;
        self.bg = bg;
        self.fill_fg = fill_fg;
        self.fill_bg = fill_bg;
    }

    /// Set the border style
    pub fn setBorder(self: *ProgressBar, border: render.BorderStyle) void {
        self.border = border;
    }

    /// Draw implementation for ProgressBar
    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*ProgressBar, @ptrCast(@alignCast(widget_ptr)));

        if (!self.widget.visible) {
            return;
        }

        const rect = self.widget.rect;

        // Fill background
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', self.fg, self.bg, render.Style{});

        // Draw progress
        if (self.direction == .horizontal) {
            const progress_width = @as(u16, @intFromFloat(@as(f32, @floatFromInt(rect.width)) * @as(f32, @floatFromInt(self.progress)) / 100.0));

            if (progress_width > 0) {
                renderer.fillRect(rect.x, rect.y, progress_width, rect.height, self.fill_char, self.fill_fg, self.fill_bg, render.Style{});
            }

            // Show percentage text
            if (self.show_text and rect.width >= 5) {
                var buffer: [5]u8 = undefined;
                const text = std.fmt.bufPrintZ(&buffer, "{d}%", .{self.progress}) catch "";

                const half_width = @divTrunc(rect.width, 2);
                const text_len = @as(u16, @intCast(text.len));
                const half_text_len = @divTrunc(text_len, 2);
                const text_x = rect.x + @as(u16, @intCast(@max(0, half_width - half_text_len)));
                const text_y = rect.y + @divTrunc(rect.height, 2);

                for (text, 0..) |char, i| {
                    const x = text_x + @as(u16, @intCast(i));
                    const y = text_y;

                    // Choose text color based on position (in progress area or not)
                    const is_in_progress_area = x < rect.x + progress_width;
                    const text_fg = if (is_in_progress_area) self.bg else self.fg;
                    const text_bg = if (is_in_progress_area) self.fill_fg else self.bg;

                    renderer.drawChar(x, y, char, text_fg, text_bg, render.Style{});
                }
            }
        } else {
            const progress_height = @as(u16, @intFromFloat(@as(f32, @floatFromInt(rect.height)) * @as(f32, @floatFromInt(self.progress)) / 100.0));
            const start_y = rect.y + @as(u16, @intCast(@max(0, @as(i16, @intCast(rect.height)) - @as(i16, @intCast(progress_height)))));

            if (progress_height > 0) {
                renderer.fillRect(rect.x, start_y, rect.width, progress_height, self.fill_char, self.fill_fg, self.fill_bg, render.Style{});
            }

            // Show percentage text
            if (self.show_text and rect.height >= 1 and rect.width >= 4) {
                var buffer: [5]u8 = undefined;
                const text = std.fmt.bufPrintZ(&buffer, "{d}%", .{self.progress}) catch "";

                const text_x = rect.x + @as(u16, @intCast(@divTrunc(@as(i16, @intCast(rect.width)), 2) - @divTrunc(@as(i16, @intCast(text.len)), 2)));
                const text_y = rect.y + @divTrunc(rect.height, 2);

                for (text, 0..) |char, i| {
                    const x = text_x + @as(u16, @intCast(i));
                    const y = text_y;

                    // Choose text color based on position (in progress area or not)
                    const is_in_progress_area = y >= start_y;
                    const text_fg = if (is_in_progress_area) self.bg else self.fg;
                    const text_bg = if (is_in_progress_area) self.fill_fg else self.bg;

                    renderer.drawChar(x, y, char, text_fg, text_bg, render.Style{});
                }
            }
        }
    }

    /// Event handling implementation for ProgressBar
    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*ProgressBar, @ptrCast(@alignCast(widget_ptr)));
        _ = self;
        _ = event;
        return false; // Progress bar doesn't handle events
    }

    /// Layout implementation for ProgressBar
    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*ProgressBar, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    /// Get preferred size implementation for ProgressBar
    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*ProgressBar, @ptrCast(@alignCast(widget_ptr)));

        if (self.direction == .horizontal) {
            return layout_module.Size.init(10, 1); // Default horizontal progress bar size
        } else {
            return layout_module.Size.init(1, 10); // Default vertical progress bar size
        }
    }

    /// Can focus implementation for ProgressBar
    fn canFocusFn(widget_ptr: *anyopaque) bool {
        _ = widget_ptr;
        return false; // Progress bars are not focusable
    }
};
