// Real-world demo: deterministic extended widget gallery for visual regression review.

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

/// Render advanced and composition-heavy widgets for an interactive terminal or snapshot capture.
pub fn main(init: std.process.Init) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var mock = try zit.testing.MockTerminal.init(allocator, 120, 50);
    defer mock.deinit();

    drawHeading(&mock, 2, 0, "Zit extended widget gallery");
    drawText(&mock, 31, 0, "repeat-captured visual regression target", .bright_black, Style{});

    var menu = try zit.widget.MenuBar.init(allocator);
    defer menu.deinit();
    try menu.addItem("File", null);
    try menu.addItem("View", null);
    try menu.addItem("Tools", null);
    try menu.addItem("Help", null);
    menu.setActive(2);
    try menu.widget.layout(Rect.init(0, 2, 120, 1));
    try menu.widget.draw(&mock.renderer);

    drawHeading(&mock, 2, 4, "Text Entry");

    var input_field = try zit.widget.InputField.init(allocator, 64);
    defer input_field.deinit();
    try input_field.setPlaceholder("Search commands");
    try input_field.setText("status --watch");
    input_field.setBorder(.rounded);
    input_field.widget.setFocus(true);
    try input_field.widget.layout(Rect.init(2, 6, 28, 3));
    try input_field.widget.draw(&mock.renderer);

    var autocomplete = try zit.widget.AutocompleteInput.init(allocator, 32);
    defer autocomplete.deinit();
    try autocomplete.input_field.setText("zi");
    try autocomplete.setSuggestions(&[_][]const u8{ "zig build test", "zig build quality", "zls check", "zit gallery" });
    autocomplete.widget.setFocus(true);
    try autocomplete.widget.layout(Rect.init(2, 10, 28, 5));
    try autocomplete.widget.draw(&mock.renderer);

    var text_area = try zit.widget.TextArea.init(allocator, 256);
    defer text_area.deinit();
    try text_area.setText(
        \\Release notes
        \\- quality gate passed
        \\- visual repeat stable
    );
    text_area.setBorder(.rounded);
    try text_area.widget.layout(Rect.init(2, 16, 36, 6));
    try text_area.widget.draw(&mock.renderer);

    drawHeading(&mock, 42, 4, "Structured Text");

    var markdown = try zit.widget.Markdown.init(allocator,
        \\# Stability gate
        \\- deterministic frames
        \\- **clear** widget states
        \\> inspect contact sheet
    );
    defer markdown.deinit();
    try markdown.widget.layout(Rect.init(42, 6, 35, 6));
    try markdown.widget.draw(&mock.renderer);

    var rich = try zit.widget.RichText.init(allocator);
    defer rich.deinit();
    rich.setBorder(.rounded);
    try rich.addSpan("Rich ", Color.named(.bright_white), Color.named(.default), Style{ .bold = true });
    try rich.addSpan("text spans\n", Color.named(.cyan), Color.named(.default), Style{});
    try rich.addSpan("wrap across stable boxes", Color.named(.yellow), Color.named(.default), Style{ .italic = true });
    try rich.widget.layout(Rect.init(80, 6, 34, 5));
    try rich.widget.draw(&mock.renderer);

    var syntax = try zit.widget.SyntaxHighlighter.init(allocator);
    defer syntax.deinit();
    try syntax.setCode(
        \\const ok = true;
        \\// renderer snapshot
        \\try gate.run(4);
    );
    syntax.setLanguage(.zig);
    try syntax.widget.layout(Rect.init(42, 13, 34, 6));
    try syntax.widget.draw(&mock.renderer);

    var paragraph = try zit.widget.Paragraph.init(allocator, "A block can own layout around a child while the child keeps its own rendering contract.");
    defer paragraph.deinit();
    paragraph.setWrap(true);
    paragraph.setPadding(.{ .left = 1, .right = 1, .top = 0, .bottom = 0 });

    var block = try zit.widget.Block.init(allocator);
    defer block.deinit();
    try block.setTitle("Block + paragraph");
    block.setBorder(.rounded);
    block.setChild(&paragraph.widget);
    try block.widget.layout(Rect.init(80, 12, 34, 7));
    try block.widget.draw(&mock.renderer);

    drawHeading(&mock, 2, 24, "Data Views");

    var tree = try zit.widget.TreeView.init(allocator);
    defer tree.deinit();
    const root = try tree.addRoot("src");
    const widgets = try tree.addChild(root, "widget");
    _ = try tree.addChild(widgets, "rendering.zig");
    _ = try tree.addChild(widgets, "layout.zig");
    _ = try tree.addChild(root, "testing");
    tree.nodes.items[root].expanded = true;
    tree.nodes.items[widgets].expanded = true;
    tree.visible_dirty = true;
    tree.selected = 2;
    try tree.widget.layout(Rect.init(2, 26, 25, 7));
    try tree.widget.draw(&mock.renderer);

    var dropdown = try zit.widget.DropdownMenu.init(allocator);
    defer dropdown.deinit();
    try dropdown.setLabel("Theme");
    try dropdown.addItem("Dark", true, null);
    try dropdown.addItem("Light", true, null);
    try dropdown.addItem("High Contrast", true, null);
    dropdown.setSelectedIndex(2);
    dropdown.open();
    try dropdown.widget.layout(Rect.init(30, 26, 22, 5));
    try dropdown.widget.draw(&mock.renderer);

    var command_palette = try zit.widget.CommandPalette.init(allocator, &[_][]const u8{
        "Open Dashboard",
        "Run Quality Gate",
        "Capture Visuals",
        "Publish Release",
    });
    defer command_palette.deinit();
    command_palette.setQuery("> quality");
    command_palette.selected = 1;
    try command_palette.widget.layout(Rect.init(55, 22, 31, 8));
    try command_palette.widget.draw(&mock.renderer);

    var popup = try zit.widget.Popup.init(allocator, "Frame stable");
    defer popup.deinit();
    popup.width = 22;
    popup.height = 5;
    try popup.widget.layout(Rect.init(88, 22, 28, 8));
    try popup.widget.draw(&mock.renderer);

    drawHeading(&mock, 2, 34, "Telemetry");

    var chart = try zit.widget.Chart.init(allocator);
    defer chart.deinit();
    chart.setType(.bar);
    chart.setPadding(1);
    try chart.setAxisLabels("runs", "q");
    try chart.addSeries("pass", &[_]f32{ 2, 4, 6, 8, 7 }, Color.named(.green), null);
    try chart.addSeries("warn", &[_]f32{ 1, 1, 2, 1, 1 }, Color.named(.yellow), null);
    try chart.widget.layout(Rect.init(2, 35, 34, 7));
    try chart.widget.draw(&mock.renderer);

    var spark = try zit.widget.Sparkline.init(allocator);
    defer spark.deinit();
    try spark.setValues(&[_]f32{ 0.1, 0.4, 0.3, 0.9, 0.7, 1.0, 0.6, 0.8 });
    try spark.widget.layout(Rect.init(39, 36, 22, 1));
    try spark.widget.draw(&mock.renderer);
    drawText(&mock, 63, 36, "latency trend", .bright_black, Style{});

    var log = try zit.widget.LogView.init(allocator);
    defer log.deinit();
    try log.append(.info, "started repeat capture");
    try log.append(.debug, "render hash stable");
    try log.append(.warn, "manual review required");
    try log.append(.err, "sample failure state");
    try log.widget.layout(Rect.init(39, 38, 42, 4));
    try log.widget.draw(&mock.renderer);

    var battery = try zit.widget.BatteryIndicator.init(allocator);
    defer battery.deinit();
    battery.setLevel(0.72);
    battery.setCharging(true);
    try battery.widget.layout(Rect.init(84, 33, 14, 4));
    try battery.widget.draw(&mock.renderer);

    var signal = try zit.widget.SignalStrength.init(allocator);
    defer signal.deinit();
    signal.setStrength(0.75);
    try signal.widget.layout(Rect.init(100, 33, 12, 4));
    try signal.widget.draw(&mock.renderer);

    var resource = try zit.widget.ResourceMeter.init(allocator);
    defer resource.deinit();
    try resource.setLabel("CPU");
    resource.setValue(0.68);
    try resource.widget.layout(Rect.init(84, 38, 28, 2));
    try resource.widget.draw(&mock.renderer);

    var traffic = try zit.widget.TrafficLight.init(allocator);
    defer traffic.deinit();
    traffic.setState(.yellow);
    try traffic.widget.layout(Rect.init(114, 33, 6, 4));
    try traffic.widget.draw(&mock.renderer);

    var vertical_scroll = try zit.widget.Scrollbar.init(allocator, .vertical);
    defer vertical_scroll.deinit();
    vertical_scroll.setValue(0.45);
    vertical_scroll.setThumbRatio(0.35);
    try vertical_scroll.widget.layout(Rect.init(118, 22, 1, 10));
    try vertical_scroll.widget.draw(&mock.renderer);

    var horizontal_scroll = try zit.widget.Scrollbar.init(allocator, .horizontal);
    defer horizontal_scroll.deinit();
    horizontal_scroll.setValue(0.6);
    horizontal_scroll.setThumbRatio(0.25);
    try horizontal_scroll.widget.layout(Rect.init(84, 41, 28, 1));
    try horizontal_scroll.widget.draw(&mock.renderer);

    drawHeading(&mock, 2, 43, "Drawing Primitives");

    var canvas = try zit.widget.Canvas.init(allocator, 21, 5);
    defer canvas.deinit();
    canvas.drawRect(0, 0, 21, 5, '#', Color.named(.cyan), Color.named(.black), Style{});
    canvas.drawLine(1, 3, 19, 1, '*', Color.named(.green), Color.named(.black), Style{ .bold = true });
    canvas.fillRect(3, 2, 4, 1, '=', Color.named(.yellow), Color.named(.black), Style{});
    try canvas.widget.layout(Rect.init(2, 44, 21, 5));
    try canvas.widget.draw(&mock.renderer);

    var palette = [_]Color{
        Color.named(.red),
        Color.named(.green),
        Color.named(.blue),
        Color.named(.yellow),
        Color.named(.magenta),
        Color.named(.cyan),
    };
    var picker = try zit.widget.ColorPicker.init(allocator, &palette);
    defer picker.deinit();
    picker.setColumns(3);
    picker.selectIndex(4);
    try picker.widget.layout(Rect.init(26, 44, 18, 6));
    try picker.widget.draw(&mock.renderer);

    var snap = try mock.snapshot(allocator);
    defer snap.deinit(allocator);
    try snap.expectWellFormed();
    const frame = try mock.captureOutput();
    try interactive.finishFrames(init, allocator, "widget-gallery-extended", snap.text(), frame);
}
