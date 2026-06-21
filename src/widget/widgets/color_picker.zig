const std = @import("std");
const base = @import("base_widget.zig");
const layout = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const accessibility = @import("../accessibility.zig");

/// Palette-based color picker widget with keyboard and mouse selection.
pub const ColorPicker = struct {
    widget: base.Widget,
    palette: std.ArrayList(render.Color),
    columns: u16 = 4,
    swatch_width: u16 = 6,
    swatch_height: u16 = 3,
    selected_index: usize = 0,
    on_change: ?*const fn (render.Color, usize) void = null,
    on_change_with_ctx: ?*const fn (render.Color, usize, ?*anyopaque) void = null,
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
        errdefer self.deinit();
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.list), "Color picker", "");
        try self.setPalette(palette);
        return self;
    }

    pub fn deinit(self: *ColorPicker) void {
        self.palette.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    /// Replace the palette and clamp selection to a valid entry if needed.
    pub fn setPalette(self: *ColorPicker, palette: []const render.Color) !void {
        if (self.paletteEqual(palette)) {
            if (self.clampSelection()) self.widget.markDirty();
            return;
        }

        var next_palette = std.ArrayList(render.Color).empty;
        errdefer next_palette.deinit(self.allocator);

        try next_palette.appendSlice(self.allocator, palette);

        self.palette.deinit(self.allocator);
        self.palette = next_palette;
        _ = self.clampSelection();
        self.widget.markDirty();
    }

    pub fn setColumns(self: *ColorPicker, columns: u16) void {
        if (columns == 0 or self.columns == columns) return;
        self.columns = columns;
        self.widget.markDirty();
    }

    pub fn setOnChange(self: *ColorPicker, callback: *const fn (render.Color, usize) void) void {
        self.on_change = callback;
        self.on_change_with_ctx = null;
        self.on_change_ctx = null;
    }

    pub fn setOnChangeWithContext(self: *ColorPicker, callback: *const fn (render.Color, usize, ?*anyopaque) void, ctx: ?*anyopaque) void {
        self.on_change_with_ctx = callback;
        self.on_change_ctx = ctx;
        self.on_change = null;
    }

    pub fn selectIndex(self: *ColorPicker, index: usize) void {
        if (index >= self.palette.items.len) return;
        if (self.selected_index != index) {
            self.selected_index = index;
            self.widget.markDirty();
            if (self.on_change) |cb| cb(self.palette.items[index], index);
            if (self.on_change_with_ctx) |cb| cb(self.palette.items[index], index, self.on_change_ctx);
        }
    }

    fn paletteEqual(self: *const ColorPicker, palette: []const render.Color) bool {
        if (self.palette.items.len != palette.len) return false;
        for (self.palette.items, palette) |lhs, rhs| {
            if (!std.meta.eql(lhs, rhs)) return false;
        }
        return true;
    }

    fn clampSelection(self: *ColorPicker) bool {
        const previous = self.selected_index;
        if (self.palette.items.len == 0) {
            self.selected_index = 0;
        } else if (self.selected_index >= self.palette.items.len) {
            self.selected_index = self.palette.items.len - 1;
        }
        return previous != self.selected_index;
    }

    fn checkedCoord(value: u64) ?u16 {
        if (value > std.math.maxInt(u16)) return null;
        return @intCast(value);
    }

    fn checkedSize(value: u64) u16 {
        return @intCast(@min(value, @as(u64, std.math.maxInt(u16))));
    }

    fn saturatingProduct(count: usize, cell_size: u16) u16 {
        const product = std.math.mul(usize, count, @as(usize, cell_size)) catch return std.math.maxInt(u16);
        return @intCast(@min(product, @as(usize, std.math.maxInt(u16))));
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *ColorPicker = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible) return;

        const rect = self.widget.rect;
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', render.Color.named(render.NamedColor.default), render.Color.named(render.NamedColor.black), render.Style{});

        _ = self.clampSelection();
        if (self.palette.items.len == 0 or rect.width == 0 or rect.height == 0 or self.columns == 0) return;

        const cols: usize = @intCast(self.columns);
        const sw_w = if (self.swatch_width < 2) 2 else self.swatch_width;
        const sw_h = if (self.swatch_height < 2) 2 else self.swatch_height;
        const right = @as(u64, rect.x) + @as(u64, rect.width);
        const bottom = @as(u64, rect.y) + @as(u64, rect.height);

        for (self.palette.items, 0..) |color, idx| {
            const col = idx % cols;
            const row = idx / cols;

            const offset_x = std.math.mul(u64, @as(u64, @intCast(col)), @as(u64, sw_w)) catch break;
            const offset_y = std.math.mul(u64, @as(u64, @intCast(row)), @as(u64, sw_h)) catch break;
            const base_x = std.math.add(u64, @as(u64, rect.x), offset_x) catch break;
            const base_y = std.math.add(u64, @as(u64, rect.y), offset_y) catch break;

            if (base_y >= bottom) break;
            if (base_x >= right) continue;

            const draw_x = checkedCoord(base_x) orelse continue;
            const draw_y = checkedCoord(base_y) orelse continue;
            const visible_w = checkedSize(@min(@as(u64, sw_w), right - base_x));
            const visible_h = checkedSize(@min(@as(u64, sw_h), bottom - base_y));
            if (visible_w == 0 or visible_h == 0) continue;

            const inset: u16 = if (sw_w > 2 and sw_h > 2) 1 else 0;
            if (inset == 0) {
                renderer.fillRect(draw_x, draw_y, visible_w, visible_h, ' ', color, color, render.Style{});
            } else {
                if (visible_w < 2 or visible_h < 2) {
                    renderer.fillRect(draw_x, draw_y, visible_w, visible_h, ' ', color, color, render.Style{});
                } else {
                    renderer.drawBox(draw_x, draw_y, visible_w, visible_h, render.BorderStyle.single, render.Color.named(render.NamedColor.white), render.Color.named(render.NamedColor.black), render.Style{});
                }
                if (visible_w > 2 and visible_h > 2) {
                    const inner_x = checkedCoord(base_x + 1) orelse continue;
                    const inner_y = checkedCoord(base_y + 1) orelse continue;
                    renderer.fillRect(inner_x, inner_y, visible_w - 2, visible_h - 2, ' ', color, color, render.Style{});
                }
            }

            if (self.selected_index == idx) {
                const marker_base_x = base_x + @as(u64, inset);
                const marker_base_y = base_y + @as(u64, inset);
                if (marker_base_x >= right or marker_base_y >= bottom) continue;
                const marker_x = checkedCoord(marker_base_x) orelse continue;
                const marker_y = checkedCoord(marker_base_y) orelse continue;
                renderer.drawChar(marker_x, marker_y, 'X', render.Color.named(render.NamedColor.black), render.Color.named(render.NamedColor.white), render.Style{ .bold = true });
            }
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *ColorPicker = @fieldParentPtr("widget", widget_ref);
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
                const row_base = std.math.mul(usize, row, cols) catch return false;
                const idx = std.math.add(usize, row_base, col) catch return false;
                if (idx < self.palette.items.len) {
                    self.selectIndex(idx);
                    return true;
                }
            },
            .key => |key| {
                if (!self.widget.focused) return false;
                const max_index = self.palette.items.len - 1;
                _ = self.clampSelection();
                const current = @min(self.selected_index, max_index);
                const cols_step: usize = if (self.columns == 0) 1 else self.columns;

                switch (key.key) {
                    input.KeyCode.LEFT => self.selectIndex(if (current > 0) current - 1 else 0),
                    input.KeyCode.RIGHT => self.selectIndex(@min(current +| 1, max_index)),
                    input.KeyCode.UP => self.selectIndex(if (current > cols_step) current - cols_step else 0),
                    input.KeyCode.DOWN => self.selectIndex(@min(current +| cols_step, max_index)),
                    input.KeyCode.ENTER, input.KeyCode.SPACE => {
                        if (self.on_change) |cb| cb(self.palette.items[current], current);
                        if (self.on_change_with_ctx) |cb| cb(self.palette.items[current], current, self.on_change_ctx);
                        return true;
                    },
                    else => return false,
                }
                return true;
            },
            else => {},
        }

        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout.Rect) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *ColorPicker = @fieldParentPtr("widget", widget_ref);
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout.Size {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *ColorPicker = @fieldParentPtr("widget", widget_ref);
        const cols_count: usize = if (self.columns == 0) 1 else self.columns;
        const sw_w = if (self.swatch_width == 0) 1 else self.swatch_width;
        const sw_h = if (self.swatch_height == 0) 1 else self.swatch_height;
        const count = self.palette.items.len;
        const rows_count: usize = if (count == 0) 1 else (count + cols_count - 1) / cols_count;
        return layout.Size.init(saturatingProduct(cols_count, sw_w), saturatingProduct(rows_count, sw_h));
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *ColorPicker = @fieldParentPtr("widget", widget_ref);
        return self.widget.enabled and self.palette.items.len > 0;
    }
};

