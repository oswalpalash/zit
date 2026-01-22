const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const form = @import("../form.zig");
const input_mask = @import("../input_mask.zig");

/// Input field widget for text entry
pub const InputField = struct {
    /// Base widget
    widget: base.Widget,
    /// Text content
    text: []u8,
    /// Active text length
    len: usize = 0,
    /// Current cursor position
    cursor: usize = 0,
    /// Maximum text length
    max_length: usize,
    /// Foreground color
    fg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    /// Background color
    bg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    /// Focused foreground color
    focused_fg: render.Color = render.Color{ .named_color = render.NamedColor.black },
    /// Focused background color
    focused_bg: render.Color = render.Color{ .named_color = render.NamedColor.cyan },
    /// Disabled foreground color
    disabled_fg: render.Color = render.Color{ .named_color = render.NamedColor.bright_black },
    /// Disabled background color
    disabled_bg: render.Color = render.Color{ .named_color = render.NamedColor.black },
    /// Text style
    style: render.Style = render.Style{},
    /// Border style
    border: render.BorderStyle = .single,
    /// Show border
    show_border: bool = true,
    /// Placeholder text
    placeholder: []const u8 = "",
    /// Whether placeholder memory is owned by this widget
    placeholder_owned: bool = false,
    /// Optional formatter that enforces a masking pattern
    mask: ?input_mask.Mask = null,
    /// Validation rules to run against the current value
    validation_rules: ?[]const form.Rule = null,
    /// Field name used for validation reporting
    validation_field_name: []const u8 = "value",
    validation_field_owned: bool = false,
    /// Whether to automatically re-run validation on each edit
    validate_on_change: bool = false,
    /// Callback invoked after validation completes
    on_validation: ?*const fn (*InputField, *const form.ValidationResult) void = null,
    /// Cached validation result (owned)
    last_validation: ?form.ValidationResult = null,
    /// Colors used when the input is invalid
    invalid_fg: render.Color = render.Color{ .named_color = render.NamedColor.white },
    invalid_bg: render.Color = render.Color{ .named_color = render.NamedColor.red },
    /// On change callback
    on_change: ?*const fn ([]const u8) void = null,
    /// On submit callback
    on_submit: ?*const fn ([]const u8) void = null,
    /// Allocator for text operations
    allocator: std.mem.Allocator,
    /// Undo/redo history
    undo_redo: input.UndoRedoStack,
    /// Owned clipboard storage
    clipboard_storage: input.Clipboard,
    /// Active clipboard reference
    clipboard: *input.Clipboard,
    /// Whether the clipboard is owned by this widget
    owns_clipboard: bool = true,

    /// Virtual method table for InputField
    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    /// Initialize a new input field
    pub fn init(allocator: std.mem.Allocator, max_length: usize) !*InputField {
        const capacity = @max(max_length, 1);
        const self = try allocator.create(InputField);
        const initial_buffer = try allocator.alloc(u8, capacity);

        @memset(initial_buffer, 0);

        self.* = InputField{
            .widget = base.Widget.init(&vtable),
            .text = initial_buffer,
            .max_length = capacity,
            .allocator = allocator,
            .undo_redo = input.UndoRedoStack.init(allocator),
            .clipboard_storage = input.Clipboard.init(allocator),
            .clipboard = undefined,
        };

        self.clipboard = &self.clipboard_storage;
        self.widget.setFocusRing(render.FocusRingStyle{
            .color = self.focused_bg,
            .border = .rounded,
            .style = render.Style{ .bold = true },
        });
        try self.undo_redo.capture(self.text[0..0]);

        return self;
    }

    /// Clean up input field resources
    pub fn deinit(self: *InputField) void {
        if (self.placeholder_owned and self.placeholder.len > 0) {
            self.allocator.free(self.placeholder);
        }
        self.clearMask();
        self.clearValidationResult();
        if (self.validation_field_owned and self.validation_field_name.len > 0) {
            self.allocator.free(self.validation_field_name);
        }
        self.undo_redo.deinit();
        if (self.owns_clipboard) {
            self.clipboard_storage.deinit();
        }
        self.allocator.free(self.text);
        self.allocator.destroy(self);
    }

    fn currentText(self: *const InputField) []const u8 {
        return self.text[0..self.len];
    }

    fn resetSentinel(self: *InputField) void {
        if (self.len < self.text.len) {
            self.text[self.len] = 0;
        }
    }

    fn writeText(self: *InputField, value: []const u8) void {
        const len = @min(value.len, self.text.len);
        @memset(self.text, 0);
        if (len > 0) {
            std.mem.copyForwards(u8, self.text[0..len], value[0..len]);
        }
        self.len = len;
        self.cursor = len;
        self.resetSentinel();
    }

    fn ensureCapacity(self: *InputField, capacity: usize) !void {
        if (capacity <= self.text.len) return;

        const resized = try self.allocator.realloc(self.text, capacity);
        if (capacity > self.text.len) {
            @memset(resized[self.text.len..capacity], 0);
        }
        self.text = resized;
        self.max_length = capacity;
        self.resetSentinel();
    }

    fn clearMask(self: *InputField) void {
        if (self.mask) |*existing| {
            existing.deinit();
        }
        self.mask = null;
    }

    fn setValidationFieldName(self: *InputField, name: []const u8) !void {
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

    fn applyMask(self: *InputField) !void {
        if (self.mask) |*mask_value| {
            const masked = try mask_value.format(self.allocator, self.currentText());
            defer self.allocator.free(masked);
            const copy_len = @min(masked.len, self.text.len);
            self.writeText(masked[0..copy_len]);
            self.cursor = self.len;
        }
    }

    fn clearValidationResult(self: *InputField) void {
        if (self.last_validation) |*res| {
            res.deinit();
        }
        self.last_validation = null;
    }

    fn runValidation(self: *InputField) !void {
        if (self.validation_rules) |rules| {
            self.clearValidationResult();
            const result = try form.validateField(self.allocator, self.validation_field_name, self.getText(), rules);
            self.last_validation = result;
            if (self.on_validation) |callback| {
                callback(self, &self.last_validation.?);
            }
        }
    }

    fn finalizeChange(self: *InputField, capture_history: bool, force_validate: bool) void {
        self.applyMask() catch {};
        self.resetSentinel();
        self.clampCursor();
        if (capture_history) self.pushHistory() catch {};
        if ((self.validate_on_change or force_validate) and self.validation_rules != null) {
            self.runValidation() catch {};
        }
        self.notifyChange();
    }

    fn hasValidationError(self: *const InputField) bool {
        if (self.last_validation) |result| {
            return !result.isValid();
        }
        return false;
    }

    fn clampCursor(self: *InputField) void {
        if (self.cursor > self.len) {
            self.cursor = self.len;
        }
    }

    fn pushHistory(self: *InputField) !void {
        try self.undo_redo.capture(self.currentText());
    }

    fn notifyChange(self: *InputField) void {
        if (self.on_change) |callback| {
            callback(self.currentText());
        }
    }

    fn applySnapshot(self: *InputField, snapshot: []const u8) void {
        self.writeText(snapshot);
        self.finalizeChange(false, self.validate_on_change);
    }

    /// Share a clipboard instance between multiple input fields.
    pub fn useClipboard(self: *InputField, clipboard: *input.Clipboard) void {
        if (self.owns_clipboard) {
            self.clipboard_storage.deinit();
        }
        self.clipboard = clipboard;
        self.owns_clipboard = false;
    }

    /// Toggle integration with the system clipboard when supported by the host.
    pub fn preferSystemClipboard(self: *InputField, enable: bool) void {
        self.clipboard.preferSystem(enable);
    }

    /// Limit undo history growth.
    pub fn setHistoryDepth(self: *InputField, depth: usize) void {
        self.undo_redo.setMaxDepth(depth);
    }

    /// Set the input field text
    pub fn setText(self: *InputField, text: []const u8) void {
        self.writeText(text);
        self.finalizeChange(true, self.validate_on_change);
    }

    /// Undo the most recent edit, returning true when the buffer changed.
    pub fn undo(self: *InputField) bool {
        return (self.performUndo() catch false);
    }

    /// Redo the most recently undone edit, returning true when the buffer changed.
    pub fn redo(self: *InputField) bool {
        return (self.performRedo() catch false);
    }

    /// Validate the current value using the provided rules.
    pub fn validate(self: *InputField, allocator: std.mem.Allocator, field_name: []const u8, rules: []const form.Rule) !form.ValidationResult {
        return form.validateField(allocator, field_name, self.getText(), rules);
    }

    /// Get the current text
    pub fn getText(self: *InputField) []const u8 {
        return self.currentText();
    }

    /// Set the placeholder text. Existing owned placeholder memory is released before storing the new value.
    pub fn setPlaceholder(self: *InputField, placeholder: []const u8) !void {
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

    /// Apply a mask pattern (e.g. "(###) ###-####"). The input field owns the mask.
    pub fn setMaskPattern(self: *InputField, pattern: []const u8) !void {
        const mask = try input_mask.Mask.init(self.allocator, pattern);
        self.setMask(mask);
    }

    /// Assign a pre-built mask (ownership is transferred to the input).
    pub fn setMask(self: *InputField, mask: input_mask.Mask) void {
        self.clearMask();
        self.mask = mask;
        self.ensureCapacity(self.mask.?.maxLength()) catch {};
        self.applyMask() catch {};
    }

    /// Remove the active mask and leave the current text untouched.
    pub fn disableMask(self: *InputField) void {
        self.clearMask();
    }

    /// Set the border style
    pub fn setBorder(self: *InputField, border: render.BorderStyle) void {
        self.border = border;
        self.show_border = border != .none;
    }

    /// Set the input field colors
    pub fn setColors(self: *InputField, fg: render.Color, bg: render.Color, focused_fg: render.Color, focused_bg: render.Color) void {
        self.fg = fg;
        self.bg = bg;
        self.focused_fg = focused_fg;
        self.focused_bg = focused_bg;
    }

    /// Set the on-change callback
    pub fn setOnChange(self: *InputField, callback: *const fn ([]const u8) void) void {
        self.on_change = callback;
    }

    /// Set the on-submit callback
    pub fn setOnSubmit(self: *InputField, callback: *const fn ([]const u8) void) void {
        self.on_submit = callback;
    }

    /// Assign validation rules and a logical field name for error reporting.
    pub fn setValidation(self: *InputField, field_name: []const u8, rules: []const form.Rule, realtime: bool) !void {
        try self.setValidationFieldName(field_name);
        self.validation_rules = rules;
        self.validate_on_change = realtime;
        if (realtime) try self.runValidation();
    }

    /// Clear validation metadata and any cached results.
    pub fn clearValidation(self: *InputField) void {
        self.validation_rules = null;
        self.validate_on_change = false;
        self.clearValidationResult();
    }

    /// Manually trigger validation using the configured rules.
    pub fn revalidate(self: *InputField) !void {
        try self.runValidation();
    }

    /// Hook invoked whenever validation runs (manual or real-time).
    pub fn setOnValidate(self: *InputField, callback: *const fn (*InputField, *const form.ValidationResult) void) void {
        self.on_validation = callback;
    }

    /// Access the most recent validation result (owned by the input).
    pub fn validationState(self: *InputField) ?*const form.ValidationResult {
        if (self.last_validation) |*res| return res;
        return null;
    }

    /// Draw implementation for InputField
    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *InputField = @fieldParentPtr("widget", widget_ref);

        if (!self.widget.visible) {
            return;
        }

        self.clampCursor();

        const rect = self.widget.rect;

        // Choose colors based on state
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

        // Fill input field background
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', fg, bg, self.style);

        // Draw border if enabled
        if (self.show_border) {
            renderer.drawBox(rect.x, rect.y, rect.width, rect.height, self.border, fg, bg, self.style);
        }

        // Get text content
        const content = self.getText();

        // Calculate content area
        const border_adjust: u16 = if (self.show_border) 1 else 0;
        const inner_x = rect.x + border_adjust;
        const inner_y = rect.y + rect.height / 2;
        const inner_width = if (rect.width > 2 * border_adjust) rect.width - 2 * border_adjust else 0;

        // Draw placeholder if no text
        if (content.len == 0 and self.placeholder.len > 0 and inner_width > 0) {
            if (self.placeholder.len <= inner_width) {
                renderer.drawStr(inner_x, inner_y, self.placeholder, fg, bg, self.style);
            } else if (inner_width > 3) {
                var truncated: [256]u8 = undefined;
                const copy_len: usize = @min(@as(usize, inner_width - 3), self.placeholder.len);
                const safe_len = @min(copy_len, truncated.len - 3);
                @memcpy(truncated[0..safe_len], self.placeholder[0..safe_len]);
                @memcpy(truncated[safe_len .. safe_len + 3], "...");
                renderer.drawStr(inner_x, inner_y, truncated[0 .. safe_len + 3], fg, bg, self.style);
            } else {
                const slice_len: usize = @intCast(inner_width);
                renderer.drawStr(inner_x, inner_y, self.placeholder[0..slice_len], fg, bg, self.style);
            }
        }
        // Otherwise draw text
        else if (content.len > 0 and inner_width > 0) {
            var rendered_len: usize = 0;
            if (content.len <= inner_width) {
                renderer.drawStr(inner_x, inner_y, content, fg, bg, self.style);
                rendered_len = content.len;
            } else if (inner_width > 3) {
                var truncated: [256]u8 = undefined;
                const copy_len: usize = @min(@as(usize, inner_width - 3), content.len);
                const safe_len = @min(copy_len, truncated.len - 3);
                @memcpy(truncated[0..safe_len], content[0..safe_len]);
                @memcpy(truncated[safe_len .. safe_len + 3], "...");
                rendered_len = safe_len + 3;
                renderer.drawStr(inner_x, inner_y, truncated[0..rendered_len], fg, bg, self.style);
            } else {
                const slice_len: usize = @intCast(inner_width);
                rendered_len = slice_len;
                renderer.drawStr(inner_x, inner_y, content[0..slice_len], fg, bg, self.style);
            }

            // Draw cursor if focused
            if (self.widget.focused and self.cursor <= rendered_len) {
                const cursor_x = inner_x + @as(u16, @intCast(self.cursor));
                renderer.drawChar(cursor_x, inner_y, '_', fg, bg, render.Style{ .underline = true });
            }
        }

        self.widget.drawFocusRing(renderer);
    }

    fn applyEditorAction(self: *InputField, action: input.EditorAction) anyerror!bool {
        switch (action) {
            .cursor_left => {
                if (self.cursor > 0) self.cursor -= 1;
                return true;
            },
            .cursor_right => {
                if (self.cursor < self.len) self.cursor += 1;
                return true;
            },
            .line_start => {
                self.cursor = 0;
                return true;
            },
            .line_end => {
                self.cursor = self.len;
                return true;
            },
            .undo => return self.performUndo(),
            .redo => return self.performRedo(),
            .copy => return self.performCopy(),
            .paste => return self.performPaste(),
            .cut => return self.performCut(),
            else => return false,
        }
    }

    fn performUndo(self: *InputField) anyerror!bool {
        if (self.undo_redo.undoOp()) |snapshot| {
            self.applySnapshot(snapshot);
            return true;
        }
        return false;
    }

    fn performRedo(self: *InputField) anyerror!bool {
        if (self.undo_redo.redoOp()) |snapshot| {
            self.applySnapshot(snapshot);
            return true;
        }
        return false;
    }

    fn performCopy(self: *InputField) anyerror!bool {
        const slice = self.currentText();
        try self.clipboard.copy(slice);
        return slice.len > 0;
    }

    fn performCut(self: *InputField) anyerror!bool {
        const slice = self.currentText();
        if (slice.len == 0) return false;

        try self.clipboard.copy(slice);
        self.writeText("");
        self.finalizeChange(true, false);
        return true;
    }

    fn performPaste(self: *InputField) anyerror!bool {
        const pasted = self.clipboard.paste() orelse return false;
        if (pasted.len == 0) return false;

        const available = if (self.text.len > self.len) self.text.len - self.len else 0;
        if (available == 0) return false;

        const insert_len = @min(available, pasted.len);
        if (self.cursor < self.len) {
            const tail = self.len - self.cursor;
            if (tail > 0) {
                std.mem.copyBackwards(u8, self.text[self.cursor + insert_len .. self.cursor + insert_len + tail], self.text[self.cursor .. self.cursor + tail]);
            }
        }

        std.mem.copyForwards(u8, self.text[self.cursor .. self.cursor + insert_len], pasted[0..insert_len]);

        self.len += insert_len;
        self.cursor += insert_len;
        self.finalizeChange(true, false);
        return true;
    }

    fn insertByte(self: *InputField, value: u8) !void {
        if (self.len >= self.text.len) {
            return;
        }

        if (self.cursor < self.len) {
            const tail = self.len - self.cursor;
            std.mem.copyBackwards(u8, self.text[self.cursor + 1 .. self.cursor + 1 + tail], self.text[self.cursor .. self.cursor + tail]);
        }

        self.text[self.cursor] = value;
        self.len += 1;
        self.cursor += 1;
        self.finalizeChange(true, false);
    }

    /// Event handling implementation for InputField
    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *InputField = @fieldParentPtr("widget", widget_ref);

        if (!self.widget.visible or !self.widget.enabled) {
            return false;
        }

        // Only handle keyboard events when focused
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
                    self.clampCursor();
                    return true;
                }
            }

            switch (key_event.key) {
                input.KeyCode.ENTER => {
                    if (self.on_submit) |callback| {
                        callback(self.currentText());
                    }
                    return true;
                },
                input.KeyCode.BACKSPACE => {
                    if (self.cursor > 0 and self.len > 0) {
                        const tail = self.len - self.cursor;
                        if (tail > 0) {
                            std.mem.copyForwards(u8, self.text[self.cursor - 1 .. self.cursor - 1 + tail], self.text[self.cursor .. self.cursor + tail]);
                        }
                        self.len -= 1;
                        self.cursor -= 1;
                        self.finalizeChange(true, false);
                    }
                    return true;
                },
                input.KeyCode.DELETE => {
                    if (self.cursor < self.len) {
                        const tail = self.len - self.cursor - 1;
                        if (tail > 0) {
                            std.mem.copyForwards(u8, self.text[self.cursor .. self.cursor + tail], self.text[self.cursor + 1 .. self.cursor + 1 + tail]);
                        }
                        self.len -= 1;
                        self.finalizeChange(true, false);
                    }
                    return true;
                },
                else => {
                    // Regular character input
                    if (key_event.isPrintable() and !key_event.modifiers.ctrl and !key_event.modifiers.alt) {
                        try self.insertByte(@as(u8, @intCast(key_event.key)));
                        return true;
                    }
                },
            }
        }
        // Handle mouse events
        else if (event == .mouse) {
            const mouse_event = event.mouse;

            // Handle clicks to set focus
            if (mouse_event.action == .press and mouse_event.button == 1) {
                return self.widget.rect.contains(mouse_event.x, mouse_event.y);
            }
        }

        return false;
    }

    /// Layout implementation for InputField
    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *InputField = @fieldParentPtr("widget", widget_ref);
        self.widget.rect = rect;
    }

    /// Get preferred size implementation for InputField
    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *InputField = @fieldParentPtr("widget", widget_ref);

        // Calculate width based on max length plus borders
        const border_adjust: u16 = if (self.show_border) 2 else 0;

        return layout_module.Size.init(@as(u16, @intCast(@min(self.max_length, 40))) + border_adjust, // Cap width at 40 chars
            1 + border_adjust // Default height plus borders
        );
    }

    /// Can focus implementation for InputField
    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *InputField = @fieldParentPtr("widget", widget_ref);
        return self.widget.enabled;
    }
};

