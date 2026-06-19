# API Quick Reference

Lightweight pointers to the most-used types and functions. Import via `const zit = @import("zit");`.

## Core Modules
- `terminal` – `Terminal.init(allocator)`, `enableRawMode/disableRawMode`, `moveCursor`, `clear`, `enterAlternateScreen`, `beginSynchronizedOutput/endSynchronizedOutput`, and `reportCleanupError(action, err)` for deferred cleanup paths that cannot return errors.
- `input` – `InputHandler.init(allocator, &terminal)`, `enableMouse/disableMouse`, `pollEvent(timeout_ms)`, resize detection via SIGWINCH plus periodic geometry polling, decoded mouse events in zero-based render coordinates, plus key codes (`KeyCode.*`) and modifiers.
- `event` – `Event`, `EventQueue`, `EventDispatcher`, `PropagationPhase`. Helpers in `propagation.zig` build widget paths and dispatch with bubbling/capturing.
- `event.Application` – event loop coordinator with timers, animations, background tasks, shortcuts, accessibility, `bindInput(&input)`, and `bindResize(&renderer, &reflow)` for automatic terminal resize handling.
- `layout` – `Rect`, `Constraints`, `EdgeInsets`, `Size`, flex helpers. `LayoutElement` adapters let widgets participate in container layouts.
- `render` – `Renderer.init(allocator, width, height)`, `drawStr`, `drawBox`, `fillRect`, `drawGradient`, `render()` (front/back diff). Colors via `Color.named/rgb/ansi256`, styles via `Style` and `FocusRingStyle`.
- `widget` – Base `Widget` + vtable, theme helpers, builders, and concrete widgets (`Label`, `Button`, `List`, `Table`, `SplitPane`, `Modal`, `ContextMenu`, etc.).
- `memory` – `MemoryManager.init(parent, arena_size, widget_pool_size)`, `getArenaAllocator`, `getWidgetPoolAllocator`, `resetArena`, `getStats`.
- `quickstart` – Convenience helpers like `renderText` for trivial programs.
- `testing` – `MockTerminal`, `WidgetHarness`, `renderWidget`, golden snapshot assertions, and `Snapshot.expectWellFormed()` for deterministic headless rendering checks.

## Common Patterns
### Bootstrapping
```zig
var gpa = std.heap.DebugAllocator(.{}){};
defer std.debug.assert(gpa.deinit() == .ok);
const allocator = gpa.allocator();

var memory_manager = try zit.memory.MemoryManager.init(allocator, 1 * 1024 * 1024, 128);
defer memory_manager.deinit();

var term = try zit.terminal.init(allocator);
defer term.deinit() catch |err| zit.terminal.reportCleanupError("term.deinit", err);
try term.enableRawMode();

var renderer = try zit.render.Renderer.init(allocator, term.width, term.height);
defer renderer.deinit();
```

### Event Loop Skeleton
```zig
var app = zit.event.Application.init(allocator);
defer app.deinit();
app.setRoot(root);
app.bindInput(&input_handler);
app.bindResize(&renderer, null);
app.setInputPollTimeout(16);

while (true) {
    _ = try app.pollInputOnce();
    try app.tickOnce();
    try renderer.render();
}
```

### Mouse Coordinates
```zig
const maybe_event = try input_handler.pollEvent(0);
if (maybe_event) |event| switch (event) {
    .mouse => |mouse| {
        // Already zero-based and aligned with renderer/widget layout rects.
        const point = input_handler.translateMouseCoordinates(mouse.x, mouse.y);
        _ = point;
    },
    else => {},
};

// Only use this for raw terminal protocol coordinates read outside InputHandler.
// For synthetic app/widget events, prefer MouseEvent.init with zero-based coords.
const point = input_handler.translateTerminalMouseCoordinates(1, 1);
const synthetic = zit.input.MouseEvent.fromTerminalCoordinates(.press, 1, 1, 1, 0);
_ = synthetic;
```

### Automatic Resize
```zig
var app = zit.event.Application.init(allocator);
defer app.deinit();

var reflow = zit.layout.ReflowManager.init();
reflow.setRoot(root.widget.asLayoutElement());

app.setRoot(root);
app.bindInput(&input_handler);
app.bindResize(&renderer, &reflow);
_ = try app.handleResize(term.width, term.height);

_ = try app.pollInputOnce(); // resize events update renderer + reflow
try app.tickOnce(); // also polls bound input before dispatching events

input_handler.setResizePollInterval(125); // default; use 0 to poll every call
app.setInputPollTimeout(0); // default; keep tickOnce non-blocking
```

