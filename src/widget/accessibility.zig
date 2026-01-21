const std = @import("std");
const base = @import("widgets/base_widget.zig");
const layout = @import("../layout/layout.zig");
const theme = @import("theme.zig");

/// Accessible roles to describe widgets.
pub const Role = enum {
    generic,
    button,
    checkbox,
    input,
    list,
    container,
    popup,
    menu,
    canvas,
    slider,
    progressbar,
    tab,
    tablist,
    tabpanel,
    alert,
    status,
    tooltip,
};

pub const AccessibleNode = struct {
    widget_ptr: *base.Widget,
    role: Role = .generic,
    name: []const u8 = "",
    description: []const u8 = "",
    bounds: layout.Rect = layout.Rect.init(0, 0, 0, 0),
};

/// Minimal accessibility manager that tracks widget semantics and produces announcements.
pub const Manager = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayList(AccessibleNode),
    last_announcement: []u8 = &[_]u8{},
    high_contrast: bool = false,

    pub fn init(allocator: std.mem.Allocator) Manager {
        return Manager{
            .allocator = allocator,
            .nodes = std.ArrayList(AccessibleNode).empty,
            .high_contrast = false,
        };
    }

    pub fn deinit(self: *Manager) void {
        for (self.nodes.items) |node| {
            if (node.name.len > 0) self.allocator.free(node.name);
            if (node.description.len > 0) self.allocator.free(node.description);
        }
        self.nodes.deinit(self.allocator);
        if (self.last_announcement.len > 0) {
            self.allocator.free(self.last_announcement);
        }
    }

    pub fn registerNode(self: *Manager, node: AccessibleNode) !void {
        if (self.findNode(node.widget_ptr)) |existing| {
            if (existing.name.len > 0) self.allocator.free(existing.name);
            if (existing.description.len > 0) self.allocator.free(existing.description);
            existing.* = AccessibleNode{
                .widget_ptr = node.widget_ptr,
                .role = node.role,
                .name = try self.allocator.dupe(u8, node.name),
                .description = try self.allocator.dupe(u8, node.description),
                .bounds = node.bounds,
            };
            return;
        }

        var stored = node;
        stored.name = try self.allocator.dupe(u8, node.name);
        stored.description = try self.allocator.dupe(u8, node.description);
        try self.nodes.append(self.allocator, stored);
    }

    pub fn updateBounds(self: *Manager, ptr: *base.Widget, rect: layout.Rect) void {
        if (self.findNode(ptr)) |node| {
            node.bounds = rect;
        }
    }

    pub fn announceFocus(self: *Manager, ptr: *base.Widget) ![]const u8 {
        if (self.last_announcement.len > 0) {
            self.allocator.free(self.last_announcement);
            self.last_announcement = &[_]u8{};
        }

        const node = self.findNode(ptr) orelse {
            self.last_announcement = try std.fmt.allocPrint(self.allocator, "Focused element", .{});
            return self.last_announcement;
        };

        const role_name = roleToString(node.role);
        if (node.description.len > 0) {
            self.last_announcement = try std.fmt.allocPrint(self.allocator, "{s}: {s} - {s}", .{ role_name, node.name, node.description });
        } else {
            self.last_announcement = try std.fmt.allocPrint(self.allocator, "{s}: {s}", .{ role_name, node.name });
        }
        return self.last_announcement;
    }

    /// Announce a state or value change for a widget (e.g. progress updates).
    pub fn announceState(self: *Manager, ptr: *base.Widget, state: []const u8) ![]const u8 {
        if (self.last_announcement.len > 0) {
            self.allocator.free(self.last_announcement);
            self.last_announcement = &[_]u8{};
        }

        const node = self.findNode(ptr) orelse {
            self.last_announcement = try std.fmt.allocPrint(self.allocator, "{s}", .{state});
            return self.last_announcement;
        };

        const role_name = roleToString(node.role);
        self.last_announcement = try std.fmt.allocPrint(self.allocator, "{s}: {s} ({s})", .{ role_name, node.name, state });
        return self.last_announcement;
    }

    pub fn lastAnnouncement(self: *Manager) []const u8 {
        return self.last_announcement;
    }

    /// Toggle high contrast preference to inform theme selection.
    pub fn setHighContrast(self: *Manager, enabled: bool) void {
        self.high_contrast = enabled;
    }

    pub fn prefersHighContrast(self: *Manager) bool {
        return self.high_contrast;
    }

    /// Helper to opt into the built-in high contrast theme.
    pub fn highContrastTheme(self: *Manager) theme.Theme {
        _ = self;
        return theme.Theme.highContrast();
    }

    fn findNode(self: *Manager, ptr: *base.Widget) ?*AccessibleNode {
        for (self.nodes.items) |*node| {
            if (node.widget_ptr == ptr) return node;
        }
        return null;
    }
};

pub fn roleToString(role: Role) []const u8 {
    return switch (role) {
        .generic => "element",
        .button => "button",
        .checkbox => "checkbox",
        .input => "input",
        .list => "list",
        .container => "container",
        .popup => "popup",
        .menu => "menu",
        .canvas => "canvas",
        .slider => "slider",
        .progressbar => "progress bar",
        .tab => "tab",
        .tablist => "tab list",
        .tabpanel => "tab panel",
        .alert => "alert",
        .status => "status",
        .tooltip => "tooltip",
    };
}

test "accessibility manager registers nodes and announces focus" {
    const alloc = std.testing.allocator;
    var manager = Manager.init(alloc);
    defer manager.deinit();

    var fake_widget = base.Widget.init(&base.Widget.VTable{
        .draw = undefined,
        .handle_event = undefined,
        .layout = undefined,
        .get_preferred_size = undefined,
        .can_focus = undefined,
    });

    try manager.registerNode(AccessibleNode{
        .widget_ptr = &fake_widget,
        .role = .button,
        .name = "Submit",
        .description = "Sends form data",
    });

    _ = try manager.announceFocus(&fake_widget);
    try std.testing.expectEqualStrings("button: Submit - Sends form data", manager.lastAnnouncement());
}

test "high contrast preference and state announcements" {
    const alloc = std.testing.allocator;
    var manager = Manager.init(alloc);
    defer manager.deinit();

    var widget_instance = base.Widget.init(&base.Widget.VTable{
        .draw = undefined,
        .handle_event = undefined,
        .layout = undefined,
        .get_preferred_size = undefined,
        .can_focus = undefined,
    });

    try manager.registerNode(AccessibleNode{
        .widget_ptr = &widget_instance,
        .role = .progressbar,
        .name = "Download",
    });

    manager.setHighContrast(true);
    try std.testing.expect(manager.prefersHighContrast());
    const announcement = try manager.announceState(&widget_instance, "50%");
    try std.testing.expectEqualStrings("progress bar: Download (50%)", announcement);
    const hc = manager.highContrastTheme();
    try std.testing.expect(hc.style.bold);
}
