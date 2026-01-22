# ROADMAP

## 1. Executive Summary (current state, goal)
- Current state: core widget API mismatches, incomplete event to input translation, parent linkage gaps, rendering safety risks, minimal snapshot coverage, and uneven docs/test depth.
- Goal: ship a consistent, extensible Zig TUI core with reliable event/input handling, robust layout/rendering, cohesive theming and accessibility, and measurable performance and test coverage.

## 2. Phase 1: Foundation (event unification, input correctness)

### P1.1: Unify input and event models
- Description: define a single canonical event model and mapping layer so input parsing and event dispatch share one source of truth (key/mouse/resize/custom).
- Files: `src/input/input.zig`, `src/event/event.zig`, `src/event/propagation.zig`
- Complexity: M
- Dependencies: None

### P1.2: Complete input-to-event translation
- Description: fix Application input conversion for mouse wheel, key release, modifier propagation, and raw key handling; ensure target selection is explicit.
- Files: `src/event/event.zig`, `src/input/input.zig`
- Complexity: M
- Dependencies: P1.1

### P1.3: Input correctness regression suite
- Description: add tests for escape sequences, modifier combos, scroll deltas, and key release semantics to prevent parser regressions.
- Files: `src/input/input.zig`, `src/event/event.zig`, `src/testing/testing.zig`
- Complexity: S
- Dependencies: P1.1, P1.2

## 3. Phase 2: Layout & Rendering (root traversal, Flex/Grid widgets, per-frame arena)

### P2.1: Root traversal and parent linkage guarantees
- Description: standardize parent pointers for composite widgets and provide a root traversal helper for layout, rendering, and hit-testing.
- Files: `src/widget/widgets/tab_view.zig`, `src/widget/widgets/modal.zig`, `src/widget/widgets/scroll_container.zig`, `src/widget/widgets/container.zig`, `src/event/propagation.zig`
- Complexity: M
- Dependencies: None

### P2.2: Fix core widget API and layout inconsistencies
- Description: resolve init/constructor mismatches and layout contract inconsistencies (Label, Scrollbar, ScrollContainer, Modal sizing).
- Files: `src/widget/widget.zig`, `src/widget/widgets/label.zig`, `src/widget/widgets/scrollbar.zig`, `src/widget/widgets/scroll_container.zig`, `src/widget/widgets/modal.zig`, `src/widget/widgets/tab_view.zig`, `src/widget/widgets/split_pane.zig`
- Complexity: M
- Dependencies: None

### P2.3: Rendering safety fixes for truncation and underflow
- Description: clamp truncation buffers and avoid coordinate underflow for Label, Button, and Checkbox rendering paths.
- Files: `src/widget/widgets/label.zig`, `src/widget/widgets/button.zig`, `src/widget/widgets/checkbox.zig`
- Complexity: S
- Dependencies: P2.2

### P2.4: Flex layout widget integration
- Description: create a Flex container widget that wraps `layout.FlexLayout`, supports child management, and integrates into the widget tree.
- Files: `src/layout/layout.zig`, `src/widget/widgets/flex_container.zig`, `src/widget/widget.zig`
- Complexity: L
- Dependencies: P2.1

### P2.5: Grid layout widget integration
- Description: create a Grid container widget that wraps `layout.GridLayout`, supports row/column tracks, and integrates into the widget tree.
- Files: `src/layout/layout.zig`, `src/widget/widgets/grid_container.zig`, `src/widget/widget.zig`
- Complexity: L
- Dependencies: P2.1

### P2.6: Per-frame arena integration
- Description: wire the memory manager into the app loop and reset the arena per tick for layout and render scratch allocations.
- Files: `src/event/event.zig`, `src/memory/memory.zig`, `src/layout/layout.zig`, `src/render/render.zig`
- Complexity: L
- Dependencies: P1.1

## 4. Phase 3: Theming & Accessibility (global theme, CSS integration, accessibility nodes)

### P3.1: Global theme contract for widgets
- Description: define a stable theme role map and align widgets/builders to consume theme defaults consistently.
- Files: `src/widget/theme.zig`, `src/widget/builders.zig`, `src/widget/widgets/*.zig`
- Complexity: M
- Dependencies: P2.2

