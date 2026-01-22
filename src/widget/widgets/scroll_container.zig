const std = @import("std");
const base = @import("base_widget.zig");
const scrollbar = @import("scrollbar.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const theme = @import("../theme.zig");
const accessibility = @import("../accessibility.zig");

/// BorderStyle for ScrollContainer
pub const BorderStyle = enum {
    none,
    single,
    double,
    rounded,
};

/// A container that provides scrolling functionality for its content
pub const ScrollContainer = struct {
    /// Base widget
    widget: base.Widget,
    /// Content widget
    content: ?*base.Widget = null,
    /// Horizontal scrollbar
    h_scrollbar: ?*scrollbar.Scrollbar = null,
    /// Vertical scrollbar
    v_scrollbar: ?*scrollbar.Scrollbar = null,
    /// Horizontal scroll offset
    h_offset: i16 = 0,
    /// Vertical scroll offset
    v_offset: i16 = 0,
    /// Content width
    content_width: i16 = 0,
    /// Content height
    content_height: i16 = 0,
    /// Show horizontal scrollbar
    show_h_scrollbar: bool = true,
    /// Show vertical scrollbar
    show_v_scrollbar: bool = true,
    /// Foreground color
    fg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    /// Background color
    bg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    /// Disabled foreground color
    disabled_fg: render.Color = render.Color{ .named_color = render.NamedColor.bright_black },
    /// Disabled background color
    disabled_bg: render.Color = render.Color{ .named_color = render.NamedColor.black },
    /// Show border
    show_border: bool = true,
    /// Border style
    border: BorderStyle = .single,
    /// Custom border style characters
    custom_border_style: ?*const [6]u21 = null,
    /// Render style
    style: render.Style = render.Style{},
    /// Allocator for scroll container operations
    allocator: std.mem.Allocator,

    /// Virtual method table for ScrollContainer
    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    /// Initialize a new scroll container
    pub fn init(allocator: std.mem.Allocator) !*ScrollContainer {
        const self = try allocator.create(ScrollContainer);

        // Create scrollbars
        const h_scrollbar_widget = try scrollbar.Scrollbar.init(allocator, .horizontal);
        h_scrollbar_widget.setOnValueChange(onHorizontalScroll);

        const v_scrollbar_widget = try scrollbar.Scrollbar.init(allocator, .vertical);
        v_scrollbar_widget.setOnValueChange(onVerticalScroll);

        self.* = ScrollContainer{
            .widget = base.Widget.init(&vtable),
            .h_scrollbar = h_scrollbar_widget,
            .v_scrollbar = v_scrollbar_widget,
            .allocator = allocator,
        };
        h_scrollbar_widget.widget.parent = &self.widget;
        v_scrollbar_widget.widget.parent = &self.widget;
        self.setTheme(theme.Theme.dark());
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.container), "Scroll container", "");

        return self;
    }

    /// Clean up scroll container resources
    pub fn deinit(self: *ScrollContainer) void {
        if (self.h_scrollbar) |h_scrollbar_widget| {
            h_scrollbar_widget.deinit();
        }

        if (self.v_scrollbar) |v_scrollbar_widget| {
            v_scrollbar_widget.deinit();
        }

        self.allocator.destroy(self);
    }

    /// Set the content widget
    pub fn setContent(self: *ScrollContainer, content: *base.Widget) void {
        if (self.content) |current| {
            if (current.parent == &self.widget) {
                current.parent = null;
            }
        }
        self.content = content;
        content.parent = &self.widget;
        self.updateContentSize();
    }

    /// Set whether to show scrollbars
    pub fn setShowScrollbars(self: *ScrollContainer, show_h: bool, show_v: bool) void {
        self.show_h_scrollbar = show_h;
        self.show_v_scrollbar = show_v;
    }

    /// Set the scroll container colors
    pub fn setColors(self: *ScrollContainer, fg: render.Color, bg: render.Color) void {
        self.fg = fg;
        self.bg = bg;

        if (self.h_scrollbar) |h_scrollbar_widget| {
            h_scrollbar_widget.setColors(fg, bg, render.Color{ .named_color = render.NamedColor.white });
        }

        if (self.v_scrollbar) |v_scrollbar_widget| {
            v_scrollbar_widget.setColors(fg, bg, render.Color{ .named_color = render.NamedColor.white });
        }
    }

    /// Set the border options
    pub fn setBorder(self: *ScrollContainer, show_border: bool, border_style: BorderStyle) void {
        self.show_border = show_border;
        self.border = border_style;
    }

    /// Apply theme defaults for container and scrollbar colors.
    pub fn setTheme(self: *ScrollContainer, theme_value: theme.Theme) void {
        const colors = theme.controlColors(theme_value);
        self.fg = colors.fg;
        self.bg = colors.bg;
        self.disabled_fg = colors.disabled_fg;
        self.disabled_bg = colors.disabled_bg;
        self.style = theme_value.style;
        if (self.h_scrollbar) |h_scrollbar_widget| {
            h_scrollbar_widget.setTheme(theme_value);
        }
        if (self.v_scrollbar) |v_scrollbar_widget| {
            v_scrollbar_widget.setTheme(theme_value);
        }
    }

    /// Set custom border style
    pub fn setCustomBorderStyle(self: *ScrollContainer, style: *const [6]u21) void {
        self.custom_border_style = style;
    }

    /// Horizontal scroll callback
    fn onHorizontalScroll(_: f32) void {
        // Empty implementation
    }

    /// Vertical scroll callback
    fn onVerticalScroll(_: f32) void {
        // Empty implementation
    }

    /// Update the content size
    fn updateContentSize(self: *ScrollContainer) void {
        if (self.content) |content| {
            const content_size = content.getPreferredSize() catch layout_module.Size.init(0, 0);
            self.content_width = @intCast(@min(content_size.width, std.math.maxInt(i16)));
            self.content_height = @intCast(@min(content_size.height, std.math.maxInt(i16)));
            self.syncHScrollbar();
            self.syncVScrollbar();
        }
    }

    const Viewport = struct {
        width: i16,
        height: i16,
    };

    /// Compute viewport size without mutual recursion between width/height.
    fn computeViewport(self: *ScrollContainer) Viewport {
        var base_width: i16 = @intCast(@min(self.widget.rect.width, std.math.maxInt(i16)));
        var base_height: i16 = @intCast(@min(self.widget.rect.height, std.math.maxInt(i16)));

        if (self.show_border) {
            base_width -= 2;
            base_height -= 2;
        }

        var need_h = false;
        var need_v = false;
        var width = base_width;
        var height = base_height;

        var iter: u2 = 0;
        while (iter < 2) : (iter += 1) {
            width = base_width - @as(i16, if (need_v) 1 else 0);
            height = base_height - @as(i16, if (need_h) 1 else 0);
            width = @max(width, 0);
            height = @max(height, 0);

            const next_h = self.show_h_scrollbar and self.content_width > width;
            const next_v = self.show_v_scrollbar and self.content_height > height;
            if (next_h == need_h and next_v == need_v) break;
            need_h = next_h;
            need_v = next_v;
        }

        return .{ .width = @max(width, 0), .height = @max(height, 0) };
    }

    /// Get the viewport width (content area width)
    fn getViewportWidth(self: *ScrollContainer) i16 {
        return self.computeViewport().width;
    }

    /// Get the viewport height (content area height)
    fn getViewportHeight(self: *ScrollContainer) i16 {
        return self.computeViewport().height;
    }

    fn maxVerticalOffset(self: *ScrollContainer) i16 {
        return @max(0, self.content_height - self.getViewportHeight());
    }

    fn maxHorizontalOffset(self: *ScrollContainer) i16 {
        return @max(0, self.content_width - self.getViewportWidth());
    }

    fn applyVOffset(self: *ScrollContainer, offset: i16) void {
        const clamped = std.math.clamp(offset, 0, self.maxVerticalOffset());
        if (clamped == self.v_offset) return;
        self.v_offset = clamped;
        self.syncVScrollbar();
    }

    fn applyHOffset(self: *ScrollContainer, offset: i16) void {
        const clamped = std.math.clamp(offset, 0, self.maxHorizontalOffset());
        if (clamped == self.h_offset) return;
        self.h_offset = clamped;
        self.syncHScrollbar();
    }

    fn syncVScrollbar(self: *ScrollContainer) void {
        if (self.v_scrollbar) |v_scrollbar_widget| {
            const max_offset = self.maxVerticalOffset();
            const denom = @as(f32, @floatFromInt(@max(1, max_offset)));
            const value = @as(f32, @floatFromInt(self.v_offset)) / denom;
            v_scrollbar_widget.setValue(value);

            const content_height = @max(1, self.content_height);
            const ratio = @as(f32, @floatFromInt(self.getViewportHeight())) / @as(f32, @floatFromInt(content_height));
            v_scrollbar_widget.setThumbRatio(ratio);
        }
    }

    fn syncHScrollbar(self: *ScrollContainer) void {
        if (self.h_scrollbar) |h_scrollbar_widget| {
            const max_offset = self.maxHorizontalOffset();
            const denom = @as(f32, @floatFromInt(@max(1, max_offset)));
            const value = @as(f32, @floatFromInt(self.h_offset)) / denom;
            h_scrollbar_widget.setValue(value);

            const content_width = @max(1, self.content_width);
            const ratio = @as(f32, @floatFromInt(self.getViewportWidth())) / @as(f32, @floatFromInt(content_width));
            h_scrollbar_widget.setThumbRatio(ratio);
        }
    }

    /// Get the border characters based on style
    fn getBorderChars(self: *ScrollContainer) [6]u21 {
        if (self.custom_border_style) |custom_style| {
            return custom_style.*;
        }

        return switch (self.border) {
            .none => [_]u21{ ' ', ' ', ' ', ' ', ' ', ' ' },
            .single => [_]u21{ '+', '+', '+', '+', '-', '|' },
            .double => [_]u21{ '╔', '╗', '╚', '╝', '═', '║' },
            .rounded => [_]u21{ '╭', '╮', '╰', '╯', '─', '│' },
        };
    }

    /// Draw implementation for ScrollContainer
    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*ScrollContainer, @ptrCast(@alignCast(widget_ptr)));

        if (!self.widget.visible) {
            return;
        }

        const rect = self.widget.rect;

        // Choose colors based on state
        const base_bg = if (!self.widget.enabled) self.disabled_bg else self.bg;
        const base_fg = if (!self.widget.enabled) self.disabled_fg else self.fg;
        const styled = self.widget.applyStyle(
            "scroll_container",
            .{ .focus = self.widget.focused, .disabled = !self.widget.enabled },
            self.style,
            base_fg,
            base_bg,
        );
        const fg = styled.fg;
        const bg = styled.bg;
        const style = styled.style;

        // Fill background
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', fg, bg, style);

        // Draw border if enabled
        if (self.show_border and rect.width >= 2 and rect.height >= 2) {
            const border_chars = self.getBorderChars();

            // Top and bottom borders
            for (1..@as(usize, @intCast(rect.width - 1))) |i| {
                renderer.drawChar(rect.x + @as(u16, @intCast(i)), rect.y, border_chars[4], fg, bg, style);
                renderer.drawChar(rect.x + @as(u16, @intCast(i)), rect.y + rect.height - 1, border_chars[4], fg, bg, style);
            }

            // Left and right borders
            for (1..@as(usize, @intCast(rect.height - 1))) |i| {
                renderer.drawChar(rect.x, rect.y + @as(u16, @intCast(i)), border_chars[5], fg, bg, style);
                renderer.drawChar(rect.x + rect.width - 1, rect.y + @as(u16, @intCast(i)), border_chars[5], fg, bg, style);
            }

            // Corners
            renderer.drawChar(rect.x, rect.y, border_chars[0], fg, bg, style);
            renderer.drawChar(rect.x + rect.width - 1, rect.y, border_chars[1], fg, bg, style);
            renderer.drawChar(rect.x, rect.y + rect.height - 1, border_chars[2], fg, bg, style);
            renderer.drawChar(rect.x + rect.width - 1, rect.y + rect.height - 1, border_chars[3], fg, bg, style);
        }

        // Draw content
        if (self.content) |content| {
            // Create a viewport for the content
            var vp = renderer.createViewport() catch {
                try content.draw(renderer);
                return;
            };
            const viewport_rect = self.getContentRect();

            vp.x = viewport_rect.x;
            vp.y = viewport_rect.y;
            vp.width = viewport_rect.width;
            vp.height = viewport_rect.height;
            vp.offset_x = @as(i16, @intCast(self.h_offset));
            vp.offset_y = @as(i16, @intCast(self.v_offset));

            renderer.setViewport(&vp);
            try content.draw(renderer);
            renderer.clearViewport();
        }

        // Draw scrollbars
        if (self.show_h_scrollbar and self.content_width > self.getViewportWidth()) {
            if (self.h_scrollbar) |h_scrollbar_widget| {
                try h_scrollbar_widget.widget.draw(renderer);
            }
        }

        if (self.show_v_scrollbar and self.content_height > self.getViewportHeight()) {
            if (self.v_scrollbar) |v_scrollbar_widget| {
                try v_scrollbar_widget.widget.draw(renderer);
            }
        }

        self.widget.drawFocusRing(renderer);
    }

    /// Get the content rectangle
    fn getContentRect(self: *ScrollContainer) layout_module.Rect {
        var content_rect = self.widget.rect;

        // Adjust for border
        if (self.show_border) {
            content_rect.x += 1;
            content_rect.y += 1;
            content_rect.width -= 2;
            content_rect.height -= 2;
        }

        // Adjust for horizontal scrollbar
        if (self.show_h_scrollbar and self.content_width > self.getViewportWidth()) {
            content_rect.height -= 1;
        }

        // Adjust for vertical scrollbar
        if (self.show_v_scrollbar and self.content_height > self.getViewportHeight()) {
            content_rect.width -= 1;
        }

        return content_rect;
    }

    /// Event handling implementation for ScrollContainer
    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*ScrollContainer, @ptrCast(@alignCast(widget_ptr)));

        if (!self.widget.visible or !self.widget.enabled) {
            return false;
        }

        // First check if scrollbars handle the event
        if (self.show_h_scrollbar and self.content_width > self.getViewportWidth()) {
            if (self.h_scrollbar) |h_scrollbar_widget| {
                if (try h_scrollbar_widget.widget.handleEvent(event)) {
                    const max_offset = self.maxHorizontalOffset();
                    const offset = @as(i16, @intFromFloat(@round(h_scrollbar_widget.getValue() * @as(f32, @floatFromInt(max_offset)))));
                    self.applyHOffset(offset);
                    return true;
                }
            }
        }

        if (self.show_v_scrollbar and self.content_height > self.getViewportHeight()) {
            if (self.v_scrollbar) |v_scrollbar_widget| {
                if (try v_scrollbar_widget.widget.handleEvent(event)) {
                    const max_offset = self.maxVerticalOffset();
                    const offset = @as(i16, @intFromFloat(@round(v_scrollbar_widget.getValue() * @as(f32, @floatFromInt(max_offset)))));
                    self.applyVOffset(offset);
                    return true;
                }
            }
        }

        // Check if content handles the event
        if (self.content) |content| {
            if (try content.handleEvent(event)) {
                return true;
            }
        }

        // Handle scroll events ourselves if within our bounds
        if (event == .mouse) {
            const mouse_event = event.mouse;
            const content_rect = self.getContentRect();

            if (content_rect.contains(mouse_event.x, mouse_event.y)) {
                if (mouse_event.action == .scroll_up or mouse_event.action == .scroll_down) {
                    if (self.show_v_scrollbar and self.content_height > self.getViewportHeight()) {
                        const scroll_amount: i16 = 3;
                        const steps: i16 = if (mouse_event.scroll_delta != 0)
                            mouse_event.scroll_delta
                        else if (mouse_event.action == .scroll_up)
                            -1
                        else
                            1;
                        const delta = scroll_amount * steps;
                        self.applyVOffset(self.v_offset + delta);
                        return true;
                    }
                }
            }
        }

        // Handle keyboard scrolling when focused
        if (event == .key and self.widget.focused) {
            const key_event = event.key;
            const profiles = [_]input.KeybindingProfile{
                input.KeybindingProfile.commonEditing(),
                input.KeybindingProfile.emacs(),
                input.KeybindingProfile.vi(),
            };

            if (input.editorActionForEvent(key_event, &profiles)) |action| {
                switch (action) {
                    .cursor_down => {
                        if (self.show_v_scrollbar and self.content_height > self.getViewportHeight()) {
                            self.applyVOffset(self.v_offset + 1);
                            return true;
                        }
                    },
                    .cursor_up => {
                        if (self.show_v_scrollbar and self.content_height > self.getViewportHeight()) {
                            self.applyVOffset(self.v_offset - 1);
                            return true;
                        }
                    },
                    .page_down => {
                        if (self.show_v_scrollbar and self.content_height > self.getViewportHeight()) {
                            self.applyVOffset(self.v_offset + self.getViewportHeight());
                            return true;
                        }
                        if (self.show_h_scrollbar and self.content_width > self.getViewportWidth()) {
                            self.applyHOffset(self.h_offset + self.getViewportWidth());
                            return true;
                        }
                    },
                    .page_up => {
                        if (self.show_v_scrollbar and self.content_height > self.getViewportHeight()) {
                            self.applyVOffset(self.v_offset - self.getViewportHeight());
                            return true;
                        }
                        if (self.show_h_scrollbar and self.content_width > self.getViewportWidth()) {
                            self.applyHOffset(self.h_offset - self.getViewportWidth());
                            return true;
                        }
                    },
                    .line_end => {
                        if (self.show_v_scrollbar and self.content_height > self.getViewportHeight()) {
                            self.applyVOffset(self.maxVerticalOffset());
                            return true;
                        }
                        if (self.show_h_scrollbar and self.content_width > self.getViewportWidth()) {
                            self.applyHOffset(self.maxHorizontalOffset());
                            return true;
                        }
                    },
                    .line_start => {
                        if (self.show_v_scrollbar and self.content_height > self.getViewportHeight()) {
                            self.applyVOffset(0);
                            return true;
                        }
                        if (self.show_h_scrollbar and self.content_width > self.getViewportWidth()) {
                            self.applyHOffset(0);
                            return true;
                        }
                    },
                    .cursor_right => {
                        if (self.show_h_scrollbar and self.content_width > self.getViewportWidth()) {
                            self.applyHOffset(self.h_offset + 1);
                            return true;
                        }
                    },
                    .cursor_left => {
                        if (self.show_h_scrollbar and self.content_width > self.getViewportWidth()) {
                            self.applyHOffset(self.h_offset - 1);
                            return true;
                        }
                    },
                    else => {},
                }
            }
        }

        return false;
    }

    /// Layout implementation for ScrollContainer
    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*ScrollContainer, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;

        // Layout scrollbars
        if (self.show_h_scrollbar) {
            if (self.h_scrollbar) |h_scrollbar_widget| {
                var h_scrollbar_rect = rect;
                h_scrollbar_rect.y = rect.y + rect.height - 1;
                h_scrollbar_rect.height = 1;

                if (self.show_v_scrollbar) {
                    h_scrollbar_rect.width -= 1; // Make room for vertical scrollbar
                }

                try h_scrollbar_widget.widget.layout(h_scrollbar_rect);
            }
        }

        if (self.show_v_scrollbar) {
            if (self.v_scrollbar) |v_scrollbar_widget| {
                var v_scrollbar_rect = rect;
                v_scrollbar_rect.x = rect.x + rect.width - 1;
                v_scrollbar_rect.width = 1;

                if (self.show_h_scrollbar) {
                    v_scrollbar_rect.height -= 1; // Make room for horizontal scrollbar
                }

                try v_scrollbar_widget.widget.layout(v_scrollbar_rect);
            }
        }

        // Layout content
        if (self.content) |content| {
            var content_rect = self.getContentRect();

            // Content can be larger than viewport
            const content_width: u16 = @intCast(@max(self.content_width, 0));
            const content_height: u16 = @intCast(@max(self.content_height, 0));
            content_rect.width = @max(content_rect.width, content_width);
            content_rect.height = @max(content_rect.height, content_height);

            try content.layout(content_rect);
        }

        self.updateContentSize();
    }

    /// Get preferred size implementation for ScrollContainer
    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*ScrollContainer, @ptrCast(@alignCast(widget_ptr)));

        var width: i16 = 10; // Minimum width
        var height: i16 = 5; // Minimum height

        if (self.content) |content| {
            const content_size = try content.getPreferredSize();
            width = @max(width, @as(i16, @intCast(@min(content_size.width, std.math.maxInt(i16)))));
            height = @max(height, @as(i16, @intCast(@min(content_size.height, std.math.maxInt(i16)))));
        }

        // Add border space
        if (self.show_border) {
            width += 2;
            height += 2;
        }

        // Add scrollbar space
        if (self.show_h_scrollbar) {
            height += 1;
        }

        if (self.show_v_scrollbar) {
            width += 1;
        }

        return layout_module.Size.init(width, height);
    }

    /// Can focus implementation for ScrollContainer
    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*ScrollContainer, @ptrCast(@alignCast(widget_ptr)));

        if (!self.widget.enabled) {
            return false;
        }

        // We can focus if either scrollbars or content can focus
        if (self.content) |content| {
            if (content.canFocus()) {
                return true;
            }
        }

        return (self.show_h_scrollbar and self.content_width > self.getViewportWidth()) or
            (self.show_v_scrollbar and self.content_height > self.getViewportHeight());
    }
};

