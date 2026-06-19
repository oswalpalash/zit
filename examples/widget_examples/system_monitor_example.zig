// Example: system-monitor style gauges, charts, and stats grid.

const std = @import("std");
const zit = @import("zit");
const render = zit.render;
const layout = zit.layout;
const widget = zit.widget;
const theme = zit.widget.theme;
const memory = zit.memory;
const style = @import("example_style.zig");
const snapshot = @import("example_snapshot.zig");

const Process = struct {
    name: []const u8,
    cpu: f32,
    mem: f32,
    state: []const u8,
};

const StatusLine = struct {
    buffer: [200]u8 = undefined,
    text: []const u8 = "q: quit | p: pause | t: theme | type to search table",
};

fn setStatus(status: *StatusLine, comptime fmt: []const u8, args: anytype) void {
    status.text = std.fmt.bufPrint(&status.buffer, fmt, args) catch status.text;
}

const ThemeOption = struct {
    name: []const u8,
    value: theme.Theme,
};

fn namedToRgb(color: render.NamedColor) render.RgbColor {
    return switch (color) {
        .black => render.RgbColor.init(0, 0, 0),
        .red => render.RgbColor.init(205, 49, 49),
        .green => render.RgbColor.init(13, 188, 121),
        .yellow => render.RgbColor.init(229, 229, 16),
        .blue => render.RgbColor.init(36, 114, 200),
        .magenta => render.RgbColor.init(188, 63, 188),
        .cyan => render.RgbColor.init(17, 168, 205),
        .white => render.RgbColor.init(229, 229, 229),
        .default => render.RgbColor.init(0, 0, 0),
        .bright_black => render.RgbColor.init(102, 102, 102),
        .bright_red => render.RgbColor.init(241, 76, 76),
        .bright_green => render.RgbColor.init(35, 209, 139),
        .bright_yellow => render.RgbColor.init(245, 245, 67),
        .bright_blue => render.RgbColor.init(59, 142, 234),
        .bright_magenta => render.RgbColor.init(214, 112, 214),
        .bright_cyan => render.RgbColor.init(41, 184, 219),
        .bright_white => render.RgbColor.init(255, 255, 255),
    };
}

fn toRgb(color: render.Color) render.RgbColor {
    return switch (color) {
        .named_color => |named| namedToRgb(named),
        .ansi_256 => |idx| render.colorToRgb(render.Color.ansi256(idx)),
        .rgb_color => |rgb| rgb,
    };
}

fn channelLinear(value: u8) f32 {
    const v = @as(f32, @floatFromInt(value)) / 255.0;
    return if (v <= 0.03928) v / 12.92 else std.math.pow(f32, (v + 0.055) / 1.055, 2.4);
}

