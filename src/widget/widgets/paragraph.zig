const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const text_metrics = @import("../../render/text_metrics.zig");
const input = @import("../../input/input.zig");
const accessibility = @import("../accessibility.zig");

/// Paragraph widget: read-only text with wrapping, padding, alignment, and scroll offset.
pub const Paragraph = struct {
    widget: base.Widget,
    allocator: std.mem.Allocator,
    text: []u8,
    fg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    bg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    style: render.Style = render.Style{},
    wrap: bool = true,
    scroll_offset: u16 = 0,
    alignment: Alignment = .left,
    padding: Padding = Padding{},

    pub const Alignment = enum { left, center, right };
    pub const Padding = struct {
        left: u16 = 0,
        right: u16 = 0,
        top: u16 = 0,
        bottom: u16 = 0,
    };

    const RenderLine = struct {
        text: []const u8,
        width: u16,
    };

    const LineIterator = struct {
        text: []const u8,
        max_width: u16,
        wrap: bool,
        next_segment_start: usize = 0,
        segments_finished: bool = false,
        remaining: ?[]const u8 = null,

        const Fit = struct {
            end: usize = 0,
            width: u16 = 0,
            first_end: usize = 0,
            last_space: ?usize = null,
            width_before_space: u16 = 0,
        };

        fn init(text: []const u8, max_width: u16, wrap: bool) LineIterator {
            return .{ .text = text, .max_width = max_width, .wrap = wrap };
        }

        fn next(self: *LineIterator) ?RenderLine {
            if (self.max_width == 0) return null;
            if (self.remaining == null and !self.loadSegment()) return null;

            const remaining = self.remaining.?;
            if (remaining.len == 0) {
                self.remaining = null;
                return .{ .text = "", .width = 0 };
            }

            const fit = fitPrefix(remaining, self.max_width);
            if (!self.wrap or fit.end == remaining.len) {
                self.remaining = null;
                return .{ .text = remaining[0..fit.end], .width = fit.width };
            }

            var line_end = fit.end;
            var line_width = fit.width;
            var consume_end = fit.end;
            if (fit.last_space) |space| {
                if (space > 0) {
                    line_end = space;
                    line_width = fit.width_before_space;
                    consume_end = space;
                }
            }

            if (consume_end == 0) {
                consume_end = fit.first_end;
                line_end = 0;
                line_width = 0;
            }

            const tail = std.mem.trimStart(u8, remaining[consume_end..], " ");
            self.remaining = if (tail.len == 0) null else tail;
            return .{ .text = remaining[0..line_end], .width = line_width };
        }

        fn loadSegment(self: *LineIterator) bool {
            if (self.segments_finished) return false;
            const next_break = std.mem.indexOfScalarPos(u8, self.text, self.next_segment_start, '\n') orelse self.text.len;
            self.remaining = self.text[self.next_segment_start..next_break];
            if (next_break == self.text.len) {
                self.segments_finished = true;
            } else {
                self.next_segment_start = next_break + 1;
            }
            return true;
        }

        fn fitPrefix(segment: []const u8, max_width: u16) Fit {
            var fit = Fit{};
            var graphemes = text_metrics.GraphemeIterator.init(segment);
            while (true) {
                const start = graphemes.it.i;
                const grapheme = graphemes.next() orelse break;
                const end = graphemes.it.i;
                if (fit.first_end == 0) fit.first_end = end;

                const grapheme_width: u16 = grapheme.width;
                if (grapheme_width > max_width - fit.width) break;
                if (end - start == 1 and segment[start] == ' ') {
                    fit.last_space = start;
                    fit.width_before_space = fit.width;
                }
                fit.end = end;
                fit.width += grapheme_width;
            }
            return fit;
        }
    };

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator, text: []const u8) !*Paragraph {
        const self = try allocator.create(Paragraph);
        errdefer allocator.destroy(self);

        const text_copy = try allocator.dupe(u8, text);
        self.* = Paragraph{
            .widget = base.Widget.init(&vtable),
            .allocator = allocator,
            .text = text_copy,
        };
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.status), "Paragraph", "");
        return self;
    }

    pub fn deinit(self: *Paragraph) void {
        self.allocator.free(self.text);
        self.allocator.destroy(self);
    }

    pub fn setText(self: *Paragraph, text: []const u8) !void {
        if (std.mem.eql(u8, self.text, text)) return;

        const next = try self.allocator.dupe(u8, text);
        self.allocator.free(self.text);
        self.text = next;
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.status), "Paragraph", "");
        self.widget.markDirty();
    }

    pub fn setWrap(self: *Paragraph, wrap: bool) void {
        if (self.wrap == wrap) return;
        self.wrap = wrap;
        self.widget.markDirty();
    }

    pub fn setScroll(self: *Paragraph, offset: u16) void {
        if (self.scroll_offset == offset) return;
        self.scroll_offset = offset;
        self.widget.markDirty();
    }

    pub fn setAlignment(self: *Paragraph, alignment: Alignment) void {
        if (self.alignment == alignment) return;
        self.alignment = alignment;
        self.widget.markDirty();
    }

    pub fn setPadding(self: *Paragraph, padding: Padding) void {
        if (std.meta.eql(self.padding, padding)) return;
        self.padding = padding;
        self.widget.markDirty();
    }

    pub fn setColors(self: *Paragraph, fg: render.Color, bg: render.Color) void {
        if (std.meta.eql(self.fg, fg) and std.meta.eql(self.bg, bg)) return;

        self.fg = fg;
        self.bg = bg;
        self.widget.markDirty();
    }

    pub fn setStyle(self: *Paragraph, style: render.Style) void {
        if (std.meta.eql(self.style, style)) return;

        self.style = style;
        self.widget.markDirty();
    }

    fn addOffsetClamped(origin: u16, offset: u16) u16 {
        const value = @as(u32, origin) + @as(u32, offset);
        return @intCast(@min(value, @as(u32, std.math.maxInt(u16))));
    }

    fn addU16Clamped(a: u16, b: u16) u16 {
        const value = @as(u32, a) + @as(u32, b);
        return @intCast(@min(value, @as(u32, std.math.maxInt(u16))));
    }

    fn addUsizeClamped(a: usize, b: usize) usize {
        return std.math.add(usize, a, b) catch std.math.maxInt(usize);
    }

    fn clampUsizeToU16(value: usize) u16 {
        return @intCast(@min(value, @as(usize, std.math.maxInt(u16))));
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Paragraph = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible) return;

        const rect = self.widget.rect;
        if (rect.width == 0 or rect.height == 0) return;

        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', self.fg, self.bg, render.Style{});

        const horizontal_padding = addU16Clamped(self.padding.left, self.padding.right);
        const vertical_padding = addU16Clamped(self.padding.top, self.padding.bottom);
        const content_width = if (rect.width > horizontal_padding)
            rect.width - horizontal_padding
        else
            0;
        const content_height = if (rect.height > vertical_padding)
            rect.height - vertical_padding
        else
            0;
        if (content_width == 0 or content_height == 0) return;

        const base_y = addOffsetClamped(rect.y, self.padding.top);
        const base_x = addOffsetClamped(rect.x, self.padding.left);
        var lines = LineIterator.init(self.text, content_width, self.wrap);
        var skipped: usize = 0;
        while (skipped < self.scroll_offset) : (skipped += 1) {
            _ = lines.next() orelse return;
        }

        var row: u16 = 0;
        while (row < content_height) : (row += 1) {
            const line = lines.next() orelse break;
            var draw_x = base_x;

            switch (self.alignment) {
                .left => {},
                .center => {
                    if (line.width < content_width) {
                        draw_x = addOffsetClamped(draw_x, (content_width - line.width) / 2);
                    }
                },
                .right => {
                    if (line.width < content_width) {
                        draw_x = addOffsetClamped(draw_x, content_width - line.width);
                    }
                },
            }

            const y = addOffsetClamped(base_y, row);
            renderer.drawStr(draw_x, y, line.text, self.fg, self.bg, self.style);
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        _ = widget_ptr;
        _ = event;
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Paragraph = @fieldParentPtr("widget", widget_ref);
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Paragraph = @fieldParentPtr("widget", widget_ref);
        var max_width: u16 = 0;
        var lines: usize = 1;
        var start: usize = 0;
        while (start <= self.text.len) {
            const next_break = std.mem.indexOfScalarPos(u8, self.text, start, '\n') orelse self.text.len;
            max_width = @max(max_width, text_metrics.measureWidth(self.text[start..next_break]).width);
            if (next_break == self.text.len) break;
            lines += 1;
            start = next_break + 1;
        }

        const horizontal_padding = addUsizeClamped(self.padding.left, self.padding.right);
        const vertical_padding = addUsizeClamped(self.padding.top, self.padding.bottom);
        const width = clampUsizeToU16(addUsizeClamped(horizontal_padding, @max(max_width, 1)));
        const height = clampUsizeToU16(addUsizeClamped(vertical_padding, @max(lines, 1)));
        return layout_module.Size.init(width, height);
    }

    fn canFocusFn(_: *anyopaque) bool {
        return false;
    }
};

