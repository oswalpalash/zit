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
        const name_copy = try self.allocator.dupe(u8, node.name);
        errdefer if (name_copy.len > 0) self.allocator.free(name_copy);
        const description_copy = try self.allocator.dupe(u8, node.description);
        errdefer if (description_copy.len > 0) self.allocator.free(description_copy);

        if (self.findNode(node.widget_ptr)) |existing| {
            const old_name = existing.name;
            const old_description = existing.description;
            existing.* = AccessibleNode{
                .widget_ptr = node.widget_ptr,
                .role = node.role,
                .name = name_copy,
                .description = description_copy,
                .bounds = node.bounds,
            };
            if (old_name.len > 0) self.allocator.free(old_name);
            if (old_description.len > 0) self.allocator.free(old_description);
            return;
        }

        try self.nodes.append(self.allocator, AccessibleNode{
            .widget_ptr = node.widget_ptr,
            .role = node.role,
            .name = name_copy,
            .description = description_copy,
            .bounds = node.bounds,
        });
    }

    pub fn updateBounds(self: *Manager, ptr: *base.Widget, rect: layout.Rect) void {
        if (self.findNode(ptr)) |node| {
            node.bounds = rect;
        }
    }

    pub fn announceFocus(self: *Manager, ptr: *base.Widget) ![]const u8 {
        const node = self.findNode(ptr) orelse {
            const next = try std.fmt.allocPrint(self.allocator, "Focused element", .{});
            self.replaceAnnouncement(next);
            return self.last_announcement;
        };

        const role_name = roleToString(node.role);
        const next = if (node.description.len > 0)
            try std.fmt.allocPrint(self.allocator, "{s}: {s} - {s}", .{ role_name, node.name, node.description })
        else
            try std.fmt.allocPrint(self.allocator, "{s}: {s}", .{ role_name, node.name });
        self.replaceAnnouncement(next);
        return self.last_announcement;
    }

    fn replaceAnnouncement(self: *Manager, next: []u8) void {
        if (self.last_announcement.len > 0) {
            self.allocator.free(self.last_announcement);
        }
        self.last_announcement = next;
    }

    /// Announce a state or value change for a widget (e.g. progress updates).
    pub fn announceState(self: *Manager, ptr: *base.Widget, state: []const u8) ![]const u8 {
        const node = self.findNode(ptr) orelse {
            const next = try std.fmt.allocPrint(self.allocator, "{s}", .{state});
            self.replaceAnnouncement(next);
            return self.last_announcement;
        };

        const role_name = roleToString(node.role);
        const next = try std.fmt.allocPrint(self.allocator, "{s}: {s} ({s})", .{ role_name, node.name, state });
        self.replaceAnnouncement(next);
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

fn accessibilityRegisterAllocationFailureHarness(allocator: std.mem.Allocator) !void {
    var manager = Manager.init(allocator);
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
        .role = .button,
        .name = "Save",
        .description = "Writes the file",
    });
}

fn accessibilityRegisterUpdateAllocationFailureHarness(allocator: std.mem.Allocator) !void {
    var manager = Manager.init(allocator);
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
        .role = .button,
        .name = "Save",
        .description = "Writes the file",
    });
    try manager.registerNode(AccessibleNode{
        .widget_ptr = &widget_instance,
        .role = .input,
        .name = "Search",
        .description = "Filters results",
    });
    try std.testing.expectEqualStrings("Search", manager.nodes.items[0].name);
    try std.testing.expectEqualStrings("Filters results", manager.nodes.items[0].description);
}

test "accessibility register cleans up every allocation failure path" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, accessibilityRegisterAllocationFailureHarness, .{});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, accessibilityRegisterUpdateAllocationFailureHarness, .{});
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

test "accessibility register preserves existing node on allocation failure" {
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
        .role = .button,
        .name = "Save",
        .description = "Writes the file",
    });

    const original_allocator = manager.allocator;
    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 1 });
    manager.allocator = failing.allocator();
    try std.testing.expectError(error.OutOfMemory, manager.registerNode(AccessibleNode{
        .widget_ptr = &widget_instance,
        .role = .input,
        .name = "Search",
        .description = "Filters results",
    }));
    manager.allocator = original_allocator;

    try std.testing.expectEqual(@as(usize, 1), manager.nodes.items.len);
    try std.testing.expectEqual(Role.button, manager.nodes.items[0].role);
    try std.testing.expectEqualStrings("Save", manager.nodes.items[0].name);
    try std.testing.expectEqualStrings("Writes the file", manager.nodes.items[0].description);
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

test "focus announcement preserves previous text on allocation failure" {
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
        .role = .button,
        .name = "Save",
    });
    _ = try manager.announceFocus(&widget_instance);
    try std.testing.expectEqualStrings("button: Save", manager.lastAnnouncement());

    const original_allocator = manager.allocator;
    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    manager.allocator = failing.allocator();
    try std.testing.expectError(error.OutOfMemory, manager.announceFocus(&widget_instance));
    manager.allocator = original_allocator;

    try std.testing.expectEqualStrings("button: Save", manager.lastAnnouncement());
}

test "state announcement preserves previous text on allocation failure" {
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
    _ = try manager.announceState(&widget_instance, "50%");
    try std.testing.expectEqualStrings("progress bar: Download (50%)", manager.lastAnnouncement());

    const original_allocator = manager.allocator;
    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    manager.allocator = failing.allocator();
    try std.testing.expectError(error.OutOfMemory, manager.announceState(&widget_instance, "75%"));
    manager.allocator = original_allocator;

    try std.testing.expectEqualStrings("progress bar: Download (50%)", manager.lastAnnouncement());
}