test "input field placeholder can be replaced safely" {
    const alloc = std.testing.allocator;
    const field = try InputField.init(alloc, 32);
    defer field.deinit();

    try field.setPlaceholder("first");
    try field.setPlaceholder("second");
    try std.testing.expectEqualStrings("second", field.placeholder);
}

test "input field supports undo and redo shortcuts" {
    const alloc = std.testing.allocator;
    const field = try InputField.init(alloc, 32);
    defer field.deinit();
    field.widget.focused = true;

    field.setText("abc");
    field.setText("abcd");

    const undo_event = input.Event{ .key = input.KeyEvent.init('z', input.KeyModifiers{ .ctrl = true }) };
    try std.testing.expect(try field.widget.handleEvent(undo_event));
    try std.testing.expectEqualStrings("abc", field.getText());

    const redo_event = input.Event{ .key = input.KeyEvent.init('y', input.KeyModifiers{ .ctrl = true }) };
    try std.testing.expect(try field.widget.handleEvent(redo_event));
    try std.testing.expectEqualStrings("abcd", field.getText());
}

test "input field copy and paste round trips through clipboard" {
    const alloc = std.testing.allocator;
    const field = try InputField.init(alloc, 32);
    defer field.deinit();
    field.widget.focused = true;

    field.setText("copy-me");
    const copy_event = input.Event{ .key = input.KeyEvent.init('c', input.KeyModifiers{ .ctrl = true }) };
    try std.testing.expect(try field.widget.handleEvent(copy_event));

    field.setText("");
    const paste_event = input.Event{ .key = input.KeyEvent.init('v', input.KeyModifiers{ .ctrl = true }) };
    try std.testing.expect(try field.widget.handleEvent(paste_event));

    try std.testing.expectEqualStrings("copy-me", field.getText());
}

