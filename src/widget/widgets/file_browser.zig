const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const text_metrics = @import("../../render/text_metrics.zig");
const input = @import("../../input/input.zig");
const compat = @import("../../compat.zig");
const accessibility = @import("../accessibility.zig");

/// File browser widget with basic directory navigation and selection.
pub const FileBrowser = struct {
    widget: base.Widget,
    allocator: std.mem.Allocator,
    current_path: []u8,
    entries: std.ArrayList(Entry),
    selected: usize = 0,
    scroll: usize = 0,
    visible_items: usize = 0,
    show_hidden: bool = false,
    border: render.BorderStyle = .single,
    fg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    bg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    highlight_fg: render.Color = render.Color{ .named_color = render.NamedColor.black },
    highlight_bg: render.Color = render.Color{ .named_color = render.NamedColor.cyan },
    border_color: render.Color = render.Color{ .named_color = render.NamedColor.default },
    header_style: render.Style = render.Style{ .bold = true },
    on_file_select: ?*const fn ([]const u8, bool) void = null,
    on_directory_change: ?*const fn ([]const u8) void = null,
    search_buffer: [64]u8 = undefined,
    search_len: usize = 0,
    last_search_ms: ?i64 = null,
    search_timeout_ms: u64 = 900,
    clock: *const fn () i64 = compat.nowMillis,

    pub const Entry = struct {
        name: []u8,
        is_dir: bool,
        is_parent: bool = false,
    };

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator, start_path: []const u8) !*FileBrowser {
        const normalized = try normalizePath(allocator, start_path);
        errdefer allocator.free(normalized);

        const self = try allocator.create(FileBrowser);
        errdefer allocator.destroy(self);

        self.* = FileBrowser{
            .widget = base.Widget.init(&vtable),
            .allocator = allocator,
            .current_path = normalized,
            .entries = std.ArrayList(Entry).empty,
        };
        errdefer self.entries.deinit(self.allocator);
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.list), "File browser", "");

        try self.refresh();
        return self;
    }

    pub fn deinit(self: *FileBrowser) void {
        self.clearEntries();
        self.allocator.free(self.current_path);
        self.entries.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn setColors(self: *FileBrowser, fg: render.Color, bg: render.Color, highlight_fg: render.Color, highlight_bg: render.Color) void {
        if (std.meta.eql(self.fg, fg) and
            std.meta.eql(self.bg, bg) and
            std.meta.eql(self.highlight_fg, highlight_fg) and
            std.meta.eql(self.highlight_bg, highlight_bg)) return;

        self.fg = fg;
        self.bg = bg;
        self.highlight_fg = highlight_fg;
        self.highlight_bg = highlight_bg;
        self.widget.markDirty();
    }

    pub fn setBorder(self: *FileBrowser, border: render.BorderStyle, border_color: render.Color) void {
        if (self.border == border and std.meta.eql(self.border_color, border_color)) return;
        self.border = border;
        self.border_color = border_color;
        self.widget.markDirty();
    }

    pub fn setShowHidden(self: *FileBrowser, show: bool) !void {
        if (self.show_hidden == show) return;
        const previous = self.show_hidden;
        self.show_hidden = show;
        self.refresh() catch |err| {
            self.show_hidden = previous;
            return err;
        };
    }

    pub fn setOnFileSelect(self: *FileBrowser, callback: *const fn ([]const u8, bool) void) void {
        self.on_file_select = callback;
    }

    pub fn setOnDirectoryChange(self: *FileBrowser, callback: *const fn ([]const u8) void) void {
        self.on_directory_change = callback;
    }

    pub fn setTypeaheadTimeout(self: *FileBrowser, timeout_ms: u64) void {
        self.search_timeout_ms = timeout_ms;
    }

    pub fn resetTypeahead(self: *FileBrowser) void {
        self.search_len = 0;
        self.last_search_ms = null;
    }

    pub fn setTypeaheadClock(self: *FileBrowser, clock: *const fn () i64) void {
        self.clock = clock;
    }

    pub fn setPath(self: *FileBrowser, path: []const u8) !void {
        const normalized = try normalizePath(self.allocator, path);
        errdefer self.allocator.free(normalized);

        var next_entries = try self.buildEntries(normalized);
        errdefer self.deinitEntries(&next_entries);

        const old_path = self.current_path;
        var old_entries = self.entries;
        self.current_path = normalized;
        self.entries = next_entries;
        self.selected = 0;
        self.scroll = 0;
        self.resetTypeahead();

        self.deinitEntries(&old_entries);
        self.allocator.free(old_path);

        if (self.on_directory_change) |cb| {
            cb(self.current_path);
        }
        self.widget.markDirty();
    }

    pub fn refresh(self: *FileBrowser) !void {
        var next_entries = try self.buildEntries(self.current_path);
        errdefer self.deinitEntries(&next_entries);

        var old_entries = self.entries;
        self.entries = next_entries;
        self.deinitEntries(&old_entries);

        self.clampSelection();

        self.resetTypeahead();
        self.ensureVisible();
        self.widget.markDirty();
    }

    fn buildEntries(self: *FileBrowser, path: []const u8) !std.ArrayList(Entry) {
        var entries = std.ArrayList(Entry).empty;
        errdefer self.deinitEntries(&entries);

        if (std.fs.path.dirname(path) != null) {
            try self.appendEntry(&entries, "..", true, true);
        }

        const io = std.Io.Threaded.global_single_threaded.io();
        const cwd = std.Io.Dir.cwd();
        var dir = try cwd.openDir(io, path, .{ .iterate = true });
        defer dir.close(io);

        var it = dir.iterate();
        while (try it.next(io)) |entry| {
            if (!self.show_hidden and entry.name.len > 0 and entry.name[0] == '.') continue;
            try self.appendEntry(&entries, entry.name, entry.kind == .directory, false);
        }

        // Sort directories first, then files alphabetically.
        const Ctx = struct {};
        std.sort.pdq(Entry, entries.items, Ctx{}, struct {
            fn lessThan(_: Ctx, a: Entry, b: Entry) bool {
                if (a.is_parent != b.is_parent) return a.is_parent;
                if (a.is_dir != b.is_dir) return a.is_dir;
                return std.ascii.lessThanIgnoreCase(a.name, b.name);
            }
        }.lessThan);

        return entries;
    }

    fn appendEntry(self: *FileBrowser, entries: *std.ArrayList(Entry), name: []const u8, is_dir: bool, is_parent: bool) !void {
        try entries.ensureUnusedCapacity(self.allocator, 1);
        const name_copy = try self.allocator.dupe(u8, name);
        entries.appendAssumeCapacity(.{
            .name = name_copy,
            .is_dir = is_dir,
            .is_parent = is_parent,
        });
    }

    fn clearEntries(self: *FileBrowser) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.name);
        }
        self.entries.clearRetainingCapacity();
    }

    fn deinitEntries(self: *FileBrowser, entries: *std.ArrayList(Entry)) void {
        for (entries.items) |entry| {
            self.allocator.free(entry.name);
        }
        entries.deinit(self.allocator);
    }

    fn normalizePath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
        if (path.len == 0) {
            return try allocator.dupe(u8, ".");
        }
        const io = std.Io.Threaded.global_single_threaded.io();
        const cwd = std.Io.Dir.cwd();
        const real = cwd.realPathFileAlloc(io, path, allocator) catch return try allocator.dupe(u8, path);
        defer allocator.free(real);
        return try allocator.dupe(u8, real);
    }

    fn parentPath(self: *FileBrowser) ![]u8 {
        if (std.fs.path.dirname(self.current_path)) |parent| {
            return try self.allocator.dupe(u8, parent);
        }
        return try self.allocator.dupe(u8, self.current_path);
    }

    fn joinPath(self: *FileBrowser, child: []const u8) ![]u8 {
        return try std.fs.path.join(self.allocator, &[_][]const u8{ self.current_path, child });
    }

    fn enterSelection(self: *FileBrowser) !void {
        if (self.entries.items.len == 0) return;
        self.clampSelection();
        const entry = self.entries.items[self.selected];

        if (entry.is_dir) {
            const next_path = if (entry.is_parent)
                try self.parentPath()
            else
                try self.joinPath(entry.name);

            defer self.allocator.free(next_path);
            try self.setPath(next_path);
        } else if (self.on_file_select) |cb| {
            const full_path = try self.joinPath(entry.name);
            defer self.allocator.free(full_path);
            cb(full_path, entry.is_dir);
        }
    }

    fn ensureVisible(self: *FileBrowser) void {
        if (self.visible_items == 0) return;
        if (self.selected < self.scroll) {
            self.scroll = self.selected;
        } else if (self.selected >= self.scroll + self.visible_items) {
            self.scroll = self.selected - self.visible_items + 1;
        }
    }

    fn clampSelection(self: *FileBrowser) void {
        if (self.entries.items.len == 0) {
            self.selected = 0;
            self.scroll = 0;
            return;
        }
        if (self.selected >= self.entries.items.len) {
            self.selected = self.entries.items.len - 1;
        }
        if (self.scroll >= self.entries.items.len) {
            self.scroll = self.selected;
        }
    }

    fn selectionStateChanged(self: *const FileBrowser, previous_selected: usize, previous_scroll: usize) bool {
        return previous_selected != self.selected or previous_scroll != self.scroll;
    }

    fn finishNavigation(self: *FileBrowser, previous_selected: usize, previous_scroll: usize, repaired: bool) bool {
        const changed = self.selectionStateChanged(previous_selected, previous_scroll);
        if (changed or repaired) {
            self.resetTypeahead();
            return true;
        }
        return false;
    }

    fn hasDrawableBorder(self: *const FileBrowser) bool {
        const rect = self.widget.rect;
        return self.border != .none and rect.width >= 2 and rect.height >= 2;
    }

    fn contentRect(self: *const FileBrowser) layout_module.Rect {
        const rect = self.widget.rect;
        if (self.hasDrawableBorder()) {
            return rect.shrink(layout_module.EdgeInsets.all(1));
        }
        return rect;
    }

    fn listRect(self: *const FileBrowser) layout_module.Rect {
        var rect = self.contentRect();
        if (rect.height > 0) {
            rect.y = std.math.add(u16, rect.y, 1) catch std.math.maxInt(u16);
            rect.height -= 1;
        }
        return rect;
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *FileBrowser = @fieldParentPtr("widget", widget_ref);

        if (!self.widget.visible) return;

        const rect = self.widget.rect;
        if (rect.width == 0 or rect.height == 0) return;

        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', self.fg, self.bg, render.Style{});

        const has_border = self.hasDrawableBorder();

        if (has_border) {
            renderer.drawBox(rect.x, rect.y, rect.width, rect.height, self.border, self.border_color, self.bg, render.Style{});
        }

        const content_rect = self.contentRect();
        if (content_rect.width == 0 or content_rect.height == 0) return;

        // Header with current path
        const header_y = content_rect.y;
        const header_x = content_rect.x;
        const header_width = content_rect.width;

        // List area starts after header
        const list_rect = self.listRect();
        self.visible_items = @intCast(@as(usize, list_rect.height));
        self.ensureVisible();

        var header_buf: [256]u8 = undefined;
        if (header_width > 0) {
            const header_slice = text_metrics.clipWithEllipsis(self.current_path, header_width, header_buf[0..]).text;
            renderer.drawStr(header_x, header_y, header_slice, self.fg, self.bg, self.header_style);
        }

        var row: usize = 0;
        while (row < self.visible_items) : (row += 1) {
            const entry_index = self.scroll + row;
            if (entry_index >= self.entries.items.len) break;

            const entry = self.entries.items[entry_index];
            const row_offset: u16 = @intCast(row);
            const line_y = std.math.add(u16, list_rect.y, row_offset) catch break;

            const is_selected = entry_index == self.selected;
            const line_fg = if (is_selected) self.highlight_fg else self.fg;
            const line_bg = if (is_selected) self.highlight_bg else self.bg;

            renderer.fillRect(header_x, line_y, header_width, 1, ' ', line_fg, line_bg, render.Style{});

            const tag = if (entry.is_dir) "[D] " else "[F] ";
            var prefix_buf: [4]u8 = .{ '[', ' ', ']', ' ' };
            if (entry.is_dir) prefix_buf[1] = 'D' else prefix_buf[1] = 'F';

            if (header_width >= prefix_buf.len) {
                renderer.drawStr(header_x, line_y, &prefix_buf, line_fg, line_bg, render.Style{ .bold = entry.is_dir });

                const available = header_width - @as(u16, @intCast(prefix_buf.len));
                if (available > 0) {
                    const name_slice = text_metrics.clipWithEllipsis(entry.name, available, header_buf[0..]).text;
                    renderer.drawStr(header_x + @as(u16, @intCast(prefix_buf.len)), line_y, name_slice, line_fg, line_bg, render.Style{ .italic = entry.is_parent });
                }
            } else {
                const tag_slice = text_metrics.clipWithEllipsis(tag[0..], header_width, header_buf[0..]).text;
                renderer.drawStr(header_x, line_y, tag_slice, line_fg, line_bg, render.Style{});
            }
        }
    }

    fn truncateIntoBuffer(text: []const u8, max_chars: usize, buffer: []u8) []const u8 {
        if (max_chars == 0) return buffer[0..0];

        const capped: u16 = @intCast(@min(max_chars, @as(usize, std.math.maxInt(u16))));
        return text_metrics.truncateToWidth(text, capped, buffer, true);
    }

    fn handleTypeaheadKey(self: *FileBrowser, byte: u8) bool {
        if (self.entries.items.len == 0) return false;
        self.clampSelection();

        const now = self.clock();
        if (self.last_search_ms) |last| {
            if (now < last or @as(u64, @intCast(now - last)) > self.search_timeout_ms) {
                self.resetTypeahead();
            }
        }
        self.last_search_ms = now;

        if (self.search_len < self.search_buffer.len) {
            self.search_buffer[self.search_len] = std.ascii.toLower(byte);
            self.search_len += 1;
        } else {
            std.mem.copyForwards(u8, self.search_buffer[0 .. self.search_buffer.len - 1], self.search_buffer[1..]);
            self.search_buffer[self.search_buffer.len - 1] = std.ascii.toLower(byte);
            self.search_len = self.search_buffer.len;
        }

        const needle = self.search_buffer[0..self.search_len];
        if (needle.len == 0) return false;

        const start = self.selected;
        var i: usize = 0;
        while (i < self.entries.items.len) : (i += 1) {
            const idx = (start + i) % self.entries.items.len;
            if (startsWithIgnoreCase(self.entries.items[idx].name, needle)) {
                self.selected = idx;
                self.ensureVisible();
                return true;
            }
        }

        return false;
    }

    fn startsWithIgnoreCase(haystack: []const u8, needle: []const u8) bool {
        if (needle.len == 0 or needle.len > haystack.len) {
            return false;
        }

        var i: usize = 0;
        while (i < needle.len) : (i += 1) {
            if (std.ascii.toLower(haystack[i]) != needle[i]) {
                return false;
            }
        }
        return true;
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *FileBrowser = @fieldParentPtr("widget", widget_ref);

        if (!self.widget.visible or !self.widget.enabled or self.entries.items.len == 0) return false;

        const content_rect = self.contentRect();
        const list_rect = self.listRect();

        switch (event) {
            .mouse => |mouse_event| {
                if (!content_rect.contains(mouse_event.x, mouse_event.y)) return false;
                if (!list_rect.contains(mouse_event.x, mouse_event.y)) return true;

                const row = mouse_event.y - list_rect.y;
                const index = self.scroll + @as(usize, @intCast(row));
                if (index < self.entries.items.len) {
                    self.selected = index;
                    self.ensureVisible();
                    if (mouse_event.action == .press and mouse_event.button == 1) {
                        try self.enterSelection();
                    }
                    return true;
                }
                return true;
            },
            .key => |key_event| {
                if (!self.widget.focused) return false;
                const before_clamp_selected = self.selected;
                const before_clamp_scroll = self.scroll;
                self.clampSelection();
                const repaired = self.selectionStateChanged(before_clamp_selected, before_clamp_scroll);

                const key = key_event.key;
                if (key == input.KeyCode.UP or key == 'k') {
                    const previous_selected = self.selected;
                    const previous_scroll = self.scroll;
                    if (self.selected > 0) {
                        self.selected -= 1;
                        self.ensureVisible();
                    }
                    return self.finishNavigation(previous_selected, previous_scroll, repaired);
                } else if (key == input.KeyCode.DOWN or key == 'j') {
                    const previous_selected = self.selected;
                    const previous_scroll = self.scroll;
                    if (self.selected + 1 < self.entries.items.len) {
                        self.selected += 1;
                        self.ensureVisible();
                    }
                    return self.finishNavigation(previous_selected, previous_scroll, repaired);
                } else if (key == input.KeyCode.PAGE_UP) {
                    const previous_selected = self.selected;
                    const previous_scroll = self.scroll;
                    if (self.visible_items > 0) {
                        if (self.selected >= self.visible_items) {
                            self.selected -= self.visible_items;
                        } else {
                            self.selected = 0;
                        }
                        self.ensureVisible();
                    }
                    return self.finishNavigation(previous_selected, previous_scroll, repaired);
                } else if (key == input.KeyCode.PAGE_DOWN) {
                    const previous_selected = self.selected;
                    const previous_scroll = self.scroll;
                    if (self.visible_items > 0) {
                        const next = std.math.add(usize, self.selected, self.visible_items) catch std.math.maxInt(usize);
                        self.selected = @min(next, self.entries.items.len - 1);
                        self.ensureVisible();
                    }
                    return self.finishNavigation(previous_selected, previous_scroll, repaired);
                } else if (key == input.KeyCode.LEFT or key == input.KeyCode.BACKSPACE) {
                    if (std.fs.path.dirname(self.current_path) != null) {
                        const parent = try self.parentPath();
                        defer self.allocator.free(parent);
                        try self.setPath(parent);
                    }
                    self.resetTypeahead();
                    return true;
                } else if (key == input.KeyCode.RIGHT or key == input.KeyCode.ENTER or key == '\r' or key == '\n') {
                    try self.enterSelection();
                    self.resetTypeahead();
                    return true;
                } else if (key == input.KeyCode.ESCAPE) {
                    self.resetTypeahead();
                    return false;
                } else if (key_event.isPrintable() and !key_event.modifiers.ctrl and !key_event.modifiers.alt) {
                    if (self.handleTypeaheadKey(@as(u8, @intCast(key_event.key)))) {
                        return true;
                    }
                }
            },
            else => {},
        }

        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *FileBrowser = @fieldParentPtr("widget", widget_ref);
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(_: *anyopaque) anyerror!layout_module.Size {
        return layout_module.Size.init(30, 10);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *FileBrowser = @fieldParentPtr("widget", widget_ref);
        return self.widget.enabled and self.entries.items.len > 0;
    }
};

