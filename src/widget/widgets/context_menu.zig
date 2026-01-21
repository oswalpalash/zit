const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const theme = @import("../theme.zig");

/// Item entry for context menus.
pub const MenuItem = struct {
    label: []const u8,
    enabled: bool = true,
    data: ?*anyopaque = null,
};

    /// Lightweight context menu that can be opened at an arbitrary position.
    pub const ContextMenu = struct {
        widget: base.Widget,
        allocator: std.mem.Allocator,
        items: std.ArrayList(MenuItem),
        theme_value: theme.Theme,
    open: bool = false,
    selected: usize = 0,
    max_visible: usize = 8,
    on_select: ?*const fn (usize, MenuItem, ?*anyopaque) void = null,
    on_select_ctx: ?*anyopaque = null,

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator) !*ContextMenu {
        const self = try allocator.create(ContextMenu);
        self.* = ContextMenu{
            .widget = base.Widget.init(&vtable),
            .allocator = allocator,
            .items = try std.ArrayList(MenuItem).initCapacity(allocator, 0),
            .theme_value = theme.Theme.dark(),
        };
        return self;
    }

    pub fn deinit(self: *ContextMenu) void {
        self.clear();
        self.items.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn addItem(self: *ContextMenu, label: []const u8, enabled: bool, data: ?*anyopaque) !void {
        const copy = try self.allocator.dupe(u8, label);
        try self.items.append(self.allocator, .{ .label = copy, .enabled = enabled, .data = data });
    }

    pub fn clear(self: *ContextMenu) void {
        for (self.items.items) |item| {
            self.allocator.free(item.label);
        }
        self.items.clearRetainingCapacity();
        self.selected = 0;
    }

    pub fn setTheme(self: *ContextMenu, t: theme.Theme) void {
        self.theme_value = t;
    }

    pub fn setOnSelect(self: *ContextMenu, callback: *const fn (usize, MenuItem, ?*anyopaque) void, ctx: ?*anyopaque) void {
        self.on_select = callback;
        self.on_select_ctx = ctx;
    }

    pub fn setMaxVisible(self: *ContextMenu, count: usize) void {
        self.max_visible = @max(@as(usize, 1), count);
    }

    pub fn openAt(self: *ContextMenu, x: u16, y: u16) void {
        self.open = true;
        self.selected = 0;
        self.widget.rect.x = x;
        self.widget.rect.y = y;
        self.widget.rect.height = self.computedHeight();
    }

    pub fn close(self: *ContextMenu) void {
        self.open = false;
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*ContextMenu, @ptrCast(@alignCast(widget_ptr)));
        if (!self.open or !self.widget.visible) return;
        const rect = self.widget.rect;
        if (rect.width == 0 or rect.height == 0) return;

        const fg = self.theme_value.color(.text);
        const bg = self.theme_value.color(.surface);
        const highlight_fg = self.theme_value.color(.background);
        const highlight_bg = self.theme_value.color(.accent);
        const disabled = self.theme_value.color(.muted);

        const visible_rows: usize = @intCast(@min(self.items.items.len, self.max_visible));
        if (visible_rows == 0) return;

        renderer.drawBox(rect.x, rect.y, rect.width, rect.height, render.BorderStyle.single, fg, bg, render.Style{});
        renderer.fillRect(rect.x + 1, rect.y + 1, rect.width - 2, rect.height - 2, ' ', fg, bg, render.Style{});

        var row: usize = 0;
        while (row < visible_rows) : (row += 1) {
            const item_y = rect.y + 1 + @as(u16, @intCast(row));
            const idx = row;
            const item = self.items.items[idx];
            const is_selected = idx == self.selected;
            const row_fg = if (!item.enabled) disabled else if (is_selected) highlight_fg else fg;
            const row_bg = if (is_selected) highlight_bg else bg;
            renderer.fillRect(rect.x + 1, item_y, rect.width - 2, 1, ' ', row_fg, row_bg, render.Style{});
            renderer.drawSmartStr(rect.x + 2, item_y, item.label, row_fg, row_bg, render.Style{ .bold = is_selected });
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*ContextMenu, @ptrCast(@alignCast(widget_ptr)));
        if (!self.open or !self.widget.enabled) return false;

        switch (event) {
            .key => |key_event| {
                if (!self.widget.focused) return false;
                switch (key_event.key) {
                    input.KeyCode.UP => {
                        if (self.selected > 0) self.selected -= 1;
                        return true;
                    },
                    input.KeyCode.DOWN => {
                        if (self.selected + 1 < self.items.items.len and self.selected + 1 < self.max_visible) {
                            self.selected += 1;
                        }
                        return true;
                    },
                    input.KeyCode.ENTER, input.KeyCode.SPACE => {
                        return self.activateSelected();
                    },
                    input.KeyCode.ESCAPE => {
                        self.close();
                        return true;
                    },
                    else => {},
                }
            },
            .mouse => |mouse_event| {
                const rect = self.widget.rect;
                const inside_x = mouse_event.x >= rect.x and mouse_event.x < rect.x + rect.width;
                const inside_y = mouse_event.y >= rect.y and mouse_event.y < rect.y + rect.height;
                if (inside_x and inside_y) {
                    if (mouse_event.y > rect.y and mouse_event.y < rect.y + rect.height - 1) {
                        const idx = @as(usize, @intCast(mouse_event.y - rect.y - 1));
                        if (idx < self.items.items.len and idx < self.max_visible) {
                            self.selected = idx;
                            if (mouse_event.action == .press and mouse_event.button == 1) {
                                return self.activateSelected();
                            }
                        }
                    }
                    return true;
                }

                if (mouse_event.action == .press) {
                    self.close();
                }
                return false;
            },
            else => {},
        }

        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*ContextMenu, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
        if (self.open) self.widget.rect.height = self.computedHeight();
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*ContextMenu, @ptrCast(@alignCast(widget_ptr)));
        const width = self.preferredWidth();
        const height = self.computedHeight();
        return layout_module.Size.init(width, if (height == 0) 2 else height);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*ContextMenu, @ptrCast(@alignCast(widget_ptr)));
        return self.widget.enabled and self.open;
    }

    fn preferredWidth(self: *const ContextMenu) u16 {
        var max_len: usize = 4; // padding + border
        for (self.items.items) |item| {
            max_len = @max(max_len, item.label.len + 4);
        }
        return @intCast(max_len);
    }

    fn computedHeight(self: *const ContextMenu) u16 {
        const visible_rows: usize = @min(self.items.items.len, self.max_visible);
        if (visible_rows == 0) return 0;
        return @intCast(visible_rows + 2);
    }

    fn activateSelected(self: *ContextMenu) !bool {
        if (self.items.items.len == 0 or self.selected >= self.items.items.len) return false;
        const item = self.items.items[self.selected];
        if (!item.enabled) return false;
        if (self.on_select) |cb| {
            cb(self.selected, item, self.on_select_ctx);
        }
        self.close();
        return true;
    }
};

