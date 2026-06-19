# Cookbook

Practical patterns for building Zit applications without guessing at lifecycle,
input, rendering, resize, or release behavior. Each recipe points to the
reference guide or runnable example that proves the pattern.

## Production App Skeleton

Use `Application`, `InputHandler`, `Renderer`, and `ReflowManager` together so
input, resize, timers, and rendering share one event loop.

```zig
var memory = try zit.memory.MemoryManager.init(allocator, 1 * 1024 * 1024, 128);
defer memory.deinit();

var term = try zit.terminal.init(memory.getArenaAllocator());
defer term.deinit() catch |err| zit.terminal.reportCleanupError("term.deinit", err);

var renderer = try zit.render.Renderer.init(memory.getArenaAllocator(), term.width, term.height);
defer renderer.deinit();
renderer.setScratchAllocator(memory.frameAllocator());

var input = zit.input.InputHandler.init(memory.getArenaAllocator(), &term);
var app = zit.event.Application.initWithMemoryManager(&memory);
defer app.deinit();

var reflow = zit.layout.ReflowManager.init();
reflow.setRoot(root.widget.asLayoutElement());

app.setRoot(root);
app.bindInput(&input);
app.bindResize(&renderer, &reflow);
_ = try app.handleResize(term.width, term.height);
```

Reference: [APP_LOOP_TUTORIAL.md](APP_LOOP_TUTORIAL.md), [API.md](API.md).

## Raw Mode and Alternate Screen Cleanup

Every terminal state transition must have a deferred restoration path. Report
cleanup failures instead of swallowing them; cleanup can fail while raw mode or
alternate-screen state is being restored.

```zig
try term.enterAlternateScreen();
defer term.exitAlternateScreen() catch |err| zit.terminal.reportCleanupError("term.exitAlternateScreen", err);

try term.enableRawMode();
defer term.disableRawMode() catch |err| zit.terminal.reportCleanupError("term.disableRawMode", err);

try term.hideCursor();
defer term.showCursor() catch |err| zit.terminal.reportCleanupError("term.showCursor", err);
```

Gate: `python3 scripts/check_terminal_state_cleanup.py`.

## Interactive Example Contract

Public examples should be real interactive terminal programs:

- enter the alternate screen;
- render continuously or redraw after events;
- support `q` to quit;
- report terminal cleanup failures;
- survive tiny terminal sizes and resize back to normal dimensions.

Run:

```sh
zig build demo
python3 scripts/interactive_example_smoke.py
python3 scripts/resize_smoke.py --no-build
```

Reference examples: [examples/demo.zig](../examples/demo.zig),
[examples/widget_test.zig](../examples/widget_test.zig),
[examples/realworld/dashboard_demo.zig](../examples/realworld/dashboard_demo.zig).

## Automatic Resize

Bind input and resize once, then let `pollInputOnce()` and `tickOnce()` keep the
renderer and reflow tree synchronized.

```zig
app.bindInput(&input_handler);
app.bindResize(&renderer, &reflow);
_ = try app.handleResize(term.width, term.height);

while (running) {
    if (try app.pollInputOnce()) |event| {
        switch (event) {
            .key => |key| if (key.key == 'q') running = false,
            else => {},
        }
    }

    try app.tickOnce();
    renderer.back.clear();
    reflow.render(&renderer);
    try renderer.render();
}
```

Gate: `python3 scripts/resize_smoke.py --no-build`.

## Mouse Coordinates and Hit Testing

Mouse events returned by `InputHandler` are already normalized to zero-based
render coordinates. Widget hit tests should compare those coordinates directly
with layout rectangles.

```zig
if (try input_handler.pollEvent(0)) |event| switch (event) {
    .mouse => |mouse| {
        if (button.widget.rect.contains(mouse.x, mouse.y)) {
            _ = try button.widget.handleEvent(.{ .mouse = mouse });
        }
    },
    else => {},
};
```

Only raw terminal protocol coordinates should use terminal-coordinate helpers:

```zig
const event = zit.input.MouseEvent.fromTerminalCoordinates(.press, 1, 1, 1, 0);
```

Gates: `python3 scripts/check_mouse_coordinate_contract.py`,
`python3 scripts/check_mouse_hit_coverage.py`, and
`python3 scripts/mouse_alignment_smoke.py --no-build`.

## Memory Ownership

Use `MemoryManager` for applications that allocate widgets, scratch render
buffers, and frame-local data. Use widget-pool allocation for long-lived
widgets and frame allocation for temporary render work.

```zig
const widgets = memory.getWidgetPoolAllocator();
const frame = memory.frameAllocator();

var table = try zit.widget.Table.init(widgets);
defer table.deinit();

const scratch = try frame.alloc(u8, 256);
_ = scratch;
memory.resetFrame();
```

Rules:

- every `init` that owns allocations needs a matching `deinit`;
- owned string replacements must be transactional under `OutOfMemory`;
- allocator-owned helper results must have one caller cleanup rule;
- examples should use `DebugAllocator` when they own public lifecycle behavior.

Gates: `python3 scripts/check_debug_allocator_cleanup.py` and
`python3 scripts/check_owned_allocation_patterns.py`.

## Rendering Without Flicker

Keep one renderer alive, clear or redraw the back buffer intentionally, then use
`renderer.render()` to diff against the front buffer.

```zig
renderer.back.clear();
try root.widget.draw(&renderer);
try renderer.render();
```

For visual changes, capture repeated frames:

```sh
python3 scripts/visual_repeat_check.py --count 4
```

Inspect `zig-out/visual-repeat/contact-sheet.png` for clipping, overlapping
text, unstable alignment, blank frames, and frame-to-frame drift.

## Adding a Widget

Before promoting a widget as public:

1. implement allocator-aware `init` and `deinit`;
2. expose keyboard accessibility metadata;
3. add direct mouse hit-test coverage if it handles mouse input;
4. document it in [WIDGET_CATALOG.md](WIDGET_CATALOG.md);
5. add a visual or snapshot coverage reference;
6. run `zig build widget-coverage` and `zig build mouse-hit-coverage`.

Reference: [WIDGET_GUIDE.md](WIDGET_GUIDE.md).

## Release Readiness

Before pushing public-facing stability work:

```sh
zig build release-check --summary all
```

Then inspect:

- generated docs under `zig-out/docs-release`;
- visual contact sheet under `zig-out/visual-repeat/contact-sheet.png`;
- CI status for the pushed `main` commit.

Reference: [STABILITY.md](STABILITY.md).