fn colorPickerInitAllocationFailureHarness(allocator: std.mem.Allocator) !void {
    const palette = [_]render.Color{
        render.Color.named(render.NamedColor.red),
        render.Color.named(render.NamedColor.green),
        render.Color.named(render.NamedColor.blue),
    };

    var picker = try ColorPicker.init(allocator, &palette);
    defer picker.deinit();

    try std.testing.expectEqual(@as(usize, 3), picker.palette.items.len);
}

test "color picker init cleans up every allocation failure path" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, colorPickerInitAllocationFailureHarness, .{});
}

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
    picker.setOnChangeWithContext(Callbacks.onChange, &change_called);

    const mouse_event = input.Event{ .mouse = input.MouseEvent.init(input.MouseAction.press, picker.widget.rect.x + picker.swatch_width + 1, picker.widget.rect.y + 1, 1, 0) };
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

test "color picker clamps selection when palette shrinks" {
    const allocator = std.testing.allocator;
    const palette = [_]render.Color{
        render.Color.named(render.NamedColor.red),
        render.Color.named(render.NamedColor.green),
        render.Color.named(render.NamedColor.blue),
        render.Color.named(render.NamedColor.yellow),
    };
    const shorter_palette = [_]render.Color{
        render.Color.named(render.NamedColor.magenta),
        render.Color.named(render.NamedColor.cyan),
    };

    var picker = try ColorPicker.init(allocator, &palette);
    defer picker.deinit();

    picker.selectIndex(3);
    try picker.setPalette(&shorter_palette);
    try std.testing.expectEqual(@as(usize, 1), picker.selected_index);

    try picker.setPalette(&.{});
    try std.testing.expectEqual(@as(usize, 0), picker.selected_index);
}

