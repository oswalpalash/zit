const std = @import("std");
const layout = @import("layout/layout.zig");
const render = @import("render/render.zig");
const widget = @import("widget/widget.zig");
const event_mod = @import("event/event.zig");

fn widgetTypeName(base_ptr: *widget.Widget) []const u8 {
    if (asWidget(widget.Container, base_ptr) != null) return "Container";
    if (asWidget(widget.ScrollContainer, base_ptr) != null) return "ScrollContainer";
    if (asWidget(widget.SplitPane, base_ptr) != null) return "SplitPane";
    if (asWidget(widget.TabView, base_ptr) != null) return "TabView";
    if (asWidget(widget.Block, base_ptr) != null) return "Block";
    if (asWidget(widget.Modal, base_ptr) != null) return "Modal";
    return "Widget";
}

fn asWidget(comptime T: type, base_ptr: *widget.Widget) ?*T {
    if (!@hasDecl(T, "vtable") or !@hasField(T, "widget")) return null;
    if (base_ptr.vtable == &T.vtable) {
        return @alignCast(@fieldParentPtr("widget", base_ptr));
    }
    return null;
}

fn collectChildren(allocator: std.mem.Allocator, base_ptr: *widget.Widget, out: *std.ArrayList(*widget.Widget)) !void {
    if (asWidget(widget.Container, base_ptr)) |c| {
        for (c.children.items) |child| {
            try out.append(allocator, child);
        }
        return;
    }

    if (asWidget(widget.ScrollContainer, base_ptr)) |c| {
        if (c.content) |child| try out.append(allocator, child);
        return;
    }

    if (asWidget(widget.SplitPane, base_ptr)) |c| {
        if (c.first) |child| try out.append(allocator, child);
        if (c.second) |child| try out.append(allocator, child);
        return;
    }

    if (asWidget(widget.TabView, base_ptr)) |c| {
        for (c.tabs.items) |tab| {
            try out.append(allocator, tab.content);
        }
        return;
    }

    if (asWidget(widget.Block, base_ptr)) |c| {
        if (c.child) |child| try out.append(allocator, child);
        return;
    }

    if (asWidget(widget.Modal, base_ptr)) |c| {
        if (c.content) |child| try out.append(allocator, child);
    }
}

fn widgetLabel(w: *widget.Widget, buf: []u8) []const u8 {
    if (w.id.len > 0) return w.id;
    return std.fmt.bufPrint(buf, "widget@0x{x}", .{@intFromPtr(w)}) catch "<anonymous>";
}

/// Traverse the widget tree and print a readable outline with bounds.
pub const WidgetInspector = struct {
    allocator: std.mem.Allocator,

    pub const Options = struct {
        show_rect: bool = true,
        show_flags: bool = true,
    };

    /// Create a reusable inspector.
    ///
    /// Parameters:
    /// - `allocator`: backing allocator for child collection while traversing.
    /// Returns: initialized inspector with no retained state.
    /// Example:
    /// ```zig
    /// var inspector = zit.debug.WidgetInspector.init(alloc);
    /// try inspector.printTree(root, std.io.getStdOut().writer(), .{});
    /// ```
    pub fn init(allocator: std.mem.Allocator) WidgetInspector {
        return .{ .allocator = allocator };
    }

    /// Print a formatted outline of the widget tree.
    ///
    /// Parameters:
    /// - `root`: widget to start traversal from.
    /// - `writer`: output sink receiving the outline.
    /// - `options`: toggle rectangle/flag details.
    /// Returns: any writer error.
    /// Example:
    /// ```zig
    /// try inspector.printTree(&my_root.widget, std.io.getStdErr().writer(), .{ .show_flags = false });
    /// ```
    pub fn printTree(self: *WidgetInspector, root: *widget.Widget, writer: anytype, options: Options) !void {
        try writer.writeAll("widget tree (root first):\n");
        try self.printNode(writer, root, 0, options);
    }

    fn printNode(self: *WidgetInspector, writer: anytype, node: *widget.Widget, depth: usize, options: Options) !void {
        var i: usize = 0;
        while (i < depth) : (i += 1) {
            try writer.writeAll("  ");
        }

        var label_buf: [48]u8 = undefined;
        const id = widgetLabel(node, &label_buf);
        try writer.print("- {s} ({s}", .{ widgetTypeName(node), id });

        if (options.show_rect) {
            try writer.print(" rect={d}x{d}+{d},{d}", .{ node.rect.width, node.rect.height, node.rect.x, node.rect.y });
        }

        if (options.show_flags) {
            try writer.print(" visible={any} enabled={any}", .{ node.visible, node.enabled });
        }

        try writer.writeAll(")\n");

        var children = try std.ArrayList(*widget.Widget).initCapacity(self.allocator, 0);
        defer children.deinit(self.allocator);
        try collectChildren(self.allocator, node, &children);

        for (children.items) |child| {
            try self.printNode(writer, child, depth + 1, options);
        }
    }
};

