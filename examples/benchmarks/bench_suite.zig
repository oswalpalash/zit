// Benchmark suite entrypoint for Zit render/layout microbenchmarks.

const std = @import("std");
const zit = @import("zit");

const render = zit.render;
const widget = zit.widget;
const layout = zit.layout;
const input = zit.input;

const PerformanceBudget = struct {
    render_avg_ns: u64 = 50_000_000, // 20 fps floor in Debug builds.
    table_scroll_avg_ns: u64 = 20_000_000,
    input_decode_avg_ns: u64 = 1_000_000,
    unicode_measure_avg_ns: u64 = 100_000,
    interned_unique_ratio_percent: usize = 75,
    interned_capacity_ratio_percent: usize = 100,
};

const DEFAULT_BUDGET = PerformanceBudget{};

fn nowNanos() i96 {
    const io = std.Io.Threaded.global_single_threaded.io();
    return std.Io.Clock.awake.now(io).toNanoseconds();
}

const CountingWriter = struct {
    bytes: usize = 0,

    pub fn write(self: *CountingWriter, data: []const u8) error{}!usize {
        self.bytes += data.len;
        return data.len;
    }
};

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const render_result = try benchmarkRenderThroughput(allocator);
    const table_result = try benchmarkTableScroll(allocator);
    const input_result = try benchmarkInputLatency();
    const unicode_result = benchmarkUnicodeMeasurement();
    const memory_result = try benchmarkMemoryUsage(allocator);
    try checkPerformanceBudgets(DEFAULT_BUDGET, render_result, table_result, input_result, unicode_result, memory_result);

    std.debug.print(
        \\Render throughput: {d} frames, avg {d} ns ({d:.2} fps), wrote {d} bytes
        \\Table scroll (10k rows): {d} iterations in {d} ms (avg {d} ns)
        \\Input decode latency: {d} events, avg {d} ns
        \\Unicode width measurement: {d} mixed-script strings, avg {d} ns
        \\Memory (table text, 10k rows): plain payload {d} bytes vs interned unique payload {d} bytes across {d} strings (string arena capacity {d} bytes)
        \\Performance budgets: passed
        \\
    , .{
        render_result.frames,
        render_result.avg_ns,
        render_result.fps,
        render_result.bytes_written,
        table_result.iterations,
        table_result.total_ns / std.time.ns_per_ms,
        table_result.avg_ns,
        input_result.decoded,
        input_result.avg_ns,
        unicode_result.iterations,
        unicode_result.avg_ns,
        memory_result.plain_payload_bytes,
        memory_result.interned_unique_bytes,
        memory_result.interned_unique_strings,
        memory_result.interned_allocated_bytes,
    });
}

fn percentOf(value: usize, total: usize) usize {
    if (total == 0) return std.math.maxInt(usize);
    return (value / total) * 100 + ((value % total) * 100 / total);
}

fn checkPerformanceBudgets(
    budget: PerformanceBudget,
    render_result: RenderBench,
    table_result: TableBench,
    input_result: InputBench,
    unicode_result: UnicodeBench,
    memory_result: MemoryBench,
) !void {
    return checkPerformanceBudgetsImpl(budget, render_result, table_result, input_result, unicode_result, memory_result, true);
}

