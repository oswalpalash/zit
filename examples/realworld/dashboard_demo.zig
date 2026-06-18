// Real-world demo: operational dashboard with charts, alerts, and service state.

const std = @import("std");
const zit = @import("zit");
const render = zit.render;
const layout = zit.layout;
const widget = zit.widget;
const interactive = @import("interactive_snapshot.zig");
const style = @import("realworld_style.zig");

fn drawKpi(
    renderer: *render.Renderer,
    rect: layout.Rect,
    palette: style.Palette,
    title: []const u8,
    value: []const u8,
    delta: []const u8,
    accent: render.Color,
) void {
    style.drawPanel(renderer, rect, palette, title, accent);
    if (rect.width < 10 or rect.height < 6) return;

    renderer.drawSmartStr(rect.x + 3, rect.y + 3, value, palette.text, palette.surface, render.Style{ .bold = true });
    renderer.drawSmartStr(rect.x + 3, rect.y + 5, delta, accent, palette.surface, render.Style{ .bold = true });
}

fn drawServiceRow(
    renderer: *render.Renderer,
    x: u16,
    y: u16,
    width: u16,
    palette: style.Palette,
    name: []const u8,
    owner: []const u8,
    latency: []const u8,
    state: []const u8,
    accent: render.Color,
    selected: bool,
) void {
    const bg = if (selected) render.Color.rgb(18, 45, 66) else palette.surface;
    renderer.fillRect(x, y, width, 1, ' ', palette.text, bg, render.Style{});
    renderer.drawSmartStr(x + 1, y, name, if (selected) palette.text else accent, bg, render.Style{ .bold = selected });
    renderer.drawSmartStr(x + 24, y, owner, palette.muted, bg, render.Style{});
    renderer.drawSmartStr(x + 46, y, latency, palette.text, bg, render.Style{ .bold = true });
    renderer.drawSmartStr(x + 62, y, state, accent, bg, render.Style{ .bold = true });
}

