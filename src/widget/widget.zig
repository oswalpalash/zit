const std = @import("std");

/// Widget library module
///
/// This module provides UI components for building terminal interfaces:
/// - Primitive components (labels, buttons, inputs)
/// - Complex components (dialogs, menus, tabs)
/// - Custom widget API

// Re-export the base Widget API
pub const Widget = @import("widgets/base_widget.zig").Widget;
pub const FocusDirection = @import("widgets/base_widget.zig").FocusDirection;

// Re-export widgets
pub const Label = @import("widgets/label.zig").Label;
pub const Button = @import("widgets/button.zig").Button;
pub const Checkbox = @import("widgets/checkbox.zig").Checkbox;
pub const InputField = @import("widgets/input_field.zig").InputField;
pub const Container = @import("widgets/container.zig").Container;
pub const Scrollbar = @import("widgets/scrollbar.zig").Scrollbar;
pub const ProgressBar = @import("widgets/progress_bar.zig").ProgressBar;
pub const List = @import("widgets/list.zig").List;
pub const TabView = @import("widgets/tab_view.zig").TabView;
pub const ScrollContainer = @import("widgets/scroll_container.zig").ScrollContainer;
pub const DropdownMenu = @import("widgets/dropdown_menu.zig").DropdownMenu;
pub const Table = @import("widgets/table.zig").Table;
pub const Modal = @import("widgets/modal.zig").Modal;

// For when a new file is needed
pub usingnamespace struct {
    pub fn _placeholder() void {}
};

pub const BaseWidget = @import("widgets/base_widget.zig").Widget;
pub const ScrollOrientation = @import("widgets/scrollbar.zig").ScrollOrientation;
pub const BorderStyle = @import("widgets/scroll_container.zig").BorderStyle;
pub const TabItem = @import("widgets/tab_view.zig").TabItem;

pub const ProgressDirection = @import("widgets/progress_bar.zig").ProgressDirection;

/// Create a new button with the given text
pub fn createButton(allocator: std.mem.Allocator, text: []const u8) !*Button {
    var button = try Button.init(allocator);
    try button.setText(text);
    return button;
}

/// Create a new label with the given text
pub fn createLabel(allocator: std.mem.Allocator, text: []const u8) !*Label {
    var label = try Label.init(allocator);
    try label.setText(text);
    return label;
}

/// Create a new container
pub fn createContainer(allocator: std.mem.Allocator) !*Container {
    return Container.init(allocator);
}

/// Create a new input field
pub fn createInputField(allocator: std.mem.Allocator) !*InputField {
    return InputField.init(allocator);
}

/// Create a new list
pub fn createList(allocator: std.mem.Allocator) !*List {
    return List.init(allocator);
}

/// Create a new progress bar
pub fn createProgressBar(allocator: std.mem.Allocator) !*ProgressBar {
    return ProgressBar.init(allocator);
}

/// Create a new scrollbar
pub fn createScrollbar(allocator: std.mem.Allocator, orientation: ScrollOrientation) !*Scrollbar {
    var scrollbar_widget = try Scrollbar.init(allocator);
    scrollbar_widget.setOrientation(orientation);
    return scrollbar_widget;
}

/// Create a new scroll container
pub fn createScrollContainer(allocator: std.mem.Allocator) !*ScrollContainer {
    return ScrollContainer.init(allocator);
}

/// Create a new tab view
pub fn createTabView(allocator: std.mem.Allocator) !*TabView {
    return TabView.init(allocator);
}

/// Create a new modal dialog
pub fn createModal(allocator: std.mem.Allocator) !*Modal {
    return Modal.init(allocator);
}

/// Create a new table
pub fn createTable(allocator: std.mem.Allocator) !*Table {
    return Table.init(allocator);
}

/// Create a new dropdown menu
pub fn createDropdownMenu(allocator: std.mem.Allocator) !*DropdownMenu {
    return DropdownMenu.init(allocator);
}

/// Convenience function to focus a widget
pub fn focusWidget(widget: *BaseWidget) void {
    widget.focused = true;
}

/// Convenience function to enable a widget
pub fn enableWidget(widget: *BaseWidget) void {
    widget.enabled = true;
}

/// Convenience function to disable a widget
pub fn disableWidget(widget: *BaseWidget) void {
    widget.enabled = false;
}

/// Convenience function to show a widget
pub fn showWidget(widget: *BaseWidget) void {
    widget.visible = true;
}

/// Convenience function to hide a widget
pub fn hideWidget(widget: *BaseWidget) void {
    widget.visible = false;
}

test "widget" {
    const expect = std.testing.expect;
    
    const allocator = std.testing.allocator;
    
    // Create a button
    var button = try createButton(allocator, "Test Button");
    defer button.deinit();
    
    try expect(button.widget.enabled);
    try expect(button.widget.visible);
    
    // Test enable/disable
    disableWidget(&button.widget);
    try expect(!button.widget.enabled);
    
    enableWidget(&button.widget);
    try expect(button.widget.enabled);
    
    // Test show/hide
    hideWidget(&button.widget);
    try expect(!button.widget.visible);
    
    showWidget(&button.widget);
    try expect(button.widget.visible);
    
    // Test focus
    try expect(!button.widget.focused);
    
    focusWidget(&button.widget);
    try expect(button.widget.focused);
}