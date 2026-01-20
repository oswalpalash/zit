const std = @import("std");
const render = @import("render/render.zig");

/// Options for quick one-off rendering.
pub const FrameOptions = struct {
    width: u16 = 48,
    height: u16 = 6,
    padding: u16 = 1,
    fg: render.Color = render.Color.named(render.NamedColor.white),
    bg: render.Color = render.Color.named(render.NamedColor.default),
    style: render.Style = render.Style{},
    render_frame: bool = true,
};

/// Run a render callback with a ready-to-use renderer and sensible defaults.
pub fn withRenderer(
    allocator: std.mem.Allocator,
    options: FrameOptions,
    draw: *const fn (*render.Renderer, FrameOptions) anyerror!void,
) !void {
    var renderer = render.Renderer.init(allocator, options.width, options.height) catch |err| {
        std.log.err("zit.quickstart: failed to start renderer: {s}", .{@errorName(err)});
        return err;
    };
    defer renderer.deinit();

    renderer.fillRect(0, 0, options.width, options.height, ' ', options.fg, options.bg, options.style);
    try draw(&renderer, options);
    if (options.render_frame) {
        try renderer.render();
    }
}

/// Smallest possible "hello world" entry-point.
pub fn renderText(text: []const u8, options: FrameOptions) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try withRenderer(allocator, options, struct {
        fn draw(r: *render.Renderer, opts: FrameOptions) !void {
            const x = if (opts.padding < opts.width) opts.padding else opts.width - 1;
            const y = if (opts.padding < opts.height) opts.padding else opts.height - 1;
            r.drawSmartStr(x, y, text, opts.fg, opts.bg, opts.style);
        }
    }.draw);
}

test "renderText draws without extra boilerplate" {
    const allocator = std.testing.allocator;
    try withRenderer(allocator, .{ .render_frame = false }, struct {
        fn draw(r: *render.Renderer, _: FrameOptions) !void {
            r.drawSmartStr(0, 0, "ok", render.Color.named(.green), render.Color.named(.default), render.Style{});
        }
    }.draw);
}