fn checkPerformanceBudgetsImpl(
    budget: PerformanceBudget,
    render_result: RenderBench,
    table_result: TableBench,
    input_result: InputBench,
    unicode_result: UnicodeBench,
    memory_result: MemoryBench,
    emit_diagnostics: bool,
) !void {
    var failed = false;

    if (render_result.avg_ns > budget.render_avg_ns) {
        if (emit_diagnostics) {
            std.debug.print("performance budget exceeded: render avg {d} ns > {d} ns\n", .{ render_result.avg_ns, budget.render_avg_ns });
        }
        failed = true;
    }
    if (table_result.avg_ns > budget.table_scroll_avg_ns) {
        if (emit_diagnostics) {
            std.debug.print("performance budget exceeded: table scroll avg {d} ns > {d} ns\n", .{ table_result.avg_ns, budget.table_scroll_avg_ns });
        }
        failed = true;
    }
    if (input_result.avg_ns > budget.input_decode_avg_ns) {
        if (emit_diagnostics) {
            std.debug.print("performance budget exceeded: input decode avg {d} ns > {d} ns\n", .{ input_result.avg_ns, budget.input_decode_avg_ns });
        }
        failed = true;
    }
    if (unicode_result.avg_ns > budget.unicode_measure_avg_ns) {
        if (emit_diagnostics) {
            std.debug.print(
                "performance budget exceeded: Unicode measurement avg {d} ns > {d} ns\n",
                .{ unicode_result.avg_ns, budget.unicode_measure_avg_ns },
            );
        }
        failed = true;
    }

    const unique_ratio = percentOf(memory_result.interned_unique_bytes, memory_result.plain_payload_bytes);
    if (unique_ratio > budget.interned_unique_ratio_percent) {
        if (emit_diagnostics) {
            std.debug.print(
                "performance budget exceeded: interned unique bytes {d}% of plain payload > {d}%\n",
                .{ unique_ratio, budget.interned_unique_ratio_percent },
            );
        }
        failed = true;
    }

    const capacity_ratio = percentOf(memory_result.interned_allocated_bytes, memory_result.plain_payload_bytes);
    if (capacity_ratio > budget.interned_capacity_ratio_percent) {
        if (emit_diagnostics) {
            std.debug.print(
                "performance budget exceeded: interned arena capacity {d}% of plain payload > {d}%\n",
                .{ capacity_ratio, budget.interned_capacity_ratio_percent },
            );
        }
        failed = true;
    }

    if (failed) return error.PerformanceBudgetExceeded;
}

const RenderBench = struct {
    frames: usize,
    avg_ns: u64,
    fps: f64,
    bytes_written: usize,
};

fn benchmarkRenderThroughput(allocator: std.mem.Allocator) !RenderBench {
    var renderer = try render.Renderer.init(allocator, 120, 40);
    defer renderer.deinit();
    renderer.capabilities.unicode = true;
    renderer.capabilities.colors_256 = true;
    renderer.capabilities.rgb_colors = true;

    var sink = CountingWriter{};
    const iterations: usize = 400;

    const start_ns = nowNanos();
    for (0..iterations) |_| {
        renderer.fillRect(0, 0, 120, 40, ' ', render.Color.named(.white), render.Color.named(.black), render.Style{});
        renderer.drawStyledBox(1, 1, 80, 10, render.BoxStyle{
            .border = render.BorderStyle.rounded,
            .border_color = render.Color.named(.cyan),
            .background = render.Color.named(.black),
        });
        renderer.drawHLine(2, 12, 90, '-', render.Color.named(.green), render.Color.named(.black), render.Style{});
        renderer.drawVLine(10, 2, 30, '|', render.Color.named(.yellow), render.Color.named(.black), render.Style{});
        try renderer.renderToWriter(&sink);
    }

    const total_ns: u64 = @intCast(nowNanos() - start_ns);
    const fps = (@as(f64, @floatFromInt(iterations)) * @as(f64, @floatFromInt(std.time.ns_per_s))) /
        @as(f64, @floatFromInt(total_ns));

    return .{
        .frames = iterations,
        .avg_ns = total_ns / iterations,
        .fps = fps,
        .bytes_written = sink.bytes,
    };
}

const TableBench = struct {
    iterations: usize,
    total_ns: u64,
    avg_ns: u64,
};