### P3.2: CSS stylesheet integration
- Description: apply stylesheet resolution to widget id/class and integrate with theme overrides during rendering.
- Files: `src/widget/css.zig`, `src/widget/widgets/base_widget.zig`, `src/event/event.zig`
- Complexity: M
- Dependencies: P3.1

### P3.3: Accessibility node coverage
- Description: ensure core widgets register accessibility nodes and update bounds during layout; add roles/labels for focusable widgets.
- Files: `src/widget/accessibility.zig`, `src/event/event.zig`, `src/widget/widgets/*.zig`, `src/layout/layout.zig`
- Complexity: L
- Dependencies: P2.1, P3.1

## 5. Phase 4: Performance (renderer batching, dirty ranges, zero per-draw allocs)

### P4.1: Renderer batching improvements
- Description: reduce ANSI emissions by batching contiguous runs and minimizing style transitions during render flush.
- Files: `src/render/render.zig`
- Complexity: M
- Dependencies: P2.6

### P4.2: Dirty range propagation
- Description: propagate dirty rect updates from layout and widget updates to minimize redraw scope.
- Files: `src/render/render.zig`, `src/widget/widgets/base_widget.zig`, `src/event/event.zig`
- Complexity: M
- Dependencies: P2.1, P2.6

### P4.3: Zero per-draw allocations
- Description: audit draw paths for allocations, move temporary buffers to per-frame scratch, and enforce allocator-free render hot paths.
- Files: `src/render/render.zig`, `src/widget/widgets/label.zig`, `src/widget/widgets/button.zig`, `src/widget/widgets/checkbox.zig`, `src/layout/layout.zig`
- Complexity: L
- Dependencies: P2.6, P2.3

## 6. Phase 5: Documentation & Testing (widget catalog, app loop tutorial, golden snapshots)

### P5.1: Widget catalog
- Description: create a catalog that documents each widget, its capabilities, and example usage with screenshots or snapshot references.
- Files: `docs/WIDGET_CATALOG.md`, `docs/WIDGET_GUIDE.md`, `examples/*`
- Complexity: M
- Dependencies: P2.2, P3.1

### P5.2: Application loop tutorial
- Description: document the event loop, input handling, layout, and render flow with an end-to-end example.
- Files: `docs/APP_LOOP_TUTORIAL.md`, `README.md`, `docs/ARCHITECTURE.md`
- Complexity: S
- Dependencies: P1.1, P2.1

### P5.3: Fill unit test gaps
- Description: add unit tests for untested widgets and edge cases called out in the audit report (list, table, TabView, TextArea, InputField, ScreenManager, Chart, TreeView).
- Files: `src/widget/widgets/button.zig`, `src/widget/widgets/checkbox.zig`, `src/widget/widgets/container.zig`, `src/widget/widgets/dropdown_menu.zig`, `src/widget/widgets/label.zig`, `src/widget/widgets/modal.zig`, `src/widget/widgets/progress_bar.zig`, `src/widget/widgets/scroll_container.zig`, `src/widget/widgets/scrollbar.zig`, `src/widget/widgets/list.zig`, `src/widget/widgets/table.zig`, `src/widget/widgets/tab_view.zig`, `src/widget/widgets/text_area.zig`, `src/widget/widgets/input_field.zig`, `src/widget/widgets/screen_manager.zig`, `src/widget/widgets/chart.zig`, `src/widget/widgets/tree_view.zig`
- Complexity: L
- Dependencies: P2.2, P2.3

### P5.4: Expand golden snapshot coverage
- Description: add snapshots for core widgets and complex layouts to catch rendering regressions.
- Files: `src/testing/golden/*.snap`, `src/widget/widgets/*.zig`, `src/testing/testing.zig`
- Complexity: M
- Dependencies: P5.3, P2.3

## 7. Success Criteria (what "best Zig TUI library" means)
- API consistency: zero compile-time mismatches and documented ownership/parenting rules for all widgets.
- Event/input reliability: input decoding + event dispatch covers key, mouse, resize, drag/drop with tests for edge cases.
- Layout robustness: root traversal is deterministic, Flex/Grid containers are first-class widgets, and sizing is consistent across call paths.
- Theming and accessibility: global theme + CSS overrides work across widgets and accessibility nodes are present for focusable UI.
- Performance: render loop sustains smooth updates with minimal dirty redraws and no per-draw allocations on hot paths.
- Documentation and tests: widget catalog + app loop tutorial exist, and snapshot coverage guards core widget rendering.
