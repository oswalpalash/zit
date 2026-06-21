const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const text_metrics = @import("../../render/text_metrics.zig");
const input = @import("../../input/input.zig");
const theme = @import("../theme.zig");
const accessibility = @import("../accessibility.zig");

/// Hierarchical tree widget with keyboard navigation.
pub const TreeView = struct {
    widget: base.Widget,
    nodes: std.ArrayList(Node),
    visible: std.ArrayList(usize),
    selected: usize = 0,
    scroll_offset: usize = 0,
    palette: theme.Theme,
    visible_dirty: bool = true,
    allocator: std.mem.Allocator,

    pub const Node = struct {
        label: []const u8,
        parent: ?usize,
        children: std.ArrayList(usize),
        expanded: bool = false,
        depth: usize = 0,
    };

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator) !*TreeView {
        const self = try allocator.create(TreeView);
        self.* = TreeView{
            .widget = base.Widget.init(&vtable),
            .nodes = std.ArrayList(Node).empty,
            .visible = std.ArrayList(usize).empty,
            .palette = theme.Theme.dark(),
            .allocator = allocator,
        };
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.list), "Tree view", "");
        return self;
    }

    pub fn deinit(self: *TreeView) void {
        for (self.nodes.items) |*node| {
            if (node.label.len > 0) {
                self.allocator.free(node.label);
            }
            node.children.deinit(self.allocator);
        }
        self.nodes.deinit(self.allocator);
        self.visible.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn setTheme(self: *TreeView, palette: theme.Theme) !void {
        if (std.meta.eql(self.palette, palette)) return;
        self.palette = palette;
        self.widget.markDirty();
    }

    pub fn addRoot(self: *TreeView, label: []const u8) !usize {
        return self.addNode(null, label);
    }

    pub fn addChild(self: *TreeView, parent_index: usize, label: []const u8) !usize {
        return self.addNode(parent_index, label);
    }

    fn addNode(self: *TreeView, parent_index: ?usize, label: []const u8) !usize {
        if (parent_index) |idx| {
            if (idx >= self.nodes.items.len) return error.InvalidParent;
            try self.nodes.ensureUnusedCapacity(self.allocator, 1);
            try self.nodes.items[idx].children.ensureUnusedCapacity(self.allocator, 1);
        } else {
            try self.nodes.ensureUnusedCapacity(self.allocator, 1);
        }

        const children = std.ArrayList(usize).empty;
        const owned = try self.allocator.dupe(u8, label);
        const depth = if (parent_index) |idx| addUsizeSaturating(self.nodes.items[idx].depth, 1) else 0;
        const node = Node{
            .label = owned,
            .parent = parent_index,
            .children = children,
            .expanded = false,
            .depth = depth,
        };
        const index = self.nodes.items.len;
        self.nodes.appendAssumeCapacity(node);
        if (parent_index) |idx| {
            self.nodes.items[idx].children.appendAssumeCapacity(index);
        }
        self.visible_dirty = true;
        self.widget.markDirty();
        return index;
    }

    fn syncVisible(self: *TreeView) !void {
        if (!self.visible_dirty) return;

        var next_visible = std.ArrayList(usize).empty;
        errdefer next_visible.deinit(self.allocator);

        for (self.nodes.items, 0..) |_, idx| {
            const node = self.nodes.items[idx];
            if (node.parent == null) {
                try self.collectVisibleInto(idx, &next_visible);
            }
        }

        self.visible.deinit(self.allocator);
        self.visible = next_visible;
        self.visible_dirty = false;

        if (self.scroll_offset >= self.visible.items.len and self.visible.items.len > 0) {
            self.scroll_offset = self.visible.items.len - 1;
        }
        if (self.selected >= self.visible.items.len and self.visible.items.len > 0) {
            self.selected = self.visible.items.len - 1;
        }
        if (self.visible.items.len == 0) {
            self.selected = 0;
            self.scroll_offset = 0;
        }
    }

    fn collectVisibleInto(self: *TreeView, index: usize, visible: *std.ArrayList(usize)) !void {
        try visible.append(self.allocator, index);
        const node = &self.nodes.items[index];
        if (!node.expanded) return;
        for (node.children.items) |child_idx| {
            try self.collectVisibleInto(child_idx, visible);
        }
    }

    fn ensureSelectionVisible(self: *TreeView, height: usize) void {
        if (self.visible.items.len == 0) {
            self.scroll_offset = 0;
            return;
        }
        if (self.selected < self.scroll_offset) {
            self.scroll_offset = self.selected;
        }
        const limit = self.scroll_offset + height;
        if (self.selected >= limit) {
            self.scroll_offset = self.selected - height + 1;
        }
    }

    fn clampSelection(self: *TreeView) void {
        if (self.visible.items.len == 0) {
            self.selected = 0;
        } else if (self.selected >= self.visible.items.len) {
            self.selected = self.visible.items.len - 1;
        }
    }

    fn addOffsetClamped(origin: u16, offset: u16) u16 {
        const value = @as(u32, origin) + @as(u32, offset);
        return @intCast(@min(value, @as(u32, std.math.maxInt(u16))));
    }

    fn addU16Clamped(a: u16, b: u16) u16 {
        const value = @as(u32, a) + @as(u32, b);
        return @intCast(@min(value, @as(u32, std.math.maxInt(u16))));
    }

    fn addUsizeSaturating(a: usize, b: usize) usize {
        return std.math.add(usize, a, b) catch std.math.maxInt(usize);
    }

    fn indentForDepth(depth: usize, width: u16) u16 {
        const width_usize: usize = width;
        const saturating_threshold = (width_usize + 1) / 2;
        if (depth >= saturating_threshold) return width;
        return @intCast(depth * 2);
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *TreeView = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible) return;

        const rect = self.widget.rect;
        if (rect.width == 0 or rect.height == 0) return;

        try self.syncVisible();

        const total = self.visible.items.len;
        const height: usize = @intCast(rect.height);
        if (total == 0) {
            renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', self.palette.color(.text), self.palette.color(.surface), self.palette.style);
            return;
        }

        if (self.selected >= total) self.selected = total - 1;
        self.ensureSelectionVisible(height);

        const start = self.scroll_offset;
        const end = @min(start + height, total);

        const accent = self.palette.color(.accent);
        const text = self.palette.color(.text);
        const surface = self.palette.color(.surface);
        const muted = self.palette.color(.muted);

        var row: usize = 0;
        for (start..end) |visible_index| {
            const node_index = self.visible.items[visible_index];
            const node = self.nodes.items[node_index];
            const y_pos = addOffsetClamped(rect.y, @intCast(row));
            const is_selected = visible_index == self.selected;
            const row_bg = if (is_selected) accent else surface;
            const row_fg = if (is_selected) self.palette.color(.background) else text;

            renderer.fillRect(rect.x, y_pos, rect.width, 1, ' ', row_fg, row_bg, self.palette.style);

            const indent = indentForDepth(node.depth, rect.width);
            const marker: u21 = if (node.children.items.len > 0)
                (if (node.expanded) '▾' else '▸')
            else
                '•';

            if (indent < rect.width) {
                renderer.drawChar(addOffsetClamped(rect.x, indent), y_pos, marker, if (node.children.items.len > 0) accent else muted, row_bg, self.palette.style);
            }

            const label_start = addU16Clamped(indent, 2);
            if (label_start < rect.width) {
                var label_buf: [256]u8 = undefined;
                const clipped = text_metrics.clipWithEllipsis(node.label, rect.width - label_start, &label_buf);
                renderer.drawStr(addOffsetClamped(rect.x, label_start), y_pos, clipped.text, row_fg, row_bg, self.palette.style);
            }

            row += 1;
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *TreeView = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.enabled or !self.widget.visible) return false;

        try self.syncVisible();
        if (self.visible.items.len == 0) return false;
        self.clampSelection();

        switch (event) {
            .key => |key| {
                var handled = false;
                switch (key.key) {
                    input.KeyCode.DOWN => {
                        if (self.selected + 1 < self.visible.items.len) {
                            self.selected += 1;
                            handled = true;
                        }
                    },
                    input.KeyCode.UP => {
                        if (self.selected > 0) {
                            self.selected -= 1;
                            handled = true;
                        }
                    },
                    input.KeyCode.RIGHT => {
                        const idx = self.visible.items[self.selected];
                        if (self.nodes.items[idx].children.items.len > 0 and !self.nodes.items[idx].expanded) {
                            self.nodes.items[idx].expanded = true;
                            self.visible_dirty = true;
                            handled = true;
                            try self.syncVisible();
                        }
                    },
                    input.KeyCode.LEFT => {
                        const idx = self.visible.items[self.selected];
                        if (self.nodes.items[idx].expanded) {
                            self.nodes.items[idx].expanded = false;
                            self.visible_dirty = true;
                            handled = true;
                            try self.syncVisible();
                        } else if (self.nodes.items[idx].parent) |parent_idx| {
                            self.selected = self.indexOfVisible(parent_idx) orelse self.selected;
                            handled = true;
                        }
                    },
                    input.KeyCode.HOME => {
                        self.selected = 0;
                        handled = true;
                    },
                    input.KeyCode.END => {
                        self.selected = self.visible.items.len - 1;
                        handled = true;
                    },
                    input.KeyCode.SPACE, input.KeyCode.ENTER => {
                        const idx = self.visible.items[self.selected];
                        if (self.nodes.items[idx].children.items.len > 0) {
                            self.nodes.items[idx].expanded = !self.nodes.items[idx].expanded;
                            self.visible_dirty = true;
                            handled = true;
                            try self.syncVisible();
                        }
                    },
                    else => {},
                }

                if (handled) {
                    self.ensureSelectionVisible(@intCast(self.widget.rect.height));
                    return true;
                }
            },
            else => {},
        }

        return false;
    }

    fn indexOfVisible(self: *TreeView, node_index: usize) ?usize {
        for (self.visible.items, 0..) |value, i| {
            if (value == node_index) return i;
        }
        return null;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *TreeView = @fieldParentPtr("widget", widget_ref);
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *TreeView = @fieldParentPtr("widget", widget_ref);
        try self.syncVisible();
        const width_guess: usize = @min(self.visible.items.len + 8, @as(usize, 32));
        const height_guess: usize = @min(self.visible.items.len, @as(usize, 10));
        const width: u16 = @intCast(@max(width_guess, 12));
        const height: u16 = @intCast(if (height_guess == 0) 3 else height_guess);
        return layout_module.Size.init(width, height);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *TreeView = @fieldParentPtr("widget", widget_ref);
        return self.widget.enabled and self.widget.visible;
    }

    /// Visible nodes for testing and layout decisions.
    pub fn visibleCount(self: *TreeView) !usize {
        try self.syncVisible();
        return self.visible.items.len;
    }
};

