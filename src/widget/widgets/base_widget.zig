const std = @import("std");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const event_module = @import("../../event/event.zig");
const animation = @import("../animation.zig");
const css = @import("../css.zig");
const theme = @import("../theme.zig");
const container_widget = @import("container.zig");
const scroll_container_widget = @import("scroll_container.zig");
const split_pane_widget = @import("split_pane.zig");
const tab_view_widget = @import("tab_view.zig");
const block_widget = @import("block.zig");
const modal_widget = @import("modal.zig");
const screen_manager_widget = @import("screen_manager.zig");
const flex_container_widget = @import("flex_container.zig");
const grid_container_widget = @import("grid_container.zig");

/// Focus direction for navigation
pub const FocusDirection = enum {
    next,
    previous,
    up,
    down,
    left,
    right,
};

/// Base widget interface
pub const Widget = struct {
    /// Rectangle defining the widget's position and size
    rect: layout_module.Rect = layout_module.Rect.init(0, 0, 0, 0),
    /// Whether the widget is focused
    focused: bool = false,
    /// Whether the widget is visible
    visible: bool = true,
    /// Whether the widget needs to be redrawn
    dirty: bool = true,
    /// Optional dirty rectangle for partial redraws
    dirty_rect: ?layout_module.Rect = null,
    /// Whether the widget is enabled
    enabled: bool = true,
    /// Widget ID for identification
    id: []const u8 = "",
    /// Optional style class used by stylesheet helpers
    style_class: ?[]const u8 = null,
    /// Optional stylesheet attached for CSS-like styling
    style_sheet: ?*css.StyleSheet = null,
    /// Optional theme used when resolving stylesheet roles
    style_theme: ?theme.Theme = null,
    /// Accessibility role identifier (matches accessibility.Role enum value)
    accessibility_role: u8 = 0,
    /// Accessibility name for announcements
    accessibility_name: []const u8 = "",
    /// Accessibility description for announcements
    accessibility_description: []const u8 = "",
    /// Accessibility context pointer provided by the application
    accessibility_ctx: ?*anyopaque = null,
    /// Callback for registering accessibility nodes
    accessibility_register: ?*const fn (?*anyopaque, *Widget) void = null,
    /// Callback for updating accessibility bounds
    accessibility_update_bounds: ?*const fn (?*anyopaque, *Widget, layout_module.Rect) void = null,
    /// Optional focus ring styling
    focus_ring: ?render.FocusRingStyle = null,
    /// Animated visibility controller for show/hide transitions
    visibility_transition: animation.VisibilityController = .{},
    /// Parent widget, used primarily for modal dialogs and layout containment
    parent: ?*Widget = null,

    /// Virtual table for widget methods
    vtable: *const VTable,

    /// Virtual method table
    pub const VTable = struct {
        /// Draw the widget
        draw: *const fn (widget: *anyopaque, renderer: *render.Renderer) anyerror!void,
        /// Handle an input event
        handle_event: *const fn (widget: *anyopaque, event: input.Event) anyerror!bool,
        /// Layout the widget
        layout: *const fn (widget: *anyopaque, rect: layout_module.Rect) anyerror!void,
        /// Get preferred size
        get_preferred_size: *const fn (widget: *anyopaque) anyerror!layout_module.Size,
        /// Can focus
        can_focus: *const fn (widget: *anyopaque) bool,
        /// Optional hook invoked after focus, visibility, or enabled state changes.
        on_state_change: ?*const fn (widget: *anyopaque) void = null,
    };

    /// Initialize a new widget
    pub fn init(vtable: *const VTable) Widget {
        return Widget{
            .vtable = vtable,
        };
    }

    /// Draw the widget
    pub fn draw(self: *Widget, renderer: *render.Renderer) !void {
        const animating = self.visibility_transition.isAnimating();
        if (!self.visible and !animating) return;
        if (!self.dirty and !animating) return;
        try self.vtable.draw(self, renderer);
        self.clearDirty();
    }

    /// Handle an input event
    pub fn handleEvent(self: *Widget, event: input.Event) !bool {
        if (!self.visible or !self.enabled or self.visibility_transition.isHiding()) {
            return false;
        }
        const handled = try self.vtable.handle_event(self, event);
        if (handled) {
            self.markDirty();
        }
        return handled;
    }

    /// Layout the widget
    pub fn layout(self: *Widget, rect: layout_module.Rect) !void {
        const previous_rect = self.rect;
        const previous_dirty = self.dirty;
        const previous_dirty_rect = self.dirty_rect;
        self.rect = rect;
        self.vtable.layout(self, rect) catch |err| {
            self.rect = previous_rect;
            self.dirty = previous_dirty;
            self.dirty_rect = previous_dirty_rect;
            return err;
        };
        if (!rectEql(previous_rect, self.rect)) {
            self.markDirtyRect(rectUnion(previous_rect, self.rect));
        }
        if (self.accessibility_update_bounds) |cb| {
            cb(self.accessibility_ctx, self, self.rect);
        }
    }

    /// Get preferred size
    pub fn getPreferredSize(self: *Widget) !layout_module.Size {
        return self.vtable.get_preferred_size(self);
    }

    /// Check if widget can receive focus
    pub fn canFocus(self: *Widget) bool {
        if (!self.visible or !self.enabled) {
            return false;
        }
        return self.vtable.can_focus(self);
    }

    /// Set focus state
    pub fn setFocus(self: *Widget, focused: bool) void {
        if (self.focused == focused) return;
        self.focused = focused;
        if (self.vtable.on_state_change) |callback| callback(self);
        self.markDirty();
    }

    /// Set visibility
    pub fn setVisible(self: *Widget, visible: bool) void {
        self.setVisibleWithTransition(visible, true);
    }

    fn setVisibleForAnimation(self: *Widget, visible: bool) void {
        self.setVisibleWithTransition(visible, false);
    }

    fn setVisibleWithTransition(self: *Widget, visible: bool, snap_transition: bool) void {
        if (self.visible == visible) return;
        self.visible = visible;
        if (snap_transition) self.visibility_transition.snap(visible);
        if (self.vtable.on_state_change) |callback| callback(self);
        self.markDirty();
    }

    /// Set enabled state
    pub fn setEnabled(self: *Widget, enabled: bool) void {
        if (self.enabled == enabled) return;
        self.enabled = enabled;
        if (self.vtable.on_state_change) |callback| callback(self);
        self.markDirty();
    }

    /// Set widget ID
    pub fn setId(self: *Widget, id: []const u8) void {
        self.id = id;
        self.markDirty();
    }

    /// Set widget style class for CSS-like styling
    pub fn setClass(self: *Widget, class: ?[]const u8) void {
        self.style_class = class;
        self.markDirty();
    }

    /// Attach a stylesheet for CSS-like styling.
    pub fn setStyleSheet(self: *Widget, sheet: ?*css.StyleSheet) void {
        self.style_sheet = sheet;
        self.markDirty();
    }

    /// Attach a theme for resolving stylesheet roles.
    pub fn setStyleTheme(self: *Widget, theme_value: ?theme.Theme) void {
        self.style_theme = theme_value;
        self.markDirty();
    }

    /// Set accessibility metadata for this widget.
    pub fn setAccessibility(self: *Widget, role_id: u8, name: []const u8, description: []const u8) void {
        self.accessibility_role = role_id;
        self.accessibility_name = name;
        self.accessibility_description = description;
        if (self.accessibility_register) |cb| {
            if (role_id != 0 or name.len > 0 or description.len > 0) {
                cb(self.accessibility_ctx, self);
            }
        }
    }

    /// Resolve stylesheet overrides for this widget.
    pub fn resolveStyle(self: *Widget, type_name: []const u8, state: css.State, base_style: render.Style) css.StyleSheet.Resolved {
        const sheet = self.style_sheet orelse return .{ .fg = null, .bg = null, .style = base_style };
        var target = css.StyleTarget{
            .id = if (self.id.len > 0) self.id else null,
            .class = self.style_class,
            .type_name = type_name,
            .state = .{},
        };
        target.state = state;
        return sheet.resolve(target, self.style_theme, base_style);
    }

    pub const AppliedStyle = struct {
        fg: render.Color,
        bg: render.Color,
        style: render.Style,
    };

    /// Apply stylesheet overrides for the given colors.
    pub fn applyStyle(self: *Widget, type_name: []const u8, state: css.State, base_style: render.Style, fg: render.Color, bg: render.Color) AppliedStyle {
        const resolved = self.resolveStyle(type_name, state, base_style);
        return .{
            .fg = resolved.fg orelse fg,
            .bg = resolved.bg orelse bg,
            .style = resolved.style,
        };
    }

    /// Apply stylesheet and theme context to the widget tree.
    pub fn applyStyleContext(root: *Widget, sheet: ?*css.StyleSheet, theme_value: ?theme.Theme) void {
        root.style_sheet = sheet;
        root.style_theme = theme_value;
        applyStyleContextImpl(root, sheet, theme_value);
    }

    /// Apply accessibility callbacks to the widget tree.
    pub fn applyAccessibilityContext(
        root: *Widget,
        ctx: ?*anyopaque,
        register: ?*const fn (?*anyopaque, *Widget) void,
        update: ?*const fn (?*anyopaque, *Widget, layout_module.Rect) void,
    ) void {
        root.accessibility_ctx = ctx;
        root.accessibility_register = register;
        root.accessibility_update_bounds = update;
        if (register != null and (root.accessibility_role != 0 or root.accessibility_name.len > 0 or root.accessibility_description.len > 0)) {
            register.?(ctx, root);
        }
        applyAccessibilityContextImpl(root, ctx, register, update);
    }

    /// Set focus ring styling.
    pub fn setFocusRing(self: *Widget, ring: ?render.FocusRingStyle) void {
        self.focus_ring = ring;
        self.markDirty();
    }

    /// Animate visibility using configured transitions. This keeps the widget
    /// renderable while fading/sliding out, then hides it when complete.
    pub fn animateVisibility(self: *Widget, animator: *animation.Animator, visible: bool, opts: animation.VisibilityOptions) !void {
        const previous_visible = self.visible;
        if (visible) {
            self.setVisibleForAnimation(true);
        }
        _ = self.visibility_transition.animateWithCompletion(animator, visible, opts, visibilityAnimationComplete, self) catch |err| {
            self.setVisible(previous_visible);
            return err;
        };
        self.markDirty();
    }

    /// Mark the widget dirty so it redraws on the next render pass.
    pub fn markDirty(self: *Widget) void {
        self.markDirtyRect(self.rect);
    }

    /// Mark a specific rect as dirty and propagate to parents.
    pub fn markDirtyRect(self: *Widget, rect: layout_module.Rect) void {
        self.dirty = true;
        if (self.dirty_rect) |existing| {
            self.dirty_rect = rectUnion(existing, rect);
        } else {
            self.dirty_rect = rect;
        }
        if (self.parent) |parent| {
            parent.markDirtyRect(rect);
        }
    }

    /// Clear the dirty flag after a successful draw.
    pub fn clearDirty(self: *Widget) void {
        self.dirty = false;
        self.dirty_rect = null;
    }

    /// Current visibility alpha (1 when fully visible, 0 when hidden).
    pub fn visibilityAlpha(self: *Widget) f32 {
        return self.visibility_transition.alpha();
    }

    /// Attach this widget to an owning parent without silently reparenting it.
    /// Owners must detach the widget from its current parent first.
    pub fn attachTo(self: *Widget, parent: *Widget) !void {
        if (self.parent) |current| {
            if (current != parent) return error.WidgetAlreadyAttached;
        }
        self.parent = parent;
    }

    /// Detach this widget only when the caller is its current owner.
    pub fn detachFrom(self: *Widget, parent: *Widget) bool {
        if (self.parent != parent) return false;
        self.parent = null;
        return true;
    }

    /// Traverse widget children depth-first and invoke a callback for each child.
    pub fn traverseChildren(widget: *Widget, callback: *const fn (*Widget) void) void {
        traverseChildrenImpl(widget, callback);
    }

    /// Draw a configurable focus ring if one is configured and the widget is focused.
    pub fn drawFocusRing(self: *Widget, renderer: *render.Renderer) void {
        if (!self.focused) return;
        const ring = self.focus_ring orelse return;

        const inset: u32 = ring.inset;
        const inset_twice = inset * 2;
        if (@as(u32, self.rect.width) <= inset_twice or @as(u32, self.rect.height) <= inset_twice) return;

        const ring_x = u16SaturatingAdd(self.rect.x, inset);
        const ring_y = u16SaturatingAdd(self.rect.y, inset);
        const ring_width: u16 = @intCast(@as(u32, self.rect.width) - inset_twice);
        const ring_height: u16 = @intCast(@as(u32, self.rect.height) - inset_twice);

        if (ring_width < 2 or ring_height < 2) return;

        if (ring.fill) |fill| {
            renderer.fillRect(ring_x, ring_y, ring_width, ring_height, ' ', ring.color, fill, ring.style);
        }

        renderer.drawBox(
            ring_x,
            ring_y,
            ring_width,
            ring_height,
            ring.border,
            ring.color,
            ring.fill orelse render.Color.named(render.NamedColor.default),
            ring.style,
        );
    }

    /// Adapter to create a LayoutElement from a Widget
    pub fn asLayoutElement(self: *Widget) layout_module.LayoutElement {
        return layout_module.LayoutElement{
            .layoutFn = widgetLayoutAdapter,
            .renderFn = widgetRenderAdapter,
            .ctx = @ptrCast(@alignCast(self)),
        };
    }
};

