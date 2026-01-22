// Example: FileBrowser widget with navigation and typeahead.

const std = @import("std");
const zit = @import("zit");
const theme = zit.widget.theme;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var term = try zit.terminal.init(allocator);
    defer term.deinit() catch {};

    var renderer = try zit.render.Renderer.init(allocator, term.width, term.height);
    defer renderer.deinit();

    var input_handler = zit.input.InputHandler.init(allocator, &term);

    var browser = try zit.widget.FileBrowser.init(allocator, ".");
    defer browser.deinit();
    browser.widget.focused = true;
    const ui_theme = theme.Theme.dark();
    const bg = ui_theme.color(.background);
    const text = ui_theme.color(.text);
    const muted = ui_theme.color(.muted);
    const surface = ui_theme.color(.surface);
    const border = ui_theme.color(.border);
    const selection = theme.selectionColors(ui_theme);
    browser.setBorder(.single, border);
    browser.setColors(text, bg, selection.fg, selection.bg);

    try term.enableRawMode();
    try term.hideCursor();
    try input_handler.enableMouse();
    defer {
        input_handler.disableMouse() catch {};
        term.showCursor() catch {};
        term.disableRawMode() catch {};
    }

    var running = true;
    while (running) {
        renderer.back.clear();
        const width = renderer.back.width;
        const height = renderer.back.height;
        renderer.fillRect(0, 0, width, height, ' ', text, bg, zit.render.Style{});

        const hint = "File browser: type to jump to entries, arrows/page navigate, Enter to open, h toggles hidden, q quits";
        const hint_slice = hint[0..@min(hint.len, @as(usize, width))];
        renderer.drawStr(0, 0, hint_slice, muted, bg, zit.render.Style{});

        const content_height: u16 = if (height > 2) height - 2 else height;
        if (content_height > 0) {
            try browser.widget.layout(zit.layout.Rect.init(0, 1, width, content_height));
            try browser.widget.draw(&renderer);
        }

        if (height > 0 and width > 0 and browser.entries.items.len > 0) {
            const status_y: u16 = height - 1;
            const entry = browser.entries.items[browser.selected];
            var status_buf: [200]u8 = undefined;
            const status = std.fmt.bufPrint(&status_buf, "Selected: {s}{s}", .{
                if (entry.is_dir) "[D] " else "[F] ",
                entry.name,
            }) catch "Selected: ?";
            const status_slice = status[0..@min(status.len, @as(usize, width - 1))];
            renderer.drawStr(1, status_y, status_slice, text, surface, zit.render.Style{});
        }

        try renderer.render();

        const event = try input_handler.pollEvent(120);
        if (event) |e| {
            switch (e) {
                .key => |key| {
                    if (key.key == 'q' and !key.modifiers.ctrl and !key.modifiers.alt) {
                        running = false;
                    } else if (key.key == 'h' and !key.modifiers.ctrl and !key.modifiers.alt) {
                        try browser.setShowHidden(!browser.show_hidden);
                    } else {
                        _ = try browser.widget.handleEvent(e);
                    }
                },
                .resize => |resize| {
                    try renderer.resize(resize.width, resize.height);
                },
                else => {
                    _ = try browser.widget.handleEvent(e);
                },
            }
        }
    }

    try term.clear();
    try term.moveCursor(0, 0);
}