test "tree view expands and navigates" {
    const alloc = std.testing.allocator;
    var tree = try TreeView.init(alloc);
    defer tree.deinit();

    const root = try tree.addRoot("root");
    _ = try tree.addChild(root, "child");
    try tree.widget.layout(layout_module.Rect.init(0, 0, 20, 4));

    try tree.syncVisible();
    try std.testing.expectEqual(@as(usize, 1), try tree.visibleCount());

    const toggle = input.Event{ .key = input.KeyEvent{ .key = input.KeyCode.SPACE, .modifiers = .{} } };
    _ = try tree.widget.handleEvent(toggle);
    try tree.syncVisible();
    try std.testing.expectEqual(@as(usize, 2), try tree.visibleCount());

    const down = input.Event{ .key = input.KeyEvent{ .key = input.KeyCode.DOWN, .modifiers = .{} } };
    _ = try tree.widget.handleEvent(down);
    try std.testing.expect(tree.selected == 1);
}

test "tree view clamps stale selection before keyboard navigation" {
    const alloc = std.testing.allocator;
    var tree = try TreeView.init(alloc);
    defer tree.deinit();

    _ = try tree.addRoot("first");
    _ = try tree.addRoot("second");
    try tree.widget.layout(layout_module.Rect.init(0, 0, 20, 2));
    try tree.syncVisible();
    try std.testing.expectEqual(@as(usize, 2), tree.visible.items.len);

    tree.selected = std.math.maxInt(usize);
    const down = input.Event{ .key = input.KeyEvent{ .key = input.KeyCode.DOWN, .modifiers = .{} } };
    try std.testing.expect(!try tree.widget.handleEvent(down));
    try std.testing.expectEqual(@as(usize, 1), tree.selected);

    const up = input.Event{ .key = input.KeyEvent{ .key = input.KeyCode.UP, .modifiers = .{} } };
    try std.testing.expect(try tree.widget.handleEvent(up));
    try std.testing.expectEqual(@as(usize, 0), tree.selected);
}

