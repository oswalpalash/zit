const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const testing = @import("../../testing/testing.zig");
const animation = @import("../animation.zig");
const theme = @import("../theme.zig");
const accessibility = @import("../accessibility.zig");

/// Progress bar direction
pub const ProgressDirection = enum {
    horizontal,
    vertical,
};

fn floatEql(a: f32, b: f32) bool {
    return @abs(a - b) <= 0.0001;
}

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
    /// Optional shared animator for smooth transitions
    animator: ?*animation.Animator = null,
    /// Animated scalar for progress smoothing
    progress_driver: animation.ValueDriver = .{},
    /// Animated foreground color for the fill
    fill_fg_transition: animation.ColorTransition = animation.ColorTransition.init(render.Color.named(render.NamedColor.green)),
    /// Animated background color for the fill
    fill_bg_transition: animation.ColorTransition = animation.ColorTransition.init(render.Color.named(render.NamedColor.default)),
    /// Duration for progress tweening
    progress_duration_ms: u64 = 180,

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
        self.setTheme(theme.Theme.dark());

        self.progress_driver.snap(@floatFromInt(self.progress));
        self.fill_fg_transition.snap(self.fill_fg);
        self.fill_bg_transition.snap(self.fill_bg);
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.progressbar), "Progress", "");
        return self;
    }

    fn addOffsetClamped(origin: u16, offset: u16) u16 {
        const value = @as(u32, origin) + @as(u32, offset);
        return @intCast(@min(value, @as(u32, std.math.maxInt(u16))));
    }

    fn addUsizeOffsetClamped(origin: u16, offset: usize) u16 {
        const capped = @min(offset, @as(usize, std.math.maxInt(u16)));
        return addOffsetClamped(origin, @intCast(capped));
    }

    /// Clean up progress bar resources
    pub fn deinit(self: *ProgressBar) void {
        self.allocator.destroy(self);
    }

    /// Set the progress bar direction
    pub fn setDirection(self: *ProgressBar, direction: ProgressDirection) void {
        if (self.direction == direction) return;
        self.direction = direction;
        self.widget.markDirty();
    }

    /// Attach a shared animator to enable animated progress and color transitions.
    pub fn attachAnimator(self: *ProgressBar, animator: *animation.Animator) void {
        self.animator = animator;
        self.progress_driver.snap(@floatFromInt(self.progress));
        self.fill_fg_transition.snap(self.fill_fg);
        self.fill_bg_transition.snap(self.fill_bg);
    }

    /// Set the progress value (0-100)
    pub fn setProgress(self: *ProgressBar, progress: u8) void {
        const clamped = @min(progress, 100);
        const target: f32 = @floatFromInt(clamped);
        if (self.progress == clamped and
            floatEql(self.progress_driver.target, target) and
            (self.animator != null or floatEql(self.progress_driver.current, target)))
        {
            return;
        }

        self.progress = clamped;
        if (self.animator) |anim| {
            const update = struct {
                fn onChange(value: f32, ctx: ?*anyopaque) void {
                    const bar = @as(*ProgressBar, @ptrCast(@alignCast(ctx.?)));
                    bar.progress_driver.current = value;
                }
            }.onChange;

            _ = self.progress_driver.animate(
                anim,
                self.progress_driver.current,
                target,
                self.progress_duration_ms,
                animation.Easing.easeInOutQuad,
                update,
                @ptrCast(self),
            ) catch {
                self.progress_driver.snap(target);
            };
        } else {
            self.progress_driver.snap(target);
        }
        self.widget.markDirty();
    }

    /// Set the progress value (0-100)
    pub fn setValue(self: *ProgressBar, value: u8) void {
        self.setProgress(value);
    }

    /// Set whether to show text percentage
    pub fn setShowPercentage(self: *ProgressBar, show_text: bool) void {
        if (self.show_text == show_text) return;
        self.show_text = show_text;
        self.widget.markDirty();
    }

    /// Set the fill character
    pub fn setFillChar(self: *ProgressBar, fill_char: u21) void {
        if (self.fill_char == fill_char) return;
        self.fill_char = fill_char;
        self.widget.markDirty();
    }

    /// Set the progress bar colors
    pub fn setColors(self: *ProgressBar, fg: render.Color, bg: render.Color, fill_fg: render.Color, fill_bg: render.Color) void {
        if (std.meta.eql(self.fg, fg) and
            std.meta.eql(self.bg, bg) and
            std.meta.eql(self.fill_fg, fill_fg) and
            std.meta.eql(self.fill_bg, fill_bg)) return;

        self.fg = fg;
        self.bg = bg;
        self.fill_fg = fill_fg;
        self.fill_bg = fill_bg;
        self.fill_fg_transition.snap(fill_fg);
        self.fill_bg_transition.snap(fill_bg);
        self.widget.markDirty();
    }

    /// Smoothly transition fill colors when an animator is available.
    pub fn transitionFillColors(self: *ProgressBar, fill_fg: render.Color, fill_bg: render.Color, duration_ms: u64) !void {
        if (std.meta.eql(self.fill_fg, fill_fg) and
            std.meta.eql(self.fill_bg, fill_bg) and
            std.meta.eql(self.fill_fg_transition.target, fill_fg) and
            std.meta.eql(self.fill_bg_transition.target, fill_bg)) return;

        self.fill_fg = fill_fg;
        self.fill_bg = fill_bg;
        if (self.animator) |anim| {
            try self.fill_fg_transition.animateTo(anim, fill_fg, duration_ms, animation.Easing.easeInOutQuad);
            try self.fill_bg_transition.animateTo(anim, fill_bg, duration_ms, animation.Easing.easeInOutQuad);
        } else {
            self.fill_fg_transition.snap(fill_fg);
            self.fill_bg_transition.snap(fill_bg);
        }
        self.widget.markDirty();
    }

    /// Set the border style
    pub fn setBorder(self: *ProgressBar, border: render.BorderStyle) void {
        if (self.border == border) return;
        self.border = border;
        self.widget.markDirty();
    }

    /// Apply theme defaults for progress bar colors.
    pub fn setTheme(self: *ProgressBar, theme_value: theme.Theme) void {
        const colors = theme.progressColors(theme_value);
        self.setColors(colors.fg, colors.bg, colors.fill_fg, colors.fill_bg);
    }

    /// Draw implementation for ProgressBar
    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *ProgressBar = @fieldParentPtr("widget", widget_ref);

        if (!self.widget.visible) {
            return;
        }

        const rect = self.widget.rect;
        const styled = self.widget.applyStyle(
            "progress_bar",
            .{ .disabled = !self.widget.enabled },
            render.Style{},
            self.fg,
            self.bg,
        );
        const fg = styled.fg;
        const bg = styled.bg;
        const style = styled.style;

        // Fill background
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', fg, bg, style);

        const effective_progress: f32 = if (self.animator != null) self.progress_driver.current else @as(f32, @floatFromInt(self.progress));
        const clamped = std.math.clamp(effective_progress, 0, 100);
        const fill_fg = if (self.animator != null) self.fill_fg_transition.value() else self.fill_fg;
        const fill_bg = if (self.animator != null) self.fill_bg_transition.value() else self.fill_bg;

        // Draw progress
        if (self.direction == .horizontal) {
            const progress_width = @as(u16, @intFromFloat(@as(f32, @floatFromInt(rect.width)) * (clamped / 100.0)));

            if (progress_width > 0) {
                renderer.fillRect(rect.x, rect.y, progress_width, rect.height, self.fill_char, fill_fg, fill_bg, style);
            }

            // Show percentage text
            if (self.show_text and rect.width >= 5) {
                var buffer: [5]u8 = undefined;
                const text = std.fmt.bufPrintZ(&buffer, "{d}%", .{@as(u8, @intFromFloat(clamped))}) catch "";

                const half_width = @divTrunc(rect.width, 2);
                const text_len = @as(u16, @intCast(text.len));
                const half_text_len = @divTrunc(text_len, 2);
                const text_x = addOffsetClamped(rect.x, @as(u16, @intCast(@max(0, half_width - half_text_len))));
                const text_y = addOffsetClamped(rect.y, @divTrunc(rect.height, 2));
                const progress_right = @as(u32, rect.x) + @as(u32, progress_width);

                for (text, 0..) |char, i| {
                    const x = addUsizeOffsetClamped(text_x, i);
                    const y = text_y;

                    // Choose text color based on position (in progress area or not)
                    const is_in_progress_area = @as(u32, x) < progress_right;
                    const text_fg = if (is_in_progress_area) self.bg else self.fg;
                    const text_bg = if (is_in_progress_area) fill_fg else self.bg;

                    renderer.drawChar(x, y, char, text_fg, text_bg, style);
                }
            }
        } else {
            const progress_height = @as(u16, @intFromFloat(@as(f32, @floatFromInt(rect.height)) * (clamped / 100.0)));
            const start_y = addOffsetClamped(rect.y, rect.height - progress_height);

            if (progress_height > 0) {
                renderer.fillRect(rect.x, start_y, rect.width, progress_height, self.fill_char, fill_fg, fill_bg, style);
            }

            // Show percentage text
            if (self.show_text and rect.height >= 1 and rect.width >= 4) {
                var buffer: [5]u8 = undefined;
                const text = std.fmt.bufPrintZ(&buffer, "{d}%", .{@as(u8, @intFromFloat(clamped))}) catch "";

                const text_offset = @divTrunc(rect.width, 2) - @as(u16, @intCast(@divTrunc(@as(i16, @intCast(text.len)), 2)));
                const text_x = addOffsetClamped(rect.x, text_offset);
                const text_y = addOffsetClamped(rect.y, @divTrunc(rect.height, 2));

                for (text, 0..) |char, i| {
                    const x = addUsizeOffsetClamped(text_x, i);
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
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *ProgressBar = @fieldParentPtr("widget", widget_ref);
        _ = self;
        _ = event;
        return false; // Progress bar doesn't handle events
    }

    /// Layout implementation for ProgressBar
    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *ProgressBar = @fieldParentPtr("widget", widget_ref);
        self.widget.rect = rect;
    }

    /// Get preferred size implementation for ProgressBar
    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *ProgressBar = @fieldParentPtr("widget", widget_ref);

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

test "progress bar init/deinit" {
    const alloc = std.testing.allocator;
    var bar = try ProgressBar.init(alloc);
    defer bar.deinit();

    try std.testing.expectEqual(@as(u8, 0), bar.progress);
}

test "progress bar updates progress and renders fill" {
    const alloc = std.testing.allocator;
    var bar = try ProgressBar.init(alloc);
    defer bar.deinit();

    bar.setProgress(50);
    try std.testing.expectEqual(@as(u8, 50), bar.progress);
    try std.testing.expectEqual(@as(f32, 50), bar.progress_driver.current);

    var snap = try testing.renderWidget(alloc, &bar.widget, layout_module.Size.init(10, 1));
    defer snap.deinit(alloc);
    try std.testing.expect(std.mem.indexOfScalar(u8, snap.text(), '%') != null);
}

test "progress bar visible mutations mark dirty only when changed" {
    const alloc = std.testing.allocator;
    var bar = try ProgressBar.init(alloc);
    defer bar.deinit();

    bar.widget.clearDirty();
    bar.setProgress(50);
    try std.testing.expect(bar.widget.dirty);
    bar.widget.clearDirty();
    bar.setProgress(50);
    try std.testing.expect(!bar.widget.dirty);
    bar.setProgress(150);
    try std.testing.expect(bar.widget.dirty);
    try std.testing.expectEqual(@as(u8, 100), bar.progress);
    bar.widget.clearDirty();
    bar.setProgress(100);
    try std.testing.expect(!bar.widget.dirty);

    bar.widget.clearDirty();
    bar.setDirection(.vertical);
    try std.testing.expect(bar.widget.dirty);
    bar.widget.clearDirty();
    bar.setDirection(.vertical);
    try std.testing.expect(!bar.widget.dirty);

    bar.widget.clearDirty();
    bar.setShowPercentage(false);
    try std.testing.expect(bar.widget.dirty);
    bar.widget.clearDirty();
    bar.setShowPercentage(false);
    try std.testing.expect(!bar.widget.dirty);

    bar.widget.clearDirty();
    bar.setFillChar('#');
    try std.testing.expect(bar.widget.dirty);
    bar.widget.clearDirty();
    bar.setFillChar('#');
    try std.testing.expect(!bar.widget.dirty);

    bar.widget.clearDirty();
    bar.setBorder(.rounded);
    try std.testing.expect(bar.widget.dirty);
    bar.widget.clearDirty();
    bar.setBorder(.rounded);
    try std.testing.expect(!bar.widget.dirty);
}

test "progress bar colors and theme mark dirty only when changed" {
    const alloc = std.testing.allocator;
    var bar = try ProgressBar.init(alloc);
    defer bar.deinit();

    bar.widget.clearDirty();
    bar.setColors(render.Color.named(.white), render.Color.named(.black), render.Color.named(.green), render.Color.named(.blue));
    try std.testing.expect(bar.widget.dirty);
    bar.widget.clearDirty();
    bar.setColors(render.Color.named(.white), render.Color.named(.black), render.Color.named(.green), render.Color.named(.blue));
    try std.testing.expect(!bar.widget.dirty);

    bar.widget.clearDirty();
    try bar.transitionFillColors(render.Color.named(.red), render.Color.named(.yellow), 120);
    try std.testing.expect(bar.widget.dirty);
    bar.widget.clearDirty();
    try bar.transitionFillColors(render.Color.named(.red), render.Color.named(.yellow), 120);
    try std.testing.expect(!bar.widget.dirty);

    bar.widget.clearDirty();
    bar.setTheme(theme.Theme.light());
    try std.testing.expect(bar.widget.dirty);
    bar.widget.clearDirty();
    bar.setTheme(theme.Theme.light());
    try std.testing.expect(!bar.widget.dirty);
}

test "progress bar tolerates zero size" {
    const alloc = std.testing.allocator;
    var bar = try ProgressBar.init(alloc);
    defer bar.deinit();

    var snap = try testing.renderWidget(alloc, &bar.widget, layout_module.Size.init(0, 0));
    defer snap.deinit(alloc);
    try std.testing.expectEqual(@as(usize, 0), snap.text().len);
}

test "progress bar clamps horizontal edge label coordinates" {
    const alloc = std.testing.allocator;
    var bar = try ProgressBar.init(alloc);
    defer bar.deinit();

    bar.setProgress(100);
    bar.setDirection(.horizontal);
    try bar.widget.layout(layout_module.Rect.init(std.math.maxInt(u16), std.math.maxInt(u16), 8, 3));

    var renderer = try render.Renderer.init(alloc, 2, 2);
    defer renderer.deinit();

    try bar.widget.draw(&renderer);
    try std.testing.expectEqual(@as(u21, ' '), renderer.back.getCell(0, 0).codepoint());
    try std.testing.expectEqual(@as(u21, ' '), renderer.back.getCell(1, 1).codepoint());
}

test "progress bar clamps vertical edge label and fill coordinates" {
    const alloc = std.testing.allocator;
    var bar = try ProgressBar.init(alloc);
    defer bar.deinit();

    bar.setProgress(50);
    bar.setDirection(.vertical);
    try bar.widget.layout(layout_module.Rect.init(std.math.maxInt(u16), std.math.maxInt(u16), 4, 10));

    var renderer = try render.Renderer.init(alloc, 2, 2);
    defer renderer.deinit();

    try bar.widget.draw(&renderer);
    try std.testing.expectEqual(@as(u21, ' '), renderer.back.getCell(0, 0).codepoint());
    try std.testing.expectEqual(@as(u21, ' '), renderer.back.getCell(1, 1).codepoint());
}