fn benchmarkTableScroll(allocator: std.mem.Allocator) !TableBench {
    var renderer = try render.Renderer.init(allocator, 120, 40);
    defer renderer.deinit();
    renderer.capabilities.unicode = true;
    renderer.capabilities.colors_256 = true;
    renderer.capabilities.rgb_colors = true;

    var builder = widget.TableBuilder.init(allocator);
    _ = try builder.addColumn(.{ .header = "ID", .width = 6 });
    _ = try builder.addColumn(.{ .header = "Status", .width = 10 });
    _ = try builder.addColumn(.{ .header = "Description", .width = 100, .resizable = false });
    var table = try builder.build();
    defer table.deinit();

    const row_count: usize = 10_000;
    const statuses = [_][]const u8{ "OK", "WARN", "BUSY", "IDLE" };

    for (0..row_count) |i| {
        var id_buf: [16]u8 = undefined;
        var desc_buf: [48]u8 = undefined;
        const id = try std.fmt.bufPrint(&id_buf, "#{d}", .{i});
        const desc = try std.fmt.bufPrint(&desc_buf, "Row {d} scrolling payload", .{i % 256});
        try table.addRow(&.{ id, statuses[i % statuses.len], desc });
    }

    try table.widget.layout(layout.Rect.init(0, 0, 118, 38));
    table.setShowGrid(false);

    const header_offset: usize = if (table.show_headers) 1 else 0;
    const visible_rows = @max(@as(usize, 1), @as(usize, table.widget.rect.height) - header_offset);
    const max_start = row_count - @min(row_count, visible_rows);
    var sink = CountingWriter{};

    const iterations: usize = 400;
    const start_ns = nowNanos();
    for (0..iterations) |iter| {
        const start = if (max_start == 0) 0 else (iter * 32) % max_start;
        table.first_visible_row = start;
        table.setSelectedRow(start);
        try table.widget.draw(&renderer);
        try renderer.renderToWriter(&sink);
    }

    const total_ns: u64 = @intCast(nowNanos() - start_ns);
    return .{
        .iterations = iterations,
        .total_ns = total_ns,
        .avg_ns = total_ns / iterations,
    };
}

const InputBench = struct {
    decoded: usize,
    avg_ns: u64,
};

const UnicodeBench = struct {
    iterations: usize,
    avg_ns: u64,
};

fn benchmarkUnicodeMeasurement() UnicodeBench {
    const sample = "status: 東京 e\u{0301} क्‍ष 각 👩‍💻 🇮🇳 ䷀";
    const capabilities = render.TerminalCapabilities.init();
    const iterations: usize = 25_000;

    const start_ns = nowNanos();
    for (0..iterations) |_| {
        const metrics = capabilities.measure(sample);
        std.mem.doNotOptimizeAway(metrics);
    }
    const total_ns: u64 = @intCast(nowNanos() - start_ns);
    return .{ .iterations = iterations, .avg_ns = total_ns / iterations };
}

fn benchmarkInputLatency() !InputBench {
    const sequences = [_][]const u8{
        "\x1b[A",
        "\x1b[B",
        "\x1b[1;5C",
        "\x1b[99;5u",
        "\x1b[57417;2u",
        "\x1b[I",
        "\x1b[O",
        "a",
        "Z",
        "\x1b[<64;10;5M",
    };

    const iterations: usize = 50_000;
    const start_ns = nowNanos();
    for (0..iterations) |idx| {
        const seq = sequences[idx % sequences.len];
        _ = try input.decodeEventFromBytes(seq);
    }
    const total_ns: u64 = @intCast(nowNanos() - start_ns);
    return .{
        .decoded = iterations,
        .avg_ns = total_ns / iterations,
    };
}

const MemoryBench = struct {
    plain_payload_bytes: usize,
    interned_unique_bytes: usize,
    interned_unique_strings: usize,
    interned_allocated_bytes: usize,
};