test "context menu selection via keyboard" {
    const alloc = std.testing.allocator;
    var menu = try ContextMenu.init(alloc);
    defer menu.deinit();
    try menu.addItem("One", true, null);
    try menu.addItem("Two", true, null);

    const pref = try menu.widget.getPreferredSize();
    try menu.widget.layout(layout_module.Rect.init(0, 0, pref.width, pref.height));
    menu.widget.setFocus(true);
    menu.openAt(0, 0);

    var selection: usize = 0;
    const Callbacks = struct {
        fn onSelect(idx: usize, _: MenuItem, ctx: ?*anyopaque) void {
            if (ctx) |ptr| {
                const slot = @as(*usize, @ptrCast(@alignCast(ptr)));
                slot.* = idx;
            }
        }
    };
    menu.setOnSelect(Callbacks.onSelect, &selection);

    const down = input.Event{ .key = input.KeyEvent.init(input.KeyCode.DOWN, .{}) };
    try std.testing.expect(try menu.widget.handleEvent(down));
    const enter = input.Event{ .key = input.KeyEvent.init(input.KeyCode.ENTER, .{}) };
    try std.testing.expect(try menu.widget.handleEvent(enter));
    try std.testing.expectEqual(@as(usize, 1), selection);
    try std.testing.expect(!menu.open);
}

test "context menu closes on outside click" {
    const alloc = std.testing.allocator;
    var menu = try ContextMenu.init(alloc);
    defer menu.deinit();
    try menu.addItem("Exit", true, null);
    menu.openAt(0, 0);
    try menu.widget.layout(layout_module.Rect.init(0, 0, 12, 3));

    const click = input.Event{ .mouse = input.MouseEvent.init(input.MouseAction.press, 20, 20, 1) };
    _ = try menu.widget.handleEvent(click);
    try std.testing.expect(!menu.open);
}
