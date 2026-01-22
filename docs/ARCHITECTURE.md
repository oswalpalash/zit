# Zit Architecture

This document explains how Zit fits together internally: the main modules, how data flows through the system, and the memory and event models that keep TUIs responsive.

## Module Overview
- **terminal** – Cross-platform terminal driver (raw mode, cursor control, alt screen, sync output, mouse enable/disable, capability detection).
- **input** – Decodes bytes from the terminal into semantic `KeyEvent`/`MouseEvent`/`resize` notifications and normalizes modifiers and special keys.
- **event** – Event types, dispatchers, queues, and propagation helpers (capturing/target/bubbling) used by widgets and application code.
- **layout** – Geometry primitives (`Rect`, `Constraints`, flex helpers) plus adapters that let widgets plug into layout containers.
- **render** – Double-buffered renderer with drawing primitives, ANSI/truecolor support, gradients, focus rings, and glyph width helpers.
- **widget** – Base `Widget` + vtable, theme helpers, builder APIs, and the built-in widget set.
- **memory** – `MemoryManager` composed of an arena for per-frame/temp allocations and a pool allocator sized for widgets.

## Data Flow (Text Diagrams)
- **Input → Event → Widget → Render → Terminal**
  - Terminal bytes are read by `input.InputHandler`.
  - Decoded events are queued in `event.EventQueue` and dispatched with propagation.
  - Widgets update state/layout on events, draw into the render back buffer, and the renderer flushes to the terminal.
- **Layout pass → Draw pass**
  - Containers measure children via `Widget.getPreferredSize` (through the layout adapters) and assign `Rect`s.
  - Once rectangles are final, `Widget.draw` emits characters/colors into the render buffer; `Renderer.render()` diffs against the front buffer.
- **Timers/Animations → Event loop**
  - `event.timer.TimerManager` and `widget.animation.Animator` enqueue callbacks/events that are processed alongside user input, keeping motion and IO unified.

## Application Loop
- The app loop is a thin orchestration layer around input polling, `Application.tickOnce()`, layout, and `Renderer.render()`.
- See `docs/APP_LOOP_TUTORIAL.md` for a full end-to-end example that wires together terminal setup, the event queue, reflow layout, and rendering.

## Memory Management Strategy
- **MemoryManager** owns:
  - An **arena allocator**: fast, resettable per-frame scratch space for transient buffers, measurements, and decoded input.
  - A **widget pool allocator**: fixed-size blocks sized to `widget.Widget` for quick allocation/deallocation and reuse of widget instances.
  - A reference to the **parent allocator** for long-lived objects that should outlive a frame.
- **Reset model**: call `MemoryManager.resetArena()` once per frame or when a screen redraw completes to reclaim temporary allocations in bulk.
- **Widget lifetime**: allocate widgets from the pool allocator and pair each `init` with a `deinit` to return blocks to the pool; large per-widget data can still use the parent allocator if needed.
- **Stats**: `MemoryManager.getStats()` surfaces arena usage and pool stats for profiling; leaks are prevented by the pooled design and arena resets.

## Event Propagation Model
- Events carry both a `target` and `current_target` plus a `PropagationPhase` enum (`capturing`, `target`, `bubbling`).
- `event.propagation.buildWidgetPath` walks `Widget.parent` links to build the root→leaf path for a target.
- `EventDispatcher.dispatchEventWithPropagation` runs three phases:
  - **Capturing**: root down to the parent of the target.
  - **Target**: dispatched to the target widget.
  - **Bubbling**: from the target’s parent back up to root.
- Listeners can mark `handled` or `stop_propagation` to short-circuit traversal. Custom events can also install filter functions for selective delivery.
- Widgets typically register listeners for focus changes, pointer/key handling, and custom actions; container widgets can intercept in capturing to implement behaviors like focus rings or hover management.