test "file browser navigates directories" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const io = std.Io.Threaded.global_single_threaded.io();

    try tmp.dir.createDirPath(io, "nested");
    {
        const root_file = try tmp.dir.createFile(io, "readme.txt", .{});
        root_file.close(io);
    }
    {
        const nested_file = try tmp.dir.createFile(io, "nested/note.md", .{});
        nested_file.close(io);
    }

    const root_path = try tmp.dir.realPathFileAlloc(io, ".", alloc);
    defer alloc.free(root_path);

    var browser = try FileBrowser.init(alloc, root_path);
    defer browser.deinit();

    browser.widget.focused = true;
    try browser.widget.layout(layout_module.Rect.init(0, 0, 20, 6));
    try std.testing.expect(browser.entries.items.len >= 2);

    // Move selection down to nested directory and enter it.
    _ = try browser.widget.handleEvent(.{ .key = .{ .key = input.KeyCode.DOWN, .modifiers = .{} } });
    _ = try browser.widget.handleEvent(.{ .key = .{ .key = input.KeyCode.ENTER, .modifiers = .{} } });

    try std.testing.expect(std.mem.endsWith(u8, browser.current_path, "nested"));
    try std.testing.expect(browser.entries.items.len >= 1);

    // Navigate back up.
    _ = try browser.widget.handleEvent(.{ .key = .{ .key = input.KeyCode.LEFT, .modifiers = .{} } });
    try std.testing.expect(!std.mem.endsWith(u8, browser.current_path, "nested"));
}

