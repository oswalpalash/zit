// Real-world demo: dashboard view with charts, logs, and status cards.

const std = @import("std");
const zit = @import("zit");

/// Dashboard demo that stitches together new widgets in a single frame.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var mock = try zit.testing.MockTerminal.init(allocator, 80, 22);
    defer mock.deinit();

    // Header toolbar.
    var toolbar = try zit.widget.Toolbar.init(allocator, &[_][]const u8{ "Overview", "Pipelines", "Alerts", "Settings" });
    defer toolbar.deinit();
    toolbar.setActive(0);
    try toolbar.widget.layout(zit.layout.Rect.init(0, 0, 80, 1));
    try toolbar.widget.draw(&mock.renderer);

    // Service health rating.
    var rating = try zit.widget.RatingStars.init(allocator, 5);
    defer rating.deinit();
    rating.setValue(4);
    try rating.widget.layout(zit.layout.Rect.init(2, 2, 10, 1));
    try rating.widget.draw(&mock.renderer);
    mock.renderer.drawStr(13, 2, "service health", zit.render.Color.named(.bright_white), zit.render.Color.named(.default), zit.render.Style{});

    // Throughput slider as a capacity dial.
    var throughput = try zit.widget.Slider.init(allocator, 0, 1000);
    defer throughput.deinit();
    throughput.setValue(620);
    throughput.show_value = true;
    throughput.step = 25;
    try throughput.widget.layout(zit.layout.Rect.init(2, 4, 30, 1));
    try throughput.widget.draw(&mock.renderer);
    mock.renderer.drawStr(34, 4, "req/s", zit.render.Color.named(.bright_black), zit.render.Color.named(.default), zit.render.Style{});

    // Wizard/stepper showing deployment progress.
    var wizard = try zit.widget.WizardStepper.init(allocator, &[_][]const u8{ "Build", "Test", "Deploy", "Verify" });
    defer wizard.deinit();
    wizard.setStep(2);
    try wizard.widget.layout(zit.layout.Rect.init(2, 6, 70, 2));
    try wizard.widget.draw(&mock.renderer);

    // Notification center with recent events.
    var center = try zit.widget.NotificationCenter.init(allocator);
    defer center.deinit();
    try center.push("Deploy", "p99 +8ms", .warning);
    try center.push("Canary", "2 pods pending", .info);
    try center.push("Logs", "error rate flat", .success);
    try center.widget.layout(zit.layout.Rect.init(2, 9, 50, 5));
    try center.widget.draw(&mock.renderer);

    // Pagination footer.
    var pager = try zit.widget.Pagination.init(allocator, 7);
    defer pager.deinit();
    pager.setPage(3);
    try pager.widget.layout(zit.layout.Rect.init(2, 15, 20, 1));
    try pager.widget.draw(&mock.renderer);

    var status = try zit.widget.StatusBar.init(allocator);
    defer status.deinit();
    status.setSegments("status: green", "dashboard", "shift+q quit");
    try status.widget.layout(zit.layout.Rect.init(0, 20, 80, 1));
    try status.widget.draw(&mock.renderer);

    var snap = try mock.snapshot(allocator);
    defer snap.deinit(allocator);
    std.debug.print("{s}", .{snap.text()});
}