test "scroll container init/deinit" {
    const alloc = std.testing.allocator;
    var container = try ScrollContainer.init(alloc);
    defer container.deinit();

    try std.testing.expect(container.h_scrollbar != null);
    try std.testing.expect(container.v_scrollbar != null);
    try std.testing.expectEqual(&container.widget, container.h_scrollbar.?.widget.parent.?);
    try std.testing.expectEqual(&container.widget, container.v_scrollbar.?.widget.parent.?);
}

test "scroll container maintains parent linkage for content" {
    const alloc = std.testing.allocator;
    var container = try ScrollContainer.init(alloc);
    defer container.deinit();

    var first = try @import("block.zig").Block.init(alloc);
    defer first.deinit();
    var second = try @import("block.zig").Block.init(alloc);
    defer second.deinit();

    container.setContent(&first.widget);
    try std.testing.expectEqual(&container.widget, first.widget.parent.?);

    container.setContent(&second.widget);
    try std.testing.expect(first.widget.parent == null);
    try std.testing.expectEqual(&container.widget, second.widget.parent.?);
}

test "scroll container scrolls content with mouse wheel" {
    const Dummy = struct {
        widget: base.Widget = base.Widget.init(&vtable),
        const vtable = base.Widget.VTable{
            .draw = drawFn,
            .handle_event = handleEventFn,
            .layout = layoutFn,
            .get_preferred_size = preferredFn,
            .can_focus = canFocusFn,
        };

        fn drawFn(_: *anyopaque, _: *render.Renderer) anyerror!void {}
        fn handleEventFn(_: *anyopaque, _: input.Event) anyerror!bool {
            return false;
        }
        fn layoutFn(_: *anyopaque, _: layout_module.Rect) anyerror!void {}
        fn preferredFn(_: *anyopaque) anyerror!layout_module.Size {
            return layout_module.Size.init(20, 20);
        }
        fn canFocusFn(_: *anyopaque) bool {
            return false;
        }
    };

    const alloc = std.testing.allocator;
    var container = try ScrollContainer.init(alloc);
    defer container.deinit();
    var dummy = Dummy{};
    container.setContent(&dummy.widget);

    try container.widget.layout(layout_module.Rect.init(0, 0, 10, 6));
    try std.testing.expectEqual(@as(i16, 0), container.v_offset);

    const scroll_event = input.Event{ .mouse = input.MouseEvent.init(.scroll_down, 1, 1, 0, 0) };
    try std.testing.expect(try container.widget.handleEvent(scroll_event));
    try std.testing.expect(container.v_offset > 0);
}

test "scroll container ignores scroll without content" {
    const alloc = std.testing.allocator;
    var container = try ScrollContainer.init(alloc);
    defer container.deinit();

    try container.widget.layout(layout_module.Rect.init(0, 0, 10, 6));
    const scroll_event = input.Event{ .mouse = input.MouseEvent.init(.scroll_down, 1, 1, 0, 0) };
    try std.testing.expect(!try container.widget.handleEvent(scroll_event));
    try std.testing.expectEqual(@as(i16, 0), container.v_offset);
}