test "color picker preferred size saturates large products" {
    const allocator = std.testing.allocator;
    const palette = [_]render.Color{
        render.Color.named(render.NamedColor.red),
        render.Color.named(render.NamedColor.green),
    };

    var picker = try ColorPicker.init(allocator, &palette);
    defer picker.deinit();

    picker.setColumns(std.math.maxInt(u16));
    picker.swatch_width = 2;
    picker.swatch_height = std.math.maxInt(u16);

    const pref = try picker.widget.getPreferredSize();
    try std.testing.expectEqual(std.math.maxInt(u16), pref.width);
    try std.testing.expectEqual(std.math.maxInt(u16), pref.height);
}

test "color picker draw clips edge coordinates before u16 overflow" {
    const allocator = std.testing.allocator;
    const palette = [_]render.Color{
        render.Color.named(render.NamedColor.red),
        render.Color.named(render.NamedColor.green),
    };

    var picker = try ColorPicker.init(allocator, &palette);
    defer picker.deinit();

    picker.setColumns(1);
    picker.swatch_width = 2;
    picker.swatch_height = 2;
    try picker.widget.layout(layout.Rect.init(std.math.maxInt(u16) - 1, 0, 2, 2));

    var renderer = try render.Renderer.init(allocator, 4, 2);
    defer renderer.deinit();
    try picker.widget.draw(&renderer);
}

test "color picker renders clipped partial swatches" {
    const allocator = std.testing.allocator;
    const palette = [_]render.Color{
        render.Color.named(render.NamedColor.red),
    };

    var picker = try ColorPicker.init(allocator, &palette);
    defer picker.deinit();

    picker.swatch_width = 2;
    picker.swatch_height = 2;
    try picker.widget.layout(layout.Rect.init(0, 0, 1, 1));

    var renderer = try render.Renderer.init(allocator, 1, 1);
    defer renderer.deinit();
    try picker.widget.draw(&renderer);

    const cell = renderer.back.getCell(0, 0).*;
    try std.testing.expect(std.meta.eql(cell.bg, render.Color.named(render.NamedColor.white)));
    try std.testing.expectEqual(@as(u21, 'X'), cell.codepoint());

    picker.selected_index = 1;
    picker.swatch_width = 6;
    picker.swatch_height = 3;
    renderer.back.clear();
    picker.widget.markDirty();
    try picker.widget.draw(&renderer);

    const clipped_cell = renderer.back.getCell(0, 0).*;
    try std.testing.expect(std.meta.eql(clipped_cell.bg, render.Color.named(render.NamedColor.red)));
}

test "color picker clamps stale selection during draw" {
    const allocator = std.testing.allocator;
    const palette = [_]render.Color{
        render.Color.named(render.NamedColor.red),
        render.Color.named(render.NamedColor.green),
    };

    var picker = try ColorPicker.init(allocator, &palette);
    defer picker.deinit();

    picker.setColumns(2);
    picker.swatch_width = 2;
    picker.swatch_height = 2;
    picker.selected_index = std.math.maxInt(usize);
    try picker.widget.layout(layout.Rect.init(0, 0, 4, 2));

    var renderer = try render.Renderer.init(allocator, 4, 2);
    defer renderer.deinit();
    try picker.widget.draw(&renderer);

    try std.testing.expectEqual(@as(usize, 1), picker.selected_index);
    const marker_cell = renderer.back.getCell(2, 0).*;
    try std.testing.expectEqual(@as(u21, 'X'), marker_cell.codepoint());
}

