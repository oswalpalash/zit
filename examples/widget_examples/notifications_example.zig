// Example: notification center/toast manager showcasing auto-dismiss.

const std = @import("std");
const zit = @import("zit");
const render = zit.render;
const layout = zit.layout;
const widget = zit.widget;
const memory = zit.memory;
const theme = zit.widget.theme;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var memory_manager = try memory.MemoryManager.init(allocator, 256 * 1024, 64);
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
    const surface = ui_theme.color(.surface);
    const text = ui_theme.color(.text);
    const muted = ui_theme.color(.muted);
    const border = ui_theme.color(.border);
    const accent = ui_theme.color(.accent);

    var menu = try widget.MenuBar.init(memory_manager.getWidgetPoolAllocator());
    defer menu.deinit();
    try menu.addItem("File", null);
    try menu.addItem("Help", null);
    menu.fg = text;
    menu.bg = surface;
    menu.active_fg = bg;
    menu.active_bg = accent;

    var toasts = try widget.ToastManager.init(memory_manager.getWidgetPoolAllocator());
    defer toasts.deinit();
    toasts.fg = text;
    try toasts.push("Saved", .success, 48);
    try toasts.push("Syncing…", .info, 96);

    var popup = try widget.Popup.init(memory_manager.getWidgetPoolAllocator(), "Press q to quit");
    defer popup.deinit();
    popup.setColors(text, accent);

    var canvas = try widget.Canvas.init(memory_manager.getWidgetPoolAllocator(), 20, 6);
    defer canvas.deinit();
    canvas.drawLine(0, 0, 19, 5, '*', render.Color.named(render.NamedColor.yellow), render.Color.named(render.NamedColor.black), render.Style{});
    canvas.drawRect(2, 1, 8, 3, '#', render.Color.named(render.NamedColor.green), render.Color.named(render.NamedColor.black), render.Style{});

    const toast_messages = [_][]const u8{
        "Backup finished",
        "New message received",
        "Warnings resolved",
        "Sync complete",
    };
    var toast_idx: usize = 0;
    var running = true;
    while (running) {
        renderer.back.clear();
        const width = renderer.back.width;
        const height = renderer.back.height;

        renderer.fillRect(0, 0, width, height, ' ', text, bg, render.Style{});
        renderer.drawBox(0, 0, width, height, render.BorderStyle.single, border, bg, render.Style{});

        try menu.widget.layout(layout.Rect.init(0, 0, width, 1));
        try menu.widget.draw(&renderer);

        if (height > 4) {
            const popup_width: u16 = if (width > 10) width - 10 else width;
            const popup_x: u16 = if (width > popup_width) (width - popup_width) / 2 else 0;
            const popup_y: u16 = 2;
            try popup.widget.layout(layout.Rect.init(popup_x, popup_y, popup_width, 4));
            try popup.widget.draw(&renderer);
        }

        if (height > 8 and width > 8) {
            const canvas_width: u16 = if (width > 28) 26 else width - 4;
            const canvas_height: u16 = if (height > 12) 8 else height - 6;
            try canvas.widget.layout(layout.Rect.init(2, height - canvas_height - 3, canvas_width, canvas_height));
            try canvas.widget.draw(&renderer);
        }

        if (width > 12 and height > 6) {
            const toast_width: u16 = if (width > 30) 28 else width - 4;
            const toast_height: u16 = if (height > 10) 8 else height - 4;
            try toasts.widget.layout(layout.Rect.init(width - toast_width - 2, height - toast_height - 2, toast_width, toast_height));
            try toasts.widget.draw(&renderer);
        }

        if (height > 0) {
            renderer.drawSmartStr(2, height - 1, "Notifications demo: n = new toast, q = quit", muted, bg, render.Style{});
        }

        try renderer.render();

        toasts.tick(1);

        if (try input_handler.pollEvent(80)) |event| {
            switch (event) {
                .key => |key| {
                    if (key.key == 'q') {
                        running = false;
                    } else if (key.key == 'n') {
                        const msg = toast_messages[toast_idx % toast_messages.len];
                        toast_idx += 1;
                        try toasts.push(msg, .info, 96);
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
