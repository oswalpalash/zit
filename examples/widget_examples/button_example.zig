const std = @import("std");
const zit = @import("zit");
const Button = zit.widget.Button;
const Container = zit.widget.Container;
const Label = zit.widget.Label;
const render = zit.render;
const input = zit.input;
const layout = zit.layout;
const memory = zit.memory;
const widget = zit.widget;
const term = zit.terminal;

var counter_state: u32 = 0;

const LayoutWidget = struct {
    widget: widget.Widget,
    layout_element: layout.LayoutElement,

    pub fn init(layout_element: layout.LayoutElement) LayoutWidget {
        return .{
            .widget = widget.Widget.init(&.{
                .draw = drawFn,
                .handle_event = handleEventFn,
                .layout = layoutFn,
                .get_preferred_size = getPreferredSizeFn,
                .can_focus = canFocusFn,
            }),
            .layout_element = layout_element,
        };
    }

    fn drawFn(widget_ptr: *anyopaque, r: *render.Renderer) anyerror!void {
        const self = @as(*LayoutWidget, @ptrCast(@alignCast(widget_ptr)));
        self.layout_element.render(r, self.widget.rect);
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        _ = widget_ptr;
        _ = event;
        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout.Rect) anyerror!void {
        const self = @as(*LayoutWidget, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout.Size {
        const self = @as(*LayoutWidget, @ptrCast(@alignCast(widget_ptr)));
        // Use loose constraints to get the preferred size
        return self.layout_element.layout(layout.Constraints.loose(65535, 65535));
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        _ = widget_ptr;
        return false;
    }
};

pub fn main() !void {
    // Create an allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize memory manager
    var memory_manager = try memory.MemoryManager.init(allocator, 1024 * 1024, 100);
    defer memory_manager.deinit();

    // Initialize terminal with memory manager
    var terminal = try zit.terminal.init(memory_manager.getArenaAllocator());
    defer terminal.deinit() catch {};

    // Initialize input handler with memory manager
    var input_handler = zit.input.InputHandler.init(memory_manager.getArenaAllocator(), &terminal);

    // Create a root container using widget pool allocator
    var root = try Container.init(memory_manager.getWidgetPoolAllocator());
    defer root.deinit();
    root.setColors(
        render.Color{ .named_color = render.NamedColor.black },
        render.Color{ .named_color = render.NamedColor.white },
    );
    root.setBorder(.single);

    // Create a renderer with memory manager
    var renderer = try render.Renderer.init(memory_manager.getArenaAllocator(), terminal.width, terminal.height);
    defer renderer.deinit();

    // Create a title label using widget pool allocator
    const title = try Label.init(memory_manager.getWidgetPoolAllocator(), "Zit Button Widget Demo");
    defer title.deinit();
    title.setColor(
        render.Color{ .named_color = render.NamedColor.yellow },
        render.Color{ .named_color = render.NamedColor.black },
    );
    try root.addChild(@as(*zit.widget.Widget, @ptrCast(title)));

    // Create a flex layout for buttons
    var flex_layout = try layout.FlexLayout.init(memory_manager.getArenaAllocator(), .column);
    defer flex_layout.deinit();
    _ = flex_layout.mainAlignment(.center);
    _ = flex_layout.crossAlignment(.center);
    _ = flex_layout.gap(1);
    _ = flex_layout.padding(layout.EdgeInsets.all(1));

    // Section 1: Basic Buttons
    const basic_label = try Label.init(memory_manager.getWidgetPoolAllocator(), "Basic Buttons");
    defer basic_label.deinit();
    basic_label.setColor(
        render.Color{ .named_color = render.NamedColor.cyan },
        render.Color{ .named_color = render.NamedColor.black },
    );
    try flex_layout.addChild(layout.FlexChild.init(basic_label.widget.asLayoutElement(), 0));

    // Standard button
    const standard_button = try Button.init(memory_manager.getWidgetPoolAllocator(), "Standard Button");
    defer standard_button.deinit();
    standard_button.setOnPress(struct {
        fn callback() void {
            std.debug.print("Standard button pressed\n", .{});
        }
    }.callback);
    try flex_layout.addChild(layout.FlexChild.init(standard_button.widget.asLayoutElement(), 0));

    // Disabled button
    const disabled_button = try Button.init(memory_manager.getWidgetPoolAllocator(), "Disabled Button");
    defer disabled_button.deinit();
    disabled_button.widget.setEnabled(false);
    try flex_layout.addChild(layout.FlexChild.init(disabled_button.widget.asLayoutElement(), 0));

    // Section 2: Styled Buttons
    const styled_label = try Label.init(memory_manager.getWidgetPoolAllocator(), "Styled Buttons");
    defer styled_label.deinit();
    styled_label.setColor(
        render.Color{ .named_color = render.NamedColor.cyan },
        render.Color{ .named_color = render.NamedColor.black },
    );
    try flex_layout.addChild(layout.FlexChild.init(styled_label.widget.asLayoutElement(), 0));

    // Colored button
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
    try flex_layout.addChild(layout.FlexChild.init(colored_button.widget.asLayoutElement(), 0));

    // Highlighted button
    const highlight_button = try Button.init(memory_manager.getWidgetPoolAllocator(), "Highlight Button");
    defer highlight_button.deinit();
    highlight_button.setColors(
        render.Color{ .named_color = render.NamedColor.yellow },
        render.Color{ .named_color = render.NamedColor.black },
        render.Color{ .named_color = render.NamedColor.black },
        render.Color{ .named_color = render.NamedColor.yellow },
    );
    highlight_button.setOnPress(struct {
        fn callback() void {
            std.debug.print("Highlight button pressed\n", .{});
        }
    }.callback);
    try flex_layout.addChild(layout.FlexChild.init(highlight_button.widget.asLayoutElement(), 0));

    // Section 3: Interactive Buttons
    const interactive_label = try Label.init(memory_manager.getWidgetPoolAllocator(), "Interactive Buttons");
    defer interactive_label.deinit();
    interactive_label.setColor(
        render.Color{ .named_color = render.NamedColor.cyan },
        render.Color{ .named_color = render.NamedColor.black },
    );
    try flex_layout.addChild(layout.FlexChild.init(interactive_label.widget.asLayoutElement(), 0));

    // Counter button
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
    try flex_layout.addChild(layout.FlexChild.init(counter_button.widget.asLayoutElement(), 0));

    // Toggle button
    const toggle_button = try Button.init(memory_manager.getWidgetPoolAllocator(), "Toggle: Off");
    defer toggle_button.deinit();
    const toggle_data = struct {
        var button: *Button = undefined;
        var alloc: std.mem.Allocator = undefined;
        var state: bool = false;
    };
    toggle_data.button = toggle_button;
    toggle_data.alloc = memory_manager.getArenaAllocator();
    toggle_button.setOnPress(struct {
        fn callback() void {
            toggle_data.state = !toggle_data.state;
            toggle_data.button.setText(std.fmt.allocPrint(toggle_data.alloc, "Toggle: {s}", .{if (toggle_data.state) "On" else "Off"}) catch unreachable) catch unreachable;
        }
    }.callback);
    try flex_layout.addChild(layout.FlexChild.init(toggle_button.widget.asLayoutElement(), 0));

    // Create a layout widget for the flex layout
    var layout_widget = LayoutWidget.init(flex_layout.asElement());

    // Add layout widget to root
    try root.addChild(&layout_widget.widget);

    // Set up the terminal
    try terminal.enableRawMode();
    try terminal.hideCursor();
    try input_handler.enableMouse();
    defer {
        input_handler.disableMouse() catch {};
        terminal.showCursor() catch {};
        terminal.disableRawMode() catch {};
    }

    // Clear screen initially
    try terminal.clear();

    // Main event loop
    var running = true;
    while (running) {
        // Clear the buffer
        renderer.back.clear();

        // Fill the background
        renderer.fillRect(0, 0, terminal.width, terminal.height, ' ', render.Color{ .named_color = render.NamedColor.white }, render.Color{ .named_color = render.NamedColor.black }, render.Style{});

        // Layout and render the root container
        try root.widget.layout(layout.Rect.init(0, 0, terminal.width, terminal.height));
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
    try terminal.clear();
    try terminal.moveCursor(0, 0);
}
