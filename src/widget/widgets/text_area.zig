const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const text_metrics = @import("../../render/text_metrics.zig");
const input = @import("../../input/input.zig");
const form = @import("../form.zig");
const theme = @import("../theme.zig");
const accessibility = @import("../accessibility.zig");

fn addOffsetClamped(origin: u16, offset: u16) u16 {
    const value = @as(u32, origin) + @as(u32, offset);
    return @intCast(@min(value, @as(u32, std.math.maxInt(u16))));
}

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
    bracketed_paste_active: bool = false,
    allocator: std.mem.Allocator,

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
        .on_state_change = stateChangeFn,
    };

    pub fn init(allocator: std.mem.Allocator, max_bytes: usize) !*TextArea {
        const capacity = @max(max_bytes, 1);
        const self = try allocator.create(TextArea);
        errdefer allocator.destroy(self);

        var buffer = try std.ArrayList(u8).initCapacity(allocator, capacity);
        errdefer buffer.deinit(allocator);

        var undo_redo = input.UndoRedoStack.init(allocator);
        errdefer undo_redo.deinit();
        try undo_redo.capture(buffer.items);

        self.* = TextArea{
            .widget = base.Widget.init(&vtable),
            .buffer = buffer,
            .max_bytes = capacity,
            .undo_redo = undo_redo,
            .clipboard_storage = input.Clipboard.init(allocator),
            .clipboard = undefined,
            .allocator = allocator,
            .extra_cursors = std.ArrayList(usize).empty,
        };

        self.clipboard = &self.clipboard_storage;
        self.setTheme(theme.Theme.dark());
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.input), self.accessibilityLabel(), "");
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
        const copy_len = utf8PrefixLen(text, self.max_bytes);
        const next_text = text[0..copy_len];
        const changed = !std.mem.eql(u8, self.buffer.items, next_text) or self.cursor != copy_len or self.scroll_row != 0 or self.scroll_col != 0 or self.normalizedSelection() != null or self.extra_cursors.items.len > 0;
        try self.buffer.ensureTotalCapacity(self.allocator, copy_len);

        var next_validation: ?form.ValidationResult = null;
        errdefer if (next_validation) |*res| res.deinit();
        if (self.validate_on_change) {
            if (self.validation_rules) |rules| {
                next_validation = try form.validateField(self.allocator, self.validation_field_name, next_text, rules);
            }
        }

        try self.undo_redo.capture(next_text);

        self.writeText(next_text);
        if (next_validation) |result| {
            self.commitValidationResult(result);
            next_validation = null;
        }
        if (changed) self.widget.markDirty();
        self.notifyChange();
    }

    pub fn getText(self: *TextArea) []const u8 {
        return self.buffer.items;
    }

    pub fn setPlaceholder(self: *TextArea, placeholder: []const u8) !void {
        if (std.mem.eql(u8, self.placeholder, placeholder)) return;

        if (placeholder.len == 0) {
            if (self.placeholder_owned and self.placeholder.len > 0) {
                self.allocator.free(self.placeholder);
            }
            self.placeholder = "";
            self.placeholder_owned = false;
            self.widget.setAccessibility(@intFromEnum(accessibility.Role.input), self.accessibilityLabel(), "");
            self.widget.markDirty();
            return;
        }

        const next = try self.allocator.dupe(u8, placeholder);
        if (self.placeholder_owned and self.placeholder.len > 0) {
            self.allocator.free(self.placeholder);
        }
        self.placeholder = next;
        self.placeholder_owned = true;
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.input), self.accessibilityLabel(), "");
        self.widget.markDirty();
    }

    fn accessibilityLabel(self: *TextArea) []const u8 {
        return if (self.placeholder.len > 0) self.placeholder else "Text area";
    }

    pub fn setColors(self: *TextArea, fg: render.Color, bg: render.Color, focused_fg: render.Color, focused_bg: render.Color) void {
        if (std.meta.eql(self.fg, fg) and
            std.meta.eql(self.bg, bg) and
            std.meta.eql(self.focused_fg, focused_fg) and
            std.meta.eql(self.focused_bg, focused_bg)) return;

        self.fg = fg;
        self.bg = bg;
        self.focused_fg = focused_fg;
        self.focused_bg = focused_bg;
        self.widget.markDirty();
    }

    /// Apply theme defaults for text area colors and focus ring.
    pub fn setTheme(self: *TextArea, theme_value: theme.Theme) void {
        const colors = theme.inputColors(theme_value);
        const focus_ring = render.FocusRingStyle{
            .color = colors.focused_bg,
            .border = .rounded,
            .style = render.Style{ .bold = true },
        };
        const changed = !std.meta.eql(self.fg, colors.fg) or
            !std.meta.eql(self.bg, colors.bg) or
            !std.meta.eql(self.focused_fg, colors.focused_fg) or
            !std.meta.eql(self.focused_bg, colors.focused_bg) or
            !std.meta.eql(self.disabled_fg, colors.disabled_fg) or
            !std.meta.eql(self.disabled_bg, colors.disabled_bg) or
            !std.meta.eql(self.invalid_fg, colors.invalid_fg) or
            !std.meta.eql(self.invalid_bg, colors.invalid_bg) or
            !std.meta.eql(self.style, colors.style) or
            self.widget.focus_ring == null or
            !std.meta.eql(self.widget.focus_ring.?, focus_ring);

        if (!changed) return;

        self.fg = colors.fg;
        self.bg = colors.bg;
        self.focused_fg = colors.focused_fg;
        self.focused_bg = colors.focused_bg;
        self.disabled_fg = colors.disabled_fg;
        self.disabled_bg = colors.disabled_bg;
        self.invalid_fg = colors.invalid_fg;
        self.invalid_bg = colors.invalid_bg;
        self.style = colors.style;
        self.widget.setFocusRing(focus_ring);
    }

    pub fn setBorder(self: *TextArea, border: render.BorderStyle) void {
        if (self.border == border) return;
        self.border = border;
        self.show_border = border != .none;
        self.widget.markDirty();
    }

    fn contentRect(self: *const TextArea) layout_module.Rect {
        const border_adjust: u16 = if (self.show_border) 1 else 0;
        return self.widget.rect.shrink(layout_module.EdgeInsets.all(border_adjust));
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

    /// Cancel any in-flight bracketed paste sequence tracked by this editor.
    pub fn cancelBracketedPaste(self: *TextArea) void {
        self.bracketed_paste_active = false;
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
        const clamped_start = if (start <= end)
            graphemeBoundaryAtOrBefore(self.buffer.items, start)
        else
            graphemeBoundaryAtOrAfter(self.buffer.items, start);
        const clamped_end = if (start <= end)
            graphemeBoundaryAtOrAfter(self.buffer.items, end)
        else
            graphemeBoundaryAtOrBefore(self.buffer.items, end);
        if (self.selection) |sel| {
            if (sel.start == clamped_start and sel.end == clamped_end) return;
        }
        self.selection = .{ .start = clamped_start, .end = clamped_end };
        self.widget.markDirty();
    }

    pub fn clearSelection(self: *TextArea) void {
        if (self.normalizedSelection() == null) {
            self.selection = null;
            return;
        }
        self.selection = null;
        self.widget.markDirty();
    }

    pub fn selectAll(self: *TextArea) void {
        if (self.buffer.items.len == 0) return;
        if (self.selection) |sel| {
            if (sel.start == 0 and sel.end == self.buffer.items.len) return;
        }
        self.selection = .{ .start = 0, .end = self.buffer.items.len };
        self.widget.markDirty();
    }

    pub fn addCursor(self: *TextArea, position: usize) !void {
        const clamped = graphemeBoundaryAtOrBefore(self.buffer.items, position);
        if (clamped == self.cursor) return;
        if (std.mem.indexOfScalar(usize, self.extra_cursors.items, clamped) != null) return;
        try self.extra_cursors.append(self.allocator, clamped);
        std.sort.pdq(usize, self.extra_cursors.items, {}, std.sort.asc(usize));
        self.widget.markDirty();
    }

    pub fn clearExtraCursors(self: *TextArea) void {
        if (self.extra_cursors.items.len == 0) return;
        self.extra_cursors.clearRetainingCapacity();
        self.widget.markDirty();
    }

    pub fn setCursors(self: *TextArea, positions: []const usize) !void {
        if (positions.len == 0) {
            self.clearExtraCursors();
            return;
        }

        const next_primary = graphemeBoundaryAtOrBefore(self.buffer.items, positions[0]);
        var next_extra = std.ArrayList(usize).empty;
        errdefer next_extra.deinit(self.allocator);

        for (positions[1..]) |pos| {
            const clamped = graphemeBoundaryAtOrBefore(self.buffer.items, pos);
            if (clamped == next_primary) continue;
            if (std.mem.indexOfScalar(usize, next_extra.items, clamped) != null) continue;
            try next_extra.append(self.allocator, clamped);
        }
        std.sort.pdq(usize, next_extra.items, {}, std.sort.asc(usize));

        const changed = self.cursor != next_primary or !std.mem.eql(usize, self.extra_cursors.items, next_extra.items);
        if (!changed) {
            next_extra.deinit(self.allocator);
            return;
        }

        self.extra_cursors.deinit(self.allocator);
        self.extra_cursors = next_extra;
        self.cursor = next_primary;
        self.widget.markDirty();
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
        const was_invalid = self.hasValidationError();
        if (self.last_validation) |*res| res.deinit();
        self.last_validation = null;
        if (was_invalid) self.widget.markDirty();
    }

    fn setValidationFieldName(self: *TextArea, name: []const u8) !void {
        if (name.len == 0) {
            if (self.validation_field_owned and self.validation_field_name.len > 0) {
                self.allocator.free(self.validation_field_name);
            }
            self.validation_field_name = "value";
            self.validation_field_owned = false;
        } else {
            const next_name = try self.allocator.dupe(u8, name);
            if (self.validation_field_owned and self.validation_field_name.len > 0) {
                self.allocator.free(self.validation_field_name);
            }
            self.validation_field_name = next_name;
            self.validation_field_owned = true;
        }
    }

    fn runValidation(self: *TextArea) !void {
        if (self.validation_rules) |rules| {
            const result = try form.validateField(self.allocator, self.validation_field_name, self.getText(), rules);
            self.commitValidationResult(result);
        }
    }

    fn commitValidationResult(self: *TextArea, result: form.ValidationResult) void {
        const was_invalid = self.hasValidationError();
        var previous = self.last_validation;
        self.last_validation = result;
        if (previous) |*res| res.deinit();
        if (was_invalid != self.hasValidationError()) self.widget.markDirty();
        if (self.on_validation) |callback| callback(self, &self.last_validation.?);
    }

    fn finalizeChange(self: *TextArea, capture_history: bool, force_validate: bool) !void {
        self.clampCursor();
        self.resetPreferredColumn();
        if (capture_history) try self.pushHistory();
        if ((self.validate_on_change or force_validate) and self.validation_rules != null) {
            try self.runValidation();
        }
        self.widget.markDirty();
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

    fn utf8PrefixLen(value: []const u8, max_bytes: usize) usize {
        const limit = @min(value.len, max_bytes);
        var idx: usize = 0;
        var last_valid: usize = 0;
        while (idx < limit) {
            const first = value[idx];
            const width: usize = if (first < 0x80)
                1
            else if ((first & 0b1110_0000) == 0b1100_0000)
                2
            else if ((first & 0b1111_0000) == 0b1110_0000)
                3
            else if ((first & 0b1111_1000) == 0b1111_0000)
                4
            else
                break;

            if (idx + width > limit) break;
            if (std.unicode.utf8Decode(value[idx .. idx + width])) |_| {
                idx += width;
                last_valid = idx;
            } else |_| {
                break;
            }
        }
        return last_valid;
    }

    const LineBounds = struct { start: usize, end: usize };

    fn lineBoundsForIndex(bytes: []const u8, pos: usize) LineBounds {
        const bounded = @min(pos, bytes.len);
        var start = bounded;
        while (start > 0 and bytes[start - 1] != '\n') : (start -= 1) {}

        var end = bounded;
        while (end < bytes.len and bytes[end] != '\n') : (end += 1) {}
        return .{ .start = start, .end = end };
    }

    fn graphemeBoundaryAtOrBefore(bytes: []const u8, pos: usize) usize {
        const bounded = @min(pos, bytes.len);
        const bounds = lineBoundsForIndex(bytes, bounded);
        const line = bytes[bounds.start..bounds.end];
        return bounds.start + text_metrics.graphemeBoundaryAtOrBefore(line, bounded - bounds.start);
    }

    fn graphemeBoundaryAtOrAfter(bytes: []const u8, pos: usize) usize {
        const bounded = @min(pos, bytes.len);
        const before = graphemeBoundaryAtOrBefore(bytes, bounded);
        if (before == bounded) return bounded;
        return nextGraphemeBoundary(bytes, before);
    }

    fn previousGraphemeBoundary(bytes: []const u8, pos: usize) usize {
        const bounded = graphemeBoundaryAtOrBefore(bytes, pos);
        if (bounded == 0) return 0;

        const bounds = lineBoundsForIndex(bytes, bounded);
        if (bounded == bounds.start) return bounded - 1;
        const line = bytes[bounds.start..bounds.end];
        return bounds.start + text_metrics.previousGraphemeBoundary(line, bounded - bounds.start);
    }

    fn nextGraphemeBoundary(bytes: []const u8, pos: usize) usize {
        const bounded = graphemeBoundaryAtOrBefore(bytes, pos);
        if (bounded >= bytes.len) return bytes.len;

        const bounds = lineBoundsForIndex(bytes, bounded);
        if (bounded == bounds.end) return bounded + 1;
        const line = bytes[bounds.start..bounds.end];
        return bounds.start + text_metrics.nextGraphemeBoundary(line, bounded - bounds.start);
    }

    fn removeRange(self: *TextArea, start: usize, end: usize) void {
        if (start >= end or start >= self.buffer.items.len) return;
        const bounded_end = @min(end, self.buffer.items.len);
        const tail_len = self.buffer.items.len - bounded_end;
        if (tail_len > 0) {
            std.mem.copyForwards(u8, self.buffer.items[start .. start + tail_len], self.buffer.items[bounded_end .. bounded_end + tail_len]);
        }
        self.buffer.items.len -= bounded_end - start;
    }

    const CursorMark = struct { pos: usize, primary: bool };

    const CursorMarkIterator = struct {
        extras: []const usize,
        primary_pos: usize,
        max_pos: usize,
        extra_index: usize = 0,
        primary_emitted: bool = false,

        fn init(extras: []const usize, primary_pos: usize, max_pos: usize) CursorMarkIterator {
            return .{
                .extras = extras,
                .primary_pos = @min(primary_pos, max_pos),
                .max_pos = max_pos,
            };
        }

        fn next(self: *CursorMarkIterator) ?CursorMark {
            if (self.primary_emitted and self.extra_index >= self.extras.len) return null;

            const extra_pos = if (self.extra_index < self.extras.len)
                @min(self.extras[self.extra_index], self.max_pos)
            else
                null;
            const pos = if (self.primary_emitted)
                extra_pos.?
            else if (extra_pos) |extra|
                @min(self.primary_pos, extra)
            else
                self.primary_pos;

            const primary = !self.primary_emitted and self.primary_pos == pos;
            if (primary) self.primary_emitted = true;
            while (self.extra_index < self.extras.len and @min(self.extras[self.extra_index], self.max_pos) == pos) {
                self.extra_index += 1;
            }
            return .{ .pos = pos, .primary = primary };
        }
    };

    fn cursorMarks(self: *const TextArea) CursorMarkIterator {
        return CursorMarkIterator.init(self.extra_cursors.items, self.cursor, self.buffer.items.len);
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
        const insert_len = utf8PrefixLen(replacement, max_insert);

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
        var marks = self.cursorMarks();

        var new_marks = try std.ArrayList(CursorMark).initCapacity(self.allocator, self.extra_cursors.items.len + 1);
        defer new_marks.deinit(self.allocator);

        var shift: usize = 0;
        var inserted_any = false;
        while (marks.next()) |mark| {
            const available = if (self.buffer.items.len >= self.max_bytes) 0 else self.max_bytes - self.buffer.items.len;
            if (available == 0) {
                try new_marks.append(self.allocator, .{ .pos = @min(mark.pos + shift, self.buffer.items.len), .primary = mark.primary });
                continue;
            }
            const insert_len = utf8PrefixLen(slice, available);
            if (insert_len == 0) {
                try new_marks.append(self.allocator, .{ .pos = @min(mark.pos + shift, self.buffer.items.len), .primary = mark.primary });
                continue;
            }
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
            try self.finalizeChange(true, self.validate_on_change);
            return true;
        }

        if (self.extra_cursors.items.len == 0) {
            const remaining = self.remainingCapacity();
            if (remaining == 0) return false;
            const insert_len = utf8PrefixLen(content, remaining);
            if (insert_len == 0) return false;
            try self.buffer.insertSlice(self.allocator, self.cursor, content[0..insert_len]);
            self.cursor += insert_len;
            self.clearSelection();
            try self.finalizeChange(true, self.validate_on_change);
            return true;
        }

        if (try self.insertSliceMulti(content)) {
            try self.finalizeChange(true, self.validate_on_change);
            return true;
        }
        return false;
    }

    fn deleteBackwardMulti(self: *TextArea) !bool {
        var marks = self.cursorMarks();

        var new_marks = try std.ArrayList(CursorMark).initCapacity(self.allocator, self.extra_cursors.items.len + 1);
        defer new_marks.deinit(self.allocator);

        var removed: usize = 0;
        while (marks.next()) |mark| {
            if (mark.pos <= removed or self.buffer.items.len == 0) {
                try new_marks.append(self.allocator, .{ .pos = 0, .primary = mark.primary });
                continue;
            }

            const cursor_pos = mark.pos - removed;
            if (cursor_pos > self.buffer.items.len) {
                try new_marks.append(self.allocator, .{ .pos = self.buffer.items.len, .primary = mark.primary });
                continue;
            }

            const target = previousGraphemeBoundary(self.buffer.items, cursor_pos);
            self.removeRange(target, cursor_pos);
            removed += cursor_pos - target;
            try new_marks.append(self.allocator, .{ .pos = target, .primary = mark.primary });
        }

        if (removed == 0) return false;
        try self.applyCursorMarks(new_marks.items);
        self.clearSelection();
        try self.finalizeChange(true, self.validate_on_change);
        return true;
    }

    fn deleteForwardMulti(self: *TextArea) !bool {
        var marks = self.cursorMarks();

        var new_marks = try std.ArrayList(CursorMark).initCapacity(self.allocator, self.extra_cursors.items.len + 1);
        defer new_marks.deinit(self.allocator);

        var removed: usize = 0;
        while (marks.next()) |mark| {
            const target = if (mark.pos > removed) mark.pos - removed else 0;
            if (target >= self.buffer.items.len) {
                try new_marks.append(self.allocator, .{ .pos = self.buffer.items.len, .primary = mark.primary });
                continue;
            }

            const remove_end = nextGraphemeBoundary(self.buffer.items, target);
            self.removeRange(target, remove_end);
            removed += remove_end - target;
            try new_marks.append(self.allocator, .{ .pos = target, .primary = mark.primary });
        }

        if (removed == 0) return false;
        try self.applyCursorMarks(new_marks.items);
        self.clearSelection();
        try self.finalizeChange(true, self.validate_on_change);
        return true;
    }

    fn writeText(self: *TextArea, text: []const u8) void {
        self.buffer.clearRetainingCapacity();
        const copy_len = utf8PrefixLen(text, self.max_bytes);
        self.buffer.appendSliceAssumeCapacity(text[0..copy_len]);
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
        self.cursor = graphemeBoundaryAtOrBefore(self.buffer.items, self.cursor);
    }

    fn resetPreferredColumn(self: *TextArea) void {
        self.preferred_col = self.cursorPosition().col;
    }

    fn applySnapshot(self: *TextArea, snapshot: []const u8) !void {
        self.writeText(snapshot);
        try self.finalizeChange(false, self.validate_on_change);
    }

    const Selection = struct { start: usize, end: usize };
    const Position = struct { row: usize, col: usize };

    fn positionForIndex(self: *const TextArea, idx: usize) Position {
        const bounded = graphemeBoundaryAtOrBefore(self.buffer.items, idx);
        const bounds = lineBoundsForIndex(self.buffer.items, bounded);
        var row: usize = 0;
        var i: usize = 0;
        while (i < bounds.start) : (i += 1) {
            if (self.buffer.items[i] == '\n') row += 1;
        }
        const line = self.buffer.items[bounds.start..bounds.end];
        const col = text_metrics.cellWidthThroughByte(line, bounded - bounds.start);
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
                const candidate = pos.col - @as(usize, @intCast(inner_width - 1));
                const range = self.lineRange(pos.row).?;
                self.scroll_col = text_metrics.cellColumnAtOrAfter(self.buffer.items[range.start..range.end], candidate);
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
                    self.cursor = previousGraphemeBoundary(self.buffer.items, self.cursor);
                    self.resetPreferredColumn();
                    self.ensureVisible(viewport.width, viewport.height);
                    return true;
                }
                return false;
            },
            .cursor_right => {
                if (self.cursor < self.buffer.items.len) {
                    self.cursor = nextGraphemeBoundary(self.buffer.items, self.cursor);
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
            const line = self.buffer.items[range.start..range.end];
            self.cursor = range.start + text_metrics.byteOffsetForCellColumn(line, desired_col);
        } else {
            self.cursor = self.buffer.items.len;
        }
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
            try self.finalizeChange(true, self.validate_on_change);
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
        try self.finalizeChange(true, self.validate_on_change);
        return true;
    }

    fn performPaste(self: *TextArea) anyerror!bool {
        const pasted = self.clipboard.paste() orelse return false;
        if (pasted.len == 0) return false;

        return try self.insertTextAtCursors(pasted);
    }

    fn insertSlice(self: *TextArea, value: []const u8) !bool {
        return try self.insertTextAtCursors(value);
    }

    fn deleteBackward(self: *TextArea) !bool {
        if (try self.replaceSelection(&[_]u8{})) {
            try self.finalizeChange(true, self.validate_on_change);
            return true;
        }

        if (self.buffer.items.len == 0) return false;
        if (self.extra_cursors.items.len == 0) {
            if (self.cursor == 0) return false;
            const remove_start = previousGraphemeBoundary(self.buffer.items, self.cursor);
            self.removeRange(remove_start, self.cursor);
            self.cursor = remove_start;
            self.resetPreferredColumn();
            try self.finalizeChange(true, self.validate_on_change);
            return true;
        }

        return try self.deleteBackwardMulti();
    }

    fn deleteForward(self: *TextArea) !bool {
        if (try self.replaceSelection(&[_]u8{})) {
            try self.finalizeChange(true, self.validate_on_change);
            return true;
        }

        if (self.extra_cursors.items.len == 0) {
            if (self.cursor >= self.buffer.items.len) return false;
            const remove_end = nextGraphemeBoundary(self.buffer.items, self.cursor);
            self.removeRange(self.cursor, remove_end);
            self.resetPreferredColumn();
            try self.finalizeChange(true, self.validate_on_change);
            return true;
        }

        return try self.deleteForwardMulti();
    }

    fn drawLine(
        renderer: *render.Renderer,
        x: u16,
        y: u16,
        line: []const u8,
        global_start: usize,
        scroll_col: usize,
        width: u16,
        selection_range: ?Selection,
        fg: render.Color,
        bg: render.Color,
        style: render.Style,
    ) void {
        const right = scroll_col + @as(usize, @intCast(width));
        var cells: usize = 0;
        var byte_start: usize = 0;
        var it = text_metrics.GraphemeIterator.init(line);
        while (it.next()) |grapheme| {
            const byte_end = it.it.i;
            const next_cells = cells + grapheme.width;
            defer {
                cells = next_cells;
                byte_start = byte_end;
            }

            if (next_cells <= scroll_col) continue;
            if (cells < scroll_col) continue;
            if (cells >= right or next_cells > right) break;

            var cell_style = style;
            if (selection_range) |selection| {
                const cluster_start = global_start + byte_start;
                const cluster_end = global_start + byte_end;
                if (cluster_start < selection.end and cluster_end > selection.start) {
                    cell_style.reverse = true;
                    cell_style.bold = true;
                }
            }

            const draw_x = addOffsetClamped(x, @intCast(cells - scroll_col));
            renderer.drawStr(draw_x, y, line[byte_start..byte_end], fg, bg, cell_style);
        }
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *TextArea = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible) return;

        const rect = self.widget.rect;

        const invalid = self.widget.enabled and self.hasValidationError();
        const base_fg = if (!self.widget.enabled)
            self.disabled_fg
        else if (invalid)
            self.invalid_fg
        else if (self.widget.focused)
            self.focused_fg
        else
            self.fg;

        const base_bg = if (!self.widget.enabled)
            self.disabled_bg
        else if (invalid)
            self.invalid_bg
        else if (self.widget.focused)
            self.focused_bg
        else
            self.bg;

        const styled = self.widget.applyStyle(
            "text_area",
            .{ .focus = self.widget.focused, .disabled = !self.widget.enabled },
            self.style,
            base_fg,
            base_bg,
        );
        const fg = styled.fg;
        const bg = styled.bg;
        const style = styled.style;

        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', fg, bg, style);
        if (self.show_border) {
            renderer.drawBox(rect.x, rect.y, rect.width, rect.height, self.border, fg, bg, style);
        }

        const border_adjust: u16 = if (self.show_border) 1 else 0;
        const inner_x = addOffsetClamped(rect.x, border_adjust);
        const inner_y = addOffsetClamped(rect.y, border_adjust);
        const viewport = self.viewportSize();
        if (viewport.width == 0 or viewport.height == 0) {
            self.widget.drawFocusRing(renderer);
            return;
        }

        const selection_range = self.normalizedSelection();

        if (self.buffer.items.len == 0 and self.placeholder.len > 0) {
            drawLine(renderer, inner_x, inner_y, self.placeholder, 0, 0, viewport.width, null, fg, bg, style);
        } else {
            var row: u16 = 0;
            while (row < viewport.height) : (row += 1) {
                const line_idx = self.scroll_row + @as(usize, @intCast(row));
                if (self.lineRange(line_idx)) |range| {
                    if (range.start == range.end and range.start >= self.buffer.items.len) break;
                    const line = self.buffer.items[range.start..range.end];
                    drawLine(renderer, inner_x, addOffsetClamped(inner_y, row), line, range.start, self.scroll_col, viewport.width, selection_range, fg, bg, style);
                } else {
                    break;
                }
            }
        }

        if (self.widget.focused) {
            var marks = self.cursorMarks();
            while (marks.next()) |mark| {
                const pos = self.positionForIndex(mark.pos);
                if (pos.row >= self.scroll_row and pos.row < self.scroll_row + @as(usize, @intCast(viewport.height))) {
                    if (pos.col >= self.scroll_col and pos.col < self.scroll_col + @as(usize, @intCast(viewport.width))) {
                        const cx = addOffsetClamped(inner_x, @intCast(pos.col - self.scroll_col));
                        const cy = addOffsetClamped(inner_y, @intCast(pos.row - self.scroll_row));
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
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *TextArea = @fieldParentPtr("widget", widget_ref);

        if (!self.widget.visible or !self.widget.enabled) return false;

        switch (event) {
            .key => |key_event| {
                if (!self.widget.focused) return false;
                if (key_event.key == input.KeyCode.BRACKETED_PASTE_START) {
                    self.bracketed_paste_active = true;
                    return true;
                }
                if (key_event.key == input.KeyCode.BRACKETED_PASTE_END) {
                    self.bracketed_paste_active = false;
                    return true;
                }
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
                        _ = try self.insertSlice("\n");
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
                        if (key_event.isTextInput() and !key_event.modifiers.ctrl and !key_event.modifiers.alt) {
                            var utf8_buf: [4]u8 = undefined;
                            const bytes = key_event.utf8(&utf8_buf) orelse return false;
                            if (!try self.insertSlice(bytes)) return false;
                            self.ensureVisible(self.viewportSize().width, self.viewportSize().height);
                            return true;
                        }
                    },
                }
            },
            .mouse => |mouse_event| {
                if (mouse_event.action == .press and mouse_event.button == 1) {
                    return self.contentRect().contains(mouse_event.x, mouse_event.y);
                }
            },
            else => {},
        }

        return false;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *TextArea = @fieldParentPtr("widget", widget_ref);
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *TextArea = @fieldParentPtr("widget", widget_ref);
        const border_adjust: u16 = if (self.show_border) 2 else 0;
        return layout_module.Size.init(
            40 + border_adjust,
            5 + border_adjust,
        );
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *TextArea = @fieldParentPtr("widget", widget_ref);
        return self.widget.enabled;
    }

    fn stateChangeFn(widget_ptr: *anyopaque) void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *TextArea = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.focused or !self.widget.visible or !self.widget.enabled) {
            self.cancelBracketedPaste();
        }
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

test "text area cursor geometry uses grapheme cell widths" {
    const alloc = std.testing.allocator;
    const area = try TextArea.init(alloc, 64);
    defer area.deinit();
    try area.setText("A界e\u{0301}B");

    try std.testing.expectEqual(TextArea.Position{ .row = 0, .col = 1 }, area.positionForIndex(1));
    try std.testing.expectEqual(TextArea.Position{ .row = 0, .col = 3 }, area.positionForIndex(4));
    try std.testing.expectEqual(TextArea.Position{ .row = 0, .col = 3 }, area.positionForIndex(5));
    try std.testing.expectEqual(TextArea.Position{ .row = 0, .col = 4 }, area.positionForIndex(7));
    try std.testing.expectEqual(TextArea.Position{ .row = 0, .col = 5 }, area.cursorPosition());
}

test "text area vertical movement preserves preferred display column" {
    const alloc = std.testing.allocator;
    const area = try TextArea.init(alloc, 64);
    defer area.deinit();
    area.widget.focused = true;
    area.setBorder(.none);
    try area.widget.layout(layout_module.Rect.init(0, 0, 6, 3));
    try area.setText("a界z\nab\n12345");
    area.cursor = 4;
    area.resetPreferredColumn();

    const down = input.Event{ .key = input.KeyEvent.init(input.KeyCode.DOWN, input.KeyModifiers{}) };
    const up = input.Event{ .key = input.KeyEvent.init(input.KeyCode.UP, input.KeyModifiers{}) };

    try std.testing.expect(try area.widget.handleEvent(down));
    try std.testing.expectEqual(TextArea.Position{ .row = 1, .col = 2 }, area.cursorPosition());
    try std.testing.expect(try area.widget.handleEvent(down));
    try std.testing.expectEqual(TextArea.Position{ .row = 2, .col = 3 }, area.cursorPosition());
    try std.testing.expect(try area.widget.handleEvent(up));
    try std.testing.expectEqual(TextArea.Position{ .row = 1, .col = 2 }, area.cursorPosition());
    try std.testing.expect(try area.widget.handleEvent(up));
    try std.testing.expectEqual(@as(usize, 4), area.cursor);
}

test "text area renders graphemes without splitting terminal cells" {
    const alloc = std.testing.allocator;
    const area = try TextArea.init(alloc, 64);
    defer area.deinit();
    area.setBorder(.none);
    try area.widget.layout(layout_module.Rect.init(0, 0, 6, 1));
    try area.setText("A界e\u{0301}B");

    var renderer = try render.Renderer.init(alloc, 6, 1);
    defer renderer.deinit();
    renderer.capabilities.unicode = true;
    renderer.capabilities.double_width = true;

    try area.widget.draw(&renderer);
    try std.testing.expectEqual(@as(u21, 'A'), renderer.back.getCell(0, 0).codepoint());
    try std.testing.expectEqual(@as(u21, '界'), renderer.back.getCell(1, 0).codepoint());
    try std.testing.expect(renderer.back.getCell(2, 0).continuation);
    try std.testing.expectEqualStrings("e\u{0301}", renderer.back.getCell(3, 0).glyph.slice());
    try std.testing.expectEqual(@as(u21, 'B'), renderer.back.getCell(4, 0).codepoint());

    var narrow_renderer = try render.Renderer.init(alloc, 1, 1);
    defer narrow_renderer.deinit();
    narrow_renderer.capabilities.unicode = true;
    narrow_renderer.capabilities.double_width = true;
    try area.widget.layout(layout_module.Rect.init(0, 0, 1, 1));
    try area.setText("界a");
    try area.widget.draw(&narrow_renderer);
    try std.testing.expectEqual(@as(u21, ' '), narrow_renderer.back.getCell(0, 0).codepoint());
}

test "text area horizontal scroll starts on a grapheme boundary" {
    const alloc = std.testing.allocator;
    const area = try TextArea.init(alloc, 64);
    defer area.deinit();
    area.setBorder(.none);
    area.widget.focused = true;
    try area.widget.layout(layout_module.Rect.init(0, 0, 3, 1));
    try area.setText("界ab");
    area.ensureVisible(3, 1);

    try std.testing.expectEqual(@as(usize, 2), area.scroll_col);

    var renderer = try render.Renderer.init(alloc, 3, 1);
    defer renderer.deinit();
    renderer.capabilities.unicode = true;
    renderer.capabilities.double_width = true;
    try area.widget.draw(&renderer);

    try std.testing.expectEqual(@as(u21, 'a'), renderer.back.getCell(0, 0).codepoint());
    try std.testing.expectEqual(@as(u21, 'b'), renderer.back.getCell(1, 0).codepoint());
    try std.testing.expectEqual(@as(u21, '_'), renderer.back.getCell(2, 0).codepoint());
}

test "text area navigation and deletion keep combining graphemes atomic" {
    const alloc = std.testing.allocator;
    const area = try TextArea.init(alloc, 64);
    defer area.deinit();
    area.widget.focused = true;
    try area.setText("Ae\u{0301}B");

    const left = input.Event{ .key = input.KeyEvent.init(input.KeyCode.LEFT, input.KeyModifiers{}) };
    const right = input.Event{ .key = input.KeyEvent.init(input.KeyCode.RIGHT, input.KeyModifiers{}) };
    try std.testing.expect(try area.widget.handleEvent(left));
    try std.testing.expectEqual(@as(usize, 4), area.cursor);
    try std.testing.expect(try area.widget.handleEvent(left));
    try std.testing.expectEqual(@as(usize, 1), area.cursor);
    try std.testing.expect(try area.widget.handleEvent(right));
    try std.testing.expectEqual(@as(usize, 4), area.cursor);
    try std.testing.expect(try area.deleteBackward());
    try std.testing.expectEqualStrings("AB", area.getText());
}

test "text area expands partial selections to grapheme boundaries" {
    const alloc = std.testing.allocator;
    const area = try TextArea.init(alloc, 64);
    defer area.deinit();
    try area.setText("Ae\u{0301}B");
    area.selectRange(2, 3);

    try std.testing.expectEqual(TextArea.Selection{ .start = 1, .end = 4 }, area.selectionRange().?);
    try std.testing.expect(try area.deleteBackward());
    try std.testing.expectEqualStrings("AB", area.getText());
    try std.testing.expect(std.unicode.utf8ValidateSlice(area.getText()));
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
    try std.testing.expectEqual(@as(usize, 1), res.errors.items.len);
    try std.testing.expectEqualStrings("body", res.errors.items[0].field);
    try std.testing.expectEqualStrings("too short", res.errors.items[0].message);
}

fn textAreaInitAllocationFailureHarness(allocator: std.mem.Allocator) !void {
    const area = try TextArea.init(allocator, 64);
    area.deinit();
}

test "text area init cleans up every allocation failure path" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, textAreaInitAllocationFailureHarness, .{});
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

