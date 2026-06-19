## Summary
What does this PR change and why?

## Testing
Mark all that apply. Use `zig build release-check` before maintainers cut or merge public-facing stability work.
- [ ] `zig fmt --check src/ examples/ build.zig`
- [ ] `zig build quality`
- [ ] `python3 scripts/interactive_example_smoke.py`
- [ ] `python3 scripts/resize_smoke.py --no-build`
- [ ] `python3 scripts/mouse_alignment_smoke.py --no-build`
- [ ] `python3 scripts/visual_repeat_check.py --count 4` for TUI-facing changes, plus contact-sheet inspection.
- [ ] `python3 scripts/check_accessibility_metadata.py`
- [ ] `python3 scripts/check_example_coverage.py`
- [ ] `python3 scripts/check_mouse_hit_coverage.py`
- [ ] `python3 scripts/check_owned_allocation_patterns.py`
- [ ] `python3 scripts/check_widget_owner_casts.py`
- [ ] `zig build release-check`
- [ ] Targeted examples/benchmarks (list):

## Checklist
- [ ] Added/updated docs or examples for user-visible changes.
- [ ] Added/updated CHANGELOG entry under `Unreleased`.
- [ ] Considered accessibility, keyboard/mouse parity, and theming impact.
- [ ] Called out platform coverage (Linux/macOS/Windows) and terminal quirks if relevant.
- [ ] Confirmed resize behavior for changed interactive paths.
- [ ] Breaking changes documented with migration notes (if any).

## Screenshots
For UI-affecting changes, include before/after captures or recordings.
