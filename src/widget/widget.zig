const std = @import("std");
const render = @import("../render/render.zig");

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
pub const css = @import("css.zig");

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
pub const Markdown = @import("widgets/markdown.zig").Markdown;
pub const SplitPane = @import("widgets/split_pane.zig").SplitPane;
pub const SplitOrientation = @import("widgets/split_pane.zig").SplitOrientation;
pub const Popup = @import("widgets/popup.zig").Popup;
pub const ToastManager = @import("widgets/toast.zig").ToastManager;
pub const ToastLevel = @import("widgets/toast.zig").ToastLevel;
pub const MenuBar = @import("widgets/menubar.zig").MenuBar;
pub const Canvas = @import("widgets/canvas.zig").Canvas;
pub const ColorPicker = @import("widgets/color_picker.zig").ColorPicker;
pub const FileBrowser = @import("widgets/file_browser.zig").FileBrowser;
pub const DateTimePicker = @import("widgets/date_time_picker.zig").DateTimePicker;
pub const RichText = @import("widgets/rich_text.zig").RichText;
pub const ImageWidget = @import("widgets/image.zig").ImageWidget;
pub const TextArea = @import("widgets/text_area.zig").TextArea;
pub const SyntaxHighlighter = @import("widgets/syntax_highlighter.zig").SyntaxHighlighter;
pub const ToggleSwitch = @import("widgets/advanced_controls.zig").ToggleSwitch;
pub const RadioGroup = @import("widgets/advanced_controls.zig").RadioGroup;
pub const Slider = @import("widgets/advanced_controls.zig").Slider;
pub const RatingStars = @import("widgets/advanced_controls.zig").RatingStars;
pub const StatusBar = @import("widgets/advanced_controls.zig").StatusBar;
pub const Toolbar = @import("widgets/advanced_controls.zig").Toolbar;
pub const Breadcrumbs = @import("widgets/advanced_controls.zig").Breadcrumbs;
pub const Pagination = @import("widgets/advanced_controls.zig").Pagination;
pub const CommandPalette = @import("widgets/advanced_controls.zig").CommandPalette;
pub const NotificationCenter = @import("widgets/advanced_controls.zig").NotificationCenter;
pub const Accordion = @import("widgets/advanced_controls.zig").Accordion;
pub const WizardStepper = @import("widgets/advanced_controls.zig").WizardStepper;
pub const animation = @import("animation.zig");
pub const Animator = animation.Animator;
pub const AnimationSpec = animation.AnimationSpec;
pub const AnimationHandle = animation.AnimationHandle;
pub const Easing = animation.Easing;
pub const accessibility = @import("accessibility.zig");
pub const AccessibilityManager = accessibility.Manager;
pub const AccessibilityRole = accessibility.Role;
pub const AccessibleNode = accessibility.AccessibleNode;
pub const form = @import("form.zig");
pub const builders = @import("builders.zig");

// For when a new file is needed
pub const _placeholder = struct {};

pub const BaseWidget = @import("widgets/base_widget.zig").Widget;
pub const ScrollOrientation = @import("widgets/scrollbar.zig").ScrollOrientation;
pub const BorderStyle = @import("widgets/scroll_container.zig").BorderStyle;
pub const TabItem = @import("widgets/tab_view.zig").TabItem;

pub const ProgressDirection = @import("widgets/progress_bar.zig").ProgressDirection;
pub const ButtonBuilder = builders.ButtonBuilder;
pub const LabelBuilder = builders.LabelBuilder;
pub const CheckboxBuilder = builders.CheckboxBuilder;
pub const InputBuilder = builders.InputBuilder;
pub const TextAreaBuilder = builders.TextAreaBuilder;
pub const ProgressBarBuilder = builders.ProgressBarBuilder;

/// Create a new button with the given text
pub fn createButton(allocator: std.mem.Allocator, text: []const u8) !*Button {
    return Button.init(allocator, text);
}

/// Create a new button using the fluent builder API
pub fn button(allocator: std.mem.Allocator, text: []const u8) !*Button {
    var builder = ButtonBuilder.init(allocator);
    return builder.text(text).build();
}

/// Create a new label with the given text
pub fn createLabel(allocator: std.mem.Allocator, text: []const u8) !*Label {
    var lbl = try Label.init(allocator);
    try lbl.setText(text);
    return lbl;
}

/// Create a new label using the fluent builder API
pub fn label(allocator: std.mem.Allocator, text: []const u8) !*Label {
    var builder = LabelBuilder.init(allocator);
    return builder.content(text).build();
}

/// Create a new container
pub fn createContainer(allocator: std.mem.Allocator) !*Container {
    return Container.init(allocator);
}

/// Create a new input field
pub fn createInputField(allocator: std.mem.Allocator) !*InputField {
    return InputField.init(allocator, 256);
}

/// Create a new input field using the fluent builder API
pub fn input(allocator: std.mem.Allocator, placeholder: []const u8) !*InputField {
    var builder = InputBuilder.init(allocator);
    return builder.withPlaceholder(placeholder).build();
}

/// Create a new multi-line text area
pub fn createTextArea(allocator: std.mem.Allocator) !*TextArea {
    return TextArea.init(allocator, 4096);
}

/// Create a new multi-line text area using the fluent builder API
pub fn textArea(allocator: std.mem.Allocator, placeholder: []const u8) !*TextArea {
    var builder = TextAreaBuilder.init(allocator);
    return builder.withPlaceholder(placeholder).build();
}

/// Create a new list
pub fn createList(allocator: std.mem.Allocator) !*List {
    return List.init(allocator);
}

/// Create a new progress bar
pub fn createProgressBar(allocator: std.mem.Allocator) !*ProgressBar {
    return ProgressBar.init(allocator);
}

/// Create a new progress bar using the fluent builder API
pub fn progress(allocator: std.mem.Allocator, value: usize, max_value: usize) !*ProgressBar {
    var builder = ProgressBarBuilder.init(allocator);
    return builder.range(value, max_value).build();
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

/// Create a new color picker
pub fn createColorPicker(allocator: std.mem.Allocator, palette: []const render.Color) !*ColorPicker {
    return ColorPicker.init(allocator, palette);
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
    var btn = try createButton(allocator, "Test Button");
    defer btn.deinit();

    try expect(btn.widget.enabled);
    try expect(btn.widget.visible);

    // Test enable/disable
    disableWidget(&btn.widget);
    try expect(!btn.widget.enabled);

    enableWidget(&btn.widget);
    try expect(btn.widget.enabled);

    // Test show/hide
    hideWidget(&btn.widget);
    try expect(!btn.widget.visible);

    showWidget(&btn.widget);
    try expect(btn.widget.visible);

    // Test focus
    try expect(!btn.widget.focused);

    focusWidget(&btn.widget);
    try expect(btn.widget.focused);
}