test "text area cursor iterator merges clamped duplicate positions" {
    const extras = [_]usize{ 1, 7, 9 };
    var marks = TextArea.CursorMarkIterator.init(&extras, 9, 4);

    try std.testing.expectEqual(TextArea.CursorMark{ .pos = 1, .primary = false }, marks.next().?);
    try std.testing.expectEqual(TextArea.CursorMark{ .pos = 4, .primary = true }, marks.next().?);
    try std.testing.expect(marks.next() == null);
}

test "text area focused multi-cursor draw remains allocation-free" {
    const alloc = std.testing.allocator;
    const area = try TextArea.init(alloc, 64);
    defer area.deinit();
    try area.setText("a界e\u{0301}");
    try area.setCursors(&[_]usize{ 7, 0, 4 });
    area.widget.focused = true;
    try area.widget.layout(layout_module.Rect.init(0, 0, 8, 3));

    var renderer = try render.Renderer.init(alloc, 8, 3);
    defer renderer.deinit();
    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = area.allocator;
    const original_renderer_allocator = renderer.allocator;
    area.allocator = failing.allocator();
    renderer.allocator = failing.allocator();
    defer {
        area.allocator = original_allocator;
        renderer.allocator = original_renderer_allocator;
    }

    try area.widget.draw(&renderer);
    try std.testing.expectEqual(@as(u21, '_'), renderer.back.getCell(1, 1).codepoint());
    try std.testing.expectEqual(@as(u21, '界'), renderer.back.getCell(2, 1).codepoint());
    try std.testing.expect(renderer.back.getCell(3, 1).continuation);
    try std.testing.expectEqual(@as(u21, '_'), renderer.back.getCell(4, 1).codepoint());
    try std.testing.expectEqual(@as(u21, '_'), renderer.back.getCell(5, 1).codepoint());
}