test "paragraph wraps and scrolls" {
    const alloc = std.testing.allocator;
    var p = try Paragraph.init(alloc, "alpha beta gamma");
    defer p.deinit();
    p.setPadding(.{});
    p.setWrap(true);
    p.setScroll(1);
    try p.widget.layout(layout_module.Rect.init(0, 0, 6, 2));

    var renderer = try render.Renderer.init(alloc, 6, 2);
    defer renderer.deinit();
    try p.widget.draw(&renderer);

    // After scrolling one line, the second wrapped line should be visible first.
    const cell0 = renderer.back.getCell(0, 0).*;
    try std.testing.expectEqual(@as(u21, 'b'), cell0.codepoint());
}

test "paragraph wraps on grapheme cell widths" {
    var lines = Paragraph.LineIterator.init("界A\u{0301} 😁\n", 2, true);

    const cjk = lines.next().?;
    try std.testing.expectEqualStrings("界", cjk.text);
    try std.testing.expectEqual(@as(u16, 2), cjk.width);

    const combining = lines.next().?;
    try std.testing.expectEqualStrings("A\u{0301}", combining.text);
    try std.testing.expectEqual(@as(u16, 1), combining.width);

    const emoji = lines.next().?;
    try std.testing.expectEqualStrings("😁", emoji.text);
    try std.testing.expectEqual(@as(u16, 2), emoji.width);

    const trailing_empty = lines.next().?;
    try std.testing.expectEqualStrings("", trailing_empty.text);
    try std.testing.expectEqual(@as(u16, 0), trailing_empty.width);
    try std.testing.expect(lines.next() == null);

    var clipped = Paragraph.LineIterator.init("界A", 2, false);
    const clipped_line = clipped.next().?;
    try std.testing.expectEqualStrings("界", clipped_line.text);
    try std.testing.expectEqual(@as(u16, 2), clipped_line.width);
    try std.testing.expect(clipped.next() == null);
}

