# Changelog

All notable changes to Zit are documented here. Add new entries under the `Unreleased` heading, grouped by type. When releasing, copy items into a dated section.

## Unreleased

### Added
- Rich widget catalog (tables with typeahead, context menus, tree and file browser, gauges/charts, dialogs, popups, drag targets, text inputs with bracketed paste, focus rings).
- Theming system with light/dark/high-contrast palettes and per-widget `setTheme`/role-driven colors.
- Event loop with timers, animations (easing/yoyo), background tasks, and non-blocking `tickOnce`/`pollUntil` helpers for embedding.
- Accessibility plumbing: roles, focus announcements, keyboard-first UX, and mouse parity for key widgets.
- Cross-platform terminal support, including Windows/ConPTY handling and terminal capability detection.
- Example suite and demos covering widgets, real-world dashboards, file managers, editors, and benchmarks.
- Benchmarks and testing harness wired through `zig build` to keep render paths and layouts stable.
- `zig build quality` aggregates smoke compilation, unit/snapshot tests, and benchmarks for local pre-push verification.
- Real-world snapshot regressions cover htop-style, file manager, dashboard, and editor compositions.
- Deterministic widget gallery snapshot target for screenshot-based review of core widgets and advanced controls.
- Extended deterministic widget gallery snapshot target for text entry, structured text, charting, menus, logs, indicators, and drawing primitives.
- Layout/navigation widget gallery target for container, tab, split-pane, screen-manager, overlay, date/time, image, toast, accordion, and wizard coverage.
- Public widget coverage checker (`scripts/check_widget_coverage.py`) fails when an exported widget lacks declared visual or snapshot coverage.
- DebugAllocator cleanup checker (`scripts/check_debug_allocator_cleanup.py`) fails when public examples or memory tests ignore allocator deinit status.
- Repeat visual capture checker (`scripts/visual_repeat_check.py`) runs four deterministic `--snapshot` frames per target and emits a contact sheet for flicker/drift review.
- Interactive example PTY smoke checker (`scripts/interactive_example_smoke.py`) launches every interactive example in a pseudo-terminal, waits for rendered content, sends `q`, fails on allocator/panic diagnostics, and verifies clean exit.
- Resize PTY smoke checker (`scripts/resize_smoke.py`, `zig build resize-smoke`) changes a live pseudo-terminal size and requires `input_test` to report the new geometry.
- CI script coverage checker (`scripts/check_ci_script_coverage.py`) keeps GitHub Actions script compilation aligned with release verification script coverage.
- Contribution gate checker (`scripts/check_contribution_gates.py`, `zig build contribution-gates`) keeps GitHub Actions, release verification, PR checklist, and stability docs aligned on required quality gates.
- Widget coverage checking now validates `docs/WIDGET_CATALOG.md` rows and file references so public widget docs cannot point at missing snapshots or examples.
- Full release verifier (`scripts/release_verify.py`, `zig build release-check`) runs quality, formatting, docs generation, public build steps, cross-target smoke, PTY smoke, memory cleanup checks, and visual repeat captures.
- Public build-step checker (`scripts/check_build_steps.py`) runs every non-destructive `zig build` target with per-step timeouts.
- Public build-step checker supports `--skip-interactive` for Windows CI shells that cannot provide PTY semantics for TUI run targets.
- DebugAllocator cleanup checker now covers README and Markdown docs so public snippets cannot silently ignore allocator cleanup status.
- `Application.bindResize` and `Application.handleResize` provide automatic terminal resize handling for renderer buffers, root layout, and optional `ReflowManager` state.
- `Application.bindInput`, `Application.pollInputOnce`, and `Application.tickOnce` now let the app loop own input polling so resize events automatically reach the renderer/reflow/root path without per-example resize forwarding.
- `InputHandler` now periodically polls terminal geometry in addition to consuming SIGWINCH, catching missed signal and ConPTY-style resize changes.
- Package manager metadata (`build.zig.zon`) with module export configured for `b.dependency("zit", .{})` consumers.
- CI matrix expanded to Linux/macOS/Windows, explicit Linux/Windows cross-smoke builds, and tag-triggered release publishing.
- README screenshot generation now emits polished deterministic SVG previews for the system monitor, file manager, and widget showcase.

