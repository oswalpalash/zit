# Troubleshooting

Use this guide when a Zit app behaves differently in a real terminal than it did
in tests or snapshots.

## App Flashes, Then the Terminal Goes Blank

Likely causes:

- the program rendered one frame and exited instead of running an event loop;
- the example did not enter the alternate screen;
- cleanup ran before the user could interact with the UI.

Checks:

```sh
zig build demo
python3 scripts/interactive_example_smoke.py
```

Expected behavior: public interactive examples stay alive, render inside the
alternate screen, and quit with `q`.

## Resize Does Not Update Layout

Likely causes:

- `Application.bindInput(&input_handler)` was not called;
- `Application.bindResize(&renderer, &reflow)` was not called;
- the initial terminal size was never pushed through `handleResize`;
- the loop polls input outside `Application` and skips resize dispatch.

Use:

```zig
app.bindInput(&input_handler);
app.bindResize(&renderer, &reflow);
_ = try app.handleResize(term.width, term.height);
```

Check:

```sh
python3 scripts/resize_smoke.py --no-build
```

## Mouse Clicks Land One Row or Column Off

Likely causes:

- raw terminal protocol coordinates were used directly;
- a synthetic mouse event used one-based coordinates;
- a widget compared terminal coordinates with zero-based render rectangles.

Rules:

- events returned by `InputHandler` are already zero-based;
- raw terminal protocol coordinates must use
  `MouseEvent.fromTerminalCoordinates` or
  `translateTerminalMouseCoordinates`;
- hit tests should compare mouse events with rendered layout rectangles.

Checks:

```sh
python3 scripts/check_mouse_coordinate_contract.py
python3 scripts/mouse_alignment_smoke.py --no-build
```

Reference: [API.md](API.md#mouse-coordinates).

## Escape Sequences or UTF-8 Keys Decode Incorrectly

Zit waits up to 25 ms for each byte continuing an ESC, CSI, mouse, or UTF-8 sequence on POSIX and Windows. If a high-latency SSH, tmux, nested-terminal, or console connection still splits sequences beyond that interval, increase the bound before entering the event loop:

```zig
input_handler.setSequenceTimeout(80);
```

Lowering the value reduces lone-Escape latency. A value of `0` disables continuation waiting and is appropriate only when the input transport delivers complete sequences atomically.

On Windows, call `term.supportsVtInputProtocols()` after `enableRawMode`. A false result means the console accepted ordinary raw input but not the VT input mode required for mouse, focus, bracketed-paste, or Kitty keyboard escape sequences. Zit leaves those optional modes disabled instead of reporting a cleanup obligation it cannot fulfill.

## Terminal State Is Not Restored

Likely causes:

- raw mode, cursor visibility, mouse tracking, or alternate-screen cleanup was
  not deferred;
- cleanup errors were swallowed with an empty `catch {}`;
- an early return bypassed manual cleanup.

Use:

```zig
defer term.disableRawMode() catch |err| zit.terminal.reportCleanupError("term.disableRawMode", err);
defer term.showCursor() catch |err| zit.terminal.reportCleanupError("term.showCursor", err);
defer term.exitAlternateScreen() catch |err| zit.terminal.reportCleanupError("term.exitAlternateScreen", err);
```

Check:

```sh
python3 scripts/check_terminal_state_cleanup.py
```

## Memory Diagnostics Report Leaks

Likely causes:

- a widget `deinit` was not called;
- a factory helper returned an owned pointer and the caller did not destroy it;
- a fallible initializer allocated after `allocator.create` without `errdefer`;
- a replacement path leaked old or partially copied owned strings.

Checks:

```sh
python3 scripts/check_debug_allocator_cleanup.py
python3 scripts/check_owned_allocation_patterns.py
zig build test
```

Reference: [COOKBOOK.md](COOKBOOK.md#memory-ownership).

## Visual Captures Flicker or Drift

Likely causes:

- time-varying data is included in snapshot mode;
- the renderer or app state is recreated every frame;
- layout depends on unordered iteration;
- text exceeds fixed-width regions and wraps into neighboring UI.

Check:

```sh
python3 scripts/visual_repeat_check.py --count 4
```

Inspect `zig-out/visual-repeat/contact-sheet.png`. Repeated frames for the same
target should be visually identical unless the target is intentionally animated
and the animation is part of the test.

## Widget Is Missing From Docs or Coverage

Likely causes:

- a public widget export was added without a catalog row;
- a helper/factory API was added without an API reference entry;
- the widget has no declared visual or snapshot coverage.

Checks:

```sh
zig build widget-coverage
python3 scripts/check_widget_coverage.py
```

Reference: [WIDGET_CATALOG.md](WIDGET_CATALOG.md) and
[WIDGET_GUIDE.md](WIDGET_GUIDE.md).

## CI Fails But Local Smoke Passes

Use the release gate locally before chasing individual failures:

```sh
zig build release-check --summary all
```

Then compare the failing CI step with the release checklist in
[STABILITY.md](STABILITY.md). Hosted CI intentionally runs some checks in
separate jobs, while local release verification runs the aggregate gate and
writes generated docs plus visual contact sheets.
