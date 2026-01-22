const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");

/// Grid container widget that arranges children using GridLayout.
pub const GridContainer = struct {
    widget: base.Widget,
    layout: *layout_module.GridLayout,
    children: std.ArrayList(Child),
    allocator: std.mem.Allocator,

    const Child = struct {
        widget: *base.Widget,
        column: u16,
        row: u16,
    };

    const LayoutContext = struct {
        err: ?anyerror = null,
    };

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator, columns: u16, rows: u16) !*GridContainer {
        const self = try allocator.create(GridContainer);
        errdefer allocator.destroy(self);

        const layout = try layout_module.GridLayout.init(allocator, columns, rows);
        errdefer layout.deinit();

        self.* = GridContainer{
            .widget = base.Widget.init(&vtable),
            .layout = layout,
            .children = std.ArrayList(Child).empty,
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *GridContainer) void {
        self.clearChildren();
        self.children.deinit(self.allocator);
        self.layout.deinit();
        self.allocator.destroy(self);
    }

    pub fn addChild(self: *GridContainer, child: *base.Widget, column: u16, row: u16) !void {
        self.removeChildAt(column, row);
        try self.layout.addChild(child.asLayoutElement(), column, row);
        try self.children.append(self.allocator, Child{ .widget = child, .column = column, .row = row });
        child.parent = &self.widget;
    }

    pub fn removeChild(self: *GridContainer, child: *base.Widget) void {
        for (self.children.items, 0..) |entry, idx| {
            if (entry.widget == child) {
                _ = self.children.orderedRemove(idx);
                child.parent = null;
                self.clearCell(entry.column, entry.row);
                break;
            }
        }
    }

    pub fn removeChildAt(self: *GridContainer, column: u16, row: u16) void {
        for (self.children.items, 0..) |entry, idx| {
            if (entry.column == column and entry.row == row) {
                entry.widget.parent = null;
                _ = self.children.orderedRemove(idx);
                break;
            }
        }
        self.clearCell(column, row);
    }

    pub fn clearChildren(self: *GridContainer) void {
        for (self.children.items) |entry| {
            entry.widget.parent = null;
        }
        self.children.clearRetainingCapacity();

        for (self.layout.cells.items) |*cell| {
            cell.* = null;
        }
        self.layout.cache.valid = false;
    }

    pub fn setColumns(self: *GridContainer, tracks: []const layout_module.GridTrack) !void {
        self.clearChildren();
        _ = try self.layout.setColumns(tracks);
    }

    pub fn setRows(self: *GridContainer, tracks: []const layout_module.GridTrack) !void {
        self.clearChildren();
        _ = try self.layout.setRows(tracks);
    }

    pub fn setPadding(self: *GridContainer, padding_value: layout_module.EdgeInsets) void {
        _ = self.layout.padding(padding_value);
    }

    pub fn setGap(self: *GridContainer, gap_value: u16) void {
        _ = self.layout.gap(gap_value);
    }

    fn clearCell(self: *GridContainer, column: u16, row: u16) void {
        if (column >= self.layout.columns or row >= self.layout.rows) return;
        const index = @as(usize, row) * @as(usize, self.layout.columns) + @as(usize, column);
        if (index >= self.layout.cells.items.len) return;
        self.layout.cells.items[index] = null;
        self.layout.cache.valid = false;
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*GridContainer, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;

        self.layout.renderLayout(renderer, self.widget.rect);
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*GridContainer, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible or !self.widget.enabled) return false;

        var idx: usize = self.children.items.len;
        while (idx > 0) {
            idx -= 1;
            const child = self.children.items[idx].widget;
            if (try child.handleEvent(event)) {
                return true;
            }
        }

        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*GridContainer, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;

        var ctx = LayoutContext{};
        self.layout.forEachCellRect(rect, &ctx, layoutCell);
        if (ctx.err) |err| return err;
    }

    fn layoutCell(ctx_ptr: *anyopaque, cell: layout_module.LayoutElement, rect: layout_module.Rect) void {
        const ctx = @as(*LayoutContext, @ptrCast(@alignCast(ctx_ptr)));
        if (ctx.err != null) return;

        const widget = @as(*base.Widget, @ptrCast(@alignCast(cell.ctx)));
        widget.layout(rect) catch |err| {
            ctx.err = err;
        };
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*GridContainer, @ptrCast(@alignCast(widget_ptr)));
        return self.layout.calculateLayout(layout_module.Constraints.loose(0, 0));
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*GridContainer, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.enabled) return false;

        for (self.children.items) |entry| {
            if (entry.widget.canFocus()) return true;
        }

        return false;
    }
};

test "grid container lays out children and forwards events" {
    const Dummy = struct {
        widget: base.Widget = base.Widget.init(&vtable),
        last_rect: ?layout_module.Rect = null,
        handled: bool = false,
        const Self = @This();

        const vtable = base.Widget.VTable{
            .draw = drawFn,
            .handle_event = handleEventFn,
            .layout = layoutFn,
            .get_preferred_size = preferredFn,
            .can_focus = canFocusFn,
        };

        fn drawFn(_: *anyopaque, _: *render.Renderer) anyerror!void {}
        fn handleEventFn(widget_ptr: *anyopaque, _: input.Event) anyerror!bool {
            const self = @as(*Self, @ptrCast(@alignCast(widget_ptr)));
            self.handled = true;
            return true;
        }
        fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
            const self = @as(*Self, @ptrCast(@alignCast(widget_ptr)));
            self.last_rect = rect;
        }
        fn preferredFn(_: *anyopaque) anyerror!layout_module.Size {
            return layout_module.Size.init(2, 1);
        }
        fn canFocusFn(_: *anyopaque) bool {
            return true;
        }
    };

    const alloc = std.testing.allocator;
    var grid = try GridContainer.init(alloc, 2, 1);
    defer grid.deinit();

    var left = Dummy{};
    var right = Dummy{};

    try grid.addChild(&left.widget, 0, 0);
    try grid.addChild(&right.widget, 1, 0);
    try std.testing.expectEqual(&grid.widget, left.widget.parent.?);

    try grid.widget.layout(layout_module.Rect.init(0, 0, 4, 1));
    try std.testing.expect(left.last_rect != null);
    try std.testing.expect(right.last_rect != null);

    const left_rect = left.last_rect.?;
    const right_rect = right.last_rect.?;
    try std.testing.expectEqual(@as(u16, 0), left_rect.x);
    try std.testing.expectEqual(@as(u16, 2), left_rect.width);
    try std.testing.expectEqual(@as(u16, 2), right_rect.x);
    try std.testing.expectEqual(@as(u16, 2), right_rect.width);

    const event = input.Event{ .key = input.KeyEvent.init('x', input.KeyModifiers{}) };
    try std.testing.expect(try grid.widget.handleEvent(event));
    try std.testing.expect(!left.handled);
    try std.testing.expect(right.handled);
}
