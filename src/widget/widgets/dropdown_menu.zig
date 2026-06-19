const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const theme = @import("../theme.zig");
const accessibility = @import("../accessibility.zig");

/// MenuItem structure
pub const MenuItem = struct {
    /// Menu item text
    text: []const u8,
    /// Menu item is enabled
    enabled: bool = true,
    /// Menu item data (optional)
    data: ?*anyopaque = null,
};

/// DropdownMenu widget for creating dropdown menus
pub const DropdownMenu = struct {
    /// Base widget
    widget: base.Widget,
    /// Menu items
    items: std.ArrayList(MenuItem),
    /// Selected item index
    selected_index: usize = 0,
    /// Label/caption text
    label: []const u8 = "",
    /// Menu is open
    is_open: bool = false,
    /// Foreground color
    fg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    /// Background color
    bg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    /// Selected item foreground color
    selected_fg: render.Color = render.Color{ .named_color = render.NamedColor.black },
    /// Selected item background color
    selected_bg: render.Color = render.Color{ .named_color = render.NamedColor.cyan },
    /// Focused foreground color
    focused_fg: render.Color = render.Color{ .named_color = render.NamedColor.black },
    /// Focused background color
    focused_bg: render.Color = render.Color{ .named_color = render.NamedColor.white },
    /// Disabled foreground color
    disabled_fg: render.Color = render.Color{ .named_color = render.NamedColor.bright_black },
    /// Disabled background color
    disabled_bg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    /// On selection callback
    on_select: ?*const fn (usize) void = null,
    /// Allocator for dropdown menu operations
    allocator: std.mem.Allocator,

    /// Virtual method table for DropdownMenu
    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    /// Initialize a new dropdown menu
    pub fn init(allocator: std.mem.Allocator) !*DropdownMenu {
        const self = try allocator.create(DropdownMenu);

        self.* = DropdownMenu{
            .widget = base.Widget.init(&vtable),
            .items = std.ArrayList(MenuItem).empty,
            .allocator = allocator,
        };
        self.setTheme(theme.Theme.dark());
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.menu), self.label, "");

        return self;
    }

    /// Clean up dropdown menu resources
    pub fn deinit(self: *DropdownMenu) void {
        // Free all items
        for (self.items.items) |item| {
            self.allocator.free(item.text);
        }
        self.items.deinit(self.allocator);

        // Free label if set
        if (self.label.len > 0) {
            self.allocator.free(self.label);
        }

        self.allocator.destroy(self);
    }

    /// Add an item to the dropdown menu
    pub fn addItem(self: *DropdownMenu, text: []const u8, enabled: bool, data: ?*anyopaque) !void {
        try self.items.ensureUnusedCapacity(self.allocator, 1);
        const text_copy = try self.allocator.dupe(u8, text);

        self.items.appendAssumeCapacity(MenuItem{
            .text = text_copy,
            .enabled = enabled,
            .data = data,
        });
    }

    /// Remove an item from the dropdown menu
    pub fn removeItem(self: *DropdownMenu, index: usize) void {
        if (index >= self.items.items.len) {
            return;
        }

        // Free the item text
        self.allocator.free(self.items.items[index].text);

        // Remove the item
        _ = self.items.orderedRemove(index);

        // Update selected index if needed
        if (self.selected_index >= self.items.items.len) {
            self.setSelectedIndex(if (self.items.items.len > 0) self.items.items.len - 1 else 0);
        }
    }

    /// Set the dropdown label/caption
    pub fn setLabel(self: *DropdownMenu, label: []const u8) !void {
        const label_copy = if (label.len == 0) "" else try self.allocator.dupe(u8, label);

        if (self.label.len > 0) {
            self.allocator.free(self.label);
        }

        self.label = label_copy;
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.menu), self.label, "");
    }

    /// Set the selected item
    pub fn setSelectedIndex(self: *DropdownMenu, index: usize) void {
        if (index == self.selected_index or self.items.items.len == 0) {
            return;
        }

        const old_index = self.selected_index;
        self.selected_index = @min(index, self.items.items.len - 1);

        // Call the selection changed callback
        if (old_index != self.selected_index and self.on_select != null) {
            self.on_select.?(self.selected_index);
        }
    }

    /// Apply theme defaults for dropdown colors.
    pub fn setTheme(self: *DropdownMenu, theme_value: theme.Theme) void {
        const base_colors = theme.controlColors(theme_value);
        const selected = theme.selectionColors(theme_value);
        self.fg = base_colors.fg;
        self.bg = base_colors.bg;
        self.selected_fg = selected.fg;
        self.selected_bg = selected.bg;
        self.focused_fg = selected.focused_fg;
        self.focused_bg = selected.focused_bg;
        self.disabled_fg = base_colors.disabled_fg;
        self.disabled_bg = base_colors.disabled_bg;
    }

    /// Get the selected item index
    pub fn getSelectedIndex(self: *DropdownMenu) usize {
        return self.selected_index;
    }

    /// Get the selected item text
    pub fn getSelectedItemText(self: *DropdownMenu) ?[]const u8 {
        if (self.items.items.len == 0) {
            return null;
        }
        return self.items.items[self.selected_index].text;
    }

    /// Get the selected item data
    pub fn getSelectedItemData(self: *DropdownMenu) ?*anyopaque {
        if (self.items.items.len == 0) {
            return null;
        }
        return self.items.items[self.selected_index].data;
    }

    /// Open the dropdown menu
    pub fn open(self: *DropdownMenu) void {
        self.is_open = true;
    }

    /// Close the dropdown menu
    pub fn close(self: *DropdownMenu) void {
        self.is_open = false;
    }

    /// Toggle the dropdown menu state
    pub fn toggle(self: *DropdownMenu) void {
        self.is_open = !self.is_open;
    }

    /// Set the dropdown menu colors
    pub fn setColors(self: *DropdownMenu, fg: render.Color, bg: render.Color, selected_fg: render.Color, selected_bg: render.Color) void {
        self.fg = fg;
        self.bg = bg;
        self.selected_fg = selected_fg;
        self.selected_bg = selected_bg;
    }

    /// Set the on-select callback
    pub fn setOnSelect(self: *DropdownMenu, callback: *const fn (usize) void) void {
        self.on_select = callback;
    }

    /// Draw implementation for DropdownMenu
    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *DropdownMenu = @fieldParentPtr("widget", widget_ref);

        if (!self.widget.visible) {
            return;
        }

        const rect = self.widget.rect;

        // Choose colors based on state
        const base_bg = if (!self.widget.enabled)
            self.disabled_bg
        else if (self.widget.focused)
            self.focused_bg
        else
            self.bg;

        const base_fg = if (!self.widget.enabled)
            self.disabled_fg
        else if (self.widget.focused)
            self.focused_fg
        else
            self.fg;

        const styled = self.widget.applyStyle(
            "dropdown",
            .{ .focus = self.widget.focused, .disabled = !self.widget.enabled },
            render.Style{},
            base_fg,
            base_bg,
        );
        const fg = styled.fg;
        const bg = styled.bg;
        const style = styled.style;

        if (rect.width == 0 or rect.height == 0) return;

        // Fill dropdown background
        renderer.fillRect(rect.x, rect.y, rect.width, 1, ' ', fg, bg, style);

        // Draw selected item or label
        var display_text: []const u8 = undefined;
        if (self.items.items.len > 0) {
            display_text = self.items.items[self.selected_index].text;
        } else if (self.label.len > 0) {
            display_text = self.label;
        } else {
            display_text = "";
        }

        // Draw text
        const header_text_capacity: u16 = if (rect.width > 2) rect.width - 2 else 0;
        if (header_text_capacity > 0) {
            var x = rect.x + 1;
            for (display_text, 0..) |char, i| {
                if (i >= header_text_capacity) {
                    break;
                }

                renderer.drawChar(x, rect.y, char, fg, bg, style);
                x += 1;
            }
        }

        // Draw dropdown arrow
        const arrow_x = if (rect.width >= 2) rect.x + rect.width - 2 else rect.x;
        renderer.drawChar(arrow_x, rect.y, '▼', fg, bg, style);

        // Draw dropdown menu if open
        if (self.is_open and self.items.items.len > 0 and rect.y < std.math.maxInt(u16)) {
            const menu_height = @min(@as(i16, @intCast(self.items.items.len)), 10);
            const menu_height_u16: u16 = @intCast(menu_height);

            // Fill menu background
            renderer.fillRect(rect.x, rect.y + 1, rect.width, menu_height_u16, ' ', fg, bg, style);

            // Draw menu items
            const item_text_capacity: u16 = if (rect.width > 1) rect.width - 1 else 0;
            for (self.items.items, 0..) |item, i| {
                if (i >= @as(usize, @intCast(menu_height))) {
                    break;
                }

                const item_y = rect.y + 1 + @as(u16, @intCast(i));
                const is_selected = i == self.selected_index;

                // Choose colors based on selection and enabled state
                const item_fg = if (!item.enabled)
                    self.disabled_fg
                else if (is_selected)
                    self.selected_fg
                else
                    self.fg;

                const item_bg = if (is_selected)
                    self.selected_bg
                else
                    self.bg;

                // Draw item background
                renderer.fillRect(rect.x, item_y, rect.width, 1, ' ', item_fg, item_bg, style);

                // Draw item text
                if (item_text_capacity > 0) {
                    var x = rect.x + 1;
                    for (item.text, 0..) |char, text_idx| {
                        if (text_idx >= item_text_capacity) {
                            break;
                        }

                        renderer.drawChar(x, item_y, char, item_fg, item_bg, style);
                        x += 1;
                    }
                }
            }
        }
    }

    /// Event handling implementation for DropdownMenu
    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *DropdownMenu = @fieldParentPtr("widget", widget_ref);

        if (!self.widget.visible or !self.widget.enabled or self.items.items.len == 0) {
            return false;
        }

        // Handle mouse events
        if (event == .mouse) {
            const mouse_event = event.mouse;
            const rect = self.widget.rect;

            // Check if mouse is within dropdown header bounds
            if (mouse_event.y == rect.y and mouse_event.x >= rect.x and mouse_event.x < rect.x + rect.width) {
                // Toggle dropdown on click
                if (mouse_event.action == .press and mouse_event.button == 1) {
                    self.toggle();
                    return true;
                }
            }

            // Check if mouse is within dropdown menu bounds
            if (self.is_open and
                mouse_event.y >= rect.y + 1 and
                mouse_event.y < rect.y + 1 + @as(u16, @intCast(@min(@as(i16, @intCast(self.items.items.len)), 10))) and
                mouse_event.x >= rect.x and
                mouse_event.x < rect.x + rect.width)
            {

                // Convert y position to item index
                const item_index = @as(usize, @intCast(mouse_event.y - (rect.y + 1)));

                if (item_index < self.items.items.len and self.items.items[item_index].enabled) {
                    // Select item on click
                    if (mouse_event.action == .press and mouse_event.button == 1) {
                        self.setSelectedIndex(item_index);
                        self.close();
                        return true;
                    }
                }

                return true; // Capture all mouse events within menu bounds
            }

            // Close dropdown if clicked outside
            if (self.is_open and mouse_event.action == .press) {
                self.close();
                return false; // Allow the click to be processed by other widgets
            }
        }

        // Handle key events
        if (event == .key and self.widget.focused) {
            const key_event = event.key;
            const profiles = [_]input.KeybindingProfile{
                input.KeybindingProfile.commonEditing(),
                input.KeybindingProfile.emacs(),
                input.KeybindingProfile.vi(),
            };

            if (self.is_open) {
                // Navigation within open dropdown
                if (input.editorActionForEvent(key_event, &profiles)) |action| {
                    switch (action) {
                        .cursor_down => {
                            var index = self.selected_index;
                            while (index < self.items.items.len - 1) {
                                index += 1;
                                if (self.items.items[index].enabled) {
                                    self.setSelectedIndex(index);
                                    break;
                                }
                            }
                            return true;
                        },
                        .cursor_up => {
                            var index = self.selected_index;
                            while (index > 0) {
                                index -= 1;
                                if (self.items.items[index].enabled) {
                                    self.setSelectedIndex(index);
                                    break;
                                }
                            }
                            return true;
                        },
                        else => {},
                    }
                }

                if (key_event.key == input.KeyCode.ENTER or key_event.key == input.KeyCode.SPACE) {
                    self.close();
                    return true;
                } else if (key_event.key == input.KeyCode.ESCAPE) {
                    self.close();
                    return true;
                }
            } else {
                // Open dropdown on Enter, Space, or Down arrow
                if (input.editorActionForEvent(key_event, &profiles)) |action| {
                    if (action == .cursor_down or action == .cursor_up) {
                        self.open();
                        return true;
                    }
                }

                if (key_event.key == input.KeyCode.ENTER or key_event.key == input.KeyCode.SPACE) {
                    self.open();
                    return true;
                }
            }
        }

        return false;
    }

    /// Layout implementation for DropdownMenu
    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *DropdownMenu = @fieldParentPtr("widget", widget_ref);
        self.widget.rect = rect;
    }

    /// Get preferred size implementation for DropdownMenu
    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *DropdownMenu = @fieldParentPtr("widget", widget_ref);

        // Find the longest item
        var max_width: i16 = 10; // Minimum width

        // Check label length
        if (self.label.len > 0) {
            max_width = @max(max_width, @as(i16, @intCast(self.label.len)) + 4); // Add space for arrow and padding
        }

        // Check item lengths
        for (self.items.items) |item| {
            max_width = @max(max_width, @as(i16, @intCast(item.text.len)) + 4); // Add space for arrow and padding
        }

        // Height is always 1 when closed
        return layout_module.Size.init(@as(u16, @intCast(max_width)), 1);
    }

    /// Can focus implementation for DropdownMenu
    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *DropdownMenu = @fieldParentPtr("widget", widget_ref);
        return self.widget.enabled and self.items.items.len > 0;
    }
};

