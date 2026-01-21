const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const theme_mod = @import("../theme.zig");

const InlineSegment = struct {
    text: []const u8,
    color: render.Color,
    style: render.Style,
};

const Line = struct {
    segments: std.ArrayList(InlineSegment),

    fn init() Line {
        return Line{ .segments = std.ArrayList(InlineSegment).empty };
    }

    fn deinit(self: *Line, allocator: std.mem.Allocator) void {
        self.segments.deinit(allocator);
    }

    fn appendSegment(self: *Line, allocator: std.mem.Allocator, slice: []const u8, style: render.Style, color: render.Color) !void {
        if (slice.len == 0) return;
        try self.segments.append(allocator, InlineSegment{
            .text = slice,
            .color = color,
            .style = style,
        });
    }
};

/// Markdown widget that renders a subset of Markdown (headings, bullets, inline emphasis).
pub const Markdown = struct {
    widget: base.Widget,
    allocator: std.mem.Allocator,
    theme: theme_mod.Theme = theme_mod.Theme.dark(),
    content: []u8,
    lines: std.ArrayList(Line),

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator, text: []const u8) !*Markdown {
        const self = try allocator.create(Markdown);
        self.* = Markdown{
            .widget = base.Widget.init(&vtable),
            .allocator = allocator,
            .theme = theme_mod.Theme.dark(),
            .content = try allocator.dupe(u8, text),
            .lines = std.ArrayList(Line).empty,
        };

        try self.parse();
        return self;
    }

    pub fn deinit(self: *Markdown) void {
        self.clearLines();
        self.lines.deinit(self.allocator);
        self.allocator.free(self.content);
        self.allocator.destroy(self);
    }

    pub fn setText(self: *Markdown, text: []const u8) !void {
        self.clearLines();
        self.allocator.free(self.content);
        self.content = try self.allocator.dupe(u8, text);
        try self.parse();
    }

    pub fn setTheme(self: *Markdown, theme: theme_mod.Theme) !void {
        self.theme = theme;
        self.clearLines();
        try self.parse();
    }

    fn clearLines(self: *Markdown) void {
        for (self.lines.items) |*line| {
            line.deinit(self.allocator);
        }
        self.lines.clearRetainingCapacity();
    }

    fn parse(self: *Markdown) !void {
        var in_code_block = false;
        var it = std.mem.split(u8, self.content, "\n");
        while (it.next()) |raw_line| {
            if (std.mem.startsWith(u8, raw_line, "```")) {
                in_code_block = !in_code_block;
                continue;
            }

            var working = raw_line;
            var base_style = self.theme.style;
            var fg = self.theme.color(.text);
            var prefix: ?InlineSegment = null;

            if (in_code_block) {
                base_style.reverse = true;
                fg = self.theme.color(.muted);
            } else if (std.mem.startsWith(u8, working, "# ")) {
                base_style.bold = true;
                base_style.underline = true;
                fg = self.theme.color(.accent);
                working = working[2..];
            } else if (std.mem.startsWith(u8, working, "## ")) {
                base_style.bold = true;
                fg = self.theme.color(.accent);
                working = working[3..];
            } else if (std.mem.startsWith(u8, working, "- ") or std.mem.startsWith(u8, working, "* ")) {
                prefix = InlineSegment{
                    .text = "• ",
                    .color = self.theme.color(.accent),
                    .style = base_style,
                };
                working = working[2..];
            } else if (std.mem.startsWith(u8, working, "> ")) {
                base_style.italic = true;
                prefix = InlineSegment{
                    .text = "│ ",
                    .color = self.theme.color(.muted),
                    .style = base_style,
                };
                working = working[2..];
            }

            var line = Line.init();
            if (prefix) |p| {
                try line.segments.append(self.allocator, p);
            }

            try self.parseInline(&line, working, base_style, fg);
            try self.lines.append(self.allocator, line);
        }
    }

    fn parseInline(self: *Markdown, line: *Line, text: []const u8, base_style: render.Style, base_color: render.Color) !void {
        var current_style = base_style;
        var start: usize = 0;
        var i: usize = 0;
        while (i < text.len) {
            if (i + 1 < text.len and text[i] == '*' and text[i + 1] == '*') {
                try line.appendSegment(self.allocator, text[start..i], current_style, base_color);
                current_style.bold = !current_style.bold;
                i += 2;
                start = i;
                continue;
            }

            if (text[i] == '_') {
                try line.appendSegment(self.allocator, text[start..i], current_style, base_color);
                current_style.italic = !current_style.italic;
                i += 1;
                start = i;
                continue;
            }

            if (text[i] == '`') {
                try line.appendSegment(self.allocator, text[start..i], current_style, base_color);
                current_style.reverse = !current_style.reverse;
                i += 1;
                start = i;
                continue;
            }

            i += 1;
        }

        if (start <= text.len) {
            try line.appendSegment(self.allocator, text[start..], current_style, base_color);
        }
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*Markdown, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;

        const rect = self.widget.rect;
        if (rect.width == 0 or rect.height == 0) return;

        const bg = self.theme.color(.surface);
        const base_fg = self.theme.color(.text);
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', base_fg, bg, self.theme.style);

        const max_lines = @min(self.lines.items.len, rect.height);
        var row: usize = 0;
        while (row < max_lines) : (row += 1) {
            const line = &self.lines.items[row];
            var cursor_x: u16 = rect.x;
            for (line.segments.items) |segment| {
                if (cursor_x >= rect.x + rect.width) break;
                const available: u16 = rect.x + rect.width - cursor_x;
                const take_len: usize = @min(segment.text.len, available);
                if (take_len == 0) break;
                renderer.drawStr(cursor_x, rect.y + @as(u16, @intCast(row)), segment.text[0..take_len], segment.color, bg, segment.style);
                cursor_x += @intCast(take_len);
            }
        }
    }

    fn handleEventFn(_: *anyopaque, _: input.Event) anyerror!bool {
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*Markdown, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    fn get_preferred_dimensions(self: *Markdown) layout_module.Size {
        var max_width: u16 = 0;
        for (self.lines.items) |line| {
            var width: u16 = 0;
            for (line.segments.items) |segment| {
                const seg_width: u16 = @intCast(@min(segment.text.len, @as(usize, std.math.maxInt(u16))));
                if (width > std.math.maxInt(u16) - seg_width) {
                    width = std.math.maxInt(u16);
                } else {
                    width += seg_width;
                }
            }
            if (width > max_width) {
                max_width = width;
            }
        }

        const height: u16 = if (self.lines.items.len > std.math.maxInt(u16))
            std.math.maxInt(u16)
        else
            @intCast(self.lines.items.len);
        return layout_module.Size.init(max_width, height);
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*Markdown, @ptrCast(@alignCast(widget_ptr)));
        return self.get_preferred_dimensions();
    }

    fn canFocusFn(_: *anyopaque) bool {
        return false;
    }
};

test "markdown renders headings and bullets" {
    const alloc = std.testing.allocator;
    var md = try Markdown.init(alloc, "# Title\n- item");
    defer md.deinit();

    try md.widget.layout(layout_module.Rect.init(0, 0, 16, 4));

    var renderer = try render.Renderer.init(alloc, 16, 4);
    defer renderer.deinit();

    try md.widget.draw(&renderer);

    try std.testing.expectEqual(@as(u21, 'T'), renderer.back.getCell(0, 0).codepoint());
    try std.testing.expectEqual(@as(u21, 'i'), renderer.back.getCell(2, 1).codepoint());
    try std.testing.expectEqual(@as(u21, '•'), renderer.back.getCell(0, 1).codepoint());
}