test "text area multi-cursor deletion preserves UTF-8" {
    const alloc = std.testing.allocator;
    const area = try TextArea.init(alloc, 64);
    defer area.deinit();

    try area.setText("aéb");
    try area.setCursors(&[_]usize{ 2, 3 });
    try std.testing.expectEqual(@as(usize, 1), area.cursor);
    try std.testing.expectEqualSlices(usize, &[_]usize{3}, area.extra_cursors.items);

    try area.setText("aéb界c");
    try area.setCursors(&[_]usize{ 7, 3 });
    try std.testing.expect(try area.deleteBackward());
    try std.testing.expectEqualStrings("abc", area.getText());
    try std.testing.expect(std.unicode.utf8ValidateSlice(area.getText()));
    try std.testing.expectEqual(@as(usize, 2), area.cursor);
    try std.testing.expectEqualSlices(usize, &[_]usize{1}, area.extra_cursors.items);

    try area.setText("aéb界c");
    try area.setCursors(&[_]usize{ 4, 1 });
    try std.testing.expect(try area.deleteForward());
    try std.testing.expectEqualStrings("abc", area.getText());
    try std.testing.expect(std.unicode.utf8ValidateSlice(area.getText()));
    try std.testing.expectEqual(@as(usize, 2), area.cursor);
    try std.testing.expectEqualSlices(usize, &[_]usize{1}, area.extra_cursors.items);
}