fn asWidget(comptime T: type, base_ptr: *Widget) ?*T {
    if (!@hasDecl(T, "vtable") or !@hasField(T, "widget")) return null;
    if (base_ptr.vtable == &T.vtable) {
        return @alignCast(@fieldParentPtr("widget", base_ptr));
    }
    return null;
}

fn traverseChildrenImpl(widget: *Widget, callback: *const fn (*Widget) void) void {
    if (asWidget(container_widget.Container, widget)) |container| {
        for (container.children.items) |child| {
            callback(child);
            traverseChildrenImpl(child, callback);
        }
        return;
    }

    if (asWidget(flex_container_widget.FlexContainer, widget)) |container| {
        for (container.children.items) |child| {
            callback(child);
            traverseChildrenImpl(child, callback);
        }
        return;
    }

    if (asWidget(grid_container_widget.GridContainer, widget)) |grid| {
        for (grid.children.items) |entry| {
            const child = entry.widget;
            callback(child);
            traverseChildrenImpl(child, callback);
        }
        return;
    }

    if (asWidget(scroll_container_widget.ScrollContainer, widget)) |container| {
        if (container.content) |child| {
            callback(child);
            traverseChildrenImpl(child, callback);
        }
        if (container.h_scrollbar) |bar| {
            const child = &bar.widget;
            callback(child);
            traverseChildrenImpl(child, callback);
        }
        if (container.v_scrollbar) |bar| {
            const child = &bar.widget;
            callback(child);
            traverseChildrenImpl(child, callback);
        }
        return;
    }

    if (asWidget(split_pane_widget.SplitPane, widget)) |pane| {
        if (pane.first) |child| {
            callback(child);
            traverseChildrenImpl(child, callback);
        }
        if (pane.second) |child| {
            callback(child);
            traverseChildrenImpl(child, callback);
        }
        return;
    }

    if (asWidget(tab_view_widget.TabView, widget)) |tabs| {
        const tab_bar_child = &tabs.tab_bar.widget;
        callback(tab_bar_child);
        traverseChildrenImpl(tab_bar_child, callback);
        for (tabs.tabs.items) |tab| {
            if (tab.content) |child| {
                callback(child);
                traverseChildrenImpl(child, callback);
            }
        }
        return;
    }

    if (asWidget(block_widget.Block, widget)) |block| {
        if (block.child) |child| {
            callback(child);
            traverseChildrenImpl(child, callback);
        }
        return;
    }

    if (asWidget(modal_widget.Modal, widget)) |modal| {
        if (modal.content) |child| {
            callback(child);
            traverseChildrenImpl(child, callback);
        }
        return;
    }

    if (asWidget(screen_manager_widget.ScreenManager, widget)) |manager| {
        for (manager.screens.items) |entry| {
            const child = entry.screen.widget;
            callback(child);
            traverseChildrenImpl(child, callback);
        }
    }
}

