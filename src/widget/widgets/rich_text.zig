const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const accessibility = @import("../accessibility.zig");

/// Rich text viewer that renders styled spans (color, bold, italic).
pub const RichText = struct {
    widget: base.Widget,
    allocator: std.mem.Allocator,
    spans: std.ArrayList(Span),
    border: render.BorderStyle = .none,
    background: render.Color = render.Color{ .named_color = render.NamedColor.default },
    wrap: bool = true,
    box_style: ?render.BoxStyle = null,

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
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.status), "Rich text", "");
        return self;
    }

    pub fn deinit(self: *RichText) void {
        self.clear();
        self.spans.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn addSpan(self: *RichText, text: []const u8, fg: render.Color, bg: render.Color, style: render.Style) !void {
        try self.spans.ensureUnusedCapacity(self.allocator, 1);
        const copy = try self.allocator.dupe(u8, text);
        self.spans.appendAssumeCapacity(.{
            .text = copy,
            .fg = fg,
            .bg = bg,
            .style = style,
        });
        self.widget.markDirty();
    }

    pub fn clear(self: *RichText) void {
        const had_spans = self.spans.items.len > 0;
        for (self.spans.items) |span| {
            self.allocator.free(span.text);
        }
        self.spans.clearRetainingCapacity();
        if (had_spans) self.widget.markDirty();
    }

    pub fn setWrap(self: *RichText, wrap: bool) void {
        if (self.wrap == wrap) return;
        self.wrap = wrap;
        self.widget.markDirty();
    }

    pub fn setBorder(self: *RichText, border: render.BorderStyle) void {
        if (self.border == border) return;
        self.border = border;
        self.widget.markDirty();
    }

    pub fn setBackground(self: *RichText, color: render.Color) void {
        if (std.meta.eql(self.background, color)) return;
        self.background = color;
        self.widget.markDirty();
    }

    pub fn setBoxStyle(self: *RichText, style: render.BoxStyle) void {
        self.box_style = style;
        self.widget.markDirty();
    }

    fn addOffsetClamped(origin: u16, offset: u16) u16 {
        const value = @as(u32, origin) + @as(u32, offset);
        return @intCast(@min(value, @as(u32, std.math.maxInt(u16))));
    }

    fn endCoordClamped(start: u16, len: u16) u16 {
        if (len == 0) return start;
        return addOffsetClamped(start, len - 1);
    }

    fn clampUsizeToU16(value: usize) u16 {
        return @intCast(@min(value, @as(usize, std.math.maxInt(u16))));
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *RichText = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible) return;

        const rect = self.widget.rect;
        if (rect.width == 0 or rect.height == 0) return;

        var inset: u16 = 0;
        var active_border = self.border;

        if (self.box_style) |style| {
            renderer.drawStyledBox(rect.x, rect.y, rect.width, rect.height, style);
            active_border = style.border;
            if (active_border != .none and rect.width >= 2 and rect.height >= 2) {
                inset = 1;
            }
        } else {
            renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', render.Color{ .named_color = render.NamedColor.default }, self.background, render.Style{});
            if (active_border != .none and rect.width >= 2 and rect.height >= 2) {
                renderer.drawBox(rect.x, rect.y, rect.width, rect.height, active_border, render.Color{ .named_color = render.NamedColor.default }, self.background, render.Style{});
                inset = 1;
            }
        }

        const content_width = if (rect.width > inset * 2) rect.width - inset * 2 else 0;
        const content_height = if (rect.height > inset * 2) rect.height - inset * 2 else 0;
        if (content_width == 0 or content_height == 0) return;

        const start_x = addOffsetClamped(rect.x, inset);
        const start_y = addOffsetClamped(rect.y, inset);
        const max_x = endCoordClamped(start_x, content_width);
        const max_y = endCoordClamped(start_y, content_height);

        const start_x_u32: u32 = start_x;
        const start_y_u32: u32 = start_y;
        const max_x_u32: u32 = max_x;
        const max_y_u32: u32 = max_y;

        var x = start_x_u32;
        var y = start_y_u32;

        span_loop: for (self.spans.items) |span| {
            var it = std.unicode.Utf8Iterator{ .bytes = span.text, .i = 0 };
            while (it.nextCodepoint()) |cp| {
                if (cp == '\n') {
                    x = start_x_u32;
                    y += 1;
                    if (y > max_y_u32) break :span_loop;
                    continue;
                }

                if (x > max_x_u32) {
                    if (self.wrap) {
                        x = start_x_u32;
                        y += 1;
                        if (y > max_y_u32) break :span_loop;
                    } else {
                        break;
                    }
                }

                renderer.drawChar(@intCast(x), @intCast(y), cp, span.fg, span.bg, span.style);
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
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *RichText = @fieldParentPtr("widget", widget_ref);
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *RichText = @fieldParentPtr("widget", widget_ref);

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
        return layout_module.Size.init(clampUsizeToU16(@max(max_width, 12)), clampUsizeToU16(@max(lines, 2)));
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

test "rich text marks dirty when content changes" {
    const alloc = std.testing.allocator;
    var text = try RichText.init(alloc);
    defer text.deinit();

    try text.widget.layout(layout_module.Rect.init(0, 0, 12, 2));
    var renderer = try render.Renderer.init(alloc, 12, 2);
    defer renderer.deinit();

    try text.widget.draw(&renderer);
    try std.testing.expect(!text.widget.dirty);

    try text.addSpan("Hello", render.Color{ .named_color = render.NamedColor.green }, render.Color{ .named_color = render.NamedColor.default }, render.Style{});
    try std.testing.expect(text.widget.dirty);

    try text.widget.draw(&renderer);
    try std.testing.expect(!text.widget.dirty);

    text.clear();
    try std.testing.expect(text.widget.dirty);

    try text.widget.draw(&renderer);
    try std.testing.expect(!text.widget.dirty);
    text.clear();
    try std.testing.expect(!text.widget.dirty);
}

test "rich text marks dirty when rendering options change" {
    const alloc = std.testing.allocator;
    var text = try RichText.init(alloc);
    defer text.deinit();

    try text.widget.layout(layout_module.Rect.init(0, 0, 8, 3));
    var renderer = try render.Renderer.init(alloc, 8, 3);
    defer renderer.deinit();

    try text.addSpan("wrapped text", render.Color{ .named_color = render.NamedColor.white }, render.Color{ .named_color = render.NamedColor.default }, render.Style{});
    try text.widget.draw(&renderer);
    try std.testing.expect(!text.widget.dirty);

    text.setWrap(false);
    try std.testing.expect(text.widget.dirty);
    try text.widget.draw(&renderer);
    try std.testing.expect(!text.widget.dirty);
    text.setWrap(false);
    try std.testing.expect(!text.widget.dirty);

    text.setBorder(.single);
    try std.testing.expect(text.widget.dirty);
    try text.widget.draw(&renderer);
    try std.testing.expect(!text.widget.dirty);
    text.setBorder(.single);
    try std.testing.expect(!text.widget.dirty);

    text.setBackground(render.Color{ .named_color = render.NamedColor.blue });
    try std.testing.expect(text.widget.dirty);
    try text.widget.draw(&renderer);
    try std.testing.expect(!text.widget.dirty);
    text.setBackground(render.Color{ .named_color = render.NamedColor.blue });
    try std.testing.expect(!text.widget.dirty);

    text.setBoxStyle(render.BoxStyle{ .border = .rounded, .background = render.Color{ .named_color = render.NamedColor.black } });
    try std.testing.expect(text.widget.dirty);
}

test "rich text clamps far-edge render coordinates" {
    const alloc = std.testing.allocator;
    var text = try RichText.init(alloc);
    defer text.deinit();

    try text.addSpan("ab", render.Color{ .named_color = render.NamedColor.green }, render.Color{ .named_color = render.NamedColor.default }, render.Style{});
    try text.widget.layout(layout_module.Rect.init(std.math.maxInt(u16), 0, 2, 1));

    var renderer = try render.Renderer.init(alloc, 4, 1);
    defer renderer.deinit();

    try text.widget.draw(&renderer);
}

test "rich text preferred size saturates long content" {
    const alloc = std.testing.allocator;
    var text = try RichText.init(alloc);
    defer text.deinit();

    const long_line = try alloc.alloc(u8, @as(usize, std.math.maxInt(u16)) + 128);
    defer alloc.free(long_line);
    @memset(long_line, 'x');

    try text.addSpan(long_line, render.Color{ .named_color = render.NamedColor.green }, render.Color{ .named_color = render.NamedColor.default }, render.Style{});
    var size = try text.widget.getPreferredSize();
    try std.testing.expectEqual(@as(u16, std.math.maxInt(u16)), size.width);
    try std.testing.expectEqual(@as(u16, 2), size.height);

    text.clear();
    @memset(long_line, '\n');

    try text.addSpan(long_line, render.Color{ .named_color = render.NamedColor.green }, render.Color{ .named_color = render.NamedColor.default }, render.Style{});
    size = try text.widget.getPreferredSize();
    try std.testing.expectEqual(@as(u16, 12), size.width);
    try std.testing.expectEqual(@as(u16, std.math.maxInt(u16)), size.height);
}

fn richTextAddSpanAllocationFailureHarness(allocator: std.mem.Allocator) !void {
    var text = try RichText.init(allocator);
    defer text.deinit();

    try text.addSpan("Hello", render.Color{ .named_color = render.NamedColor.green }, render.Color{ .named_color = render.NamedColor.default }, render.Style{});
    try text.addSpan("World", render.Color{ .named_color = render.NamedColor.blue }, render.Color{ .named_color = render.NamedColor.default }, render.Style{});
}

test "rich text addSpan cleans up every allocation failure path" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, richTextAddSpanAllocationFailureHarness, .{});
}

test "rich text addSpan preserves spans on allocation failure" {
    const alloc = std.testing.allocator;
    var text = try RichText.init(alloc);
    defer text.deinit();

    try text.addSpan("stable", render.Color{ .named_color = render.NamedColor.green }, render.Color{ .named_color = render.NamedColor.default }, render.Style{});

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = text.allocator;
    text.allocator = failing.allocator();
    defer text.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, text.addSpan("replacement", render.Color{ .named_color = render.NamedColor.blue }, render.Color{ .named_color = render.NamedColor.default }, render.Style{}));
    try std.testing.expectEqual(@as(usize, 1), text.spans.items.len);
    try std.testing.expectEqualStrings("stable", text.spans.items[0].text);
}
