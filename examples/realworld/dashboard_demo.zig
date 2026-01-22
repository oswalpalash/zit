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
    rating.filled_color = zit.render.Color.named(.bright_yellow);
    rating.empty_color = zit.render.Color.named(.bright_black);
    try rating.widget.layout(zit.layout.Rect.init(2, 2, 10, 1));
    try rating.widget.draw(&mock.renderer);
    mock.renderer.drawStr(13, 2, "service health", zit.render.Color.named(.bright_white), zit.render.Color.named(.default), zit.render.Style{});

    // CPU/memory activity sparklines.
    const cpu_samples = [_]f32{ 32, 40, 55, 48, 62, 58, 66, 70, 63, 72, 68, 74, 69, 72 };
    const mem_samples = [_]f32{ 45, 50, 56, 53, 58, 60, 62, 59, 61, 64, 60, 63, 62, 64 };

    var cpu_graph = try zit.widget.Sparkline.init(allocator);
    defer cpu_graph.deinit();
    cpu_graph.setMaxSamples(cpu_samples.len);
    try cpu_graph.setValues(&cpu_samples);
    try cpu_graph.widget.layout(zit.layout.Rect.init(45, 2, 28, 1));
    try cpu_graph.widget.draw(&mock.renderer);

    var mem_graph = try zit.widget.Sparkline.init(allocator);
    defer mem_graph.deinit();
    mem_graph.setMaxSamples(mem_samples.len);
    try mem_graph.setValues(&mem_samples);
    try mem_graph.widget.layout(zit.layout.Rect.init(45, 3, 28, 1));
    try mem_graph.widget.draw(&mock.renderer);

    mock.renderer.drawStr(40, 2, "CPU", zit.render.Color.named(.bright_white), zit.render.Color.named(.default), zit.render.Style{});
    mock.renderer.drawStr(40, 3, "MEM", zit.render.Color.named(.bright_white), zit.render.Color.named(.default), zit.render.Style{});
    mock.renderer.drawStr(74, 2, "72%", zit.render.Color.named(.bright_green), zit.render.Color.named(.default), zit.render.Style{});
    mock.renderer.drawStr(74, 3, "64%", zit.render.Color.named(.bright_cyan), zit.render.Color.named(.default), zit.render.Style{});

    // Throughput slider as a capacity dial.
    var throughput = try zit.widget.Slider.init(allocator, 0, 1000);
    defer throughput.deinit();
    throughput.setValue(620);
    throughput.show_value = true;
    throughput.step = 25;
    try throughput.widget.layout(zit.layout.Rect.init(2, 4, 30, 1));
    try throughput.widget.draw(&mock.renderer);
    mock.renderer.drawStr(34, 4, "req/s", zit.render.Color.named(.bright_black), zit.render.Color.named(.default), zit.render.Style{});

    // Release rollout progress.
    var rollout = try zit.widget.ProgressBar.init(allocator);
    defer rollout.deinit();
    rollout.setValue(68);
    rollout.setColors(
        zit.render.Color.named(.bright_white),
        zit.render.Color.named(.black),
        zit.render.Color.named(.bright_green),
        zit.render.Color.named(.black),
    );
    try rollout.widget.layout(zit.layout.Rect.init(2, 5, 30, 1));
    try rollout.widget.draw(&mock.renderer);
    mock.renderer.drawStr(34, 5, "rollout", zit.render.Color.named(.bright_black), zit.render.Color.named(.default), zit.render.Style{});

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
