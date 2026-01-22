const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");

/// Lazy factory for tab content, called when a tab is first activated.
pub const TabLoader = *const fn (std.mem.Allocator) anyerror!*base.Widget;

/// Tab item structure
pub const TabItem = struct {
    /// Tab title
    title: []const u8,
    /// Tab content widget
    content: ?*base.Widget = null,
    /// Optional lazy loader for content
    loader: ?TabLoader = null,
    /// Whether the tab can be closed from the UI
    closable: bool = false,
    /// Track whether lazy content has been created
    loaded: bool = false,
};

/// Declarative tab specification for creation helpers.
pub const TabSpec = struct {
    title: []const u8,
    content: ?*base.Widget = null,
    loader: ?TabLoader = null,
    closable: bool = false,
};

/// Lightweight tab strip that can be embedded without a TabView.
pub const TabBar = struct {
    widget: base.Widget,
    tabs: []const TabItem = &.{},
    active_tab: usize = 0,
    tab_height: i16 = 1,
    tab_padding: i16 = 1,
    allow_close: bool = false,
    allow_reorder: bool = false,
    fg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    bg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    active_fg: render.Color = render.Color{ .named_color = render.NamedColor.black },
    active_bg: render.Color = render.Color{ .named_color = render.NamedColor.cyan },
    inactive_fg: render.Color = render.Color{ .named_color = render.NamedColor.white },
    inactive_bg: render.Color = render.Color{ .named_color = render.NamedColor.blue },
    on_tab_selected: ?*const fn (usize, ?*anyopaque) void = null,
    on_tab_closed: ?*const fn (usize, ?*anyopaque) void = null,
    on_tab_reordered: ?*const fn (usize, usize, ?*anyopaque) void = null,
    callback_ctx: ?*anyopaque = null,
    allocator: std.mem.Allocator,

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator) !*TabBar {
        const self = try allocator.create(TabBar);
        self.* = TabBar{
            .widget = base.Widget.init(&vtable),
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *TabBar) void {
        self.allocator.destroy(self);
    }

    pub fn setTabs(self: *TabBar, tabs: []const TabItem) void {
        self.tabs = tabs;
    }

    pub fn setActive(self: *TabBar, idx: usize) void {
        if (self.tabs.len == 0) {
            self.active_tab = 0;
            return;
        }
        self.active_tab = @min(idx, self.tabs.len - 1);
    }

    pub fn setCallbacks(
        self: *TabBar,
        select: ?*const fn (usize, ?*anyopaque) void,
        close: ?*const fn (usize, ?*anyopaque) void,
        reorder: ?*const fn (usize, usize, ?*anyopaque) void,
        ctx: ?*anyopaque,
    ) void {
        self.on_tab_selected = select;
        self.on_tab_closed = close;
        self.on_tab_reordered = reorder;
        self.callback_ctx = ctx;
    }

    pub fn setTabColors(self: *TabBar, fg: render.Color, bg: render.Color, active_fg: render.Color, active_bg: render.Color, inactive_fg: render.Color, inactive_bg: render.Color) void {
        self.fg = fg;
        self.bg = bg;
        self.active_fg = active_fg;
        self.active_bg = active_bg;
        self.inactive_fg = inactive_fg;
        self.inactive_bg = inactive_bg;
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*TabBar, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;

        const rect = self.widget.rect;
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', self.fg, self.bg, render.Style{});

        var x = rect.x;
        for (self.tabs, 0..) |tab, i| {
            const is_active = i == self.active_tab;
            const tab_fg = if (is_active) self.active_fg else self.inactive_fg;
            const tab_bg = if (is_active) self.active_bg else self.inactive_bg;
            const width = self.tabWidth(tab);
            if (x >= rect.x + rect.width) break;

            renderer.fillRect(x, rect.y, width, self.tab_height, ' ', tab_fg, tab_bg, render.Style{});

            const cursor = x + self.tab_padding;
            for (tab.title, 0..) |char, j| {
                if (cursor + @as(i16, @intCast(j)) >= rect.x + rect.width) break;
                renderer.drawChar(cursor + @as(i16, @intCast(j)), rect.y, char, tab_fg, tab_bg, render.Style{});
            }

            if (tab.closable or self.allow_close) {
                const close_x = x + width - self.tab_padding - 1;
                if (close_x < rect.x + rect.width) {
                    renderer.drawChar(close_x, rect.y, 'x', tab_fg, tab_bg, render.Style{ .bold = true });
                }
            }

            x += width + 1;
        }

        self.widget.drawFocusRing(renderer);
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*TabBar, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible or self.tabs.len == 0) return false;

        if (event == .mouse) {
            const m = event.mouse;
            if (m.action == .press and m.button == 1) {
                if (self.getTabIndexAt(m.x, m.y)) |idx| {
                    if (self.isOnCloseGlyph(m.x, idx)) {
                        if ((self.tabs[idx].closable or self.allow_close) and self.on_tab_closed != null) {
                            self.on_tab_closed.?(idx, self.callback_ctx);
                            return true;
                        }
                    } else {
                        self.setActive(idx);
                        if (self.on_tab_selected) |cb| cb(idx, self.callback_ctx);
                        return true;
                    }
                }
            }
        } else if (event == .key and self.widget.focused) {
            const key = event.key;
            if (key.key == input.KeyCode.LEFT) {
                if (self.active_tab > 0) {
                    self.setActive(self.active_tab - 1);
                    if (self.on_tab_selected) |cb| cb(self.active_tab, self.callback_ctx);
                    return true;
                }
            } else if (key.key == input.KeyCode.RIGHT) {
                if (self.active_tab + 1 < self.tabs.len) {
                    self.setActive(self.active_tab + 1);
                    if (self.on_tab_selected) |cb| cb(self.active_tab, self.callback_ctx);
                    return true;
                }
            } else if (key.key == 'w' and key.modifiers.ctrl) {
                if (self.on_tab_closed != null and (self.tabs[self.active_tab].closable or self.allow_close)) {
                    self.on_tab_closed.?(self.active_tab, self.callback_ctx);
                    return true;
                }
            } else if (self.allow_reorder and key.modifiers.ctrl and key.modifiers.shift and (key.key == input.KeyCode.LEFT or key.key == input.KeyCode.RIGHT)) {
                const target = if (key.key == input.KeyCode.LEFT)
                    if (self.active_tab == 0) @as(usize, 0) else self.active_tab - 1
                else if (self.active_tab + 1 < self.tabs.len)
                    self.active_tab + 1
                else
                    self.active_tab;

                if (target != self.active_tab and self.on_tab_reordered != null) {
                    self.on_tab_reordered.?(self.active_tab, target, self.callback_ctx);
                    return true;
                }
            } else if (key.isPrintable() and key.key >= '1' and key.key <= '9') {
                const target = @as(usize, @intCast(key.key - '1'));
                if (target < self.tabs.len) {
                    self.setActive(target);
                    if (self.on_tab_selected) |cb| cb(target, self.callback_ctx);
                    return true;
                }
            }
        }

        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*TabBar, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*TabBar, @ptrCast(@alignCast(widget_ptr)));
        var width: i16 = 2;
        for (self.tabs) |tab| {
            width += self.tabWidth(tab) + 1;
        }
        return layout_module.Size.init(width, self.tab_height);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*TabBar, @ptrCast(@alignCast(widget_ptr)));
        return self.widget.enabled and self.tabs.len > 0;
    }

    fn getTabIndexAt(self: *TabBar, x: i16, y: i16) ?usize {
        if (y < self.widget.rect.y or y >= self.widget.rect.y + self.tab_height) return null;
        var tab_x = self.widget.rect.x;
        for (self.tabs, 0..) |tab, idx| {
            const width = self.tabWidth(tab);
            if (x >= tab_x and x < tab_x + width) {
                return idx;
            }
            tab_x += width + 1;
        }
        return null;
    }

    fn isOnCloseGlyph(self: *TabBar, x: i16, idx: usize) bool {
        if (!(self.tabs[idx].closable or self.allow_close)) return false;
        var tab_x = self.widget.rect.x;
        for (self.tabs, 0..) |tab, i| {
            const width = self.tabWidth(tab);
            if (i == idx) {
                const close_x = tab_x + width - self.tab_padding - 1;
                return x == close_x;
            }
            tab_x += width + 1;
        }
        return false;
    }

    fn tabWidth(self: TabBar, tab: TabItem) i16 {
        const close_extra: i16 = if (tab.closable or self.allow_close) 2 else 0;
        return @as(i16, @intCast(tab.title.len)) + self.tab_padding * 2 + close_extra;
    }
};

