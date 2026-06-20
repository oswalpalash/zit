const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const accessibility = @import("../accessibility.zig");

const CanvasCell = struct {
    char: u21,
    fg: render.Color,
    bg: render.Color,
    style: render.Style,
};

/// Immediate mode drawing surface for custom widgets or data visualizations.
pub const Canvas = struct {
    widget: base.Widget,
    width: u16,
    height: u16,
    cells: std.ArrayList(CanvasCell),
    default_fg: render.Color = render.Color.named(render.NamedColor.default),
    default_bg: render.Color = render.Color.named(render.NamedColor.black),
    default_style: render.Style = render.Style{},
    allocator: std.mem.Allocator,

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator, width: u16, height: u16) !*Canvas {
        const self = try allocator.create(Canvas);
        self.* = Canvas{
            .widget = base.Widget.init(&vtable),
            .width = if (width == 0) 1 else width,
            .height = if (height == 0) 1 else height,
            .cells = std.ArrayList(CanvasCell).empty,
            .allocator = allocator,
        };
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.canvas), "Canvas", "");
        errdefer self.deinit();

        try self.resizeInternal(self.width, self.height);
        return self;
    }

    pub fn deinit(self: *Canvas) void {
        self.cells.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    /// Change the backing surface size. Content is cleared on resize.
    pub fn resize(self: *Canvas, width: u16, height: u16) !void {
        const new_w = if (width == 0) 1 else width;
        const new_h = if (height == 0) 1 else height;
        try self.resizeInternal(new_w, new_h);
    }

    /// Clear the canvas with the default style.
    pub fn clear(self: *Canvas) void {
        const cell = CanvasCell{ .char = ' ', .fg = self.default_fg, .bg = self.default_bg, .style = self.default_style };
        for (self.cells.items) |*c| {
            c.* = cell;
        }
    }

    /// Plot a single point if it is inside the canvas bounds.
    pub fn drawPoint(self: *Canvas, x: u16, y: u16, char: u21, fg: render.Color, bg: render.Color, style: render.Style) void {
        if (x >= self.width or y >= self.height) return;
        const idx = @as(usize, y) * @as(usize, self.width) + @as(usize, x);
        self.cells.items[idx] = CanvasCell{ .char = char, .fg = fg, .bg = bg, .style = style };
    }

    fn addOffsetClamped(origin: u16, offset: u16) u16 {
        const value = @as(u32, origin) + @as(u32, offset);
        return clampCoord(value);
    }

    fn clampCoord(value: u32) u16 {
        return @intCast(@min(value, @as(u32, std.math.maxInt(u16))));
    }

    /// Draw a line using a simplified Bresenham algorithm.
    pub fn drawLine(self: *Canvas, x0: i32, y0: i32, x1: i32, y1: i32, char: u21, fg: render.Color, bg: render.Color, style: render.Style) void {
        const dx = if (x1 > x0) x1 - x0 else x0 - x1;
        const sx: i32 = if (x0 < x1) 1 else -1;
        const dy = -if (y1 > y0) y1 - y0 else y0 - y1;
        const sy: i32 = if (y0 < y1) 1 else -1;
        var err = dx + dy;

        var cx = x0;
        var cy = y0;
        while (true) {
            if (cx >= 0 and cy >= 0) {
                self.drawPoint(@intCast(cx), @intCast(cy), char, fg, bg, style);
            }

            if (cx == x1 and cy == y1) break;
            const e2 = 2 * err;
            if (e2 >= dy) {
                err += dy;
                cx += sx;
            }
            if (e2 <= dx) {
                err += dx;
                cy += sy;
            }
        }
    }

    /// Draw a rectangle outline.
    pub fn drawRect(self: *Canvas, x: u16, y: u16, width: u16, height: u16, char: u21, fg: render.Color, bg: render.Color, style: render.Style) void {
        if (width == 0 or height == 0) return;
        const max_x_u32 = @as(u32, x) + @as(u32, width) - 1;
        const max_y_u32 = @as(u32, y) + @as(u32, height) - 1;
        const max_x = clampCoord(max_x_u32);
        const max_y = clampCoord(max_y_u32);

        self.drawLine(@intCast(x), @intCast(y), @intCast(max_x), @intCast(y), char, fg, bg, style);
        self.drawLine(@intCast(x), @intCast(max_y), @intCast(max_x), @intCast(max_y), char, fg, bg, style);
        if (height > 2) {
            const inner_top = addOffsetClamped(y, 1);
            const inner_bottom = clampCoord(max_y_u32 - 1);
            self.drawLine(@intCast(x), @intCast(inner_top), @intCast(x), @intCast(inner_bottom), char, fg, bg, style);
            self.drawLine(@intCast(max_x), @intCast(inner_top), @intCast(max_x), @intCast(inner_bottom), char, fg, bg, style);
        }
    }

    /// Fill a rectangular area.
    pub fn fillRect(self: *Canvas, x: u16, y: u16, width: u16, height: u16, char: u21, fg: render.Color, bg: render.Color, style: render.Style) void {
        var cy: u16 = 0;
        while (cy < height) : (cy += 1) {
            var cx: u16 = 0;
            while (cx < width) : (cx += 1) {
                self.drawPoint(addOffsetClamped(x, cx), addOffsetClamped(y, cy), char, fg, bg, style);
            }
        }
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Canvas = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible) return;

        const rect = self.widget.rect;
        const width = @min(rect.width, self.width);
        const height = @min(rect.height, self.height);

        for (0..height) |y| {
            for (0..width) |x| {
                const idx = y * @as(usize, self.width) + x;
                const cell = self.cells.items[idx];
                renderer.drawChar(addOffsetClamped(rect.x, @intCast(x)), addOffsetClamped(rect.y, @intCast(y)), cell.char, cell.fg, cell.bg, cell.style);
            }
        }
    }

    fn handleEventFn(_: *anyopaque, _: input.Event) anyerror!bool {
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Canvas = @fieldParentPtr("widget", widget_ref);
        if (rect.width != self.width or rect.height != self.height) {
            try self.resize(rect.width, rect.height);
        }
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Canvas = @fieldParentPtr("widget", widget_ref);
        return layout_module.Size.init(self.width, self.height);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Canvas = @fieldParentPtr("widget", widget_ref);
        return self.widget.visible and self.widget.enabled;
    }

    fn resizeInternal(self: *Canvas, width: u16, height: u16) !void {
        const total = @as(usize, width) * @as(usize, height);
        try self.cells.resize(self.allocator, total);
        self.width = width;
        self.height = height;
        self.clear();
    }
};

