const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const accessibility = @import("../accessibility.zig");

/// Syntax highlighting widget for displaying code snippets.
pub const SyntaxHighlighter = struct {
    widget: base.Widget,
    allocator: std.mem.Allocator,
    code: []u8 = &[_]u8{},
    language: Language = .zig,
    wrap: bool = true,
    tab_width: u8 = 4,
    border: render.BorderStyle = .single,
    bg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    fg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    keyword_color: render.Color = render.Color{ .named_color = render.NamedColor.cyan },
    string_color: render.Color = render.Color{ .named_color = render.NamedColor.yellow },
    comment_color: render.Color = render.Color{ .named_color = render.NamedColor.bright_black },
    number_color: render.Color = render.Color{ .named_color = render.NamedColor.magenta },

    pub const Language = enum { zig, json, plain };

    const State = enum { normal, string, comment };

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator) !*SyntaxHighlighter {
        const self = try allocator.create(SyntaxHighlighter);
        self.* = SyntaxHighlighter{
            .widget = base.Widget.init(&vtable),
            .allocator = allocator,
        };
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.status), "Syntax highlighter", "");
        return self;
    }

    pub fn deinit(self: *SyntaxHighlighter) void {
        self.freeCode();
        self.allocator.destroy(self);
    }

    pub fn setCode(self: *SyntaxHighlighter, code: []const u8) !void {
        if (std.mem.eql(u8, self.code, code)) return;
        const next: []u8 = if (code.len == 0) &[_]u8{} else try self.allocator.dupe(u8, code);
        self.freeCode();
        self.code = next;
        self.widget.markDirty();
    }

    pub fn setLanguage(self: *SyntaxHighlighter, language: Language) void {
        if (self.language == language) return;
        self.language = language;
        self.widget.markDirty();
    }

    pub fn setWrap(self: *SyntaxHighlighter, wrap: bool) void {
        if (self.wrap == wrap) return;
        self.wrap = wrap;
        self.widget.markDirty();
    }

    pub fn setColors(self: *SyntaxHighlighter, fg: render.Color, bg: render.Color, keyword: render.Color, string: render.Color, comment: render.Color, number: render.Color) void {
        if (std.meta.eql(self.fg, fg) and std.meta.eql(self.bg, bg) and std.meta.eql(self.keyword_color, keyword) and std.meta.eql(self.string_color, string) and std.meta.eql(self.comment_color, comment) and std.meta.eql(self.number_color, number)) return;
        self.fg = fg;
        self.bg = bg;
        self.keyword_color = keyword;
        self.string_color = string;
        self.comment_color = comment;
        self.number_color = number;
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

    fn addUsizeClamped(a: usize, b: usize) usize {
        return std.math.add(usize, a, b) catch std.math.maxInt(usize);
    }

    fn clampUsizeToU16(value: usize) u16 {
        return @intCast(@min(value, @as(usize, std.math.maxInt(u16))));
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *SyntaxHighlighter = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible) return;

        const rect = self.widget.rect;
        if (rect.width == 0 or rect.height == 0) return;

        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', self.fg, self.bg, render.Style{});

        const has_border = self.border != .none and rect.width >= 2 and rect.height >= 2;
        const inset: u16 = if (has_border) 1 else 0;
        if (has_border) {
            renderer.drawBox(rect.x, rect.y, rect.width, rect.height, self.border, self.fg, self.bg, render.Style{});
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

        var state: State = .normal;
        var x = start_x_u32;
        var y = start_y_u32;
        var i: usize = 0;

        while (i < self.code.len) : (i += 1) {
            if (y > max_y_u32) break;
            const ch = self.code[i];

            // Handle newlines
            if (ch == '\n') {
                state = if (state == .comment) .normal else state;
                x = start_x_u32;
                y += 1;
                continue;
            }

            // Handle tabs
            if (ch == '\t') {
                const tab_width = @max(self.tab_width, 1);
                const spaces_needed = tab_width - @as(u8, @intCast((x - start_x_u32) % tab_width));
                var s: u8 = 0;
                while (s < spaces_needed) : (s += 1) {
                    if (x > max_x_u32) {
                        if (self.wrap) {
                            x = start_x_u32;
                            y += 1;
                            if (y > max_y_u32) break;
                        } else break;
                    }
                    renderer.drawChar(@intCast(x), @intCast(y), ' ', self.fg, self.bg, render.Style{});
                    x += 1;
                }
                continue;
            }

            if (x > max_x_u32) {
                if (self.wrap) {
                    x = start_x_u32;
                    y += 1;
                    if (y > max_y_u32) break;
                } else {
                    continue;
                }
            }

            // Detect state transitions
            if (state == .normal) {
                if (ch == '/' and i + 1 < self.code.len and self.code[i + 1] == '/') {
                    state = .comment;
                } else if (ch == '"') {
                    state = .string;
                }
            } else if (state == .string and ch == '"' and (i == 0 or self.code[i - 1] != '\\')) {
                state = .normal;
            }

            // Token based coloring
            var fg = self.fg;
            var style = render.Style{};
            switch (state) {
                .comment => fg = self.comment_color,
                .string => fg = self.string_color,
                .normal => {
                    if (isDigit(ch)) {
                        const len = numberLength(self.code[i..]);
                        fg = self.number_color;
                        style = render.Style{ .bold = false };
                        var n: usize = 0;
                        while (n < len and x <= max_x_u32 and y <= max_y_u32) : (n += 1) {
                            renderer.drawChar(@intCast(x), @intCast(y), self.code[i + n], fg, self.bg, style);
                            x += 1;
                            if (x > max_x_u32 and self.wrap and n + 1 < len) {
                                x = start_x_u32;
                                y += 1;
                                if (y > max_y_u32) break;
                            }
                        }
                        i += len - 1;
                        continue;
                    } else if (isIdentStart(ch)) {
                        const word_len = identLength(self.code[i..]);
                        const word = self.code[i .. i + word_len];
                        if (isKeyword(self.language, word)) {
                            fg = self.keyword_color;
                            style = render.Style{ .bold = true };
                        }
                        var n: usize = 0;
                        while (n < word_len and x <= max_x_u32 and y <= max_y_u32) : (n += 1) {
                            renderer.drawChar(@intCast(x), @intCast(y), self.code[i + n], fg, self.bg, style);
                            x += 1;
                            if (x > max_x_u32 and self.wrap and n + 1 < word_len) {
                                x = start_x_u32;
                                y += 1;
                                if (y > max_y_u32) break;
                            }
                        }
                        i += word_len - 1;
                        continue;
                    }
                },
            }

            const draw_color = switch (state) {
                .comment => self.comment_color,
                .string => self.string_color,
                .normal => fg,
            };
            const draw_style = if (state == .comment or state == .string) render.Style{} else style;
            renderer.drawChar(@intCast(x), @intCast(y), ch, draw_color, self.bg, draw_style);
            x += 1;
        }
    }

    fn isDigit(ch: u8) bool {
        return ch >= '0' and ch <= '9';
    }

    fn isIdentStart(ch: u8) bool {
        return (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or ch == '_';
    }

    fn identLength(slice: []const u8) usize {
        var len: usize = 0;
        while (len < slice.len) : (len += 1) {
            const ch = slice[len];
            if (isIdentStart(ch) or isDigit(ch)) {
                continue;
            }
            break;
        }
        return len;
    }

    fn numberLength(slice: []const u8) usize {
        var len: usize = 0;
        while (len < slice.len) : (len += 1) {
            const ch = slice[len];
            if (isDigit(ch) or ch == '.' or ch == 'x' or ch == 'b' or ch == 'o' or ch == '_') {
                continue;
            }
            break;
        }
        return len;
    }

    fn isKeyword(language: Language, word: []const u8) bool {
        const zig_keywords = [_][]const u8{
            "const",  "var",  "pub",   "fn",   "struct",         "enum",  "union",    "if",    "else", "switch", "for", "while",
            "return", "true", "false", "null", "usingnamespace", "break", "continue", "defer",
        };

        const json_keywords = [_][]const u8{ "true", "false", "null" };

        return switch (language) {
            .zig => contains(&zig_keywords, word),
            .json => contains(&json_keywords, word),
            .plain => false,
        };
    }

    fn contains(list: []const []const u8, value: []const u8) bool {
        for (list) |item| {
            if (std.mem.eql(u8, item, value)) return true;
        }
        return false;
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        _ = widget_ptr;
        _ = event;
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *SyntaxHighlighter = @fieldParentPtr("widget", widget_ref);
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *SyntaxHighlighter = @fieldParentPtr("widget", widget_ref);

        var lines: usize = 1;
        var width: usize = 0;
        var max_width: usize = 0;

        for (self.code) |ch| {
            if (ch == '\n') {
                max_width = @max(max_width, width);
                width = 0;
                lines += 1;
            } else {
                width += 1;
            }
        }
        max_width = @max(max_width, width);

        const preferred_width = clampUsizeToU16(@max(addUsizeClamped(max_width, 2), 24));
        const preferred_height = clampUsizeToU16(@max(lines, 3));
        return layout_module.Size.init(preferred_width, preferred_height);
    }

    fn canFocusFn(_: *anyopaque) bool {
        return false;
    }

    fn freeCode(self: *SyntaxHighlighter) void {
        if (self.code.len > 0) {
            self.allocator.free(self.code);
        }
        self.code = &[_]u8{};
    }
};

test "syntax highlighter colors keywords and comments" {
    const alloc = std.testing.allocator;
    var highlighter = try SyntaxHighlighter.init(alloc);
    defer highlighter.deinit();

    try highlighter.setCode("const value: i32 = 5; // comment");
    try highlighter.widget.layout(layout_module.Rect.init(0, 0, 40, 3));

    var renderer = try render.Renderer.init(alloc, 40, 3);
    defer renderer.deinit();

    try highlighter.widget.draw(&renderer);

    const rect = highlighter.widget.rect;
    const inset: u16 = if (highlighter.border != .none and rect.width >= 2 and rect.height >= 2) 1 else 0;
    const start_x = rect.x + inset;
    const start_y = rect.y + inset;

    // Keyword "const" should be colored.
    const keyword_cell = renderer.back.getCell(start_x, start_y).*;
    try std.testing.expect(std.meta.eql(keyword_cell.fg, highlighter.keyword_color));

    // Comment area should use comment color.
    const comment_cell = renderer.back.getCell(start_x + 22, start_y).*;
    try std.testing.expect(std.meta.eql(comment_cell.fg, highlighter.comment_color));
}

test "syntax highlighter clamps far-edge render coordinates" {
    const alloc = std.testing.allocator;
    var highlighter = try SyntaxHighlighter.init(alloc);
    defer highlighter.deinit();

    try highlighter.setCode("12");
    try highlighter.widget.layout(layout_module.Rect.init(std.math.maxInt(u16), 0, 3, 3));

    var renderer = try render.Renderer.init(alloc, 4, 3);
    defer renderer.deinit();

    try highlighter.widget.draw(&renderer);
}

test "syntax highlighter preferred size saturates long content" {
    const alloc = std.testing.allocator;
    var highlighter = try SyntaxHighlighter.init(alloc);
    defer highlighter.deinit();

    const long_code = try alloc.alloc(u8, @as(usize, std.math.maxInt(u16)) + 128);
    defer alloc.free(long_code);
    @memset(long_code, 'x');

    try highlighter.setCode(long_code);
    var size = try highlighter.widget.getPreferredSize();
    try std.testing.expectEqual(@as(u16, std.math.maxInt(u16)), size.width);
    try std.testing.expectEqual(@as(u16, 3), size.height);

    @memset(long_code, '\n');

    try highlighter.setCode(long_code);
    size = try highlighter.widget.getPreferredSize();
    try std.testing.expectEqual(@as(u16, 24), size.width);
    try std.testing.expectEqual(@as(u16, std.math.maxInt(u16)), size.height);
}

test "syntax highlighter treats zero tab width as one column" {
    const alloc = std.testing.allocator;
    var highlighter = try SyntaxHighlighter.init(alloc);
    defer highlighter.deinit();

    highlighter.border = .none;
    highlighter.tab_width = 0;
    try highlighter.setCode("\t");
    try highlighter.widget.layout(layout_module.Rect.init(0, 0, 2, 1));

    var renderer = try render.Renderer.init(alloc, 2, 1);
    defer renderer.deinit();

    try highlighter.widget.draw(&renderer);
}

test "syntax highlighter marks dirty when code changes" {
    const alloc = std.testing.allocator;
    var highlighter = try SyntaxHighlighter.init(alloc);
    defer highlighter.deinit();

    try highlighter.widget.layout(layout_module.Rect.init(0, 0, 24, 3));
    var renderer = try render.Renderer.init(alloc, 24, 3);
    defer renderer.deinit();

    try highlighter.widget.draw(&renderer);
    try std.testing.expect(!highlighter.widget.dirty);

    try highlighter.setCode("const value = 1;");
    try std.testing.expect(highlighter.widget.dirty);

    try highlighter.widget.draw(&renderer);
    try std.testing.expect(!highlighter.widget.dirty);

    try highlighter.setCode("const value = 1;");
    try std.testing.expect(!highlighter.widget.dirty);

    try highlighter.setCode("");
    try std.testing.expect(highlighter.widget.dirty);
}

test "syntax highlighter marks dirty when rendering options change" {
    const alloc = std.testing.allocator;
    var highlighter = try SyntaxHighlighter.init(alloc);
    defer highlighter.deinit();

    try highlighter.setCode("true");
    try highlighter.widget.layout(layout_module.Rect.init(0, 0, 24, 3));
    var renderer = try render.Renderer.init(alloc, 24, 3);
    defer renderer.deinit();
    try highlighter.widget.draw(&renderer);
    try std.testing.expect(!highlighter.widget.dirty);

    highlighter.setLanguage(.json);
    try std.testing.expect(highlighter.widget.dirty);
    try highlighter.widget.draw(&renderer);
    try std.testing.expect(!highlighter.widget.dirty);
    highlighter.setLanguage(.json);
    try std.testing.expect(!highlighter.widget.dirty);

    highlighter.setWrap(false);
    try std.testing.expect(highlighter.widget.dirty);
    try highlighter.widget.draw(&renderer);
    try std.testing.expect(!highlighter.widget.dirty);
    highlighter.setWrap(false);
    try std.testing.expect(!highlighter.widget.dirty);

    highlighter.setColors(
        render.Color{ .named_color = render.NamedColor.white },
        render.Color{ .named_color = render.NamedColor.black },
        render.Color{ .named_color = render.NamedColor.green },
        render.Color{ .named_color = render.NamedColor.yellow },
        render.Color{ .named_color = render.NamedColor.bright_black },
        render.Color{ .named_color = render.NamedColor.magenta },
    );
    try std.testing.expect(highlighter.widget.dirty);
    try highlighter.widget.draw(&renderer);
    try std.testing.expect(!highlighter.widget.dirty);
    highlighter.setColors(
        render.Color{ .named_color = render.NamedColor.white },
        render.Color{ .named_color = render.NamedColor.black },
        render.Color{ .named_color = render.NamedColor.green },
        render.Color{ .named_color = render.NamedColor.yellow },
        render.Color{ .named_color = render.NamedColor.bright_black },
        render.Color{ .named_color = render.NamedColor.magenta },
    );
    try std.testing.expect(!highlighter.widget.dirty);
}

test "syntax highlighter setCode preserves code on allocation failure" {
    const alloc = std.testing.allocator;
    var highlighter = try SyntaxHighlighter.init(alloc);
    defer highlighter.deinit();

    try highlighter.setCode("const stable = true;");

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = highlighter.allocator;
    highlighter.allocator = failing.allocator();
    defer highlighter.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, highlighter.setCode("const replacement = false;"));
    try std.testing.expectEqualStrings("const stable = true;", highlighter.code);
}
