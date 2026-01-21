// Benchmark suite entrypoint for Zit render/layout microbenchmarks.

const std = @import("std");
const zit = @import("zit");

const render = zit.render;
const widget = zit.widget;
const layout = zit.layout;
const input = zit.input;

const CountingWriter = struct {
    bytes: usize = 0,

    pub fn write(self: *CountingWriter, data: []const u8) error{}!usize {
        self.bytes += data.len;
        return data.len;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const render_result = try benchmarkRenderThroughput(allocator);
    const table_result = try benchmarkTableScroll(allocator);
    const input_result = try benchmarkInputLatency();
    const memory_result = try benchmarkMemoryUsage(allocator);

    std.debug.print(
        \\Render throughput: {d} frames, avg {d} ns ({d:.2} fps), wrote {d} bytes
        \\Table scroll (10k rows): {d} iterations in {d} ms (avg {d} ns)
        \\Input decode latency: {d} events, avg {d} ns
        \\Memory (table, 10k rows): plain {d} bytes vs interned {d} bytes
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
        memory_result.plain_bytes,
        memory_result.interned_bytes,
    });
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

    var timer = try std.time.Timer.start();
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

    const total_ns = timer.read();
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
    var timer = try std.time.Timer.start();
    for (0..iterations) |iter| {
        const start = if (max_start == 0) 0 else (iter * 32) % max_start;
        table.first_visible_row = start;
        table.setSelectedRow(start);
        try table.widget.draw(&renderer);
        try renderer.renderToWriter(&sink);
    }

    const total_ns = timer.read();
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

fn benchmarkInputLatency() !InputBench {
    const sequences = [_][]const u8{
        "\x1b[A",
        "\x1b[B",
        "\x1b[1;5C",
        "a",
        "Z",
        "\x1b[<64;10;5M",
    };

    const iterations: usize = 50_000;
    var timer = try std.time.Timer.start();
    for (0..iterations) |idx| {
        const seq = sequences[idx % sequences.len];
        _ = try input.decodeEventFromBytes(seq);
    }
    const total_ns = timer.read();
    return .{
        .decoded = iterations,
        .avg_ns = total_ns / iterations,
    };
}

const MemoryBench = struct {
    plain_bytes: usize,
    interned_bytes: usize,
};

fn benchmarkMemoryUsage(allocator: std.mem.Allocator) !MemoryBench {
    const row_count: usize = 10_000;

    var arena_plain = std.heap.ArenaAllocator.init(allocator);
    defer arena_plain.deinit();
    var plain_table = try widget.Table.init(arena_plain.allocator());
    defer plain_table.deinit();
    try seedTable(plain_table, row_count);
    const plain_bytes = arena_plain.state.end_index;

    var arena_intern = std.heap.ArenaAllocator.init(allocator);
    defer arena_intern.deinit();
    var intern_table = try widget.Table.init(arena_intern.allocator());
    defer intern_table.deinit();
    try intern_table.enableStringInterning();
    try seedTable(intern_table, row_count);
    const intern_bytes = arena_intern.state.end_index;

    return .{
        .plain_bytes = plain_bytes,
        .interned_bytes = intern_bytes,
    };
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