/// Overlay widget bounds directly onto a renderer to debug layout issues.
pub const LayoutDebugger = struct {
    pub const Options = struct {
        border_color: render.Color = render.Color.named(render.NamedColor.magenta),
        label_color: render.Color = render.Color.named(render.NamedColor.bright_white),
        show_size: bool = true,
        show_ids: bool = true,
    };

    /// Draw outlines around every widget to help diagnose layout issues.
    ///
    /// Parameters:
    /// - `renderer`: renderer to draw into (typically the active frame buffer).
    /// - `root`: root widget whose descendants will be annotated.
    /// - `options`: colors and label toggles for the overlay.
    /// Returns: nothing; errors are ignored so debugging cannot crash a UI.
    /// Example:
    /// ```zig
    /// debug.LayoutDebugger.outline(&renderer, &root.widget, .{ .show_ids = true });
    /// ```
    pub fn outline(renderer: *render.Renderer, root: *widget.Widget, options: Options) void {
        drawNode(renderer, root, 0, options);

        var children = try std.ArrayList(*widget.Widget).initCapacity(renderer.allocator, 0);
        defer children.deinit(renderer.allocator);
        collectChildren(renderer.allocator, root, &children) catch return;

        for (children.items) |child| {
            outline(renderer, child, options);
        }
    }

    fn drawNode(renderer: *render.Renderer, node: *widget.Widget, depth: usize, options: Options) void {
        const rect = node.rect;
        if (rect.width < 2 or rect.height < 1) return;

        const border_style = if (depth % 2 == 0) render.BorderStyle.single else render.BorderStyle.rounded;
        renderer.drawBox(rect.x, rect.y, rect.width, rect.height, border_style, options.border_color, render.Color.named(render.NamedColor.default), render.Style{ .italic = true });

        var label_buf: [96]u8 = undefined;
        var label_len: usize = 0;

        if (options.show_ids) {
            const id = if (node.id.len > 0) node.id else "<anon>";
            const written = std.fmt.bufPrint(&label_buf, "{s}", .{id}) catch 0;
            label_len = written;
        }

        if (options.show_size) {
            const size_slice = std.fmt.bufPrint(label_buf[label_len..], "{s}{d}x{d}", .{ if (label_len > 0) " " else "", rect.width, rect.height }) catch 0;
            label_len += size_slice;
        }

        if (label_len == 0 or rect.width == 0) return;
        const max_len: usize = @intCast(@min(label_len, rect.width));
        renderer.drawSmartStr(rect.x, rect.y, label_buf[0..max_len], options.label_color, render.Color.named(render.NamedColor.default), render.Style{ .bold = true });
    }
};

