const std = @import("std");
const zit = @import("zit");
const render = zit.render;
const layout = zit.layout;
const widget = zit.widget;
const theme = zit.widget.theme;
const memory = zit.memory;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var memory_manager = try memory.MemoryManager.init(allocator, 1024 * 1024, 100);
    defer memory_manager.deinit();

    var term = try zit.terminal.init(memory_manager.getArenaAllocator());
    defer term.deinit() catch {};

    var renderer = try render.Renderer.init(memory_manager.getArenaAllocator(), term.width, term.height);
    defer renderer.deinit();

    var input_handler = zit.input.InputHandler.init(memory_manager.getArenaAllocator(), &term);

    try term.enableRawMode();
    try term.hideCursor();
    try input_handler.enableMouse();
    defer {
        input_handler.disableMouse() catch {};
        term.showCursor() catch {};
        term.disableRawMode() catch {};
    }

    try term.clear();

    var tree = try widget.TreeView.init(memory_manager.getWidgetPoolAllocator());
    defer tree.deinit();
    const root = try tree.addRoot("Systems");
    const api = try tree.addChild(root, "API");
    _ = try tree.addChild(api, "Gateway");
    _ = try tree.addChild(api, "Users");
    const data = try tree.addChild(root, "Data");
    _ = try tree.addChild(data, "Postgres");
    _ = try tree.addChild(data, "Redis");
    const ui = try tree.addChild(root, "UI");
    _ = try tree.addChild(ui, "Dashboard");
    _ = try tree.addChild(ui, "Public Site");
    tree.nodes.items[root].expanded = true;
    tree.nodes.items[api].expanded = true;
    tree.nodes.items[data].expanded = true;
    tree.nodes.items[ui].expanded = true;
    try tree.setTheme(theme.Theme.dark());

    var gauge = try widget.Gauge.init(memory_manager.getWidgetPoolAllocator());
    defer gauge.deinit();
    gauge.setRange(0, 100);
    try gauge.setTheme(theme.Theme.highContrast());
    try gauge.setLabel("Usage: 0%");

    var sparkline = try widget.Sparkline.init(memory_manager.getWidgetPoolAllocator());
    defer sparkline.deinit();
    try sparkline.setTheme(theme.Theme.dark());
    sparkline.setMaxSamples(80);

    var metrics_split = try widget.SplitPane.init(memory_manager.getWidgetPoolAllocator());
    defer metrics_split.deinit();
    metrics_split.setOrientation(.vertical);
    metrics_split.setRatio(0.35);
    metrics_split.setFirst(&gauge.widget);
    metrics_split.setSecond(&sparkline.widget);

    var main_split = try widget.SplitPane.init(memory_manager.getWidgetPoolAllocator());
    defer main_split.deinit();
    main_split.setOrientation(.horizontal);
    main_split.setRatio(0.38);
    main_split.setFirst(&tree.widget);
    main_split.setSecond(&metrics_split.widget);

    const seed: u64 = @bitCast(std.time.timestamp());
    var prng = std.Random.DefaultPrng.init(seed);
    var running = true;
    var phase: f64 = 0;
    var dark_mode = true;

    while (running) {
        renderer.back.clear();
        renderer.fillRect(0, 0, renderer.back.width, renderer.back.height, ' ', render.Color.named(render.NamedColor.white), render.Color.named(render.NamedColor.black), render.Style{});
        renderer.drawBox(0, 0, renderer.back.width, renderer.back.height, render.BorderStyle.single, render.Color.named(render.NamedColor.cyan), render.Color.named(render.NamedColor.black), render.Style{});

        const usable_height: u16 = if (renderer.back.height > 3) renderer.back.height - 2 else renderer.back.height;
        const usable_width: u16 = if (renderer.back.width > 2) renderer.back.width - 2 else renderer.back.width;
        const split_rect = layout.Rect.init(1, 1, usable_width, usable_height);
        try main_split.widget.layout(split_rect);
        sparkline.setMaxSamples(@max(8, @as(usize, @intCast(sparkline.widget.rect.width))));
        try main_split.widget.draw(&renderer);

        try renderer.render();

        phase += 0.12;
        const usage = 60.0 + 35.0 * std.math.sin(phase);
        const clamped_usage: f32 = @floatCast(std.math.clamp(usage, 0.0, 100.0));
        gauge.setValue(clamped_usage);
        var label_buf: [32]u8 = undefined;
        const label_text = std.fmt.bufPrint(&label_buf, "Usage: {d}%", .{@as(u8, @intFromFloat(clamped_usage))}) catch "Usage";
        try gauge.setLabel(label_text);

        const sample = 50.0 + 45.0 * (prng.random().float(f32) - 0.5);
        try sparkline.push(sample);

        if (try input_handler.pollEvent(60)) |event| {
            switch (event) {
                .key => |key| {
                    if (key.key == 'q') {
                        running = false;
                    } else if (key.key == 't') {
                        dark_mode = !dark_mode;
                        const next_theme = if (dark_mode) theme.Theme.dark() else theme.Theme.light();
                        try tree.setTheme(next_theme);
                        try sparkline.setTheme(next_theme);
                        try gauge.setTheme(next_theme);
                    } else {
                        _ = try main_split.widget.handleEvent(event);
                    }
                },
                .resize => |resize| {
                    try renderer.resize(resize.width, resize.height);
                },
                else => {
                    _ = try main_split.widget.handleEvent(event);
                },
            }
        }
    }

    try term.clear();
    try term.moveCursor(0, 0);
}
