const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const text_metrics = @import("../../render/text_metrics.zig");
const input = @import("../../input/input.zig");
const theme_mod = @import("../theme.zig");
const accessibility = @import("../accessibility.zig");

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
        const content = try allocator.dupe(u8, text);
        var content_owned_by_stack = true;
        errdefer if (content_owned_by_stack) allocator.free(content);

        const self = try allocator.create(Markdown);
        self.* = Markdown{
            .widget = base.Widget.init(&vtable),
            .allocator = allocator,
            .theme = theme_mod.Theme.dark(),
            .content = content,
            .lines = std.ArrayList(Line).empty,
        };
        content_owned_by_stack = false;
        errdefer self.deinit();

        self.widget.setAccessibility(@intFromEnum(accessibility.Role.status), "Markdown", "");

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
        const next_content = try self.allocator.dupe(u8, text);
        const old_content = self.content;
        var old_lines = self.lines;

        self.content = next_content;
        self.lines = std.ArrayList(Line).empty;
        errdefer {
            self.clearLines();
            self.lines.deinit(self.allocator);
            self.allocator.free(next_content);
            self.content = old_content;
            self.lines = old_lines;
        }

        try self.parse();

        for (old_lines.items) |*line| {
            line.deinit(self.allocator);
        }
        old_lines.deinit(self.allocator);
        self.allocator.free(old_content);
        self.widget.markDirty();
    }

    pub fn setTheme(self: *Markdown, theme: theme_mod.Theme) !void {
        if (std.meta.eql(self.theme, theme)) return;
        const old_theme = self.theme;
        var old_lines = self.lines;

        self.theme = theme;
        self.lines = std.ArrayList(Line).empty;
        errdefer {
            self.clearLines();
            self.lines.deinit(self.allocator);
            self.theme = old_theme;
            self.lines = old_lines;
        }

        try self.parse();

        for (old_lines.items) |*line| {
            line.deinit(self.allocator);
        }
        old_lines.deinit(self.allocator);
        self.widget.markDirty();
    }

    fn clearLines(self: *Markdown) void {
        for (self.lines.items) |*line| {
            line.deinit(self.allocator);
        }
        self.lines.clearRetainingCapacity();
    }

    fn parse(self: *Markdown) !void {
        var in_code_block = false;
        var it = std.mem.splitScalar(u8, self.content, '\n');
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
            var line_owned_by_stack = true;
            errdefer if (line_owned_by_stack) line.deinit(self.allocator);

            if (prefix) |p| {
                try line.segments.append(self.allocator, p);
            }

            try self.parseInline(&line, working, base_style, fg);
            try self.lines.append(self.allocator, line);
            line_owned_by_stack = false;
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
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Markdown = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible) return;

        const rect = self.widget.rect;
        if (rect.width == 0 or rect.height == 0) return;

        const bg = self.theme.color(.surface);
        const base_fg = self.theme.color(.text);
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', base_fg, bg, self.theme.style);

        const right: u32 = @as(u32, rect.x) + @as(u32, rect.width);
        const bottom: u32 = @as(u32, rect.y) + @as(u32, rect.height);
        const max_lines = @min(self.lines.items.len, rect.height);
        var row: usize = 0;
        while (row < max_lines) : (row += 1) {
            const row_u32: u32 = @intCast(row);
            const draw_y_u32 = @as(u32, rect.y) + row_u32;
            if (draw_y_u32 >= bottom) break;
            const draw_y = u16Coord(draw_y_u32) orelse break;

            const line = &self.lines.items[row];
            var cursor_x: u32 = rect.x;
            var scratch: [1024]u8 = undefined;
            for (line.segments.items) |segment| {
                if (cursor_x >= right) break;
                const draw_x = u16Coord(cursor_x) orelse break;
                const available: u16 = @intCast(@min(right - cursor_x, @as(u32, std.math.maxInt(u16))));
                const clipped = text_metrics.truncateToWidth(segment.text, available, scratch[0..], false);
                if (clipped.len == 0) break;
                renderer.drawStr(draw_x, draw_y, clipped, segment.color, bg, segment.style);
                const width = text_metrics.measureWidth(clipped).width;
                if (width == 0) break;
                cursor_x += width;
            }
        }
    }

    fn handleEventFn(_: *anyopaque, _: input.Event) anyerror!bool {
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Markdown = @fieldParentPtr("widget", widget_ref);
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
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *Markdown = @fieldParentPtr("widget", widget_ref);
        return self.get_preferred_dimensions();
    }

    fn canFocusFn(_: *anyopaque) bool {
        return false;
    }

    fn u16Coord(value: u32) ?u16 {
        if (value > std.math.maxInt(u16)) return null;
        return @intCast(value);
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

test "markdown clips edge coordinates before u16 overflow" {
    const alloc = std.testing.allocator;
    var md = try Markdown.init(alloc, "# Title\n- item");
    defer md.deinit();

    var renderer = try render.Renderer.init(alloc, 4, 2);
    defer renderer.deinit();

    try md.widget.layout(layout_module.Rect.init(std.math.maxInt(u16) - 1, 0, 4, 2));
    try md.widget.draw(&renderer);

    try md.widget.layout(layout_module.Rect.init(0, std.math.maxInt(u16) - 1, 4, 2));
    try md.widget.draw(&renderer);
}

fn markdownInitAllocationFailureHarness(allocator: std.mem.Allocator) !void {
    var md = try Markdown.init(allocator, "# Title\n- **bold**\n> quote\n`code`");
    defer md.deinit();

    try std.testing.expect(md.lines.items.len >= 4);
    try std.testing.expect(md.lines.items[1].segments.items.len >= 2);
}

test "markdown init cleans up every allocation failure path" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, markdownInitAllocationFailureHarness, .{});
}

test "markdown setText preserves parsed content on allocation failure" {
    const alloc = std.testing.allocator;
    var md = try Markdown.init(alloc, "# Stable\n- item");
    defer md.deinit();

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 1 });
    md.allocator = failing.allocator();

    try std.testing.expectError(error.OutOfMemory, md.setText("## Replacement\n- next"));
    try std.testing.expectEqualStrings("# Stable\n- item", md.content);
    try std.testing.expect(md.lines.items.len > 0);
}
