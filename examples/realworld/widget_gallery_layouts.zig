// Real-world demo: deterministic layout, navigation, and overlay widget gallery.

const std = @import("std");
const zit = @import("zit");
const interactive = @import("interactive_snapshot.zig");

const Rect = zit.layout.Rect;
const Color = zit.render.Color;
const NamedColor = zit.render.NamedColor;
const Style = zit.render.Style;

fn drawText(mock: *zit.testing.MockTerminal, x: u16, y: u16, text: []const u8, color: NamedColor, style: Style) void {
    mock.renderer.drawStr(x, y, text, Color.named(color), Color.named(.default), style);
}

fn drawHeading(mock: *zit.testing.MockTerminal, x: u16, y: u16, text: []const u8) void {
    drawText(mock, x, y, text, .bright_white, Style{ .bold = true });
}

fn paintImage(image: *zit.widget.ImageWidget) void {
    var y: u16 = 0;
    while (y < image.height) : (y += 1) {
        var x: u16 = 0;
        while (x < image.width) : (x += 1) {
            const color = switch ((x + y) % 5) {
                0 => Color.named(.cyan),
                1 => Color.named(.blue),
                2 => Color.named(.green),
                3 => Color.named(.yellow),
                else => Color.named(.magenta),
            };
            image.setPixel(x, y, color);
        }
    }
}

