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

    fn addI16Saturating(value: i16, delta: i16) i16 {
        return std.math.add(i16, value, delta) catch if (delta > 0) std.math.maxInt(i16) else std.math.minInt(i16);
    }

    /// Initialize a new scroll container
    pub fn init(allocator: std.mem.Allocator) !*ScrollContainer {
        const self = try allocator.create(ScrollContainer);
        errdefer allocator.destroy(self);

        // Create scrollbars
        const h_scrollbar_widget = try scrollbar.Scrollbar.init(allocator, .horizontal);
        errdefer h_scrollbar_widget.deinit();
        h_scrollbar_widget.setOnValueChange(onHorizontalScroll);

        const v_scrollbar_widget = try scrollbar.Scrollbar.init(allocator, .vertical);
        errdefer v_scrollbar_widget.deinit();
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
        self.detachContent();

        if (self.h_scrollbar) |h_scrollbar_widget| {
            h_scrollbar_widget.deinit();
        }

        if (self.v_scrollbar) |v_scrollbar_widget| {
            v_scrollbar_widget.deinit();
        }

        self.allocator.destroy(self);
    }

    /// Set the content widget. Ownership stays with the caller.
    pub fn setContent(self: *ScrollContainer, content: *base.Widget) !void {
        if (self.content != content and content.parent != null) return error.WidgetAlreadyAttached;
        try content.attachTo(&self.widget);

        const previous = self.content;
        if (previous != content) {
            self.detachContent();
            self.content = content;
        }
        const size_changed = self.updateContentSize();
        if (previous != content or size_changed) self.widget.markDirty();
    }

    fn detachContent(self: *ScrollContainer) void {
        if (self.content) |current| {
            if (current.parent == &self.widget) {
                current.parent = null;
            }
        }
        self.content = null;
    }

    /// Set whether to show scrollbars
    pub fn setShowScrollbars(self: *ScrollContainer, show_h: bool, show_v: bool) void {
        if (self.show_h_scrollbar == show_h and self.show_v_scrollbar == show_v) return;
        self.show_h_scrollbar = show_h;
        self.show_v_scrollbar = show_v;
        self.syncHScrollbar();
        self.syncVScrollbar();
        self.widget.markDirty();
    }

    /// Set the scroll container colors
    pub fn setColors(self: *ScrollContainer, fg: render.Color, bg: render.Color) void {
        const changed = !std.meta.eql(self.fg, fg) or !std.meta.eql(self.bg, bg);
        self.fg = fg;
        self.bg = bg;

        if (self.h_scrollbar) |h_scrollbar_widget| {
            h_scrollbar_widget.setColors(fg, bg, render.Color{ .named_color = render.NamedColor.white });
        }

        if (self.v_scrollbar) |v_scrollbar_widget| {
            v_scrollbar_widget.setColors(fg, bg, render.Color{ .named_color = render.NamedColor.white });
        }
        if (changed) self.widget.markDirty();
    }

    /// Set the border options
    pub fn setBorder(self: *ScrollContainer, show_border: bool, border_style: BorderStyle) void {
        if (self.show_border == show_border and self.border == border_style) return;
        self.show_border = show_border;
        self.border = border_style;
        self.syncHScrollbar();
        self.syncVScrollbar();
        self.widget.markDirty();
    }

    /// Apply theme defaults for container and scrollbar colors.
    pub fn setTheme(self: *ScrollContainer, theme_value: theme.Theme) void {
        const colors = theme.controlColors(theme_value);
        const changed =
            !std.meta.eql(self.fg, colors.fg) or
            !std.meta.eql(self.bg, colors.bg) or
            !std.meta.eql(self.disabled_fg, colors.disabled_fg) or
            !std.meta.eql(self.disabled_bg, colors.disabled_bg) or
            !std.meta.eql(self.style, theme_value.style);
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
        if (changed) self.widget.markDirty();
    }

    /// Set custom border style
    pub fn setCustomBorderStyle(self: *ScrollContainer, style: *const [6]u21) void {
        if (self.custom_border_style == style) return;
        self.custom_border_style = style;
        self.widget.markDirty();
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
    fn updateContentSize(self: *ScrollContainer) bool {
        if (self.content) |content| {
            const content_size = content.getPreferredSize() catch layout_module.Size.init(0, 0);
            const next_width: i16 = @intCast(@min(content_size.width, std.math.maxInt(i16)));
            const next_height: i16 = @intCast(@min(content_size.height, std.math.maxInt(i16)));
            const changed = self.content_width != next_width or self.content_height != next_height;
            self.content_width = next_width;
            self.content_height = next_height;
            self.syncHScrollbar();
            self.syncVScrollbar();
            return changed;
        }
        return false;
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
        self.widget.markDirty();
    }

    fn applyHOffset(self: *ScrollContainer, offset: i16) void {
        const clamped = std.math.clamp(offset, 0, self.maxHorizontalOffset());
        if (clamped == self.h_offset) return;
        self.h_offset = clamped;
        self.syncHScrollbar();
        self.widget.markDirty();
    }

    fn offsetBySaturating(current: i16, delta: i32) i16 {
        const value = @as(i32, current) + delta;
        return @intCast(std.math.clamp(
            value,
            @as(i32, std.math.minInt(i16)),
            @as(i32, std.math.maxInt(i16)),
        ));
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
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *ScrollContainer = @fieldParentPtr("widget", widget_ref);

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
            const right_x = rectEndCoord(rect.x, rect.width);
            const bottom_y = rectEndCoord(rect.y, rect.height);

            // Top and bottom borders
            for (1..@as(usize, @intCast(rect.width - 1))) |i| {
                const x = rectOffsetCoord(rect.x, i);
                renderer.drawChar(x, rect.y, border_chars[4], fg, bg, style);
                renderer.drawChar(x, bottom_y, border_chars[4], fg, bg, style);
            }

            // Left and right borders
            for (1..@as(usize, @intCast(rect.height - 1))) |i| {
                const y = rectOffsetCoord(rect.y, i);
                renderer.drawChar(rect.x, y, border_chars[5], fg, bg, style);
                renderer.drawChar(right_x, y, border_chars[5], fg, bg, style);
            }

            // Corners
            renderer.drawChar(rect.x, rect.y, border_chars[0], fg, bg, style);
            renderer.drawChar(right_x, rect.y, border_chars[1], fg, bg, style);
            renderer.drawChar(rect.x, bottom_y, border_chars[2], fg, bg, style);
            renderer.drawChar(right_x, bottom_y, border_chars[3], fg, bg, style);
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
            content_rect = content_rect.shrink(layout_module.EdgeInsets.all(1));
        }

        // Adjust for horizontal scrollbar
        if (self.show_h_scrollbar and self.content_width > self.getViewportWidth()) {
            if (content_rect.height > 0) content_rect.height -= 1;
        }

        // Adjust for vertical scrollbar
        if (self.show_v_scrollbar and self.content_height > self.getViewportHeight()) {
            if (content_rect.width > 0) content_rect.width -= 1;
        }

        return content_rect;
    }

    fn translateMouseCoord(coord: u16, offset: i16) u16 {
        var value: i32 = @intCast(coord);
        value += @intCast(offset);
        if (value <= 0) return 0;
        return @intCast(@min(value, std.math.maxInt(u16)));
    }

    fn translateContentEvent(self: *ScrollContainer, event: input.Event, content_rect: layout_module.Rect) ?input.Event {
        if (event != .mouse) return event;

        const mouse_event = event.mouse;
        if (!content_rect.contains(mouse_event.x, mouse_event.y)) return null;

        var translated = mouse_event;
        translated.x = translateMouseCoord(mouse_event.x, self.h_offset);
        translated.y = translateMouseCoord(mouse_event.y, self.v_offset);
        return input.Event{ .mouse = translated };
    }

    /// Event handling implementation for ScrollContainer
    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *ScrollContainer = @fieldParentPtr("widget", widget_ref);

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
            const content_rect = self.getContentRect();
            if (self.translateContentEvent(event, content_rect)) |content_event| {
                if (try content.handleEvent(content_event)) {
                    return true;
                }
            }
        }

        // Handle scroll events ourselves if within our bounds
        if (event == .mouse) {
            const mouse_event = event.mouse;
            const content_rect = self.getContentRect();

            if (content_rect.contains(mouse_event.x, mouse_event.y)) {
                if (mouse_event.action == .scroll_up or mouse_event.action == .scroll_down) {
                    if (self.show_v_scrollbar and self.content_height > self.getViewportHeight()) {
                        const scroll_amount: i32 = 3;
                        const steps: i32 = if (mouse_event.scroll_delta != 0)
                            mouse_event.scroll_delta
                        else if (mouse_event.action == .scroll_up)
                            -1
                        else
                            1;
                        const delta = scroll_amount * steps;
                        self.applyVOffset(offsetBySaturating(self.v_offset, delta));
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
                            self.applyVOffset(offsetBySaturating(self.v_offset, 1));
                            return true;
                        }
                    },
                    .cursor_up => {
                        if (self.show_v_scrollbar and self.content_height > self.getViewportHeight()) {
                            self.applyVOffset(offsetBySaturating(self.v_offset, -1));
                            return true;
                        }
                    },
                    .page_down => {
                        if (self.show_v_scrollbar and self.content_height > self.getViewportHeight()) {
                            self.applyVOffset(offsetBySaturating(self.v_offset, self.getViewportHeight()));
                            return true;
                        }
                        if (self.show_h_scrollbar and self.content_width > self.getViewportWidth()) {
                            self.applyHOffset(offsetBySaturating(self.h_offset, self.getViewportWidth()));
                            return true;
                        }
                    },
                    .page_up => {
                        if (self.show_v_scrollbar and self.content_height > self.getViewportHeight()) {
                            self.applyVOffset(offsetBySaturating(self.v_offset, -@as(i32, self.getViewportHeight())));
                            return true;
                        }
                        if (self.show_h_scrollbar and self.content_width > self.getViewportWidth()) {
                            self.applyHOffset(offsetBySaturating(self.h_offset, -@as(i32, self.getViewportWidth())));
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
                            self.applyHOffset(offsetBySaturating(self.h_offset, 1));
                            return true;
                        }
                    },
                    .cursor_left => {
                        if (self.show_h_scrollbar and self.content_width > self.getViewportWidth()) {
                            self.applyHOffset(offsetBySaturating(self.h_offset, -1));
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
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *ScrollContainer = @fieldParentPtr("widget", widget_ref);
        self.widget.rect = rect;

        // Layout scrollbars
        if (self.show_h_scrollbar) {
            if (self.h_scrollbar) |h_scrollbar_widget| {
                var h_scrollbar_rect = layout_module.Rect.init(rect.x, rect.y, 0, 0);
                if (rect.height > 0) {
                    h_scrollbar_rect = rect;
                    h_scrollbar_rect.y = rectEndCoord(rect.y, rect.height);
                    h_scrollbar_rect.height = 1;

                    if (self.show_v_scrollbar and h_scrollbar_rect.width > 0) {
                        h_scrollbar_rect.width -= 1; // Make room for vertical scrollbar
                    }
                }
                try h_scrollbar_widget.widget.layout(h_scrollbar_rect);
            }
        }

        if (self.show_v_scrollbar) {
            if (self.v_scrollbar) |v_scrollbar_widget| {
                var v_scrollbar_rect = layout_module.Rect.init(rect.x, rect.y, 0, 0);
                if (rect.width > 0) {
                    v_scrollbar_rect = rect;
                    v_scrollbar_rect.x = rectEndCoord(rect.x, rect.width);
                    v_scrollbar_rect.width = 1;

                    if (self.show_h_scrollbar and v_scrollbar_rect.height > 0) {
                        v_scrollbar_rect.height -= 1; // Make room for horizontal scrollbar
                    }
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

        if (self.updateContentSize()) self.widget.markDirty();
    }

    /// Get preferred size implementation for ScrollContainer
    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *ScrollContainer = @fieldParentPtr("widget", widget_ref);

        var width: i16 = 10; // Minimum width
        var height: i16 = 5; // Minimum height

        if (self.content) |content| {
            const content_size = try content.getPreferredSize();
            width = @max(width, @as(i16, @intCast(@min(content_size.width, std.math.maxInt(i16)))));
            height = @max(height, @as(i16, @intCast(@min(content_size.height, std.math.maxInt(i16)))));
        }

        // Add border space
        if (self.show_border) {
            width = addI16Saturating(width, 2);
            height = addI16Saturating(height, 2);
        }

        // Add scrollbar space
        if (self.show_h_scrollbar) {
            height = addI16Saturating(height, 1);
        }

        if (self.show_v_scrollbar) {
            width = addI16Saturating(width, 1);
        }

        return layout_module.Size.init(width, height);
    }

    /// Can focus implementation for ScrollContainer
    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *ScrollContainer = @fieldParentPtr("widget", widget_ref);

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

fn rectEndCoord(start: u16, size: u16) u16 {
    if (size == 0) return start;
    const end = @as(u32, start) + @as(u32, size) - 1;
    return @intCast(@min(end, std.math.maxInt(u16)));
}

fn rectOffsetCoord(start: u16, offset: usize) u16 {
    const capped_offset = @min(offset, @as(usize, std.math.maxInt(u16)));
    const coord = @as(u32, start) + @as(u32, @intCast(capped_offset));
    return @intCast(@min(coord, std.math.maxInt(u16)));
}

test "scroll container init/deinit" {
    const alloc = std.testing.allocator;
    var container = try ScrollContainer.init(alloc);
    defer container.deinit();

    try std.testing.expect(container.h_scrollbar != null);
    try std.testing.expect(container.v_scrollbar != null);
    try std.testing.expectEqual(&container.widget, container.h_scrollbar.?.widget.parent.?);
    try std.testing.expectEqual(&container.widget, container.v_scrollbar.?.widget.parent.?);
}

fn scrollContainerInitAllocationFailureHarness(allocator: std.mem.Allocator) !void {
    var container = try ScrollContainer.init(allocator);
    defer container.deinit();

    try std.testing.expect(container.h_scrollbar != null);
    try std.testing.expect(container.v_scrollbar != null);
}

test "scroll container init cleans up every allocation failure path" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, scrollContainerInitAllocationFailureHarness, .{});
}

test "scroll container maintains parent linkage for content" {
    const alloc = std.testing.allocator;
    var container = try ScrollContainer.init(alloc);
    defer container.deinit();

    var first = try @import("block.zig").Block.init(alloc);
    defer first.deinit();
    var second = try @import("block.zig").Block.init(alloc);
    defer second.deinit();

    try container.setContent(&first.widget);
    try std.testing.expectEqual(&container.widget, first.widget.parent.?);

    try container.setContent(&second.widget);
    try std.testing.expect(first.widget.parent == null);
    try std.testing.expectEqual(&container.widget, second.widget.parent.?);
}

test "scroll container rejects content attached to another parent transactionally" {
    const alloc = std.testing.allocator;
    var owner = try ScrollContainer.init(alloc);
    var target = try ScrollContainer.init(alloc);
    var current = try @import("block.zig").Block.init(alloc);
    var attached = try @import("block.zig").Block.init(alloc);
    defer {
        target.deinit();
        owner.deinit();
        current.deinit();
        attached.deinit();
    }

    current.setPadding(.{ .left = 3, .right = 4, .top = 5, .bottom = 6 });
    try target.setContent(&current.widget);
    try owner.setContent(&attached.widget);
    const width_before = target.content_width;
    const height_before = target.content_height;
    target.widget.clearDirty();

    try std.testing.expectError(error.WidgetAlreadyAttached, target.setContent(&attached.widget));
    try std.testing.expectEqual(&current.widget, target.content.?);
    try std.testing.expectEqual(width_before, target.content_width);
    try std.testing.expectEqual(height_before, target.content_height);
    try std.testing.expectEqual(&target.widget, current.widget.parent.?);
    try std.testing.expectEqual(&attached.widget, owner.content.?);
    try std.testing.expectEqual(&owner.widget, attached.widget.parent.?);
    try std.testing.expect(!target.widget.dirty);
}

test "scroll container visible mutations mark dirty" {
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

    const custom_border = [_]u21{ '/', '\\', '\\', '/', '=', '!' };

    const alloc = std.testing.allocator;
    var container = try ScrollContainer.init(alloc);
    defer container.deinit();

    try container.widget.layout(layout_module.Rect.init(0, 0, 10, 6));
    var renderer = try render.Renderer.init(alloc, 10, 6);
    defer renderer.deinit();

    try container.widget.draw(&renderer);
    try std.testing.expect(!container.widget.dirty);

    var dummy = Dummy{};
    try container.setContent(&dummy.widget);
    try std.testing.expect(container.widget.dirty);

    try container.widget.layout(layout_module.Rect.init(0, 0, 10, 6));
    try container.widget.draw(&renderer);
    try std.testing.expect(!container.widget.dirty);

    try container.setContent(&dummy.widget);
    try std.testing.expect(!container.widget.dirty);

    container.setShowScrollbars(false, true);
    try std.testing.expect(container.widget.dirty);

    try container.widget.draw(&renderer);
    try std.testing.expect(!container.widget.dirty);

    container.setShowScrollbars(false, true);
    try std.testing.expect(!container.widget.dirty);

    container.setBorder(false, .single);
    try std.testing.expect(container.widget.dirty);

    try container.widget.draw(&renderer);
    try std.testing.expect(!container.widget.dirty);

    container.setBorder(false, .single);
    try std.testing.expect(!container.widget.dirty);

    container.setCustomBorderStyle(&custom_border);
    try std.testing.expect(container.widget.dirty);

    try container.widget.draw(&renderer);
    try std.testing.expect(!container.widget.dirty);

    container.setCustomBorderStyle(&custom_border);
    try std.testing.expect(!container.widget.dirty);

    container.setColors(render.Color.named(.red), render.Color.named(.black));
    try std.testing.expect(container.widget.dirty);

    try container.widget.draw(&renderer);
    try std.testing.expect(!container.widget.dirty);

    container.setColors(render.Color.named(.red), render.Color.named(.black));
    try std.testing.expect(!container.widget.dirty);

    container.setBorder(true, .single);
    container.setShowScrollbars(true, true);
    try container.widget.layout(layout_module.Rect.init(0, 0, 10, 6));
    try container.widget.draw(&renderer);
    try std.testing.expect(!container.widget.dirty);

    container.applyVOffset(1);
    try std.testing.expect(container.widget.dirty);

    try container.widget.draw(&renderer);
    try std.testing.expect(!container.widget.dirty);

    container.applyVOffset(1);
    try std.testing.expect(!container.widget.dirty);

    container.applyHOffset(1);
    try std.testing.expect(container.widget.dirty);

    try container.widget.draw(&renderer);
    try std.testing.expect(!container.widget.dirty);

    container.applyHOffset(1);
    try std.testing.expect(!container.widget.dirty);
}

test "scroll container deinit detaches content parent link" {
    const alloc = std.testing.allocator;
    var container = try ScrollContainer.init(alloc);

    var content = try @import("block.zig").Block.init(alloc);
    defer content.deinit();

    try container.setContent(&content.widget);
    container.deinit();

    try std.testing.expect(content.widget.parent == null);
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
    try container.setContent(&dummy.widget);

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

test "scroll container tolerates tiny layouts with overflowing content" {
    const Dummy = struct {
        widget: base.Widget = base.Widget.init(&vtable),
        const vtable = base.Widget.VTable{
            .draw = drawFn,
            .handle_event = handleEventFn,
            .layout = layoutFn,
            .get_preferred_size = preferredFn,
            .can_focus = canFocusFn,
        };

        fn drawFn(_: *anyopaque, renderer: *render.Renderer) anyerror!void {
            renderer.drawStr(0, 0, "overflowing content", render.Color.named(.white), render.Color.named(.default), render.Style{});
        }
        fn handleEventFn(_: *anyopaque, _: input.Event) anyerror!bool {
            return false;
        }
        fn layoutFn(_: *anyopaque, _: layout_module.Rect) anyerror!void {}
        fn preferredFn(_: *anyopaque) anyerror!layout_module.Size {
            return layout_module.Size.init(80, 24);
        }
        fn canFocusFn(_: *anyopaque) bool {
            return false;
        }
    };

    const alloc = std.testing.allocator;
    var container = try ScrollContainer.init(alloc);
    defer container.deinit();
    var dummy = Dummy{};
    try container.setContent(&dummy.widget);

    var renderer = try render.Renderer.init(alloc, 4, 4);
    defer renderer.deinit();

    const tiny_rects = [_]layout_module.Rect{
        layout_module.Rect.init(0, 0, 0, 0),
        layout_module.Rect.init(0, 0, 1, 1),
        layout_module.Rect.init(0, 0, 2, 1),
        layout_module.Rect.init(0, 0, 1, 2),
    };

    for (tiny_rects) |rect| {
        try container.widget.layout(rect);
        try container.widget.draw(&renderer);
    }
}

test "scroll container clips border edge coordinates before u16 overflow" {
    const alloc = std.testing.allocator;
    var container = try ScrollContainer.init(alloc);
    defer container.deinit();

    try container.widget.layout(layout_module.Rect.init(
        std.math.maxInt(u16) - 1,
        std.math.maxInt(u16) - 1,
        4,
        4,
    ));

    var renderer = try render.Renderer.init(alloc, 4, 4);
    defer renderer.deinit();

    try container.widget.draw(&renderer);
}

test "scroll container preferred size saturates chrome inflation" {
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
            return layout_module.Size.init(std.math.maxInt(i16), std.math.maxInt(i16));
        }
        fn canFocusFn(_: *anyopaque) bool {
            return false;
        }
    };

    const alloc = std.testing.allocator;
    var container = try ScrollContainer.init(alloc);
    defer container.deinit();
    var dummy = Dummy{};
    try container.setContent(&dummy.widget);

    const size = try container.widget.getPreferredSize();
    try std.testing.expectEqual(@as(u16, @intCast(std.math.maxInt(i16))), size.width);
    try std.testing.expectEqual(@as(u16, @intCast(std.math.maxInt(i16))), size.height);
}

test "scroll container saturates relative offset arithmetic" {
    try std.testing.expectEqual(
        std.math.maxInt(i16),
        ScrollContainer.offsetBySaturating(std.math.maxInt(i16), 1),
    );
    try std.testing.expectEqual(
        std.math.minInt(i16),
        ScrollContainer.offsetBySaturating(std.math.minInt(i16), -1),
    );
    try std.testing.expectEqual(
        @as(i16, 15),
        ScrollContainer.offsetBySaturating(10, 5),
    );
    try std.testing.expectEqual(
        @as(i16, 5),
        ScrollContainer.offsetBySaturating(10, -5),
    );
}

test "scroll container clamps keyboard offsets after saturating overflow edges" {
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
            return layout_module.Size.init(std.math.maxInt(u16), std.math.maxInt(u16));
        }
        fn canFocusFn(_: *anyopaque) bool {
            return false;
        }
    };

    const alloc = std.testing.allocator;
    var container = try ScrollContainer.init(alloc);
    defer container.deinit();
    var dummy = Dummy{};
    try container.setContent(&dummy.widget);
    try container.widget.layout(layout_module.Rect.init(0, 0, 10, 6));
    container.widget.focused = true;

    container.v_offset = std.math.maxInt(i16);
    try std.testing.expect(try container.widget.handleEvent(.{ .key = input.KeyEvent.init(input.KeyCode.DOWN, .{}) }));
    try std.testing.expectEqual(container.maxVerticalOffset(), container.v_offset);

    container.h_offset = std.math.maxInt(i16);
    container.v_offset = 0;
    container.show_v_scrollbar = false;
    try std.testing.expect(try container.widget.handleEvent(.{ .key = input.KeyEvent.init(input.KeyCode.RIGHT, .{}) }));
    try std.testing.expectEqual(container.maxHorizontalOffset(), container.h_offset);
}