test "file browser typeahead selects entries" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.Io.Threaded.global_single_threaded.io();

    {
        const file = try tmp.dir.createFile(io, "garden.log", .{});
        file.close(io);
    }
    {
        const file = try tmp.dir.createFile(io, "melon.txt", .{});
        file.close(io);
    }
    {
        const file = try tmp.dir.createFile(io, "zeta.md", .{});
        file.close(io);
    }

    const root_path = try tmp.dir.realPathFileAlloc(io, ".", alloc);
    defer alloc.free(root_path);

    var browser = try FileBrowser.init(alloc, root_path);
    defer browser.deinit();

    browser.widget.focused = true;
    try browser.widget.layout(layout_module.Rect.init(0, 0, 30, 8));

    const TestClock = struct {
        var now: i64 = 0;
        fn tick() i64 {
            return now;
        }
    };

    browser.setTypeaheadClock(TestClock.tick);
    browser.setTypeaheadTimeout(1_000);

    _ = try browser.widget.handleEvent(.{ .key = .{ .key = 'g', .modifiers = .{} } });
    try std.testing.expect(std.mem.startsWith(u8, browser.entries.items[browser.selected].name, "garden"));

    _ = try browser.widget.handleEvent(.{ .key = .{ .key = 'a', .modifiers = .{} } });
    try std.testing.expect(std.mem.startsWith(u8, browser.entries.items[browser.selected].name, "garden"));

    TestClock.now = 2_000;
    _ = try browser.widget.handleEvent(.{ .key = .{ .key = 'z', .modifiers = .{} } });
    try std.testing.expect(std.mem.startsWith(u8, browser.entries.items[browser.selected].name, "zeta"));
}