fn relativeLuminance(color: render.Color) f32 {
    const rgb = toRgb(color);
    const r = channelLinear(rgb.r);
    const g = channelLinear(rgb.g);
    const b = channelLinear(rgb.b);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

fn contrast(a: render.Color, b: render.Color) f32 {
    const la = relativeLuminance(a);
    const lb = relativeLuminance(b);
    const light = @max(la, lb);
    const dark = @min(la, lb);
    return (light + 0.05) / (dark + 0.05);
}

fn pickAccentForeground(accent: render.Color, palette: theme.Palette) render.Color {
    const options = [_]render.Color{ palette.text, palette.background, palette.surface };
    var best = options[0];
    var best_ratio = contrast(accent, best);
    for (options[1..]) |candidate| {
        const candidate_ratio = contrast(accent, candidate);
        if (candidate_ratio > best_ratio) {
            best_ratio = candidate_ratio;
            best = candidate;
        }
    }
    return best;
}

fn jitter(random: std.Random, value: f32, min: f32, max: f32, spread: f32) f32 {
    const delta = (random.float(f32) - 0.5) * spread;
    return std.math.clamp(value + delta, min, max);
}

fn refreshTable(table: *widget.Table, procs: []const Process) !void {
    for (procs, 0..) |proc, idx| {
        var cpu_buf: [16]u8 = undefined;
        var mem_buf: [16]u8 = undefined;
        const cpu_text = std.fmt.bufPrint(&cpu_buf, "{d:.1}%", .{proc.cpu}) catch "0%";
        const mem_text = std.fmt.bufPrint(&mem_buf, "{d:.1} MB", .{proc.mem}) catch "0 MB";
        try table.setCell(idx, 1, cpu_text, null, null);
        try table.setCell(idx, 2, mem_text, null, null);
        try table.setCell(idx, 3, proc.state, null, null);
    }
}

fn renderSnapshot(init: std.process.Init, allocator: std.mem.Allocator) !void {
    var mock = try zit.testing.MockTerminal.init(allocator, 100, 35);
    defer mock.deinit();

    var cpu = try widget.Gauge.init(allocator);
    defer cpu.deinit();
    cpu.setRange(0, 100);
    cpu.setOrientation(.horizontal);
    cpu.setValue(47.8);
    try cpu.setLabel("CPU 47.8%");

    var mem = try widget.Gauge.init(allocator);
    defer mem.deinit();
    mem.setRange(0, 100);
    mem.setOrientation(.horizontal);
    mem.setValue(63.2);
    try mem.setLabel("Memory 63.2%");

    var spark = try widget.Sparkline.init(allocator);
    defer spark.deinit();
    spark.setMaxSamples(80);
    for (&[_]f32{ 24, 28, 31, 29, 42, 47, 44, 51, 49, 58, 55, 62, 59, 64, 61, 67 }) |sample| {
        try spark.push(sample);
    }

    var table = try widget.Table.init(allocator);
    defer table.deinit();
    table.widget.focused = true;
    table.setShowHeaders(true);
    table.setBorder(.none);
    table.show_grid = false;
    try table.addColumn("Process", 16, true);
    try table.addColumn("CPU", 8, true);
    try table.addColumn("Memory", 10, true);
    try table.addColumn("State", 10, true);

    const processes = [_]Process{
        .{ .name = "renderer", .cpu = 47.8, .mem = 118.0, .state = "steady" },
        .{ .name = "input-loop", .cpu = 13.4, .mem = 42.0, .state = "ready" },
        .{ .name = "layout", .cpu = 8.1, .mem = 51.0, .state = "clean" },
        .{ .name = "watcher", .cpu = 2.3, .mem = 19.0, .state = "idle" },
        .{ .name = "telemetry", .cpu = 4.5, .mem = 34.0, .state = "sample" },
    };
    for (processes) |proc| {
        try table.addRow(&.{ proc.name, "0%", "0 MB", proc.state });
    }
    table.setSelectedRow(0);
    try refreshTable(table, &processes);

    const current_theme = theme.Theme.dark();
    const palette = style.monitorPalette();
    const text = palette.text;
    const success = palette.success;
    try cpu.setTheme(current_theme);
    try mem.setTheme(current_theme);
    try spark.setTheme(current_theme);
    table.fg = text;
    table.bg = palette.surface;
    table.header_bg = palette.surface_alt;
    table.header_fg = palette.accent_text;
    table.selected_bg = render.Color.rgb(14, 42, 58);
    table.selected_fg = palette.accent_text;
    table.grid_fg = palette.border;
    table.focused_bg = palette.surface_alt;
    table.focused_fg = text;
    spark.fg = palette.accent;
    spark.bg = palette.surface;
    cpu.fill = success;
    mem.fill = palette.accent;

    const renderer = &mock.renderer;
    renderer.back.clear();
    const content = style.drawChrome(renderer, palette, "zit system monitor", "live widgets / stable frames");

    const gap: u16 = 2;
    const top_h: u16 = 12;
    const left_w: u16 = 36;
    const right_w: u16 = content.width - left_w - gap;
    const service = layout.Rect.init(content.x, content.y, left_w, top_h);
    const proc_rect = layout.Rect.init(content.x + left_w + gap, content.y, right_w, top_h);
    const latency = layout.Rect.init(content.x, content.y + top_h + gap, content.width, content.height - top_h - gap);

    style.drawPanel(renderer, service, palette, "Service Health", palette.accent);
    style.drawMeter(renderer, service.x + 3, service.y + 3, service.width - 6, "CPU 47.8%", 0.478, palette, success);
    style.drawMeter(renderer, service.x + 3, service.y + 6, service.width - 6, "Memory 63.2%", 0.632, palette, palette.accent);
    style.drawMeter(renderer, service.x + 3, service.y + 9, service.width - 6, "Network 36%", 0.36, palette, palette.accent);

    style.drawPanel(renderer, proc_rect, palette, "Process Table", palette.accent);
    try table.widget.layout(layout.Rect.init(proc_rect.x + 2, proc_rect.y + 3, proc_rect.width - 4, proc_rect.height - 4));
    table.widget.markDirty();
    try table.widget.draw(renderer);

    style.drawPanel(renderer, latency, palette, "Latency + Event Stream", palette.accent);
    renderer.drawSmartStr(latency.x + 3, latency.y + 3, "p95 frame time", palette.muted, palette.surface, render.Style{ .bold = true });
    renderer.drawSmartStr(latency.x + 3, latency.y + 4, "1.18ms", palette.text, palette.surface, render.Style{ .bold = true });
    try spark.widget.layout(layout.Rect.init(latency.x + 18, latency.y + 3, latency.width - 22, latency.height - 5));
    spark.widget.markDirty();
    try spark.widget.draw(renderer);
    renderer.drawSmartStr(latency.x + latency.width - 40, latency.y + latency.height - 2, "automatic resize + diff renderer", palette.muted, palette.surface, render.Style{ .bold = true });

    style.drawStatus(renderer, palette, "Theme: Midnight | q quit, p pause, t theme, type to search | focused: renderer");
    try snapshot.print(init, allocator, &mock);
}

pub fn main(init: std.process.Init) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    if (try snapshot.isMode(init, allocator)) {
        try renderSnapshot(init, allocator);
        return;
    }

    var memory_manager = try memory.MemoryManager.init(allocator, 1024 * 512, 128);
    defer memory_manager.deinit();

    var term = (try zit.terminal.initInteractive(memory_manager.getArenaAllocator(), "system-monitor-example")) orelse return;
    defer term.deinit() catch |err| zit.terminal.reportCleanupError("term.deinit", err);

    // Use the general allocator so per-frame renderer scratch buffers can be freed.
    var renderer = try render.Renderer.init(allocator, term.width, term.height);
    defer renderer.deinit();

    var input_handler = zit.input.InputHandler.init(allocator, &term);
    var app = zit.event.Application.init(allocator);
    defer app.deinit();
    app.bindResize(&renderer, null);
    app.bindInput(&input_handler);
    app.setInputPollTimeout(60);

    try term.enterAlternateScreen();
    defer term.exitAlternateScreen() catch |err| zit.terminal.reportCleanupError("term.exitAlternateScreen", err);

    try term.enableRawMode();
    defer term.disableRawMode() catch |err| zit.terminal.reportCleanupError("term.disableRawMode", err);

    try term.hideCursor();
    defer term.showCursor() catch |err| zit.terminal.reportCleanupError("term.showCursor", err);

    try input_handler.enableMouse();
    defer input_handler.disableMouse() catch |err| zit.terminal.reportCleanupError("input_handler.disableMouse", err);

    var cpu = try widget.Gauge.init(memory_manager.getWidgetPoolAllocator());
    defer cpu.deinit();
    cpu.setRange(0, 100);
    cpu.setOrientation(.horizontal);
    try cpu.setLabel("CPU 0%");

    var mem = try widget.Gauge.init(memory_manager.getWidgetPoolAllocator());
    defer mem.deinit();
    mem.setRange(0, 100);
    mem.setOrientation(.horizontal);
    try mem.setLabel("Memory 0%");

    var spark = try widget.Sparkline.init(memory_manager.getWidgetPoolAllocator());
    defer spark.deinit();
    spark.setMaxSamples(80);

    var table = try widget.Table.init(memory_manager.getWidgetPoolAllocator());
    defer table.deinit();
    table.widget.focused = true;
    table.setShowHeaders(true);
    table.setBorder(.none);
    table.show_grid = false;
    try table.addColumn("Process", 16, true);
    try table.addColumn("CPU", 8, true);
    try table.addColumn("Memory", 10, true);
    try table.addColumn("State", 10, true);

    var processes = [_]Process{
        .{ .name = "renderer", .cpu = 41.0, .mem = 118.0, .state = "steady" },
        .{ .name = "input-loop", .cpu = 13.0, .mem = 42.0, .state = "ready" },
        .{ .name = "layout", .cpu = 8.0, .mem = 51.0, .state = "clean" },
        .{ .name = "watcher", .cpu = 2.0, .mem = 19.0, .state = "idle" },
        .{ .name = "telemetry", .cpu = 4.5, .mem = 34.0, .state = "sample" },
    };

    for (processes) |proc| {
        try table.addRow(&.{ proc.name, "0%", "0 MB", proc.state });
    }
    table.setSelectedRow(0);

    const theme_options = [_]ThemeOption{
        .{ .name = "Midnight", .value = theme.Theme.dark() },
        .{ .name = "Dracula", .value = theme.Theme.dracula() },
        .{ .name = "Nord", .value = theme.Theme.nord() },
        .{ .name = "Gruvbox", .value = theme.Theme.gruvbox() },
        .{ .name = "High Contrast", .value = theme.Theme.highContrast() },
        .{ .name = "Light", .value = theme.Theme.light() },
    };
    var theme_idx: usize = 0;

    const seed: u64 = 0x5a17_5a11_c0de_2026;
    var prng = std.Random.DefaultPrng.init(seed);
    var running = true;
    var paused = false;
    var status = StatusLine{};
    setStatus(&status, "Theme: {s} | q quit, p pause, t theme, type to search", .{theme_options[theme_idx].name});

    while (running) {
        const active_theme = theme_options[theme_idx];
        const current_theme = active_theme.value;
        const palette = style.monitorPalette();
        const accent_fg = palette.accent_text;
        const text = palette.text;
        const success = palette.success;
        const warning = palette.warning;
        const danger = palette.danger;

        try cpu.setTheme(current_theme);
        try mem.setTheme(current_theme);
        try spark.setTheme(current_theme);
        table.fg = text;
        table.bg = palette.surface;
        table.header_bg = palette.surface_alt;
        table.header_fg = accent_fg;
        table.selected_bg = render.Color.rgb(14, 42, 58);
        table.selected_fg = accent_fg;
        table.grid_fg = palette.border;
        table.focused_bg = palette.surface_alt;
        table.focused_fg = text;
        spark.fg = palette.accent;
        spark.bg = palette.surface;

        renderer.back.clear();
        const content = style.drawChrome(&renderer, palette, "zit system monitor", "live widgets / stable frames");

        if (!paused) {
            const random = prng.random();
            for (processes, 0..) |_, idx| {
                var proc = &processes[idx];
                proc.cpu = jitter(random, proc.cpu, 0.5, 98, 6);
                proc.mem = jitter(random, proc.mem, 24, 320, 12);

                // Keep the top process a little busier to show movement.
                if (idx == 0) proc.cpu = jitter(random, proc.cpu + 4, 0.5, 99, 10);
            }

            var total_cpu: f32 = 0;
            var total_mem: f32 = 0;
            for (processes) |proc| {
                total_cpu += proc.cpu;
                total_mem += proc.mem;
            }
            const cpu_avg = total_cpu / @as(f32, @floatFromInt(processes.len));
            const mem_pct = std.math.clamp(total_mem / 500.0, 0.0, 100.0);
            cpu.setValue(cpu_avg);
            mem.setValue(mem_pct);

            var cpu_label: [32]u8 = undefined;
            var mem_label: [32]u8 = undefined;
            const cpu_text = std.fmt.bufPrint(&cpu_label, "CPU {d:.1}%", .{cpu_avg}) catch "CPU";
            const mem_text = std.fmt.bufPrint(&mem_label, "Memory {d:.1}%", .{mem_pct}) catch "Memory";
            try cpu.setLabel(cpu_text);
            try mem.setLabel(mem_text);

            const net_sample = jitter(prng.random(), 42 + prng.random().float(f32) * 20, 10, 120, 8);
            try spark.push(net_sample);

            try refreshTable(table, &processes);
        }

        // Apply contextual colors to meters.
        const cpu_fill = if (cpu.value > 85) danger else if (cpu.value > 65) warning else success;
        const mem_fill = if (mem.value > 85) danger else if (mem.value > 65) warning else palette.accent;
        cpu.fill = cpu_fill;
        mem.fill = mem_fill;
        var cpu_meter_buf: [32]u8 = undefined;
        var mem_meter_buf: [32]u8 = undefined;
        const cpu_meter_text = std.fmt.bufPrint(&cpu_meter_buf, "CPU {d:.1}%", .{cpu.value}) catch "CPU";
        const mem_meter_text = std.fmt.bufPrint(&mem_meter_buf, "Memory {d:.1}%", .{mem.value}) catch "Memory";

        if (content.width > 20 and content.height > 8) {
            const gap: u16 = 2;
            const top_h: u16 = if (content.height > 18) 12 else @max(@as(u16, 5), content.height / 2);
            const left_w: u16 = if (content.width > 70) 36 else content.width / 2;
            const right_w: u16 = if (content.width > left_w + gap) content.width - left_w - gap else 0;
            const service = layout.Rect.init(content.x, content.y, left_w, top_h);
            const proc_rect = layout.Rect.init(content.x + left_w + gap, content.y, right_w, top_h);
            const latency_h: u16 = if (content.height > top_h + gap) content.height - top_h - gap else 0;
            const latency = layout.Rect.init(content.x, content.y + top_h + gap, content.width, latency_h);

            style.drawPanel(&renderer, service, palette, "Service Health", palette.accent);
            if (service.width > 8 and service.height > 8) {
                const meter_w = service.width - 6;
                style.drawMeter(&renderer, service.x + 3, service.y + 3, meter_w, cpu_meter_text, cpu.value / 100.0, palette, cpu_fill);
                style.drawMeter(&renderer, service.x + 3, service.y + 6, meter_w, mem_meter_text, mem.value / 100.0, palette, mem_fill);
                style.drawMeter(&renderer, service.x + 3, service.y + 9, meter_w, "Network 36%", 0.36, palette, palette.accent);
            }

            if (proc_rect.width > 8 and proc_rect.height > 5) {
                style.drawPanel(&renderer, proc_rect, palette, "Process Table", palette.accent);
                try table.widget.layout(layout.Rect.init(proc_rect.x + 2, proc_rect.y + 3, proc_rect.width - 4, proc_rect.height - 4));
                table.widget.markDirty();
                try table.widget.draw(&renderer);
            }

            if (latency.width > 8 and latency.height > 5) {
                style.drawPanel(&renderer, latency, palette, "Latency + Event Stream", palette.accent);
                renderer.drawSmartStr(latency.x + 3, latency.y + 3, "p95 frame time", palette.muted, palette.surface, render.Style{ .bold = true });
                renderer.drawSmartStr(latency.x + 3, latency.y + 4, "1.18ms", palette.text, palette.surface, render.Style{ .bold = true });
                try spark.widget.layout(layout.Rect.init(latency.x + 18, latency.y + 3, latency.width - 22, latency.height - 5));
                spark.widget.markDirty();
                try spark.widget.draw(&renderer);
                if (latency.width > 42) {
                    renderer.drawSmartStr(latency.x + latency.width - 40, latency.y + latency.height - 2, "automatic resize + diff renderer", palette.muted, palette.surface, render.Style{ .bold = true });
                }
            }
        }

        const selected = if (table.selected_row) |idx| processes[idx].name else "(none)";
        var status_buf: [220]u8 = undefined;
        const text_line = std.fmt.bufPrint(&status_buf, "{s} | theme: {s} | focused: {s}", .{ status.text, active_theme.name, selected }) catch status.text;
        style.drawStatus(&renderer, palette, text_line);

        try renderer.render();

        if (try app.pollInputOnce()) |event| {
            switch (event) {
                .key => |key| {
                    if (key.key == 'q') {
                        running = false;
                    } else if (key.key == 'p') {
                        paused = !paused;
                        if (paused) {
                            setStatus(&status, "Paused updates", .{});
                        } else {
                            setStatus(&status, "Resumed updates", .{});
                        }
                    } else if (key.key == 't') {
                        theme_idx = (theme_idx + 1) % theme_options.len;
                        setStatus(&status, "Theme: {s}", .{theme_options[theme_idx].name});
                    } else {
                        _ = try table.widget.handleEvent(event);
                    }
                },
                .mouse => {
                    _ = try table.widget.handleEvent(event);
                },
                .resize => {},
                else => {},
            }
        }
    }

    try term.clear();
    try term.moveCursor(0, 0);
}
