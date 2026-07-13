const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const testing = @import("../../testing/testing.zig");
const accessibility = @import("../accessibility.zig");

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
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.status), "Log view", "");
        return self;
    }

    pub fn deinit(self: *LogView) void {
        self.clear();
        self.entries.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn append(self: *LogView, level: Level, message: []const u8) !void {
        try self.entries.ensureUnusedCapacity(self.allocator, 1);
        const owned = try self.allocator.dupe(u8, message);
        errdefer self.allocator.free(owned);

        if (self.entries.items.len >= self.max_entries) {
            const removed = self.entries.orderedRemove(0);
            self.allocator.free(removed.text);
        }

        self.entries.appendAssumeCapacity(.{ .level = level, .text = owned });
        if (self.auto_scroll) {
            self.scroll_offset = 0;
        } else {
            const visible = self.visibleLines();
            const max_offset: usize = if (self.entries.items.len > visible) self.entries.items.len - visible else 0;
            if (self.scroll_offset > max_offset) self.scroll_offset = max_offset;
        }
        self.widget.markDirty();
    }

    pub fn appendText(self: *LogView, message: []const u8) !void {
        try self.append(.info, message);
    }

    pub fn setMaxEntries(self: *LogView, max_entries: usize) void {
        self.max_entries = @max(max_entries, 1);
        const previous_len = self.entries.items.len;
        const previous_scroll_offset = self.scroll_offset;
        const previous_auto_scroll = self.auto_scroll;
        while (self.entries.items.len > self.max_entries) {
            const removed = self.entries.orderedRemove(0);
            self.allocator.free(removed.text);
        }
        const visible = self.visibleLines();
        const max_offset: usize = if (self.entries.items.len > visible) self.entries.items.len - visible else 0;
        if (self.scroll_offset > max_offset) self.scroll_offset = max_offset;
        self.auto_scroll = self.scroll_offset == 0;
        if (self.entries.items.len != previous_len or self.scroll_offset != previous_scroll_offset or self.auto_scroll != previous_auto_scroll) {
            self.widget.markDirty();
        }
    }

    pub fn clear(self: *LogView) void {
        const had_visible_state = self.entries.items.len > 0 or self.scroll_offset != 0 or !self.auto_scroll;
        for (self.entries.items) |entry| self.allocator.free(entry.text);
        self.entries.clearRetainingCapacity();
        self.scroll_offset = 0;
        self.auto_scroll = true;
        if (had_visible_state) self.widget.markDirty();
    }

    fn visibleLines(self: *const LogView) usize {
        if (self.widget.rect.height == 0) return 0;
        return @intCast(self.widget.rect.height);
    }

    fn maxScrollOffset(self: *const LogView) usize {
        const visible = self.visibleLines();
        if (visible == 0) return 0;
        return if (self.entries.items.len > visible) self.entries.items.len - visible else 0;
    }

    fn addOffsetClamped(origin: u16, offset: u16) u16 {
        const value = @as(u32, origin) + @as(u32, offset);
        return @intCast(@min(value, @as(u32, std.math.maxInt(u16))));
    }

    fn addUsizeSaturating(a: usize, b: usize) usize {
        return std.math.add(usize, a, b) catch std.math.maxInt(usize);
    }

    fn applyScrollDelta(current: usize, delta: isize, max_offset: usize) usize {
        const clamped_current = @min(current, max_offset);
        if (delta >= 0) {
            const positive_delta: usize = @intCast(delta);
            return @min(addUsizeSaturating(clamped_current, positive_delta), max_offset);
        }

        const magnitude: usize = @intCast(-(delta + 1));
        return clamped_current -| (magnitude + 1);
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *LogView = @fieldParentPtr("widget", widget_ref);
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
            const y = addOffsetClamped(rect.y, row);
            const level_label = levelText(entry.level);
            const level_color = levelColor(entry.level);
            const available = rect.width;
            if (available == 0) break;

            const clipped_level = render.clipTextToWidth(level_label, available);
            renderer.drawStr(rect.x, y, clipped_level.text, level_color, self.bg, render.Style{ .bold = true });

            if (available > clipped_level.width + 1) {
                const max_text = available - clipped_level.width - 1;
                const text_x = addOffsetClamped(rect.x, clipped_level.width + 1);
                const clipped_text = render.clipTextToWidth(entry.text, max_text);
                renderer.drawStr(text_x, y, clipped_text.text, self.fg, self.bg, render.Style{});
            }
            row += 1;
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *LogView = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible or !self.widget.enabled) return false;

        switch (event) {
            .mouse => |mouse| {
                switch (mouse.action) {
                    .scroll_up => {
                        return self.scrollLines(1);
                    },
                    .scroll_down => {
                        return self.scrollLines(-1);
                    },
                    else => {},
                }
            },
            .key => |key| {
                if (!self.widget.focused) return false;
                switch (key.key) {
                    input.KeyCode.PAGE_UP => {
                        return self.scrollLines(@intCast(self.widget.rect.height));
                    },
                    input.KeyCode.PAGE_DOWN => {
                        return self.scrollLines(-@as(isize, @intCast(self.widget.rect.height)));
                    },
                    input.KeyCode.HOME => {
                        const max_offset = self.maxScrollOffset();
                        return self.setScrollOffset(max_offset, max_offset == 0);
                    },
                    input.KeyCode.END => {
                        return self.setScrollOffset(0, true);
                    },
                    else => {},
                }
            },
            else => {},
        }

        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *LogView = @fieldParentPtr("widget", widget_ref);
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

    fn setScrollOffset(self: *LogView, offset: usize, auto_scroll: bool) bool {
        const clamped = @min(offset, self.maxScrollOffset());
        if (self.scroll_offset == clamped and self.auto_scroll == auto_scroll) return false;
        self.scroll_offset = clamped;
        self.auto_scroll = auto_scroll;
        self.widget.markDirty();
        return true;
    }

    fn scrollLines(self: *LogView, delta: isize) bool {
        const max_offset = self.maxScrollOffset();
        const next_offset = applyScrollDelta(self.scroll_offset, delta, max_offset);
        return self.setScrollOffset(next_offset, next_offset == 0);
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

test "log view clips unicode message after level cell geometry" {
    const alloc = std.testing.allocator;
    var log = try LogView.init(alloc);
    defer log.deinit();
    try log.append(.info, "界e\u{301}👩‍💻");

    try log.widget.layout(layout_module.Rect.init(0, 0, 10, 1));
    var renderer = try render.Renderer.init(alloc, 10, 1);
    defer renderer.deinit();
    try log.widget.draw(&renderer);

    try std.testing.expectEqualStrings("界", renderer.back.getCell(7, 0).glyph.slice());
    try std.testing.expect(renderer.back.getCell(8, 0).continuation);
    try std.testing.expectEqualStrings("e\u{301}", renderer.back.getCell(9, 0).glyph.slice());
}

test "log view mouse wheel scrolls rendered viewport" {
    const alloc = std.testing.allocator;
    var log = try LogView.init(alloc);
    defer log.deinit();

    try log.appendText("first");
    try log.appendText("second");
    try log.appendText("third");
    try log.appendText("fourth");
    try log.widget.layout(layout_module.Rect.init(3, 2, 12, 2));

    try std.testing.expectEqual(@as(usize, 0), log.scroll_offset);
    try std.testing.expect(try log.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.scroll_up, 4, 2, 0, -1) }));
    try std.testing.expectEqual(@as(usize, 1), log.scroll_offset);
}

