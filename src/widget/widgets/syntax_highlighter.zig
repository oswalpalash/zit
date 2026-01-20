const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");

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
        return self;
    }

    pub fn deinit(self: *SyntaxHighlighter) void {
        self.freeCode();
        self.allocator.destroy(self);
    }

    pub fn setCode(self: *SyntaxHighlighter, code: []const u8) !void {
        self.freeCode();
        if (code.len == 0) {
            self.code = &[_]u8{};
            return;
        }
        self.code = try self.allocator.dupe(u8, code);
    }

    pub fn setLanguage(self: *SyntaxHighlighter, language: Language) void {
        self.language = language;
    }

    pub fn setWrap(self: *SyntaxHighlighter, wrap: bool) void {
        self.wrap = wrap;
    }

    pub fn setColors(self: *SyntaxHighlighter, fg: render.Color, bg: render.Color, keyword: render.Color, string: render.Color, comment: render.Color, number: render.Color) void {
        self.fg = fg;
        self.bg = bg;
        self.keyword_color = keyword;
        self.string_color = string;
        self.comment_color = comment;
        self.number_color = number;
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*SyntaxHighlighter, @ptrCast(@alignCast(widget_ptr)));
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

        const start_x = rect.x + inset;
        const start_y = rect.y + inset;
        const max_x = start_x + content_width - 1;
        const max_y = start_y + content_height - 1;

        var state: State = .normal;
        var x = start_x;
        var y = start_y;
        var i: usize = 0;

        while (i < self.code.len) : (i += 1) {
            if (y > max_y) break;
            const ch = self.code[i];

            // Handle newlines
            if (ch == '\n') {
                state = if (state == .comment) .normal else state;
                x = start_x;
                y += 1;
                continue;
            }

            // Handle tabs
            if (ch == '\t') {
                const spaces_needed = self.tab_width - @as(u8, @intCast((x - start_x) % self.tab_width));
                var s: u8 = 0;
                while (s < spaces_needed) : (s += 1) {
                    if (x > max_x) {
                        if (self.wrap) {
                            x = start_x;
                            y += 1;
                            if (y > max_y) break;
                        } else break;
                    }
                    renderer.drawChar(x, y, ' ', self.fg, self.bg, render.Style{});
                    x += 1;
                }
                continue;
            }

            if (x > max_x) {
                if (self.wrap) {
                    x = start_x;
                    y += 1;
                    if (y > max_y) break;
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
                        while (n < len and x <= max_x and y <= max_y) : (n += 1) {
                            renderer.drawChar(x, y, self.code[i + n], fg, self.bg, style);
                            x += 1;
                            if (x > max_x and self.wrap and n + 1 < len) {
                                x = start_x;
                                y += 1;
                                if (y > max_y) break;
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
                        while (n < word_len and x <= max_x and y <= max_y) : (n += 1) {
                            renderer.drawChar(x, y, self.code[i + n], fg, self.bg, style);
                            x += 1;
                            if (x > max_x and self.wrap and n + 1 < word_len) {
                                x = start_x;
                                y += 1;
                                if (y > max_y) break;
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
            renderer.drawChar(x, y, ch, draw_color, self.bg, draw_style);
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
        const self = @as(*SyntaxHighlighter, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*SyntaxHighlighter, @ptrCast(@alignCast(widget_ptr)));

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

        return layout_module.Size.init(@intCast(@max(max_width + 2, 24)), @intCast(@max(lines, 3)));
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