/// Dashboard demo rendered interactively by default and as a deterministic snapshot with --snapshot.
pub fn main(init: std.process.Init) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var mock = try zit.testing.MockTerminal.init(allocator, 100, 38);
    defer mock.deinit();

    const palette = style.monitorPalette();
    const renderer = &mock.renderer;
    renderer.back.clear();

    const content = style.drawChrome(renderer, palette, "zit operations dashboard", "deploys / q quits");

    var toolbar = try widget.Toolbar.init(allocator, &[_][]const u8{ "Overview", "Pipelines", "Incidents", "Capacity", "Settings" });
    defer toolbar.deinit();
    toolbar.setActive(0);
    try toolbar.widget.layout(layout.Rect.init(content.x, content.y, content.width, 1));
    try toolbar.widget.draw(renderer);

    const gap: u16 = 2;
    const card_w: u16 = (content.width - gap * 2) / 3;
    const card_y = content.y + 2;
    drawKpi(renderer, layout.Rect.init(content.x, card_y, card_w, 7), palette, "Requests", "14.8k/min", "+12.4% from baseline", palette.accent);
    drawKpi(renderer, layout.Rect.init(content.x + card_w + gap, card_y, card_w, 7), palette, "Error Budget", "98.73%", "steady burn 0.2x", palette.success);
    drawKpi(renderer, layout.Rect.init(content.x + (card_w + gap) * 2, card_y, content.width - (card_w + gap) * 2, 7), palette, "p95 Latency", "118ms", "+8ms canary", palette.warning);

    var rating = try widget.RatingStars.init(allocator, 5);
    defer rating.deinit();
    rating.setValue(4);
    rating.filled_color = palette.warning;
    rating.empty_color = palette.border;
    try rating.widget.layout(layout.Rect.init(content.x + card_w + gap + 3, card_y + 4, 10, 1));
    try rating.widget.draw(renderer);

    const pipeline = layout.Rect.init(content.x, card_y + 9, 60, 11);
    const alerts = layout.Rect.init(content.x + 62, card_y + 9, content.width - 62, 11);
    const services_y = card_y + 21;
    const services_h = content.y + content.height - services_y - 1;
    const services = layout.Rect.init(content.x, services_y, content.width, services_h);

    style.drawPanel(renderer, pipeline, palette, "Deployment Pipeline", palette.accent);
    var wizard = try widget.WizardStepper.init(allocator, &[_][]const u8{ "Build", "Test", "Canary", "Global", "Verify" });
    defer wizard.deinit();
    wizard.setStep(3);
    try wizard.widget.layout(layout.Rect.init(pipeline.x + 3, pipeline.y + 3, pipeline.width - 6, 2));
    try wizard.widget.draw(renderer);

    var rollout = try widget.ProgressBar.init(allocator);
    defer rollout.deinit();
    rollout.setValue(68);
    rollout.setColors(palette.text, palette.surface, palette.success, palette.surface);
    try rollout.widget.layout(layout.Rect.init(pipeline.x + 3, pipeline.y + 6, pipeline.width - 21, 1));
    try rollout.widget.draw(renderer);
    renderer.drawSmartStr(pipeline.x + pipeline.width - 16, pipeline.y + 6, "68% global", palette.success, palette.surface, render.Style{ .bold = true });
    style.drawMeter(renderer, pipeline.x + 3, pipeline.y + 8, pipeline.width - 6, "Capacity guardrail", 0.62, palette, palette.accent);

    style.drawPanel(renderer, alerts, palette, "Live Alerts", palette.warning);
    var center = try widget.NotificationCenter.init(allocator);
    defer center.deinit();
    try center.push("Deploy", "p99 +8ms", .warning);
    try center.push("Canary", "2 pods pending", .info);
    try center.push("Logs", "error rate flat", .success);
    try center.push("SLO", "burn 0.2x", .success);
    try center.widget.layout(layout.Rect.init(alerts.x + 2, alerts.y + 3, alerts.width - 4, alerts.height - 5));
    try center.widget.draw(renderer);

    renderer.drawSmartStr(alerts.x + 3, alerts.y + alerts.height - 2, "ack: 4m  owner: platform-runtime", palette.muted, palette.surface, render.Style{ .bold = true });

    style.drawPanel(renderer, services, palette, "Service Fleet", palette.success);
    renderer.fillRect(services.x + 2, services.y + 3, services.width - 4, 1, ' ', palette.accent, palette.surface_alt, render.Style{});
    renderer.drawSmartStr(services.x + 3, services.y + 3, "SERVICE", palette.accent, palette.surface_alt, render.Style{ .bold = true });
    renderer.drawSmartStr(services.x + 26, services.y + 3, "OWNER", palette.accent, palette.surface_alt, render.Style{ .bold = true });
    renderer.drawSmartStr(services.x + 48, services.y + 3, "P95", palette.accent, palette.surface_alt, render.Style{ .bold = true });
    renderer.drawSmartStr(services.x + 64, services.y + 3, "STATE", palette.accent, palette.surface_alt, render.Style{ .bold = true });

    drawServiceRow(renderer, services.x + 2, services.y + 5, services.width - 4, palette, "edge-router", "traffic", "72ms", "ok", palette.success, false);
    drawServiceRow(renderer, services.x + 2, services.y + 6, services.width - 4, palette, "checkout-api", "payments", "118ms", "canary", palette.warning, true);
    drawServiceRow(renderer, services.x + 2, services.y + 7, services.width - 4, palette, "search-index", "discovery", "93ms", "ok", palette.success, false);
    drawServiceRow(renderer, services.x + 2, services.y + 8, services.width - 4, palette, "worker-pool", "platform", "141ms", "scaling", palette.accent, false);

    const cpu_samples = [_]f32{ 32, 40, 55, 48, 62, 58, 66, 70, 63, 72, 68, 74, 69, 72 };
    var cpu_graph = try widget.Sparkline.init(allocator);
    defer cpu_graph.deinit();
    cpu_graph.fg = palette.accent;
    cpu_graph.bg = palette.surface;
    cpu_graph.setMaxSamples(cpu_samples.len);
    try cpu_graph.setValues(&cpu_samples);
    try cpu_graph.widget.layout(layout.Rect.init(services.x + services.width - 28, services.y + 5, 23, 4));
    try cpu_graph.widget.draw(renderer);
    renderer.drawSmartStr(services.x + services.width - 28, services.y + 4, "traffic trend", palette.muted, palette.surface, render.Style{ .bold = true });

    style.drawStatus(renderer, palette, "status: green | focused: checkout-api | dashboard-demo | q quit");

    var snap = try mock.snapshot(allocator);
    defer snap.deinit(allocator);
    const frame = try mock.captureOutput();
    try interactive.finishFrames(init, allocator, "dashboard-demo", snap.text(), frame);
}
