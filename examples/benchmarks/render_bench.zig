// Benchmark: stress-tests renderer throughput and diffing.

const std = @import("std");
const zit = @import("zit");
const render = zit.render;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var renderer = try render.Renderer.init(allocator, 100, 30);
    defer renderer.deinit();

    const iterations: usize = 500;
    var timer = try std.time.Timer.start();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        renderer.fillRect(0, 0, 100, 30, ' ', render.Color.named(render.NamedColor.white), render.Color.named(render.NamedColor.black), render.Style{});
        renderer.drawBox(1, 1, 60, 6, .rounded, render.Color.named(render.NamedColor.cyan), render.Color.named(render.NamedColor.black), render.Style{});
        renderer.drawHLine(2, 4, 50, '-', render.Color.named(render.NamedColor.green), render.Color.named(render.NamedColor.black), render.Style{});
        renderer.drawVLine(10, 2, 8, '|', render.Color.named(render.NamedColor.yellow), render.Color.named(render.NamedColor.black), render.Style{});
    }

    const ns = timer.read();
    const per_iter_ns = ns / iterations;
    std.debug.print("Rendered {d} frames in {d} ms (avg {d} ns)\n", .{ iterations, ns / std.time.ns_per_ms, per_iter_ns });
}
