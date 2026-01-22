// Hello world: minimal alternate-screen label rendered with Zit primitives.

const std = @import("std");
const zit = @import("zit");
const render = zit.render;
const layout = zit.layout;
const memory = zit.memory;
const theme = zit.widget.theme;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var memory_manager = try memory.MemoryManager.init(allocator, 128 * 1024, 32);
    defer memory_manager.deinit();

    var term = try zit.terminal.init(allocator);
    defer term.deinit() catch {};

    var renderer = try render.Renderer.init(allocator, term.width, term.height);
    defer renderer.deinit();

    var input_handler = zit.input.InputHandler.init(allocator, &term);

    try term.enterAlternateScreen();
    defer term.exitAlternateScreen() catch {};

    try term.enableRawMode();
    defer term.disableRawMode() catch {};

    try term.hideCursor();
    defer term.showCursor() catch {};

    try input_handler.enableMouse();
    defer input_handler.disableMouse() catch {};

    const ui_theme = theme.Theme.dark();
    const bg = ui_theme.color(.background);
    const text = ui_theme.color(.text);
    const muted = ui_theme.color(.muted);

    var label = try zit.widget.Label.init(memory_manager.getWidgetPoolAllocator(), "Hello, Zit!");
    defer label.deinit();
    label.setAlignment(.center);
    label.setTheme(ui_theme);
    label.setStyle(render.Style.init(true, false, true));

    var running = true;
    while (running) {
        renderer.back.clear();
        const width = renderer.back.width;
        const height = renderer.back.height;

        renderer.fillRect(0, 0, width, height, ' ', text, bg, render.Style{});
        if (height > 2) {
            renderer.drawSmartStr(1, 1, "Hello world: press q to quit", muted, bg, render.Style{});
        }

        const label_width: u16 = if (width > 20) 20 else width;
        const label_x: u16 = if (width > label_width) (width - label_width) / 2 else 0;
        const label_y: u16 = if (height > 0) height / 2 else 0;
        try label.widget.layout(layout.Rect.init(label_x, label_y, label_width, 1));
        try label.widget.draw(&renderer);

        try renderer.render();

        if (try input_handler.pollEvent(120)) |event| {
            switch (event) {
                .key => |key| {
                    if (key.key == 'q') {
                        running = false;
                    }
                },
                .resize => |size| {
                    try renderer.resize(size.width, size.height);
                },
                else => {},
            }
        }
    }

    try term.clear();
    try term.moveCursor(0, 0);
}
