# Integration Guide

Zit is designed to drop cleanly into existing Zig projects, whether you use the package manager or vendor the source. This guide shows the quickest paths and a couple of project patterns that map well to Zit.

## Adding Zit via the Zig package manager

1. Fetch and record the dependency (Zig 0.15+):
```bash
zig fetch --save git+https://github.com/oswalpalash/zit
```

2. Import the module in `build.zig`:
```zig
const zit_dep = b.dependency("zit", .{});
const zit_mod = zit_dep.module("zit");

const exe = b.addExecutable(.{
    .name = "app",
    .root_source_file = b.path("src/main.zig"),
});
exe.root_module.addImport("zit", zit_mod);
```

3. Keep your `build.zig.zon` pinned to a tag (`v0.x.y`). CI publishes a release for every tag so you can lock to a known bundle without mirroring.

## Vendoring into an existing repo

1. Add Zit as a submodule (example path `deps/zit`):
```bash
git submodule add https://github.com/oswalpalash/zit.git deps/zit
```

2. Wire the module:
```zig
const zit_mod = b.createModule(.{
    .root_source_file = b.path("deps/zit/src/main.zig"),
});
exe.root_module.addImport("zit", zit_mod);
```

3. Update submodules when you upgrade Zig or pull new widgets (`git submodule update --remote deps/zit`).

## Embedding Zit in larger builds

- **Multiple executables/tests**: create the module once and re-use it:
```zig
const zit_mod = b.dependency("zit", .{}).module("zit");
const server = b.addExecutable(.{ .name = "server", .root_source_file = b.path("src/server.zig") });
server.root_module.addImport("zit", zit_mod);

const cli = b.addExecutable(.{ .name = "cli", .root_source_file = b.path("src/cli.zig") });
cli.root_module.addImport("zit", zit_mod);
```
- **Custom render backends**: `zit.render.Renderer` is allocator-driven. If you need to drive rendering from another loop, call `renderer.render()` only when your backend says the terminal is ready and use `Application.tickOnce()` for non-blocking event processing.
- **Async/background work**: keep UI smooth by using `Application.startBackgroundTask()` and listen for the completion event before mutating widgets.

## Project patterns that pair well with Zit

### MVC/Presenter
- **Model**: own your data and keep it allocator-aware.
- **View**: compose widgets as struct fields; render based on the model snapshot.
- **Controller**: route `zit.event.Event` to methods that mutate the model and view.
```zig
const std = @import("std");
const zit = @import("zit");

const Model = struct { cpu: u8, services: []const []const u8 };

const Dashboard = struct {
    renderer: zit.render.Renderer,
    cpu: zit.widget.Gauge,
    services: zit.widget.Table,

    fn init(alloc: std.mem.Allocator, term: *zit.terminal.Terminal) !Dashboard {
        var table_builder = zit.widget.TableBuilder.init(alloc);
        const table = try table_builder.build();
        return .{
            .renderer = try zit.render.Renderer.init(alloc, term.width, term.height),
            .cpu = try zit.widget.Gauge.init(alloc),
            .services = table,
        };
    }

    fn update(self: *Dashboard, model: Model) void {
        self.cpu.setValue(model.cpu);
        // Rebuild or patch the table from the model here.
    }
};

fn run(app: *zit.event.Application, dash: *Dashboard, model: *Model) !void {
    while (try app.tickOnce()) |evt| switch (evt) {
        .key => |key| if (key.key == 'r') { model.cpu = 42; dash.update(model.*); },
        .resize => |size| try dash.renderer.resize(size.width, size.height),
        else => {},
    };
}
```

### Component-based widgets
- Create reusable components that expose their root widget and manage their own init/deinit.
- Wire focus and keyboard handlers in a small `handleEvent` method so the parent can delegate easily.
```zig
const SearchBox = struct {
    input: zit.widget.Input,

    fn init(alloc: std.mem.Allocator) !SearchBox {
        var input = try zit.widget.Input.init(alloc);
        input.widget.focused = true;
        return .{ .input = input };
    }

    fn widget(self: *SearchBox) *zit.widget.Widget {
        return &self.input.widget;
    }

    fn handleEvent(self: *SearchBox, event: zit.event.Event) void {
        if (event == .input) self.input.handleEvent(event);
    }
};
```
- Parent layout code simply places each component's root widget; components stay testable in isolation.

## Slotting Zit beside other loops

If you already have a network or game loop, integrate Zit without blocking:
- Drive input with `if (try input.pollEvent(timeout_ms)) |event| ...` to keep deterministic frames.
- Use `Application.tickOnce()` inside your main loop to process timers/animations while you run other work between ticks.
- On shutdown, call `renderer.render()` once after clearing the back buffer to leave the terminal clean.
