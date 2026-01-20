const std = @import("std");
const base = @import("base_widget.zig");
const layout = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");

/// Palette-based color picker widget with keyboard and mouse selection.
pub const ColorPicker = struct {
    widget: base.Widget,
    palette: std.ArrayList(render.Color),
    columns: u16 = 4,
    swatch_width: u16 = 6,
    swatch_height: u16 = 3,
    selected_index: usize = 0,
    on_change: ?*const fn (render.Color, usize, ?*anyopaque) void = null,
    on_change_ctx: ?*anyopaque = null,
    allocator: std.mem.Allocator,

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator, palette: []const render.Color) !*ColorPicker {
        const self = try allocator.create(ColorPicker);
        self.* = ColorPicker{
            .widget = base.Widget.init(&vtable),
            .palette = std.ArrayList(render.Color).empty,
            .allocator = allocator,
        };
        try self.setPalette(palette);
        return self;
    }

    pub fn deinit(self: *ColorPicker) void {
        self.palette.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    /// Replace the palette. Resets selection to the first entry if available.
    pub fn setPalette(self: *ColorPicker, palette: []const render.Color) !void {
        self.palette.clearRetainingCapacity();
        try self.palette.appendSlice(self.allocator, palette);
        if (self.selected_index >= self.palette.items.len) {
            self.selected_index = if (self.palette.items.len > 0) 0 else 0;
        }
    }

    pub fn setColumns(self: *ColorPicker, columns: u16) void {
        if (columns > 0) self.columns = columns;
    }

    pub fn setOnChange(self: *ColorPicker, callback: *const fn (render.Color, usize, ?*anyopaque) void, ctx: ?*anyopaque) void {
        self.on_change = callback;
        self.on_change_ctx = ctx;
    }

    pub fn selectIndex(self: *ColorPicker, index: usize) void {
        if (index >= self.palette.items.len) return;
        if (self.selected_index != index) {
            self.selected_index = index;
            if (self.on_change) |cb| cb(self.palette.items[index], index, self.on_change_ctx);
        }
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*ColorPicker, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;

        const rect = self.widget.rect;
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', render.Color.named(render.NamedColor.default), render.Color.named(render.NamedColor.black), render.Style{});

        if (self.palette.items.len == 0 or rect.width == 0 or rect.height == 0 or self.columns == 0) return;

        const cols = self.columns;
        const sw_w = if (self.swatch_width < 2) 2 else self.swatch_width;
        const sw_h = if (self.swatch_height < 2) 2 else self.swatch_height;

        for (self.palette.items, 0..) |color, idx| {
            const col: u16 = @intCast(idx % cols);
            const row: u16 = @intCast(idx / cols);

            const base_x = rect.x + col * sw_w;
            const base_y = rect.y + row * sw_h;

            if (base_x >= rect.x + rect.width or base_y >= rect.y + rect.height) continue;
            if (base_x + sw_w > rect.x + rect.width or base_y + sw_h > rect.y + rect.height) continue;

            const inset = if (sw_w > 2 and sw_h > 2) 1 else 0;
            if (inset == 0) {
                renderer.fillRect(base_x, base_y, sw_w, sw_h, ' ', color, color, render.Style{});
            } else {
                renderer.drawBox(base_x, base_y, sw_w, sw_h, render.BorderStyle.single, render.Color.named(render.NamedColor.white), render.Color.named(render.NamedColor.black), render.Style{});
                renderer.fillRect(base_x + 1, base_y + 1, sw_w - 2, sw_h - 2, ' ', color, color, render.Style{});
            }

            if (self.selected_index == idx) {
                const marker_x = base_x + inset;
                const marker_y = base_y + inset;
                renderer.drawChar(marker_x, marker_y, 'X', render.Color.named(render.NamedColor.black), render.Color.named(render.NamedColor.white), render.Style{ .bold = true });
            }
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*ColorPicker, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible or !self.widget.enabled) return false;
        if (self.palette.items.len == 0) return false;

        switch (event) {
            .mouse => |mouse| {
                if (mouse.action != .press or mouse.button != 1) return false;
                if (!self.widget.rect.contains(mouse.x, mouse.y)) return false;

                const cols: usize = @intCast(if (self.columns == 0) 1 else self.columns);
                const sw_w = if (self.swatch_width == 0) 1 else self.swatch_width;
                const sw_h = if (self.swatch_height == 0) 1 else self.swatch_height;
                const col: usize = @intCast(@divFloor(mouse.x - self.widget.rect.x, sw_w));
                const row: usize = @intCast(@divFloor(mouse.y - self.widget.rect.y, sw_h));
                const idx = row * cols + col;
                if (idx < self.palette.items.len) {
                    self.selectIndex(idx);
                    return true;
                }
            },
            .key => |key| {
                if (!self.widget.focused) return false;
                const cols_step: isize = @intCast(if (self.columns == 0) 1 else self.columns);
                var idx: isize = @intCast(self.selected_index);

                switch (key.key) {
                    input.KeyCode.LEFT => idx -= 1,
                    input.KeyCode.RIGHT => idx += 1,
                    input.KeyCode.UP => idx -= cols_step,
                    input.KeyCode.DOWN => idx += cols_step,
                    input.KeyCode.ENTER, input.KeyCode.SPACE => {
                        if (self.on_change) |cb| cb(self.palette.items[self.selected_index], self.selected_index, self.on_change_ctx);
                        return true;
                    },
                    else => return false,
                }

                if (idx < 0) idx = 0;
                const max_index: isize = @intCast(self.palette.items.len - 1);
                if (idx > max_index) idx = max_index;
                self.selectIndex(@intCast(idx));
                return true;
            },
            else => {},
        }

        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout.Rect) anyerror!void {
        const self = @as(*ColorPicker, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout.Size {
        const self = @as(*ColorPicker, @ptrCast(@alignCast(widget_ptr)));
        const cols_count: usize = if (self.columns == 0) 1 else self.columns;
        const sw_w = if (self.swatch_width == 0) 1 else self.swatch_width;
        const sw_h = if (self.swatch_height == 0) 1 else self.swatch_height;
        const count = self.palette.items.len;
        const rows_count: usize = if (count == 0) 1 else (count + cols_count - 1) / cols_count;
        return layout.Size.init(@as(u16, @intCast(cols_count)) * sw_w, @as(u16, @intCast(rows_count)) * sw_h);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*ColorPicker, @ptrCast(@alignCast(widget_ptr)));
        return self.widget.enabled and self.palette.items.len > 0;
    }
};

test "color picker handles mouse and keyboard selection" {
    const allocator = std.testing.allocator;
    var palette = [_]render.Color{
        render.Color.named(render.NamedColor.red),
        render.Color.named(render.NamedColor.green),
        render.Color.named(render.NamedColor.blue),
        render.Color.named(render.NamedColor.yellow),
    };

    var picker = try ColorPicker.init(allocator, &palette);
    defer picker.deinit();
    picker.setColumns(2);

    const pref = try picker.widget.getPreferredSize();
    try std.testing.expectEqual(@as(u16, 12), pref.width);
    try std.testing.expectEqual(@as(u16, 6), pref.height);

    try picker.widget.layout(layout.Rect.init(0, 0, pref.width, pref.height));

    var change_called = false;
    const Callbacks = struct {
        fn onChange(_: render.Color, _: usize, ctx: ?*anyopaque) void {
            if (ctx) |ptr| {
                const flag = @as(*bool, @ptrCast(@alignCast(ptr)));
                flag.* = true;
            }
        }
    };
    picker.setOnChange(Callbacks.onChange, &change_called);

    const mouse_event = input.Event{ .mouse = input.MouseEvent.init(input.MouseAction.press, picker.widget.rect.x + picker.swatch_width + 1, picker.widget.rect.y + 1, 1) };
    try std.testing.expect(try picker.widget.handleEvent(mouse_event));
    try std.testing.expectEqual(@as(usize, 1), picker.selected_index);
    try std.testing.expect(change_called);

    change_called = false;
    picker.widget.setFocus(true);
    const down_event = input.Event{ .key = input.KeyEvent.init(input.KeyCode.DOWN, .{}) };
    try std.testing.expect(try picker.widget.handleEvent(down_event));
    try std.testing.expectEqual(@as(usize, 3), picker.selected_index);
    try std.testing.expect(change_called);
}