fn applyStyleContextImpl(widget: *Widget, sheet: ?*css.StyleSheet, theme_value: ?theme.Theme) void {
    if (asWidget(container_widget.Container, widget)) |container| {
        for (container.children.items) |child| {
            child.style_sheet = sheet;
            child.style_theme = theme_value;
            applyStyleContextImpl(child, sheet, theme_value);
        }
        return;
    }

    if (asWidget(flex_container_widget.FlexContainer, widget)) |container| {
        for (container.children.items) |child| {
            child.style_sheet = sheet;
            child.style_theme = theme_value;
            applyStyleContextImpl(child, sheet, theme_value);
        }
        return;
    }

    if (asWidget(grid_container_widget.GridContainer, widget)) |grid| {
        for (grid.children.items) |entry| {
            const child = entry.widget;
            child.style_sheet = sheet;
            child.style_theme = theme_value;
            applyStyleContextImpl(child, sheet, theme_value);
        }
        return;
    }

    if (asWidget(scroll_container_widget.ScrollContainer, widget)) |container| {
        if (container.content) |child| {
            child.style_sheet = sheet;
            child.style_theme = theme_value;
            applyStyleContextImpl(child, sheet, theme_value);
        }
        if (container.h_scrollbar) |bar| {
            const child = &bar.widget;
            child.style_sheet = sheet;
            child.style_theme = theme_value;
            applyStyleContextImpl(child, sheet, theme_value);
        }
        if (container.v_scrollbar) |bar| {
            const child = &bar.widget;
            child.style_sheet = sheet;
            child.style_theme = theme_value;
            applyStyleContextImpl(child, sheet, theme_value);
        }
        return;
    }

    if (asWidget(split_pane_widget.SplitPane, widget)) |pane| {
        if (pane.first) |child| {
            child.style_sheet = sheet;
            child.style_theme = theme_value;
            applyStyleContextImpl(child, sheet, theme_value);
        }
        if (pane.second) |child| {
            child.style_sheet = sheet;
            child.style_theme = theme_value;
            applyStyleContextImpl(child, sheet, theme_value);
        }
        return;
    }

    if (asWidget(tab_view_widget.TabView, widget)) |tabs| {
        const tab_bar_child = &tabs.tab_bar.widget;
        tab_bar_child.style_sheet = sheet;
        tab_bar_child.style_theme = theme_value;
        applyStyleContextImpl(tab_bar_child, sheet, theme_value);
        for (tabs.tabs.items) |tab| {
            if (tab.content) |child| {
                child.style_sheet = sheet;
                child.style_theme = theme_value;
                applyStyleContextImpl(child, sheet, theme_value);
            }
        }
        return;
    }

    if (asWidget(block_widget.Block, widget)) |block| {
        if (block.child) |child| {
            child.style_sheet = sheet;
            child.style_theme = theme_value;
            applyStyleContextImpl(child, sheet, theme_value);
        }
        return;
    }

    if (asWidget(modal_widget.Modal, widget)) |modal| {
        if (modal.content) |child| {
            child.style_sheet = sheet;
            child.style_theme = theme_value;
            applyStyleContextImpl(child, sheet, theme_value);
        }
        return;
    }

    if (asWidget(screen_manager_widget.ScreenManager, widget)) |manager| {
        for (manager.screens.items) |entry| {
            const child = entry.screen.widget;
            child.style_sheet = sheet;
            child.style_theme = theme_value;
            applyStyleContextImpl(child, sheet, theme_value);
        }
    }
}