### Fixed
- Non-blocking stdin reads now treat EAGAIN/EWOULDBLOCK as no-event instead of crashing interactive loops.
- Migrated the library, examples, benchmarks, and CI baseline to Zig 0.16.x.
- Made network I/O fail explicitly with a `.network_error` event while the Zig 0.16 transport layer is rebuilt.
- Robust terminal state management (raw mode, cursor restore, resize handling) to avoid leaving sessions in a broken state.
- POSIX SIGWINCH handling is now reference-counted and restored on terminal teardown, preventing Zit from leaving process-global signal handlers installed after `Terminal.deinit`.
- `Terminal.deinit` now attempts every registered cleanup action before returning the first error, reducing the chance of stranded raw mode, hidden cursor, mouse tracking, alternate screen, or signal state.
- Hardened input parsing for mouse, drag payloads, and bracketed paste across terminals.
- Platform reliability improvements for Windows alongside POSIX terminals.
- Bordered tables now preserve headers and row content instead of drawing borders or separators over them.
- Modals now render with proper rounded borders, respect no-border mode, and tolerate tiny layouts without underflow-prone drawing math.
- Gauges now render visible filled/empty glyphs in addition to color, so progress remains legible in screenshots and monochrome terminals.
- Labels, buttons, and checkboxes now clip by grapheme and terminal-cell width, preserving UTF-8 while avoiding premature ellipsizing for exact-fit text.
- File browser entries, tree labels, and modal titles now use the same grapheme-aware clipping path for arbitrary UTF-8 user text.
- Interactive example build steps launch real TUI demos when a TTY is available and exit cleanly under non-TTY automation.
- Real-world and widget-gallery examples now default to interactive terminal sessions that render their UI until `q`; automation uses explicit `--snapshot` mode.
- Terminal and input diagnostics now flush their initial frames before waiting for raw-mode input.
- Grapheme rendering no longer returns slices into by-value temporaries, fixing corrupted terminal frames and invalid borrowed memory during render output assembly.
- File browser path normalization now frees realpath sentinel allocations with the correct allocation shape.
- Examples and memory tests now assert `DebugAllocator.deinit() == .ok` so leaks and allocator misuse fail deterministically.
- Table string interning now migrates existing text transactionally and keeps hash-map index storage out of the string arena, reducing retained arena capacity and making memory benchmark output comparable.
- MemorySafety now frees and resizes the exact backing allocation length used for canary storage, uses byte-wise canaries for odd-sized allocations, and fails transactionally if allocation tracking cannot be recorded.
- MemoryOptimizer now tracks live cache-line ownership instead of casting arbitrary small frees into cache nodes, preventing backing allocation corruption and freeing live optimized blocks on teardown.
- Memory debugger, ownership, safety, optimizer, and memory-manager suites now compile through the primary `zig build test` target, preventing dormant memory regressions from bypassing release checks.
- Background tasks are now owned by `Application`, joined on shutdown, and paired with queued custom-event destructor cleanup so teardown cannot leave detached workers using a destroyed event queue.
- Event input binding tests now use cross-platform standard handles, fixing the Windows CI compile failure in `zig build quality`.
- Windows CI now keeps compile/test/script coverage while avoiding non-PTY interactive run-target hangs in the matrix public build-step sweep.
- Label, button, checkbox, progress bar, paragraph, markdown, popup, input-field placeholder, and text-area placeholder setters now invalidate retained render state after visible changes.
- Text-owning widget setters now duplicate replacement buffers before releasing current buffers, with allocation-failure regression coverage for stable rollback behavior.
- The interactive demo layout now presents a structured application frame while continuing to stay live until `q`.

### Docs
- Added a stability policy centered on efficiency, reliability, stability, and features.
- Added polished graphical README previews for the system monitor, file manager, and widget showcase examples.
- Comprehensive references: `docs/API.md`, `docs/WIDGET_GUIDE.md`, `docs/ARCHITECTURE.md`, and `docs/TERMINAL_COMPAT.md`.
- README quickstart, installation, feature highlights, and example commands kept in sync with the build targets.
- Integration guide covering package manager setup, vendoring, and MVC/component-oriented patterns (`docs/INTEGRATION.md`).

### Breaking Changes
- None.
