const std = @import("std");
const base = @import("base_widget.zig");
const Widget = base.Widget;
const layout_module = @import("../../layout/layout.zig");
const Size = layout_module.Size;
const render = @import("../../render/render.zig");
const text_metrics = @import("../../render/text_metrics.zig");
const input = @import("../../input/input.zig");
const theme = @import("../theme.zig");
const accessibility = @import("../accessibility.zig");

/// Modal dialog widget
pub const Modal = struct {
    /// Base widget
    widget: Widget,
    /// Content widget
    content: ?*Widget = null,
    /// Modal title
    title: []const u8 = "",
    /// Modal width
    width: u16 = 40,
    /// Modal height
    height: u16 = 10,
    /// Show title
    show_title: bool = true,
    /// Title foreground color
    title_fg: render.Color = render.Color{ .named_color = render.NamedColor.white },
    /// Title background color
    title_bg: render.Color = render.Color{ .named_color = render.NamedColor.blue },
    /// Foreground color
    fg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    /// Background color
    bg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    /// Border foreground color
    border_fg: render.Color = render.Color{ .named_color = render.NamedColor.white },
    /// Show border
    show_border: bool = true,
    /// Modal is centered
    centered: bool = true,
    /// Close on escape key
    close_on_escape: bool = true,
    /// On close callback
    on_close: ?*const fn () void = null,
    /// Allocator for modal operations
    allocator: std.mem.Allocator,

    /// Virtual method table for Modal
    pub const vtable = Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    /// Initialize a new modal
    pub fn init(allocator: std.mem.Allocator) !*Modal {
        const self = try allocator.create(Modal);
        self.* = Modal{
            .widget = Widget{
                .vtable = &vtable,
            },
            .width = 40,
            .height = 10,
            .allocator = allocator,
            .title = "",
            .content = null,
        };
        self.setTheme(theme.Theme.dark());
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.popup), "Modal", "");
        return self;
    }

    /// Clean up modal resources
    pub fn deinit(self: *Modal) void {
        self.detachContent();
        if (self.title.len > 0) {
            self.allocator.free(self.title);
        }
        self.allocator.destroy(self);
    }

    /// Set the modal content
    pub fn setContent(self: *Modal, content: *Widget) void {
        self.detachContent();
        self.content = content;
        content.parent = &self.widget;
    }

    fn detachContent(self: *Modal) void {
        if (self.content) |current| {
            if (current.parent == &self.widget) {
                current.parent = null;
            }
        }
        self.content = null;
    }

    /// Set the modal title
    pub fn setTitle(self: *Modal, title: []const u8) !void {
        const title_copy = if (title.len == 0) "" else try self.allocator.dupe(u8, title);

        if (self.title.len > 0) {
            self.allocator.free(self.title);
        }

        self.title = title_copy;
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.popup), self.accessibilityLabel(), "");
    }

    fn accessibilityLabel(self: *Modal) []const u8 {
        return if (self.title.len > 0) self.title else "Modal";
    }

    /// Set the modal colors
    pub fn setColors(self: *Modal, fg: render.Color, bg: render.Color, border_fg: render.Color) void {
        self.fg = fg;
        self.bg = bg;
        self.border_fg = border_fg;
    }

    /// Set the title colors
    pub fn setTitleColors(self: *Modal, title_fg: render.Color, title_bg: render.Color) void {
        self.title_fg = title_fg;
        self.title_bg = title_bg;
    }

    /// Apply theme defaults for modal colors.
    pub fn setTheme(self: *Modal, theme_value: theme.Theme) void {
        const colors = theme.modalColors(theme_value);
        self.title_fg = colors.title_fg;
        self.title_bg = colors.title_bg;
        self.fg = colors.fg;
        self.bg = colors.bg;
        self.border_fg = colors.border_fg;
    }

    /// Set whether to show the title
    pub fn setShowTitle(self: *Modal, show_title: bool) void {
        self.show_title = show_title;
    }

    /// Set whether to show the border
    pub fn setShowBorder(self: *Modal, show_border: bool) void {
        self.show_border = show_border;
    }

    /// Set whether the modal is centered
    pub fn setCentered(self: *Modal, centered: bool) void {
        self.centered = centered;
    }

    /// Set whether to close on escape key
    pub fn setCloseOnEscape(self: *Modal, close_on_escape: bool) void {
        self.close_on_escape = close_on_escape;
    }

    /// Set the on-close callback
    pub fn setOnClose(self: *Modal, callback: *const fn () void) void {
        self.on_close = callback;
    }

    /// Close the modal
    pub fn close(self: *Modal) void {
        self.widget.visible = false;

        if (self.on_close != null) {
            self.on_close.?();
        }
    }

    /// Draw implementation for Modal
    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Modal = @fieldParentPtr("widget", widget_ref);

        if (!self.widget.visible) {
            return;
        }

        const rect = self.widget.rect;
        const styled = self.widget.applyStyle(
            "modal",
            .{ .focus = self.widget.focused, .disabled = !self.widget.enabled },
            render.Style{},
            self.fg,
            self.bg,
        );
        const bg = styled.bg;
        const style = styled.style;

        if (rect.width == 0 or rect.height == 0) return;

        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', styled.fg, bg, style);

        const draw_border = self.show_border and rect.width >= 2 and rect.height >= 2;
        if (draw_border) {
            renderer.drawBox(rect.x, rect.y, rect.width, rect.height, .rounded, self.border_fg, bg, style);
        }

        // Draw title if enabled
        if (self.show_title and self.title.len > 0) {
            const title_inset: u16 = if (draw_border) 1 else 0;
            if (rect.width > title_inset * 2) {
                const title_y = rect.y;
                const title_x = rect.x + title_inset;
                const title_width = rect.width - title_inset * 2;
                var title_buf: [256]u8 = undefined;
                const clipped = text_metrics.clipWithEllipsis(self.title, title_width, &title_buf);
                const text_x = title_x + (title_width - clipped.width) / 2;

                renderer.fillRect(title_x, title_y, title_width, 1, ' ', self.title_fg, self.title_bg, style);
                renderer.drawStr(text_x, title_y, clipped.text, self.title_fg, self.title_bg, style);
            }
        }

        // Draw content
        if (self.content) |content| {
            try content.draw(renderer);
        }
    }

    /// Event handling implementation for Modal
    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Modal = @fieldParentPtr("widget", widget_ref);

        if (!self.widget.visible or !self.widget.enabled) {
            return false;
        }

        // Pass event to content first
        if (self.content) |content| {
            if (try content.handleEvent(event)) {
                return true;
            }
        }

        // Close on escape key if enabled
        if (event == .key and self.close_on_escape) {
            const key_event = event.key;

            if (key_event.key == input.KeyCode.ESCAPE) {
                self.close();
                return true;
            }
        }

        return false;
    }

    /// Layout implementation for Modal
    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Modal = @fieldParentPtr("widget", widget_ref);

        var modal_rect = rect;

        // Center modal in available space
        const pref_size = try self.getPreferredSize();
        modal_rect.width = @min(pref_size.width, rect.width);
        modal_rect.height = @min(pref_size.height, rect.height);
        modal_rect.x = rect.x + @divTrunc(rect.width - modal_rect.width, 2);
        modal_rect.y = rect.y + @divTrunc(rect.height - modal_rect.height, 2);

        self.widget.rect = modal_rect;

        // Layout content if present
        if (self.content) |content| {
            const content_rect = self.contentRect(modal_rect);
            try content.layout(content_rect);
        }
    }

    fn contentRect(self: *Modal, rect: layout_module.Rect) layout_module.Rect {
        if (rect.width == 0 or rect.height == 0) return layout_module.Rect.init(rect.x, rect.y, 0, 0);

        const border_inset: u16 = if (self.show_border and rect.width > 2 and rect.height > 2) 1 else 0;
        const title_rows: u16 = if (self.show_title and self.title.len > 0 and rect.height > border_inset) 1 else 0;
        const x = rect.x + border_inset;
        const y = rect.y + border_inset + title_rows;
        const width = if (rect.width > border_inset * 2) rect.width - border_inset * 2 else 0;
        const consumed_height = border_inset * 2 + title_rows;
        const height = if (rect.height > consumed_height) rect.height - consumed_height else 0;
        return layout_module.Rect.init(x, y, width, height);
    }

    /// Get preferred size implementation for Modal
    fn getPreferredSize(self: *Modal) anyerror!layout_module.Size {
        var width: u16 = self.width;
        var height: u16 = self.height;

        // Account for content size
        if (self.content) |content| {
            const content_size = try content.getPreferredSize();
            width = @max(width, content_size.width + 2);
            height = @max(height, content_size.height + 3);
        }

        return layout_module.Size.init(width, height);
    }

    /// Can focus implementation for Modal
    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Modal = @fieldParentPtr("widget", widget_ref);

        if (!self.widget.enabled) {
            return false;
        }

        // Modal can be focused if it has focusable content
        if (self.content) |content| {
            return content.canFocus();
        }

        return false;
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!Size {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Modal = @fieldParentPtr("widget", widget_ref);
        return self.getPreferredSize();
    }
};

