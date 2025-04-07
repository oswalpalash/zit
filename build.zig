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
    });

    const lib = b.addStaticLibrary(.{
        .name = "zit",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const main_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_main_tests = b.addRunArtifact(main_tests);

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build test`
    // This will evaluate the `test` step rather than the default, which is "install".
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
    
    // Add terminal test example
    const terminal_test = b.addExecutable(.{
        .name = "terminal_test",
        .root_source_file = b.path("examples/terminal_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Link the library to the example
    terminal_test.root_module.addImport("zit", zit_module);
    
    // Install the example binary
    b.installArtifact(terminal_test);
    
    // Create a run step for the terminal test
    const run_terminal_test = b.addRunArtifact(terminal_test);
    run_terminal_test.step.dependOn(b.getInstallStep());
    
    // Add a separate step to run the terminal test
    const terminal_test_step = b.step("terminal-test", "Run the terminal test example");
    terminal_test_step.dependOn(&run_terminal_test.step);
    
    // Add input test example
    const input_test = b.addExecutable(.{
        .name = "input_test",
        .root_source_file = b.path("examples/input_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Link the library to the example
    input_test.root_module.addImport("zit", zit_module);
    
    // Install the example binary
    b.installArtifact(input_test);
    
    // Create a run step for the input test
    const run_input_test = b.addRunArtifact(input_test);
    run_input_test.step.dependOn(b.getInstallStep());
    
    // Add a separate step to run the input test
    const input_test_step = b.step("input-test", "Run the input handling test example");
    input_test_step.dependOn(&run_input_test.step);
    
    // Add render test example
    const render_test = b.addExecutable(.{
        .name = "render_test",
        .root_source_file = b.path("examples/render_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Link the library to the example
    render_test.root_module.addImport("zit", zit_module);
    
    // Install the example binary
    b.installArtifact(render_test);
    
    // Create a run step for the render test
    const run_render_test = b.addRunArtifact(render_test);
    run_render_test.step.dependOn(b.getInstallStep());
    
    // Add a separate step to run the render test
    const render_test_step = b.step("render-test", "Run the rendering test example");
    render_test_step.dependOn(&run_render_test.step);
    
    // Add layout test example
    const layout_test = b.addExecutable(.{
        .name = "layout_test",
        .root_source_file = b.path("examples/layout_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Link the library to the example
    layout_test.root_module.addImport("zit", zit_module);
    
    // Install the example binary
    b.installArtifact(layout_test);
    
    // Create a run step for the layout test
    const run_layout_test = b.addRunArtifact(layout_test);
    run_layout_test.step.dependOn(b.getInstallStep());
    
    // Add a separate step to run the layout test
    const layout_test_step = b.step("layout-test", "Run the layout system test example");
    layout_test_step.dependOn(&run_layout_test.step);
    
    // Add demo example
    const demo = b.addExecutable(.{
        .name = "demo",
        .root_source_file = b.path("examples/demo.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Link the library to the example
    demo.root_module.addImport("zit", zit_module);
    
    // Install the example binary
    b.installArtifact(demo);
    
    // Create a run step for the demo
    const run_demo = b.addRunArtifact(demo);
    run_demo.step.dependOn(b.getInstallStep());
    
    // Add a separate step to run the demo
    const demo_step = b.step("demo", "Run the comprehensive demo example");
    demo_step.dependOn(&run_demo.step);
    
    // Add widget test example
    const widget_test = b.addExecutable(.{
        .name = "widget_test",
        .root_source_file = b.path("examples/widget_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Link the library to the example
    widget_test.root_module.addImport("zit", zit_module);
    
    // Install the example binary
    b.installArtifact(widget_test);
    
    // Create a run step for the widget test
    const run_widget_test = b.addRunArtifact(widget_test);
    run_widget_test.step.dependOn(b.getInstallStep());
    
    // Add a separate step to run the widget test
    const widget_test_step = b.step("widget-test", "Run the widget test example");
    widget_test_step.dependOn(&run_widget_test.step);

    // Add widget examples
    const widget_examples = [_]struct {
        name: []const u8,
        description: []const u8,
        path: []const u8,
        step_name: []const u8,
    }{
        .{ .name = "button", .description = "Run the button widget example", .path = "examples/widget_examples/button_example.zig", .step_name = "button-example" },
    };

    for (widget_examples) |example| {
        const exe = b.addExecutable(.{
            .name = example.name,
            .root_source_file = b.path(example.path),
            .target = target,
            .optimize = optimize,
        });

        // Link the library to the example
        exe.root_module.addImport("zit", zit_module);

        // Install the example binary
        b.installArtifact(exe);

        // Create a run step for the example
        const run_exe = b.addRunArtifact(exe);
        run_exe.step.dependOn(b.getInstallStep());

        // Add a separate step to run the example
        const exe_step = b.step(example.step_name, example.description);
        exe_step.dependOn(&run_exe.step);
    }
}
