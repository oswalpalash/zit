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
pub const theme = @import("theme.zig");
pub const Theme = @import("theme.zig").Theme;
pub const ThemeRole = @import("theme.zig").ThemeRole;

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
pub const TreeView = @import("widgets/tree_view.zig").TreeView;
pub const Sparkline = @import("widgets/sparkline.zig").Sparkline;
pub const Gauge = @import("widgets/gauge.zig").Gauge;
pub const GaugeOrientation = @import("widgets/gauge.zig").GaugeOrientation;
pub const SplitPane = @import("widgets/split_pane.zig").SplitPane;
pub const SplitOrientation = @import("widgets/split_pane.zig").SplitOrientation;
pub const Popup = @import("widgets/popup.zig").Popup;
pub const ToastManager = @import("widgets/toast.zig").ToastManager;
pub const ToastLevel = @import("widgets/toast.zig").ToastLevel;
pub const MenuBar = @import("widgets/menubar.zig").MenuBar;
pub const Canvas = @import("widgets/canvas.zig").Canvas;
pub const animation = @import("animation.zig");
pub const Animator = animation.Animator;
pub const AnimationSpec = animation.AnimationSpec;
pub const AnimationHandle = animation.AnimationHandle;
pub const Easing = animation.Easing;

// For when a new file is needed
pub const _placeholder = struct {};

pub const BaseWidget = @import("widgets/base_widget.zig").Widget;
pub const ScrollOrientation = @import("widgets/scrollbar.zig").ScrollOrientation;
pub const BorderStyle = @import("widgets/scroll_container.zig").BorderStyle;
pub const TabItem = @import("widgets/tab_view.zig").TabItem;

pub const ProgressDirection = @import("widgets/progress_bar.zig").ProgressDirection;

/// Create a new button with the given text
pub fn createButton(allocator: std.mem.Allocator, text: []const u8) !*Button {
    return Button.init(allocator, text);
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

/// Create a new tree view
pub fn createTreeView(allocator: std.mem.Allocator) !*TreeView {
    return TreeView.init(allocator);
}

/// Create a new sparkline
pub fn createSparkline(allocator: std.mem.Allocator) !*Sparkline {
    return Sparkline.init(allocator);
}

/// Create a new gauge
pub fn createGauge(allocator: std.mem.Allocator) !*Gauge {
    return Gauge.init(allocator);
}

/// Create a new split pane
pub fn createSplitPane(allocator: std.mem.Allocator) !*SplitPane {
    return SplitPane.init(allocator);
}

/// Create a new popup
pub fn createPopup(allocator: std.mem.Allocator, message: []const u8) !*Popup {
    return Popup.init(allocator, message);
}

/// Create a new toast manager
pub fn createToastManager(allocator: std.mem.Allocator) !*ToastManager {
    return ToastManager.init(allocator);
}

/// Create a new menu bar
pub fn createMenuBar(allocator: std.mem.Allocator) !*MenuBar {
    return MenuBar.init(allocator);
}

/// Create a new canvas
pub fn createCanvas(allocator: std.mem.Allocator, width: u16, height: u16) !*Canvas {
    return Canvas.init(allocator, width, height);
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
