# Zit Documentation

This directory is the maintained documentation set for Zit. The README gives a
fast overview; these guides are the source of truth for behavior, integration,
and release guarantees.

The human-facing documentation format is Markdown in this directory. Generated
Zig docs are a release artifact for exported-symbol/API inspection, not the
primary docs experience.

## Start Here

| Goal | Read |
| --- | --- |
| Build a first interactive app | [APP_LOOP_TUTORIAL.md](APP_LOOP_TUTORIAL.md) |
| Find copy-paste patterns for common tasks | [COOKBOOK.md](COOKBOOK.md) |
| Debug runtime, resize, mouse, memory, or visual issues | [TROUBLESHOOTING.md](TROUBLESHOOTING.md) |
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
2. Keep [COOKBOOK.md](COOKBOOK.md) open for production app skeletons,
   cleanup, resize, mouse, memory, and visual QA recipes.
3. Run `zig build hello-world`, `zig build demo`, and one real-world example.
4. Use [WIDGET_CATALOG.md](WIDGET_CATALOG.md) to pick widgets and examples.
5. Keep [API.md](API.md) open for helper names, resize wiring, mouse
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
3. Use [TROUBLESHOOTING.md](TROUBLESHOOTING.md) to diagnose runtime behavior
   that differs between tests, PTYs, and real terminals.
4. Use [STABILITY.md](STABILITY.md) as the release checklist before shipping.

### Maintainers
1. Use [STABILITY.md](STABILITY.md) as the authoritative release gate list.
2. Keep this index updated when adding, renaming, or removing docs.
3. Run `zig build release-check` before pushing public-facing stability work.

## Documentation Quality Gates

- `python3 scripts/check_docs_links.py` validates Markdown relative links,
  same-file and cross-file heading anchors, and requires every top-level
  `docs/*.md` guide to be linked from this index.
- `python3 scripts/check_docs_commands.py` validates documented script
  invocations, build steps, and format paths against files and build steps in
  this repository.
- `python3 scripts/check_docs_zig_snippets.py` validates public Markdown Zig
  snippets do not model empty catches, panic paths, unreachable paths, or
  unchecked `DebugAllocator` cleanup.
- `python3 scripts/check_widget_coverage.py` validates widget docs against
  public widget exports, examples, snapshots, and helper APIs.
- `zig build release-check` generates API docs under `zig-out/docs-release` and
  repeated visual captures under `zig-out/visual-repeat`.
- `python3 scripts/visual_repeat_check.py --count 4` writes the contact sheet
  used for human visual review before public-facing UI changes are pushed.

## Writing Rules

- Write user-facing documentation as Markdown guides, tutorials, recipes, and
  troubleshooting notes. Do not rely on generated Zig docs to explain concepts,
  workflows, stability guarantees, or visual behavior.
- Public examples must be copy-pasteable and use explicit cleanup reporting for
  terminal restoration paths.
- Claims about stability, performance, platform support, visual behavior, or
  widget coverage need a gate, test, benchmark, example, or release verifier.
- Prefer short, direct sections with links to runnable examples over broad
  marketing prose.