test "paragraph draw remains allocation-free while wrapping" {
    const alloc = std.testing.allocator;
    var p = try Paragraph.init(alloc, "alpha beta gamma delta");
    defer p.deinit();
    try p.widget.layout(layout_module.Rect.init(0, 0, 6, 4));

    var renderer = try render.Renderer.init(alloc, 6, 4);
    defer renderer.deinit();
    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = p.allocator;
    const original_renderer_allocator = renderer.allocator;
    p.allocator = failing.allocator();
    renderer.allocator = failing.allocator();
    defer {
        p.allocator = original_allocator;
        renderer.allocator = original_renderer_allocator;
    }

    try p.widget.draw(&renderer);
    try std.testing.expectEqual(@as(u21, 'a'), renderer.back.getCell(0, 0).codepoint());
    try std.testing.expectEqual(@as(u21, 'b'), renderer.back.getCell(0, 1).codepoint());
    try std.testing.expectEqual(@as(u21, 'g'), renderer.back.getCell(0, 2).codepoint());
    try std.testing.expectEqual(@as(u21, 'd'), renderer.back.getCell(0, 3).codepoint());
}

test "paragraph preferred size uses terminal cell widths" {
    const alloc = std.testing.allocator;
    var p = try Paragraph.init(alloc, "界A\u{0301}\n😁");
    defer p.deinit();

    const size = try p.widget.getPreferredSize();
    try std.testing.expectEqual(@as(u16, 3), size.width);
    try std.testing.expectEqual(@as(u16, 2), size.height);
}

test "paragraph clamps edge padding and draw coordinates" {
    const alloc = std.testing.allocator;
    var p = try Paragraph.init(alloc, "x");
    defer p.deinit();

    p.setPadding(.{ .left = std.math.maxInt(u16), .right = 1 });
    try p.widget.layout(layout_module.Rect.init(0, 0, 10, 1));

    var renderer = try render.Renderer.init(alloc, 10, 1);
    defer renderer.deinit();

    try p.widget.draw(&renderer);

    p.setPadding(.{ .left = 1 });
    try p.widget.layout(layout_module.Rect.init(std.math.maxInt(u16), 0, 2, 1));
    try p.widget.draw(&renderer);
}