/// Trace events as they flow through the dispatcher.
pub const EventTracer = struct {
    writer: std.io.AnyWriter,
    include_payloads: bool = true,
    include_path: bool = true,

    /// Create a tracer that prints every event dispatched through the UI.
    ///
    /// Parameters:
    /// - `writer`: destination for logs (stdout, file writer, etc).
    /// Returns: tracer with payload/path logging enabled by default.
    /// Example:
    /// ```zig
    /// var tracer = zit.debug.EventTracer.init(std.io.getStdErr().writer());
    /// const hooks = tracer.hooks();
    /// app.debug_hooks = hooks;
    /// ```
    pub fn init(writer: anytype) EventTracer {
        return .{ .writer = std.io.anyWriter(writer) };
    }

    /// Convert the tracer into `event.DebugHooks` used by `Application`.
    ///
    /// Returns: hook struct that can be assigned to `Application.debug_hooks`.
    /// Example:
    /// ```zig
    /// app.debug_hooks = tracer.hooks();
    /// ```
    pub fn hooks(self: *EventTracer) event_mod.DebugHooks {
        return .{ .event_trace = trace, .trace_ctx = self };
    }

    fn trace(ev: *event_mod.Event, phase: event_mod.Event.PropagationPhase, node: ?*widget.Widget, handled: bool, ctx: ?*anyopaque) void {
        if (ctx == null) return;
        const self = @as(*EventTracer, @ptrCast(@alignCast(ctx.?)));
        self.log(ev, phase, node, handled) catch {};
    }

    fn log(self: *EventTracer, ev: *event_mod.Event, phase: event_mod.Event.PropagationPhase, node: ?*widget.Widget, handled: bool) !void {
        var node_buf: [48]u8 = undefined;
        var target_buf: [48]u8 = undefined;
        const node_label = if (node) |n| widgetLabel(n, &node_buf) else "queue";
        const target_label = if (ev.target) |t| widgetLabel(t, &target_buf) else "none";

        var summary_buf: [128]u8 = undefined;
        const summary = describe(ev, &summary_buf);

        try self.writer.print(
            "zit.debug:event type={s} phase={s} node={s} target={s} handled={any}{s}\n",
            .{ @tagName(ev.type), @tagName(phase), node_label, target_label, handled, summary },
        );
    }

    fn describe(ev: *event_mod.Event, buf: []u8) []const u8 {
        const written = switch (ev.type) {
            .key_press => std.fmt.bufPrint(buf, " key='{u}' mods=0x{x}", .{ ev.data.key_press.key, ev.data.key_press.modifiers }),
            .key_release => std.fmt.bufPrint(buf, " key-up='{u}' mods=0x{x}", .{ ev.data.key_release.key, ev.data.key_release.modifiers }),
            .mouse_press, .mouse_release, .mouse_move => |tag| blk: {
                const mouse = switch (tag) {
                    .mouse_press => ev.data.mouse_press,
                    .mouse_release => ev.data.mouse_release,
                    else => ev.data.mouse_move,
                };
                break :blk std.fmt.bufPrint(buf, " mouse@{d},{d} btn={d} mods=0x{x}", .{ mouse.x, mouse.y, mouse.button, mouse.modifiers });
            },
            .mouse_wheel => std.fmt.bufPrint(buf, " wheel@{d},{d} dx={d} dy={d}", .{ ev.data.mouse_wheel.x, ev.data.mouse_wheel.y, ev.data.mouse_wheel.dx, ev.data.mouse_wheel.dy }),
            .resize => std.fmt.bufPrint(buf, " resize {d}x{d}", .{ ev.data.resize.width, ev.data.resize.height }),
            .focus_change => std.fmt.bufPrint(buf, " focus to={any}", .{ev.data.focus_change.focused}),
            .custom => std.fmt.bufPrint(buf, " custom id=0x{x}", .{ev.data.custom.id}),
            else => std.fmt.bufPrint(buf, "", .{}),
        } catch 0;

        return buf[0..written];
    }
};