var test_modal_closed: usize = 0;

test "modal init/deinit" {
    const alloc = std.testing.allocator;
    var modal = try Modal.init(alloc);
    defer modal.deinit();

    try modal.setTitle("Confirm");
    try std.testing.expectEqualStrings("Confirm", modal.title);
}

test "modal setTitle preserves title on allocation failure" {
    const alloc = std.testing.allocator;
    var modal = try Modal.init(alloc);
    defer modal.deinit();

    try modal.setTitle("Stable");

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = modal.allocator;
    modal.allocator = failing.allocator();
    defer modal.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, modal.setTitle("Replacement"));
    try std.testing.expectEqualStrings("Stable", modal.title);
    try std.testing.expectEqualStrings("Stable", modal.widget.accessibility_name);
}

test "modal closes on escape and fires callback" {
    const alloc = std.testing.allocator;
    var modal = try Modal.init(alloc);
    defer modal.deinit();

    test_modal_closed = 0;
    const callback = struct {
        fn call() void {
            test_modal_closed += 1;
        }
    }.call;
    modal.setOnClose(callback);

    modal.widget.visible = true;
    const escape_event = input.Event{ .key = input.KeyEvent.init(input.KeyCode.ESCAPE, input.KeyModifiers{}) };
    try std.testing.expect(try modal.widget.handleEvent(escape_event));
    try std.testing.expect(!modal.widget.visible);
    try std.testing.expectEqual(@as(usize, 1), test_modal_closed);
}