test "canvas draws primitives" {
    const alloc = std.testing.allocator;
    var canvas = try Canvas.init(alloc, 8, 4);
    defer canvas.deinit();

    canvas.drawLine(0, 0, 7, 0, '#', render.Color.named(render.NamedColor.green), render.Color.named(render.NamedColor.black), render.Style{});
    canvas.drawRect(1, 1, 3, 2, '*', render.Color.named(render.NamedColor.blue), render.Color.named(render.NamedColor.black), render.Style{});

    try canvas.widget.layout(layout_module.Rect.init(0, 0, 8, 4));

    var renderer = try render.Renderer.init(alloc, 8, 4);
    defer renderer.deinit();

    try canvas.widget.draw(&renderer);

    const first_cell = renderer.back.getCell(0, 0).*;
    try std.testing.expectEqual(@as(u21, '#'), first_cell.codepoint());

    const rect_cell = renderer.back.getCell(2, 2).*;
    try std.testing.expectEqual(@as(u21, '*'), rect_cell.codepoint());
}

test "canvas clamps edge draw coordinates" {
    const alloc = std.testing.allocator;
    var canvas = try Canvas.init(alloc, 2, 2);
    defer canvas.deinit();

    canvas.fillRect(0, 0, 2, 2, '#', render.Color.named(render.NamedColor.green), render.Color.named(render.NamedColor.black), render.Style{});
    try canvas.widget.layout(layout_module.Rect.init(std.math.maxInt(u16) - 1, std.math.maxInt(u16), 2, 2));

    var renderer = try render.Renderer.init(alloc, 2, 2);
    defer renderer.deinit();

    try canvas.widget.draw(&renderer);

    try std.testing.expectEqual(@as(u21, ' '), renderer.back.getCell(0, 0).codepoint());
    try std.testing.expectEqual(@as(u21, ' '), renderer.back.getCell(1, 1).codepoint());
}

test "canvas primitives clamp edge-local coordinates" {
    const alloc = std.testing.allocator;
    var canvas = try Canvas.init(alloc, 2, 2);
    defer canvas.deinit();

    const fg = render.Color.named(render.NamedColor.green);
    const bg = render.Color.named(render.NamedColor.black);
    canvas.drawRect(std.math.maxInt(u16) - 1, std.math.maxInt(u16) - 1, 4, 4, '#', fg, bg, render.Style{});
    canvas.fillRect(std.math.maxInt(u16) - 1, std.math.maxInt(u16) - 1, 4, 4, '*', fg, bg, render.Style{});

    for (canvas.cells.items) |cell| {
        try std.testing.expectEqual(@as(u21, ' '), cell.char);
    }
}

fn canvasInitAllocationFailureHarness(allocator: std.mem.Allocator) !void {
    var canvas = try Canvas.init(allocator, 8, 4);
    defer canvas.deinit();

    try std.testing.expectEqual(@as(u16, 8), canvas.width);
    try std.testing.expectEqual(@as(u16, 4), canvas.height);
    try std.testing.expectEqual(@as(usize, 32), canvas.cells.items.len);
}

test "canvas init cleans up every allocation failure path" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, canvasInitAllocationFailureHarness, .{});
}