/// Tab view widget for managing tabbed interfaces
pub const TabView = struct {
    /// Base widget
    widget: base.Widget,
    /// Tabs
    tabs: std.ArrayList(TabItem),
    /// Tab strip widget
    tab_bar: *TabBar,
    /// Active tab index
    active_tab: usize = 0,
    /// Tab height
    tab_height: i16 = 1,
    /// Tab padding
    tab_padding: i16 = 1,
    /// Normal foreground color
    fg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    /// Normal background color
    bg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    /// Active tab foreground color
    active_fg: render.Color = render.Color{ .named_color = render.NamedColor.black },
    /// Active tab background color
    active_bg: render.Color = render.Color{ .named_color = render.NamedColor.cyan },
    /// Inactive tab foreground color
    inactive_fg: render.Color = render.Color{ .named_color = render.NamedColor.white },
    /// Inactive tab background color
    inactive_bg: render.Color = render.Color{ .named_color = render.NamedColor.blue },
    /// Border color
    border_fg: render.Color = render.Color{ .named_color = render.NamedColor.white },
    /// Show border
    show_border: bool = true,
    /// On tab changed callback
    on_tab_changed: ?*const fn (usize) void = null,
    /// Allocator for tab view operations
    allocator: std.mem.Allocator,

    /// Virtual method table for TabView
    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    /// Initialize a new tab view
    pub fn init(allocator: std.mem.Allocator) !*TabView {
        const header = try TabBar.init(allocator);
        errdefer header.deinit();

        const self = try allocator.create(TabView);
        self.* = TabView{
            .widget = base.Widget.init(&vtable),
            .tabs = std.ArrayList(TabItem).empty,
            .tab_bar = header,
            .allocator = allocator,
        };
        self.configureHeader();
        return self;
    }

    /// Clean up tab view resources
    pub fn deinit(self: *TabView) void {
        for (self.tabs.items) |tab| {
            self.allocator.free(tab.title);
        }
        self.tabs.deinit(self.allocator);
        self.tab_bar.deinit();
        self.allocator.destroy(self);
    }

    /// Add a tab to the tab view
    pub fn addTab(self: *TabView, title: []const u8, content: *base.Widget) !void {
        try self.addTabSpec(.{ .title = title, .content = content });
    }

    /// Add a tab whose content will be created on first activation.
    pub fn addLazyTab(self: *TabView, title: []const u8, loader: TabLoader, closable: bool) !void {
        try self.addTabSpec(.{ .title = title, .loader = loader, .closable = closable });
    }

    /// Create a tab from a specification.
    pub fn addTabSpec(self: *TabView, spec: TabSpec) !void {
        const title_copy = try self.allocator.dupe(u8, spec.title);
        try self.tabs.append(self.allocator, TabItem{
            .title = title_copy,
            .content = spec.content,
            .loader = spec.loader,
            .closable = spec.closable,
            .loaded = spec.content != null,
        });
        if (spec.content) |content| {
            content.parent = &self.widget;
        }
        self.syncHeader();

        if (self.tabs.items.len == 1) {
            self.setActiveTab(0);
        }
    }

    /// Remove a tab from the tab view
    pub fn removeTab(self: *TabView, index: usize) void {
        if (index >= self.tabs.items.len) return;
        const old_active = self.active_tab;
        self.allocator.free(self.tabs.items[index].title);
        _ = self.tabs.orderedRemove(index);

        if (self.tabs.items.len == 0) {
            self.active_tab = 0;
        } else if (self.active_tab >= self.tabs.items.len) {
            self.active_tab = self.tabs.items.len - 1;
        }
        self.syncHeader();
        self.syncVisibility();

        if (self.on_tab_changed != null and old_active != self.active_tab and self.tabs.items.len > 0) {
            self.on_tab_changed.?(self.active_tab);
        }
    }

    /// Move a tab to a new index for reordering.
    pub fn moveTab(self: *TabView, from: usize, to: usize) !void {
        if (from >= self.tabs.items.len or to >= self.tabs.items.len or from == to) return;
        const moved = self.tabs.orderedRemove(from);
        try self.tabs.insert(self.allocator, to, moved);

        if (self.active_tab == from) {
            self.active_tab = to;
        } else if (from < self.active_tab and to >= self.active_tab) {
            self.active_tab -= 1;
        } else if (from > self.active_tab and to <= self.active_tab) {
            self.active_tab += 1;
        }

        self.syncHeader();
        self.syncVisibility();
    }

    /// Set the active tab
    pub fn setActiveTab(self: *TabView, index: usize) void {
        if (self.tabs.items.len == 0) {
            self.active_tab = 0;
            self.tab_bar.setActive(0);
            return;
        }

        const clamped = @min(index, self.tabs.items.len - 1);
        if (clamped == self.active_tab) {
            self.ensureTabLoaded(clamped);
            self.syncVisibility();
            return;
        }

        self.active_tab = clamped;
        self.ensureTabLoaded(clamped);
        self.syncVisibility();
        self.tab_bar.setActive(clamped);

        if (self.on_tab_changed) |cb| {
            cb(self.active_tab);
        }
    }

    /// Get the active tab index
    pub fn getActiveTab(self: *TabView) usize {
        return self.active_tab;
    }

    /// Get the active tab content widget
    pub fn getActiveContent(self: *TabView) ?*base.Widget {
        if (self.tabs.items.len == 0) return null;
        self.ensureTabLoaded(self.active_tab);
        return self.tabs.items[self.active_tab].content;
    }

    /// Set the tab view colors
    pub fn setColors(self: *TabView, fg: render.Color, bg: render.Color, active_fg: render.Color, active_bg: render.Color, inactive_fg: render.Color, inactive_bg: render.Color) void {
        self.fg = fg;
        self.bg = bg;
        self.active_fg = active_fg;
        self.active_bg = active_bg;
        self.inactive_fg = inactive_fg;
        self.inactive_bg = inactive_bg;
        self.configureHeader();
    }

    /// Set the border options
    pub fn setBorder(self: *TabView, show_border: bool, border_fg: render.Color) void {
        self.show_border = show_border;
        self.border_fg = border_fg;
    }

    /// Set the on-tab-changed callback
    pub fn setOnTabChanged(self: *TabView, callback: *const fn (usize) void) void {
        self.on_tab_changed = callback;
    }

    /// Allow keyboard-driven tab movement.
    pub fn setReorderable(self: *TabView, allow: bool) void {
        self.tab_bar.allow_reorder = allow;
    }

    /// Enable close controls even for tabs not explicitly marked closable.
    pub fn setAllowClosing(self: *TabView, allow: bool) void {
        self.tab_bar.allow_close = allow;
    }

    fn ensureTabLoaded(self: *TabView, idx: usize) void {
        if (idx >= self.tabs.items.len) return;
        var tab = &self.tabs.items[idx];
        if (tab.loaded or tab.loader == null) return;

        const builder = tab.loader.?;
        const content = builder(self.allocator) catch |err| {
            std.log.err("zit.widget: tab loader failed: {s}", .{@errorName(err)});
            return;
        };
        tab.content = content;
        tab.loaded = true;

        if (tab.content) |tab_content| {
            tab_content.parent = &self.widget;
            const rect = self.contentRect();
            tab_content.layout(rect) catch {};
        }
    }

    fn isTabClosable(self: *TabView, idx: usize) bool {
        if (idx >= self.tabs.items.len) return false;
        return self.tabs.items[idx].closable or self.tab_bar.allow_close;
    }

    fn configureHeader(self: *TabView) void {
        self.tab_bar.widget.parent = &self.widget;
        self.tab_bar.tab_height = self.tab_height;
        self.tab_bar.tab_padding = self.tab_padding;
        self.tab_bar.setTabColors(self.fg, self.bg, self.active_fg, self.active_bg, self.inactive_fg, self.inactive_bg);
        self.tab_bar.setTabs(self.tabs.items);
        self.tab_bar.setActive(self.active_tab);
        self.tab_bar.setCallbacks(onTabSelected, onTabClosed, onTabReordered, self);
    }

    fn syncVisibility(self: *TabView) void {
        for (self.tabs.items, 0..) |tab, i| {
            if (tab.content) |content| {
                content.visible = (i == self.active_tab);
            }
        }
    }

    fn contentRect(self: *TabView) layout_module.Rect {
        var rect = self.widget.rect;
        rect.y += self.tab_bar.tab_height;
        rect.height = if (rect.height > self.tab_bar.tab_height) rect.height - self.tab_bar.tab_height else 0;
        if (self.show_border and rect.height >= 2 and rect.width >= 2) {
            rect.x += 1;
            rect.y += 1;
            rect.width -= 2;
            rect.height -= 2;
        }
        return rect;
    }

    /// Draw implementation for TabView
    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*TabView, @ptrCast(widget_ptr));
        if (!self.widget.visible) return;

        const rect = self.widget.rect;
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', self.fg, self.bg, render.Style{});
        try self.tab_bar.widget.draw(renderer);
        if (self.show_border and rect.width > 1 and rect.height > self.tab_bar.tab_height + 1) {
            renderer.drawBox(
                rect.x,
                rect.y + self.tab_bar.tab_height,
                rect.width,
                rect.height - self.tab_bar.tab_height,
                .single,
                self.border_fg,
                self.bg,
                render.Style{},
            );
        }

        if (self.tabs.items.len > 0) {
            self.ensureTabLoaded(self.active_tab);
            if (self.tabs.items[self.active_tab].content) |content| {
                try content.draw(renderer);
            }
        }

        self.widget.drawFocusRing(renderer);
    }

    /// Event handling implementation for TabView
    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*TabView, @ptrCast(widget_ptr));

        if (!self.widget.visible or !self.widget.enabled or self.tabs.items.len == 0) {
            return false;
        }

        if (try self.tab_bar.widget.handleEvent(event)) {
            return true;
        }

        const active_content = self.getActiveContent() orelse return false;
        return active_content.handleEvent(event);
    }

    /// Layout implementation for TabView
    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*TabView, @ptrCast(widget_ptr));
        self.widget.rect = rect;

        const header_rect = layout_module.Rect.init(rect.x, rect.y, rect.width, self.tab_bar.tab_height);
        try self.tab_bar.widget.layout(header_rect);

        const content_rect = self.contentRect();
        for (self.tabs.items) |tab| {
            if (tab.content) |content| {
                try content.layout(content_rect);
            }
        }
    }

    /// Get preferred size implementation for TabView
    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*TabView, @ptrCast(widget_ptr));

        var width: i16 = 20;
        var height: i16 = self.tab_bar.tab_height;

        const header_size = try self.tab_bar.widget.getPreferredSize();
        width = @max(width, header_size.width);
        height = @max(height, header_size.height);

        if (self.getActiveContent()) |content| {
            const content_size = try content.getPreferredSize();
            const border_space: i16 = if (self.show_border) 2 else 0;
            width = @max(width, content_size.width + border_space * 2);
            height += content_size.height + border_space * 2;
        } else {
            height += 6;
        }

        return layout_module.Size.init(width, height);
    }

    /// Can focus implementation for TabView
    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*TabView, @ptrCast(widget_ptr));
        if (!self.widget.enabled or self.tabs.items.len == 0) return false;

        if (self.tab_bar.widget.canFocus()) return true;
        if (self.getActiveContent()) |content| {
            if (content.canFocus()) return true;
        }
        return true;
    }

    fn onTabSelected(index: usize, ctx: ?*anyopaque) void {
        const self = @as(*TabView, @ptrCast(@alignCast(ctx orelse return)));
        self.setActiveTab(index);
    }

    fn onTabClosed(index: usize, ctx: ?*anyopaque) void {
        const self = @as(*TabView, @ptrCast(@alignCast(ctx orelse return)));
        if (self.isTabClosable(index)) {
            self.removeTab(index);
        }
    }

    fn onTabReordered(from: usize, to: usize, ctx: ?*anyopaque) void {
        const self = @as(*TabView, @ptrCast(@alignCast(ctx orelse return)));
        self.moveTab(from, to) catch {};
    }
};

