// Example: simple file manager composed of panels and shortcuts.

const std = @import("std");
const zit = @import("zit");
const render = zit.render;
const layout = zit.layout;
const widget = zit.widget;
const theme = zit.widget.theme;
const memory = zit.memory;
const input = zit.input;
const style = @import("example_style.zig");

const StatusLine = struct {
    buffer: [160]u8 = undefined,
    text: []const u8 = "Tab switches focus, m/right-click opens actions, q quits",
};

const Folder = struct {
    name: []const u8,
    files: []const []const u8,
};

const folders = [_]Folder{
    .{ .name = "apps", .files = &[_][]const u8{ "dashboard.zig", "notes.zig", "cli.zig", "watcher.zig" } },
    .{ .name = "logs", .files = &[_][]const u8{ "access.log", "error.log", "jobs.log", "metrics.log" } },
    .{ .name = "scripts", .files = &[_][]const u8{ "deploy.sh", "backup.sh", "fmt.zsh", "bench.zsh" } },
    .{ .name = "third_party", .files = &[_][]const u8{ "zig-ansi", "zig-json", "zig-tar" } },
    .{ .name = "notes", .files = &[_][]const u8{ "design.md", "roadmap.md", "retro.md" } },
};

fn setStatus(status: *StatusLine, comptime fmt: []const u8, args: anytype) void {
    status.text = std.fmt.bufPrint(&status.buffer, fmt, args) catch status.text;
}

fn loadFiles(list: *widget.List, folder_name: []const u8) !void {
    list.clear();
    list.widget.enabled = true;
    for (folders) |entry| {
        if (std.mem.eql(u8, entry.name, folder_name)) {
            for (entry.files) |file| {
                try list.addItem(file);
            }
            if (entry.files.len > 0) list.setSelectedIndex(0);
            return;
        }
    }

    try list.addItem("(empty folder)");
    list.widget.enabled = false;
    list.setSelectedIndex(0);
}

fn selectedFolder(tree: *widget.TreeView) []const u8 {
    if (tree.visible.items.len == 0) return "apps";
    const idx = tree.visible.items[tree.selected];
    return tree.nodes.items[idx].label;
}