var test_dropdown_selection: ?usize = null;

test "dropdown menu init/deinit" {
    const alloc = std.testing.allocator;
    var menu = try DropdownMenu.init(alloc);
    defer menu.deinit();

    try std.testing.expectEqual(@as(usize, 0), menu.items.items.len);
    try menu.setLabel("Pick one");
    try menu.addItem("One", true, null);
}

test "dropdown menu addItem preserves items on append allocation failure" {
    const alloc = std.testing.allocator;
    var menu = try DropdownMenu.init(alloc);
    defer menu.deinit();

    try menu.addItem("stable", true, null);

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = menu.allocator;
    menu.allocator = failing.allocator();
    defer menu.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, menu.addItem("new", true, null));
    try std.testing.expectEqual(@as(usize, 1), menu.items.items.len);
    try std.testing.expectEqualStrings("stable", menu.items.items[0].text);
}

test "dropdown menu setLabel preserves label on allocation failure" {
    const alloc = std.testing.allocator;
    var menu = try DropdownMenu.init(alloc);
    defer menu.deinit();

    try menu.setLabel("Stable");

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = menu.allocator;
    menu.allocator = failing.allocator();
    defer menu.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, menu.setLabel("Replacement"));
    try std.testing.expectEqualStrings("Stable", menu.label);
    try std.testing.expectEqualStrings("Stable", menu.widget.accessibility_name);
}

