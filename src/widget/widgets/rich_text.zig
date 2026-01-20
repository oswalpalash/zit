const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");

/// Rich text viewer that renders styled spans (color, bold, italic).
pub const RichText = struct {
    widget: base.Widget,
    allocator: std.mem.Allocator,
    spans: std.ArrayList(Span),
    border: render.BorderStyle = .none,
    background: render.Color = render.Color{ .named_color = render.NamedColor.default },
    wrap: bool = true,

    pub const Span = struct {
        text: []u8,
        fg: render.Color = render.Color{ .named_color = render.NamedColor.default },
        bg: render.Color = render.Color{ .named_color = render.NamedColor.default },
        style: render.Style = render.Style{},
    };

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator) !*RichText {
        const self = try allocator.create(RichText);
        self.* = RichText{
            .widget = base.Widget.init(&vtable),
            .allocator = allocator,
            .spans = std.ArrayList(Span).empty,
        };
        return self;
    }

    pub fn deinit(self: *RichText) void {
        self.clear();
        self.spans.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn addSpan(self: *RichText, text: []const u8, fg: render.Color, bg: render.Color, style: render.Style) !void {
        const copy = try self.allocator.dupe(u8, text);
        try self.spans.append(self.allocator, .{
            .text = copy,
            .fg = fg,
            .bg = bg,
            .style = style,
        });
    }

    pub fn clear(self: *RichText) void {
        for (self.spans.items) |span| {
            self.allocator.free(span.text);
        }
        self.spans.clearRetainingCapacity();
    }

    pub fn setWrap(self: *RichText, wrap: bool) void {
        self.wrap = wrap;
    }

    pub fn setBorder(self: *RichText, border: render.BorderStyle) void {
        self.border = border;
    }

    pub fn setBackground(self: *RichText, color: render.Color) void {
        self.background = color;
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*RichText, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;

        const rect = self.widget.rect;
        if (rect.width == 0 or rect.height == 0) return;

        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', render.Color{ .named_color = render.NamedColor.default }, self.background, render.Style{});

        const has_border = self.border != .none and rect.width >= 2 and rect.height >= 2;
        const inset: u16 = if (has_border) 1 else 0;
        if (has_border) {
            renderer.drawBox(rect.x, rect.y, rect.width, rect.height, self.border, render.Color{ .named_color = render.NamedColor.default }, self.background, render.Style{});
        }

        const content_width = if (rect.width > inset * 2) rect.width - inset * 2 else 0;
        const content_height = if (rect.height > inset * 2) rect.height - inset * 2 else 0;
        if (content_width == 0 or content_height == 0) return;

        const start_x = rect.x + inset;
        const start_y = rect.y + inset;
        const max_x = start_x + content_width - 1;
        const max_y = start_y + content_height - 1;

        var x = start_x;
        var y = start_y;

        span_loop: for (self.spans.items) |span| {
            var it = std.unicode.Utf8Iterator{ .bytes = span.text, .i = 0 };
            while (it.nextCodepoint()) |cp| {
                if (cp == '\n') {
                    x = start_x;
                    y += 1;
                    if (y > max_y) break :span_loop;
                    continue;
                }

                if (x > max_x) {
                    if (self.wrap) {
                        x = start_x;
                        y += 1;
                        if (y > max_y) break :span_loop;
                    } else {
                        break;
                    }
                }

                renderer.drawChar(x, y, cp, span.fg, span.bg, span.style);
                x += 1;
            }
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        _ = widget_ptr;
        _ = event;
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*RichText, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*RichText, @ptrCast(@alignCast(widget_ptr)));

        var max_width: usize = 0;
        var current_width: usize = 0;
        var lines: usize = 1;

        for (self.spans.items) |span| {
            for (span.text) |c| {
                if (c == '\n') {
                    max_width = @max(max_width, current_width);
                    current_width = 0;
                    lines += 1;
                } else {
                    current_width += 1;
                }
            }
        }

        max_width = @max(max_width, current_width);
        return layout_module.Size.init(@intCast(@max(max_width, 12)), @intCast(@max(lines, 2)));
    }

    fn canFocusFn(_: *anyopaque) bool {
        return false;
    }
};

test "rich text applies span styles" {
    const alloc = std.testing.allocator;
    var text = try RichText.init(alloc);
    defer text.deinit();

    try text.addSpan("Hello ", render.Color{ .named_color = render.NamedColor.green }, render.Color{ .named_color = render.NamedColor.default }, render.Style{ .bold = true });
    try text.addSpan("World", render.Color{ .named_color = render.NamedColor.blue }, render.Color{ .named_color = render.NamedColor.default }, render.Style{ .italic = true });

    try text.widget.layout(layout_module.Rect.init(0, 0, 16, 3));

    var renderer = try render.Renderer.init(alloc, 16, 3);
    defer renderer.deinit();

    try text.widget.draw(&renderer);

    const hello_cell = renderer.back.getCell(0, 0).*;
    try std.testing.expect(hello_cell.style.bold);
    try std.testing.expect(std.meta.eql(hello_cell.fg, render.Color{ .named_color = render.NamedColor.green }));

    const world_cell = renderer.back.getCell(6, 0).*;
    try std.testing.expect(world_cell.style.italic);
    try std.testing.expect(std.meta.eql(world_cell.fg, render.Color{ .named_color = render.NamedColor.blue }));
}