test "log view scroll input invalidates only changed viewports" {
    const alloc = std.testing.allocator;
    var log = try LogView.init(alloc);
    defer log.deinit();

    try log.appendText("first");
    try log.appendText("second");
    try log.appendText("third");
    try log.appendText("fourth");
    try log.widget.layout(layout_module.Rect.init(0, 0, 18, 2));
    log.widget.focused = true;

    var renderer = try render.Renderer.init(alloc, 18, 2);
    defer renderer.deinit();
    try log.widget.draw(&renderer);
    try std.testing.expect(!log.widget.dirty);

    const page_up = input.Event{ .key = input.KeyEvent.init(input.KeyCode.PAGE_UP, .{}) };
    try std.testing.expect(try log.widget.handleEvent(page_up));
    try std.testing.expectEqual(@as(usize, 2), log.scroll_offset);
    try std.testing.expect(!log.auto_scroll);
    try std.testing.expect(log.widget.dirty);

    try log.widget.draw(&renderer);
    try std.testing.expect(!log.widget.dirty);
    try std.testing.expect(!try log.widget.handleEvent(page_up));
    try std.testing.expectEqual(@as(usize, 2), log.scroll_offset);
    try std.testing.expect(!log.widget.dirty);

    const end = input.Event{ .key = input.KeyEvent.init(input.KeyCode.END, .{}) };
    try std.testing.expect(try log.widget.handleEvent(end));
    try std.testing.expectEqual(@as(usize, 0), log.scroll_offset);
    try std.testing.expect(log.auto_scroll);
    try std.testing.expect(log.widget.dirty);

    try log.widget.draw(&renderer);
    try std.testing.expect(!log.widget.dirty);
    try std.testing.expect(!try log.widget.handleEvent(end));
    try std.testing.expect(!log.widget.dirty);
}

