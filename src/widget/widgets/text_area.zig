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
    selection: ?Selection = null,
    extra_cursors: std.ArrayList(usize),
    validation_rules: ?[]const form.Rule = null,
    validation_field_name: []const u8 = "value",
    validation_field_owned: bool = false,
    validate_on_change: bool = false,
    on_validation: ?*const fn (*TextArea, *const form.ValidationResult) void = null,
    last_validation: ?form.ValidationResult = null,
    invalid_fg: render.Color = render.Color{ .named_color = render.NamedColor.white },
    invalid_bg: render.Color = render.Color{ .named_color = render.NamedColor.red },
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
            .extra_cursors = std.ArrayList(usize).empty,
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
        self.clearValidationResult();
        if (self.validation_field_owned and self.validation_field_name.len > 0) {
            self.allocator.free(self.validation_field_name);
        }
        self.extra_cursors.deinit(self.allocator);
        self.undo_redo.deinit();
        if (self.owns_clipboard) {
            self.clipboard_storage.deinit();
        }
        self.buffer.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn setText(self: *TextArea, text: []const u8) !void {
        try self.writeText(text);
        self.finalizeChange(true, self.validate_on_change);
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

    pub fn selectionRange(self: *TextArea) ?Selection {
        return self.normalizedSelection();
    }

    pub fn selectRange(self: *TextArea, start: usize, end: usize) void {
        const clamped_start = @min(start, self.buffer.items.len);
        const clamped_end = @min(end, self.buffer.items.len);
        self.selection = .{ .start = clamped_start, .end = clamped_end };
    }

    pub fn clearSelection(self: *TextArea) void {
        self.selection = null;
    }

    pub fn selectAll(self: *TextArea) void {
        self.selection = .{ .start = 0, .end = self.buffer.items.len };
    }

    pub fn addCursor(self: *TextArea, position: usize) !void {
        const clamped = @min(position, self.buffer.items.len);
        if (clamped == self.cursor) return;
        if (std.mem.indexOfScalar(usize, self.extra_cursors.items, clamped) != null) return;
        try self.extra_cursors.append(self.allocator, clamped);
        std.sort.sort(usize, self.extra_cursors.items, {}, std.sort.asc(usize));
    }

    pub fn clearExtraCursors(self: *TextArea) void {
        self.extra_cursors.clearRetainingCapacity();
    }

    pub fn setCursors(self: *TextArea, positions: []const usize) !void {
        if (positions.len == 0) {
            self.clearExtraCursors();
            return;
        }

        self.cursor = @min(positions[0], self.buffer.items.len);
        self.clearExtraCursors();
        for (positions[1..]) |pos| {
            try self.addCursor(pos);
        }
    }

    pub fn setValidation(self: *TextArea, field_name: []const u8, rules: []const form.Rule, realtime: bool) !void {
        try self.setValidationFieldName(field_name);
        self.validation_rules = rules;
        self.validate_on_change = realtime;
        if (realtime) try self.runValidation();
    }

    pub fn clearValidation(self: *TextArea) void {
        self.validation_rules = null;
        self.validate_on_change = false;
        self.clearValidationResult();
    }

    /// Manually trigger validation using the configured rules.
    pub fn revalidate(self: *TextArea) !void {
        try self.runValidation();
    }

    pub fn setOnValidate(self: *TextArea, callback: *const fn (*TextArea, *const form.ValidationResult) void) void {
        self.on_validation = callback;
    }

    pub fn validationState(self: *TextArea) ?*const form.ValidationResult {
        if (self.last_validation) |*res| return res;
        return null;
    }

    fn clearValidationResult(self: *TextArea) void {
        if (self.last_validation) |*res| res.deinit();
        self.last_validation = null;
    }

    fn setValidationFieldName(self: *TextArea, name: []const u8) !void {
        if (self.validation_field_owned and self.validation_field_name.len > 0) {
            self.allocator.free(self.validation_field_name);
        }

        if (name.len == 0) {
            self.validation_field_name = "value";
            self.validation_field_owned = false;
        } else {
            self.validation_field_name = try self.allocator.dupe(u8, name);
            self.validation_field_owned = true;
        }
    }

    fn runValidation(self: *TextArea) !void {
        if (self.validation_rules) |rules| {
            self.clearValidationResult();
            const result = try form.validateField(self.allocator, self.validation_field_name, self.getText(), rules);
            self.last_validation = result;
            if (self.on_validation) |callback| callback(self, &self.last_validation.?);
        }
    }

    fn finalizeChange(self: *TextArea, capture_history: bool, force_validate: bool) void {
        self.clampCursor();
        self.resetPreferredColumn();
        if (capture_history) self.pushHistory() catch {};
        if ((self.validate_on_change or force_validate) and self.validation_rules != null) {
            self.runValidation() catch {};
        }
        self.notifyChange();
    }

    fn hasValidationError(self: *const TextArea) bool {
        if (self.last_validation) |result| return !result.isValid();
        return false;
    }

    fn normalizedSelection(self: *TextArea) ?Selection {
        if (self.selection) |sel| {
            const start = @min(sel.start, sel.end);
            const end = @max(sel.start, sel.end);
            if (start == end) return null;
            return .{ .start = start, .end = end };
        }
        return null;
    }

    fn remainingCapacity(self: *const TextArea) usize {
        if (self.buffer.items.len >= self.max_bytes) return 0;
        return self.max_bytes - self.buffer.items.len;
    }

    const CursorMark = struct { pos: usize, primary: bool };

    fn cursorLess(_: void, a: CursorMark, b: CursorMark) bool {
        return a.pos < b.pos;
    }

    fn collectCursorMarks(self: *TextArea) !std.ArrayList(CursorMark) {
        var marks = try std.ArrayList(CursorMark).initCapacity(self.allocator, self.extra_cursors.items.len + 1);
        errdefer marks.deinit(self.allocator);

        try marks.append(self.allocator, .{ .pos = @min(self.cursor, self.buffer.items.len), .primary = true });
        for (self.extra_cursors.items) |pos| {
            try marks.append(self.allocator, .{ .pos = @min(pos, self.buffer.items.len), .primary = false });
        }

        std.sort.sort(CursorMark, marks.items, {}, cursorLess);

        var write: usize = 0;
        var idx: usize = 0;
        while (idx < marks.items.len) {
            var merged = marks.items[idx];
            idx += 1;
            while (idx < marks.items.len and marks.items[idx].pos == merged.pos) {
                merged.primary = merged.primary or marks.items[idx].primary;
                idx += 1;
            }
            marks.items[write] = merged;
            write += 1;
        }
        marks.shrinkRetainingCapacity(write);
        return marks;
    }

    fn applyCursorMarks(self: *TextArea, marks: []const CursorMark) !void {
        self.clearExtraCursors();
        for (marks) |mark| {
            if (mark.primary) {
                self.cursor = @min(mark.pos, self.buffer.items.len);
            } else {
                try self.extra_cursors.append(self.allocator, @min(mark.pos, self.buffer.items.len));
            }
        }
    }

    fn replaceSelection(self: *TextArea, replacement: []const u8) !bool {
        const selection_range = self.normalizedSelection() orelse return false;
        const bounded_end = @min(selection_range.end, self.buffer.items.len);
        const bounded_start = @min(selection_range.start, bounded_end);
        const remove_len = bounded_end - bounded_start;

        const max_insert = self.max_bytes - (self.buffer.items.len - remove_len);
        if (max_insert == 0 and replacement.len > 0) return false;
        const insert_len = @min(replacement.len, max_insert);

        if (remove_len > 0) {
            const tail_len = self.buffer.items.len - bounded_end;
            if (tail_len > 0) {
                std.mem.copyForwards(u8, self.buffer.items[bounded_start .. bounded_start + tail_len], self.buffer.items[bounded_end .. bounded_end + tail_len]);
            }
            self.buffer.items.len -= remove_len;
        }

        if (insert_len > 0) {
            try self.buffer.insertSlice(self.allocator, bounded_start, replacement[0..insert_len]);
        }

        self.cursor = bounded_start + insert_len;
        self.clearSelection();
        self.clearExtraCursors();
        return true;
    }

    fn insertSliceMulti(self: *TextArea, slice: []const u8) !bool {
        if (slice.len == 0) return false;
        var marks = try self.collectCursorMarks();
        defer marks.deinit(self.allocator);

        var new_marks = try std.ArrayList(CursorMark).initCapacity(self.allocator, marks.items.len);
        defer new_marks.deinit(self.allocator);

        var shift: usize = 0;
        var inserted_any = false;
        for (marks.items) |mark| {
            const available = if (self.buffer.items.len >= self.max_bytes) 0 else self.max_bytes - self.buffer.items.len;
            if (available == 0) {
                try new_marks.append(self.allocator, .{ .pos = @min(mark.pos + shift, self.buffer.items.len), .primary = mark.primary });
                continue;
            }
            const insert_len = @min(available, slice.len);
            const target = mark.pos + shift;
            try self.buffer.insertSlice(self.allocator, target, slice[0..insert_len]);
            shift += insert_len;
            inserted_any = true;
            try new_marks.append(self.allocator, .{ .pos = target + insert_len, .primary = mark.primary });
        }

        if (!inserted_any) return false;
        try self.applyCursorMarks(new_marks.items);
        self.clearSelection();
        return true;
    }

    fn insertTextAtCursors(self: *TextArea, content: []const u8) !bool {
        if (content.len == 0) return false;

        if (try self.replaceSelection(content)) {
            self.finalizeChange(true, self.validate_on_change);
            return true;
        }

        if (self.extra_cursors.items.len == 0) {
            const remaining = self.remainingCapacity();
            if (remaining == 0) return false;
            const insert_len = @min(remaining, content.len);
            try self.buffer.insertSlice(self.allocator, self.cursor, content[0..insert_len]);
            self.cursor += insert_len;
            self.clearSelection();
            self.finalizeChange(true, self.validate_on_change);
            return true;
        }

        if (try self.insertSliceMulti(content)) {
            self.finalizeChange(true, self.validate_on_change);
            return true;
        }
        return false;
    }

    fn deleteBackwardMulti(self: *TextArea) !bool {
        var marks = try self.collectCursorMarks();
        defer marks.deinit(self.allocator);

        var new_marks = try std.ArrayList(CursorMark).initCapacity(self.allocator, marks.items.len);
        defer new_marks.deinit(self.allocator);

        var removed: usize = 0;
        for (marks.items) |mark| {
            if (mark.pos <= removed or self.buffer.items.len == 0) {
                try new_marks.append(self.allocator, .{ .pos = 0, .primary = mark.primary });
                continue;
            }

            const target = mark.pos - 1 - removed;
            if (target >= self.buffer.items.len) {
                try new_marks.append(self.allocator, .{ .pos = self.buffer.items.len, .primary = mark.primary });
                continue;
            }

            _ = self.buffer.orderedRemove(target);
            removed += 1;
            try new_marks.append(self.allocator, .{ .pos = target, .primary = mark.primary });
        }

        if (removed == 0) return false;
        try self.applyCursorMarks(new_marks.items);
        self.clearSelection();
        self.finalizeChange(true, self.validate_on_change);
        return true;
    }

    fn deleteForwardMulti(self: *TextArea) !bool {
        var marks = try self.collectCursorMarks();
        defer marks.deinit(self.allocator);

        var new_marks = try std.ArrayList(CursorMark).initCapacity(self.allocator, marks.items.len);
        defer new_marks.deinit(self.allocator);

        var removed: usize = 0;
        for (marks.items) |mark| {
            const target = if (mark.pos > removed) mark.pos - removed else 0;
            if (target >= self.buffer.items.len) {
                try new_marks.append(self.allocator, .{ .pos = self.buffer.items.len, .primary = mark.primary });
                continue;
            }

            _ = self.buffer.orderedRemove(target);
            removed += 1;
            try new_marks.append(self.allocator, .{ .pos = target, .primary = mark.primary });
        }

        if (removed == 0) return false;
        try self.applyCursorMarks(new_marks.items);
        self.clearSelection();
        self.finalizeChange(true, self.validate_on_change);
        return true;
    }

    fn writeText(self: *TextArea, text: []const u8) !void {
        self.buffer.clearRetainingCapacity();
        const copy_len = @min(text.len, self.max_bytes);
        try self.buffer.appendSlice(self.allocator, text[0..copy_len]);
        self.cursor = self.buffer.items.len;
        self.preferred_col = self.cursorPosition().col;
        self.scroll_row = 0;
        self.scroll_col = 0;
        self.selection = null;
        self.clearExtraCursors();
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
        self.finalizeChange(false, self.validate_on_change);
    }

    const Selection = struct { start: usize, end: usize };
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
        if (self.normalizedSelection()) |sel| {
            const slice = self.buffer.items[sel.start..sel.end];
            try self.clipboard.copy(slice);
            return slice.len > 0;
        }

        try self.clipboard.copy(self.buffer.items);
        return self.buffer.items.len > 0;
    }

    fn performCut(self: *TextArea) anyerror!bool {
        if (self.normalizedSelection()) |sel| {
            const slice = self.buffer.items[sel.start..sel.end];
            if (slice.len == 0) return false;
            try self.clipboard.copy(slice);
            _ = try self.replaceSelection(&[_]u8{});
            self.finalizeChange(true, self.validate_on_change);
            return true;
        }

        if (self.buffer.items.len == 0) return false;

        try self.clipboard.copy(self.buffer.items);
        self.buffer.clearRetainingCapacity();
        self.cursor = 0;
        self.resetPreferredColumn();
        self.scroll_row = 0;
        self.scroll_col = 0;
        self.clearSelection();
        self.clearExtraCursors();
        self.finalizeChange(true, self.validate_on_change);
        return true;
    }

    fn performPaste(self: *TextArea) anyerror!bool {
        const pasted = self.clipboard.paste() orelse return false;
        if (pasted.len == 0) return false;

        return try self.insertTextAtCursors(pasted);
    }

    fn insertByte(self: *TextArea, value: u8) !void {
        _ = try self.insertTextAtCursors(&[_]u8{value});
    }

    fn deleteBackward(self: *TextArea) !bool {
        if (try self.replaceSelection(&[_]u8{})) {
            self.finalizeChange(true, self.validate_on_change);
            return true;
        }

        if (self.buffer.items.len == 0) return false;
        if (self.extra_cursors.items.len == 0) {
            if (self.cursor == 0) return false;
            _ = self.buffer.orderedRemove(self.cursor - 1);
            self.cursor -= 1;
            self.resetPreferredColumn();
            self.finalizeChange(true, self.validate_on_change);
            return true;
        }

        return try self.deleteBackwardMulti();
    }

    fn deleteForward(self: *TextArea) !bool {
        if (try self.replaceSelection(&[_]u8{})) {
            self.finalizeChange(true, self.validate_on_change);
            return true;
        }

        if (self.extra_cursors.items.len == 0) {
            if (self.cursor >= self.buffer.items.len) return false;
            _ = self.buffer.orderedRemove(self.cursor);
            self.resetPreferredColumn();
            self.finalizeChange(true, self.validate_on_change);
            return true;
        }

        return try self.deleteForwardMulti();
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*TextArea, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;

        const rect = self.widget.rect;

        const invalid = self.widget.enabled and self.hasValidationError();
        const fg = if (!self.widget.enabled)
            self.disabled_fg
        else if (invalid)
            self.invalid_fg
        else if (self.widget.focused)
            self.focused_fg
        else
            self.fg;

        const bg = if (!self.widget.enabled)
            self.disabled_bg
        else if (invalid)
            self.invalid_bg
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

        const selection_range = self.normalizedSelection();

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
                    if (self.scroll_col < line.len) {
                        const slice_start = self.scroll_col;
                        const end = @min(line.len, self.scroll_col + @as(usize, @intCast(viewport.width)));
                        var col: usize = slice_start;
                        while (col < end) : (col += 1) {
                            const ch = line[col];
                            const global_idx = range.start + col;
                            var style = self.style;
                            if (selection_range) |sel| {
                                if (global_idx >= sel.start and global_idx < sel.end) {
                                    style.reverse = true;
                                    style.bold = true;
                                }
                            }
                            const draw_x = inner_x + @as(u16, @intCast(col - slice_start));
                            renderer.drawChar(draw_x, inner_y + row, ch, fg, bg, style);
                        }
                    }
                } else {
                    break;
                }
            }
        }

        if (self.widget.focused) {
            var marks = try self.collectCursorMarks();
            defer marks.deinit(self.allocator);
            for (marks.items) |mark| {
                const pos = self.positionForIndex(mark.pos);
                if (pos.row >= self.scroll_row and pos.row < self.scroll_row + @as(usize, @intCast(viewport.height))) {
                    if (pos.col >= self.scroll_col and pos.col <= self.scroll_col + @as(usize, @intCast(viewport.width))) {
                        const cx = inner_x + @as(u16, @intCast(pos.col - self.scroll_col));
                        const cy = inner_y + @as(u16, @intCast(pos.row - self.scroll_row));
                        var cursor_style = render.Style{ .underline = true };
                        if (!mark.primary) cursor_style.italic = true;
                        renderer.drawChar(cx, cy, '_', fg, bg, cursor_style);
                    }
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
    const area = try TextArea.init(alloc, 128);
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
    const area = try TextArea.init(alloc, 64);
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
    const area = try TextArea.init(alloc, 32);
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

test "text area multi-cursor inserts at every caret" {
    const alloc = std.testing.allocator;
    const area = try TextArea.init(alloc, 64);
    defer area.deinit();

    try area.setText("abc");
    area.cursor = 3;
    try area.addCursor(1);

    try std.testing.expect(try area.insertTextAtCursors("q"));
    try std.testing.expectEqualStrings("aqbcq", area.getText());
    try std.testing.expectEqual(@as(usize, 5), area.cursor);
    try std.testing.expectEqual(@as(usize, 1), area.extra_cursors.items.len);
}

test "text area selection edits collapse and clear extra cursors" {
    const alloc = std.testing.allocator;
    const area = try TextArea.init(alloc, 64);
    defer area.deinit();

    try area.setText("hello");
    area.cursor = 5;
    try area.addCursor(0);
    area.selectRange(1, 4);

    try std.testing.expect(try area.deleteBackward());
    try std.testing.expectEqualStrings("ho", area.getText());
    try std.testing.expectEqual(@as(usize, 1), area.cursor);
    try std.testing.expectEqual(@as(usize, 0), area.extra_cursors.items.len);
}

test "text area real-time validation caches latest result" {
    const alloc = std.testing.allocator;
    const area = try TextArea.init(alloc, 64);
    defer area.deinit();

    const rules = [_]form.Rule{
        form.required("body required"),
        form.minLength(5, "too short"),
    };

    try area.setValidation("body", &rules, true);
    try area.setText("tiny");

    const first = area.validationState().?;
    try std.testing.expect(!first.*.isValid());

    try area.setText("long enough");
    const second = area.validationState().?;
    try std.testing.expect(second.*.isValid());
}