test "text area setCursors preserves cursors on allocation failure" {
    const alloc = std.testing.allocator;
    const area = try TextArea.init(alloc, 64);
    defer area.deinit();

    try area.setText("abcdef");
    try area.setCursors(&[_]usize{ 4, 1, 5 });
    try std.testing.expectEqual(@as(usize, 4), area.cursor);
    try std.testing.expectEqualSlices(usize, &[_]usize{ 1, 5 }, area.extra_cursors.items);

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = area.allocator;
    area.allocator = failing.allocator();
    defer area.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, area.setCursors(&[_]usize{ 2, 3, 6 }));
    try std.testing.expectEqual(@as(usize, 4), area.cursor);
    try std.testing.expectEqualSlices(usize, &[_]usize{ 1, 5 }, area.extra_cursors.items);
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

test "text area preserves validation result on allocation failure" {
    const alloc = std.testing.allocator;
    const area = try TextArea.init(alloc, 64);
    defer area.deinit();

    const rules = [_]form.Rule{
        form.required("body required"),
        form.minLength(10, "too short"),
    };
    try area.setValidation("body", &rules, true);
    const first = area.validationState().?;
    try std.testing.expect(!first.*.isValid());

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = area.allocator;
    area.allocator = failing.allocator();
    defer area.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, area.revalidate());
    const preserved = area.validationState().?;
    try std.testing.expect(!preserved.*.isValid());
    try std.testing.expectEqualStrings("body required", preserved.*.firstError().?.message);
}

