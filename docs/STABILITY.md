# Stability Policy

Zit is governed by four tenets, in priority order:

1. Efficiency
2. Reliability
3. Stability
4. Features

Features are welcome only when they preserve the first three tenets.

## Zig Baseline

- Supported compiler line: Zig 0.16.x.
- `build.zig.zon` is the source of truth for the minimum supported compiler.
- CI must compile and test on Linux, macOS, and Windows before a release tag is cut.
- CI must run `zig build release-check` on pull requests, `main` pushes, and release tags so the strongest public gate is not reserved for releases only.

## Public API

- Stable public modules are `terminal`, `input`, `render`, `layout`, `event`, `widget`, `memory`, `testing`, `i18n`, and `quickstart`.
- Breaking changes are allowed before 1.0 only when they harden ownership, lifecycle, error handling, portability, or API consistency.
- Every breaking change needs a changelog entry and migration note.
- Experimental or incomplete APIs must be documented as such before being promoted in README examples.

## Reliability Bar

Before a feature is promoted as stable, it needs:

- Allocator-aware `init`/`deinit` behavior with clear ownership rules.
- Interactive examples must exit without `DebugAllocator` diagnostics, panic output, or mismatched allocation/free sizes.
- Tests for lifecycle, bounds, zero-size layout, resize behavior, and error paths.
- Snapshot coverage when rendering output is user-visible.
- Benchmarks must enforce conservative budgets for render throughput, large-table scrolling, input decoding, and memory-retention optimizations.
- `ScreenManager` transition rendering must preserve stack order without allocating per frame.
- Keyboard accessibility, and mouse support where the widget exposes pointer behavior.
- Terminal mouse protocol coordinates must be normalized at the input boundary so widget hit tests use the same zero-based coordinate system as rendering and layout.
- No unexpected panics for user input, terminal size changes, or normal rendering paths.

## Release Checklist

- `zig build release-check`

`zig build release-check` is the authoritative aggregate gate. It runs the checks below and writes generated API docs under `zig-out/docs-release` plus visual captures under `zig-out/visual-repeat`.

