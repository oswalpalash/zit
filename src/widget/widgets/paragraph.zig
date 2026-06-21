const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
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

        var lines = try self.buildLines(content_width);
        defer lines.deinit(self.allocator);

        const start_line = @min(@as(usize, self.scroll_offset), lines.items.len);
        const max_lines = @min(@as(usize, content_height), lines.items.len - start_line);

        const base_y = addOffsetClamped(rect.y, self.padding.top);
        const base_x = addOffsetClamped(rect.x, self.padding.left);

        for (lines.items[start_line .. start_line + max_lines], 0..) |line, row| {
            const slice = if (line.len > content_width) line[0..content_width] else line;
            const line_width: u16 = @intCast(slice.len);
            var draw_x = base_x;

            switch (self.alignment) {
                .left => {},
                .center => {
                    if (line_width < content_width) {
                        draw_x = addOffsetClamped(draw_x, (content_width - line_width) / 2);
                    }
                },
                .right => {
                    if (line_width < content_width) {
                        draw_x = addOffsetClamped(draw_x, content_width - line_width);
                    }
                },
            }

            const y = addOffsetClamped(base_y, @intCast(row));
            renderer.drawStr(draw_x, y, slice, self.fg, self.bg, self.style);
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
        var max_width: usize = 0;
        var lines: usize = 1;
        var current: usize = 0;

        for (self.text) |c| {
            if (c == '\n') {
                max_width = @max(max_width, current);
                current = 0;
                lines += 1;
            } else {
                current += 1;
            }
        }
        max_width = @max(max_width, current);

        const horizontal_padding = addUsizeClamped(self.padding.left, self.padding.right);
        const vertical_padding = addUsizeClamped(self.padding.top, self.padding.bottom);
        const width = clampUsizeToU16(addUsizeClamped(horizontal_padding, @max(max_width, 1)));
        const height = clampUsizeToU16(addUsizeClamped(vertical_padding, @max(lines, 1)));
        return layout_module.Size.init(width, height);
    }

    fn canFocusFn(_: *anyopaque) bool {
        return false;
    }

    fn buildLines(self: *Paragraph, width: u16) !std.ArrayList([]const u8) {
        var lines = try std.ArrayList([]const u8).initCapacity(self.allocator, 4);
        if (width == 0) return lines;

        var start: usize = 0;
        while (start <= self.text.len) {
            const next_break = std.mem.indexOfScalarPos(u8, self.text, start, '\n') orelse self.text.len;
            const segment = self.text[start..next_break];
            try self.wrapSegment(segment, width, &lines);
            if (next_break == self.text.len) break;
            start = next_break + 1;
        }

        if (lines.items.len == 0) {
            try lines.append(self.allocator, "");
        }
        return lines;
    }

    fn wrapSegment(self: *Paragraph, segment: []const u8, width: u16, lines: *std.ArrayList([]const u8)) !void {
        if (!self.wrap or segment.len <= width) {
            try lines.append(self.allocator, segment);
            return;
        }

        var remaining = segment;
        const max_width: usize = @intCast(width);
        while (remaining.len > 0) {
            if (remaining.len <= max_width) {
                try lines.append(self.allocator, remaining);
                break;
            }

            const maybe_space = std.mem.findScalarLast(u8, remaining[0..max_width], ' ');
            const split_at = maybe_space orelse max_width;
            const line = remaining[0..split_at];
            try lines.append(self.allocator, line);

            const after = remaining[split_at..];
            const trimmed = std.mem.trimStart(u8, after, " ");
            remaining = trimmed;
        }
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