### Memory Stats
```zig
const arena = memory_manager.getArenaAllocator();
const widgets = memory_manager.getWidgetPoolAllocator();

const scratch = try arena.alloc(u8, 256);
defer arena.free(scratch); // counted as a deallocation; arena bytes reclaim on resetArena().

var label = try zit.widget.Label.init(widgets, "Ready");
defer label.deinit();

const stats = memory_manager.getStats();
// stats.total_allocations / total_deallocations count operations through MemoryManager allocators.
// stats.current_memory_usage reports arena bytes in use plus live widget-pool block bytes.
// stats.arena_usage drops when resetArena() or resetFrame() is called.
```

### Widget Creation & Layout
```zig
var button = try zit.widget.Button.init(memory_manager.getWidgetPoolAllocator(), "Deploy");
defer button.deinit();
button.setOnClick(myHandler);

const rect = zit.layout.Rect.init(2, 2, 12, 1);
try button.widget.layout(rect);
try button.widget.draw(&renderer);
```

### Widget Factory Helpers
The `widget` module exposes direct factory helpers for quick construction plus a few fluent-builder shortcuts. Every helper returns an owned widget pointer; call the widget's `deinit()` with the same allocator family when it leaves your UI tree.

| Helper | Creates |
| --- | --- |
| `createButton(allocator, text)` | `Button` |
| `button(allocator, text)` | `Button` through `ButtonBuilder` |
| `createLabel(allocator, text)` | `Label` |
| `label(allocator, text)` | `Label` through `LabelBuilder` |
| `createContainer(allocator)` | `Container` |
| `createInputField(allocator)` | `InputField` with default capacity |
| `input(allocator, placeholder)` | `InputField` through `InputBuilder` |
| `createTextArea(allocator)` | `TextArea` with default capacity |
| `textArea(allocator, placeholder)` | `TextArea` through `TextAreaBuilder` |
| `createList(allocator)` | `List` |
| `createProgressBar(allocator)` | `ProgressBar` |
| `progress(allocator, value, max_value)` | `ProgressBar` through `ProgressBarBuilder` |
| `createScrollbar(allocator, orientation)` | `Scrollbar` |
| `createScrollContainer(allocator)` | `ScrollContainer` |
| `createTabView(allocator)` | `TabView` |
| `createModal(allocator)` | `Modal` |
| `createTable(allocator)` | `Table` |
| `table(allocator, columns)` | `Table` through `TableBuilder` |
| `createDropdownMenu(allocator)` | `DropdownMenu` |
| `createContextMenu(allocator)` | `ContextMenu` |
| `createTreeView(allocator)` | `TreeView` |
| `createSparkline(allocator)` | `Sparkline` |
| `createGauge(allocator)` | `Gauge` |
| `createSplitPane(allocator)` | `SplitPane` |
| `createPopup(allocator, message)` | `Popup` |
| `createToastManager(allocator)` | `ToastManager` |
| `createMenuBar(allocator)` | `MenuBar` |
| `createCanvas(allocator, width, height)` | `Canvas` |
| `createColorPicker(allocator, palette)` | `ColorPicker` |
| `createParagraph(allocator, text)` | `Paragraph` |
| `createBlock(allocator)` | `Block` |

State helpers operate on any `BaseWidget` pointer and mark simple lifecycle state directly: `focusWidget(widget)`, `enableWidget(widget)`, `disableWidget(widget)`, `showWidget(widget)`, and `hideWidget(widget)`.

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

### Quickstart Helpers
```zig
const opts = zit.quickstart.FrameOptions{ .width = 32, .height = 6 };
try zit.quickstart.withRenderer(alloc, opts, struct {
    fn draw(r: *zit.render.Renderer, _: zit.quickstart.FrameOptions) !void {
        r.drawSmartStr(1, 1, "Zit quickstart", zit.render.Color.named(.green), zit.render.Color.named(.default), .{});
    }
}.draw);
```

### Theme Hot Reload
```zig
var app = zit.event.Application.init(alloc);
const reloader = try zit.theme_hot_reload.ThemeHotReloader.start(
    alloc,
    &app,
    "theme.toml",
    zit.widget.theme.Theme.dark(),
    struct {
        fn reload(t: zit.widget.theme.Theme, _: ?*anyopaque) void {
            std.log.info("applied theme: {any}", .{t});
        }
    }.reload,
    null,
);
defer reloader.stop();
```

### Debug Hooks
```zig
var tracer = zit.debug.EventTracer.init(std.io.getStdErr().writer());
app.debug_hooks = tracer.hooks();
var inspector = zit.debug.WidgetInspector.init(alloc);
try inspector.printTree(&root.widget, std.io.getStdOut().writer(), .{});
```
