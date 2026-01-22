const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const theme = @import("../theme.zig");

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
        self.palette = palette;
    }

    pub fn addRoot(self: *TreeView, label: []const u8) !usize {
        return self.addNode(null, label);
    }

    pub fn addChild(self: *TreeView, parent_index: usize, label: []const u8) !usize {
        return self.addNode(parent_index, label);
    }

    fn addNode(self: *TreeView, parent_index: ?usize, label: []const u8) !usize {
        const children = std.ArrayList(usize).empty;
        const owned = try self.allocator.dupe(u8, label);
        const depth = if (parent_index) |idx| self.nodes.items[idx].depth + 1 else 0;
        const node = Node{
            .label = owned,
            .parent = parent_index,
            .children = children,
            .expanded = false,
            .depth = depth,
        };
        const index = self.nodes.items.len;
        try self.nodes.append(self.allocator, node);
        if (parent_index) |idx| {
            try self.nodes.items[idx].children.append(self.allocator, index);
        }
        self.visible_dirty = true;
        return index;
    }

    fn syncVisible(self: *TreeView) !void {
        if (!self.visible_dirty) return;
        self.visible_dirty = false;
        self.visible.clearRetainingCapacity();
        errdefer self.visible_dirty = true;
        for (self.nodes.items, 0..) |_, idx| {
            const node = self.nodes.items[idx];
            if (node.parent == null) {
                try self.collectVisible(idx);
            }
        }
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

    fn collectVisible(self: *TreeView, index: usize) !void {
        try self.visible.append(self.allocator, index);
        const node = &self.nodes.items[index];
        if (!node.expanded) return;
        for (node.children.items) |child_idx| {
            try self.collectVisible(child_idx);
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

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*TreeView, @ptrCast(@alignCast(widget_ptr)));
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
            const y_pos: u16 = rect.y + @as(u16, @intCast(row));
            const is_selected = visible_index == self.selected;
            const row_bg = if (is_selected) accent else surface;
            const row_fg = if (is_selected) self.palette.color(.background) else text;

            renderer.fillRect(rect.x, y_pos, rect.width, 1, ' ', row_fg, row_bg, self.palette.style);

            const indent: u16 = @min(rect.width, @as(u16, @intCast(node.depth * 2)));
            const marker: u21 = if (node.children.items.len > 0)
                (if (node.expanded) '▾' else '▸')
            else
                '•';

            if (indent < rect.width) {
                renderer.drawChar(rect.x + indent, y_pos, marker, if (node.children.items.len > 0) accent else muted, row_bg, self.palette.style);
            }

            const label_start = indent + 2;
            if (label_start < rect.width) {
                const max_label = @min(node.label.len, rect.width - label_start);
                renderer.drawStr(rect.x + label_start, y_pos, node.label[0..max_label], row_fg, row_bg, self.palette.style);
            }

            row += 1;
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*TreeView, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.enabled or !self.widget.visible) return false;

        try self.syncVisible();
        if (self.visible.items.len == 0) return false;

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
        const self = @as(*TreeView, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*TreeView, @ptrCast(@alignCast(widget_ptr)));
        const width_guess: usize = @min(self.visible.items.len + 8, @as(usize, 32));
        const height_guess: usize = @min(self.visible.items.len, @as(usize, 10));
        const width: u16 = @intCast(@max(width_guess, 12));
        const height: u16 = @intCast(if (height_guess == 0) 3 else height_guess);
        return layout_module.Size.init(width, height);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*TreeView, @ptrCast(@alignCast(widget_ptr)));
        return self.widget.enabled and self.widget.visible;
    }

    /// Visible nodes for testing and layout decisions.
    pub fn visibleCount(self: *TreeView) usize {
        self.syncVisible() catch {};
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
    try std.testing.expectEqual(@as(usize, 1), tree.visibleCount());

    const toggle = input.Event{ .key = input.KeyEvent{ .key = input.KeyCode.SPACE, .modifiers = .{} } };
    _ = try tree.handleEvent(toggle);
    try tree.syncVisible();
    try std.testing.expectEqual(@as(usize, 2), tree.visibleCount());

    const down = input.Event{ .key = input.KeyEvent{ .key = input.KeyCode.DOWN, .modifiers = .{} } };
    _ = try tree.handleEvent(down);
    try std.testing.expect(tree.selected == 1);
}

test "tree view lazily rebuilds visible cache" {
    const alloc = std.testing.allocator;
    var tree = try TreeView.init(alloc);
    defer tree.deinit();

    _ = try tree.addRoot("first");
    _ = try tree.addRoot("second");

    try std.testing.expect(tree.visible_dirty);
    try std.testing.expectEqual(@as(usize, 2), tree.visibleCount());
    try std.testing.expect(!tree.visible_dirty);

    _ = try tree.addChild(0, "child");
    try std.testing.expect(tree.visible_dirty);
    try std.testing.expectEqual(@as(usize, 2), tree.visibleCount()); // child hidden until expanded
    try std.testing.expect(!tree.visible_dirty);

    tree.nodes.items[0].expanded = true;
    tree.visible_dirty = true;
    try std.testing.expectEqual(@as(usize, 3), tree.visibleCount());
}

test "tree view preferred size defaults when empty" {
    const alloc = std.testing.allocator;
    var tree = try TreeView.init(alloc);
    defer tree.deinit();

    try std.testing.expectEqual(@as(usize, 0), tree.visibleCount());
    const size = try tree.widget.getPreferredSize();
    try std.testing.expectEqual(@as(u16, 12), size.width);
    try std.testing.expectEqual(@as(u16, 3), size.height);
}
