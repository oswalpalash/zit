# Zit – Zig-first Terminal UI Toolkit

Zit helps you ship terminal dashboards, editors, and workflows with the same confidence you expect from GUI toolkits: a rich widget catalog, focus and typeahead helpers, fast rendering, and accessibility baked in. Zero dependencies, test coverage, and benchmarks included.

## Why Zit
- 30+ production-ready widgets (blocks/paragraphs, charts, tables with typeahead, context menus, popups, file browser, bracketed paste-aware inputs).
- Batteries-included UX: mouse + drag-and-drop payloads, focus rings, typeahead search on lists/tables/file browser, accessibility roles/announcements.
- Thoughtful theming and motion: light/dark/high-contrast palettes, per-widget `setTheme`, animator with easing/yoyo, timers for periodic work.
- Works the Zig way: explicit `init`/`deinit`, allocator-friendly builders, zero global state, tested layouts + render paths, rendering benchmarks.

## Feature Highlights

Compose real screens quickly:

```zig
const std = @import("std");
const zit = @import("zit");
const theme = zit.widget.theme;

const alloc = std.testing.allocator; // replace with your allocator

var tree = try zit.widget.TreeView.init(alloc);
defer tree.deinit();
_ = try tree.addRoot("services");
try tree.setTheme(theme.Theme.dark());

var gauge = try zit.widget.Gauge.init(alloc);
defer gauge.deinit();
try gauge.setTheme(theme.Theme.highContrast());
try gauge.setLabel("CPU");
gauge.setRange(0, 100);

var split = try zit.widget.SplitPane.init(alloc);
defer split.deinit();
split.setOrientation(.horizontal);
try split.setTheme(theme.Theme.dark());
split.setFirst(&tree.widget);
split.setSecond(&gauge.widget);
```

Navigate instantly with typeahead and fluent builders:

```zig
const std = @import("std");
const zit = @import("zit");
const alloc = std.testing.allocator;
var table_builder = zit.widget.TableBuilder.init(alloc);
_ = try table_builder.addColumn(.{ .header = "Service", .width = 16, .sortable = true });
_ = try table_builder.addColumn(.{ .header = "Owner", .width = 10, .sortable = true });
const table = try table_builder.build();
defer table.deinit();

try table.addRow(&.{ "gateway", "alice" });
try table.addRow(&.{ "search", "carmen" });
table.setTypeaheadTimeout(750); // printable keys jump rows while focused
table.widget.focused = true;
```

Add motion and recurring tasks without extra plumbing:

```zig
const std = @import("std");
const zit = @import("zit");
const alloc = std.testing.allocator;
var app = zit.event.Application.init(alloc);
var spark = try zit.widget.Sparkline.init(alloc);
defer spark.deinit();

_ = try app.addAnimation(.{
    .duration_ms = 200,
    .on_update = struct {
        fn update(progress: f32, ctx: ?*anyopaque) void {
            const widget = @as(*zit.widget.Sparkline, @ptrCast(@alignCast(ctx.?)));
            const value: f32 = 20 + progress * 80;
            widget.push(value) catch {};
        }
    }.update,
    .context = @ptrCast(spark),
});

_ = try app.scheduleTimer(1000, 1000, struct {
    fn tick(ctx: ?*anyopaque) void {
        const widget = @as(*zit.widget.Sparkline, @ptrCast(@alignCast(ctx.?)));
        widget.push(42) catch {};
    }
}.tick, spark);
```

## Comparison

| Capability            | Zit | Other Zig TUIs |
| ---                   | --- | --- |
| Widgets               | 30+ ready widgets (gauges, charts, typeahead tables, context menus, popups, drag targets) | Usually 5–15 primitives that require manual composition |
| Input UX              | Keyboard + mouse, drag payloads, focus rings, typeahead on lists/tables/file browser, bracketed paste | Often keyboard-only; advanced behaviors are app code |
| Theming               | Light/dark/high-contrast palettes, per-widget `setTheme`, role-based colors | Basic color constants or app-defined palettes |
| Motion/Feedback       | Animator with easing/yoyo, timers, toasts/notifications | Rarely built-in |
| Accessibility         | Roles + focus announcements wired through `Application` | Typically absent |
| Documentation         | API + widget guides, examples, benchmarks, screenshots | Minimal or example-only |

## Installation

Vendoring works best today (no external dependencies):

1) Add Zit to your tree (example: `deps/zit`):
```bash
git submodule add https://github.com/oswalpalash/zit.git deps/zit
```

2) Wire the module in your `build.zig`:
```zig
const target = b.standardTargetOptions(.{});
const optimize = b.standardOptimizeOption(.{});

const zit_module = b.createModule(.{
    .root_source_file = b.path("deps/zit/src/main.zig"),
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zit", zit_module);
```

From this repo you can also run `zig build hello-world` to confirm your toolchain and terminal setup.

## Quick Start (copy-pasteable)

```zig
const std = @import("std");
const zit = @import("zit");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var term = try zit.terminal.init(allocator);
    defer term.deinit() catch {};
    var renderer = try zit.render.Renderer.init(allocator, term.width, term.height);
    defer renderer.deinit();
    var input = zit.input.InputHandler.init(allocator, &term);

    try term.enableRawMode();
    defer term.disableRawMode() catch {};
    try term.hideCursor();
    defer term.showCursor() catch {};

    var para = try zit.widget.Paragraph.init(allocator, "Hello from Zit! Press q to quit.");
    defer para.deinit();

    var running = true;
    while (running) {
        renderer.back.clear();
        try para.widget.layout(zit.layout.Rect.init(0, 0, renderer.back.width, renderer.back.height));
        try para.widget.draw(&renderer);
        try renderer.render();

        if (try input.pollEvent(120)) |event| switch (event) {
            .key => |key| if (key.key == 'q') running = false,
            .resize => |size| try renderer.resize(size.width, size.height),
            else => {},
        };
    }

    try term.clear();
    try term.moveCursor(0, 0);
}
```

## Examples, Docs, and Benchmarks
- Widget tours: `zig build button-example`, `zig build table-example`, `zig build file-browser-example`, `zig build system-monitor-example`, `zig build form-wizard-example`, `zig build notifications-example`.
- Realistic snapshots: `zig build htop-clone`, `zig build file-manager`, `zig build text-editor`, `zig build dashboard-demo`.
- Benchmarks: `zig build bench` (render throughput).
- Documentation: `docs/API.md`, `docs/WIDGET_GUIDE.md`, `docs/ARCHITECTURE.md`, `docs/TERMINAL_COMPAT.md`.

## Development Notes
- Widgets follow `init`/`deinit` plus `setTheme` for themed variants and surface errors instead of panicking.
- Use `zig fmt --check src/` and `zig build` locally; repo hooks mirror the same checks.