fn benchmarkMemoryUsage(allocator: std.mem.Allocator) !MemoryBench {
    const row_count: usize = 10_000;

    var arena_plain = std.heap.ArenaAllocator.init(allocator);
    defer arena_plain.deinit();
    var plain_table = try widget.Table.init(arena_plain.allocator());
    defer plain_table.deinit();
    try seedTable(plain_table, row_count);
    const plain_payload_bytes = estimateTablePayloadBytes(plain_table);

    var arena_intern = std.heap.ArenaAllocator.init(allocator);
    defer arena_intern.deinit();
    var intern_table = try widget.Table.init(arena_intern.allocator());
    defer intern_table.deinit();
    try intern_table.enableStringInterning();
    try seedTable(intern_table, row_count);
    const stats = intern_table.stringInternStats() orelse return error.ExpectedInternedTable;

    return .{
        .plain_payload_bytes = plain_payload_bytes,
        .interned_unique_bytes = stats.unique_bytes,
        .interned_unique_strings = stats.unique_strings,
        .interned_allocated_bytes = stats.pooled_bytes,
    };
}

fn estimateTablePayloadBytes(table: *widget.Table) usize {
    var total: usize = 0;
    for (table.columns.items) |column| total += column.header.len;
    for (table.rows.items) |row| {
        for (row.items) |cell| total += cell.text.len;
    }
    return total;
}

fn seedTable(table: *widget.Table, rows: usize) !void {
    if (table.columns.items.len == 0) {
        try table.addColumn("ID", 6, true);
        try table.addColumn("Status", 10, true);
        try table.addColumn("Payload", 96, true);
    }

    const statuses = [_][]const u8{ "READY", "BUSY", "IDLE", "WARN" };

    for (0..rows) |i| {
        var id_buf: [16]u8 = undefined;
        var payload_buf: [48]u8 = undefined;
        const id = try std.fmt.bufPrint(&id_buf, "{d}", .{i});
        const payload = try std.fmt.bufPrint(&payload_buf, "payload-{d}", .{i % 512});
        try table.addRow(&.{ id, statuses[i % statuses.len], payload });
    }
}

test "performance budget rejects slow render" {
    const budget = PerformanceBudget{ .render_avg_ns = 10 };
    try std.testing.expectError(error.PerformanceBudgetExceeded, checkPerformanceBudgetsImpl(
        budget,
        .{ .frames = 1, .avg_ns = 11, .fps = 1, .bytes_written = 0 },
        .{ .iterations = 1, .total_ns = 1, .avg_ns = 1 },
        .{ .decoded = 1, .avg_ns = 1 },
        .{ .iterations = 1, .avg_ns = 1 },
        .{
            .plain_payload_bytes = 100,
            .interned_unique_bytes = 50,
            .interned_unique_strings = 1,
            .interned_allocated_bytes = 50,
        },
        false,
    ));
}

test "performance budget rejects slow Unicode measurement" {
    const budget = PerformanceBudget{ .unicode_measure_avg_ns = 10 };
    try std.testing.expectError(error.PerformanceBudgetExceeded, checkPerformanceBudgetsImpl(
        budget,
        .{ .frames = 1, .avg_ns = 1, .fps = 1, .bytes_written = 0 },
        .{ .iterations = 1, .total_ns = 1, .avg_ns = 1 },
        .{ .decoded = 1, .avg_ns = 1 },
        .{ .iterations = 1, .avg_ns = 11 },
        .{
            .plain_payload_bytes = 100,
            .interned_unique_bytes = 50,
            .interned_unique_strings = 1,
            .interned_allocated_bytes = 50,
        },
        false,
    ));
}

test "performance budget accepts current shape" {
    try checkPerformanceBudgets(
        DEFAULT_BUDGET,
        .{ .frames = 400, .avg_ns = 1_000_000, .fps = 1000, .bytes_written = 1 },
        .{ .iterations = 400, .total_ns = 10_000_000, .avg_ns = 25_000 },
        .{ .decoded = 50_000, .avg_ns = 100 },
        .{ .iterations = 25_000, .avg_ns = 10_000 },
        .{
            .plain_payload_bytes = 200_000,
            .interned_unique_bytes = 50_000,
            .interned_unique_strings = 1_000,
            .interned_allocated_bytes = 70_000,
        },
    );
}