fn applyAccessibilityContextImpl(
    widget: *Widget,
    ctx: ?*anyopaque,
    register: ?*const fn (?*anyopaque, *Widget) void,
    update: ?*const fn (?*anyopaque, *Widget, layout_module.Rect) void,
) void {
    if (asWidget(container_widget.Container, widget)) |container| {
        for (container.children.items) |child| {
            child.accessibility_ctx = ctx;
            child.accessibility_register = register;
            child.accessibility_update_bounds = update;
            if (register != null and (child.accessibility_role != 0 or child.accessibility_name.len > 0 or child.accessibility_description.len > 0)) {
                register.?(ctx, child);
            }
            applyAccessibilityContextImpl(child, ctx, register, update);
        }
        return;
    }

    if (asWidget(flex_container_widget.FlexContainer, widget)) |container| {
        for (container.children.items) |child| {
            child.accessibility_ctx = ctx;
            child.accessibility_register = register;
            child.accessibility_update_bounds = update;
            if (register != null and (child.accessibility_role != 0 or child.accessibility_name.len > 0 or child.accessibility_description.len > 0)) {
                register.?(ctx, child);
            }
            applyAccessibilityContextImpl(child, ctx, register, update);
        }
        return;
    }

    if (asWidget(grid_container_widget.GridContainer, widget)) |grid| {
        for (grid.children.items) |entry| {
            const child = entry.widget;
            child.accessibility_ctx = ctx;
            child.accessibility_register = register;
            child.accessibility_update_bounds = update;
            if (register != null and (child.accessibility_role != 0 or child.accessibility_name.len > 0 or child.accessibility_description.len > 0)) {
                register.?(ctx, child);
            }
            applyAccessibilityContextImpl(child, ctx, register, update);
        }
        return;
    }

    if (asWidget(scroll_container_widget.ScrollContainer, widget)) |container| {
        if (container.content) |child| {
            child.accessibility_ctx = ctx;
            child.accessibility_register = register;
            child.accessibility_update_bounds = update;
            if (register != null and (child.accessibility_role != 0 or child.accessibility_name.len > 0 or child.accessibility_description.len > 0)) {
                register.?(ctx, child);
            }
            applyAccessibilityContextImpl(child, ctx, register, update);
        }
        if (container.h_scrollbar) |bar| {
            const child = &bar.widget;
            child.accessibility_ctx = ctx;
            child.accessibility_register = register;
            child.accessibility_update_bounds = update;
            if (register != null and (child.accessibility_role != 0 or child.accessibility_name.len > 0 or child.accessibility_description.len > 0)) {
                register.?(ctx, child);
            }
            applyAccessibilityContextImpl(child, ctx, register, update);
        }
        if (container.v_scrollbar) |bar| {
            const child = &bar.widget;
            child.accessibility_ctx = ctx;
            child.accessibility_register = register;
            child.accessibility_update_bounds = update;
            if (register != null and (child.accessibility_role != 0 or child.accessibility_name.len > 0 or child.accessibility_description.len > 0)) {
                register.?(ctx, child);
            }
            applyAccessibilityContextImpl(child, ctx, register, update);
        }
        return;
    }

    if (asWidget(split_pane_widget.SplitPane, widget)) |pane| {
        if (pane.first) |child| {
            child.accessibility_ctx = ctx;
            child.accessibility_register = register;
            child.accessibility_update_bounds = update;
            if (register != null and (child.accessibility_role != 0 or child.accessibility_name.len > 0 or child.accessibility_description.len > 0)) {
                register.?(ctx, child);
            }
            applyAccessibilityContextImpl(child, ctx, register, update);
        }
        if (pane.second) |child| {
            child.accessibility_ctx = ctx;
            child.accessibility_register = register;
            child.accessibility_update_bounds = update;
            if (register != null and (child.accessibility_role != 0 or child.accessibility_name.len > 0 or child.accessibility_description.len > 0)) {
                register.?(ctx, child);
            }
            applyAccessibilityContextImpl(child, ctx, register, update);
        }
        return;
    }

    if (asWidget(tab_view_widget.TabView, widget)) |tabs| {
        const tab_bar_child = &tabs.tab_bar.widget;
        tab_bar_child.accessibility_ctx = ctx;
        tab_bar_child.accessibility_register = register;
        tab_bar_child.accessibility_update_bounds = update;
        if (register != null and (tab_bar_child.accessibility_role != 0 or tab_bar_child.accessibility_name.len > 0 or tab_bar_child.accessibility_description.len > 0)) {
            register.?(ctx, tab_bar_child);
        }
        applyAccessibilityContextImpl(tab_bar_child, ctx, register, update);
        for (tabs.tabs.items) |tab| {
            if (tab.content) |child| {
                child.accessibility_ctx = ctx;
                child.accessibility_register = register;
                child.accessibility_update_bounds = update;
                if (register != null and (child.accessibility_role != 0 or child.accessibility_name.len > 0 or child.accessibility_description.len > 0)) {
                    register.?(ctx, child);
                }
                applyAccessibilityContextImpl(child, ctx, register, update);
            }
        }
        return;
    }

    if (asWidget(block_widget.Block, widget)) |block| {
        if (block.child) |child| {
            child.accessibility_ctx = ctx;
            child.accessibility_register = register;
            child.accessibility_update_bounds = update;
            if (register != null and (child.accessibility_role != 0 or child.accessibility_name.len > 0 or child.accessibility_description.len > 0)) {
                register.?(ctx, child);
            }
            applyAccessibilityContextImpl(child, ctx, register, update);
        }
        return;
    }

    if (asWidget(modal_widget.Modal, widget)) |modal| {
        if (modal.content) |child| {
            child.accessibility_ctx = ctx;
            child.accessibility_register = register;
            child.accessibility_update_bounds = update;
            if (register != null and (child.accessibility_role != 0 or child.accessibility_name.len > 0 or child.accessibility_description.len > 0)) {
                register.?(ctx, child);
            }
            applyAccessibilityContextImpl(child, ctx, register, update);
        }
        return;
    }

    if (asWidget(screen_manager_widget.ScreenManager, widget)) |manager| {
        for (manager.screens.items) |entry| {
            const child = entry.screen.widget;
            child.accessibility_ctx = ctx;
            child.accessibility_register = register;
            child.accessibility_update_bounds = update;
            if (register != null and (child.accessibility_role != 0 or child.accessibility_name.len > 0 or child.accessibility_description.len > 0)) {
                register.?(ctx, child);
            }
            applyAccessibilityContextImpl(child, ctx, register, update);
        }
    }
}