test "file browser visible mutations mark dirty" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.Io.Threaded.global_single_threaded.io();

    try tmp.dir.createDirPath(io, "nested");
    {
        const file = try tmp.dir.createFile(io, "visible.txt", .{});
        file.close(io);
    }
    {
        const file = try tmp.dir.createFile(io, ".hidden.txt", .{});
        file.close(io);
    }

    const root_path = try tmp.dir.realPathFileAlloc(io, ".", alloc);
    defer alloc.free(root_path);
    const nested_path = try tmp.dir.realPathFileAlloc(io, "nested", alloc);
    defer alloc.free(nested_path);

    var browser = try FileBrowser.init(alloc, root_path);
    defer browser.deinit();

    browser.widget.clearDirty();
    browser.setColors(render.Color.named(.white), render.Color.named(.black), render.Color.named(.black), render.Color.named(.green));
    try std.testing.expect(browser.widget.dirty);
    browser.widget.clearDirty();
    browser.setColors(render.Color.named(.white), render.Color.named(.black), render.Color.named(.black), render.Color.named(.green));
    try std.testing.expect(!browser.widget.dirty);

    browser.setBorder(.rounded, render.Color.named(.yellow));
    try std.testing.expect(browser.widget.dirty);
    browser.widget.clearDirty();
    browser.setBorder(.rounded, render.Color.named(.yellow));
    try std.testing.expect(!browser.widget.dirty);

    try browser.setShowHidden(true);
    try std.testing.expect(browser.widget.dirty);
    browser.widget.clearDirty();
    try browser.setShowHidden(true);
    try std.testing.expect(!browser.widget.dirty);

    try browser.setPath(nested_path);
    try std.testing.expect(browser.widget.dirty);
    browser.widget.clearDirty();

    try browser.refresh();
    try std.testing.expect(browser.widget.dirty);
}