test "tree view clamps stale selection before toggling node" {
    const alloc = std.testing.allocator;
    var tree = try TreeView.init(alloc);
    defer tree.deinit();

    const first = try tree.addRoot("first");
    const second = try tree.addRoot("second");
    _ = try tree.addChild(second, "child");
    try tree.widget.layout(layout_module.Rect.init(0, 0, 20, 3));
    try tree.syncVisible();

    tree.selected = std.math.maxInt(usize);
    const enter = input.Event{ .key = input.KeyEvent{ .key = input.KeyCode.ENTER, .modifiers = .{} } };
    try std.testing.expect(try tree.widget.handleEvent(enter));
    try std.testing.expectEqual(@as(usize, 1), tree.selected);
    try std.testing.expect(!tree.nodes.items[first].expanded);
    try std.testing.expect(tree.nodes.items[second].expanded);
}

test "tree view lazily rebuilds visible cache" {
    const alloc = std.testing.allocator;
    var tree = try TreeView.init(alloc);
    defer tree.deinit();

    _ = try tree.addRoot("first");
    _ = try tree.addRoot("second");

    try std.testing.expect(tree.visible_dirty);
    try std.testing.expectEqual(@as(usize, 2), try tree.visibleCount());
    try std.testing.expect(!tree.visible_dirty);

    _ = try tree.addChild(0, "child");
    try std.testing.expect(tree.visible_dirty);
    try std.testing.expectEqual(@as(usize, 2), try tree.visibleCount()); // child hidden until expanded
    try std.testing.expect(!tree.visible_dirty);

    tree.nodes.items[0].expanded = true;
    tree.visible_dirty = true;
    try std.testing.expectEqual(@as(usize, 3), try tree.visibleCount());
}

