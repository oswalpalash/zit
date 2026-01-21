const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const form = @import("../form.zig");

/// Multi-line text editor with scrolling, undo/redo, and clipboard support.
pub const TextArea = struct {
    widget: base.Widget,
    buffer: std.ArrayList(u8),
    cursor: usize = 0,
    preferred_col: usize = 0,
    scroll_row: usize = 0,
    scroll_col: usize = 0,
    max_bytes: usize,

    fg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    bg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    focused_fg: render.Color = render.Color{ .named_color = render.NamedColor.black },
    focused_bg: render.Color = render.Color{ .named_color = render.NamedColor.cyan },
    disabled_fg: render.Color = render.Color{ .named_color = render.NamedColor.bright_black },
    disabled_bg: render.Color = render.Color{ .named_color = render.NamedColor.black },
    style: render.Style = render.Style{},
    border: render.BorderStyle = .single,
    show_border: bool = true,
    placeholder: []const u8 = "",
    placeholder_owned: bool = false,
    on_change: ?*const fn ([]const u8) void = null,
    on_submit: ?*const fn ([]const u8) void = null,
    submit_on_ctrl_enter: bool = true,
    undo_redo: input.UndoRedoStack,
    clipboard_storage: input.Clipboard,
    clipboard: *input.Clipboard,
    owns_clipboard: bool = true,
    allocator: std.mem.Allocator,

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator, max_bytes: usize) !*TextArea {
        const capacity = @max(max_bytes, 1);
        const self = try allocator.create(TextArea);

        const buffer = try std.ArrayList(u8).initCapacity(allocator, capacity);

        self.* = TextArea{
            .widget = base.Widget.init(&vtable),
            .buffer = buffer,
            .max_bytes = capacity,
            .undo_redo = input.UndoRedoStack.init(allocator),
            .clipboard_storage = input.Clipboard.init(allocator),
            .clipboard = undefined,
            .allocator = allocator,
        };

        self.clipboard = &self.clipboard_storage;
        self.widget.setFocusRing(render.FocusRingStyle{
            .color = self.focused_bg,
            .border = .rounded,
            .style = render.Style{ .bold = true },
        });
        try self.undo_redo.capture(self.buffer.items);
        return self;
    }

    pub fn deinit(self: *TextArea) void {
        if (self.placeholder_owned and self.placeholder.len > 0) {
            self.allocator.free(self.placeholder);
        }
        self.undo_redo.deinit();
        if (self.owns_clipboard) {
            self.clipboard_storage.deinit();
        }
        self.buffer.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn setText(self: *TextArea, text: []const u8) !void {
        try self.writeText(text);
        try self.pushHistory();
        self.notifyChange();
    }

    pub fn getText(self: *TextArea) []const u8 {
        return self.buffer.items;
    }

    pub fn setPlaceholder(self: *TextArea, placeholder: []const u8) !void {
        if (self.placeholder_owned and self.placeholder.len > 0) {
            self.allocator.free(self.placeholder);
        }

        if (placeholder.len == 0) {
            self.placeholder = "";
            self.placeholder_owned = false;
            return;
        }

        self.placeholder = try self.allocator.dupe(u8, placeholder);
        self.placeholder_owned = true;
    }

    pub fn setColors(self: *TextArea, fg: render.Color, bg: render.Color, focused_fg: render.Color, focused_bg: render.Color) void {
        self.fg = fg;
        self.bg = bg;
        self.focused_fg = focused_fg;
        self.focused_bg = focused_bg;
    }

    pub fn setBorder(self: *TextArea, border: render.BorderStyle) void {
        self.border = border;
        self.show_border = border != .none;
    }

    pub fn setOnChange(self: *TextArea, callback: *const fn ([]const u8) void) void {
        self.on_change = callback;
    }

    pub fn setOnSubmit(self: *TextArea, callback: *const fn ([]const u8) void) void {
        self.on_submit = callback;
    }

    pub fn submitOnCtrlEnter(self: *TextArea, enable: bool) void {
        self.submit_on_ctrl_enter = enable;
    }

    pub fn setHistoryDepth(self: *TextArea, depth: usize) void {
        self.undo_redo.setMaxDepth(depth);
    }

    pub fn useClipboard(self: *TextArea, clipboard: *input.Clipboard) void {
        if (self.owns_clipboard) {
            self.clipboard_storage.deinit();
        }
        self.clipboard = clipboard;
        self.owns_clipboard = false;
    }

    pub fn preferSystemClipboard(self: *TextArea, enable: bool) void {
        self.clipboard.preferSystem(enable);
    }

    pub fn undo(self: *TextArea) bool {
        return (self.performUndo() catch false);
    }

    pub fn redo(self: *TextArea) bool {
        return (self.performRedo() catch false);
    }

    pub fn validate(self: *TextArea, allocator: std.mem.Allocator, field_name: []const u8, rules: []const form.Rule) !form.ValidationResult {
        return form.validateField(allocator, field_name, self.getText(), rules);
    }

    pub fn cursorPosition(self: *const TextArea) Position {
        return self.positionForIndex(self.cursor);
    }

    fn notifyChange(self: *TextArea) void {
        if (self.on_change) |callback| {
            callback(self.buffer.items);
        }
    }

    fn writeText(self: *TextArea, text: []const u8) !void {
        self.buffer.clearRetainingCapacity();
        const copy_len = @min(text.len, self.max_bytes);
        try self.buffer.appendSlice(self.allocator, text[0..copy_len]);
        self.cursor = self.buffer.items.len;
        self.preferred_col = self.cursorPosition().col;
        self.scroll_row = 0;
        self.scroll_col = 0;
    }

    fn pushHistory(self: *TextArea) !void {
        try self.undo_redo.capture(self.buffer.items);
    }

    fn clampCursor(self: *TextArea) void {
        if (self.cursor > self.buffer.items.len) self.cursor = self.buffer.items.len;
    }

    fn resetPreferredColumn(self: *TextArea) void {
        self.preferred_col = self.cursorPosition().col;
    }

    fn applySnapshot(self: *TextArea, snapshot: []const u8) !void {
        try self.writeText(snapshot);
        self.notifyChange();
    }

    const Position = struct { row: usize, col: usize };

    fn positionForIndex(self: *const TextArea, idx: usize) Position {
        var row: usize = 0;
        var col: usize = 0;
        var i: usize = 0;
        while (i < idx and i < self.buffer.items.len) : (i += 1) {
            if (self.buffer.items[i] == '\n') {
                row += 1;
                col = 0;
            } else {
                col += 1;
            }
        }
        return .{ .row = row, .col = col };
    }

    fn lineRange(self: *const TextArea, target: usize) ?struct { start: usize, end: usize } {
        if (self.buffer.items.len == 0) {
            return if (target == 0) .{ .start = 0, .end = 0 } else null;
        }

        var start: usize = 0;
        var row: usize = 0;
        while (start <= self.buffer.items.len) {
            var end = start;
            while (end < self.buffer.items.len and self.buffer.items[end] != '\n') : (end += 1) {}

            if (row == target) return .{ .start = start, .end = end };
            if (end >= self.buffer.items.len) break;

            start = end + 1;
            row += 1;
        }

        if (row + 1 == target and start == self.buffer.items.len) {
            return .{ .start = start, .end = start };
        }

        return null;
    }

    fn ensureVisible(self: *TextArea, inner_width: u16, inner_height: u16) void {
        if (inner_width == 0 or inner_height == 0) return;

        const pos = self.cursorPosition();
        if (pos.row < self.scroll_row) {
            self.scroll_row = pos.row;
        } else {
            const bottom = self.scroll_row + @as(usize, @intCast(inner_height - 1));
            if (pos.row > bottom) {
                self.scroll_row = pos.row - @as(usize, @intCast(inner_height - 1));
            }
        }

        if (pos.col < self.scroll_col) {
            self.scroll_col = pos.col;
        } else {
            const right = self.scroll_col + @as(usize, @intCast(inner_width - 1));
            if (pos.col > right) {
                self.scroll_col = pos.col - @as(usize, @intCast(inner_width - 1));
            }
        }
    }

    fn viewportSize(self: *const TextArea) struct { width: u16, height: u16 } {
        const border_adjust: u16 = if (self.show_border) 1 else 0;
        const width = if (self.widget.rect.width > border_adjust * 2) self.widget.rect.width - (border_adjust * 2) else 0;
        const height = if (self.widget.rect.height > border_adjust * 2) self.widget.rect.height - (border_adjust * 2) else 0;
        return .{ .width = width, .height = height };
    }

    fn applyEditorAction(self: *TextArea, action: input.EditorAction) anyerror!bool {
        const viewport = self.viewportSize();
        switch (action) {
            .cursor_left => {
                if (self.cursor > 0) {
                    self.cursor -= 1;
                    self.resetPreferredColumn();
                    self.ensureVisible(viewport.width, viewport.height);
                    return true;
                }
                return false;
            },
            .cursor_right => {
                if (self.cursor < self.buffer.items.len) {
                    self.cursor += 1;
                    self.resetPreferredColumn();
                    self.ensureVisible(viewport.width, viewport.height);
                    return true;
                }
                return false;
            },
            .cursor_up => {
                return self.moveVertical(-1, viewport.height);
            },
            .cursor_down => {
                return self.moveVertical(1, viewport.height);
            },
            .line_start => {
                if (self.lineRange(self.cursorPosition().row)) |range| {
                    self.cursor = range.start;
                    self.resetPreferredColumn();
                    self.ensureVisible(viewport.width, viewport.height);
                    return true;
                }
                return false;
            },
            .line_end => {
                if (self.lineRange(self.cursorPosition().row)) |range| {
                    self.cursor = range.end;
                    self.resetPreferredColumn();
                    self.ensureVisible(viewport.width, viewport.height);
                    return true;
                }
                return false;
            },
            .page_up => {
                const delta = if (viewport.height == 0) -1 else -@as(i32, @intCast(viewport.height));
                return self.moveVertical(delta, viewport.height);
            },
            .page_down => {
                const delta = if (viewport.height == 0) 1 else @as(i32, @intCast(viewport.height));
                return self.moveVertical(delta, viewport.height);
            },
            .undo => return self.performUndo(),
            .redo => return self.performRedo(),
            .copy => return self.performCopy(),
            .paste => return self.performPaste(),
            .cut => return self.performCut(),
            else => return false,
        }
    }

    fn moveVertical(self: *TextArea, delta: i32, inner_height: u16) bool {
        if (self.buffer.items.len == 0 and delta <= 0) return false;

        const pos = self.cursorPosition();
        const desired_col = self.preferred_col;
        const current_row_signed: i32 = @intCast(pos.row);
        var target_row_signed = current_row_signed + delta;
        if (target_row_signed < 0) target_row_signed = 0;

        const target_row: usize = @intCast(target_row_signed);
        if (self.lineRange(target_row)) |range| {
            const line_len = range.end - range.start;
            const new_col = @min(line_len, desired_col);
            self.cursor = range.start + new_col;
        } else {
            self.cursor = self.buffer.items.len;
        }
        self.resetPreferredColumn();
        self.ensureVisible(self.viewportSize().width, inner_height);
        return true;
    }

    fn performUndo(self: *TextArea) anyerror!bool {
        if (self.undo_redo.undoOp()) |snapshot| {
            try self.applySnapshot(snapshot);
            self.clampCursor();
            self.resetPreferredColumn();
            self.ensureVisible(self.viewportSize().width, self.viewportSize().height);
            return true;
        }
        return false;
    }

    fn performRedo(self: *TextArea) anyerror!bool {
        if (self.undo_redo.redoOp()) |snapshot| {
            try self.applySnapshot(snapshot);
            self.clampCursor();
            self.resetPreferredColumn();
            self.ensureVisible(self.viewportSize().width, self.viewportSize().height);
            return true;
        }
        return false;
    }

    fn performCopy(self: *TextArea) anyerror!bool {
        try self.clipboard.copy(self.buffer.items);
        return self.buffer.items.len > 0;
    }

    fn performCut(self: *TextArea) anyerror!bool {
        if (self.buffer.items.len == 0) return false;

        try self.clipboard.copy(self.buffer.items);
        self.buffer.clearRetainingCapacity();
        self.cursor = 0;
        self.resetPreferredColumn();
        self.scroll_row = 0;
        self.scroll_col = 0;
        try self.pushHistory();
        self.notifyChange();
        return true;
    }

    fn performPaste(self: *TextArea) anyerror!bool {
        const pasted = self.clipboard.paste() orelse return false;
        if (pasted.len == 0) return false;

        const remaining = if (self.buffer.items.len >= self.max_bytes) 0 else self.max_bytes - self.buffer.items.len;
        if (remaining == 0) return false;

        const insert_len = @min(remaining, pasted.len);
        try self.buffer.insertSlice(self.allocator, self.cursor, pasted[0..insert_len]);
        self.cursor += insert_len;
        self.resetPreferredColumn();
        try self.pushHistory();
        self.notifyChange();
        return true;
    }

    fn insertByte(self: *TextArea, value: u8) !void {
        if (self.buffer.items.len >= self.max_bytes) return;
        try self.buffer.insert(self.allocator, self.cursor, value);
        self.cursor += 1;
        self.resetPreferredColumn();
        try self.pushHistory();
        self.notifyChange();
    }

    fn deleteBackward(self: *TextArea) !bool {
        if (self.cursor == 0 or self.buffer.items.len == 0) return false;
        _ = self.buffer.orderedRemove(self.cursor - 1);
        self.cursor -= 1;
        self.resetPreferredColumn();
        try self.pushHistory();
        self.notifyChange();
        return true;
    }

    fn deleteForward(self: *TextArea) !bool {
        if (self.cursor >= self.buffer.items.len) return false;
        _ = self.buffer.orderedRemove(self.cursor);
        self.resetPreferredColumn();
        try self.pushHistory();
        self.notifyChange();
        return true;
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*TextArea, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;

        const rect = self.widget.rect;

        const fg = if (!self.widget.enabled)
            self.disabled_fg
        else if (self.widget.focused)
            self.focused_fg
        else
            self.fg;

        const bg = if (!self.widget.enabled)
            self.disabled_bg
        else if (self.widget.focused)
            self.focused_bg
        else
            self.bg;

        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', fg, bg, self.style);
        if (self.show_border) {
            renderer.drawBox(rect.x, rect.y, rect.width, rect.height, self.border, fg, bg, self.style);
        }

        const border_adjust: u16 = if (self.show_border) 1 else 0;
        const inner_x = rect.x + border_adjust;
        const inner_y = rect.y + border_adjust;
        const viewport = self.viewportSize();
        if (viewport.width == 0 or viewport.height == 0) {
            self.widget.drawFocusRing(renderer);
            return;
        }

        if (self.buffer.items.len == 0 and self.placeholder.len > 0) {
            const clipped = self.placeholder[0..@min(self.placeholder.len, viewport.width)];
            renderer.drawStr(inner_x, inner_y, clipped, fg, bg, self.style);
        } else {
            var row: u16 = 0;
            while (row < viewport.height) : (row += 1) {
                const line_idx = self.scroll_row + @as(usize, @intCast(row));
                if (self.lineRange(line_idx)) |range| {
                    if (range.start == range.end and range.start >= self.buffer.items.len) break;
                    const line = self.buffer.items[range.start..range.end];
                    const visible = if (self.scroll_col >= line.len) "" else blk: {
                        const slice_start = self.scroll_col;
                        const end = @min(line.len, self.scroll_col + @as(usize, @intCast(viewport.width)));
                        break :blk line[slice_start..end];
                    };
                    renderer.drawStr(inner_x, inner_y + row, visible, fg, bg, self.style);
                } else {
                    break;
                }
            }
        }

        if (self.widget.focused) {
            const pos = self.cursorPosition();
            if (pos.row >= self.scroll_row and pos.row < self.scroll_row + @as(usize, @intCast(viewport.height))) {
                if (pos.col >= self.scroll_col and pos.col <= self.scroll_col + @as(usize, @intCast(viewport.width))) {
                    const cx = inner_x + @as(u16, @intCast(pos.col - self.scroll_col));
                    const cy = inner_y + @as(u16, @intCast(pos.row - self.scroll_row));
                    renderer.drawChar(cx, cy, '_', fg, bg, render.Style{ .underline = true });
                }
            }
        }

        self.widget.drawFocusRing(renderer);
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*TextArea, @ptrCast(@alignCast(widget_ptr)));

        if (!self.widget.visible or !self.widget.enabled) return false;

        if (event == .key and self.widget.focused) {
            const key_event = event.key;
            const profiles = [_]input.KeybindingProfile{
                input.KeybindingProfile.commonEditing(),
                input.KeybindingProfile.emacs(),
                input.KeybindingProfile.vi(),
            };

            self.clampCursor();

            if (input.editorActionForEvent(key_event, &profiles)) |action| {
                if (try self.applyEditorAction(action)) {
                    const viewport = self.viewportSize();
                    self.ensureVisible(viewport.width, viewport.height);
                    return true;
                }
            }

            switch (key_event.key) {
                input.KeyCode.ENTER => {
                    if (self.submit_on_ctrl_enter and key_event.modifiers.ctrl) {
                        if (self.on_submit) |callback| callback(self.buffer.items);
                        return true;
                    }
                    try self.insertByte('\n');
                    self.ensureVisible(self.viewportSize().width, self.viewportSize().height);
                    return true;
                },
                input.KeyCode.BACKSPACE => {
                    if (try self.deleteBackward()) {
                        self.ensureVisible(self.viewportSize().width, self.viewportSize().height);
                    }
                    return true;
                },
                input.KeyCode.DELETE => {
                    if (try self.deleteForward()) {
                        self.ensureVisible(self.viewportSize().width, self.viewportSize().height);
                    }
                    return true;
                },
                else => {
                    if (key_event.isPrintable() and !key_event.modifiers.ctrl and !key_event.modifiers.alt) {
                        try self.insertByte(@as(u8, @intCast(key_event.key)));
                        self.ensureVisible(self.viewportSize().width, self.viewportSize().height);
                        return true;
                    }
                },
            }
        } else if (event == .mouse) {
            const mouse_event = event.mouse;
            if (mouse_event.action == .press and mouse_event.button == 1) {
                return self.widget.rect.contains(mouse_event.x, mouse_event.y);
            }
        }

        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*TextArea, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*TextArea, @ptrCast(@alignCast(widget_ptr)));
        const border_adjust: u16 = if (self.show_border) 2 else 0;
        return layout_module.Size.init(
            40 + border_adjust,
            5 + border_adjust,
        );
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*TextArea, @ptrCast(@alignCast(widget_ptr)));
        return self.widget.enabled;
    }
};

