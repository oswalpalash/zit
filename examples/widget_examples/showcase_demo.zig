// Example: kitchen-sink showcase of widgets and themes.

const std = @import("std");
const zit = @import("zit");
const render = zit.render;
const layout = zit.layout;
const widget = zit.widget;
const theme = zit.widget.theme;
const memory = zit.memory;
const input = zit.input;
const event = zit.event;

fn enterAlternateScreen() !void {
    try std.fs.File.stdout().writeAll("\x1b[?1049h");
}

fn exitAlternateScreen() !void {
    try std.fs.File.stdout().writeAll("\x1b[?1049l");
}

// A single-file showcase that wires together the new widgets and drag-and-drop events:
// live chart + autocomplete input + context menu + image render modes + draggable tokens.
const MenuAction = enum {
    theme_dark,
    theme_light,
    theme_contrast,
    chart_line,
    chart_bar,
    chart_area,
    chart_stacked_bar,
    chart_pie,
    chart_scatter,
    image_background,
    image_block,
    image_braille,
};

const DragAction = enum {
    energize_chart,
    flip_image,
};

const max_samples: usize = 80;

const DragToken = struct {
    label: []const u8,
    accent: render.Color,
    action: DragAction,
};

const DragStatus = struct {
    active: bool = false,
    hover_target: ?*widget.Widget = null,
    label: []const u8 = "",
    accepted: bool = true,
};

const EventLog = struct {
    allocator: std.mem.Allocator,
    lines: std.ArrayList([]u8),

    fn init(allocator: std.mem.Allocator) EventLog {
        return .{
            .allocator = allocator,
            .lines = std.ArrayList([]u8).empty,
        };
    }

    fn deinit(self: *EventLog) void {
        for (self.lines.items) |line| {
            self.allocator.free(line);
        }
        self.lines.deinit(self.allocator);
    }

    fn push(self: *EventLog, msg: []const u8) void {
        const copy = self.allocator.dupe(u8, msg) catch return;
        self.lines.append(self.allocator, copy) catch {
            self.allocator.free(copy);
            return;
        };
        if (self.lines.items.len > 5) {
            const removed = self.lines.orderedRemove(0);
            self.allocator.free(removed);
        }
    }
};

const DemoState = struct {
    chart: *widget.Chart,
    image: *widget.ImageWidget,
    autocomplete: *widget.AutocompleteInput,
    ctx_menu: *widget.ContextMenu,
    log: EventLog,
    drag_status: DragStatus = .{},
    theme_index: usize = 0,
    chart_type: widget.ChartType = .line,
    image_mode: widget.ImageRenderMode = .background,
    selected_metric: []const u8 = "latency p95",
};

// Event callbacks do not receive context, so stash a pointer here.
var demo_state_ptr: ?*DemoState = null;

fn tokenFromPayload(payload: event.DragPayload) ?*const DragToken {
    return payload.asValue(DragToken);
}

fn acceptChartDrop(_: *widget.Widget, drag: event.DragEventData) bool {
    if (tokenFromPayload(drag.payload)) |token| {
        return token.action == .energize_chart;
    }
    return false;
}

fn acceptImageDrop(_: *widget.Widget, drag: event.DragEventData) bool {
    if (tokenFromPayload(drag.payload)) |token| {
        return token.action == .flip_image;
    }
    return false;
}

fn handleChartDrop(_: *widget.Widget, drag: event.DragEventData) void {
    if (!drag.accepted) return;
    const state = demo_state_ptr orelse return;
    if (tokenFromPayload(drag.payload)) |token| {
        if (token.action == .energize_chart) {
            appendSample(&state.chart.series.items[0].values, state.chart.allocator, 88, max_samples);
            appendSample(&state.chart.series.items[1].values, state.chart.allocator, 160, max_samples);
            cycleChartType(state);
        }
    }
}

fn handleImageDrop(_: *widget.Widget, drag: event.DragEventData) void {
    if (!drag.accepted) return;
    const state = demo_state_ptr orelse return;
    if (tokenFromPayload(drag.payload)) |token| {
        if (token.action == .flip_image) {
            cycleImageMode(state);
        }
    }
}