test "text area setText preserves text on history allocation failure" {
    const alloc = std.testing.allocator;
    const area = try TextArea.init(alloc, 64);
    defer area.deinit();

    try area.setText("stable");
    try std.testing.expectEqual(@as(usize, 2), area.undo_redo.undo.items.len);

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = area.undo_redo.allocator;
    area.undo_redo.allocator = failing.allocator();
    defer area.undo_redo.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, area.setText("next"));
    try std.testing.expectEqualStrings("stable", area.getText());
    try std.testing.expectEqual(@as(usize, 2), area.undo_redo.undo.items.len);
    try std.testing.expectEqualStrings("stable", area.undo_redo.undo.items[1]);
}

test "text area setText preserves text on validation allocation failure" {
    const alloc = std.testing.allocator;
    const area = try TextArea.init(alloc, 64);
    defer area.deinit();

    const rules = [_]form.Rule{
        form.required("body required"),
        form.minLength(10, "too short"),
    };
    try area.setValidation("body", &rules, true);
    try area.setText("long enough");
    const first = area.validationState().?;
    try std.testing.expect(first.*.isValid());

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = area.allocator;
    area.allocator = failing.allocator();
    defer area.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, area.setText("tiny"));
    try std.testing.expectEqualStrings("long enough", area.getText());
    const preserved = area.validationState().?;
    try std.testing.expect(preserved.*.isValid());
}