test "log view ignores zero-height page scrolls" {
    const alloc = std.testing.allocator;
    var log = try LogView.init(alloc);
    defer log.deinit();

    try log.appendText("first");
    try log.appendText("second");
    try log.widget.layout(layout_module.Rect.init(0, 0, 18, 0));
    log.widget.focused = true;
    log.widget.clearDirty();

    const page_up = input.Event{ .key = input.KeyEvent.init(input.KeyCode.PAGE_UP, .{}) };
    try std.testing.expect(!try log.widget.handleEvent(page_up));
    try std.testing.expectEqual(@as(usize, 0), log.scroll_offset);
    try std.testing.expect(log.auto_scroll);
    try std.testing.expect(!log.widget.dirty);

    const home = input.Event{ .key = input.KeyEvent.init(input.KeyCode.HOME, .{}) };
    try std.testing.expect(!try log.widget.handleEvent(home));
    try std.testing.expectEqual(@as(usize, 0), log.scroll_offset);
    try std.testing.expect(log.auto_scroll);
    try std.testing.expect(!log.widget.dirty);
}

test "log view marks dirty when visible content changes" {
    const alloc = std.testing.allocator;
    var log = try LogView.init(alloc);
    defer log.deinit();

    try log.widget.layout(layout_module.Rect.init(0, 0, 18, 2));
    var renderer = try render.Renderer.init(alloc, 18, 2);
    defer renderer.deinit();

    try log.widget.draw(&renderer);
    try std.testing.expect(!log.widget.dirty);

    try log.appendText("first");
    try std.testing.expect(log.widget.dirty);

    try log.widget.draw(&renderer);
    try std.testing.expect(!log.widget.dirty);

    log.clear();
    try std.testing.expect(log.widget.dirty);

    try log.widget.draw(&renderer);
    try std.testing.expect(!log.widget.dirty);
    log.clear();
    try std.testing.expect(!log.widget.dirty);
}

test "log view set max entries invalidates trimmed visible rows" {
    const alloc = std.testing.allocator;
    var log = try LogView.init(alloc);
    defer log.deinit();

    try log.widget.layout(layout_module.Rect.init(0, 0, 18, 3));
    try log.appendText("one");
    try log.appendText("two");
    try log.appendText("three");

    var renderer = try render.Renderer.init(alloc, 18, 3);
    defer renderer.deinit();
    try log.widget.draw(&renderer);
    try std.testing.expect(!log.widget.dirty);

    log.setMaxEntries(2);
    try std.testing.expect(log.widget.dirty);
    try std.testing.expectEqual(@as(usize, 2), log.entries.items.len);
    try std.testing.expectEqualStrings("two", log.entries.items[0].text);
}

