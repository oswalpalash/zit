const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");

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
        self.* = Paragraph{
            .widget = base.Widget.init(&vtable),
            .allocator = allocator,
            .text = try allocator.dupe(u8, text),
        };
        return self;
    }

    pub fn deinit(self: *Paragraph) void {
        self.allocator.free(self.text);
        self.allocator.destroy(self);
    }

    pub fn setText(self: *Paragraph, text: []const u8) !void {
        self.allocator.free(self.text);
        self.text = try self.allocator.dupe(u8, text);
    }

    pub fn setWrap(self: *Paragraph, wrap: bool) void {
        self.wrap = wrap;
    }

    pub fn setScroll(self: *Paragraph, offset: u16) void {
        self.scroll_offset = offset;
    }

    pub fn setAlignment(self: *Paragraph, alignment: Alignment) void {
        self.alignment = alignment;
    }

    pub fn setPadding(self: *Paragraph, padding: Padding) void {
        self.padding = padding;
    }

    pub fn setColors(self: *Paragraph, fg: render.Color, bg: render.Color) void {
        self.fg = fg;
        self.bg = bg;
    }

    pub fn setStyle(self: *Paragraph, style: render.Style) void {
        self.style = style;
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*Paragraph, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;

        const rect = self.widget.rect;
        if (rect.width == 0 or rect.height == 0) return;

        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', self.fg, self.bg, render.Style{});

        const content_width = if (rect.width > self.padding.left + self.padding.right)
            rect.width - (self.padding.left + self.padding.right)
        else
            0;
        const content_height = if (rect.height > self.padding.top + self.padding.bottom)
            rect.height - (self.padding.top + self.padding.bottom)
        else
            0;
        if (content_width == 0 or content_height == 0) return;

        var lines = try self.buildLines(content_width);
        defer lines.deinit();

        const start_line = @min(@as(usize, self.scroll_offset), lines.items.len);
        const max_lines = @min(@as(usize, content_height), lines.items.len - start_line);

        const base_y = rect.y + self.padding.top;
        const base_x = rect.x + self.padding.left;

        for (lines.items[start_line .. start_line + max_lines], 0..) |line, row| {
            const slice = if (line.len > content_width) line[0..content_width] else line;
            const line_width: u16 = @intCast(slice.len);
            var draw_x = base_x;

            switch (self.alignment) {
                .left => {},
                .center => {
                    if (line_width < content_width) {
                        draw_x += (content_width - line_width) / 2;
                    }
                },
                .right => {
                    if (line_width < content_width) {
                        draw_x += content_width - line_width;
                    }
                },
            }

            const y = base_y + @as(u16, @intCast(row));
            renderer.drawStr(draw_x, y, slice, self.fg, self.bg, self.style);
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        _ = widget_ptr;
        _ = event;
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*Paragraph, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*Paragraph, @ptrCast(@alignCast(widget_ptr)));
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

        const width = self.padding.left + self.padding.right + @as(u16, @intCast(@max(max_width, 1)));
        const height = self.padding.top + self.padding.bottom + @as(u16, @intCast(@max(lines, 1)));
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

            const maybe_space = std.mem.lastIndexOfScalar(remaining[0..max_width], ' ');
            const split_at = maybe_space orelse max_width;
            const line = remaining[0..split_at];
            try lines.append(self.allocator, line);

            const after = remaining[split_at..];
            const trimmed = std.mem.trimLeft(u8, after, " ");
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
    try std.testing.expectEqual('b', cell0.ch);
}
