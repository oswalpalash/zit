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
- Repeat visual capture checker (`scripts/visual_repeat_check.py`) runs four deterministic frames per target and emits a contact sheet for flicker/drift review.
- Public build-step checker (`scripts/check_build_steps.py`) runs every non-destructive `zig build` target with per-step timeouts.
- Package manager metadata (`build.zig.zon`) with module export configured for `b.dependency("zit", .{})` consumers.
- CI matrix expanded to Linux/macOS/Windows, explicit Linux/Windows cross-smoke builds, and tag-triggered release publishing.

### Fixed
- Migrated the library, examples, benchmarks, and CI baseline to Zig 0.16.x.
- Made network I/O fail explicitly with a `.network_error` event while the Zig 0.16 transport layer is rebuilt.
- Robust terminal state management (raw mode, cursor restore, resize handling) to avoid leaving sessions in a broken state.
- Hardened input parsing for mouse, drag payloads, and bracketed paste across terminals.
- Platform reliability improvements for Windows alongside POSIX terminals.
- Bordered tables now preserve headers and row content instead of drawing borders or separators over them.
- Modals now render with proper rounded borders, respect no-border mode, and tolerate tiny layouts without underflow-prone drawing math.
- Gauges now render visible filled/empty glyphs in addition to color, so progress remains legible in screenshots and monochrome terminals.
- Labels, buttons, and checkboxes now clip by grapheme and terminal-cell width, preserving UTF-8 while avoiding premature ellipsizing for exact-fit text.
- File browser entries, tree labels, and modal titles now use the same grapheme-aware clipping path for arbitrary UTF-8 user text.
- Interactive example build steps launch real TUI demos when a TTY is available and exit cleanly under non-TTY automation.

### Docs
- Added a stability policy centered on efficiency, reliability, stability, and features.
- Comprehensive references: `docs/API.md`, `docs/WIDGET_GUIDE.md`, `docs/ARCHITECTURE.md`, and `docs/TERMINAL_COMPAT.md`.
- README quickstart, installation, feature highlights, and example commands kept in sync with the build targets.
- Integration guide covering package manager setup, vendoring, and MVC/component-oriented patterns (`docs/INTEGRATION.md`).

### Breaking Changes
- None.