test "scroll container saturates large wheel deltas before clamping" {
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
            return layout_module.Size.init(20, std.math.maxInt(u16));
        }
        fn canFocusFn(_: *anyopaque) bool {
            return false;
        }
    };

    const alloc = std.testing.allocator;
    var container = try ScrollContainer.init(alloc);
    defer container.deinit();
    var dummy = Dummy{};
    try container.setContent(&dummy.widget);
    try container.widget.layout(layout_module.Rect.init(0, 0, 10, 6));

    container.v_offset = std.math.maxInt(i16);
    const scroll_event = input.Event{ .mouse = input.MouseEvent.init(
        .scroll_down,
        1,
        1,
        0,
        std.math.maxInt(i16),
    ) };
    try std.testing.expect(try container.widget.handleEvent(scroll_event));
    try std.testing.expectEqual(container.maxVerticalOffset(), container.v_offset);
}

test "scroll container translates mouse events into scrolled content space" {
    const Clickable = struct {
        widget: base.Widget = base.Widget.init(&vtable),
        last_x: ?u16 = null,
        last_y: ?u16 = null,

        const vtable = base.Widget.VTable{
            .draw = drawFn,
            .handle_event = handleEventFn,
            .layout = layoutFn,
            .get_preferred_size = preferredFn,
            .can_focus = canFocusFn,
        };

        fn owner(widget_ptr: *anyopaque) *@This() {
            const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
            return @fieldParentPtr("widget", widget_ref);
        }

        fn drawFn(_: *anyopaque, _: *render.Renderer) anyerror!void {}

        fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
            const self = owner(widget_ptr);
            if (event != .mouse) return false;
            self.last_x = event.mouse.x;
            self.last_y = event.mouse.y;
            return true;
        }

        fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
            owner(widget_ptr).widget.rect = rect;
        }

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

    var clickable = Clickable{};
    try container.setContent(&clickable.widget);
    try container.widget.layout(layout_module.Rect.init(0, 0, 10, 6));
    container.applyHOffset(2);
    container.applyVOffset(3);

    const visible_content = container.getContentRect();
    const click = input.Event{ .mouse = input.MouseEvent.init(
        .press,
        visible_content.x + 2,
        visible_content.y + 1,
        1,
        0,
    ) };

    try std.testing.expect(try container.widget.handleEvent(click));
    try std.testing.expectEqual(visible_content.x + 4, clickable.last_x.?);
    try std.testing.expectEqual(visible_content.y + 4, clickable.last_y.?);
}