test "text area setText resets cursor and scroll" {
    const alloc = std.testing.allocator;
    var area = try TextArea.init(alloc, 64);
    defer area.deinit();

    try area.setText("hello\nworld");
    area.scroll_row = 2;
    area.scroll_col = 1;
    area.selection = TextArea.Selection{ .start = 0, .end = 2 };

    try area.setText("new");

    try std.testing.expectEqual(@as(usize, 3), area.cursor);
    try std.testing.expectEqual(@as(usize, 0), area.scroll_row);
    try std.testing.expectEqual(@as(usize, 0), area.scroll_col);
    try std.testing.expectEqual(@as(?TextArea.Selection, null), area.selection);
}

test "text area visible mutations mark dirty" {
    const alloc = std.testing.allocator;
    const area = try TextArea.init(alloc, 64);
    defer area.deinit();

    area.widget.clearDirty();
    try area.setText("alpha");
    try std.testing.expect(area.widget.dirty);
    area.widget.clearDirty();
    try area.setText("alpha");
    try std.testing.expect(!area.widget.dirty);

    area.widget.clearDirty();
    try area.setPlaceholder("Notes");
    try std.testing.expect(area.widget.dirty);
    area.widget.clearDirty();
    try area.setPlaceholder("Notes");
    try std.testing.expect(!area.widget.dirty);

    area.widget.clearDirty();
    area.setBorder(.rounded);
    try std.testing.expect(area.widget.dirty);
    area.widget.clearDirty();
    area.setBorder(.rounded);
    try std.testing.expect(!area.widget.dirty);

    area.widget.clearDirty();
    area.setColors(render.Color.named(.white), render.Color.named(.black), render.Color.named(.black), render.Color.named(.green));
    try std.testing.expect(area.widget.dirty);
    area.widget.clearDirty();
    area.setColors(render.Color.named(.white), render.Color.named(.black), render.Color.named(.black), render.Color.named(.green));
    try std.testing.expect(!area.widget.dirty);

    area.widget.clearDirty();
    area.setTheme(theme.Theme.light());
    try std.testing.expect(area.widget.dirty);
    area.widget.clearDirty();
    area.setTheme(theme.Theme.light());
    try std.testing.expect(!area.widget.dirty);
}