fn handleDragEvent(ev: *event.Event) bool {
    const state = demo_state_ptr orelse return false;
    switch (ev.type) {
        .drag_start => {
            const data = ev.data.drag_start;
            state.drag_status.active = true;
            state.drag_status.hover_target = null;
            state.drag_status.accepted = true;
            if (tokenFromPayload(data.payload)) |token| {
                state.drag_status.label = token.label;
            } else {
                state.drag_status.label = "drag";
            }
            var buf: [96]u8 = undefined;
            const text = std.fmt.bufPrint(&buf, "drag start @ ({d},{d})", .{ data.x, data.y }) catch return false;
            state.log.push(text);
        },
        .drag_update => {
            const data = ev.data.drag_update;
            state.drag_status.hover_target = ev.target;
            state.drag_status.accepted = data.accepted;
            // Keep a short status line in the log without spamming entries.
            var buf: [96]u8 = undefined;
            const name = if (ev.target) |t|
                if (t == &state.chart.widget) "chart" else if (t == &state.image.widget) "image" else "surface"
            else
                "surface";
            const text = std.fmt.bufPrint(&buf, "drag over {s} @ ({d},{d})", .{ name, data.x, data.y }) catch return false;
            if (state.log.lines.items.len == 0 or !std.mem.eql(u8, state.log.lines.items[state.log.lines.items.len - 1], text)) {
                state.log.push(text);
            }
        },
        .drop => {
            const data = ev.data.drop;
            const token_label = if (tokenFromPayload(data.payload)) |token|
                token.label
            else
                "token";
            var buf: [96]u8 = undefined;
            const target_label = if (ev.target) |t|
                if (t == &state.chart.widget) "chart" else if (t == &state.image.widget) "image" else "surface"
            else
                "surface";
            const verdict = if (data.accepted) "accepted" else "rejected";
            const text = std.fmt.bufPrint(&buf, "drop on {s} ({s}) with {s}", .{ target_label, verdict, token_label }) catch return false;
            state.log.push(text);
            state.drag_status.active = false;
            state.drag_status.hover_target = null;
            state.drag_status.accepted = data.accepted;
        },
        .drag_end => {
            state.drag_status.active = false;
            state.drag_status.hover_target = null;
            state.drag_status.accepted = false;
        },
        else => {},
    }
    return false;
}

fn applyTheme(current: theme.Theme, chart: *widget.Chart, autocomplete: *widget.AutocompleteInput, ctx_menu: *widget.ContextMenu) !void {
    try chart.setTheme(current);
    try autocomplete.setTheme(current);
    try ctx_menu.setTheme(current);
}

fn pointInRect(x: u16, y: u16, rect: layout.Rect) bool {
    return x >= rect.x and y >= rect.y and x < rect.x + rect.width and y < rect.y + rect.height;
}

fn cycleImageMode(state: *DemoState) void {
    state.image_mode = switch (state.image_mode) {
        .background => .block,
        .block => .braille,
        .braille => .background,
    };
    state.image.setRenderMode(state.image_mode);
}

fn cycleChartType(state: *DemoState) void {
    state.chart_type = switch (state.chart_type) {
        .line => .area,
        .area => .bar,
        .bar => .stacked_bar,
        .stacked_bar => .pie,
        .pie => .scatter,
        .scatter => .line,
    };
    state.chart.setType(state.chart_type);
}

fn paintGradient(image: *widget.ImageWidget, accent: render.Color, phase: f32) void {
    const width = image.width;
    const height = image.height;
    var y: u16 = 0;
    while (y < height) : (y += 1) {
        var x: u16 = 0;
        while (x < width) : (x += 1) {
            const t = (@as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(width))) + phase;
            const wave = std.math.sin(t * 2.4);
            const pulse = (std.math.sin((@as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(height)) + phase) * 3.14) + 1.0) * 0.5;
            const r: u8 = @intFromFloat(40 + 160 * pulse);
            const g: u8 = @intFromFloat(40 + 100 * (wave + 1.0) * 0.5);
            const b: u8 = @intFromFloat(60 + 120 * (1.0 - pulse));
            const overlay = render.Color.rgb(r, g, b);
            _ = accent;
            image.setPixel(x, y, overlay);
        }
    }
}

fn appendSample(series: *std.ArrayList(f32), allocator: std.mem.Allocator, value: f32, limit: usize) void {
    series.append(allocator, value) catch return;
    if (series.items.len > limit) {
        _ = series.orderedRemove(0);
    }
}

