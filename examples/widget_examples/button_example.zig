const std = @import("std");
const zit = @import("zit");
const Button = zit.widget.Button;
const Container = zit.widget.Container;
const Label = zit.widget.Label;
const render = zit.render;
const input = zit.input;
const layout = zit.layout;
const memory = zit.memory;

var counter_state: u32 = 0;

pub fn main() !void {
    // Create an allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize memory manager
    var memory_manager = try memory.MemoryManager.init(allocator, 1024 * 1024, 100);
    defer memory_manager.deinit();

    // Initialize terminal with memory manager
    var term = try zit.terminal.init(memory_manager.getArenaAllocator());
    defer term.deinit() catch {};

    // Initialize input handler with memory manager
    var input_handler = zit.input.InputHandler.init(memory_manager.getArenaAllocator(), &term);

    // Create a root container using widget pool allocator
    var root = try Container.init(memory_manager.getWidgetPoolAllocator());
    defer root.deinit();
    root.setColors(
        render.Color{ .named_color = render.NamedColor.black },
        render.Color{ .named_color = render.NamedColor.white },
    );
    root.setBorder(.single);

    // Create a renderer with memory manager
    var renderer = try render.Renderer.init(memory_manager.getArenaAllocator(), term.width, term.height);
    defer renderer.deinit();

    // Create a title label using widget pool allocator
    const title = try Label.init(memory_manager.getWidgetPoolAllocator(), "Button Widget Demo");
    defer title.deinit();
    title.setColor(
        render.Color{ .named_color = render.NamedColor.yellow },
        render.Color{ .named_color = render.NamedColor.black },
    );
    try root.addChild(@as(*zit.widget.Widget, @ptrCast(title)));

    // Create a container for buttons using widget pool allocator
    var button_container = try Container.init(memory_manager.getWidgetPoolAllocator());
    defer button_container.deinit();
    button_container.setColors(
        render.Color{ .named_color = render.NamedColor.white },
        render.Color{ .named_color = render.NamedColor.black },
    );
    try root.addChild(@as(*zit.widget.Widget, @ptrCast(button_container)));

    // Standard button using widget pool allocator
    const standard_button = try Button.init(memory_manager.getWidgetPoolAllocator(), "Standard Button");
    defer standard_button.deinit();
    standard_button.setOnPress(struct {
        fn callback() void {
            std.debug.print("Standard button pressed\n", .{});
        }
    }.callback);
    try button_container.addChild(@as(*zit.widget.Widget, @ptrCast(standard_button)));

    // Colored button using widget pool allocator
    const colored_button = try Button.init(memory_manager.getWidgetPoolAllocator(), "Colored Button");
    defer colored_button.deinit();
    colored_button.setColors(
        render.Color{ .named_color = render.NamedColor.green },
        render.Color{ .named_color = render.NamedColor.black },
        render.Color{ .named_color = render.NamedColor.black },
        render.Color{ .named_color = render.NamedColor.green },
    );
    colored_button.setOnPress(struct {
        fn callback() void {
            std.debug.print("Colored button pressed\n", .{});
        }
    }.callback);
    try button_container.addChild(@as(*zit.widget.Widget, @ptrCast(colored_button)));

    // Disabled button using widget pool allocator
    const disabled_button = try Button.init(memory_manager.getWidgetPoolAllocator(), "Disabled Button");
    defer disabled_button.deinit();
    disabled_button.widget.setEnabled(false);
    try button_container.addChild(@as(*zit.widget.Widget, @ptrCast(disabled_button)));

    // Counter button using widget pool allocator
    const counter_button = try Button.init(memory_manager.getWidgetPoolAllocator(), "Counter: 0");
    defer counter_button.deinit();
    const counter_data = struct {
        var button: *Button = undefined;
        var alloc: std.mem.Allocator = undefined;
    };
    counter_data.button = counter_button;
    counter_data.alloc = memory_manager.getArenaAllocator();
    counter_button.setOnPress(struct {
        fn callback() void {
            counter_state += 1;
            counter_data.button.setText(std.fmt.allocPrint(counter_data.alloc, "Counter: {}", .{counter_state}) catch unreachable) catch unreachable;
        }
    }.callback);
    try button_container.addChild(@as(*zit.widget.Widget, @ptrCast(counter_button)));

    // Set up the terminal
    try term.enableRawMode();
    try term.hideCursor();
    try input_handler.enableMouse();
    defer {
        input_handler.disableMouse() catch {};
        term.showCursor() catch {};
        term.disableRawMode() catch {};
    }

    // Clear screen initially
    try term.clear();

    // Main event loop
    var running = true;
    while (running) {
        // Clear the buffer
        renderer.back.clear();

        // Fill the background
        renderer.fillRect(0, 0, term.width, term.height, ' ',
            render.Color{ .named_color = render.NamedColor.white },
            render.Color{ .named_color = render.NamedColor.black },
            render.Style{});

        // Layout the widgets
        try root.widget.layout(layout.Rect.init(0, 0, term.width, term.height));

        // Draw the UI
        try root.widget.draw(&renderer);

        // Present the frame
        try renderer.render();

        // Handle input with a 100ms timeout
        const event = try input_handler.pollEvent(100);
        if (event) |e| {
            switch (e) {
                .key => |key| {
                    if (key.key == 'q' and !key.modifiers.ctrl and !key.modifiers.alt) {
                        running = false;
                    } else {
                        _ = try root.widget.handleEvent(e);
                    }
                },
                .resize => |resize| {
                    try renderer.resize(resize.width, resize.height);
                },
                .mouse => {
                    _ = try root.widget.handleEvent(e);
                },
                else => {},
            }
        }
    }

    // Clean up
    try term.clear();
    try term.moveCursor(0, 0);

    // Remove all children from containers before deinit
    button_container.removeChild(@as(*zit.widget.Widget, @ptrCast(standard_button)));
    button_container.removeChild(@as(*zit.widget.Widget, @ptrCast(colored_button)));
    button_container.removeChild(@as(*zit.widget.Widget, @ptrCast(disabled_button)));
    button_container.removeChild(@as(*zit.widget.Widget, @ptrCast(counter_button)));
    root.removeChild(@as(*zit.widget.Widget, @ptrCast(title)));
    root.removeChild(@as(*zit.widget.Widget, @ptrCast(button_container)));
} 