# Contributing to Zit

Thanks for helping make Zit the best Zig TUI toolkit. This guide covers how to propose changes, style expectations, and the checks we run before merging.

## How to propose changes
- Prefer an issue first for new features or breaking changes; link it from your PR.
- Keep PRs small and focused. One feature or fix per PR is easiest to review.
- Update the docs and examples that showcase your change (API docs, widget guide, quick starts).
- Add a changelog entry under the `Unreleased` section that explains the user-visible impact.
- Follow the PR template checklist and respond to review feedback promptly.

## Coding style
- Run `zig fmt --check src/` before pushing; format fixes go in their own commit whenever possible.
- Match the library patterns: explicit `init`/`deinit`, allocator-aware APIs, no hidden global state, and surface errors instead of panicking.
- Keep widgets themable: expose `setTheme`/`setPalette` where applicable and prefer role-driven colors over hardcoded values.
- Maintain accessibility: keep focus rings and announcements wired through `Application`; add keyboard paths alongside mouse support.
- Keep async work non-blocking: favor timers/animations/background tasks over busy loops.
- Add comments only where behavior is non-obvious (edge cases, terminal quirks, platform-specific code paths).

## Tests and checks
- Required for every PR: `zig fmt --check src/` and `zig build`.
- Strongly recommended: `zig build test` (unit/integration tests) and any relevant examples, e.g. `zig build table-example` or `zig build demo` when touching widgets.
- For performance-sensitive changes, compare `zig build render-bench` or `zig build bench` before/after and note regressions.
- If a change needs platform coverage (e.g. Windows/ConPTY, mouse handling), mention how you validated it in the PR.

## Pull request expectations
- Fill out the PR template, including motivation, testing notes, and screenshots for visual changes.
- Keep the public API stable; call out any breaking changes explicitly and document migration steps.
- Add new widgets/behaviors to examples and docs so users can discover them quickly.
- Include reproduction steps in bug fix PRs and, when possible, add a failing test that your fix makes pass.

## Filing issues
- Use the issue templates. Include Zig version, OS/terminal details, terminal capabilities (mouse, bracketed paste), and whether you’re on Windows/ConPTY.
- For bugs, share minimal repro code and terminal recordings/screenshots when helpful.
- For feature requests, describe the user story and how it should feel in the TUI (keyboard/mouse paths, accessibility expectations, theming knobs).