/// Adapter function to convert Widget layout to LayoutElement layout
fn widgetLayoutAdapter(ctx: *anyopaque, constraints: layout_module.Constraints) layout_module.Size {
    const widget = @as(*Widget, @ptrCast(@alignCast(ctx)));

    // Create a rect from the constraints
    const rect = layout_module.Rect{
        .x = 0,
        .y = 0,
        .width = constraints.max_width,
        .height = constraints.max_height,
    };

    // Layout the widget
    widget.layout(rect) catch |err| {
        logWidgetError(widget, "layout", err);
        return layout_module.Size.zero();
    };

    // Return the preferred size constrained by the constraints
    const preferred_size = widget.getPreferredSize() catch |err| {
        logWidgetError(widget, "preferred size", err);
        return layout_module.Size.zero();
    };
    return layout_module.Size{
        .width = @min(preferred_size.width, constraints.max_width),
        .height = @min(preferred_size.height, constraints.max_height),
    };
}

/// Adapter function to convert Widget draw to LayoutElement render
fn widgetRenderAdapter(ctx: *anyopaque, renderer: *render.Renderer, rect: layout_module.Rect) void {
    const widget = @as(*Widget, @ptrCast(@alignCast(ctx)));

    const animating = widget.visibility_transition.isAnimating();
    if (!widget.visible and !animating) {
        return;
    }
    if (!widget.dirty and !animating) {
        return;
    }

    var draw_rect = rect;
    const disp = widget.visibility_transition.displacement();
    if (disp.dx != 0 or disp.dy != 0) {
        const new_x_i32: i32 = @as(i32, @intCast(rect.x)) + disp.dx;
        const new_y_i32: i32 = @as(i32, @intCast(rect.y)) + disp.dy;
        const new_x: u16 = if (new_x_i32 < 0) 0 else @intCast(new_x_i32);
        const new_y: u16 = if (new_y_i32 < 0) 0 else @intCast(new_y_i32);
        draw_rect = layout_module.Rect.init(new_x, new_y, rect.width, rect.height);
    }

    // Set widget rect
    widget.rect = draw_rect;

    // Draw the widget
    widget.draw(renderer) catch |err| {
        logWidgetError(widget, "draw", err);
    };

    // Apply fade after drawing so we tint the rendered cells instead of erasing them.
    const alpha = widget.visibility_transition.alpha();
    if (widget.visibility_transition.options.mode == .fade and alpha < 0.999 and draw_rect.width > 0 and draw_rect.height > 0) {
        const fade_to = widget.visibility_transition.options.fade_to;
        const max_x = clippedEndExclusive(draw_rect.x, draw_rect.width, renderer.back.width);
        const max_y = clippedEndExclusive(draw_rect.y, draw_rect.height, renderer.back.height);
        var y: u16 = draw_rect.y;
        while (y < max_y) : (y += 1) {
            var x: u16 = draw_rect.x;
            while (x < max_x) : (x += 1) {
                const cell = renderer.back.getCell(x, y);
                cell.fg = render.mixColor(fade_to, cell.fg, alpha);
                cell.bg = render.mixColor(fade_to, cell.bg, alpha);
            }
        }
    }
}

