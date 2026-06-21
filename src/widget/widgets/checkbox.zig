const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const text_metrics = @import("../../render/text_metrics.zig");
const input = @import("../../input/input.zig");
const theme = @import("../theme.zig");
const accessibility = @import("../accessibility.zig");

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
        errdefer allocator.destroy(self);

        const label_copy = try allocator.dupe(u8, label);
        self.* = Checkbox{
            .widget = base.Widget.init(&vtable),
            .label = label_copy,
            .allocator = allocator,
        };
        self.setTheme(theme.Theme.dark());
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.checkbox), self.label, "");

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
            self.widget.markDirty();
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
        if (std.meta.eql(self.fg, fg) and
            std.meta.eql(self.bg, bg) and
            std.meta.eql(self.focused_fg, focused_fg) and
            std.meta.eql(self.focused_bg, focused_bg))
        {
            return;
        }

        self.fg = fg;
        self.bg = bg;
        self.focused_fg = focused_fg;
        self.focused_bg = focused_bg;
        self.widget.markDirty();
    }

    /// Set the on-change callback
    pub fn setOnChange(self: *Checkbox, callback: *const fn (bool) void) void {
        self.on_change = callback;
    }

    /// Apply theme defaults for checkbox colors.
    pub fn setTheme(self: *Checkbox, theme_value: theme.Theme) void {
        const colors = theme.controlColors(theme_value);
        if (std.meta.eql(self.fg, colors.fg) and
            std.meta.eql(self.bg, colors.bg) and
            std.meta.eql(self.focused_fg, colors.focused_fg) and
            std.meta.eql(self.focused_bg, colors.focused_bg) and
            std.meta.eql(self.disabled_fg, colors.disabled_fg) and
            std.meta.eql(self.disabled_bg, colors.disabled_bg))
        {
            return;
        }

        self.fg = colors.fg;
        self.bg = colors.bg;
        self.focused_fg = colors.focused_fg;
        self.focused_bg = colors.focused_bg;
        self.disabled_fg = colors.disabled_fg;
        self.disabled_bg = colors.disabled_bg;
        self.widget.markDirty();
    }

    fn addOffsetClamped(origin: u16, offset: u16) u16 {
        const value = @as(u32, origin) + @as(u32, offset);
        return @intCast(@min(value, @as(u32, std.math.maxInt(u16))));
    }

    /// Draw implementation for Checkbox
    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Checkbox = @fieldParentPtr("widget", widget_ref);

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
            "checkbox",
            .{ .focus = self.widget.focused, .disabled = !self.widget.enabled },
            render.Style{},
            base_fg,
            base_bg,
        );
        const fg = styled.fg;
        const bg = styled.bg;

        // Draw checkbox inside the assigned rect so visual and mouse bounds match.
        if (rect.width >= 3) {
            renderer.drawChar(rect.x, rect.y, '[', fg, bg, render.Style{});
            renderer.drawChar(addOffsetClamped(rect.x, 1), rect.y, if (self.checked) 'X' else ' ', fg, bg, render.Style{});
            renderer.drawChar(addOffsetClamped(rect.x, 2), rect.y, ']', fg, bg, render.Style{});
        }

        // Draw label
        if (self.label.len > 0 and rect.width > 3) {
            const available_width: u16 = rect.width - 3;
            var truncated_text: [256]u8 = undefined;
            const label_width = available_width;
            const clipped = text_metrics.clipWithEllipsis(self.label, label_width, &truncated_text);
            renderer.drawStr(addOffsetClamped(rect.x, 4), rect.y, clipped.text, fg, bg, render.Style{});
        }
    }

    /// Event handling implementation for Checkbox
    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Checkbox = @fieldParentPtr("widget", widget_ref);

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
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Checkbox = @fieldParentPtr("widget", widget_ref);
        self.widget.rect = rect;
    }

    /// Get preferred size implementation for Checkbox
    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Checkbox = @fieldParentPtr("widget", widget_ref);

        const label_width: usize = text_metrics.measureWidth(self.label).width;
        return layout_module.Size.init(@as(u16, @intCast(@min(label_width + 4, 40))), // Cap width at 40 cells
            1 // Height is 1 row
        );
    }

    /// Can focus implementation for Checkbox
    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Checkbox = @fieldParentPtr("widget", widget_ref);
        return self.widget.enabled;
    }
};

var test_checkbox_calls: usize = 0;
var test_checkbox_state: ?bool = null;

test "checkbox init/deinit" {
    const alloc = std.testing.allocator;
    var checkbox = try Checkbox.init(alloc, "Accept");
    defer checkbox.deinit();

    try std.testing.expectEqualStrings("Accept", checkbox.label);
}

fn checkboxInitAllocationFailureHarness(allocator: std.mem.Allocator) !void {
    var checkbox = try Checkbox.init(allocator, "Accept");
    defer checkbox.deinit();
}

test "checkbox init cleans up every allocation failure path" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, checkboxInitAllocationFailureHarness, .{});
}

