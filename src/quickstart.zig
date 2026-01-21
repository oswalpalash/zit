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
        std.log.err(
            "zit.quickstart: renderer init failed ({s}) for {d}x{d} frame. Try reducing FrameOptions dimensions or check terminal capabilities.",
            .{ @errorName(err), options.width, options.height },
        );
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

    var renderer = try render.Renderer.init(allocator, options.width, options.height);
    defer renderer.deinit();

    if (options.render_frame) {
        renderer.drawBox(0, 0, options.width, options.height, .rounded, options.fg, options.bg, options.style);
    }

    const x = if (options.padding < options.width) options.padding else options.width - 1;
    const y = if (options.padding < options.height) options.padding else options.height - 1;
    renderer.drawSmartStr(x, y, text, options.fg, options.bg, options.style);
    try renderer.render();
}

test "renderText draws without extra boilerplate" {
    const allocator = std.testing.allocator;
    try withRenderer(allocator, .{ .render_frame = false }, struct {
        fn draw(r: *render.Renderer, _: FrameOptions) !void {
            r.drawSmartStr(0, 0, "ok", render.Color.named(.green), render.Color.named(.default), render.Style{});
        }
    }.draw);
}
