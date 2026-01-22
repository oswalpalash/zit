// Example: simple file manager composed of panels and shortcuts.

const std = @import("std");
const zit = @import("zit");
const render = zit.render;
const layout = zit.layout;
const widget = zit.widget;
const theme = zit.widget.theme;
const memory = zit.memory;
const input = zit.input;

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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var memory_manager = try memory.MemoryManager.init(allocator, 1024 * 512, 128);
    defer memory_manager.deinit();

    var term = try zit.terminal.init(memory_manager.getArenaAllocator());
    defer term.deinit() catch {};

    var renderer = try render.Renderer.init(memory_manager.getArenaAllocator(), term.width, term.height);
    defer renderer.deinit();

    var input_handler = zit.input.InputHandler.init(memory_manager.getArenaAllocator(), &term);

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
    const surface = ui_theme.color(.surface);

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
    list.border = .single;
    try loadFiles(list, "apps");

    var split = try widget.SplitPane.init(memory_manager.getWidgetPoolAllocator());
    defer split.deinit();
    split.setOrientation(.horizontal);
    split.setRatio(0.33);
    split.setFirst(&tree.widget);
    split.setSecond(&list.widget);

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
        renderer.fillRect(0, 0, renderer.back.width, renderer.back.height, ' ', text, bg, render.Style{});

        const header = "File manager: arrows navigate, Tab switches focus, m/right-click opens menu";
        renderer.drawSmartStr(1, 0, header, muted, bg, render.Style{});

        if (renderer.back.height > 2 and renderer.back.width > 2) {
            const inner = layout.Rect.init(1, 1, renderer.back.width - 2, renderer.back.height - 2);
            try split.widget.layout(inner);
            try split.widget.draw(&renderer);
        }

        // Keep the context menu width consistent when reopened.
        const pref = try ctx_menu.widget.getPreferredSize();
        ctx_menu.widget.rect.width = pref.width;
        if (ctx_menu.open) {
            ctx_menu.widget.setFocus(true);
            try ctx_menu.widget.draw(&renderer);
        } else {
            ctx_menu.widget.setFocus(false);
        }

        // Status bar at the bottom for quick feedback.
        if (renderer.back.height > 0) {
            const status_y: u16 = renderer.back.height - 1;
            renderer.fillRect(0, status_y, renderer.back.width, 1, ' ', text, surface, render.Style{});
            renderer.drawSmartStr(1, status_y, status.text, text, surface, render.Style{});
        }

        try renderer.render();

        if (try input_handler.pollEvent(64)) |event| {
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
                .resize => |resize| {
                    try renderer.resize(resize.width, resize.height);
                },
                else => {},
            }
        }
    }

    try term.clear();
    try term.moveCursor(0, 0);
}