fn menuLabel(action: MenuAction) []const u8 {
    return switch (action) {
        .theme_dark => "Theme: Dark",
        .theme_light => "Theme: Light",
        .theme_contrast => "Theme: High Contrast",
        .chart_line => "Chart: Line",
        .chart_bar => "Chart: Bar",
        .chart_area => "Chart: Area",
        .chart_stacked_bar => "Chart: Stacked Bar",
        .chart_pie => "Chart: Pie",
        .chart_scatter => "Chart: Scatter",
        .image_background => "Image: Background Mode",
        .image_block => "Image: Block Mode",
        .image_braille => "Image: Braille Mode",
    };
}

fn handleMenuSelection(_: usize, item: widget.ContextMenuItem, ctx: ?*anyopaque) void {
    const state = demo_state_ptr orelse return;
    _ = ctx;
    const action_ptr: ?*const MenuAction = if (item.data) |ptr|
        @ptrCast(@alignCast(ptr))
    else
        null;
    if (action_ptr) |action| {
        switch (action.*) {
            .theme_dark => {
                state.theme_index = 0;
            },
            .theme_light => {
                state.theme_index = 1;
            },
            .theme_contrast => {
                state.theme_index = 2;
            },
            .chart_line => {
                state.chart_type = .line;
                state.chart.setType(.line);
            },
            .chart_bar => {
                state.chart_type = .bar;
                state.chart.setType(.bar);
            },
            .chart_area => {
                state.chart_type = .area;
                state.chart.setType(.area);
            },
            .chart_stacked_bar => {
                state.chart_type = .stacked_bar;
                state.chart.setType(.stacked_bar);
            },
            .chart_pie => {
                state.chart_type = .pie;
                state.chart.setType(.pie);
            },
            .chart_scatter => {
                state.chart_type = .scatter;
                state.chart.setType(.scatter);
            },
            .image_background => {
                state.image_mode = .background;
                state.image.setRenderMode(.background);
            },
            .image_block => {
                state.image_mode = .block;
                state.image.setRenderMode(.block);
            },
            .image_braille => {
                state.image_mode = .braille;
                state.image.setRenderMode(.braille);
            },
        }
        state.log.push(menuLabel(action.*));
    }
}

