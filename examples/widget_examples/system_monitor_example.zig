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
    text: []const u8 = "q quits, p pauses updates, t toggles theme, type to jump rows",
};

fn setStatus(status: *StatusLine, fmt: []const u8, args: anytype) void {
    status.text = std.fmt.bufPrint(&status.buffer, fmt, args) catch status.text;
}

fn jitter(random: std.rand.Random, value: f32, min: f32, max: f32, spread: f32) f32 {
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

    var renderer = try render.Renderer.init(memory_manager.getArenaAllocator(), term.width, term.height);
    defer renderer.deinit();

    var input_handler = zit.input.InputHandler.init(memory_manager.getArenaAllocator(), &term);
    try input_handler.enableMouse();

    try term.enableRawMode();
    try term.hideCursor();
    defer {
        input_handler.disableMouse() catch {};
        term.showCursor() catch {};
        term.disableRawMode() catch {};
    }

    var cpu = try widget.Gauge.init(memory_manager.getWidgetPoolAllocator());
    defer cpu.deinit();
    cpu.setRange(0, 100);
    cpu.setOrientation(.horizontal);
    try cpu.setLabel("CPU 0%");

    var mem = try widget.Gauge.init(memory_manager.getWidgetPoolAllocator());
    defer mem.deinit();
    mem.setRange(0, 100);
    mem.setOrientation(.horizontal);
    mem.fill = render.Color.named(render.NamedColor.magenta);
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

    var themes = [_]theme.Theme{
        theme.Theme.dark(),
        theme.Theme.highContrast(),
    };
    var theme_idx: usize = 0;

    const seed: u64 = @bitCast(std.time.timestamp());
    var prng = std.Random.DefaultPrng.init(seed);
    var running = true;
    var paused = false;
    var status = StatusLine{};

    while (running) {
        const palette = themes[theme_idx];
        const bg = palette.color(.background);
        const surface = palette.color(.surface);
        const accent = palette.color(.accent);
        const text = palette.color(.text);

        cpu.setTheme(palette);
        mem.setTheme(palette);
        spark.setTheme(palette);
        table.fg = text;
        table.bg = surface;
        table.header_bg = accent;
        table.header_fg = palette.color(.background);
        table.selected_bg = accent;
        table.selected_fg = palette.color(.background);

        renderer.back.clear();
        renderer.fillRect(0, 0, renderer.back.width, renderer.back.height, ' ', text, bg, render.Style{});
        renderer.drawBox(0, 0, renderer.back.width, renderer.back.height, render.BorderStyle.single, accent, bg, render.Style{});

        renderer.drawSmartStr(2, 0, "System monitor demo (t: theme, p: pause, type to search table)", text, bg, render.Style{});

        if (!paused) {
            var random = prng.random();
            for (processes, 0..) |*proc, idx| {
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

        if (renderer.back.width > 6 and renderer.back.height > 6) {
            const inner = layout.Rect.init(2, 2, renderer.back.width - 4, renderer.back.height - 4);
            const left_width: u16 = inner.width / 2;
            const left = layout.Rect.init(inner.x, inner.y, left_width, inner.height);
            const right = layout.Rect.init(inner.x + left_width + 1, inner.y, inner.width - left_width - 1, inner.height);

            // Stack gauges and sparkline on the left.
            const lane_end = left.y + left.height;
            const cpu_h: u16 = if (left.height > 2) 5 else left.height;
            try cpu.widget.layout(layout.Rect.init(left.x, left.y, left.width, cpu_h));
            try cpu.widget.draw(&renderer);

            var lane_y = left.y + cpu_h + 1;
            const remaining_after_cpu = if (lane_end > lane_y) lane_end - lane_y else 0;
            const mem_h: u16 = if (remaining_after_cpu > 7) 5 else if (remaining_after_cpu > 2) remaining_after_cpu - 2 else remaining_after_cpu;
            if (mem_h > 0) {
                try mem.widget.layout(layout.Rect.init(left.x, lane_y, left.width, mem_h));
                try mem.widget.draw(&renderer);
            }

            lane_y = lane_y + mem_h + 1;
            const remaining = if (lane_end > lane_y) lane_end - lane_y else 0;
            if (remaining > 0) {
                try spark.widget.layout(layout.Rect.init(left.x, lane_y, left.width, remaining));
                try spark.widget.draw(&renderer);
            }

            // Processes table on the right.
            try table.widget.layout(right);
            try table.widget.draw(&renderer);
        }

        if (renderer.back.height > 0) {
            const status_y: u16 = renderer.back.height - 1;
            renderer.fillRect(0, status_y, renderer.back.width, 1, ' ', bg, accent, render.Style{});
            const selected = if (table.selected_row) |idx|
                processes[idx].name
            else
                "(none)";
            var status_buf: [220]u8 = undefined;
            const text_line = std.fmt.bufPrint(&status_buf, "{s} | focused: {s}", .{
                status.text,
                selected,
            }) catch status.text;
            renderer.drawSmartStr(1, status_y, text_line, palette.color(.background), accent, render.Style{});
        }

        try renderer.render();

        if (try input_handler.pollEvent(60)) |event| {
            switch (event) {
                .key => |key| {
                    if (key.key == 'q') {
                        running = false;
                    } else if (key.key == 'p') {
                        paused = !paused;
                        setStatus(&status, if (paused) "Paused updates" else "Resumed updates", .{});
                    } else if (key.key == 't') {
                        theme_idx = (theme_idx + 1) % themes.len;
                        setStatus(&status, "Theme: {s}", .{if (theme_idx == 0) "dark" else "contrast"});
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
