const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");

/// Widget that renders a simple color buffer (useful for icons, previews, and charts).
pub const RenderMode = enum {
    /// Fill the cell background using the source pixel color (default).
    background,
    /// Combine two vertical pixels into one cell using block characters.
    block,
    /// Pack a 2x4 pixel block into a single braille character for higher detail.
    braille,
};

pub const ImageWidget = struct {
    widget: base.Widget,
    allocator: std.mem.Allocator,
    width: u16,
    height: u16,
    pixels: []render.Color,
    mode: RenderMode = .background,

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

    pub fn setRenderMode(self: *ImageWidget, mode: RenderMode) void {
        self.mode = mode;
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

        switch (self.mode) {
            .background => drawBackground(self, renderer, rect),
            .block => drawBlock(self, renderer, rect),
            .braille => drawBraille(self, renderer, rect),
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

    fn drawBackground(self: *ImageWidget, renderer: *render.Renderer, rect: layout_module.Rect) void {
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

    fn drawBlock(self: *ImageWidget, renderer: *render.Renderer, rect: layout_module.Rect) void {
        if (rect.height == 0 or rect.width == 0) return;

        var row: u16 = 0;
        while (row < rect.height) : (row += 1) {
            const top_src_y: u16 = @intCast(@divFloor(@as(u32, row) * 2 * self.height, rect.height * 2));
            const bottom_src_y: u16 = @intCast(@divFloor(@as(u32, row) * 2 * self.height + 1, rect.height * 2));
            var col: u16 = 0;
            while (col < rect.width) : (col += 1) {
                const src_x: u16 = @intCast(@divFloor(@as(u32, col) * self.width, rect.width));
                const top_color = self.pixels[@as(usize, top_src_y) * @as(usize, self.width) + @as(usize, src_x)];
                const bottom_color = self.pixels[@as(usize, bottom_src_y) * @as(usize, self.width) + @as(usize, src_x)];
                const glyph: u21 = if (colorsEqual(top_color, bottom_color)) '█' else '▀';
                renderer.drawChar(rect.x + col, rect.y + row, glyph, top_color, bottom_color, render.Style{});
            }
        }
    }

    fn drawBraille(self: *ImageWidget, renderer: *render.Renderer, rect: layout_module.Rect) void {
        if (rect.height == 0 or rect.width == 0) return;

        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', render.Color.named(render.NamedColor.default), render.Color.named(render.NamedColor.default), render.Style{});

        const virtual_w: u32 = @as(u32, rect.width) * 2;
        const virtual_h: u32 = @as(u32, rect.height) * 4;

        var cell_y: u16 = 0;
        while (cell_y < rect.height) : (cell_y += 1) {
            var cell_x: u16 = 0;
            while (cell_x < rect.width) : (cell_x += 1) {
                var pattern: u8 = 0;
                var accum = AccumColor{};

                var dot_y: u16 = 0;
                while (dot_y < 4) : (dot_y += 1) {
                    var dot_x: u16 = 0;
                    while (dot_x < 2) : (dot_x += 1) {
                        const virtual_x = @as(u32, cell_x) * 2 + dot_x;
                        const virtual_y = @as(u32, cell_y) * 4 + dot_y;

                        const src_x: u16 = @intCast(@divFloor(virtual_x * @as(u32, self.width), virtual_w));
                        const src_y: u16 = @intCast(@divFloor(virtual_y * @as(u32, self.height), virtual_h));
                        const src_idx = @as(usize, src_y) * @as(usize, self.width) + @as(usize, src_x);
                        const c = self.pixels[src_idx];

                        accum.add(c);

                        if (luminance(c) > 0.35) {
                            pattern |= brailleBit(dot_x, dot_y);
                        }
                    }
                }

                if (pattern == 0) continue;

                const avg = accum.average();
                const glyph: u21 = 0x2800 + @as(u21, pattern);
                renderer.drawChar(rect.x + cell_x, rect.y + cell_y, glyph, avg, render.Color.named(render.NamedColor.default), render.Style{});
            }
        }
    }

    fn brailleBit(x: u16, y: u16) u8 {
        // Dot positions: (0,0)=1, (0,1)=2, (0,2)=3, (0,3)=7, (1,0)=4, (1,1)=5, (1,2)=6, (1,3)=8
        return switch (y) {
            0 => if (x == 0) 0x01 else 0x08,
            1 => if (x == 0) 0x02 else 0x10,
            2 => if (x == 0) 0x04 else 0x20,
            else => if (x == 0) 0x40 else 0x80,
        };
    }

    fn luminance(c: render.Color) f32 {
        const rgb = toRgb(c);
        const r: f32 = @floatFromInt(rgb[0]);
        const g: f32 = @floatFromInt(rgb[1]);
        const b: f32 = @floatFromInt(rgb[2]);
        return (0.2126 * (r / 255.0)) + (0.7152 * (g / 255.0)) + (0.0722 * (b / 255.0));
    }

    fn colorsEqual(a: render.Color, b: render.Color) bool {
        return std.meta.eql(a, b);
    }

    fn toRgb(color: render.Color) [3]u8 {
        return switch (color) {
            .rgb_color => |rgb| .{ rgb.r, rgb.g, rgb.b },
            .ansi_256 => |idx| blk: {
                const rgb = render.colorToRgb(render.Color.ansi256(idx));
                break :blk .{ rgb.r, rgb.g, rgb.b };
            },
            .named_color => |named| switch (named) {
                .black => .{ 0, 0, 0 },
                .red => .{ 205, 49, 49 },
                .green => .{ 13, 188, 121 },
                .yellow => .{ 229, 229, 16 },
                .blue => .{ 36, 114, 200 },
                .magenta => .{ 188, 63, 188 },
                .cyan => .{ 17, 168, 205 },
                .white => .{ 229, 229, 229 },
                .default => .{ 127, 127, 127 },
                .bright_black => .{ 102, 102, 102 },
                .bright_red => .{ 241, 76, 76 },
                .bright_green => .{ 35, 209, 139 },
                .bright_yellow => .{ 245, 245, 67 },
                .bright_blue => .{ 59, 142, 234 },
                .bright_magenta => .{ 214, 112, 214 },
                .bright_cyan => .{ 41, 184, 219 },
                .bright_white => .{ 255, 255, 255 },
            },
        };
    }

    const AccumColor = struct {
        r: u32 = 0,
        g: u32 = 0,
        b: u32 = 0,
        count: u32 = 0,

        fn add(self: *AccumColor, color: render.Color) void {
            const rgb = toRgb(color);
            self.r += rgb[0];
            self.g += rgb[1];
            self.b += rgb[2];
            self.count += 1;
        }

        fn average(self: *AccumColor) render.Color {
            if (self.count == 0) return render.Color.named(render.NamedColor.default);
            const r: u8 = @intCast(self.r / self.count);
            const g: u8 = @intCast(self.g / self.count);
            const b: u8 = @intCast(self.b / self.count);
            return render.Color.rgb(r, g, b);
        }
    };
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

test "image widget block rendering combines two rows" {
    const alloc = std.testing.allocator;
    const pixels = [_]render.Color{
        render.Color.named(render.NamedColor.red),
        render.Color.named(render.NamedColor.red),
        render.Color.named(render.NamedColor.blue),
        render.Color.named(render.NamedColor.blue),
    };

    var image = try ImageWidget.fromData(alloc, 2, 2, &pixels);
    defer image.deinit();
    image.setRenderMode(.block);

    try image.widget.layout(layout_module.Rect.init(0, 0, 2, 1));

    var renderer = try render.Renderer.init(alloc, 2, 1);
    defer renderer.deinit();

    try image.widget.draw(&renderer);

    const cell = renderer.back.getCell(0, 0).*;
    try std.testing.expectEqual(@as(u21, '█'), cell.char);
}

test "image widget braille rendering emits dot patterns" {
    const alloc = std.testing.allocator;
    const pixels = [_]render.Color{
        render.Color.named(render.NamedColor.white),
        render.Color.named(render.NamedColor.white),
        render.Color.named(render.NamedColor.white),
        render.Color.named(render.NamedColor.white),
    };

    var image = try ImageWidget.fromData(alloc, 2, 2, &pixels);
    defer image.deinit();
    image.setRenderMode(.braille);

    try image.widget.layout(layout_module.Rect.init(0, 0, 1, 1));

    var renderer = try render.Renderer.init(alloc, 1, 1);
    defer renderer.deinit();

    try image.widget.draw(&renderer);

    const cell = renderer.back.getCell(0, 0).*;
    try std.testing.expect(cell.char != ' ');
}
