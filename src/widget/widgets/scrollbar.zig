const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const theme = @import("../theme.zig");

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
    /// On value change callback
    on_value_change: ?*const fn (f32) void = null,
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
        self.setTheme(theme.Theme.dark());

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

        if (old_value != self.value and self.on_value_change != null) {
            self.on_value_change.?(self.value);
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

    /// Set the on-value-change callback
    pub fn setOnValueChange(self: *Scrollbar, callback: *const fn (f32) void) void {
        self.on_value_change = callback;
    }

    /// Apply theme defaults for scrollbar colors.
    pub fn setTheme(self: *Scrollbar, theme_value: theme.Theme) void {
        const colors = theme.scrollbarColors(theme_value);
        self.fg = colors.fg;
        self.bg = colors.bg;
        self.thumb_fg = colors.thumb_fg;
        self.focused_fg = colors.focused_fg;
        self.focused_bg = colors.focused_bg;
    }

    /// Draw implementation for Scrollbar
    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*Scrollbar, @ptrCast(@alignCast(widget_ptr)));

        if (!self.widget.visible) {
            return;
        }

        const rect = self.widget.rect;

        // Choose colors based on state
        const base_bg = if (!self.widget.enabled)
            self.bg
        else if (self.widget.focused)
            self.focused_bg
        else
            self.bg;

        const base_fg = if (!self.widget.enabled)
            self.fg
        else if (self.widget.focused)
            self.focused_fg
        else
            self.fg;

        const styled = self.widget.applyStyle(
            "scrollbar",
            .{ .focus = self.widget.focused, .disabled = !self.widget.enabled },
            render.Style{},
            base_fg,
            base_bg,
        );
        const fg = styled.fg;
        const bg = styled.bg;

        // Fill scrollbar background
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', fg, bg, render.Style{});

        // Draw thumb
        if (self.orientation == .vertical) {
            if (rect.height > 2) {
                const track_height = @as(f32, @floatFromInt(rect.height));
                const thumb_height = @as(i16, @intFromFloat(@max(1, track_height * self.thumb_ratio)));
                const thumb_pos = @as(i16, @intFromFloat(@min(track_height - @as(f32, @floatFromInt(thumb_height)), track_height * self.value)));
                const thumb_y: u16 = @intCast(@max(@as(i16, @intCast(rect.y)) + thumb_pos, 0));
                const thumb_height_u16: u16 = @intCast(@max(thumb_height, 0));

                renderer.fillRect(rect.x, thumb_y, rect.width, thumb_height_u16, ' ', self.thumb_fg, self.thumb_fg, render.Style{});
            }
        } else {
            if (rect.width > 2) {
                const track_width = @as(f32, @floatFromInt(rect.width));
                const thumb_width = @as(i16, @intFromFloat(@max(1, track_width * self.thumb_ratio)));
                const thumb_pos = @as(i16, @intFromFloat(@min(track_width - @as(f32, @floatFromInt(thumb_width)), track_width * self.value)));
                const thumb_x: u16 = @intCast(@max(@as(i16, @intCast(rect.x)) + thumb_pos, 0));

                renderer.fillRect(thumb_x, rect.y, @intCast(@max(thumb_width, 0)), rect.height, ' ', self.thumb_fg, self.thumb_fg, render.Style{});
            }
        }
    }

    /// Event handling implementation for Scrollbar
    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*Scrollbar, @ptrCast(@alignCast(widget_ptr)));

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
                        self.drag_start_pos = @intCast(@min(mouse_event.y, std.math.maxInt(i16)));
                    } else {
                        self.drag_start_pos = @intCast(@min(mouse_event.x, std.math.maxInt(i16)));
                    }
                    self.drag_start_value = self.value;
                    return true;
                }
                // Mouse wheel scrolls
                else if (mouse_event.action == .scroll_up or mouse_event.action == .scroll_down) {
                    const step_value: i16 = if (mouse_event.scroll_delta != 0)
                        @intCast(mouse_event.scroll_delta)
                    else if (mouse_event.action == .scroll_up)
                        -1
                    else
                        1;
                    const step: f32 = @floatFromInt(step_value);
                    self.setValue(self.value + (0.1 * step));
                    return true;
                }
            }

            // Handle mouse release (end dragging)
            if (self.dragging and mouse_event.action == .release) {
                self.dragging = false;
                return true;
            }

            // Handle mouse movement while dragging
            if (self.dragging and mouse_event.action == .move) {
                if (self.orientation == .vertical) {
                    const track_height = @as(f32, @floatFromInt(rect.height));
                    const delta_i32: i32 = @as(i32, @intCast(mouse_event.y)) - @as(i32, self.drag_start_pos);
                    const delta = @as(f32, @floatFromInt(delta_i32));
                    const delta_value = delta / track_height;

                    var new_value = self.drag_start_value + delta_value;
                    new_value = std.math.clamp(new_value, 0, 1);

                    self.setValue(new_value);
                } else {
                    const track_width = @as(f32, @floatFromInt(rect.width));
                    const delta_i32: i32 = @as(i32, @intCast(mouse_event.x)) - @as(i32, self.drag_start_pos);
                    const delta = @as(f32, @floatFromInt(delta_i32));
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
                if (key_event.key == 'j' or key_event.key == 'J' or key_event.key == input.KeyCode.DOWN) { // Down
                    self.setValue(self.value + 0.1);
                    return true;
                } else if (key_event.key == 'k' or key_event.key == 'K' or key_event.key == input.KeyCode.UP) { // Up
                    self.setValue(self.value - 0.1);
                    return true;
                } else if (key_event.key == input.KeyCode.PAGE_DOWN) { // Page down
                    self.setValue(self.value + 0.25);
                    return true;
                } else if (key_event.key == input.KeyCode.PAGE_UP) { // Page up
                    self.setValue(self.value - 0.25);
                    return true;
                } else if (key_event.key == input.KeyCode.HOME) { // Home
                    self.setValue(0);
                    return true;
                } else if (key_event.key == input.KeyCode.END) { // End
                    self.setValue(1);
                    return true;
                }
            } else {
                if (key_event.key == 'l' or key_event.key == 'L' or key_event.key == input.KeyCode.RIGHT) { // Right
                    self.setValue(self.value + 0.1);
                    return true;
                } else if (key_event.key == 'h' or key_event.key == 'H' or key_event.key == input.KeyCode.LEFT) { // Left
                    self.setValue(self.value - 0.1);
                    return true;
                } else if (key_event.key == input.KeyCode.PAGE_DOWN) { // Page right
                    self.setValue(self.value + 0.25);
                    return true;
                } else if (key_event.key == input.KeyCode.PAGE_UP) { // Page left
                    self.setValue(self.value - 0.25);
                    return true;
                } else if (key_event.key == input.KeyCode.HOME) { // Home
                    self.setValue(0);
                    return true;
                } else if (key_event.key == input.KeyCode.END) { // End
                    self.setValue(1);
                    return true;
                }
            }
        }

        return false;
    }

    /// Layout implementation for Scrollbar
    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*Scrollbar, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    /// Get preferred size implementation for Scrollbar
    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*Scrollbar, @ptrCast(@alignCast(widget_ptr)));

        if (self.orientation == .vertical) {
            return layout_module.Size.init(1, 10); // Default vertical scrollbar size
        } else {
            return layout_module.Size.init(10, 1); // Default horizontal scrollbar size
        }
    }

    /// Can focus implementation for Scrollbar
    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*Scrollbar, @ptrCast(@alignCast(widget_ptr)));
        return self.widget.enabled;
    }
};