test "tree view direct visible state changes mark dirty" {
    const alloc = std.testing.allocator;
    var tree = try TreeView.init(alloc);
    defer tree.deinit();

    try tree.widget.layout(layout_module.Rect.init(0, 0, 20, 3));
    var renderer = try render.Renderer.init(alloc, 20, 3);
    defer renderer.deinit();

    try tree.widget.draw(&renderer);
    try std.testing.expect(!tree.widget.dirty);

    const root = try tree.addRoot("root");
    try std.testing.expect(tree.widget.dirty);

    try tree.widget.draw(&renderer);
    try std.testing.expect(!tree.widget.dirty);

    _ = try tree.addChild(root, "child");
    try std.testing.expect(tree.widget.dirty);

    try tree.widget.draw(&renderer);
    try std.testing.expect(!tree.widget.dirty);

    try tree.setTheme(theme.Theme.light());
    try std.testing.expect(tree.widget.dirty);

    try tree.widget.draw(&renderer);
    try std.testing.expect(!tree.widget.dirty);

    try tree.setTheme(theme.Theme.light());
    try std.testing.expect(!tree.widget.dirty);
}

fn treeViewAddChildAllocationFailureHarness(allocator: std.mem.Allocator) !void {
    var tree = try TreeView.init(allocator);
    defer tree.deinit();

    const root = try tree.addRoot("root");
    _ = try tree.addChild(root, "child");
}

test "tree view addChild cleans up every allocation failure path" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, treeViewAddChildAllocationFailureHarness, .{});
}

test "tree view addChild preserves state on allocation failure" {
    const alloc = std.testing.allocator;
    var tree = try TreeView.init(alloc);
    defer tree.deinit();

    const root = try tree.addRoot("root");
    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = tree.allocator;
    tree.allocator = failing.allocator();
    defer tree.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, tree.addChild(root, "child"));
    try std.testing.expectEqual(@as(usize, 1), tree.nodes.items.len);
    try std.testing.expectEqual(@as(usize, 0), tree.nodes.items[root].children.items.len);
}