fn handleAutocompleteSelection(choice: []const u8) void {
    const state = demo_state_ptr orelse return;
    state.selected_metric = choice;
    var buf: [96]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "search -> {s}", .{choice}) catch return;
    state.log.push(text);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var memory_manager = try memory.MemoryManager.init(allocator, 1024 * 1024, 128);
    defer memory_manager.deinit();

    var term = try zit.terminal.init(memory_manager.getArenaAllocator());
    defer term.deinit() catch {};

    var renderer = try render.Renderer.init(memory_manager.getArenaAllocator(), term.width, term.height);
    defer renderer.deinit();

    var input_handler = zit.input.InputHandler.init(memory_manager.getArenaAllocator(), &term);

    try enterAlternateScreen();
    defer exitAlternateScreen() catch {};

    try term.enableRawMode();
    defer term.disableRawMode() catch {};

    try term.hideCursor();
    defer term.showCursor() catch {};

    try input_handler.enableMouse();
    defer input_handler.disableMouse() catch {};

    var app = event.Application.init(memory_manager.getArenaAllocator());
    defer app.deinit();

    var root = try widget.Container.init(memory_manager.getWidgetPoolAllocator());
    defer root.deinit();

    var chart = try widget.Chart.init(memory_manager.getWidgetPoolAllocator());
    defer chart.deinit();
    chart.setType(.line);
    chart.setPadding(1);
    chart.setShowAxes(true);

    var autocomplete = try widget.AutocompleteInput.init(memory_manager.getWidgetPoolAllocator(), 64);
    defer autocomplete.deinit();
    const suggestions = [_][]const u8{
        "latency p95",
        "throughput rps",
        "errors per minute",
        "cache hit rate",
        "active sessions",
        "braille mode",
    };
    try autocomplete.setSuggestions(&suggestions);
    autocomplete.setMaxVisible(6);
    autocomplete.widget.focused = true;
    autocomplete.setOnSelect(handleAutocompleteSelection);

    var ctx_menu = try widget.ContextMenu.init(memory_manager.getWidgetPoolAllocator());
    defer ctx_menu.deinit();

    var menu_actions = [_]MenuAction{
        .theme_dark,
        .theme_light,
        .theme_contrast,
        .chart_line,
        .chart_bar,
        .chart_area,
        .chart_stacked_bar,
        .chart_pie,
        .chart_scatter,
        .image_background,
        .image_block,
        .image_braille,
    };
    for (menu_actions, 0..) |act, i| {
        try ctx_menu.addItem(menuLabel(act), true, @ptrCast(&menu_actions[i]));
    }
    ctx_menu.setOnSelect(handleMenuSelection, null);

    var image = try widget.ImageWidget.init(memory_manager.getWidgetPoolAllocator(), 32, 12);
    defer image.deinit();

    try root.addChild(&chart.widget);
    try root.addChild(&autocomplete.widget);
    try root.addChild(&ctx_menu.widget);
    try root.addChild(&image.widget);
    app.setRoot(root);

    var state = DemoState{
        .chart = chart,
        .image = image,
        .autocomplete = autocomplete,
        .ctx_menu = ctx_menu,
        .log = EventLog.init(memory_manager.getArenaAllocator()),
    };
    defer state.log.deinit();
    demo_state_ptr = &state;

    try app.registerDropTarget(.{ .widget = &chart.widget, .accept = acceptChartDrop, .on_drop = handleChartDrop });
    try app.registerDropTarget(.{ .widget = &image.widget, .accept = acceptImageDrop, .on_drop = handleImageDrop });

    _ = try app.addEventListener(.drag_start, handleDragEvent, null);
    _ = try app.addEventListener(.drag_update, handleDragEvent, null);
    _ = try app.addEventListener(.drop, handleDragEvent, null);
    _ = try app.addEventListener(.drag_end, handleDragEvent, null);

    const themes = [_]theme.Theme{
        theme.Theme.dark(),
        theme.Theme.light(),
        theme.Theme.highContrast(),
    };
    try applyTheme(themes[state.theme_index], chart, autocomplete, ctx_menu);

    try chart.addSeries("Throughput", &[_]f32{ 42, 48, 45, 51, 57, 64 }, null, null);
    try chart.addSeries("Latency", &[_]f32{ 120, 110, 130, 125, 135, 128 }, null, null);
    var phase: f32 = 0;

    const drag_tokens = [_]DragToken{
        .{ .label = "Drag for spikes", .accent = render.Color.rgb(246, 122, 95), .action = .energize_chart },
        .{ .label = "Drag image mode", .accent = render.Color.rgb(102, 184, 255), .action = .flip_image },
    };

    var running = true;
    while (running) {
        const current_theme = themes[state.theme_index];
        try applyTheme(current_theme, chart, autocomplete, ctx_menu);
        ctx_menu.widget.setFocus(ctx_menu.open);

        const bg = current_theme.color(.background);
        const surface = current_theme.color(.surface);
        const accent = current_theme.color(.accent);
        const text = current_theme.color(.text);
        const muted = current_theme.color(.muted);

        renderer.back.clear();
        renderer.fillRect(0, 0, renderer.back.width, renderer.back.height, ' ', text, bg, render.Style{});
        renderer.drawBox(0, 0, renderer.back.width, renderer.back.height, render.BorderStyle.single, accent, bg, render.Style{});

        const inner = layout.Rect.init(1, 1, renderer.back.width - 2, renderer.back.height - 2);
        const header_height: u16 = if (inner.height > 6) 5 else inner.height / 3;
        const chart_height: u16 = if (inner.height > 20) inner.height - header_height - 6 else inner.height / 2;
        const chart_width: u16 = if (inner.width > 50) inner.width - 24 else inner.width;
        const chart_rect = layout.Rect.init(inner.x + 1, inner.y + header_height, chart_width, chart_height);
        const info_rect = layout.Rect.init(chart_rect.x + chart_rect.width + 1, chart_rect.y, inner.width - chart_rect.width - 3, chart_height);
        const search_rect = layout.Rect.init(inner.x + 1, inner.y + 1, chart_width, header_height - 2);
        const image_rect = layout.Rect.init(info_rect.x, info_rect.y + 2, info_rect.width, info_rect.height / 2);
        const log_height: u16 = if (inner.height > 6) 3 else 1;
        const log_y = if (inner.height > log_height) inner.y + inner.height - log_height else inner.y;
        const log_rect = layout.Rect.init(inner.x + 1, log_y, inner.width - 2, log_height);

        try autocomplete.widget.layout(search_rect);
        try chart.widget.layout(chart_rect);
        try image.widget.layout(image_rect);

        paintGradient(image, accent, phase);
        image.setRenderMode(state.image_mode);
        chart.setType(state.chart_type);

        // Title + instructions.
        renderer.drawSmartStr(inner.x + 1, inner.y, "Zit showcase: chart + autocomplete + context menu + drag/drop", accent, bg, render.Style{ .bold = true });
        renderer.drawSmartStr(inner.x + 1, inner.y + 1, "Keys: q quit | t theme | c chart | m image | right click for menu | drag chips onto chart/image", text, bg, render.Style{});

        // Section backgrounds.
        renderer.drawBox(chart_rect.x - 1, chart_rect.y - 1, chart_rect.width + 2, chart_rect.height + 2, render.BorderStyle.single, accent, surface, render.Style{});
        renderer.drawBox(info_rect.x - 1, info_rect.y - 1, info_rect.width + 2, info_rect.height + 2, render.BorderStyle.single, accent, surface, render.Style{});
        renderer.drawSmartStr(chart_rect.x, chart_rect.y - 2, "Live chart", accent, bg, render.Style{ .bold = true });
        renderer.drawSmartStr(info_rect.x, info_rect.y - 2, "Image + drag targets", accent, bg, render.Style{ .bold = true });

        try autocomplete.widget.draw(&renderer);
        try chart.widget.draw(&renderer);
        try image.widget.draw(&renderer);

        // Drag tokens.
        var token_rects: [drag_tokens.len]layout.Rect = undefined;
        const token_base_y = chart_rect.y + chart_rect.height + 1;
        var idx: usize = 0;
        while (idx < drag_tokens.len) : (idx += 1) {
            const token = drag_tokens[idx];
            const token_x = inner.x + 2 + @as(u16, @intCast(idx)) * 24;
            token_rects[idx] = layout.Rect.init(token_x, token_base_y, 20, 3);
            const rect = token_rects[idx];
            renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', text, token.accent, render.Style{});
            renderer.drawBox(rect.x, rect.y, rect.width, rect.height, render.BorderStyle.rounded, text, token.accent, render.Style{});
            renderer.drawSmartStr(rect.x + 1, rect.y + 1, token.label, render.Color.named(render.NamedColor.black), token.accent, render.Style{ .bold = true });
        }

        // Event log.
        renderer.drawSmartStr(log_rect.x, log_rect.y - 1, "Event log (drag + menu + search):", accent, bg, render.Style{ .bold = true });
        var line: usize = 0;
        const visible_log_lines = @min(state.log.lines.items.len, @as(usize, log_rect.height));
        const start_line = if (visible_log_lines > 0 and state.log.lines.items.len > visible_log_lines) state.log.lines.items.len - visible_log_lines else 0;
        var row: u16 = log_rect.y;
        while (line < state.log.lines.items.len - start_line and row < log_rect.y + log_rect.height) : ({
            line += 1;
            row += 1;
        }) {
            const msg = state.log.lines.items[start_line + line];
            renderer.drawSmartStr(log_rect.x, row, msg, muted, surface, render.Style{});
        }

        // Drag cues.
        if (state.drag_status.active) {
            const target = state.drag_status.hover_target;
            const colors = event.DropVisuals.colorsFromTheme(current_theme);
            const highlight_state: event.DropVisuals.State = if (target == null)
                .idle
            else if (state.drag_status.accepted)
                .valid
            else
                .invalid;

            if (target == &chart.widget) {
                event.DropVisuals.outline(&renderer, chart_rect, highlight_state, colors);
            } else if (target == &image.widget) {
                event.DropVisuals.outline(&renderer, image_rect, highlight_state, colors);
            }

            const drag_label_x = if (inner.width > 24) inner.x + inner.width - 24 else inner.x + 1;
            const drag_label = switch (highlight_state) {
                .valid => "dragging",
                .invalid => "blocked",
                .idle => "dragging",
            };
            const drag_color = if (highlight_state == .invalid) current_theme.color(.danger) else accent;
            var drag_label_buf: [64]u8 = undefined;
            const label_text = std.fmt.bufPrint(&drag_label_buf, "{s}: {s}", .{ drag_label, state.drag_status.label }) catch drag_label;
            renderer.drawSmartStr(drag_label_x, inner.y, label_text, drag_color, bg, render.Style{ .bold = true });
        }

        // Context menu overlay (drawn last so it floats).
        const menu_size = try ctx_menu.widget.getPreferredSize();
        if (ctx_menu.open) {
            try ctx_menu.widget.layout(layout.Rect.init(ctx_menu.widget.rect.x, ctx_menu.widget.rect.y, menu_size.width, menu_size.height));
            try ctx_menu.widget.draw(&renderer);
        }

        // Status text.
        var status_buf: [128]u8 = undefined;
        const status = std.fmt.bufPrint(
            &status_buf,
            "Theme: {s} | Chart: {s} | Image: {s} | Search: {s}",
            .{
                switch (state.theme_index) {
                    0 => "dark",
                    1 => "light",
                    else => "high-contrast",
                },
                switch (state.chart_type) {
                    .line => "line",
                    .area => "area",
                    .bar => "bar",
                    .stacked_bar => "stacked bar",
                    .pie => "pie",
                    .scatter => "scatter",
                },
                switch (state.image_mode) {
                    .background => "background",
                    .block => "block",
                    .braille => "braille",
                },
                state.selected_metric,
            },
        ) catch "status";
        renderer.drawSmartStr(inner.x + 1, log_rect.y + log_rect.height, status, muted, bg, render.Style{});

        try renderer.render();

        // Animate chart + image.
        phase += 0.08;
        const traffic = 42.0 + 18.0 * std.math.sin(phase);
        const latency = 110.0 + 20.0 * std.math.sin(phase * 0.7 + 1.2);
        appendSample(&chart.series.items[0].values, chart.allocator, traffic, max_samples);
        appendSample(&chart.series.items[1].values, chart.allocator, latency, max_samples);

        if (try input_handler.pollEvent(32)) |ev| {
            switch (ev) {
                .key => |key| {
                    if (key.key == 'q') {
                        running = false;
                    } else if (key.key == 't') {
                        state.theme_index = (state.theme_index + 1) % themes.len;
                    } else if (key.key == 'c') {
                        cycleChartType(&state);
                    } else if (key.key == 'm') {
                        cycleImageMode(&state);
                    } else {
                        _ = try ctx_menu.widget.handleEvent(ev);
                        _ = try autocomplete.widget.handleEvent(ev);
                    }
                },
                .mouse => |mouse_event| {
                    if (mouse_event.action == .press and mouse_event.button == 3) {
                        ctx_menu.openAt(mouse_event.x, mouse_event.y);
                        continue;
                    }

                    if (mouse_event.action == .press and mouse_event.button == 1) {
                        idx = 0;
                        while (idx < drag_tokens.len) : (idx += 1) {
                            if (pointInRect(mouse_event.x, mouse_event.y, token_rects[idx])) {
                                const payload = try event.DragPayload.fromValue(allocator, drag_tokens[idx]);
                                try app.beginDrag(&root.widget, mouse_event.x, mouse_event.y, mouse_event.button, payload);
                                break;
                            }
                        }
                    } else if (mouse_event.action == .move and app.drag_manager.active) {
                        const drop_target = if (app.hitTestDropTarget(mouse_event.x, mouse_event.y)) |entry|
                            entry.widget
                        else
                            null;
                        try app.updateDrag(mouse_event.x, mouse_event.y, drop_target);
                    } else if (mouse_event.action == .release and app.drag_manager.active) {
                        const drop_target = if (app.hitTestDropTarget(mouse_event.x, mouse_event.y)) |entry|
                            entry.widget
                        else
                            null;
                        try app.endDrag(mouse_event.x, mouse_event.y, drop_target);
                    } else {
                        _ = try ctx_menu.widget.handleEvent(ev);
                        _ = try autocomplete.widget.handleEvent(ev);
                    }
                },
                .resize => |size| {
                    try renderer.resize(size.width, size.height);
                },
                else => {},
            }
        }

        try app.event_queue.processEvents();
    }

    try term.clear();
    try term.moveCursor(0, 0);
}