test "file browser clamps stale selection before keyboard navigation" {
    const alloc = std.testing.allocator;
    var browser = try FileBrowser.init(alloc, ".");
    defer browser.deinit();

    browser.clearEntries();
    try browser.entries.append(alloc, .{
        .name = try alloc.dupe(u8, "alpha.txt"),
        .is_dir = false,
    });
    try browser.entries.append(alloc, .{
        .name = try alloc.dupe(u8, "beta.txt"),
        .is_dir = false,
    });
    browser.widget.focused = true;
    browser.visible_items = 1;
    browser.selected = std.math.maxInt(usize);
    browser.scroll = std.math.maxInt(usize);

    try std.testing.expect(try browser.widget.handleEvent(.{ .key = .{ .key = input.KeyCode.DOWN, .modifiers = .{} } }));
    try std.testing.expectEqual(@as(usize, 1), browser.selected);
    try std.testing.expectEqual(@as(usize, 1), browser.scroll);

    try std.testing.expect(try browser.widget.handleEvent(.{ .key = .{ .key = input.KeyCode.UP, .modifiers = .{} } }));
    try std.testing.expectEqual(@as(usize, 0), browser.selected);
    try std.testing.expectEqual(@as(usize, 0), browser.scroll);
}

test "file browser ignores saturated keyboard navigation" {
    const alloc = std.testing.allocator;
    var browser = try FileBrowser.init(alloc, ".");
    defer browser.deinit();

    browser.clearEntries();
    try browser.entries.append(alloc, .{
        .name = try alloc.dupe(u8, "alpha.txt"),
        .is_dir = false,
    });
    try browser.entries.append(alloc, .{
        .name = try alloc.dupe(u8, "beta.txt"),
        .is_dir = false,
    });

    browser.widget.focused = true;
    browser.visible_items = 1;
    browser.selected = 0;
    browser.scroll = 0;
    browser.search_len = 1;
    browser.widget.clearDirty();

    try std.testing.expect(!try browser.widget.handleEvent(.{ .key = .{ .key = input.KeyCode.UP, .modifiers = .{} } }));
    try std.testing.expectEqual(@as(usize, 0), browser.selected);
    try std.testing.expectEqual(@as(usize, 0), browser.scroll);
    try std.testing.expectEqual(@as(usize, 1), browser.search_len);
    try std.testing.expect(!browser.widget.dirty);

    try std.testing.expect(!try browser.widget.handleEvent(.{ .key = .{ .key = input.KeyCode.PAGE_UP, .modifiers = .{} } }));
    try std.testing.expectEqual(@as(usize, 0), browser.selected);
    try std.testing.expectEqual(@as(usize, 0), browser.scroll);
    try std.testing.expectEqual(@as(usize, 1), browser.search_len);
    try std.testing.expect(!browser.widget.dirty);

    try std.testing.expect(try browser.widget.handleEvent(.{ .key = .{ .key = input.KeyCode.DOWN, .modifiers = .{} } }));
    try std.testing.expectEqual(@as(usize, 1), browser.selected);
    try std.testing.expectEqual(@as(usize, 1), browser.scroll);
    try std.testing.expectEqual(@as(usize, 0), browser.search_len);
    try std.testing.expect(browser.widget.dirty);

    browser.search_len = 1;
    browser.widget.clearDirty();
    try std.testing.expect(!try browser.widget.handleEvent(.{ .key = .{ .key = input.KeyCode.DOWN, .modifiers = .{} } }));
    try std.testing.expectEqual(@as(usize, 1), browser.selected);
    try std.testing.expectEqual(@as(usize, 1), browser.scroll);
    try std.testing.expectEqual(@as(usize, 1), browser.search_len);
    try std.testing.expect(!browser.widget.dirty);

    try std.testing.expect(!try browser.widget.handleEvent(.{ .key = .{ .key = input.KeyCode.PAGE_DOWN, .modifiers = .{} } }));
    try std.testing.expectEqual(@as(usize, 1), browser.selected);
    try std.testing.expectEqual(@as(usize, 1), browser.scroll);
    try std.testing.expectEqual(@as(usize, 1), browser.search_len);
    try std.testing.expect(!browser.widget.dirty);
}

