# Zit Documentation

This directory is the maintained documentation set for Zit. The README gives a
fast overview; these guides are the source of truth for behavior, integration,
and release guarantees.

## Start Here

| Goal | Read |
| --- | --- |
| Build a first interactive app | [APP_LOOP_TUTORIAL.md](APP_LOOP_TUTORIAL.md) |
| Look up public APIs and helper names | [API.md](API.md) |
| Choose widgets and examples | [WIDGET_CATALOG.md](WIDGET_CATALOG.md) |
| Build or review a custom widget | [WIDGET_GUIDE.md](WIDGET_GUIDE.md) |
| Embed Zit into another loop or renderer | [INTEGRATION.md](INTEGRATION.md) |
| Understand architecture and ownership boundaries | [ARCHITECTURE.md](ARCHITECTURE.md) |
| Debug terminal/platform behavior | [TERMINAL_COMPAT.md](TERMINAL_COMPAT.md) |
| Check release/stability expectations | [STABILITY.md](STABILITY.md) |

## Learning Paths

### App Builders
1. Read [APP_LOOP_TUTORIAL.md](APP_LOOP_TUTORIAL.md).
2. Run `zig build hello-world`, `zig build demo`, and one real-world example.
3. Use [WIDGET_CATALOG.md](WIDGET_CATALOG.md) to pick widgets and examples.
4. Keep [API.md](API.md) open for helper names, resize wiring, mouse
   coordinates, cleanup reporting, timers, and memory stats.

### Widget Authors
1. Read [WIDGET_GUIDE.md](WIDGET_GUIDE.md) for lifecycle, vtable, event, theme,
   accessibility, and ownership patterns.
2. Add visual or snapshot coverage referenced from
   [WIDGET_CATALOG.md](WIDGET_CATALOG.md).
3. Run `zig build widget-coverage`, `zig build mouse-hit-coverage`, and
   `zig build quality`.

### Integrators
1. Read [INTEGRATION.md](INTEGRATION.md) for non-blocking loops, renderer
   ownership, and resize handoff.
2. Read [TERMINAL_COMPAT.md](TERMINAL_COMPAT.md) for terminal capability and
   platform notes.
3. Use [STABILITY.md](STABILITY.md) as the release checklist before shipping.

### Maintainers
1. Use [STABILITY.md](STABILITY.md) as the authoritative release gate list.
2. Keep this index updated when adding, renaming, or removing docs.
3. Run `zig build release-check` before pushing public-facing stability work.

## Documentation Quality Gates

- `python3 scripts/check_docs_links.py` validates Markdown relative links and
  requires every top-level `docs/*.md` guide to be linked from this index.
- `python3 scripts/check_widget_coverage.py` validates widget docs against
  public widget exports, examples, snapshots, and helper APIs.
- `zig build release-check` generates API docs under `zig-out/docs-release` and
  repeated visual captures under `zig-out/visual-repeat`.

## Writing Rules

- Public examples must be copy-pasteable and use explicit cleanup reporting for
  terminal restoration paths.
- Claims about stability, performance, platform support, visual behavior, or
  widget coverage need a gate, test, benchmark, example, or release verifier.
- Prefer short, direct sections with links to runnable examples over broad
  marketing prose.