test "log view clear restores auto scroll mode" {
    const alloc = std.testing.allocator;
    var log = try LogView.init(alloc);
    defer log.deinit();

    try log.appendText("one");
    try log.appendText("two");
    try log.widget.layout(layout_module.Rect.init(0, 0, 10, 1));

    _ = log.scrollLines(1);
    try std.testing.expect(!log.auto_scroll);

    log.clear();
    try std.testing.expect(log.auto_scroll);
    try std.testing.expectEqual(@as(usize, 0), log.scroll_offset);
}

test "log view clamps edge draw coordinates" {
    const alloc = std.testing.allocator;
    var log = try LogView.init(alloc);
    defer log.deinit();

    try log.append(.info, "edge");
    try log.append(.warn, "coordinates");
    try log.widget.layout(layout_module.Rect.init(std.math.maxInt(u16), std.math.maxInt(u16), 12, 2));

    var renderer = try render.Renderer.init(alloc, 2, 2);
    defer renderer.deinit();

    try log.widget.draw(&renderer);
    try std.testing.expectEqual(@as(u21, ' '), renderer.back.getCell(0, 0).codepoint());
    try std.testing.expectEqual(@as(u21, ' '), renderer.back.getCell(1, 1).codepoint());
}

test "log view saturates oversized scroll offsets" {
    const alloc = std.testing.allocator;
    var log = try LogView.init(alloc);
    defer log.deinit();

    try log.appendText("one");
    try log.appendText("two");
    try log.appendText("three");
    try log.appendText("four");
    try log.widget.layout(layout_module.Rect.init(0, 0, 10, 2));

    log.scroll_offset = std.math.maxInt(usize);
    _ = log.scrollLines(1);
    try std.testing.expectEqual(@as(usize, 2), log.scroll_offset);
    try std.testing.expect(!log.auto_scroll);

    log.scroll_offset = std.math.maxInt(usize);
    _ = log.scrollLines(-1);
    try std.testing.expectEqual(@as(usize, 1), log.scroll_offset);
}

fn logViewAppendAllocationFailureHarness(allocator: std.mem.Allocator) !void {
    var log = try LogView.init(allocator);
    defer log.deinit();

    try log.appendText("first");
    try log.append(.warn, "second");
}

test "log view append cleans up every allocation failure path" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, logViewAppendAllocationFailureHarness, .{});
}

test "log view append preserves full log on entry allocation failure" {
    const alloc = std.testing.allocator;
    var log = try LogView.init(alloc);
    defer log.deinit();

    try log.appendText("stable");
    log.setMaxEntries(1);
    log.entries.shrinkAndFree(alloc, log.entries.items.len);
    try std.testing.expectEqual(log.entries.items.len, log.entries.capacity);

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = log.allocator;
    log.allocator = failing.allocator();
    defer log.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, log.append(.err, "replacement"));
    try std.testing.expectEqual(@as(usize, 1), log.entries.items.len);
    try std.testing.expectEqual(LogView.Level.info, log.entries.items[0].level);
    try std.testing.expectEqualStrings("stable", log.entries.items[0].text);
}

test "log view append preserves full log on message allocation failure" {
    const alloc = std.testing.allocator;
    var log = try LogView.init(alloc);
    defer log.deinit();

    try log.appendText("stable");
    log.setMaxEntries(1);
    try log.entries.ensureUnusedCapacity(alloc, 1);

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = log.allocator;
    log.allocator = failing.allocator();
    defer log.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, log.append(.err, "replacement"));
    try std.testing.expectEqual(@as(usize, 1), log.entries.items.len);
    try std.testing.expectEqual(LogView.Level.info, log.entries.items[0].level);
    try std.testing.expectEqualStrings("stable", log.entries.items[0].text);
}