test "file browser clamps stale selection before typeahead and activation" {
    const alloc = std.testing.allocator;
    var browser = try FileBrowser.init(alloc, ".");
    defer browser.deinit();

    browser.clearEntries();
    try browser.entries.append(alloc, .{
        .name = try alloc.dupe(u8, "alpha.txt"),
        .is_dir = false,
    });
    try browser.entries.append(alloc, .{
        .name = try alloc.dupe(u8, "beta.txt"),
        .is_dir = false,
    });
    browser.widget.focused = true;
    browser.visible_items = 2;
    browser.selected = std.math.maxInt(usize);

    try std.testing.expect(try browser.widget.handleEvent(.{ .key = .{ .key = 'b', .modifiers = .{} } }));
    try std.testing.expectEqual(@as(usize, 1), browser.selected);

    browser.selected = std.math.maxInt(usize);
    try std.testing.expect(try browser.widget.handleEvent(.{ .key = .{ .key = input.KeyCode.ENTER, .modifiers = .{} } }));
    try std.testing.expectEqual(@as(usize, 1), browser.selected);
}

test "file browser setPath preserves state when target cannot refresh" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.Io.Threaded.global_single_threaded.io();

    {
        const file = try tmp.dir.createFile(io, "stable.txt", .{});
        file.close(io);
    }
    {
        const file = try tmp.dir.createFile(io, "not-a-dir.txt", .{});
        file.close(io);
    }

    const root_path = try tmp.dir.realPathFileAlloc(io, ".", alloc);
    defer alloc.free(root_path);
    const file_path = try std.fs.path.join(alloc, &[_][]const u8{ root_path, "not-a-dir.txt" });
    defer alloc.free(file_path);

    var browser = try FileBrowser.init(alloc, root_path);
    defer browser.deinit();

    const old_path = try alloc.dupe(u8, browser.current_path);
    defer alloc.free(old_path);
    const old_len = browser.entries.items.len;
    try std.testing.expect(old_len > 0);
    browser.widget.clearDirty();

    try std.testing.expectError(error.NotDir, browser.setPath(file_path));
    try std.testing.expectEqualStrings(old_path, browser.current_path);
    try std.testing.expectEqual(old_len, browser.entries.items.len);
    try std.testing.expect(!browser.widget.dirty);
}