test "input field undo/redo APIs restore key edits" {
    const alloc = std.testing.allocator;
    const field = try InputField.init(alloc, 16);
    defer field.deinit();
    field.widget.focused = true;

    const first = input.Event{ .key = input.KeyEvent.init('p', input.KeyModifiers{}) };
    const second = input.Event{ .key = input.KeyEvent.init('q', input.KeyModifiers{}) };
    const backspace = input.Event{ .key = input.KeyEvent.init(input.KeyCode.BACKSPACE, input.KeyModifiers{}) };

    try std.testing.expect(try field.widget.handleEvent(first));
    try std.testing.expectEqual(@as(usize, 1), field.len);
    try std.testing.expect(try field.widget.handleEvent(second));
    try std.testing.expectEqual(@as(usize, 2), field.len);
    try std.testing.expect(try field.widget.handleEvent(backspace));
    try std.testing.expectEqual(@as(usize, 1), field.getText().len);
    try std.testing.expectEqualStrings("p", field.getText());

    try std.testing.expect(field.undo());
    try std.testing.expectEqualStrings("pq", field.getText());
    try std.testing.expect(field.redo());
    try std.testing.expectEqualStrings("p", field.getText());
}

test "input field applies input mask formatting" {
    const alloc = std.testing.allocator;
    const field = try InputField.init(alloc, 8);
    defer field.deinit();

    try field.setMaskPattern("(###) ###-####");
    field.setText("12345");
    try std.testing.expectEqualStrings("(123) 45", field.getText());
}