var test_scrollbar_calls: usize = 0;
var test_scrollbar_value: f32 = 0;

test "scrollbar init/deinit" {
    const alloc = std.testing.allocator;
    var bar = try Scrollbar.init(alloc, .vertical);
    defer bar.deinit();

    try std.testing.expectEqual(ScrollOrientation.vertical, bar.orientation);
}

test "scrollbar updates value on scroll event" {
    const alloc = std.testing.allocator;
    var bar = try Scrollbar.init(alloc, .vertical);
    defer bar.deinit();
    bar.widget.rect = layout_module.Rect.init(0, 0, 1, 10);

    test_scrollbar_calls = 0;
    test_scrollbar_value = 0;
    const callback = struct {
        fn call(value: f32) void {
            test_scrollbar_calls += 1;
            test_scrollbar_value = value;
        }
    }.call;
    bar.setOnValueChange(callback);

    const scroll_event = input.Event{ .mouse = input.MouseEvent.init(.scroll_down, 0, 0, 0, 1) };
    try std.testing.expect(try bar.widget.handleEvent(scroll_event));
    try std.testing.expect(bar.value > 0);
    try std.testing.expectEqual(@as(usize, 1), test_scrollbar_calls);
    try std.testing.expect(test_scrollbar_value > 0);
}

test "scrollbar clamps out-of-range values" {
    const alloc = std.testing.allocator;
    var bar = try Scrollbar.init(alloc, .horizontal);
    defer bar.deinit();

    bar.setValue(2.5);
    try std.testing.expectEqual(@as(f32, 1), bar.value);

    bar.setValue(-1.0);
    try std.testing.expectEqual(@as(f32, 0), bar.value);
}
