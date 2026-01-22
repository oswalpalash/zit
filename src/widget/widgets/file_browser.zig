const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");

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
    clock: *const fn () i64 = std.time.milliTimestamp,

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

        const self = try allocator.create(FileBrowser);
        self.* = FileBrowser{
            .widget = base.Widget.init(&vtable),
            .allocator = allocator,
            .current_path = normalized,
            .entries = std.ArrayList(Entry).empty,
        };

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
        self.fg = fg;
        self.bg = bg;
        self.highlight_fg = highlight_fg;
        self.highlight_bg = highlight_bg;
    }

    pub fn setBorder(self: *FileBrowser, border: render.BorderStyle, border_color: render.Color) void {
        self.border = border;
        self.border_color = border_color;
    }

    pub fn setShowHidden(self: *FileBrowser, show: bool) !void {
        self.show_hidden = show;
        try self.refresh();
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
        self.allocator.free(self.current_path);
        self.current_path = normalized;
        self.selected = 0;
        self.scroll = 0;
        self.resetTypeahead();
        try self.refresh();
        if (self.on_directory_change) |cb| {
            cb(self.current_path);
        }
    }

    pub fn refresh(self: *FileBrowser) !void {
        self.clearEntries();

        // Add parent entry if applicable.
        if (std.fs.path.dirname(self.current_path) != null) {
            const parent_name = try self.allocator.dupe(u8, "..");
            try self.entries.append(self.allocator, .{
                .name = parent_name,
                .is_dir = true,
                .is_parent = true,
            });
        }

        var dir = try std.fs.cwd().openDir(self.current_path, .{ .iterate = true });
        defer dir.close();

        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (!self.show_hidden and entry.name.len > 0 and entry.name[0] == '.') continue;
            const name_copy = try self.allocator.dupe(u8, entry.name);
            try self.entries.append(self.allocator, .{
                .name = name_copy,
                .is_dir = entry.kind == .directory,
            });
        }

        // Sort directories first, then files alphabetically.
        const Ctx = struct {};
        std.sort.pdq(Entry, self.entries.items, Ctx{}, struct {
            fn lessThan(_: Ctx, a: Entry, b: Entry) bool {
                if (a.is_parent != b.is_parent) return a.is_parent;
                if (a.is_dir != b.is_dir) return a.is_dir;
                return std.ascii.lessThanIgnoreCase(a.name, b.name);
            }
        }.lessThan);

        if (self.selected >= self.entries.items.len and self.entries.items.len > 0) {
            self.selected = self.entries.items.len - 1;
        }

        self.resetTypeahead();
        self.ensureVisible();
    }

    fn clearEntries(self: *FileBrowser) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.name);
        }
        self.entries.clearRetainingCapacity();
    }

    fn normalizePath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
        if (path.len == 0) {
            return try allocator.dupe(u8, ".");
        }
        return std.fs.cwd().realpathAlloc(allocator, path) catch try allocator.dupe(u8, path);
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

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*FileBrowser, @ptrCast(@alignCast(widget_ptr)));

        if (!self.widget.visible) return;

        const rect = self.widget.rect;
        if (rect.width == 0 or rect.height == 0) return;

        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', self.fg, self.bg, render.Style{});

        const has_border = self.border != .none and rect.width >= 2 and rect.height >= 2;
        const inset: u16 = if (has_border) 1 else 0;

        if (has_border) {
            renderer.drawBox(rect.x, rect.y, rect.width, rect.height, self.border, self.border_color, self.bg, render.Style{});
        }

        if (rect.height <= inset) return;

        // Header with current path
        const header_y = rect.y + inset;
        const header_x = rect.x + inset;
        const header_width = if (rect.width > inset * 2) rect.width - inset * 2 else 0;

        // List area starts after header
        const content_y = header_y + 1;
        if (content_y >= rect.y + rect.height) return;

        const content_height = rect.height - (content_y - rect.y);
        self.visible_items = @intCast(content_height);
        self.ensureVisible();

        var header_buf: [256]u8 = undefined;
        if (header_width > 0) {
            const max_chars: usize = @intCast(@min(header_width, @as(u16, @intCast(header_buf.len))));
            const header_slice = truncateIntoBuffer(self.current_path, max_chars, header_buf[0..]);
            renderer.drawStr(header_x, header_y, header_slice, self.fg, self.bg, self.header_style);
        }

        var row: usize = 0;
        while (row < self.visible_items) : (row += 1) {
            const entry_index = self.scroll + row;
            if (entry_index >= self.entries.items.len) break;

            const entry = self.entries.items[entry_index];
            const line_y = content_y + @as(u16, @intCast(row));

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
                    const max_chars: usize = @intCast(@min(available, @as(u16, @intCast(header_buf.len))));
                    const name_slice = truncateIntoBuffer(entry.name, max_chars, header_buf[0..]);
                    renderer.drawStr(header_x + @as(u16, @intCast(prefix_buf.len)), line_y, name_slice, line_fg, line_bg, render.Style{ .italic = entry.is_parent });
                }
            } else {
                const max_chars: usize = @intCast(header_width);
                const tag_slice = truncateIntoBuffer(tag[0..], max_chars, header_buf[0..]);
                renderer.drawStr(header_x, line_y, tag_slice, line_fg, line_bg, render.Style{});
            }
        }
    }

    fn truncateIntoBuffer(text: []const u8, max_chars: usize, buffer: []u8) []const u8 {
        if (max_chars == 0) return buffer[0..0];

        const available = @min(max_chars, buffer.len);
        if (text.len <= available) {
            @memcpy(buffer[0..text.len], text);
            return buffer[0..text.len];
        }

        if (available <= 3) {
            const len = @min(available, text.len);
            @memcpy(buffer[0..len], text[0..len]);
            return buffer[0..len];
        }

        const cut = available - 3;
        @memcpy(buffer[0..cut], text[0..cut]);
        buffer[cut] = '.';
        buffer[cut + 1] = '.';
        buffer[cut + 2] = '.';
        return buffer[0..available];
    }

    fn handleTypeaheadKey(self: *FileBrowser, byte: u8) bool {
        if (self.entries.items.len == 0) return false;

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
        const self = @as(*FileBrowser, @ptrCast(@alignCast(widget_ptr)));

        if (!self.widget.visible or !self.widget.enabled or self.entries.items.len == 0) return false;

        const rect = self.widget.rect;
        const has_border = self.border != .none and rect.width >= 2 and rect.height >= 2;
        const inset: u16 = if (has_border) 1 else 0;
        const header_y = rect.y + inset;
        const content_y = header_y + 1;

        switch (event) {
            .mouse => |mouse_event| {
                if (!rect.contains(mouse_event.x, mouse_event.y)) return false;
                if (mouse_event.y < content_y) return true;

                const row = mouse_event.y - content_y;
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

                const key = key_event.key;
                if (key == input.KeyCode.UP or key == 'k') {
                    if (self.selected > 0) {
                        self.selected -= 1;
                        self.ensureVisible();
                    }
                    self.resetTypeahead();
                    return true;
                } else if (key == input.KeyCode.DOWN or key == 'j') {
                    if (self.selected + 1 < self.entries.items.len) {
                        self.selected += 1;
                        self.ensureVisible();
                    }
                    self.resetTypeahead();
                    return true;
                } else if (key == input.KeyCode.PAGE_UP) {
                    if (self.visible_items > 0) {
                        if (self.selected >= self.visible_items) {
                            self.selected -= self.visible_items;
                        } else {
                            self.selected = 0;
                        }
                        self.ensureVisible();
                    }
                    self.resetTypeahead();
                    return true;
                } else if (key == input.KeyCode.PAGE_DOWN) {
                    if (self.visible_items > 0) {
                        self.selected = @min(self.selected + self.visible_items, self.entries.items.len - 1);
                        self.ensureVisible();
                    }
                    self.resetTypeahead();
                    return true;
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
        const self = @as(*FileBrowser, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(_: *anyopaque) anyerror!layout_module.Size {
        return layout_module.Size.init(30, 10);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*FileBrowser, @ptrCast(@alignCast(widget_ptr)));
        return self.widget.enabled and self.entries.items.len > 0;
    }
};

test "file browser navigates directories" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makePath("nested");
    {
        const root_file = try tmp.dir.createFile("readme.txt", .{});
        root_file.close();
    }
    {
        const nested_file = try tmp.dir.createFile("nested/note.md", .{});
        nested_file.close();
    }

    const root_path = try tmp.dir.realpathAlloc(alloc, ".");
    defer alloc.free(root_path);

    var browser = try FileBrowser.init(alloc, root_path);
    defer browser.deinit();

    try browser.widget.layout(layout_module.Rect.init(0, 0, 20, 6));
    try std.testing.expect(browser.entries.items.len >= 2);

    // Move selection down to nested directory and enter it.
    _ = try browser.handleEvent(.{ .key = .{ .key = input.KeyCode.DOWN, .modifiers = .{} } });
    _ = try browser.handleEvent(.{ .key = .{ .key = input.KeyCode.ENTER, .modifiers = .{} } });

    try std.testing.expect(std.mem.endsWith(u8, browser.current_path, "nested"));
    try std.testing.expect(browser.entries.items.len >= 1);

    // Navigate back up.
    _ = try browser.handleEvent(.{ .key = .{ .key = input.KeyCode.LEFT, .modifiers = .{} } });
    try std.testing.expect(!std.mem.endsWith(u8, browser.current_path, "nested"));
}

test "file browser typeahead selects entries" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    {
        const file = try tmp.dir.createFile("garden.log", .{});
        file.close();
    }
    {
        const file = try tmp.dir.createFile("gamma.txt", .{});
        file.close();
    }
    {
        const file = try tmp.dir.createFile("zeta.md", .{});
        file.close();
    }

    const root_path = try tmp.dir.realpathAlloc(alloc, ".");
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

    _ = try browser.handleEvent(.{ .key = .{ .key = 'g', .modifiers = .{} } });
    try std.testing.expect(std.mem.startsWith(u8, browser.entries.items[browser.selected].name, "garden"));

    _ = try browser.handleEvent(.{ .key = .{ .key = 'a', .modifiers = .{} } });
    try std.testing.expect(std.mem.startsWith(u8, browser.entries.items[browser.selected].name, "garden"));

    TestClock.now = 2_000;
    _ = try browser.handleEvent(.{ .key = .{ .key = 'z', .modifiers = .{} } });
    try std.testing.expect(std.mem.startsWith(u8, browser.entries.items[browser.selected].name, "zeta"));
}
