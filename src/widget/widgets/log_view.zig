const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const testing = @import("../../testing/testing.zig");

/// LogView renders append-only log lines with automatic scrolling.
pub const LogView = struct {
    pub const Level = enum { info, warn, err, debug };
    const Entry = struct { level: Level, text: []const u8 };

    widget: base.Widget,
    entries: std.ArrayList(Entry),
    max_entries: usize = 512,
    scroll_offset: usize = 0,
    auto_scroll: bool = true,
    fg: render.Color = render.Color.named(render.NamedColor.default),
    bg: render.Color = render.Color.named(render.NamedColor.black),
    allocator: std.mem.Allocator,

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator) !*LogView {
        const self = try allocator.create(LogView);
        self.* = LogView{
            .widget = base.Widget.init(&vtable),
            .entries = std.ArrayList(Entry).empty,
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *LogView) void {
        self.clear();
        self.entries.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn append(self: *LogView, level: Level, message: []const u8) !void {
        const owned = try self.allocator.dupe(u8, message);
        errdefer self.allocator.free(owned);

        if (self.entries.items.len >= self.max_entries) {
            const removed = self.entries.orderedRemove(0);
            self.allocator.free(removed.text);
        }

        try self.entries.append(self.allocator, .{ .level = level, .text = owned });
        if (self.auto_scroll) {
            self.scroll_offset = 0;
        } else {
            const visible = self.visibleLines();
            const max_offset: usize = if (self.entries.items.len > visible) self.entries.items.len - visible else 0;
            if (self.scroll_offset > max_offset) self.scroll_offset = max_offset;
        }
    }

    pub fn appendText(self: *LogView, message: []const u8) !void {
        try self.append(.info, message);
    }

    pub fn setMaxEntries(self: *LogView, max_entries: usize) void {
        self.max_entries = @max(max_entries, 1);
        while (self.entries.items.len > self.max_entries) {
            const removed = self.entries.orderedRemove(0);
            self.allocator.free(removed.text);
        }
        const visible = self.visibleLines();
        const max_offset: usize = if (self.entries.items.len > visible) self.entries.items.len - visible else 0;
        if (self.scroll_offset > max_offset) self.scroll_offset = max_offset;
        self.auto_scroll = self.scroll_offset == 0;
    }

    pub fn clear(self: *LogView) void {
        for (self.entries.items) |entry| self.allocator.free(entry.text);
        self.entries.clearRetainingCapacity();
        self.scroll_offset = 0;
    }

    fn visibleLines(self: *const LogView) usize {
        if (self.widget.rect.height == 0) return 0;
        return @intCast(self.widget.rect.height);
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*LogView, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;
        const rect = self.widget.rect;
        if (rect.width == 0 or rect.height == 0) return;

        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', self.fg, self.bg, render.Style{});

        if (self.entries.items.len == 0) {
            renderer.drawStr(rect.x, rect.y, "(no logs yet)", render.Color.named(render.NamedColor.bright_black), self.bg, render.Style{ .italic = true });
            return;
        }

        const visible = self.visibleLines();
        const start = startIndex(self.entries.items.len, visible, self.scroll_offset);
        const end = @min(self.entries.items.len, start + visible);

        var row: u16 = 0;
        var idx: usize = start;
        while (idx < end) : (idx += 1) {
            const entry = self.entries.items[idx];
            const y = rect.y + row;
            const level_label = levelText(entry.level);
            const level_color = levelColor(entry.level);
            const label_len: u16 = @intCast(level_label.len);
            const available = rect.width;
            if (available == 0) break;

            renderer.drawStr(rect.x, y, level_label[0..@min(level_label.len, available)], level_color, self.bg, render.Style{ .bold = true });

            if (available > label_len + 1) {
                const max_text = available - label_len - 1;
                renderer.drawStr(rect.x + label_len + 1, y, entry.text[0..@min(entry.text.len, max_text)], self.fg, self.bg, render.Style{});
            }
            row += 1;
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*LogView, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible or !self.widget.enabled) return false;

        switch (event) {
            .mouse => |mouse| {
                switch (mouse.action) {
                    .scroll_up => {
                        self.scrollLines(1);
                        return true;
                    },
                    .scroll_down => {
                        self.scrollLines(-1);
                        return true;
                    },
                    else => {},
                }
            },
            .key => |key| {
                if (!self.widget.focused) return false;
                switch (key.key) {
                    input.KeyCode.PAGE_UP => {
                        self.scrollLines(@intCast(self.widget.rect.height));
                        return true;
                    },
                    input.KeyCode.PAGE_DOWN => {
                        self.scrollLines(-@as(isize, @intCast(self.widget.rect.height)));
                        return true;
                    },
                    input.KeyCode.HOME => {
                        self.scroll_offset = self.entries.items.len;
                        self.auto_scroll = false;
                        return true;
                    },
                    input.KeyCode.END => {
                        self.scroll_offset = 0;
                        self.auto_scroll = true;
                        return true;
                    },
                    else => {},
                }
            },
            else => {},
        }

        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*LogView, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(_: *anyopaque) anyerror!layout_module.Size {
        return layout_module.Size.init(40, 8);
    }

    fn canFocusFn(_: *anyopaque) bool {
        return true;
    }

    fn levelText(level: Level) []const u8 {
        return switch (level) {
            .info => "[INFO]",
            .warn => "[WARN]",
            .err => "[ERR ]",
            .debug => "[DBG ]",
        };
    }

    fn levelColor(level: Level) render.Color {
        return switch (level) {
            .info => render.Color.named(render.NamedColor.bright_black),
            .warn => render.Color.named(render.NamedColor.yellow),
            .err => render.Color.named(render.NamedColor.red),
            .debug => render.Color.named(render.NamedColor.cyan),
        };
    }

    fn startIndex(total: usize, visible: usize, offset: usize) usize {
        if (visible >= total) return 0;
        const clamped_offset = @min(offset, total - visible);
        return total - visible - clamped_offset;
    }

    fn scrollLines(self: *LogView, delta: isize) void {
        const visible = self.visibleLines();
        const max_offset: isize = if (self.entries.items.len > visible) @intCast(self.entries.items.len - visible) else 0;
        const next = std.math.clamp(@as(isize, @intCast(self.scroll_offset)) + delta, 0, max_offset);
        self.scroll_offset = @intCast(next);
        self.auto_scroll = self.scroll_offset == 0;
    }
};

test "log view auto scrolls to newest entries" {
    const alloc = std.testing.allocator;
    var log = try LogView.init(alloc);
    defer log.deinit();

    try log.appendText("first");
    try log.append(.warn, "second");
    try log.append(.err, "third");

    try log.widget.layout(layout_module.Rect.init(0, 0, 14, 2));

    var snap = try testing.renderWidget(alloc, &log.widget, layout_module.Size.init(14, 2));
    defer snap.deinit(alloc);

    try snap.expectEqual(
        \\[WARN] second 
        \\[ERR ] third  
        \\
    );
}
