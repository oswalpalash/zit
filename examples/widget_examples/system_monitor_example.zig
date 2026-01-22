// Example: system-monitor style gauges, charts, and stats grid.

const std = @import("std");
const zit = @import("zit");
const render = zit.render;
const layout = zit.layout;
const widget = zit.widget;
const theme = zit.widget.theme;
const memory = zit.memory;

const Process = struct {
    name: []const u8,
    cpu: f32,
    mem: f32,
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
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var memory_manager = try memory.MemoryManager.init(allocator, 1024 * 512, 128);
    defer memory_manager.deinit();

    var term = try zit.terminal.init(memory_manager.getArenaAllocator());
    defer term.deinit() catch {};

    // Use the general allocator so per-frame renderer scratch buffers can be freed.
    var renderer = try render.Renderer.init(allocator, term.width, term.height);
    defer renderer.deinit();

    var input_handler = zit.input.InputHandler.init(allocator, &term);

    try term.enterAlternateScreen();
    defer term.exitAlternateScreen() catch {};

    try term.enableRawMode();
    defer term.disableRawMode() catch {};

    try term.hideCursor();
    defer term.showCursor() catch {};

    try input_handler.enableMouse();
    defer input_handler.disableMouse() catch {};

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
    table.setBorder(.single);
    table.show_grid = false;
    try table.addColumn("Process", 16, true);
    try table.addColumn("CPU", 10, true);
    try table.addColumn("Memory", 12, true);

    var processes = [_]Process{
        .{ .name = "zit-demo", .cpu = 8.0, .mem = 120.0 },
        .{ .name = "renderer", .cpu = 14.0, .mem = 96.0 },
        .{ .name = "metricsd", .cpu = 6.0, .mem = 80.0 },
        .{ .name = "net-tap", .cpu = 4.0, .mem = 64.0 },
        .{ .name = "backup", .cpu = 3.5, .mem = 52.0 },
    };

    for (processes) |proc| {
        try table.addRow(&.{ proc.name, "0%", "0 MB" });
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

    const seed: u64 = @bitCast(std.time.timestamp());
    var prng = std.Random.DefaultPrng.init(seed);
    var running = true;
    var paused = false;
    var status = StatusLine{};
    setStatus(&status, "Theme: {s} | q quit, p pause, t theme, type to search", .{theme_options[theme_idx].name});

    while (running) {
        const active_theme = theme_options[theme_idx];
        const current_theme = active_theme.value;
        const bg = current_theme.color(.background);
        const surface = current_theme.color(.surface);
        const accent = current_theme.color(.accent);
        const accent_fg = pickAccentForeground(accent, current_theme.palette);
        const text = current_theme.color(.text);
        const muted = current_theme.color(.muted);
        const border = current_theme.color(.border);
        const success = current_theme.color(.success);
        const warning = current_theme.color(.warning);
        const danger = current_theme.color(.danger);

        try cpu.setTheme(current_theme);
        try mem.setTheme(current_theme);
        try spark.setTheme(current_theme);
        table.fg = text;
        table.bg = surface;
        table.header_bg = theme.adjust(accent, -8);
        table.header_fg = accent_fg;
        table.selected_bg = accent;
        table.selected_fg = accent_fg;
        table.grid_fg = border;
        table.focused_bg = theme.adjust(surface, 6);
        table.focused_fg = text;

        renderer.back.clear();
        renderer.fillRect(0, 0, renderer.back.width, renderer.back.height, ' ', muted, bg, render.Style{});
        renderer.drawBox(0, 0, renderer.back.width, renderer.back.height, render.BorderStyle.single, border, bg, render.Style{});

        if (renderer.back.width > 2 and renderer.back.height > 2) {
            const header_width: u16 = renderer.back.width - 2;
            renderer.fillRect(1, 1, header_width, 1, ' ', accent_fg, accent, render.Style{});
            var header_buf: [160]u8 = undefined;
            const header_text = std.fmt.bufPrint(&header_buf, "System monitor - {s}", .{active_theme.name}) catch "System monitor";
            renderer.drawSmartStr(2, 1, header_text, accent_fg, accent, render.Style{ .bold = true });
        }

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
        const mem_fill = if (mem.value > 85) danger else if (mem.value > 65) warning else accent;
        cpu.fill = cpu_fill;
        mem.fill = mem_fill;

        const content_top: u16 = 3;
        if (renderer.back.width > 6 and renderer.back.height > content_top + 2) {
            const inner_height = renderer.back.height - content_top - 2;
            const inner = layout.Rect.init(2, content_top, renderer.back.width - 4, inner_height);
            const left_width: u16 = inner.width / 2;
            const left = layout.Rect.init(inner.x, inner.y, left_width, inner.height);
            const right = layout.Rect.init(inner.x + left_width + 1, inner.y, inner.width - left_width - 1, inner.height);

            renderer.fillRect(left.x, left.y, left.width, left.height, ' ', muted, surface, render.Style{});
            renderer.fillRect(right.x, right.y, right.width, right.height, ' ', muted, surface, render.Style{});

            const left_pad: u16 = 1;
            if (left.width > left_pad * 2 and left.height > 3) {
                renderer.drawSmartStr(left.x + left_pad, left.y, "CPU / Memory", accent, surface, render.Style{ .bold = true });

                const content_width = left.width - left_pad * 2;
                var lane_y = left.y + left_pad + 1;
                const lane_end = left.y + left.height;
                const available_after_label = if (lane_end > lane_y) lane_end - lane_y else 0;

                const cpu_h: u16 = if (available_after_label > 8) 5 else if (available_after_label > 4) 4 else available_after_label;
                if (cpu_h > 0) {
                    try cpu.widget.layout(layout.Rect.init(left.x + left_pad, lane_y, content_width, cpu_h));
                    try cpu.widget.draw(&renderer);
                }

                lane_y = lane_y + cpu_h + 1;
                const remaining_after_cpu = if (lane_end > lane_y) lane_end - lane_y else 0;
                const mem_h: u16 = if (remaining_after_cpu > 7) 4 else remaining_after_cpu;
                if (mem_h > 0) {
                    try mem.widget.layout(layout.Rect.init(left.x + left_pad, lane_y, content_width, mem_h));
                    try mem.widget.draw(&renderer);
                }

                lane_y = lane_y + mem_h + 1;
                const remaining = if (lane_end > lane_y) lane_end - lane_y else 0;
                if (remaining > 1) {
                    renderer.drawSmartStr(left.x + left_pad, lane_y - 1, "Network throughput", muted, surface, render.Style{});
                    try spark.widget.layout(layout.Rect.init(left.x + left_pad, lane_y, content_width, remaining - 1));
                    try spark.widget.draw(&renderer);
                }
            }

            if (right.width > 2 and right.height > 2) {
                renderer.drawSmartStr(right.x + 1, right.y, "Processes", accent, surface, render.Style{ .bold = true });
                const table_height = if (right.height > 1) right.height - 1 else 0;
                if (table_height > 0) {
                    try table.widget.layout(layout.Rect.init(right.x, right.y + 1, right.width, table_height));
                    try table.widget.draw(&renderer);
                }
            }
        }

        if (renderer.back.height > 0) {
            const status_y: u16 = renderer.back.height - 1;
            renderer.fillRect(0, status_y, renderer.back.width, 1, ' ', accent, surface, render.Style{});
            const selected = if (table.selected_row) |idx|
                processes[idx].name
            else
                "(none)";
            var status_buf: [220]u8 = undefined;
            const text_line = std.fmt.bufPrint(&status_buf, "{s} | theme: {s} | focused: {s}", .{
                status.text,
                active_theme.name,
                selected,
            }) catch status.text;
            renderer.drawSmartStr(1, status_y, text_line, accent, surface, render.Style{ .bold = true });
        }

        try renderer.render();

        if (try input_handler.pollEvent(60)) |event| {
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
                .resize => |size| {
                    try renderer.resize(size.width, size.height);
                },
                else => {},
            }
        }
    }

    try term.clear();
    try term.moveCursor(0, 0);
}