/// Render layout/navigation widgets for an interactive terminal or snapshot capture.
pub fn main(init: std.process.Init) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var mock = try zit.testing.MockTerminal.init(allocator, 120, 46);
    defer mock.deinit();

    drawHeading(&mock, 2, 0, "Zit layout/navigation gallery");
    drawText(&mock, 34, 0, "deterministic public widget coverage", .bright_black, Style{});

    drawHeading(&mock, 2, 3, "Containers");

    var container_label = try zit.widget.Label.init(allocator, "Container child");
    defer container_label.deinit();
    container_label.setAlignment(.center);
    container_label.setColor(Color.named(.bright_white), Color.named(.black));
    var container = try zit.widget.Container.init(allocator);
    defer container.deinit();
    container.setBorder(.rounded);
    try container.addChild(&container_label.widget);
    try container.widget.layout(Rect.init(2, 5, 25, 5));
    try container.widget.draw(&mock.renderer);

    var flex_a = try zit.widget.Button.init(allocator, "Build");
    defer flex_a.deinit();
    var flex_b = try zit.widget.Button.init(allocator, "Verify");
    defer flex_b.deinit();
    flex_b.widget.setFocus(true);
    var flex = try zit.widget.FlexContainer.init(allocator, .row);
    defer flex.deinit();
    flex.setPadding(zit.layout.EdgeInsets.all(0));
    flex.setGap(1);
    try flex.addChild(&flex_a.widget, 1);
    try flex.addChild(&flex_b.widget, 1);
    try flex.widget.layout(Rect.init(30, 5, 34, 3));
    try flex.widget.draw(&mock.renderer);
    drawText(&mock, 30, 9, "FlexContainer", .bright_black, Style{});

    var grid_one = try zit.widget.Label.init(allocator, "Grid A");
    defer grid_one.deinit();
    grid_one.setColor(Color.named(.bright_white), Color.named(.black));
    var grid_two = try zit.widget.Label.init(allocator, "Grid B");
    defer grid_two.deinit();
    grid_two.setColor(Color.named(.bright_white), Color.named(.black));
    var grid_three = try zit.widget.Label.init(allocator, "Grid C");
    defer grid_three.deinit();
    grid_three.setColor(Color.named(.bright_white), Color.named(.black));
    var grid = try zit.widget.GridContainer.init(allocator, 2, 2);
    defer grid.deinit();
    grid.setGap(1);
    try grid.addChild(&grid_one.widget, 0, 0);
    try grid.addChild(&grid_two.widget, 1, 0);
    try grid.addChild(&grid_three.widget, 0, 1);
    try grid.widget.layout(Rect.init(68, 5, 28, 5));
    try grid.widget.draw(&mock.renderer);
    drawText(&mock, 68, 10, "GridContainer", .bright_black, Style{});

    drawHeading(&mock, 2, 13, "Navigation");

    var tab_a = try zit.widget.Label.init(allocator, "Overview screen");
    defer tab_a.deinit();
    var tab_b = try zit.widget.Label.init(allocator, "Metrics panel");
    defer tab_b.deinit();
    var tab_c = try zit.widget.Label.init(allocator, "Logs panel");
    defer tab_c.deinit();
    var tab_view = try zit.widget.TabView.init(allocator);
    defer tab_view.deinit();
    try tab_view.addTab("Overview", &tab_a.widget);
    try tab_view.addTab("Metrics", &tab_b.widget);
    try tab_view.addTabSpec(.{ .title = "Logs", .content = &tab_c.widget, .closable = true });
    try tab_view.setActiveTab(1);
    try tab_view.widget.layout(Rect.init(2, 15, 42, 8));
    try tab_view.widget.draw(&mock.renderer);

    var tabs = [_]zit.widget.TabItem{
        .{ .title = "Edit", .closable = false },
        .{ .title = "Preview", .closable = true },
        .{ .title = "Ship", .closable = false },
    };
    var tab_bar = try zit.widget.TabBar.init(allocator);
    defer tab_bar.deinit();
    tab_bar.setTabs(&tabs);
    tab_bar.setActive(1);
    tab_bar.allow_close = true;
    try tab_bar.widget.layout(Rect.init(48, 15, 36, 1));
    try tab_bar.widget.draw(&mock.renderer);
    drawText(&mock, 48, 17, "TabBar standalone", .bright_black, Style{});

    var screen_label = try zit.widget.Label.init(allocator, "ScreenManager active screen");
    defer screen_label.deinit();
    screen_label.setAlignment(.center);
    screen_label.setColor(Color.named(.bright_white), Color.named(.black));
    var screen_manager = try zit.widget.ScreenManager.init(allocator);
    defer screen_manager.deinit();
    try screen_manager.widget.layout(Rect.init(88, 15, 28, 5));
    try screen_manager.push(.{ .widget = &screen_label.widget, .label = "coverage" });
    try screen_manager.tick(500);
    try screen_manager.widget.draw(&mock.renderer);
    drawText(&mock, 88, 21, "ScreenManager", .bright_black, Style{});

    drawHeading(&mock, 2, 25, "Panels and Overlays");

    var scroll_text = try zit.widget.Paragraph.init(allocator, "ScrollContainer keeps oversized content bounded while scrollbars expose the hidden area.");
    defer scroll_text.deinit();
    scroll_text.setWrap(false);
    var scroll = try zit.widget.ScrollContainer.init(allocator);
    defer scroll.deinit();
    scroll.setContent(&scroll_text.widget);
    scroll.setBorder(true, .rounded);
    try scroll.widget.layout(Rect.init(2, 27, 34, 7));
    try scroll.widget.draw(&mock.renderer);

    var left_pane = try zit.widget.Label.init(allocator, "Left pane");
    defer left_pane.deinit();
    left_pane.setColor(Color.named(.bright_white), Color.named(.black));
    var right_pane = try zit.widget.Label.init(allocator, "Right pane");
    defer right_pane.deinit();
    right_pane.setColor(Color.named(.bright_white), Color.named(.black));
    var split = try zit.widget.SplitPane.init(allocator);
    defer split.deinit();
    try split.setTheme(zit.widget.theme.Theme.dark());
    split.setRatio(0.45);
    split.setFirst(&left_pane.widget);
    split.setSecond(&right_pane.widget);
    try split.widget.layout(Rect.init(40, 27, 35, 6));
    try split.widget.draw(&mock.renderer);

    var ctx = try zit.widget.ContextMenu.init(allocator);
    defer ctx.deinit();
    try ctx.addItem("Open", true, null);
    try ctx.addItem("Rename", true, null);
    try ctx.addItem("Delete", false, null);
    ctx.selected = 1;
    ctx.openAt(79, 27);
    ctx.widget.rect.width = 18;
    try ctx.widget.draw(&mock.renderer);

    var toasts = try zit.widget.ToastManager.init(allocator);
    defer toasts.deinit();
    try toasts.push("Quality passed", .success, 10);
    try toasts.push("Review visuals", .info, 10);
    try toasts.widget.layout(Rect.init(99, 26, 20, 7));
    try toasts.widget.draw(&mock.renderer);

    drawHeading(&mock, 2, 36, "Specialized Widgets");

    var picker = try zit.widget.DateTimePicker.init(allocator);
    defer picker.deinit();
    picker.setDateTime(.{ .year = 2026, .month = 6, .day = 17, .hour = 9, .minute = 30 });
    picker.widget.setFocus(true);
    try picker.widget.layout(Rect.init(2, 38, 26, 3));
    try picker.widget.draw(&mock.renderer);

    var image = try zit.widget.ImageWidget.init(allocator, 8, 8);
    defer image.deinit();
    paintImage(image);
    image.setRenderMode(.braille);
    try image.widget.layout(Rect.init(32, 38, 12, 4));
    try image.widget.draw(&mock.renderer);
    drawText(&mock, 32, 43, "ImageWidget", .bright_black, Style{});

    var notes = try zit.widget.NotificationCenter.init(allocator);
    defer notes.deinit();
    try notes.push("Build", "quality ok", .success);
    try notes.push("Visual", "inspect sheet", .warning);
    try notes.widget.layout(Rect.init(48, 37, 34, 3));
    try notes.widget.draw(&mock.renderer);

    var accordion = try zit.widget.Accordion.init(allocator, &[_]zit.widget.Accordion.Section{
        .{ .title = "Stability", .body = "deterministic frames", .expanded = true },
        .{ .title = "Features", .body = "covered widgets", .expanded = false },
    });
    defer accordion.deinit();
    try accordion.widget.layout(Rect.init(86, 36, 31, 4));
    try accordion.widget.draw(&mock.renderer);

    var wizard = try zit.widget.WizardStepper.init(allocator, &[_][]const u8{ "Plan", "Build", "Test", "Ship" });
    defer wizard.deinit();
    wizard.setStep(2);
    try wizard.widget.layout(Rect.init(84, 41, 35, 2));
    try wizard.widget.draw(&mock.renderer);

    var snap = try mock.snapshot(allocator);
    defer snap.deinit(allocator);
    try snap.expectWellFormed();
    const frame = try mock.captureOutput();
    try interactive.finishFrames(init, allocator, "widget-gallery-layouts", snap.text(), frame);
}
