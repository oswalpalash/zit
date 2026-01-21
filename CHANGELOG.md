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
- Package manager metadata (`build.zig.zon`) with module export configured for `b.dependency("zit", .{})` consumers.
- CI matrix expanded to Linux/macOS/Windows plus tag-triggered release publishing.

### Fixed
- Robust terminal state management (raw mode, cursor restore, resize handling) to avoid leaving sessions in a broken state.
- Hardened input parsing for mouse, drag payloads, and bracketed paste across terminals.
- Platform reliability improvements for Windows alongside POSIX terminals.

### Docs
- Comprehensive references: `docs/API.md`, `docs/WIDGET_GUIDE.md`, `docs/ARCHITECTURE.md`, and `docs/TERMINAL_COMPAT.md`.
- README quickstart, installation, feature highlights, and example commands kept in sync with the build targets.
- Integration guide covering package manager setup, vendoring, and MVC/component-oriented patterns (`docs/INTEGRATION.md`).

### Breaking Changes
- None.
