const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const theme = @import("../theme.zig");
const accessibility = @import("../accessibility.zig");

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
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.slider), accessibilityLabel(orientation), "");

        return self;
    }

    fn accessibilityLabel(orientation: ScrollOrientation) []const u8 {
        return switch (orientation) {
            .horizontal => "Horizontal scrollbar",
            .vertical => "Vertical scrollbar",
        };
    }

    /// Clean up scrollbar resources
    pub fn deinit(self: *Scrollbar) void {
        self.allocator.destroy(self);
    }

    /// Set the scrollbar value (0-1)
    pub fn setValue(self: *Scrollbar, value: f32) void {
        const old_value = self.value;
        self.value = normalizedUnit(value);

        if (old_value != self.value) {
            if (self.on_value_change) |callback| {
                callback(self.value);
            }
            self.widget.markDirty();
        }
    }

    /// Get the current value
    pub fn getValue(self: *Scrollbar) f32 {
        return self.value;
    }

    /// Set the thumb ratio (0-1)
    pub fn setThumbRatio(self: *Scrollbar, ratio: f32) void {
        const next = normalizedThumbRatio(ratio);
        if (self.thumb_ratio == next) return;
        self.thumb_ratio = next;
        self.widget.markDirty();
    }

    /// Set the scrollbar colors
    pub fn setColors(self: *Scrollbar, fg: render.Color, bg: render.Color, thumb_fg: render.Color) void {
        if (std.meta.eql(self.fg, fg) and std.meta.eql(self.bg, bg) and std.meta.eql(self.thumb_fg, thumb_fg)) return;
        self.fg = fg;
        self.bg = bg;
        self.thumb_fg = thumb_fg;
        self.widget.markDirty();
    }

    /// Set the on-value-change callback
    pub fn setOnValueChange(self: *Scrollbar, callback: *const fn (f32) void) void {
        self.on_value_change = callback;
    }

    /// Apply theme defaults for scrollbar colors.
    pub fn setTheme(self: *Scrollbar, theme_value: theme.Theme) void {
        const colors = theme.scrollbarColors(theme_value);
        if (std.meta.eql(self.fg, colors.fg) and std.meta.eql(self.bg, colors.bg) and std.meta.eql(self.thumb_fg, colors.thumb_fg) and std.meta.eql(self.focused_fg, colors.focused_fg) and std.meta.eql(self.focused_bg, colors.focused_bg)) return;
        self.fg = colors.fg;
        self.bg = colors.bg;
        self.thumb_fg = colors.thumb_fg;
        self.focused_fg = colors.focused_fg;
        self.focused_bg = colors.focused_bg;
        self.widget.markDirty();
    }

    /// Draw implementation for Scrollbar
    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Scrollbar = @fieldParentPtr("widget", widget_ref);

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
                const thumb_height = clampedThumbSize(rect.height, self.thumb_ratio);
                const thumb_offset = thumbOffset(rect.height, thumb_height, self.value);
                const thumb_y_value = @as(u32, rect.y) + @as(u32, thumb_offset);

                if (u16Coord(thumb_y_value)) |thumb_y| {
                    renderer.fillRect(rect.x, thumb_y, rect.width, thumb_height, ' ', self.thumb_fg, self.thumb_fg, render.Style{});
                }
            }
        } else {
            if (rect.width > 2) {
                const thumb_width = clampedThumbSize(rect.width, self.thumb_ratio);
                const thumb_offset = thumbOffset(rect.width, thumb_width, self.value);
                const thumb_x_value = @as(u32, rect.x) + @as(u32, thumb_offset);

                if (u16Coord(thumb_x_value)) |thumb_x| {
                    renderer.fillRect(thumb_x, rect.y, thumb_width, rect.height, ' ', self.thumb_fg, self.thumb_fg, render.Style{});
                }
            }
        }
    }

    fn u16Coord(value: u32) ?u16 {
        if (value > std.math.maxInt(u16)) {
            return null;
        }
        return @intCast(value);
    }

    fn normalizedUnit(value: f32) f32 {
        if (std.math.isPositiveInf(value)) return 1;
        if (!std.math.isFinite(value)) return 0;
        return std.math.clamp(value, 0, 1);
    }

    fn normalizedThumbRatio(ratio: f32) f32 {
        if (std.math.isPositiveInf(ratio)) return 1;
        if (!std.math.isFinite(ratio)) return 0.1;
        return std.math.clamp(ratio, 0.1, 1);
    }

    fn clampedThumbSize(track: u16, ratio: f32) u16 {
        const track_f = @as(f32, @floatFromInt(track));
        const size = @min(@max(1, track_f * normalizedThumbRatio(ratio)), track_f);
        return @intFromFloat(size);
    }

    fn thumbOffset(track: u16, thumb_size: u16, value: f32) u16 {
        const available = track - thumb_size;
        const available_f = @as(f32, @floatFromInt(available));
        const offset = available_f * normalizedUnit(value);
        return @intFromFloat(@min(offset, available_f));
    }

    /// Event handling implementation for Scrollbar
    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Scrollbar = @fieldParentPtr("widget", widget_ref);

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
                    new_value = normalizedUnit(new_value);

                    self.setValue(new_value);
                } else {
                    const track_width = @as(f32, @floatFromInt(rect.width));
                    const delta_i32: i32 = @as(i32, @intCast(mouse_event.x)) - @as(i32, self.drag_start_pos);
                    const delta = @as(f32, @floatFromInt(delta_i32));
                    const delta_value = delta / track_width;

                    var new_value = self.drag_start_value + delta_value;
                    new_value = normalizedUnit(new_value);

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
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Scrollbar = @fieldParentPtr("widget", widget_ref);
        self.widget.rect = rect;
    }

    /// Get preferred size implementation for Scrollbar
    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Scrollbar = @fieldParentPtr("widget", widget_ref);

        if (self.orientation == .vertical) {
            return layout_module.Size.init(1, 10); // Default vertical scrollbar size
        } else {
            return layout_module.Size.init(10, 1); // Default horizontal scrollbar size
        }
    }

    /// Can focus implementation for Scrollbar
    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Scrollbar = @fieldParentPtr("widget", widget_ref);
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

