# Application Loop Tutorial

This guide walks through a minimal, production-style Zit loop: set up terminal + renderer, process input/events, run layout, and render each frame.

## Overview
1) Initialize allocators, terminal, renderer, and the root widget tree.
2) Feed input into the event queue (or call widget handlers directly).
3) Tick the application to process events, timers, and animations.
4) Layout the widget tree and draw into the renderer back buffer.
5) Flush the renderer to the terminal.

## End-to-End Example
```zig
const std = @import("std");
const zit = @import("zit");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var memory = try zit.memory.MemoryManager.init(allocator, 512 * 1024, 128);
    defer memory.deinit();

    var term = try zit.terminal.init(memory.getArenaAllocator());
    defer term.deinit() catch {};

    var renderer = try zit.render.Renderer.init(memory.getArenaAllocator(), term.width, term.height);
    defer renderer.deinit();
    renderer.setScratchAllocator(memory.frameAllocator());

    var input = zit.input.InputHandler.init(memory.getArenaAllocator(), &term);

    try term.enableRawMode();
    defer term.disableRawMode() catch {};
    try term.hideCursor();
    defer term.showCursor() catch {};

    var app = zit.event.Application.initWithMemoryManager(&memory);
    defer app.deinit();

    var root = try zit.widget.Container.init(memory.getWidgetPoolAllocator());
    defer root.deinit();
    app.setRoot(root);

    var title = try zit.widget.Label.init(memory.getWidgetPoolAllocator(), "Zit App Loop");
    defer title.deinit();
    title.setAlignment(.center);

    var progress = try zit.widget.ProgressBar.init(memory.getWidgetPoolAllocator());
    defer progress.deinit();
    progress.setValue(25);
    progress.setShowPercentage(true);

    try root.addChild(&title.widget);
    try root.addChild(&progress.widget);

    var reflow = zit.layout.ReflowManager.init();
    reflow.setRoot(root.widget.asLayoutElement());
    _ = try reflow.handleResize(term.width, term.height);

    try term.clear();

    var running = true;
    while (running) {
        if (try input.pollEvent(16)) |ev| {
            switch (ev) {
                .resize => |size| {
                    try renderer.resize(size.width, size.height);
                    _ = try reflow.handleResize(size.width, size.height);
                },
                .key => |key| {
                    if (key.key == 'q') running = false;
                },
                else => {},
            }

            const app_event = zit.event.fromInputEvent(ev, &root.widget);
            try app.event_queue.pushEvent(app_event);
        }

        try app.tickOnce();

        renderer.back.clear();
        reflow.render(&renderer);
        try renderer.render();
    }

    try term.clear();
    try term.moveCursor(0, 0);
}
```

## Notes and Variations
- **Dirty redraws**: if you keep the back buffer intact between frames, only dirty widgets will redraw and the renderer will diff against the front buffer.
- **Targeting input**: `event.fromInputEvent(ev, target)` lets you set a specific widget target (e.g., from hit testing).
- **Animations/timers**: `Application.tickOnce()` already advances timers/animations, so just keep calling it each frame.
- **Layout updates**: on resize or widget tree changes, call `ReflowManager.handleResize` and re-render.

For more patterns (custom widgets, async tasks, background work), see `docs/WIDGET_GUIDE.md` and `docs/ARCHITECTURE.md`.