fn visibilityAnimationComplete(ctx: ?*anyopaque, visible: bool) void {
    const widget = @as(*Widget, @ptrCast(@alignCast(ctx.?)));
    if (!visible) widget.setVisible(false);
}

fn clippedEndExclusive(start: u16, size: u16, limit: u16) u16 {
    const end = @as(u32, start) + @as(u32, size);
    return @intCast(@min(end, @as(u32, limit)));
}

fn u16SaturatingAdd(origin: u16, offset: u32) u16 {
    return @intCast(@min(@as(u32, origin) + offset, @as(u32, std.math.maxInt(u16))));
}

fn logWidgetError(widget: *Widget, action: []const u8, err: anyerror) void {
    const builtin = @import("builtin");
    if (builtin.is_test) {
        return;
    }
    const id = if (widget.id.len > 0) widget.id else "<anonymous>";
    std.log.err(
        "zit.widget: {s} {s} failed with {s} (rect={d}x{d}+{d},{d}, visible={any}, enabled={any}). Tip: set an id for easier tracing and use zit.debug.LayoutDebugger to visualize bounds.",
        .{ id, action, @errorName(err), widget.rect.width, widget.rect.height, widget.rect.x, widget.rect.y, widget.visible, widget.enabled },
    );
}

fn rectEql(lhs: layout_module.Rect, rhs: layout_module.Rect) bool {
    return lhs.x == rhs.x and lhs.y == rhs.y and lhs.width == rhs.width and lhs.height == rhs.height;
}

fn rectUnion(lhs: layout_module.Rect, rhs: layout_module.Rect) layout_module.Rect {
    const min_x: u32 = @min(lhs.x, rhs.x);
    const min_y: u32 = @min(lhs.y, rhs.y);
    const lhs_max_x: u32 = @as(u32, lhs.x) + lhs.width;
    const rhs_max_x: u32 = @as(u32, rhs.x) + rhs.width;
    const lhs_max_y: u32 = @as(u32, lhs.y) + lhs.height;
    const rhs_max_y: u32 = @as(u32, rhs.y) + rhs.height;
    const max_x = @max(lhs_max_x, rhs_max_x);
    const max_y = @max(lhs_max_y, rhs_max_y);
    const width = if (max_x > min_x) max_x - min_x else 0;
    const height = if (max_y > min_y) max_y - min_y else 0;
    const max_u16: u32 = std.math.maxInt(u16);
    return layout_module.Rect.init(
        @min(min_x, max_u16),
        @min(min_y, max_u16),
        @min(width, max_u16),
        @min(height, max_u16),
    );
}

