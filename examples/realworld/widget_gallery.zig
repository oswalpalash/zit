// Real-world demo: interactive widget gallery with deterministic snapshot mode.

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

/// Render a broad widget sample for an interactive terminal or snapshot capture.
pub fn main(init: std.process.Init) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var mock = try zit.testing.MockTerminal.init(allocator, 100, 34);
    defer mock.deinit();

    drawHeading(&mock, 2, 0, "Zit widget gallery");
    drawText(&mock, 22, 0, "interactive + snapshot target", .bright_black, Style{});

    var toolbar = try zit.widget.Toolbar.init(allocator, &[_][]const u8{ "Browse", "Edit", "Preview", "Ship" });
    defer toolbar.deinit();
    toolbar.setActive(2);
    try toolbar.widget.layout(Rect.init(0, 2, 100, 1));
    try toolbar.widget.draw(&mock.renderer);

    drawHeading(&mock, 2, 4, "Controls");

    var label = try zit.widget.Label.init(allocator, "Stable primitives render.");
    defer label.deinit();
    try label.widget.layout(Rect.init(2, 6, 30, 2));
    try label.widget.draw(&mock.renderer);

    var button = try zit.widget.Button.init(allocator, "Deploy");
    defer button.deinit();
    button.setBorder(.rounded);
    button.widget.focused = true;
    try button.widget.layout(Rect.init(2, 9, 16, 3));
    try button.widget.draw(&mock.renderer);

    var checkbox_enabled = try zit.widget.Checkbox.init(allocator, "Persist layout");
    defer checkbox_enabled.deinit();
    checkbox_enabled.setChecked(true);
    try checkbox_enabled.widget.layout(Rect.init(3, 13, 24, 1));
    try checkbox_enabled.widget.draw(&mock.renderer);

    var checkbox_disabled = try zit.widget.Checkbox.init(allocator, "Safe mode");
    defer checkbox_disabled.deinit();
    checkbox_disabled.widget.enabled = false;
    try checkbox_disabled.widget.layout(Rect.init(3, 15, 22, 1));
    try checkbox_disabled.widget.draw(&mock.renderer);

    var toggle = try zit.widget.ToggleSwitch.init(allocator, "Autosave");
    defer toggle.deinit();
    toggle.set(true);
    try toggle.widget.layout(Rect.init(2, 17, 26, 1));
    try toggle.widget.draw(&mock.renderer);

    var radio = try zit.widget.RadioGroup.init(allocator, &[_][]const u8{ "Efficiency", "Reliability", "Stability" });
    defer radio.deinit();
    radio.setSelected(2);
    try radio.widget.layout(Rect.init(2, 20, 26, 3));
    try radio.widget.draw(&mock.renderer);

    drawHeading(&mock, 36, 4, "Meters");

    var progress = try zit.widget.ProgressBar.init(allocator);
    defer progress.deinit();
    progress.setProgress(68);
    try progress.widget.layout(Rect.init(36, 6, 30, 1));
    try progress.widget.draw(&mock.renderer);
    drawText(&mock, 68, 6, "build", .bright_black, Style{});

    var gauge = try zit.widget.Gauge.init(allocator);
    defer gauge.deinit();
    gauge.setRange(0, 100);
    gauge.setValue(74);
    try gauge.setLabel("CPU 74%");
    gauge.border = .rounded;
    try gauge.widget.layout(Rect.init(36, 8, 30, 5));
    try gauge.widget.draw(&mock.renderer);

    var slider = try zit.widget.Slider.init(allocator, 0, 100);
    defer slider.deinit();
    slider.setValue(42);
    slider.show_value = true;
    try slider.widget.layout(Rect.init(36, 15, 30, 1));
    try slider.widget.draw(&mock.renderer);
    drawText(&mock, 68, 15, "latency budget", .bright_black, Style{});

    var rating = try zit.widget.RatingStars.init(allocator, 5);
    defer rating.deinit();
    rating.setValue(4);
    try rating.widget.layout(Rect.init(36, 18, 8, 1));
    try rating.widget.draw(&mock.renderer);
    drawText(&mock, 46, 18, "release confidence", .bright_black, Style{});

    var breadcrumbs = try zit.widget.Breadcrumbs.init(allocator, &[_][]const u8{ "workspace", "examples", "widgets", "gallery" });
    defer breadcrumbs.deinit();
    try breadcrumbs.widget.layout(Rect.init(36, 21, 34, 1));
    try breadcrumbs.widget.draw(&mock.renderer);

    var pager = try zit.widget.Pagination.init(allocator, 7);
    defer pager.deinit();
    pager.setPage(4);
    try pager.widget.layout(Rect.init(36, 23, 22, 1));
    try pager.widget.draw(&mock.renderer);

    drawHeading(&mock, 2, 25, "Selection");

    var list = try zit.widget.List.init(allocator);
    defer list.deinit();
    list.border = .rounded;
    try list.addItem("renderer");
    try list.addItem("layout");
    try list.addItem("input");
    try list.addItem("widgets");
    list.setSelectedIndex(1);
    try list.widget.layout(Rect.init(2, 27, 24, 6));
    try list.widget.draw(&mock.renderer);

    var table = try zit.widget.Table.init(allocator);
    defer table.deinit();
    table.border = .rounded;
    try table.addColumn("Widget", 12, true);
    try table.addColumn("State", 10, true);
    try table.addColumn("Gate", 10, true);
    try table.addRow(&[_][]const u8{ "Table", "fixed", "snap" });
    try table.addRow(&[_][]const u8{ "Modal", "fixed", "unit" });
    try table.addRow(&[_][]const u8{ "Gauge", "legible", "visual" });
    table.setSelectedRow(1);
    try table.widget.layout(Rect.init(30, 25, 42, 8));
    try table.widget.draw(&mock.renderer);

    var modal_text = try zit.widget.Label.init(allocator, "Checks catch clipping.");
    defer modal_text.deinit();

    var modal = try zit.widget.Modal.init(allocator);
    defer modal.deinit();
    try modal.setTitle("Review Gate");
    modal.width = 24;
    modal.height = 7;
    modal.setContent(&modal_text.widget);
    try modal.widget.layout(Rect.init(72, 5, 26, 12));
    try modal.widget.draw(&mock.renderer);

    var status = try zit.widget.StatusBar.init(allocator);
    defer status.deinit();
    status.setSegments("quality: visual", "widgets", "stable");
    try status.widget.layout(Rect.init(0, 33, 100, 1));
    try status.widget.draw(&mock.renderer);

    var snap = try mock.snapshot(allocator);
    defer snap.deinit(allocator);
    try interactive.finish(init, allocator, "widget-gallery", snap.text());
}