test "input field can surface real-time validation results" {
    const alloc = std.testing.allocator;
    const field = try InputField.init(alloc, 32);
    defer field.deinit();

    const rules = [_]form.Rule{
        form.required("needed"),
        form.minLength(4, "too short"),
    };

    try field.setValidation("name", &rules, true);
    field.setText("ab");
    const first_state = field.validationState().?;
    try std.testing.expect(!first_state.*.isValid());

    field.setText("abcd");
    const second_state = field.validationState().?;
    try std.testing.expect(second_state.*.isValid());
}

test "input field expands capacity for longer masks" {
    const alloc = std.testing.allocator;
    const field = try InputField.init(alloc, 4);
    defer field.deinit();

    try std.testing.expectEqual(@as(usize, 4), field.max_length);
    try field.setMaskPattern("####-####-####");
    try std.testing.expectEqual(@as(usize, 14), field.max_length);
    try std.testing.expectEqual(field.max_length, field.text.len);

    field.setText("123456789012");
    try std.testing.expectEqualStrings("1234-5678-9012", field.getText());
}

test "input field clamps cursor beyond bounds during edits" {
    const alloc = std.testing.allocator;
    const field = try InputField.init(alloc, 8);
    defer field.deinit();
    field.widget.focused = true;

    field.setText("abc");
    field.cursor = 99;

    _ = try field.widget.handleEvent(.{ .key = input.KeyEvent.init(input.KeyCode.LEFT, input.KeyModifiers{}) });
    try std.testing.expectEqual(@as(usize, 2), field.cursor);

    field.cursor = 99;
    _ = try field.widget.handleEvent(.{ .key = input.KeyEvent.init(input.KeyCode.DELETE, input.KeyModifiers{}) });
    try std.testing.expectEqual(@as(usize, 3), field.cursor);
    try std.testing.expectEqualStrings("abc", field.getText());

    field.cursor = 99;
    _ = try field.widget.handleEvent(.{ .key = input.KeyEvent.init(input.KeyCode.BACKSPACE, input.KeyModifiers{}) });
    try std.testing.expectEqual(@as(usize, 2), field.cursor);
    try std.testing.expectEqualStrings("ab", field.getText());
}
