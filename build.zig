const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // Create a module for the library
    const zit_module = b.addModule("zit", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "zit",
        .root_module = zit_module,
        .linkage = .static,
    });

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const main_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .name = "zit-tests",
    });

    const run_main_tests = b.addRunArtifact(main_tests);

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build test`
    // This will evaluate the `test` step rather than the default, which is "install".
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);

    const smoke_step = b.step("smoke", "Compile all examples and benchmarks without running them");
    smoke_step.dependOn(&lib.step);

    // Add terminal test example
    const terminal_test_module = b.createModule(.{
        .root_source_file = b.path("examples/terminal_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    terminal_test_module.addImport("zit", zit_module);

    const terminal_test = b.addExecutable(.{
        .name = "terminal_test",
        .root_module = terminal_test_module,
    });

    // Install the example binary
    b.installArtifact(terminal_test);
    smoke_step.dependOn(&terminal_test.step);

    const run_terminal_test = b.addRunArtifact(terminal_test);
    const terminal_test_step = b.step("terminal-test", "Run the terminal test example");
    terminal_test_step.dependOn(&run_terminal_test.step);

    // Add input test example
    const input_test_module = b.createModule(.{
        .root_source_file = b.path("examples/input_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    input_test_module.addImport("zit", zit_module);

    const input_test = b.addExecutable(.{
        .name = "input_test",
        .root_module = input_test_module,
    });

    // Install the example binary
    b.installArtifact(input_test);
    smoke_step.dependOn(&input_test.step);

    const run_input_test = b.addRunArtifact(input_test);
    const input_test_step = b.step("input-test", "Run the input handling test example");
    input_test_step.dependOn(&run_input_test.step);

    // Add render test example
    const render_test_module = b.createModule(.{
        .root_source_file = b.path("examples/render_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    render_test_module.addImport("zit", zit_module);

    const render_test = b.addExecutable(.{
        .name = "render_test",
        .root_module = render_test_module,
    });

    // Install the example binary
    b.installArtifact(render_test);
    smoke_step.dependOn(&render_test.step);

    const run_render_test = b.addRunArtifact(render_test);
    const render_test_step = b.step("render-test", "Run the rendering test example");
    render_test_step.dependOn(&run_render_test.step);

    // Add layout test example
    const layout_test_module = b.createModule(.{
        .root_source_file = b.path("examples/layout_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    layout_test_module.addImport("zit", zit_module);

    const layout_test = b.addExecutable(.{
        .name = "layout_test",
        .root_module = layout_test_module,
    });

    // Install the example binary
    b.installArtifact(layout_test);
    smoke_step.dependOn(&layout_test.step);

    const run_layout_test = b.addRunArtifact(layout_test);
    const layout_test_step = b.step("layout-test", "Run the layout system test example");
    layout_test_step.dependOn(&run_layout_test.step);

    // Add demo example
    const demo_module = b.createModule(.{
        .root_source_file = b.path("examples/demo.zig"),
        .target = target,
        .optimize = optimize,
    });
    demo_module.addImport("zit", zit_module);

    const demo = b.addExecutable(.{
        .name = "demo",
        .root_module = demo_module,
    });

    // Install the example binary
    b.installArtifact(demo);
    smoke_step.dependOn(&demo.step);

    const run_demo = b.addRunArtifact(demo);
    const demo_step = b.step("demo", "Run the comprehensive demo example");
    demo_step.dependOn(&run_demo.step);

    // Add widget test example
    const widget_test_module = b.createModule(.{
        .root_source_file = b.path("examples/widget_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    widget_test_module.addImport("zit", zit_module);

    const widget_test = b.addExecutable(.{
        .name = "widget_test",
        .root_module = widget_test_module,
    });

    // Install the example binary
    b.installArtifact(widget_test);
    smoke_step.dependOn(&widget_test.step);

    const run_widget_test = b.addRunArtifact(widget_test);
    const widget_test_step = b.step("widget-test", "Run the widget test example");
    widget_test_step.dependOn(&run_widget_test.step);

    // Add hello world quickstart example
    const hello_module = b.createModule(.{
        .root_source_file = b.path("examples/hello_world.zig"),
        .target = target,
        .optimize = optimize,
    });
    hello_module.addImport("zit", zit_module);

    const hello_exe = b.addExecutable(.{
        .name = "hello_world",
        .root_module = hello_module,
    });

    b.installArtifact(hello_exe);
    smoke_step.dependOn(&hello_exe.step);

    const run_hello = b.addRunArtifact(hello_exe);
    const hello_step = b.step("hello-world", "Run the 5-line hello world example");
    hello_step.dependOn(&run_hello.step);

    // Add widget examples
    const widget_examples = [_]struct {
        name: []const u8,
        description: []const u8,
        path: []const u8,
        step_name: []const u8,
    }{
        .{ .name = "button", .description = "Run the button widget example", .path = "examples/widget_examples/button_example.zig", .step_name = "button-example" },
        .{ .name = "dashboard", .description = "Run the dashboard widget example", .path = "examples/widget_examples/dashboard_example.zig", .step_name = "dashboard-example" },
        .{ .name = "notifications", .description = "Run the notifications widget example", .path = "examples/widget_examples/notifications_example.zig", .step_name = "notifications-example" },
        .{ .name = "table_widget", .description = "Run the table widget example with typeahead", .path = "examples/widget_examples/table_example.zig", .step_name = "table-example" },
        .{ .name = "file_browser", .description = "Run the file browser widget example", .path = "examples/widget_examples/file_browser_example.zig", .step_name = "file-browser-example" },
        .{ .name = "file_manager_example", .description = "Run the tree+list file manager example", .path = "examples/widget_examples/file_manager_example.zig", .step_name = "file-manager-example" },
        .{ .name = "form_wizard", .description = "Run the multi-step form example with validation", .path = "examples/widget_examples/form_wizard_example.zig", .step_name = "form-wizard-example" },
        .{ .name = "system_monitor", .description = "Run the live system monitor dashboard example", .path = "examples/widget_examples/system_monitor_example.zig", .step_name = "system-monitor-example" },
        .{ .name = "widget_showcase", .description = "Run the full widget showcase demo", .path = "examples/widget_examples/showcase_demo.zig", .step_name = "widget-showcase" },
    };

    for (widget_examples) |example| {
        const example_module = b.createModule(.{
            .root_source_file = b.path(example.path),
            .target = target,
            .optimize = optimize,
        });
        example_module.addImport("zit", zit_module);

        const exe = b.addExecutable(.{
            .name = example.name,
            .root_module = example_module,
        });

        // Install the example binary
        b.installArtifact(exe);
        smoke_step.dependOn(&exe.step);

        const run_exe = b.addRunArtifact(exe);

        // Add a separate step to run the interactive example.
        const exe_step = b.step(example.step_name, example.description);
        exe_step.dependOn(&run_exe.step);
    }

    const real_examples = [_]struct {
        name: []const u8,
        description: []const u8,
        path: []const u8,
        step_name: []const u8,
    }{
        .{ .name = "htop_clone", .description = "Run an interactive htop-inspired dashboard example", .path = "examples/realworld/htop_clone.zig", .step_name = "htop-clone" },
        .{ .name = "file_manager", .description = "Run an interactive file manager layout example", .path = "examples/realworld/file_manager.zig", .step_name = "file-manager" },
        .{ .name = "text_editor", .description = "Run an interactive text editor frame example", .path = "examples/realworld/text_editor.zig", .step_name = "text-editor" },
        .{ .name = "dashboard_demo", .description = "Run an interactive compact dashboard example", .path = "examples/realworld/dashboard_demo.zig", .step_name = "dashboard-demo" },
        .{ .name = "widget_gallery", .description = "Run an interactive core widget gallery example", .path = "examples/realworld/widget_gallery.zig", .step_name = "widget-gallery" },
        .{ .name = "widget_gallery_extended", .description = "Run an interactive extended widget gallery example", .path = "examples/realworld/widget_gallery_extended.zig", .step_name = "widget-gallery-extended" },
        .{ .name = "widget_gallery_layouts", .description = "Run an interactive layout, navigation, and overlay widget gallery example", .path = "examples/realworld/widget_gallery_layouts.zig", .step_name = "widget-gallery-layouts" },
    };

    for (real_examples) |example| {
        const example_module = b.createModule(.{
            .root_source_file = b.path(example.path),
            .target = target,
            .optimize = optimize,
        });
        example_module.addImport("zit", zit_module);

        const exe = b.addExecutable(.{
            .name = example.name,
            .root_module = example_module,
        });

        b.installArtifact(exe);
        smoke_step.dependOn(&exe.step);

        const run_exe = b.addRunArtifact(exe);
        run_exe.step.dependOn(b.getInstallStep());

        const exe_step = b.step(example.step_name, example.description);
        exe_step.dependOn(&run_exe.step);
    }

    // Rendering micro-benchmark
    const render_bench_module = b.createModule(.{
        .root_source_file = b.path("examples/benchmarks/render_bench.zig"),
        .target = target,
        .optimize = optimize,
    });
    render_bench_module.addImport("zit", zit_module);

    const render_bench = b.addExecutable(.{
        .name = "render_bench",
        .root_module = render_bench_module,
    });

    b.installArtifact(render_bench);
    smoke_step.dependOn(&render_bench.step);

    const run_render_bench = b.addRunArtifact(render_bench);
    const render_bench_step = b.step("render-bench", "Run rendering micro-benchmark");
    render_bench_step.dependOn(&run_render_bench.step);

    // Comprehensive benchmark suite
    const bench_suite_module = b.createModule(.{
        .root_source_file = b.path("examples/benchmarks/bench_suite.zig"),
        .target = target,
        .optimize = optimize,
    });
    bench_suite_module.addImport("zit", zit_module);

    const bench_suite = b.addExecutable(.{
        .name = "bench_suite",
        .root_module = bench_suite_module,
    });
    b.installArtifact(bench_suite);
    smoke_step.dependOn(&bench_suite.step);

    const bench_suite_tests_module = b.createModule(.{
        .root_source_file = b.path("examples/benchmarks/bench_suite.zig"),
        .target = target,
        .optimize = optimize,
    });
    bench_suite_tests_module.addImport("zit", zit_module);

    const bench_suite_tests = b.addTest(.{
        .name = "bench-suite-tests",
        .root_module = bench_suite_tests_module,
    });
    const run_bench_suite_tests = b.addRunArtifact(bench_suite_tests);
    test_step.dependOn(&run_bench_suite_tests.step);

    const run_bench_suite = b.addRunArtifact(bench_suite);
    const bench_step = b.step("bench", "Run benchmark suite");
    bench_step.dependOn(&run_bench_suite.step);

    const widget_coverage_cmd = b.addSystemCommand(&.{ "python3", "scripts/check_widget_coverage.py" });
    const widget_coverage_step = b.step("widget-coverage", "Check public widget visual and snapshot coverage declarations");
    widget_coverage_step.dependOn(&widget_coverage_cmd.step);

    const docs_links_cmd = b.addSystemCommand(&.{ "python3", "scripts/check_docs_links.py" });
    const docs_links_step = b.step("docs-links", "Check public Markdown docs links and index coverage");
    docs_links_step.dependOn(&docs_links_cmd.step);

    const docs_commands_cmd = b.addSystemCommand(&.{ "python3", "scripts/check_docs_commands.py" });
    const docs_commands_step = b.step("docs-commands", "Check public Markdown command references");
    docs_commands_step.dependOn(&docs_commands_cmd.step);

    const docs_zig_snippets_cmd = b.addSystemCommand(&.{ "python3", "scripts/check_docs_zig_snippets.py" });
    const docs_zig_snippets_step = b.step("docs-zig-snippets", "Check public Markdown Zig snippet hygiene");
    docs_zig_snippets_step.dependOn(&docs_zig_snippets_cmd.step);

    const accessibility_metadata_cmd = b.addSystemCommand(&.{ "python3", "scripts/check_accessibility_metadata.py" });
    const accessibility_metadata_step = b.step("accessibility-metadata", "Check public widgets expose accessibility metadata");
    accessibility_metadata_step.dependOn(&accessibility_metadata_cmd.step);

    const application_input_binding_cmd = b.addSystemCommand(&.{ "python3", "scripts/check_application_input_binding.py" });
    const application_input_binding_step = b.step("application-input-binding", "Check application examples use bound input polling");
    application_input_binding_step.dependOn(&application_input_binding_cmd.step);

    const mouse_hit_coverage_cmd = b.addSystemCommand(&.{ "python3", "scripts/check_mouse_hit_coverage.py" });
    const mouse_hit_coverage_step = b.step("mouse-hit-coverage", "Check public mouse-capable widgets have hit-test coverage");
    mouse_hit_coverage_step.dependOn(&mouse_hit_coverage_cmd.step);

    const mouse_coordinate_contract_cmd = b.addSystemCommand(&.{ "python3", "scripts/check_mouse_coordinate_contract.py" });
    const mouse_coordinate_contract_step = b.step("mouse-coordinate-contract", "Check terminal mouse coordinates normalize at the input boundary");
    mouse_coordinate_contract_step.dependOn(&mouse_coordinate_contract_cmd.step);

    const widget_owner_casts_cmd = b.addSystemCommand(&.{ "python3", "scripts/check_widget_owner_casts.py" });
    const widget_owner_casts_step = b.step("widget-owner-casts", "Check widget vtable callbacks use safe owner recovery");
    widget_owner_casts_step.dependOn(&widget_owner_casts_cmd.step);

    const owned_alloc_patterns_cmd = b.addSystemCommand(&.{ "python3", "scripts/check_owned_allocation_patterns.py" });
    const owned_alloc_patterns_step = b.step("owned-allocation-patterns", "Check owned allocations are transactional");
    owned_alloc_patterns_step.dependOn(&owned_alloc_patterns_cmd.step);

    const io_event_ownership_docs_cmd = b.addSystemCommand(&.{ "python3", "scripts/check_io_event_ownership_docs.py" });
    const io_event_ownership_docs_step = b.step("io-event-ownership-docs", "Check I/O event ownership docs avoid stale manager-owned cleanup");
    io_event_ownership_docs_step.dependOn(&io_event_ownership_docs_cmd.step);

    const unreachable_catches_cmd = b.addSystemCommand(&.{ "python3", "scripts/check_unreachable_catches.py" });
    const unreachable_catches_step = b.step("unreachable-catches", "Check recoverable errors are not converted to panics");
    unreachable_catches_step.dependOn(&unreachable_catches_cmd.step);

    const example_coverage_cmd = b.addSystemCommand(&.{ "python3", "scripts/check_example_coverage.py" });
    const example_coverage_step = b.step("example-coverage", "Check public examples are covered by PTY and visual gates");
    example_coverage_step.dependOn(&example_coverage_cmd.step);

    const interactive_alt_screen_cmd = b.addSystemCommand(&.{ "python3", "scripts/check_interactive_alt_screen.py" });
    const interactive_alt_screen_step = b.step("interactive-alt-screen", "Check interactive examples render in the alternate screen");
    interactive_alt_screen_step.dependOn(&interactive_alt_screen_cmd.step);

    const terminal_state_cleanup_cmd = b.addSystemCommand(&.{ "python3", "scripts/check_terminal_state_cleanup.py" });
    const terminal_state_cleanup_step = b.step("terminal-state-cleanup", "Check interactive examples restore terminal state");
    terminal_state_cleanup_step.dependOn(&terminal_state_cleanup_cmd.step);

    const memory_cleanup_cmd = b.addSystemCommand(&.{ "python3", "scripts/check_debug_allocator_cleanup.py" });
    const memory_cleanup_step = b.step("memory-cleanup", "Check DebugAllocator users assert clean deinit");
    memory_cleanup_step.dependOn(&memory_cleanup_cmd.step);

    const contribution_gates_cmd = b.addSystemCommand(&.{ "python3", "scripts/check_contribution_gates.py" });
    const contribution_gates_step = b.step("contribution-gates", "Check contribution docs and CI release-gate metadata");
    contribution_gates_step.dependOn(&contribution_gates_cmd.step);

    const resize_smoke_cmd = b.addSystemCommand(&.{ "python3", "scripts/resize_smoke.py", "--no-build" });
    resize_smoke_cmd.step.dependOn(b.getInstallStep());
    const resize_smoke_step = b.step("resize-smoke", "Run PTY resize smoke against input handling");
    resize_smoke_step.dependOn(&resize_smoke_cmd.step);

    const mouse_smoke_cmd = b.addSystemCommand(&.{ "python3", "scripts/mouse_alignment_smoke.py", "--no-build" });
    mouse_smoke_cmd.step.dependOn(b.getInstallStep());
    const mouse_smoke_step = b.step("mouse-smoke", "Run PTY mouse coordinate alignment smoke");
    mouse_smoke_step.dependOn(&mouse_smoke_cmd.step);

    const release_check_cmd = b.addSystemCommand(&.{ "python3", "scripts/release_verify.py" });
    const release_check_step = b.step("release-check", "Run the full public release verification gate");
    release_check_step.dependOn(&release_check_cmd.step);

    const quality_step = b.step("quality", "Run the public quality gate: smoke, tests, and benchmarks");
    quality_step.dependOn(smoke_step);
    quality_step.dependOn(test_step);
    quality_step.dependOn(bench_step);
    quality_step.dependOn(docs_links_step);
    quality_step.dependOn(docs_commands_step);
    quality_step.dependOn(docs_zig_snippets_step);
    quality_step.dependOn(widget_coverage_step);
    quality_step.dependOn(accessibility_metadata_step);
    quality_step.dependOn(application_input_binding_step);
    quality_step.dependOn(mouse_hit_coverage_step);
    quality_step.dependOn(mouse_coordinate_contract_step);
    quality_step.dependOn(widget_owner_casts_step);
    quality_step.dependOn(owned_alloc_patterns_step);
    quality_step.dependOn(io_event_ownership_docs_step);
    quality_step.dependOn(unreachable_catches_step);
    quality_step.dependOn(example_coverage_step);
    quality_step.dependOn(interactive_alt_screen_step);
    quality_step.dependOn(terminal_state_cleanup_step);
    quality_step.dependOn(memory_cleanup_step);
    quality_step.dependOn(contribution_gates_step);
}
