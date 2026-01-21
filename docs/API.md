# API Quick Reference

Lightweight pointers to the most-used types and functions. Import via `const zit = @import("zit");`.

## Core Modules
- `terminal` – `Terminal.init(allocator)`, `enableRawMode/disableRawMode`, `moveCursor`, `clear`, `enterAlternateScreen`, `beginSynchronizedOutput/endSynchronizedOutput`.
- `input` – `InputHandler.init(allocator, &terminal)`, `enableMouse/disableMouse`, `pollEvent(timeout_ms)`, plus key codes (`KeyCode.*`) and modifiers.
- `event` – `Event`, `EventQueue`, `EventDispatcher`, `PropagationPhase`. Helpers in `propagation.zig` build widget paths and dispatch with bubbling/capturing.
- `layout` – `Rect`, `Constraints`, `EdgeInsets`, `Size`, flex helpers. `LayoutElement` adapters let widgets participate in container layouts.
- `render` – `Renderer.init(allocator, width, height)`, `drawStr`, `drawBox`, `fillRect`, `drawGradient`, `render()` (front/back diff). Colors via `Color.named/rgb/ansi256`, styles via `Style` and `FocusRingStyle`.
- `widget` – Base `Widget` + vtable, theme helpers, builders, and concrete widgets (`Label`, `Button`, `List`, `Table`, `SplitPane`, `Modal`, `ContextMenu`, etc.).
- `memory` – `MemoryManager.init(parent, arena_size, widget_pool_size)`, `getArenaAllocator`, `getWidgetPoolAllocator`, `resetArena`, `getStats`.
- `quickstart` – Convenience helpers like `renderText` for trivial programs.
- `testing` – Utilities to ease widget/layout testing.

## Common Patterns
### Bootstrapping
```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();
const allocator = gpa.allocator();

var memory_manager = try zit.memory.MemoryManager.init(allocator, 1 * 1024 * 1024, 128);
defer memory_manager.deinit();

var term = try zit.terminal.init(allocator);
defer term.deinit() catch {};
try term.enableRawMode();

var renderer = try zit.render.Renderer.init(allocator, term.width, term.height);
defer renderer.deinit();
```

### Event Loop Skeleton
```zig
var queue = zit.event.EventQueue.init(allocator);
defer queue.deinit();

while (true) {
    if (try input_handler.pollEvent(16)) |evt| {
        try queue.push(evt); // or dispatch immediately
    }
    try queue.processEventsWithPropagation(allocator);
    try renderer.render();
}
```

### Widget Creation & Layout
```zig
var button = try zit.widget.Button.init(memory_manager.getWidgetPoolAllocator(), "Deploy");
defer button.deinit();
button.setOnPress(myHandler);

const rect = zit.layout.Rect.init(2, 2, 12, 1);
try button.widget.layout(rect);
try button.widget.draw(&renderer);
```

### Typeahead Lists/Tables
```zig
list.setTypeaheadTimeout(900);
table.setTypeaheadTimeout(750);
browser.resetTypeahead(); // after directory changes
```

### Timers & Animations
```zig
var app = zit.event.Application.init(allocator);
_ = try app.addAnimation(.{
    .duration_ms = 300,
    .on_update = struct {
        fn update(progress: f32, ctx: ?*anyopaque) void {
            const gauge = @as(*zit.widget.Gauge, @ptrCast(@alignCast(ctx.?)));
            gauge.setValue(progress * 100);
        }
    }.update,
    .context = @ptrCast(gauge),
});
_ = try app.scheduleTimer(1000, 1000, myTick, null);
```

### Terminal Capability Checks
```zig
const caps = term.capabilities;
const border_color = if (caps.rgb_colors) zit.render.Color.rgb(255, 128, 0) else zit.render.Color.named(.bright_yellow);
if (caps.synchronized_output) try term.beginSynchronizedOutput();
```