fn menuSelect(_: usize, item: widget.ContextMenuItem, ctx: ?*anyopaque) void {
    if (ctx) |ptr| {
        const status = @as(*StatusLine, @ptrCast(@alignCast(ptr)));
        setStatus(status, "Action: {s}", .{item.label});
    }
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var memory_manager = try memory.MemoryManager.init(allocator, 1024 * 512, 128);
    defer memory_manager.deinit();

    var term = (try zit.terminal.initInteractive(memory_manager.getArenaAllocator(), "file-manager-example")) orelse return;
    defer term.deinit() catch {};

    var renderer = try render.Renderer.init(allocator, term.width, term.height);
    defer renderer.deinit();

    var input_handler = zit.input.InputHandler.init(allocator, &term);
    var app = zit.event.Application.init(allocator);
    defer app.deinit();
    app.bindResize(&renderer, null);
    app.bindInput(&input_handler);
    app.setInputPollTimeout(64);

    try term.enterAlternateScreen();
    defer term.exitAlternateScreen() catch {};

    try term.enableRawMode();
    defer term.disableRawMode() catch {};

    try term.hideCursor();
    defer term.showCursor() catch {};

    try input_handler.enableMouse();
    defer input_handler.disableMouse() catch {};

    const palette = style.filePalette();
    const ui_theme = style.asTheme(palette);

    var tree = try widget.TreeView.init(memory_manager.getWidgetPoolAllocator());
    defer tree.deinit();
    const root = try tree.addRoot("workspace");
    const apps = try tree.addChild(root, "apps");
    const logs = try tree.addChild(root, "logs");
    const scripts = try tree.addChild(root, "scripts");
    const third_party = try tree.addChild(root, "third_party");
    const notes = try tree.addChild(root, "notes");
    tree.nodes.items[root].expanded = true;
    tree.nodes.items[apps].expanded = true;
    tree.nodes.items[logs].expanded = true;
    tree.nodes.items[scripts].expanded = true;
    tree.nodes.items[third_party].expanded = true;
    tree.nodes.items[notes].expanded = true;
    try tree.setTheme(ui_theme);
    tree.widget.setFocus(true);

    var list = try widget.List.init(memory_manager.getWidgetPoolAllocator());
    defer list.deinit();
    list.setTheme(ui_theme);
    list.border = .none;
    list.bg = palette.surface;
    list.fg = palette.text;
    list.selected_bg = render.Color.rgb(16, 51, 34);
    list.selected_fg = palette.text;
    list.focused_bg = palette.surface_alt;
    list.focused_fg = palette.text;
    try loadFiles(list, "apps");

    var status = StatusLine{};

    var ctx_menu = try widget.ContextMenu.init(memory_manager.getWidgetPoolAllocator());
    defer ctx_menu.deinit();
    try ctx_menu.addItem("Open", true, null);
    try ctx_menu.addItem("Rename", true, null);
    try ctx_menu.addItem("Delete", false, null);
    try ctx_menu.addItem("Copy path", true, null);
    try ctx_menu.addItem("Mark favorite", true, null);
    ctx_menu.setMaxVisible(6);
    try ctx_menu.setTheme(theme.Theme.highContrast());
    ctx_menu.setOnSelectWithContext(menuSelect, &status);
    const menu_pref = try ctx_menu.widget.getPreferredSize();
    try ctx_menu.widget.layout(layout.Rect.init(0, 0, menu_pref.width, menu_pref.height));

    var focused_tree = true;
    var running = true;
    while (running) {
        renderer.back.clear();
        const content = style.drawChrome(&renderer, palette, "zit file manager", "tree view / typeahead / detail pane");

        if (content.height > 6 and content.width > 20) {
            const gap: u16 = 2;
            const tree_w: u16 = if (content.width > 72) 32 else content.width / 3;
            const files_w: u16 = if (content.width > tree_w + gap) content.width - tree_w - gap else 0;
            const tree_rect = layout.Rect.init(content.x, content.y, tree_w, content.height);
            const files_rect = layout.Rect.init(content.x + tree_w + gap, content.y, files_w, content.height);

            style.drawPanel(&renderer, tree_rect, palette, "Workspace Tree", palette.accent);
            style.drawPanel(&renderer, files_rect, palette, "Directory View", palette.accent);

            if (tree_rect.width > 4 and tree_rect.height > 4) {
                try tree.widget.layout(layout.Rect.init(tree_rect.x + 2, tree_rect.y + 3, tree_rect.width - 4, tree_rect.height - 5));
                tree.widget.markDirty();
                try tree.widget.draw(&renderer);
            }
            if (files_rect.width > 4 and files_rect.height > 7) {
                renderer.fillRect(files_rect.x + 2, files_rect.y + 3, files_rect.width - 4, 1, ' ', palette.accent, palette.surface_alt, render.Style{ .bold = true });
                renderer.drawSmartStr(files_rect.x + 3, files_rect.y + 3, "NAME", palette.accent, palette.surface_alt, render.Style{ .bold = true });
                if (files_rect.width > 34) renderer.drawSmartStr(files_rect.x + files_rect.width - 18, files_rect.y + 3, "TYPE", palette.accent, palette.surface_alt, render.Style{ .bold = true });
                try list.widget.layout(layout.Rect.init(files_rect.x + 2, files_rect.y + 5, files_rect.width - 4, files_rect.height - 9));
                list.widget.markDirty();
                try list.widget.draw(&renderer);

                const detail_y = files_rect.y + files_rect.height - 3;
                renderer.fillRect(files_rect.x + 2, detail_y, files_rect.width - 4, 1, ' ', palette.text, palette.surface_alt, render.Style{});
                const label = list.getSelectedItem() orelse "(none)";
                var detail_buf: [160]u8 = undefined;
                const detail = std.fmt.bufPrint(&detail_buf, "selected: {s}  |  enter opens  |  q quits", .{label}) catch "q quits";
                renderer.drawSmartStr(files_rect.x + 3, detail_y, detail, palette.accent, palette.surface_alt, render.Style{ .bold = true });
            }
        }

        // Keep the context menu width consistent when reopened.
        const pref = try ctx_menu.widget.getPreferredSize();
        ctx_menu.widget.rect.width = pref.width;
        if (ctx_menu.open) {
            ctx_menu.widget.setFocus(true);
            ctx_menu.widget.markDirty();
            try ctx_menu.widget.draw(&renderer);
        } else {
            ctx_menu.widget.setFocus(false);
        }

        // Status bar at the bottom for quick feedback.
        style.drawStatus(&renderer, palette, status.text);

        try renderer.render();

        if (try app.pollInputOnce()) |event| {
            switch (event) {
                .key => |key| {
                    if (key.key == 'q' and !key.modifiers.ctrl and !key.modifiers.alt) {
                        running = false;
                        continue;
                    }
                    if (key.key == '\t') {
                        focused_tree = !focused_tree;
                        tree.widget.setFocus(focused_tree);
                        list.widget.setFocus(!focused_tree);
                        setStatus(&status, "Focus moved to {s}", .{if (focused_tree) "tree" else "files"});
                        continue;
                    }
                    if (key.key == 'm') {
                        const target = if (focused_tree) tree.widget.rect else list.widget.rect;
                        ctx_menu.openAt(target.x + 2, target.y + 1);
                        ctx_menu.widget.setFocus(true);
                        continue;
                    }

                    // Let the context menu consume keys when open.
                    if (ctx_menu.open and try ctx_menu.widget.handleEvent(event)) continue;

                    if (!ctx_menu.open and (key.key == '\n' or key.key == input.KeyCode.ENTER)) {
                        if (focused_tree) {
                            const folder = selectedFolder(tree);
                            try loadFiles(list, folder);
                            setStatus(&status, "Opened {s}", .{folder});
                        } else {
                            const label = list.getSelectedItem() orelse "(nothing)";
                            setStatus(&status, "Opened {s}", .{label});
                        }
                        continue;
                    }

                    if (focused_tree) {
                        if (try tree.widget.handleEvent(event)) {
                            const folder = selectedFolder(tree);
                            try loadFiles(list, folder);
                            setStatus(&status, "Opened {s}", .{folder});
                        }
                    } else {
                        _ = try list.widget.handleEvent(event);
                        const label = list.getSelectedItem() orelse "(nothing)";
                        setStatus(&status, "Selected {s}", .{label});
                    }
                },
                .mouse => |mouse| {
                    if (mouse.action == .press and mouse.button == 3) {
                        ctx_menu.openAt(mouse.x, mouse.y);
                        ctx_menu.widget.setFocus(true);
                        continue;
                    }

                    if (ctx_menu.open and try ctx_menu.widget.handleEvent(event)) continue;
                    _ = try tree.widget.handleEvent(event);
                    _ = try list.widget.handleEvent(event);
                },
                .resize => {},
                else => {},
            }
        }
    }

    try term.clear();
    try term.moveCursor(0, 0);
}