test "file browser refresh preserves entries on allocation failure" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.Io.Threaded.global_single_threaded.io();

    {
        const file = try tmp.dir.createFile(io, "alpha.txt", .{});
        file.close(io);
    }

    const root_path = try tmp.dir.realPathFileAlloc(io, ".", alloc);
    defer alloc.free(root_path);

    var browser = try FileBrowser.init(alloc, root_path);
    defer browser.deinit();

    const old_len = browser.entries.items.len;
    const old_first = try alloc.dupe(u8, browser.entries.items[0].name);
    defer alloc.free(old_first);
    browser.widget.clearDirty();

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = browser.allocator;
    browser.allocator = failing.allocator();
    defer browser.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, browser.refresh());
    try std.testing.expectEqual(old_len, browser.entries.items.len);
    try std.testing.expectEqualStrings(old_first, browser.entries.items[0].name);
    try std.testing.expect(!browser.widget.dirty);
}

test "file browser setShowHidden preserves state when refresh fails" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.Io.Threaded.global_single_threaded.io();

    try tmp.dir.createDirPath(io, "doomed");
    {
        const file = try tmp.dir.createFile(io, "doomed/stable.txt", .{});
        file.close(io);
    }

    const doomed_path = try tmp.dir.realPathFileAlloc(io, "doomed", alloc);
    defer alloc.free(doomed_path);

    var browser = try FileBrowser.init(alloc, doomed_path);
    defer browser.deinit();

    const old_len = browser.entries.items.len;
    try std.testing.expect(!browser.show_hidden);
    browser.widget.clearDirty();

    try tmp.dir.deleteTree(io, "doomed");
    try std.testing.expectError(error.FileNotFound, browser.setShowHidden(true));
    try std.testing.expect(!browser.show_hidden);
    try std.testing.expectEqual(old_len, browser.entries.items.len);
    try std.testing.expect(!browser.widget.dirty);
}