test "dropdown menu selects item on click" {
    const alloc = std.testing.allocator;
    var menu = try DropdownMenu.init(alloc);
    defer menu.deinit();

    try menu.addItem("One", true, null);
    try menu.addItem("Two", true, null);
    menu.widget.rect = layout_module.Rect.init(0, 0, 10, 1);

    test_dropdown_selection = null;
    const callback = struct {
        fn call(index: usize) void {
            test_dropdown_selection = index;
        }
    }.call;
    menu.setOnSelect(callback);

    const open_event = input.Event{ .mouse = input.MouseEvent.init(.press, 0, 0, 1, 0) };
    try std.testing.expect(try menu.widget.handleEvent(open_event));
    try std.testing.expect(menu.is_open);

    const select_event = input.Event{ .mouse = input.MouseEvent.init(.press, 0, 2, 1, 0) };
    try std.testing.expect(try menu.widget.handleEvent(select_event));
    try std.testing.expectEqual(@as(usize, 1), menu.selected_index);
    try std.testing.expectEqual(@as(?usize, 1), test_dropdown_selection);
    try std.testing.expect(!menu.is_open);
}

test "dropdown menu ignores input when empty" {
    const alloc = std.testing.allocator;
    var menu = try DropdownMenu.init(alloc);
    defer menu.deinit();
    menu.widget.rect = layout_module.Rect.init(0, 0, 10, 1);

    const click_event = input.Event{ .mouse = input.MouseEvent.init(.press, 0, 0, 1, 0) };
    try std.testing.expect(!try menu.widget.handleEvent(click_event));
    try std.testing.expect(menu.getSelectedItemText() == null);
}

test "dropdown menu tolerates tiny render widths" {
    const alloc = std.testing.allocator;
    var menu = try DropdownMenu.init(alloc);
    defer menu.deinit();
    try menu.addItem("One", true, null);
    try menu.addItem("Two", true, null);
    menu.open();

    var zero = try render.Renderer.init(alloc, 1, 3);
    defer zero.deinit();
    menu.widget.rect = layout_module.Rect.init(0, 0, 0, 1);
    try menu.widget.draw(&zero);

    var one = try render.Renderer.init(alloc, 1, 3);
    defer one.deinit();
    menu.widget.rect = layout_module.Rect.init(0, 0, 1, 1);
    try menu.widget.draw(&one);
}