test "tab view lazy loads content on first activation" {
    const alloc = std.testing.allocator;
    var tab_view = try TabView.init(alloc);
    defer tab_view.deinit();

    const Lazy = struct {
        var loaded = false;
        fn build(allocator: std.mem.Allocator) anyerror!*base.Widget {
            @This().loaded = true;
            const label = try @import("label.zig").Label.init(allocator, "lazy");
            return &label.widget;
        }
    };

    Lazy.loaded = false;
    try tab_view.addLazyTab("lazy", Lazy.build, false);
    try std.testing.expect(!Lazy.loaded);
    tab_view.setActiveTab(0);
    try std.testing.expect(Lazy.loaded);
    try std.testing.expect(tab_view.getActiveContent() != null);
    const content = tab_view.getActiveContent().?;
    const lbl_ptr = @as(*@import("label.zig").Label, @ptrCast(@alignCast(content)));
    lbl_ptr.deinit();
    tab_view.tabs.items[0].content = null;
}

test "tab view reorders tabs and keeps active index in sync" {
    const alloc = std.testing.allocator;
    var tab_view = try TabView.init(alloc);
    defer tab_view.deinit();

    var a = try @import("block.zig").Block.init(alloc);
    defer a.deinit();
    var b = try @import("block.zig").Block.init(alloc);
    defer b.deinit();

    try tab_view.addTab("one", &a.widget);
    try tab_view.addTab("two", &b.widget);
    tab_view.setActiveTab(1);
    try tab_view.moveTab(1, 0);
    try std.testing.expectEqual(@as(usize, 0), tab_view.getActiveTab());
    try std.testing.expectEqualStrings("two", tab_view.tabs.items[0].title);
}

test "tab view closes tabs only when marked closable" {
    const alloc = std.testing.allocator;
    var tab_view = try TabView.init(alloc);
    defer tab_view.deinit();

    var a = try @import("block.zig").Block.init(alloc);
    defer a.deinit();
    var b = try @import("block.zig").Block.init(alloc);
    defer b.deinit();

    try tab_view.addTab("one", &a.widget);
    try tab_view.addTabSpec(.{ .title = "two", .content = &b.widget, .closable = true });
    const before = tab_view.tabs.items.len;
    TabView.onTabClosed(1, tab_view);
    try std.testing.expectEqual(before - 1, tab_view.tabs.items.len);
    TabView.onTabClosed(0, tab_view);
    try std.testing.expectEqual(before - 1, tab_view.tabs.items.len);
}