test "color picker clamps invalid selected index during keyboard handling" {
    const allocator = std.testing.allocator;
    const palette = [_]render.Color{
        render.Color.named(render.NamedColor.red),
        render.Color.named(render.NamedColor.green),
    };

    var picker = try ColorPicker.init(allocator, &palette);
    defer picker.deinit();

    var change_index: usize = std.math.maxInt(usize);
    const Callbacks = struct {
        fn onChange(_: render.Color, index: usize, ctx: ?*anyopaque) void {
            if (ctx) |ptr| {
                const out = @as(*usize, @ptrCast(@alignCast(ptr)));
                out.* = index;
            }
        }
    };

    picker.widget.setFocus(true);
    picker.selected_index = std.math.maxInt(usize);
    picker.setOnChangeWithContext(Callbacks.onChange, &change_index);

    const enter_event = input.Event{ .key = input.KeyEvent.init(input.KeyCode.ENTER, .{}) };
    try std.testing.expect(try picker.widget.handleEvent(enter_event));
    try std.testing.expectEqual(@as(usize, 1), picker.selected_index);
    try std.testing.expectEqual(@as(usize, 1), change_index);

    const right_event = input.Event{ .key = input.KeyEvent.init(input.KeyCode.RIGHT, .{}) };
    try std.testing.expect(try picker.widget.handleEvent(right_event));
    try std.testing.expectEqual(@as(usize, 1), picker.selected_index);
}

test "color picker setPalette preserves palette on allocation failure" {
    const alloc = std.testing.allocator;
    const original_palette = [_]render.Color{
        render.Color.named(render.NamedColor.red),
        render.Color.named(render.NamedColor.green),
    };
    const replacement_palette = [_]render.Color{
        render.Color.named(render.NamedColor.blue),
        render.Color.named(render.NamedColor.yellow),
        render.Color.named(render.NamedColor.magenta),
    };

    var picker = try ColorPicker.init(alloc, &original_palette);
    defer picker.deinit();
    picker.selectIndex(1);

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = picker.allocator;
    picker.allocator = failing.allocator();
    defer picker.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, picker.setPalette(&replacement_palette));
    try std.testing.expectEqual(@as(usize, 2), picker.palette.items.len);
    try std.testing.expectEqual(render.NamedColor.red, picker.palette.items[0].named_color);
    try std.testing.expectEqual(render.NamedColor.green, picker.palette.items[1].named_color);
    try std.testing.expectEqual(@as(usize, 1), picker.selected_index);
}

test "color picker marks dirty when visible state changes" {
    const alloc = std.testing.allocator;
    const palette = [_]render.Color{
        render.Color.named(render.NamedColor.red),
        render.Color.named(render.NamedColor.green),
        render.Color.named(render.NamedColor.blue),
    };
    const replacement_palette = [_]render.Color{
        render.Color.named(render.NamedColor.yellow),
        render.Color.named(render.NamedColor.magenta),
    };

    var picker = try ColorPicker.init(alloc, &palette);
    defer picker.deinit();

    try picker.widget.layout(layout.Rect.init(0, 0, 18, 6));
    var renderer = try render.Renderer.init(alloc, 18, 6);
    defer renderer.deinit();

    try picker.widget.draw(&renderer);
    try std.testing.expect(!picker.widget.dirty);

    picker.setColumns(2);
    try std.testing.expect(picker.widget.dirty);
    try picker.widget.draw(&renderer);
    try std.testing.expect(!picker.widget.dirty);
    picker.setColumns(2);
    try std.testing.expect(!picker.widget.dirty);
    picker.setColumns(0);
    try std.testing.expect(!picker.widget.dirty);

    picker.selectIndex(1);
    try std.testing.expect(picker.widget.dirty);
    try picker.widget.draw(&renderer);
    try std.testing.expect(!picker.widget.dirty);
    picker.selectIndex(1);
    try std.testing.expect(!picker.widget.dirty);
    picker.selectIndex(42);
    try std.testing.expect(!picker.widget.dirty);

    try picker.setPalette(&palette);
    try std.testing.expect(!picker.widget.dirty);

    picker.selected_index = std.math.maxInt(usize);
    try picker.setPalette(&palette);
    try std.testing.expectEqual(@as(usize, 2), picker.selected_index);
    try std.testing.expect(picker.widget.dirty);
    try picker.widget.draw(&renderer);
    try std.testing.expect(!picker.widget.dirty);

    try picker.setPalette(&replacement_palette);
    try std.testing.expectEqual(@as(usize, 1), picker.selected_index);
    try std.testing.expect(picker.widget.dirty);
}
