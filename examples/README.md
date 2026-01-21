# Examples Index

Run everything from the repo root. Each entry lists the `zig build` step that launches it so you get module wiring and defaults without extra flags.

Quick starts
- `examples/hello_world.zig` (`zig build hello-world`): five-line alternate-screen loop with raw-mode input and a centered label.
- `examples/demo.zig` (`zig build demo`): interactive sampler with buttons, checkbox, progress bar, list navigation, and animated status updates.

System checks
- `examples/terminal_test.zig` (`zig build terminal-test`): verify terminal capabilities, resize handling, and cursor control.
- `examples/input_test.zig` (`zig build input-test`): stream key and mouse events to the screen to confirm input wiring.
- `examples/render_test.zig` (`zig build render-test`): exercise color, style, and box drawing primitives.
- `examples/layout_test.zig` (`zig build layout-test`): lay out a handful of widgets to validate sizing math.
- `examples/widget_test.zig` (`zig build widget-test`): composite widget smoke test that renders a basic UI frame.

Widget gallery
- `examples/widget_examples/button_example.zig` (`zig build button-example`): focused button interactions and styling tweaks.
- `examples/widget_examples/dashboard_example.zig` (`zig build dashboard-example`): compact dashboard with gauges, charts, and status blocks.
- `examples/widget_examples/notifications_example.zig` (`zig build notifications-example`): toast and notification manager behavior.
- `examples/widget_examples/table_example.zig` (`zig build table-example`): sortable/searchable table with keyboard navigation.
- `examples/widget_examples/file_browser_example.zig` (`zig build file-browser-example`): tree-backed file browser with preview.
- `examples/widget_examples/file_manager_example.zig` (`zig build file-manager-example`): split-pane file manager (tree + list) interactions.
- `examples/widget_examples/form_wizard_example.zig` (`zig build form-wizard-example`): multi-step form with validation feedback.
- `examples/widget_examples/system_monitor_example.zig` (`zig build system-monitor-example`): live metrics dashboard with charts and gauges.
- `examples/widget_examples/showcase_demo.zig` (`zig build widget-showcase`): everything-in-one showcase to explore most widgets in one place.

Real-world snapshots
- `examples/realworld/htop_clone.zig` (`zig build htop-clone`): htop-inspired dashboard rendering.
- `examples/realworld/file_manager.zig` (`zig build file-manager`): single-shot render of a file manager layout.
- `examples/realworld/text_editor.zig` (`zig build text-editor`): text editor frame with status bars and gutters.
- `examples/realworld/dashboard_demo.zig` (`zig build dashboard-demo`): compact monitoring dashboard composed of core widgets.

Benchmarks
- `examples/benchmarks/render_bench.zig` (`zig build render-bench`): micro-benchmark for renderer throughput.
- `examples/benchmarks/bench_suite.zig` (`zig build bench`): broader suite covering layout and widget rendering costs.
