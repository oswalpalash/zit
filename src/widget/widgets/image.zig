const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");

/// Widget that renders a simple color buffer (useful for icons, previews, and charts).
pub const ImageWidget = struct {
    widget: base.Widget,
    allocator: std.mem.Allocator,
    width: u16,
    height: u16,
    pixels: []render.Color,

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator, width: u16, height: u16) !*ImageWidget {
        const count = try std.math.mul(usize, width, height);
        const pixels = try allocator.alloc(render.Color, count);
        for (pixels) |*p| p.* = render.Color.named(render.NamedColor.default);

        const self = try allocator.create(ImageWidget);
        self.* = ImageWidget{
            .widget = base.Widget.init(&vtable),
            .allocator = allocator,
            .width = width,
            .height = height,
            .pixels = pixels,
        };
        return self;
    }

    pub fn fromData(allocator: std.mem.Allocator, width: u16, height: u16, data: []const render.Color) !*ImageWidget {
        const self = try init(allocator, width, height);
        try self.setData(data);
        return self;
    }

    pub fn deinit(self: *ImageWidget) void {
        self.allocator.free(self.pixels);
        self.allocator.destroy(self);
    }

    pub fn setPixel(self: *ImageWidget, x: u16, y: u16, color: render.Color) void {
        if (x >= self.width or y >= self.height) return;
        const idx = @as(usize, y) * @as(usize, self.width) + @as(usize, x);
        self.pixels[idx] = color;
    }

    pub fn fill(self: *ImageWidget, color: render.Color) void {
        for (self.pixels) |*p| p.* = color;
    }

    pub fn setData(self: *ImageWidget, data: []const render.Color) !void {
        const expected = try std.math.mul(usize, self.width, self.height);
        if (data.len != expected) return error.InvalidPixelCount;
        @memcpy(self.pixels, data);
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*ImageWidget, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;
        if (self.width == 0 or self.height == 0) return;

        const rect = self.widget.rect;
        if (rect.width == 0 or rect.height == 0) return;

        const target_w = rect.width;
        const target_h = rect.height;

        var row: u16 = 0;
        while (row < target_h) : (row += 1) {
            const src_y: u16 = @intCast(@divFloor(@as(u32, row) * self.height, target_h));
            var col: u16 = 0;
            while (col < target_w) : (col += 1) {
                const src_x: u16 = @intCast(@divFloor(@as(u32, col) * self.width, target_w));
                const idx = @as(usize, src_y) * @as(usize, self.width) + @as(usize, src_x);
                const color = self.pixels[idx];
                renderer.drawChar(rect.x + col, rect.y + row, ' ', render.Color.named(render.NamedColor.default), color, render.Style{});
            }
        }
    }

    fn handleEventFn(_: *anyopaque, _: input.Event) anyerror!bool {
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*ImageWidget, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*ImageWidget, @ptrCast(@alignCast(widget_ptr)));
        return layout_module.Size.init(self.width, self.height);
    }

    fn canFocusFn(_: *anyopaque) bool {
        return false;
    }
};

test "image widget renders scaled pixels" {
    const alloc = std.testing.allocator;
    const pixels = [_]render.Color{
        render.Color.named(render.NamedColor.red),
        render.Color.named(render.NamedColor.blue),
        render.Color.named(render.NamedColor.green),
        render.Color.named(render.NamedColor.white),
    };

    var image = try ImageWidget.fromData(alloc, 2, 2, &pixels);
    defer image.deinit();

    try image.widget.layout(layout_module.Rect.init(0, 0, 2, 2));

    var renderer = try render.Renderer.init(alloc, 2, 2);
    defer renderer.deinit();

    try image.widget.draw(&renderer);

    try std.testing.expect(std.meta.eql(renderer.back.getCell(0, 0).bg, render.Color.named(render.NamedColor.red)));
    try std.testing.expect(std.meta.eql(renderer.back.getCell(1, 0).bg, render.Color.named(render.NamedColor.blue)));
    try std.testing.expect(std.meta.eql(renderer.back.getCell(0, 1).bg, render.Color.named(render.NamedColor.green)));
    try std.testing.expect(std.meta.eql(renderer.back.getCell(1, 1).bg, render.Color.named(render.NamedColor.white)));
}