test "checkbox toggles and fires callback" {
    const alloc = std.testing.allocator;
    var checkbox = try Checkbox.init(alloc, "Agree");
    defer checkbox.deinit();

    test_checkbox_calls = 0;
    test_checkbox_state = null;
    const callback = struct {
        fn call(value: bool) void {
            test_checkbox_calls += 1;
            test_checkbox_state = value;
        }
    }.call;
    checkbox.setOnChange(callback);
    checkbox.widget.rect = layout_module.Rect.init(0, 0, 8, 1);

    const click_event = input.Event{ .mouse = input.MouseEvent.init(.press, 0, 0, 1, 0) };
    try std.testing.expect(try checkbox.widget.handleEvent(click_event));
    try std.testing.expect(checkbox.checked);
    try std.testing.expectEqual(@as(usize, 1), test_checkbox_calls);
    try std.testing.expectEqual(true, test_checkbox_state.?);
}

test "checkbox setColors marks dirty only when visual colors change" {
    const alloc = std.testing.allocator;
    var checkbox = try Checkbox.init(alloc, "Agree");
    defer checkbox.deinit();

    checkbox.widget.clearDirty();
    checkbox.setColors(checkbox.fg, checkbox.bg, checkbox.focused_fg, checkbox.focused_bg);
    try std.testing.expect(!checkbox.widget.dirty);

    checkbox.setColors(render.Color.named(.green), checkbox.bg, checkbox.focused_fg, checkbox.focused_bg);
    try std.testing.expect(checkbox.widget.dirty);
}

test "checkbox setTheme marks dirty only when theme colors change" {
    const alloc = std.testing.allocator;
    var checkbox = try Checkbox.init(alloc, "Agree");
    defer checkbox.deinit();

    checkbox.widget.clearDirty();
    checkbox.setTheme(theme.Theme.dark());
    try std.testing.expect(!checkbox.widget.dirty);

    checkbox.setTheme(theme.Theme.light());
    try std.testing.expect(checkbox.widget.dirty);
}

test "checkbox handles decoded terminal mouse coordinates at rendered row" {
    const alloc = std.testing.allocator;
    var checkbox = try Checkbox.init(alloc, "Agree");
    defer checkbox.deinit();

    checkbox.widget.rect = layout_module.Rect.init(2, 3, 10, 1);

    const row_above = (try input.decodeEventFromBytes("\x1b[<0;3;3M")).?;
    try std.testing.expect(!try checkbox.widget.handleEvent(row_above));
    try std.testing.expect(!checkbox.checked);

    const rendered_row = (try input.decodeEventFromBytes("\x1b[<0;3;4M")).?;
    try std.testing.expect(try checkbox.widget.handleEvent(rendered_row));
    try std.testing.expect(checkbox.checked);
}

test "checkbox does not ellipsize label that exactly fits preferred width" {
    const alloc = std.testing.allocator;
    var checkbox = try Checkbox.init(alloc, "Safe mode");
    defer checkbox.deinit();

    try checkbox.widget.layout(layout_module.Rect.init(1, 0, 14, 1));

    var renderer = try render.Renderer.init(alloc, 15, 1);
    defer renderer.deinit();
    try checkbox.widget.draw(&renderer);

    const expected = "Safe mode";
    for (expected, 0..) |char, idx| {
        try std.testing.expectEqual(@as(u21, char), renderer.back.getCell(@as(u16, @intCast(idx + 5)), 0).*.codepoint());
    }
}

test "checkbox clamps edge draw coordinates" {
    const alloc = std.testing.allocator;
    var checkbox = try Checkbox.init(alloc, "Edge");
    defer checkbox.deinit();

    checkbox.setChecked(true);
    try checkbox.widget.layout(layout_module.Rect.init(std.math.maxInt(u16) - 1, std.math.maxInt(u16), 8, 1));

    var renderer = try render.Renderer.init(alloc, 2, 2);
    defer renderer.deinit();
    try checkbox.widget.draw(&renderer);

    try std.testing.expectEqual(@as(u21, ' '), renderer.back.getCell(0, 0).*.codepoint());
    try std.testing.expectEqual(@as(u21, ' '), renderer.back.getCell(1, 1).*.codepoint());
}

test "checkbox ignores presses when bounds are zero" {
    const alloc = std.testing.allocator;
    var checkbox = try Checkbox.init(alloc, "");
    defer checkbox.deinit();

    test_checkbox_calls = 0;
    test_checkbox_state = null;
    const callback = struct {
        fn call(value: bool) void {
            test_checkbox_calls += 1;
            test_checkbox_state = value;
        }
    }.call;
    checkbox.setOnChange(callback);
    checkbox.widget.rect = layout_module.Rect.init(0, 0, 0, 0);

    const click_event = input.Event{ .mouse = input.MouseEvent.init(.press, 0, 0, 1, 0) };
    try std.testing.expect(!try checkbox.widget.handleEvent(click_event));
    try std.testing.expectEqual(@as(usize, 0), test_checkbox_calls);
    try std.testing.expectEqual(@as(?bool, null), test_checkbox_state);
}