test "tree view visible cache survives allocation failure" {
    const alloc = std.testing.allocator;
    var tree = try TreeView.init(alloc);
    defer tree.deinit();

    const root = try tree.addRoot("root");
    _ = try tree.addChild(root, "first");
    tree.nodes.items[root].expanded = true;
    try std.testing.expectEqual(@as(usize, 2), try tree.visibleCount());
    tree.visible.shrinkAndFree(tree.allocator, tree.visible.items.len);

    _ = try tree.addChild(root, "second");
    try std.testing.expect(tree.visible_dirty);

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = tree.allocator;
    tree.allocator = failing.allocator();
    defer tree.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, tree.syncVisible());
    try std.testing.expect(tree.visible_dirty);
    try std.testing.expectEqual(@as(usize, 2), tree.visible.items.len);
    try std.testing.expectEqual(@as(usize, root), tree.visible.items[0]);
}

test "tree view rejects invalid parent index" {
    const alloc = std.testing.allocator;
    var tree = try TreeView.init(alloc);
    defer tree.deinit();

    try std.testing.expectError(error.InvalidParent, tree.addChild(42, "missing"));
    try std.testing.expectEqual(@as(usize, 0), tree.nodes.items.len);
}

test "tree view saturates externally oversized depth" {
    const alloc = std.testing.allocator;
    var tree = try TreeView.init(alloc);
    defer tree.deinit();

    try std.testing.expectEqual(@as(u16, std.math.maxInt(u16)), TreeView.addU16Clamped(std.math.maxInt(u16), 2));

    const root = try tree.addRoot("root");
    tree.nodes.items[root].depth = std.math.maxInt(usize);
    tree.nodes.items[root].expanded = true;
    const child = try tree.addChild(root, "child");
    try std.testing.expectEqual(std.math.maxInt(usize), tree.nodes.items[child].depth);

    try tree.widget.layout(layout_module.Rect.init(0, 0, 8, 2));

    var renderer = try render.Renderer.init(alloc, 8, 2);
    defer renderer.deinit();
    try tree.widget.draw(&renderer);
}

test "tree view preferred size defaults when empty" {
    const alloc = std.testing.allocator;
    var tree = try TreeView.init(alloc);
    defer tree.deinit();

    try std.testing.expectEqual(@as(usize, 0), try tree.visibleCount());
    const size = try tree.widget.getPreferredSize();
    try std.testing.expectEqual(@as(u16, 12), size.width);
    try std.testing.expectEqual(@as(u16, 3), size.height);
}

test "tree view clips labels without splitting wide utf8 glyphs" {
    const alloc = std.testing.allocator;
    var tree = try TreeView.init(alloc);
    defer tree.deinit();

    _ = try tree.addRoot("界abcd");
    try tree.widget.layout(layout_module.Rect.init(0, 0, 7, 1));

    var renderer = try render.Renderer.init(alloc, 7, 1);
    defer renderer.deinit();
    renderer.capabilities.unicode = true;
    renderer.capabilities.double_width = true;

    try tree.widget.draw(&renderer);
    try std.testing.expectEqual(@as(u21, '界'), renderer.back.getCell(2, 0).*.codepoint());
    try std.testing.expect(renderer.back.getCell(3, 0).*.continuation);
    try std.testing.expectEqual(@as(u21, '.'), renderer.back.getCell(6, 0).*.codepoint());
}

test "tree view clamps edge draw coordinates" {
    const alloc = std.testing.allocator;
    var tree = try TreeView.init(alloc);
    defer tree.deinit();

    const root = try tree.addRoot("root");
    _ = try tree.addChild(root, "child");
    tree.nodes.items[root].expanded = true;
    try tree.widget.layout(layout_module.Rect.init(std.math.maxInt(u16) - 1, std.math.maxInt(u16) - 1, 8, 3));

    var renderer = try render.Renderer.init(alloc, 2, 2);
    defer renderer.deinit();
    try tree.widget.draw(&renderer);

    try std.testing.expectEqual(@as(u21, ' '), renderer.back.getCell(0, 0).*.codepoint());
    try std.testing.expectEqual(@as(u21, ' '), renderer.back.getCell(1, 1).*.codepoint());
}