- `zig build quality`
- `zig build contribution-gates`
- `zig fmt --check src/ examples/ build.zig`
- `zig build smoke`
- `zig build test`
- `zig build bench`
- `zig build bench` must fail when conservative performance budgets are exceeded; the budgets are intentionally loose enough for CI variance but tight enough to catch algorithmic regressions.
- `zig build-lib src/main.zig -femit-docs -fno-emit-bin`
- `zig build smoke -Dtarget=x86_64-linux`
- `zig build smoke -Dtarget=x86_64-windows`
- `python3 scripts/check_build_steps.py`
- `python3 scripts/check_build_steps.py --skip-interactive`
- `python3 scripts/check_debug_allocator_cleanup.py`
- `python3 scripts/check_docs_commands.py` to require public Markdown command references to point at existing scripts, build steps, and format paths.
- `python3 scripts/check_docs_links.py` to require public Markdown relative links, heading anchors, and local image targets to resolve and every top-level docs guide to appear in `docs/README.md`.
- `python3 scripts/check_docs_zig_snippets.py` to require public Markdown Zig snippets to avoid empty catches, panic/unreachable paths, and unchecked `DebugAllocator` cleanup.
- `python3 scripts/check_ci_script_coverage.py`
- `zig build ci-script-coverage`
- `python3 scripts/check_contribution_gates.py`
- `python3 scripts/check_accessibility_metadata.py` to require every public widget export to expose semantic accessibility metadata for focus announcements and assistive integrations.
- `python3 scripts/check_application_input_binding.py`
- `python3 scripts/check_example_coverage.py`
- `python3 scripts/check_interactive_alt_screen.py`
- `python3 scripts/check_io_event_ownership_docs.py`
- `python3 scripts/check_mouse_coordinate_contract.py` to require terminal mouse protocol decoders to route raw one-based positions through `MouseEvent.fromTerminalCoordinates` instead of open-coding normalization.
- `python3 scripts/check_owned_allocation_patterns.py`
- `python3 scripts/check_terminal_state_cleanup.py`
- `python3 scripts/check_unreachable_catches.py`
- `python3 scripts/check_widget_coverage.py` to require every public widget export to have a catalog row, coverage reference, valid documented file paths, and every public widget factory/helper to appear in `docs/API.md`.
- `python3 scripts/check_widget_owner_casts.py`
- `python3 scripts/check_widget_lifecycle_mutation.py` to require production widget code and public examples to use lifecycle setters instead of direct focus, enabled, or visibility mutation.
- `python3 scripts/check_widget_parent_attachment.py` to require production widget code and public examples to mutate parent links through `Widget.attachTo` and owner-checked `Widget.detachFrom`, while allowing test-only invalid-state setup.
- `python3 scripts/interactive_example_smoke.py`
- `python3 scripts/resize_smoke.py --no-build` to verify `input_test` receives live PTY resize events, every public interactive example survives rapid tiny-size stress down to 1x1, redraws a visible `resize: WxH` marker at the final geometry, and quits cleanly.
- `python3 scripts/mouse_alignment_smoke.py --no-build` to verify real SGR mouse input maps terminal 1-based coordinates to Zit screen coordinates and clicks the rendered demo button only at its actual row.
- `InputHandler.pollEvent` and `decodeEventFromBytes` are the input boundary for terminal mouse normalization: returned mouse events must already be zero-based and aligned with renderer/widget layout rects, numeric CSI/SGR parameters must be complete and validated before arithmetic, legacy X10/normal tracking bytes must be validated before arithmetic, `translateMouseCoordinates` must remain idempotent for those events, and raw terminal coordinates must use `translateTerminalMouseCoordinates` or `MouseEvent.fromTerminalCoordinates`.
- `python3 scripts/check_mouse_hit_coverage.py` to require every public mouse-capable widget to declare direct hit-test coverage before release.
- `python3 scripts/visual_repeat_check.py --count 4`
- Visually inspect the generated contact sheet for the real-world examples (`htop-clone`, `file-manager`, `text-editor`, `dashboard-demo`) and widget galleries (`widget-gallery`, `widget-gallery-extended`, `widget-gallery-layouts`) for alignment, hierarchy, spacing, clipped or overlapping text, and frame-to-frame drift.
- `python3 scripts/check_application_input_binding.py` requires examples that initialize `Application` and `InputHandler` together to route polling through `Application.bindInput` / `pollInputOnce`.
- `python3 scripts/check_example_coverage.py` keeps the build target list, interactive PTY smoke manifest, public build-step classification, and repeated visual target manifest in sync.
- `python3 scripts/check_interactive_alt_screen.py` requires every interactive example to enter and exit the alternate screen so rendered rows and terminal mouse coordinates share a stable viewport origin.
- `python3 scripts/check_io_event_ownership_docs.py` rejects stale examples that call `deinit()` directly on manager-owned file watchers or network contexts returned by `watchFile` / `connectToServer`.
- `python3 scripts/check_owned_allocation_patterns.py` rejects non-transactional owned-string append and replacement patterns so allocator failures preserve existing widget state.
- `python3 scripts/check_terminal_state_cleanup.py` requires interactive examples to restore raw mode, mouse tracking, cursor visibility, and alternate-screen state they enable, and rejects empty `catch {}` blocks on terminal cleanup paths.
- `python3 scripts/check_unreachable_catches.py` rejects `catch unreachable` so recoverable errors are propagated or handled instead of becoming panics.
- `python3 scripts/check_widget_parent_attachment.py` rejects direct `Widget.parent` assignments outside the guarded ownership primitives so new composite widgets cannot silently reparent children or clear links owned elsewhere.
- Public helpers that accept an allocator and return text, such as `KeyEvent.getName`, must return allocator-owned memory on every branch so callers can use one cleanup rule.
- Registry-style APIs that duplicate caller data, such as shortcuts and summary materialization, must be transactional under `OutOfMemory`: no leaked partial allocations and no index maps left inconsistent with stored entries.
- Navigation stacks that own copied route/screen metadata must reserve collection and transition capacity before taking ownership, then roll back appended entries if a later hook or transition setup fails.
- `ScreenManager` rapid navigation must settle an active transition before replacing its descriptor or handles, and all fallible preflight must complete before settlement so allocation/layout failure preserves the in-flight transition.
- Rejected `ScreenManager` candidates must recover public layout/dirty/visibility state and republish prior accessibility bounds, and candidates already owned by another visibility animator must be rejected before attachment.
- Failed `Widget.layout` calls must restore the widget's public rect and dirty-region state and must not publish failed accessibility bounds. `Container`, `FlexContainer`, `GridContainer`, `TabView`, `ScrollContainer`, and `ScreenManager` use preflighted reusable or fixed stack snapshots to restore direct-child public layout state plus previously published accessibility bounds when a later child fails; `TabView` covers all loaded content, including inactive tabs, `ScrollContainer` preserves its content-size cache, and `ScreenManager` restores its cached last layout rect. Other composite vtables remain responsible for equivalent child and private-cache consistency.
- Catalog/map-style APIs that accept caller-provided string keys must either document borrowed lifetimes explicitly or own key copies; stable public catalogs default to owning keys and values transactionally.
- Widget initializers that allocate after `allocator.create` must use `errdefer` cleanup or a fully initialized `deinit` path before any later fallible operation; `check_owned_allocation_patterns.py` enforces this for owned string copies before `self.*` initialization.
- Review README, API docs, examples, and changelog for claims that exceed tested behavior.

Hosted CI runs the matrix public build-step checker with `--skip-interactive`
because GitHub shell runners do not provide consistent PTY semantics for TUI
run targets across operating systems. Those same interactive targets remain
covered by dedicated PTY jobs: `interactive_example_smoke.py`,
`resize_smoke.py`, `mouse_alignment_smoke.py`, and the repeated visual capture
suite.