test "scrollbar normalizes non-finite value and thumb ratio" {
    const alloc = std.testing.allocator;
    var bar = try Scrollbar.init(alloc, .vertical);
    defer bar.deinit();

    bar.setValue(std.math.nan(f32));
    try std.testing.expectEqual(@as(f32, 0), bar.value);

    bar.setValue(std.math.inf(f32));
    try std.testing.expectEqual(@as(f32, 1), bar.value);

    bar.setValue(-std.math.inf(f32));
    try std.testing.expectEqual(@as(f32, 0), bar.value);

    bar.setThumbRatio(std.math.nan(f32));
    try std.testing.expectEqual(@as(f32, 0.1), bar.thumb_ratio);

    bar.setThumbRatio(std.math.inf(f32));
    try std.testing.expectEqual(@as(f32, 1), bar.thumb_ratio);

    bar.setThumbRatio(-std.math.inf(f32));
    try std.testing.expectEqual(@as(f32, 0.1), bar.thumb_ratio);
}

test "scrollbar marks dirty when value changes" {
    const alloc = std.testing.allocator;
    var bar = try Scrollbar.init(alloc, .vertical);
    defer bar.deinit();

    try bar.widget.layout(layout_module.Rect.init(0, 0, 1, 10));
    var renderer = try render.Renderer.init(alloc, 2, 10);
    defer renderer.deinit();

    try bar.widget.draw(&renderer);
    try std.testing.expect(!bar.widget.dirty);

    bar.setValue(0.5);
    try std.testing.expect(bar.widget.dirty);

    try bar.widget.draw(&renderer);
    try std.testing.expect(!bar.widget.dirty);
    bar.setValue(0.5);
    try std.testing.expect(!bar.widget.dirty);
}

test "scrollbar marks dirty when thumb or colors change" {
    const alloc = std.testing.allocator;
    var bar = try Scrollbar.init(alloc, .horizontal);
    defer bar.deinit();

    try bar.widget.layout(layout_module.Rect.init(0, 0, 10, 1));
    var renderer = try render.Renderer.init(alloc, 10, 1);
    defer renderer.deinit();

    try bar.widget.draw(&renderer);
    try std.testing.expect(!bar.widget.dirty);

    bar.setThumbRatio(0.5);
    try std.testing.expect(bar.widget.dirty);
    try bar.widget.draw(&renderer);
    try std.testing.expect(!bar.widget.dirty);
    bar.setThumbRatio(0.5);
    try std.testing.expect(!bar.widget.dirty);

    bar.setColors(
        render.Color.named(render.NamedColor.white),
        render.Color.named(render.NamedColor.black),
        render.Color.named(render.NamedColor.cyan),
    );
    try std.testing.expect(bar.widget.dirty);
    try bar.widget.draw(&renderer);
    try std.testing.expect(!bar.widget.dirty);
    bar.setColors(
        render.Color.named(render.NamedColor.white),
        render.Color.named(render.NamedColor.black),
        render.Color.named(render.NamedColor.cyan),
    );
    try std.testing.expect(!bar.widget.dirty);
}

test "scrollbar draws with non-finite internal state" {
    const alloc = std.testing.allocator;
    var bar = try Scrollbar.init(alloc, .vertical);
    defer bar.deinit();

    bar.value = std.math.nan(f32);
    bar.thumb_ratio = std.math.nan(f32);
    try bar.widget.layout(layout_module.Rect.init(0, 0, 1, 10));

    var renderer = try render.Renderer.init(alloc, 2, 10);
    defer renderer.deinit();

    try bar.widget.draw(&renderer);

    bar.orientation = .horizontal;
    bar.value = std.math.inf(f32);
    bar.thumb_ratio = std.math.inf(f32);
    try bar.widget.layout(layout_module.Rect.init(0, 0, 10, 1));
    bar.widget.markDirty();

    try bar.widget.draw(&renderer);
}

test "scrollbar clips vertical edge coordinates before u16 overflow" {
    const alloc = std.testing.allocator;
    var bar = try Scrollbar.init(alloc, .vertical);
    defer bar.deinit();

    bar.setValue(1);
    try bar.widget.layout(layout_module.Rect.init(0, std.math.maxInt(u16), 1, 4));

    var renderer = try render.Renderer.init(alloc, 4, 4);
    defer renderer.deinit();

    try bar.widget.draw(&renderer);
}

test "scrollbar clips horizontal edge coordinates before u16 overflow" {
    const alloc = std.testing.allocator;
    var bar = try Scrollbar.init(alloc, .horizontal);
    defer bar.deinit();

    bar.setValue(1);
    try bar.widget.layout(layout_module.Rect.init(std.math.maxInt(u16), 0, 4, 1));

    var renderer = try render.Renderer.init(alloc, 4, 4);
    defer renderer.deinit();

    try bar.widget.draw(&renderer);
}