test "layout adapter returns safe defaults on failure" {
    const failing_vtable = Widget.VTable{
        .draw = struct {
            fn draw(_: *anyopaque, _: *render.Renderer) anyerror!void {
                return error.ForcedDraw;
            }
        }.draw,
        .handle_event = struct {
            fn handle(_: *anyopaque, _: input.Event) anyerror!bool {
                return false;
            }
        }.handle,
        .layout = struct {
            fn layout(_: *anyopaque, _: layout_module.Rect) anyerror!void {
                return error.ForcedLayout;
            }
        }.layout,
        .get_preferred_size = struct {
            fn preferred(_: *anyopaque) anyerror!layout_module.Size {
                return error.ForcedPreferred;
            }
        }.preferred,
        .can_focus = struct {
            fn can(_: *anyopaque) bool {
                return true;
            }
        }.can,
    };

    const TestWidget = struct {
        widget: Widget = Widget.init(&failing_vtable),
    };

    var instance = TestWidget{};
    instance.widget.id = "failing";

    const element = instance.widget.asLayoutElement();
    const tight = layout_module.Constraints.tight(2, 2);
    const measured = element.layout(tight);
    try std.testing.expectEqual(layout_module.Size.zero(), measured);

    var renderer = try render.Renderer.init(std.testing.allocator, 2, 2);
    defer renderer.deinit();
    element.render(&renderer, layout_module.Rect.init(0, 0, 2, 2));

    // Buffer remains untouched because draw failed gracefully.
    try std.testing.expectEqual(@as(u21, ' '), renderer.back.getCell(0, 0).codepoint());
}

