const std = @import("std");
const zit = @import("zit");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var term = try zit.terminal.init(allocator);
    defer term.deinit() catch {};

    var renderer = try zit.render.Renderer.init(allocator, term.width, term.height);
    defer renderer.deinit();

    var input_handler = zit.input.InputHandler.init(allocator, &term);
    try input_handler.enableMouse();

    var browser = try zit.widget.FileBrowser.init(allocator, ".");
    defer browser.deinit();
    browser.widget.focused = true;
    browser.setBorder(.single, zit.render.Color{ .named_color = zit.render.NamedColor.bright_black });
    browser.setColors(
        zit.render.Color{ .named_color = zit.render.NamedColor.black },
        zit.render.Color{ .named_color = zit.render.NamedColor.white },
        zit.render.Color{ .named_color = zit.render.NamedColor.black },
        zit.render.Color{ .named_color = zit.render.NamedColor.cyan },
    );

    try term.enableRawMode();
    try term.hideCursor();
    defer {
        input_handler.disableMouse() catch {};
        term.showCursor() catch {};
        term.disableRawMode() catch {};
    }

    var running = true;
    while (running) {
        renderer.back.clear();
        renderer.fillRect(0, 0, term.width, term.height, ' ', zit.render.Color{ .named_color = zit.render.NamedColor.black }, zit.render.Color{ .named_color = zit.render.NamedColor.white }, zit.render.Style{});

        const hint = "File browser: type to jump to entries, arrows/page navigate, Enter to open, h toggles hidden, q quits";
        const hint_slice = hint[0..@min(hint.len, @as(usize, term.width))];
        renderer.drawStr(0, 0, hint_slice, zit.render.Color{ .named_color = zit.render.NamedColor.bright_black }, zit.render.Color{ .named_color = zit.render.NamedColor.white }, zit.render.Style{});

        const content_height: u16 = if (term.height > 2) term.height - 2 else term.height;
        if (content_height > 0) {
            try browser.widget.layout(zit.layout.Rect.init(0, 1, term.width, content_height));
            try browser.widget.draw(&renderer);
        }

        if (term.height > 0 and term.width > 0 and browser.entries.items.len > 0) {
            const status_y: u16 = term.height - 1;
            const entry = browser.entries.items[browser.selected];
            var status_buf: [200]u8 = undefined;
            const status = std.fmt.bufPrint(&status_buf, "Selected: {s}{s}", .{
                if (entry.is_dir) "[D] " else "[F] ",
                entry.name,
            }) catch "Selected: ?";
            const status_slice = status[0..@min(status.len, @as(usize, term.width - 1))];
            renderer.drawStr(1, status_y, status_slice, zit.render.Color{ .named_color = zit.render.NamedColor.black }, zit.render.Color{ .named_color = zit.render.NamedColor.white }, zit.render.Style{});
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
                    term.width = resize.width;
                    term.height = resize.height;
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
