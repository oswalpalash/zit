const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");

/// Checkbox widget
pub const Checkbox = struct {
    /// Base widget
    widget: base.Widget,
    /// Checkbox label
    label: []const u8,
    /// Whether the checkbox is checked
    checked: bool = false,
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
    /// Callback function for checkbox change
    on_change: ?*const fn (bool) void = null,
    /// Allocator for checkbox operations
    allocator: std.mem.Allocator,

    /// Virtual method table for Checkbox
    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    /// Initialize a new checkbox
    pub fn init(allocator: std.mem.Allocator, label: []const u8) !*Checkbox {
        const self = try allocator.create(Checkbox);

        self.* = Checkbox{
            .widget = base.Widget.init(&vtable),
            .label = try allocator.dupe(u8, label),
            .allocator = allocator,
        };

        return self;
    }

    /// Clean up checkbox resources
    pub fn deinit(self: *Checkbox) void {
        self.allocator.free(self.label);
        self.allocator.destroy(self);
    }

    /// Set the checkbox state
    pub fn setChecked(self: *Checkbox, checked: bool) void {
        if (self.checked != checked) {
            self.checked = checked;
            if (self.on_change) |callback| {
                callback(self.checked);
            }
        }
    }

    /// Toggle the checkbox state
    pub fn toggle(self: *Checkbox) void {
        self.setChecked(!self.checked);
    }

    /// Set the checkbox colors
    pub fn setColors(self: *Checkbox, fg: render.Color, bg: render.Color, focused_fg: render.Color, focused_bg: render.Color) void {
        self.fg = fg;
        self.bg = bg;
        self.focused_fg = focused_fg;
        self.focused_bg = focused_bg;
    }

    /// Set the on-change callback
    pub fn setOnChange(self: *Checkbox, callback: *const fn (bool) void) void {
        self.on_change = callback;
    }

    /// Draw implementation for Checkbox
    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*Checkbox, @ptrCast(@alignCast(widget_ptr)));

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

        // Draw checkbox
        renderer.drawChar(rect.x, rect.y, if (self.checked) 'X' else ' ', fg, bg, render.Style{});
        if (rect.x > 0) {
            renderer.drawChar(rect.x - 1, rect.y, '[', fg, bg, render.Style{});
        }
        renderer.drawChar(rect.x + 1, rect.y, ']', fg, bg, render.Style{});

        // Draw label
        if (self.label.len > 0 and rect.width > 4) {
            var truncated_text: [256]u8 = undefined;
            const max_width = @min(@as(usize, rect.width), truncated_text.len);
            if (max_width > 7 and self.label.len > max_width - 7) {
                @memcpy(truncated_text[0 .. max_width - 7], self.label[0 .. max_width - 7]);
                @memcpy(truncated_text[max_width - 7 .. max_width - 4], "...");
                renderer.drawStr(rect.x + 3, rect.y, truncated_text[0 .. max_width - 4], fg, bg, render.Style{});
            } else {
                renderer.drawStr(rect.x + 3, rect.y, self.label, fg, bg, render.Style{});
            }
        }
    }

    /// Event handling implementation for Checkbox
    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*Checkbox, @ptrCast(@alignCast(widget_ptr)));

        if (!self.widget.visible or !self.widget.enabled) {
            return false;
        }

        switch (event) {
            .mouse => |mouse| {
                if (mouse.action == .press and mouse.button == 1) {
                    if (self.widget.rect.contains(mouse.x, mouse.y)) {
                        self.toggle();
                        return true;
                    }
                }
            },
            .key => |key| {
                if (self.widget.focused and (key.key == '\n' or key.key == ' ')) {
                    self.toggle();
                    return true;
                }
            },
            else => {},
        }

        return false;
    }

    /// Layout implementation for Checkbox
    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*Checkbox, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    /// Get preferred size implementation for Checkbox
    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*Checkbox, @ptrCast(@alignCast(widget_ptr)));

        return layout_module.Size.init(@as(u16, @intCast(@min(self.label.len + 4, 40))), // Cap width at 40 chars
            1 // Height is 1 row
        );
    }

    /// Can focus implementation for Checkbox
    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*Checkbox, @ptrCast(@alignCast(widget_ptr)));
        return self.widget.enabled;
    }
};