test "text area selection and cursor mutations mark dirty" {
    const alloc = std.testing.allocator;
    const area = try TextArea.init(alloc, 64);
    defer area.deinit();

    try area.setText("abcdef");

    area.widget.clearDirty();
    area.selectRange(1, 4);
    try std.testing.expect(area.widget.dirty);
    area.widget.clearDirty();
    area.selectRange(1, 4);
    try std.testing.expect(!area.widget.dirty);

    area.widget.clearDirty();
    area.clearSelection();
    try std.testing.expect(area.widget.dirty);
    area.widget.clearDirty();
    area.clearSelection();
    try std.testing.expect(!area.widget.dirty);

    area.widget.clearDirty();
    try area.addCursor(2);
    try std.testing.expect(area.widget.dirty);
    area.widget.clearDirty();
    try area.addCursor(2);
    try std.testing.expect(!area.widget.dirty);

    area.widget.clearDirty();
    try area.setCursors(&[_]usize{ 3, 1, 5 });
    try std.testing.expect(area.widget.dirty);
    area.widget.clearDirty();
    try area.setCursors(&[_]usize{ 3, 1, 5 });
    try std.testing.expect(!area.widget.dirty);

    area.widget.clearDirty();
    try area.setCursors(&.{});
    try std.testing.expect(area.widget.dirty);
    try std.testing.expectEqual(@as(usize, 3), area.cursor);
    area.widget.clearDirty();
    try area.setCursors(&.{});
    try std.testing.expect(!area.widget.dirty);
}

test "text area validation state changes mark dirty" {
    const alloc = std.testing.allocator;
    const area = try TextArea.init(alloc, 64);
    defer area.deinit();

    const rules = [_]form.Rule{form.required("needed")};

    area.widget.clearDirty();
    try area.setValidation("body", &rules, true);
    try std.testing.expect(area.widget.dirty);
    try std.testing.expect(area.hasValidationError());

    area.widget.clearDirty();
    try area.revalidate();
    try std.testing.expect(!area.widget.dirty);

    try area.setText("valid");
    try std.testing.expect(area.widget.dirty);
    try std.testing.expect(!area.hasValidationError());

    area.widget.clearDirty();
    area.clearValidation();
    try std.testing.expect(!area.widget.dirty);
    try std.testing.expect(area.validationState() == null);
}