test "text area inserts newlines and supports undo" {
    const alloc = std.testing.allocator;
    var area = try TextArea.init(alloc, 128);
    defer area.deinit();
    area.widget.focused = true;

    const enter = input.Event{ .key = input.KeyEvent.init(input.KeyCode.ENTER, input.KeyModifiers{}) };
    const a = input.Event{ .key = input.KeyEvent.init('a', input.KeyModifiers{}) };
    const b = input.Event{ .key = input.KeyEvent.init('b', input.KeyModifiers{}) };

    try std.testing.expect(try area.widget.handleEvent(a));
    try std.testing.expect(try area.widget.handleEvent(enter));
    try std.testing.expect(try area.widget.handleEvent(b));

    try std.testing.expectEqualStrings("a\nb", area.getText());
    try std.testing.expect(area.undo());
    try std.testing.expectEqualStrings("a\n", area.getText());
    try std.testing.expect(area.redo());
    try std.testing.expectEqualStrings("a\nb", area.getText());
}

test "text area cursor navigation respects lines" {
    const alloc = std.testing.allocator;
    var area = try TextArea.init(alloc, 64);
    defer area.deinit();
    area.widget.focused = true;
    try area.setText("hello\nworld");

    const left = input.Event{ .key = input.KeyEvent.init(input.KeyCode.LEFT, input.KeyModifiers{}) };
    const up = input.Event{ .key = input.KeyEvent.init(input.KeyCode.UP, input.KeyModifiers{}) };
    const right = input.Event{ .key = input.KeyEvent.init(input.KeyCode.RIGHT, input.KeyModifiers{}) };

    try std.testing.expect(try area.widget.handleEvent(left));
    try std.testing.expect(try area.widget.handleEvent(left));
    try std.testing.expect(try area.widget.handleEvent(up));

    var pos = area.cursorPosition();
    try std.testing.expectEqual(@as(usize, 0), pos.row);
    try std.testing.expectEqual(@as(usize, 3), pos.col);

    try std.testing.expect(try area.widget.handleEvent(right));
    try std.testing.expect(try area.widget.handleEvent(right));
    pos = area.cursorPosition();
    try std.testing.expectEqual(@as(usize, 0), pos.row);
    try std.testing.expectEqual(@as(usize, 5), pos.col);
}

test "text area validation surfaces rule failures" {
    const alloc = std.testing.allocator;
    var area = try TextArea.init(alloc, 32);
    defer area.deinit();
    try area.setText("hi");

    const rules = [_]form.Rule{
        form.required("body required"),
        form.minLength(3, "too short"),
    };

    var res = try area.validate(alloc, "body", &rules);
    defer res.deinit();

    try std.testing.expect(!res.isValid());
    try std.testing.expectEqualStrings("body", res.errors.items[0].field);
    try std.testing.expectEqualStrings("too short", res.errors.items[1].message);
}