test "widget layout restores public geometry and dirty state on failure" {
    const FailingWidget = struct {
        widget: Widget = Widget.init(&vtable),
        bounds_updates: usize = 0,

        const vtable = Widget.VTable{
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
        fn layoutFn(widget_ptr: *anyopaque, _: layout_module.Rect) anyerror!void {
            const widget_ref: *Widget = @ptrCast(@alignCast(widget_ptr));
            const self: *@This() = @fieldParentPtr("widget", widget_ref);
            self.widget.rect = layout_module.Rect.init(20, 21, 22, 23);
            self.widget.dirty = true;
            self.widget.dirty_rect = layout_module.Rect.init(24, 25, 26, 27);
            return error.ForcedLayout;
        }
        fn preferredFn(_: *anyopaque) anyerror!layout_module.Size {
            return layout_module.Size.zero();
        }
        fn canFocusFn(_: *anyopaque) bool {
            return false;
        }
        fn updateBounds(_: ?*anyopaque, widget: *Widget, _: layout_module.Rect) void {
            const self: *@This() = @fieldParentPtr("widget", widget);
            self.bounds_updates += 1;
        }
    };

    var instance = FailingWidget{};
    const previous_rect = layout_module.Rect.init(1, 2, 3, 4);
    const previous_dirty_rect = layout_module.Rect.init(5, 6, 7, 8);
    instance.widget.rect = previous_rect;
    instance.widget.dirty = false;
    instance.widget.dirty_rect = previous_dirty_rect;
    instance.widget.accessibility_update_bounds = FailingWidget.updateBounds;

    try std.testing.expectError(error.ForcedLayout, instance.widget.layout(layout_module.Rect.init(9, 10, 11, 12)));
    try std.testing.expect(rectEql(previous_rect, instance.widget.rect));
    try std.testing.expect(!instance.widget.dirty);
    try std.testing.expect(rectEql(previous_dirty_rect, instance.widget.dirty_rect.?));
    try std.testing.expectEqual(@as(usize, 0), instance.bounds_updates);
}

test "focus ring clamps edge coordinates and oversized insets" {
    const noop_vtable = Widget.VTable{
        .draw = struct {
            fn draw(_: *anyopaque, _: *render.Renderer) anyerror!void {}
        }.draw,
        .handle_event = struct {
            fn handle(_: *anyopaque, _: input.Event) anyerror!bool {
                return false;
            }
        }.handle,
        .layout = struct {
            fn layout(_: *anyopaque, _: layout_module.Rect) anyerror!void {}
        }.layout,
        .get_preferred_size = struct {
            fn preferred(_: *anyopaque) anyerror!layout_module.Size {
                return layout_module.Size.zero();
            }
        }.preferred,
        .can_focus = struct {
            fn can(_: *anyopaque) bool {
                return true;
            }
        }.can,
    };

    var widget = Widget.init(&noop_vtable);
    widget.focused = true;
    widget.focus_ring = render.FocusRingStyle{
        .color = render.Color.named(.cyan),
        .inset = 1,
        .fill = render.Color.named(.black),
    };

    var renderer = try render.Renderer.init(std.testing.allocator, 4, 4);
    defer renderer.deinit();

    widget.rect = layout_module.Rect.init(std.math.maxInt(u16) - 1, std.math.maxInt(u16) - 1, 4, 4);
    widget.drawFocusRing(&renderer);

    widget.focus_ring.?.inset = std.math.maxInt(u16);
    widget.rect = layout_module.Rect.init(0, 0, 1, 1);
    widget.drawFocusRing(&renderer);
}

test "generic Widget pointers notify lifecycle hooks when focus changes" {
    const TestWidget = struct {
        widget: Widget = Widget.init(&vtable),
        state_changes: usize = 0,

        const vtable = Widget.VTable{
            .draw = draw,
            .handle_event = handleEvent,
            .layout = layout,
            .get_preferred_size = getPreferredSize,
            .can_focus = canFocus,
            .on_state_change = stateChange,
        };

        fn draw(_: *anyopaque, _: *render.Renderer) anyerror!void {}

        fn handleEvent(_: *anyopaque, _: input.Event) anyerror!bool {
            return false;
        }

        fn layout(_: *anyopaque, _: layout_module.Rect) anyerror!void {}

        fn getPreferredSize(_: *anyopaque) anyerror!layout_module.Size {
            return layout_module.Size.zero();
        }

        fn canFocus(_: *anyopaque) bool {
            return true;
        }

        fn stateChange(widget_ptr: *anyopaque) void {
            const widget_ref: *Widget = @ptrCast(@alignCast(widget_ptr));
            const self: *@This() = @fieldParentPtr("widget", widget_ref);
            self.state_changes += 1;
        }
    };

    var first = TestWidget{};
    var second = TestWidget{};
    const widgets = [_]*Widget{ &first.widget, &second.widget };

    widgets[0].setFocus(true);
    widgets[0].setFocus(false);
    widgets[1].setFocus(true);

    try std.testing.expect(!first.widget.focused);
    try std.testing.expect(second.widget.focused);
    try std.testing.expectEqual(@as(usize, 2), first.state_changes);
    try std.testing.expectEqual(@as(usize, 1), second.state_changes);
}

test "widget detachFrom only clears the current owner" {
    const alloc = std.testing.allocator;
    var owner = try block_widget.Block.init(alloc);
    var stale_owner = try block_widget.Block.init(alloc);
    var child = try block_widget.Block.init(alloc);
    defer {
        owner.deinit();
        stale_owner.deinit();
        child.deinit();
    }

    try child.widget.attachTo(&owner.widget);
    try std.testing.expect(!child.widget.detachFrom(&stale_owner.widget));
    try std.testing.expectEqual(&owner.widget, child.widget.parent.?);
    try std.testing.expect(child.widget.detachFrom(&owner.widget));
    try std.testing.expect(child.widget.parent == null);
    try std.testing.expect(!child.widget.detachFrom(&owner.widget));
}

test "layout adapter fade clips edge rect without u16 overflow" {
    const fade_vtable = Widget.VTable{
        .draw = struct {
            fn draw(_: *anyopaque, _: *render.Renderer) anyerror!void {}
        }.draw,
        .handle_event = struct {
            fn handle(_: *anyopaque, _: input.Event) anyerror!bool {
                return false;
            }
        }.handle,
        .layout = struct {
            fn layout(_: *anyopaque, _: layout_module.Rect) anyerror!void {}
        }.layout,
        .get_preferred_size = struct {
            fn preferred(_: *anyopaque) anyerror!layout_module.Size {
                return layout_module.Size.zero();
            }
        }.preferred,
        .can_focus = struct {
            fn can(_: *anyopaque) bool {
                return false;
            }
        }.can,
    };

    const TestWidget = struct {
        widget: Widget = Widget.init(&fade_vtable),
    };

    var instance = TestWidget{};
    instance.widget.visibility_transition.progress = 0.5;
    instance.widget.visibility_transition.handle = animation.AnimationHandle{ .id = 1 };
    instance.widget.visibility_transition.options = .{ .mode = .fade };

    var renderer = try render.Renderer.init(std.testing.allocator, 4, 4);
    defer renderer.deinit();

    const element = instance.widget.asLayoutElement();
    element.render(&renderer, layout_module.Rect.init(
        std.math.maxInt(u16) - 1,
        std.math.maxInt(u16) - 1,
        4,
        4,
    ));
}

test "widget animateVisibility restores visible state on scheduling failure" {
    const noop_vtable = Widget.VTable{
        .draw = struct {
            fn draw(_: *anyopaque, _: *render.Renderer) anyerror!void {}
        }.draw,
        .handle_event = struct {
            fn handle(_: *anyopaque, _: input.Event) anyerror!bool {
                return false;
            }
        }.handle,
        .layout = struct {
            fn layout(_: *anyopaque, _: layout_module.Rect) anyerror!void {}
        }.layout,
        .get_preferred_size = struct {
            fn preferred(_: *anyopaque) anyerror!layout_module.Size {
                return layout_module.Size.zero();
            }
        }.preferred,
        .can_focus = struct {
            fn can(_: *anyopaque) bool {
                return false;
            }
        }.can,
    };

    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var animator = animation.Animator.init(failing.allocator());
    defer animator.deinit();

    var widget = Widget.init(&noop_vtable);
    widget.visible = false;
    widget.visibility_transition.snap(false);

    try std.testing.expectError(error.OutOfMemory, widget.animateVisibility(&animator, true, .{}));
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expect(!widget.visible);
    try std.testing.expect(!widget.visibility_transition.target_visible);
    try std.testing.expectEqual(@as(f32, 0), widget.visibility_transition.progress);
    try std.testing.expect(widget.visibility_transition.handle == null);
}
