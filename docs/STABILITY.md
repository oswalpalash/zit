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
- Any terminal input protocol enabled by `Terminal` must have matching decoder coverage, idempotent per-instance ownership, symmetric cleanup, and an end-to-end PTY release check for negotiation, input, and restoration.
- Windows input protocols must require independently negotiated VT input and output modes; console-mode changes made during initialization or partial raw-mode setup remain explicit cleanup obligations.
- Input sequences must tolerate continuation bytes split across terminal reads with a bounded, configurable wait. The PTY gate injects protocol bytes individually, and the native Windows matrix exercises wait timeout/readiness behavior.
- Input polling must distinguish ordinary timeouts from transport failure. Hangup, invalid-descriptor, poll, and read errors must propagate instead of becoming no-event, Escape, or unknown-key results.
- Bound resize handling must publish renderer dimensions and widget geometry as one transaction; allocation or layout failure preserves the previously committed size on both sides.
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
- The `windows-latest` CI matrix must run `zig build quality` natively so Windows-only input wait tests execute; cross-smoke compilation is additional coverage, not a substitute.
- `python3 scripts/check_build_steps.py`
- `python3 scripts/check_build_steps.py --skip-interactive`
- `python3 scripts/check_debug_allocator_cleanup.py`
- `python3 scripts/check_docs_commands.py` to require public Markdown command references to point at existing scripts, build steps, and format paths.
- `python3 scripts/check_docs_links.py` to require public Markdown relative links, heading anchors, and local image targets to resolve and every top-level docs guide to appear in `docs/README.md`.
- `python3 scripts/check_docs_zig_snippets.py` derives public module symbols from `src/main.zig` and requires Markdown Zig snippets to reference exported APIs, use notifying widget lifecycle and ownership helpers, avoid panic/unreachable patterns, and check `DebugAllocator` cleanup.
- `python3 scripts/check_draw_layout_boundary.py` to require widget draw callbacks to consume geometry prepared by layout instead of invoking child layout during rendering.
- `zig build draw-layout-boundary`
- `python3 scripts/check_ci_script_coverage.py`
- `zig build ci-script-coverage`
- `zig build test` runs all 766 official Unicode 17 extended-grapheme conformance cases and exhaustively compares generated East Asian `W/F` classifications across every Unicode codepoint; generated tables and fixtures must declare the same Unicode version.
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
- `python3 scripts/check_widget_lifecycle_mutation.py` to require production widget code and public examples to use lifecycle setters instead of direct focus, enabled, visibility, or TreeView expansion mutation.
- `python3 scripts/check_widget_parent_attachment.py` to require production widget code and public examples to mutate parent links through `Widget.attachTo` and owner-checked `Widget.detachFrom`, while allowing test-only invalid-state setup.
- `python3 scripts/interactive_example_smoke.py` to verify every public interactive example renders and quits cleanly, plus a Kitty-capable PTY run that injects focus-in/focus-out and CSI-u Ctrl+C one byte at a time, requires their decoding, and observes matching flag-1 and focus-reporting setup and cleanup sequences.
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
- `python3 scripts/check_terminal_state_cleanup.py` requires interactive examples to restore raw mode, mouse tracking, cursor visibility, and alternate-screen state they enable; rejects empty `catch {}` blocks on terminal cleanup paths; and enforces instance-owned input/output handles, terminal-owned mouse state, independent Windows VT input/output negotiation and restoration, bounded cross-platform input continuations with fragmented PTY and native Windows wait coverage, explicit POSIX poll/read error propagation, pre-write cleanup obligations, and VT-mode teardown before raw-mode restoration.
- `python3 scripts/check_unreachable_catches.py` rejects `catch unreachable` so recoverable errors are propagated or handled instead of becoming panics.
- `python3 scripts/check_draw_layout_boundary.py` rejects child layout calls from production widget draw callbacks so redraws cannot republish geometry or accessibility bounds.
- `python3 scripts/check_widget_parent_attachment.py` rejects direct `Widget.parent` assignments outside the guarded ownership primitives so new composite widgets cannot silently reparent children or clear links owned elsewhere.
- Public helpers that accept an allocator and return text, such as `KeyEvent.getName`, must return allocator-owned memory on every branch so callers can use one cleanup rule.
- Registry-style APIs that duplicate caller data, such as shortcuts and summary materialization, must be transactional under `OutOfMemory`: no leaked partial allocations and no index maps left inconsistent with stored entries.
- Navigation stacks that own copied route/screen metadata must reserve collection and transition capacity before taking ownership, then roll back appended entries if a later hook or transition setup fails.
- `ScreenManager` rapid navigation must settle an active transition before replacing its descriptor or handles, and all fallible preflight must complete before settlement so allocation/layout failure preserves the in-flight transition.
- Rejected `ScreenManager` candidates must recover public layout/dirty/visibility state and republish prior accessibility bounds, and candidates already owned by another visibility animator must be rejected before attachment.
- Failed `Widget.layout` calls must restore the widget's public rect and dirty-region state and must not publish failed accessibility bounds. `Container`, `FlexContainer`, `GridContainer`, `TabView`, `ScrollContainer`, `SplitPane`, and `ScreenManager` use preflighted reusable or fixed stack snapshots to restore direct-child public layout state plus previously published accessibility bounds when a later child fails; `TabView` covers all loaded content, including inactive tabs, `ScrollContainer` preserves its content-size cache, and `ScreenManager` restores its cached last layout rect. Other composite vtables remain responsible for equivalent child and private-cache consistency.
- `TreeView` insertion keeps the visible-node cache current without rebuilding, and `setExpanded` validates indices and reserves full cache capacity before changing node state. Its draw callback must remain allocation-free and must not normalize stored selection or scroll state.
- `Paragraph.draw` streams wrapped slices directly from owned text without temporary line collections. Wrapping and alignment use grapheme-cell widths so UTF-8 clusters are never split at byte boundaries, and drawing must remain allocation-free regardless of text length or scroll offset.
- `InputField` keeps byte offsets internally while navigation, deletion, cursor placement, and horizontal scrolling operate on grapheme boundaries and terminal-cell columns. Focused drawing must keep the caret visible and remain allocation-free.
- `TextArea` keeps public/edit offsets byte-based but normalizes carets and selection endpoints to grapheme boundaries; cursor columns, vertical movement, horizontal scrolling, and clipping use terminal-cell widths. Draw merges sorted cursor positions with a stack-only iterator and must remain allocation-free. Backspace/delete removes complete grapheme clusters at every caret rather than individual codepoints or bytes.
- `Renderer.drawTextDir` admits prepared text by grapheme count rather than UTF-8 byte count and never grows its scratch list during draw. Prepared and over-capacity fallback rendering must advance by capability-adjusted terminal-cell widths, and one-cell overlays must clear displaced wide-glyph continuation cells. Measurement and iteration share generated Unicode 17 extended-grapheme boundaries and terminal width data. The width policy is East Asian `W/F` plus default emoji, with ambiguous characters narrow unless explicit presentation overrides them; official fixtures are the release regression contract. Fixed-size cells store at most 32 UTF-8 bytes per grapheme; longer clusters must preserve full-cluster metrics while storing a deterministic, valid UTF-8 fallback. Unicode controls must become printable fallback cells before ANSI output, and disabled Unicode, emoji, or double-width capabilities must never retain an unsupported glyph with falsified one-cell geometry.
- Catalog/map-style APIs that accept caller-provided string keys must either document borrowed lifetimes explicitly or own key copies; stable public catalogs default to owning keys and values transactionally.
- Widget initializers that allocate after `allocator.create` must use `errdefer` cleanup or a fully initialized `deinit` path before any later fallible operation; `check_owned_allocation_patterns.py` enforces this for owned string copies before `self.*` initialization.
- Review README, API docs, examples, and changelog for claims that exceed tested behavior.

Hosted CI runs the matrix public build-step checker with `--skip-interactive`
because GitHub shell runners do not provide consistent PTY semantics for TUI
run targets across operating systems. Those same interactive targets remain
covered by dedicated PTY jobs: `interactive_example_smoke.py`,
`resize_smoke.py`, `mouse_alignment_smoke.py`, and the repeated visual capture
suite.