test "text area clips edge draw coordinates before u16 overflow" {
    const alloc = std.testing.allocator;
    const max = std.math.maxInt(u16);

    var area = try TextArea.init(alloc, 64);
    defer area.deinit();

    try area.setText("abcd");
    try area.widget.layout(layout_module.Rect.init(max - 1, max - 1, 4, 3));

    var renderer = try render.Renderer.init(alloc, 2, 2);
    defer renderer.deinit();

    try area.widget.draw(&renderer);

    try std.testing.expectEqual(@as(u21, ' '), renderer.back.getCell(0, 0).codepoint());
    try std.testing.expectEqual(@as(u21, ' '), renderer.back.getCell(1, 1).codepoint());
}

test "text area placeholder survives allocation failure" {
    const alloc = std.testing.allocator;
    var area = try TextArea.init(alloc, 64);
    defer area.deinit();

    try area.setPlaceholder("stable");
    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = area.allocator;
    area.allocator = failing.allocator();
    defer area.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, area.setPlaceholder("replacement"));
    try std.testing.expectEqualStrings("stable", area.placeholder);
}

test "text area validation name survives allocation failure" {
    const alloc = std.testing.allocator;
    var area = try TextArea.init(alloc, 64);
    defer area.deinit();

    const rules = [_]form.Rule{form.required("needed")};
    try area.setValidation("stable", &rules, false);

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = area.allocator;
    area.allocator = failing.allocator();
    defer area.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, area.setValidation("replacement", &rules, false));
    try std.testing.expectEqualStrings("stable", area.validation_field_name);
    try std.testing.expect(area.validation_field_owned);
}

test "text area inserts moves and deletes UTF-8 text input atomically" {
    const alloc = std.testing.allocator;
    const area = try TextArea.init(alloc, 32);
    defer area.deinit();
    area.widget.focused = true;

    try std.testing.expect(try area.widget.handleEvent(.{ .key = input.KeyEvent.init('a', .{}) }));
    try std.testing.expect(try area.widget.handleEvent(.{ .key = input.KeyEvent.init(0x00E9, .{}) }));
    try std.testing.expect(try area.widget.handleEvent(.{ .key = input.KeyEvent.init('b', .{}) }));
    try std.testing.expectEqualStrings("aéb", area.getText());
    try std.testing.expectEqual(@as(usize, 4), area.cursor);

    try std.testing.expect(try area.widget.handleEvent(.{ .key = input.KeyEvent.init(input.KeyCode.LEFT, .{}) }));
    try std.testing.expectEqual(@as(usize, 3), area.cursor);
    try std.testing.expect(try area.widget.handleEvent(.{ .key = input.KeyEvent.init(input.KeyCode.LEFT, .{}) }));
    try std.testing.expectEqual(@as(usize, 1), area.cursor);

    try std.testing.expect(try area.widget.handleEvent(.{ .key = input.KeyEvent.init(input.KeyCode.DELETE, .{}) }));
    try std.testing.expectEqualStrings("ab", area.getText());
    try std.testing.expectEqual(@as(usize, 1), area.cursor);
}

test "text area consumes bracketed paste delimiter keys" {
    const alloc = std.testing.allocator;
    const area = try TextArea.init(alloc, 32);
    defer area.deinit();
    area.widget.focused = true;

    try area.setText("safe");

    try std.testing.expect(try area.widget.handleEvent(.{ .key = input.KeyEvent.init(input.KeyCode.BRACKETED_PASTE_START, .{}) }));
    try std.testing.expect(area.bracketed_paste_active);
    try std.testing.expect(try area.widget.handleEvent(.{ .key = input.KeyEvent.init(input.KeyCode.BRACKETED_PASTE_END, .{}) }));
    try std.testing.expect(!area.bracketed_paste_active);
    try std.testing.expectEqualStrings("safe", area.getText());
    try std.testing.expectEqual(@as(usize, 4), area.cursor);
}

test "text area inserts newline inside bracketed paste" {
    const alloc = std.testing.allocator;
    const area = try TextArea.init(alloc, 32);
    defer area.deinit();
    area.widget.focused = true;

    try std.testing.expect(try area.widget.handleEvent(.{ .key = input.KeyEvent.init('a', .{}) }));
    try std.testing.expect(try area.widget.handleEvent(.{ .key = input.KeyEvent.init(input.KeyCode.BRACKETED_PASTE_START, .{}) }));
    try std.testing.expect(try area.widget.handleEvent(.{ .key = input.KeyEvent.init(input.KeyCode.ENTER, .{}) }));
    try std.testing.expect(try area.widget.handleEvent(.{ .key = input.KeyEvent.init('b', .{}) }));
    try std.testing.expect(try area.widget.handleEvent(.{ .key = input.KeyEvent.init(input.KeyCode.BRACKETED_PASTE_END, .{}) }));

    try std.testing.expectEqualStrings("a\nb", area.getText());
    try std.testing.expectEqual(@as(usize, 3), area.cursor);
}

test "text area cancels bracketed paste when focus is lost" {
    const alloc = std.testing.allocator;
    const area = try TextArea.init(alloc, 32);
    defer area.deinit();

    area.widget.setFocus(true);
    try std.testing.expect(try area.widget.handleEvent(.{ .key = input.KeyEvent.init(input.KeyCode.BRACKETED_PASTE_START, .{}) }));
    try std.testing.expect(area.bracketed_paste_active);

    area.widget.setFocus(false);
    try std.testing.expect(!area.bracketed_paste_active);
}

test "text area max bytes does not split UTF-8 input" {
    const alloc = std.testing.allocator;
    const area = try TextArea.init(alloc, 3);
    defer area.deinit();
    area.widget.focused = true;

    try area.setText("éxy");
    try std.testing.expectEqualStrings("éx", area.getText());
    try std.testing.expectEqual(@as(usize, 3), area.cursor);

    try std.testing.expect(try area.widget.handleEvent(.{ .key = input.KeyEvent.init(input.KeyCode.BACKSPACE, .{}) }));
    try std.testing.expectEqualStrings("é", area.getText());
    try std.testing.expect(!try area.widget.handleEvent(.{ .key = input.KeyEvent.init(0x1F642, .{}) }));
    try std.testing.expectEqualStrings("é", area.getText());
}

test "text area mouse focus ignores border rows" {
    const alloc = std.testing.allocator;
    const area = try TextArea.init(alloc, 64);
    defer area.deinit();

    try area.widget.layout(layout_module.Rect.init(2, 3, 20, 5));

    try std.testing.expect(!try area.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 4, 3, 1, 0) }));
    try std.testing.expect(try area.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 4, 4, 1, 0) }));
    try std.testing.expect(!try area.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 4, 7, 1, 0) }));
}
