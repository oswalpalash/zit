const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");

/// Block widget: border + padding + optional title around a single child.
/// Mirrors the core "Block" primitive from other TUI stacks (ratatui/blessed).
pub const Block = struct {
    widget: base.Widget,
    allocator: std.mem.Allocator,
    title: ?[]u8 = null,
    border: render.BorderStyle = .single,
    fg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    bg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    title_color: render.Color = render.Color{ .named_color = render.NamedColor.default },
    title_style: render.Style = render.Style{ .bold = true },
    padding: Padding = Padding{},
    child: ?*base.Widget = null,

    pub const Padding = struct {
        left: u16 = 1,
        right: u16 = 1,
        top: u16 = 0,
        bottom: u16 = 0,
    };

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator) !*Block {
        const self = try allocator.create(Block);
        self.* = Block{
            .widget = base.Widget.init(&vtable),
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *Block) void {
        if (self.title) |t| self.allocator.free(t);
        self.allocator.destroy(self);
    }

    pub fn setBorder(self: *Block, border: render.BorderStyle) void {
        self.border = border;
    }

    pub fn setColors(self: *Block, fg: render.Color, bg: render.Color) void {
        self.fg = fg;
        self.bg = bg;
    }

    pub fn setTitle(self: *Block, title: []const u8) !void {
        if (self.title) |t| self.allocator.free(t);
        self.title = try self.allocator.dupe(u8, title);
    }

    pub fn setTitleStyle(self: *Block, color: render.Color, style: render.Style) void {
        self.title_color = color;
        self.title_style = style;
    }

    pub fn setPadding(self: *Block, padding: Padding) void {
        self.padding = padding;
    }

    /// Attach a child widget. Ownership stays with the caller.
    pub fn setChild(self: *Block, child: ?*base.Widget) void {
        self.child = child;
        if (child) |c| {
            c.parent = &self.widget;
        }
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*Block, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;

        const rect = self.widget.rect;
        if (rect.width == 0 or rect.height == 0) return;

        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', self.fg, self.bg, render.Style{});

        if (self.border != .none and rect.width >= 2 and rect.height >= 2) {
            renderer.drawBox(rect.x, rect.y, rect.width, rect.height, self.border, self.fg, self.bg, render.Style{});
        }

        if (self.title) |title_text| {
            const border_inset: u16 = if (self.border == .none) 0 else 1;
            if (rect.width > border_inset * 2 and rect.height > 0) {
                const start_x = rect.x + border_inset;
                const available: usize = @intCast(rect.width - border_inset * 2);
                const slice_len = @min(title_text.len, available);
                renderer.drawStr(start_x, rect.y, title_text[0..slice_len], self.title_color, self.bg, self.title_style);
            }
        }

        if (self.child) |child| {
            try child.*.draw(renderer);
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*Block, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible or !self.widget.enabled) return false;

        if (self.child) |child| {
            return child.*.handleEvent(event);
        }
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*Block, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;

        if (self.child) |child| {
            const inner = self.innerRect(rect);
            try child.*.layout(inner);
        }
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*Block, @ptrCast(@alignCast(widget_ptr)));
        const border_thickness: u16 = if (self.border == .none) 0 else 2;

        var preferred = layout_module.Size.init(border_thickness, border_thickness);
        preferred.width += self.padding.left + self.padding.right;
        preferred.height += self.padding.top + self.padding.bottom;

        if (self.child) |child| {
            const child_size = try child.*.getPreferredSize();
            preferred.width += child_size.width;
            preferred.height += child_size.height;
        }

        // Ensure a minimal footprint for border/title even without a child.
        preferred.width = @max(preferred.width, border_thickness + 2);
        preferred.height = @max(preferred.height, border_thickness + 1);
        return preferred;
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*Block, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.enabled) return false;
        if (self.child) |child| return child.*.canFocus();
        return false;
    }

    fn innerRect(self: *Block, rect: layout_module.Rect) layout_module.Rect {
        const border_inset: u16 = if (self.border == .none) 0 else 1;
        const x = rect.x + border_inset + self.padding.left;
        const y = rect.y + border_inset + self.padding.top;
        const width = if (rect.width > (border_inset * 2 + self.padding.left + self.padding.right))
            rect.width - (border_inset * 2 + self.padding.left + self.padding.right)
        else
            0;
        const height = if (rect.height > (border_inset * 2 + self.padding.top + self.padding.bottom))
            rect.height - (border_inset * 2 + self.padding.top + self.padding.bottom)
        else
            0;
        return layout_module.Rect.init(x, y, width, height);
    }
};

test "block applies padding and border to child layout" {
    const alloc = std.testing.allocator;

    const Dummy = struct {
        widget: base.Widget = base.Widget.init(&vtable),
        last_rect: ?layout_module.Rect = null,
        const Self = @This();

        const vtable = base.Widget.VTable{
            .draw = drawFn,
            .handle_event = handleEventFn,
            .layout = layoutFn,
            .get_preferred_size = preferredFn,
            .can_focus = canFocusFn,
        };

        fn drawFn(_: *anyopaque, _: *render.Renderer) anyerror!void {}
        fn handleEventFn(_: *anyopaque, _: input.Event) anyerror!bool {
            return false;
        }
        fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
            const self = @as(*Self, @ptrCast(@alignCast(widget_ptr)));
            self.last_rect = rect;
        }
        fn preferredFn(_: *anyopaque) anyerror!layout_module.Size {
            return layout_module.Size.init(4, 2);
        }
        fn canFocusFn(_: *anyopaque) bool {
            return false;
        }
    };

    var dummy = Dummy{};
    var block = try Block.init(alloc);
    defer block.deinit();
    block.setChild(&dummy.widget);
    block.setPadding(.{ .left = 1, .right = 1, .top = 1, .bottom = 1 });
    block.setBorder(.single);

    try block.widget.layout(layout_module.Rect.init(0, 0, 12, 6));

    try std.testing.expect(dummy.last_rect != null);
    const inner = dummy.last_rect.?;
    try std.testing.expectEqual(@as(u16, 2), inner.x);
    try std.testing.expectEqual(@as(u16, 2), inner.y);
    try std.testing.expectEqual(@as(u16, 8), inner.width);
    try std.testing.expectEqual(@as(u16, 2), inner.height);
}

test "block draws title inside border" {
    const alloc = std.testing.allocator;
    var block = try Block.init(alloc);
    defer block.deinit();
    try block.setTitle("Stats");
    block.setBorder(.single);
    try block.widget.layout(layout_module.Rect.init(0, 0, 8, 3));

    var renderer = try render.Renderer.init(alloc, 8, 3);
    defer renderer.deinit();
    try block.widget.draw(&renderer);

    const cell = renderer.back.getCell(1, 0).*;
    try std.testing.expectEqual('S', cell.ch);
}