test "file browser clips entry names without splitting wide utf8 glyphs" {
    const alloc = std.testing.allocator;
    var browser = try FileBrowser.init(alloc, ".");
    defer browser.deinit();

    browser.clearEntries();
    try browser.entries.append(alloc, .{
        .name = try alloc.dupe(u8, "界abc.txt"),
        .is_dir = false,
    });
    browser.selected = 0;
    browser.border = .none;
    try browser.widget.layout(layout_module.Rect.init(0, 0, 10, 3));

    var renderer = try render.Renderer.init(alloc, 10, 3);
    defer renderer.deinit();
    renderer.capabilities.unicode = true;
    renderer.capabilities.double_width = true;

    try browser.widget.draw(&renderer);
    try std.testing.expectEqual(@as(u21, '界'), renderer.back.getCell(4, 1).*.codepoint());
    try std.testing.expect(renderer.back.getCell(5, 1).*.continuation);
    try std.testing.expectEqual(@as(u21, '.'), renderer.back.getCell(8, 1).*.codepoint());
}

test "file browser border is not used as an entry row" {
    const alloc = std.testing.allocator;
    var browser = try FileBrowser.init(alloc, ".");
    defer browser.deinit();

    browser.clearEntries();
    try browser.entries.append(alloc, .{
        .name = try alloc.dupe(u8, "alpha.txt"),
        .is_dir = false,
    });
    try browser.entries.append(alloc, .{
        .name = try alloc.dupe(u8, "beta.txt"),
        .is_dir = false,
    });
    browser.selected = 0;
    browser.scroll = 0;
    browser.border = .single;
    try browser.widget.layout(layout_module.Rect.init(0, 0, 12, 4));

    var renderer = try render.Renderer.init(alloc, 12, 4);
    defer renderer.deinit();

    try browser.widget.draw(&renderer);
    try std.testing.expectEqual(@as(u21, '─'), renderer.back.getCell(1, 3).*.codepoint());
    try std.testing.expectEqual(@as(usize, 1), browser.visible_items);
}

test "file browser mouse clicks ignore visible border rows" {
    const alloc = std.testing.allocator;
    var browser = try FileBrowser.init(alloc, ".");
    defer browser.deinit();

    browser.clearEntries();
    try browser.entries.append(alloc, .{
        .name = try alloc.dupe(u8, "alpha.txt"),
        .is_dir = false,
    });
    try browser.entries.append(alloc, .{
        .name = try alloc.dupe(u8, "beta.txt"),
        .is_dir = false,
    });
    browser.selected = 0;
    browser.scroll = 0;
    browser.border = .single;
    try browser.widget.layout(layout_module.Rect.init(0, 0, 12, 4));

    const top_border = input.Event{ .mouse = input.MouseEvent.init(.press, 1, 0, 1, 0) };
    try std.testing.expect(!try browser.widget.handleEvent(top_border));
    try std.testing.expectEqual(@as(usize, 0), browser.selected);

    const header = input.Event{ .mouse = input.MouseEvent.init(.press, 1, 1, 1, 0) };
    try std.testing.expect(try browser.widget.handleEvent(header));
    try std.testing.expectEqual(@as(usize, 0), browser.selected);

    const first_row = input.Event{ .mouse = input.MouseEvent.init(.press, 1, 2, 1, 0) };
    try std.testing.expect(try browser.widget.handleEvent(first_row));
    try std.testing.expectEqual(@as(usize, 0), browser.selected);

    const bottom_border = input.Event{ .mouse = input.MouseEvent.init(.press, 1, 3, 1, 0) };
    try std.testing.expect(!try browser.widget.handleEvent(bottom_border));
    try std.testing.expectEqual(@as(usize, 0), browser.selected);
}