test "paragraph preferred size saturates padding and long content" {
    const alloc = std.testing.allocator;

    const long_text = try alloc.alloc(u8, @as(usize, std.math.maxInt(u16)) + 128);
    defer alloc.free(long_text);
    @memset(long_text, 'x');

    var p = try Paragraph.init(alloc, long_text);
    defer p.deinit();

    var size = try p.widget.getPreferredSize();
    try std.testing.expectEqual(@as(u16, std.math.maxInt(u16)), size.width);
    try std.testing.expectEqual(@as(u16, 1), size.height);

    p.setPadding(.{ .left = std.math.maxInt(u16), .right = 1, .top = std.math.maxInt(u16), .bottom = 1 });
    size = try p.widget.getPreferredSize();
    try std.testing.expectEqual(@as(u16, std.math.maxInt(u16)), size.width);
    try std.testing.expectEqual(@as(u16, std.math.maxInt(u16)), size.height);

    p.setPadding(.{});
    @memset(long_text, '\n');
    try p.setText(long_text);
    size = try p.widget.getPreferredSize();
    try std.testing.expectEqual(@as(u16, 1), size.width);
    try std.testing.expectEqual(@as(u16, std.math.maxInt(u16)), size.height);
}

fn paragraphInitAllocationFailureHarness(allocator: std.mem.Allocator) !void {
    var p = try Paragraph.init(allocator, "alpha beta gamma");
    defer p.deinit();
}

test "paragraph init cleans up every allocation failure path" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, paragraphInitAllocationFailureHarness, .{});
}

test "paragraph setText preserves text on allocation failure" {
    const alloc = std.testing.allocator;
    var p = try Paragraph.init(alloc, "stable paragraph");
    defer p.deinit();

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    p.allocator = failing.allocator();

    try std.testing.expectError(error.OutOfMemory, p.setText("replacement paragraph"));
    try std.testing.expectEqualStrings("stable paragraph", p.text);
}

test "paragraph visible mutations mark dirty only when changed" {
    const alloc = std.testing.allocator;
    var p = try Paragraph.init(alloc, "stable paragraph");
    defer p.deinit();

    p.widget.clearDirty();
    try p.setText("stable paragraph");
    try std.testing.expect(!p.widget.dirty);
    p.widget.clearDirty();
    try p.setText("changed paragraph");
    try std.testing.expect(p.widget.dirty);
    try std.testing.expectEqualStrings("changed paragraph", p.text);

    p.widget.clearDirty();
    p.setWrap(false);
    try std.testing.expect(p.widget.dirty);
    p.widget.clearDirty();
    p.setWrap(false);
    try std.testing.expect(!p.widget.dirty);

    p.widget.clearDirty();
    p.setScroll(2);
    try std.testing.expect(p.widget.dirty);
    p.widget.clearDirty();
    p.setScroll(2);
    try std.testing.expect(!p.widget.dirty);

    p.widget.clearDirty();
    p.setAlignment(.center);
    try std.testing.expect(p.widget.dirty);
    p.widget.clearDirty();
    p.setAlignment(.center);
    try std.testing.expect(!p.widget.dirty);

    p.widget.clearDirty();
    p.setPadding(.{ .left = 1, .right = 2, .top = 3, .bottom = 4 });
    try std.testing.expect(p.widget.dirty);
    p.widget.clearDirty();
    p.setPadding(.{ .left = 1, .right = 2, .top = 3, .bottom = 4 });
    try std.testing.expect(!p.widget.dirty);

    p.widget.clearDirty();
    p.setColors(render.Color.named(.white), render.Color.named(.black));
    try std.testing.expect(p.widget.dirty);
    p.widget.clearDirty();
    p.setColors(render.Color.named(.white), render.Color.named(.black));
    try std.testing.expect(!p.widget.dirty);

    p.widget.clearDirty();
    p.setStyle(render.Style{ .bold = true });
    try std.testing.expect(p.widget.dirty);
    p.widget.clearDirty();
    p.setStyle(render.Style{ .bold = true });
    try std.testing.expect(!p.widget.dirty);
}

test "paragraph setText no-op does not allocate" {
    const alloc = std.testing.allocator;
    var p = try Paragraph.init(alloc, "stable paragraph");
    defer p.deinit();

    p.widget.clearDirty();
    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = p.allocator;
    p.allocator = failing.allocator();
    defer p.allocator = original_allocator;

    try p.setText("stable paragraph");
    try std.testing.expectEqualStrings("stable paragraph", p.text);
    try std.testing.expect(!p.widget.dirty);
}