test "modal clamps to available bounds when empty" {
    const alloc = std.testing.allocator;
    var modal = try Modal.init(alloc);
    defer modal.deinit();

    try modal.widget.layout(layout_module.Rect.init(0, 0, 8, 4));
    try std.testing.expectEqual(@as(u16, 8), modal.widget.rect.width);
    try std.testing.expectEqual(@as(u16, 4), modal.widget.rect.height);
}

test "modal renders rounded border and respects no-border mode" {
    const alloc = std.testing.allocator;
    var modal = try Modal.init(alloc);
    defer modal.deinit();
    modal.width = 8;
    modal.height = 4;
    try modal.setTitle("Hi");
    try modal.widget.layout(layout_module.Rect.init(0, 0, 8, 4));

    var renderer = try render.Renderer.init(alloc, 8, 4);
    defer renderer.deinit();
    try modal.widget.draw(&renderer);
    try std.testing.expectEqual(@as(u21, '╭'), renderer.back.getCell(0, 0).codepoint());
    try std.testing.expectEqual(@as(u21, '╮'), renderer.back.getCell(7, 0).codepoint());
    try std.testing.expectEqual(@as(u21, '╰'), renderer.back.getCell(0, 3).codepoint());
    try std.testing.expectEqual(@as(u21, '╯'), renderer.back.getCell(7, 3).codepoint());

    modal.setShowBorder(false);
    var no_border = try render.Renderer.init(alloc, 8, 4);
    defer no_border.deinit();
    try modal.widget.draw(&no_border);
    try std.testing.expect(no_border.back.getCell(0, 0).codepoint() != '╭');
}

test "modal title renders wide utf8 glyphs as graphemes" {
    const alloc = std.testing.allocator;
    var modal = try Modal.init(alloc);
    defer modal.deinit();

    modal.width = 4;
    modal.height = 3;
    try modal.setTitle("界");
    try modal.widget.layout(layout_module.Rect.init(0, 0, 4, 3));

    var renderer = try render.Renderer.init(alloc, 4, 3);
    defer renderer.deinit();
    renderer.capabilities.unicode = true;
    renderer.capabilities.double_width = true;

    try modal.widget.draw(&renderer);
    try std.testing.expectEqual(@as(u21, '界'), renderer.back.getCell(1, 0).*.codepoint());
    try std.testing.expect(renderer.back.getCell(2, 0).*.continuation);
}

test "modal tolerates tiny layouts" {
    const alloc = std.testing.allocator;
    var modal = try Modal.init(alloc);
    defer modal.deinit();
    try modal.setTitle("Tiny");
    try modal.widget.layout(layout_module.Rect.init(0, 0, 1, 1));

    var renderer = try render.Renderer.init(alloc, 1, 1);
    defer renderer.deinit();
    try modal.widget.draw(&renderer);
}

test "modal maintains parent linkage for content" {
    const alloc = std.testing.allocator;
    var modal = try Modal.init(alloc);
    defer modal.deinit();

    var first = try @import("block.zig").Block.init(alloc);
    defer first.deinit();
    var second = try @import("block.zig").Block.init(alloc);
    defer second.deinit();

    modal.setContent(&first.widget);
    try std.testing.expectEqual(&modal.widget, first.widget.parent.?);

    modal.setContent(&second.widget);
    try std.testing.expect(first.widget.parent == null);
    try std.testing.expectEqual(&modal.widget, second.widget.parent.?);
}

test "modal deinit detaches content parent link" {
    const alloc = std.testing.allocator;
    var modal = try Modal.init(alloc);

    var content = try @import("block.zig").Block.init(alloc);
    defer content.deinit();

    modal.setContent(&content.widget);
    modal.deinit();

    try std.testing.expect(content.widget.parent == null);
}
