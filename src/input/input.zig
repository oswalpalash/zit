const std = @import("std");
const builtin = @import("builtin");
const terminal = @import("../terminal/terminal.zig");
const compat = @import("../compat.zig");

const windows_sync = struct {
    const WAIT_OBJECT_0: std.os.windows.DWORD = 0x00000000;
    const WAIT_TIMEOUT: std.os.windows.DWORD = 0x00000102;

    extern "kernel32" fn WaitForSingleObject(hHandle: std.os.windows.HANDLE, dwMilliseconds: std.os.windows.DWORD) std.os.windows.DWORD;
};

const default_resize_poll_interval_ms: u64 = 125;

fn terminalMouseCoordToScreenCoord(value: u16) u16 {
    return if (value > 0) value - 1 else 0;
}

fn legacyMouseByteToParam(byte: u8) ?u16 {
    if (byte < 32) return null;
    return @as(u16, byte) - 32;
}

fn appendDecimalParamDigit(current: u16, digit: u8) ?u16 {
    if (digit > 9) return null;
    const next = @as(u32, current) * 10 + digit;
    if (next > std.math.maxInt(u16)) return null;
    return @intCast(next);
}

fn shouldPollResize(last_poll_ms: i64, now_ms: i64, interval_ms: u64) bool {
    if (interval_ms == 0 or last_poll_ms == 0) return true;
    if (now_ms < last_poll_ms) return true;
    const elapsed: u64 = @intCast(now_ms - last_poll_ms);
    return elapsed >= interval_ms;
}

/// Input handling module
///
/// This module provides functionality for processing keyboard and mouse input:
/// - Keyboard event decoding (including special keys)
/// - Mouse event handling
/// - Focus navigation between UI elements
/// Represents different types of input events
pub const EventType = enum {
    key,
    mouse,
    resize,
    unknown,
};

/// Represents different mouse actions
pub const MouseAction = enum {
    press,
    release,
    move,
    scroll_up,
    scroll_down,
};

/// Special key codes
pub const KeyCode = struct {
    pub const BACKSPACE = 127;
    pub const ENTER = 13;
    pub const ESCAPE = 27;
    pub const TAB = 9;
    pub const SPACE = 32;

    pub const UP = 1001;
    pub const DOWN = 1002;
    pub const RIGHT = 1003;
    pub const LEFT = 1004;

    pub const HOME = 1005;
    pub const END = 1006;
    pub const PAGE_UP = 1007;
    pub const PAGE_DOWN = 1008;

    pub const INSERT = 1009;
    pub const DELETE = 1010;

    pub const F1 = 1011;
    pub const F2 = 1012;
    pub const F3 = 1013;
    pub const F4 = 1014;
    pub const F5 = 1015;
    pub const F6 = 1016;
    pub const F7 = 1017;
    pub const F8 = 1018;
    pub const F9 = 1019;
    pub const F10 = 1020;
    pub const F11 = 1021;
    pub const F12 = 1022;
};

/// Represents a keyboard event
pub const KeyEvent = struct {
    /// The key character or code
    key: u21,
    /// Modifier keys that were pressed
    modifiers: KeyModifiers,

    /// Create a new key event
    pub fn init(key: u21, modifiers: KeyModifiers) KeyEvent {
        return KeyEvent{
            .key = key,
            .modifiers = modifiers,
        };
    }

    /// Check if this is a special key
    pub fn isSpecialKey(self: KeyEvent) bool {
        return self.key >= 1000;
    }

    /// Check if this is a printable character
    pub fn isPrintable(self: KeyEvent) bool {
        return self.key >= 32 and self.key <= 126;
    }

    /// Check if this event carries text input rather than a control or special key.
    ///
    /// This accepts Unicode scalar values in addition to ASCII. The explicit
    /// special-key exclusions are necessary because legacy special key codes live
    /// in the `u21` range and overlap otherwise valid Unicode codepoints.
    pub fn isTextInput(self: KeyEvent) bool {
        if (self.key < 32 or self.key == 127) return false;
        if (self.key == KeyCode.BACKSPACE or
            self.key == KeyCode.ENTER or
            self.key == KeyCode.ESCAPE or
            self.key == KeyCode.TAB or
            self.key == KeyCode.UP or
            self.key == KeyCode.DOWN or
            self.key == KeyCode.RIGHT or
            self.key == KeyCode.LEFT or
            self.key == KeyCode.HOME or
            self.key == KeyCode.END or
            self.key == KeyCode.PAGE_UP or
            self.key == KeyCode.PAGE_DOWN or
            self.key == KeyCode.INSERT or
            self.key == KeyCode.DELETE or
            self.key == KeyCode.F1 or
            self.key == KeyCode.F2 or
            self.key == KeyCode.F3 or
            self.key == KeyCode.F4 or
            self.key == KeyCode.F5 or
            self.key == KeyCode.F6 or
            self.key == KeyCode.F7 or
            self.key == KeyCode.F8 or
            self.key == KeyCode.F9 or
            self.key == KeyCode.F10 or
            self.key == KeyCode.F11 or
            self.key == KeyCode.F12)
        {
            return false;
        }

        var buf: [4]u8 = undefined;
        _ = std.unicode.utf8Encode(self.key, &buf) catch return false;
        return true;
    }

    /// Encode this text-input key as UTF-8.
    pub fn utf8(self: KeyEvent, buffer: *[4]u8) ?[]const u8 {
        if (!self.isTextInput()) return null;
        const len = std.unicode.utf8Encode(self.key, buffer) catch return null;
        return buffer[0..len];
    }

    /// Get a string representation of the key
    pub fn getName(self: KeyEvent, allocator: std.mem.Allocator) ![]const u8 {
        if (self.isTextInput()) {
            var char_buf: [4]u8 = undefined;
            const encoded = self.utf8(&char_buf) orelse return try allocator.dupe(u8, "Unknown");
            return try allocator.dupe(u8, encoded);
        }

        const name = switch (self.key) {
            KeyCode.BACKSPACE => "Backspace",
            KeyCode.ENTER => "Enter",
            KeyCode.ESCAPE => "Escape",
            KeyCode.TAB => "Tab",
            KeyCode.SPACE => "Space",
            KeyCode.UP => "Up",
            KeyCode.DOWN => "Down",
            KeyCode.RIGHT => "Right",
            KeyCode.LEFT => "Left",
            KeyCode.HOME => "Home",
            KeyCode.END => "End",
            KeyCode.PAGE_UP => "PageUp",
            KeyCode.PAGE_DOWN => "PageDown",
            KeyCode.INSERT => "Insert",
            KeyCode.DELETE => "Delete",
            KeyCode.F1 => "F1",
            KeyCode.F2 => "F2",
            KeyCode.F3 => "F3",
            KeyCode.F4 => "F4",
            KeyCode.F5 => "F5",
            KeyCode.F6 => "F6",
            KeyCode.F7 => "F7",
            KeyCode.F8 => "F8",
            KeyCode.F9 => "F9",
            KeyCode.F10 => "F10",
            KeyCode.F11 => "F11",
            KeyCode.F12 => "F12",
            else => "Unknown",
        };
        return try allocator.dupe(u8, name);
    }

    /// Check if two key events are equal
    pub fn equals(self: KeyEvent, other: KeyEvent) bool {
        return self.modifiers.ctrl == other.modifiers.ctrl and
            self.modifiers.alt == other.modifiers.alt and
            self.modifiers.shift == other.modifiers.shift and
            self.normalizedKey() == other.normalizedKey();
    }

    fn normalizedKey(self: KeyEvent) u21 {
        if (self.modifiers.ctrl and self.key >= 1 and self.key <= 26) {
            return @as(u21, 'a') + (self.key - 1);
        }
        return self.key;
    }
};

/// Represents modifier keys
pub const KeyModifiers = struct {
    ctrl: bool = false,
    alt: bool = false,
    shift: bool = false,

    /// Create a new key modifiers struct
    pub fn init(ctrl: bool, alt: bool, shift: bool) KeyModifiers {
        return KeyModifiers{
            .ctrl = ctrl,
            .alt = alt,
            .shift = shift,
        };
    }

    /// Get a string representation of the modifiers
    pub fn toString(self: KeyModifiers, allocator: std.mem.Allocator) ![]const u8 {
        var parts = std.ArrayList(u8).empty;
        defer parts.deinit(allocator);

        if (self.ctrl) {
            try parts.appendSlice(allocator, "Ctrl+");
        }

        if (self.alt) {
            try parts.appendSlice(allocator, "Alt+");
        }

        if (self.shift) {
            try parts.appendSlice(allocator, "Shift+");
        }

        return try parts.toOwnedSlice(allocator);
    }
};

/// Represents a mouse event
pub const MouseEvent = struct {
    /// Type of mouse action
    action: MouseAction,
    /// X coordinate
    x: u16,
    /// Y coordinate
    y: u16,
    /// Which button was involved (1 = left, 2 = middle, 3 = right)
    button: u8,
    /// Scroll delta (positive for down/right, negative for up/left)
    scroll_delta: i16 = 0,

    /// Create a new mouse event in Zit's zero-based screen coordinate space.
    ///
    /// This is the same coordinate system used by `render.Renderer` and
    /// `layout.Rect`. Terminal protocol mouse coordinates are one-based; use
    /// `fromTerminalCoordinates` for raw SGR/X10 coordinates.
    pub fn init(action: MouseAction, x: u16, y: u16, button: u8, scroll_delta: i16) MouseEvent {
        return MouseEvent{
            .action = action,
            .x = x,
            .y = y,
            .button = button,
            .scroll_delta = scroll_delta,
        };
    }

    /// Create a mouse event from raw terminal protocol coordinates.
    ///
    /// SGR and legacy X10/normal tracking report one-based columns and rows.
    /// Widgets must never receive those raw values because they would place hit
    /// tests one row/column away from the rendered cells.
    pub fn fromTerminalCoordinates(action: MouseAction, terminal_x: u16, terminal_y: u16, button: u8, scroll_delta: i16) MouseEvent {
        return init(
            action,
            terminalMouseCoordToScreenCoord(terminal_x),
            terminalMouseCoordToScreenCoord(terminal_y),
            button,
            scroll_delta,
        );
    }
};

/// Represents a terminal resize event
pub const ResizeEvent = struct {
    /// New width in columns
    width: u16,
    /// New height in rows
    height: u16,

    /// Create a new resize event
    pub fn init(width: u16, height: u16) ResizeEvent {
        return ResizeEvent{
            .width = width,
            .height = height,
        };
    }
};

/// Represents any input event
pub const Event = union(EventType) {
    key: KeyEvent,
    mouse: MouseEvent,
    resize: ResizeEvent,
    unknown: void,
};

/// Lightweight decoder for synthetic event streams (benchmarks, tests).
pub fn decodeEventFromBytes(bytes: []const u8) !?Event {
    if (bytes.len == 0) return null;

    var reader = SliceByteReader{ .data = bytes };
    var sink = ByteSink{};

    const first = reader.readByte() catch return null;
    sink.put(first);

    if (first == KeyCode.ESCAPE) {
        const maybe_next = reader.readByte() catch {
            return Event{ .key = KeyEvent.init(KeyCode.ESCAPE, KeyModifiers{}) };
        };
        sink.put(maybe_next);

        if (maybe_next == '[') {
            return try parseCSISequence(&reader, &sink);
        }

        return Event{ .key = KeyEvent.init(maybe_next, KeyModifiers{ .alt = true }) };
    }

    if (first == '\r' or first == '\n') {
        return Event{ .key = KeyEvent.init(KeyCode.ENTER, KeyModifiers{}) };
    }

    if (first >= 0x80) {
        if (try readUtf8Key(first, &reader, &sink)) |cp| {
            return Event{ .key = KeyEvent.init(cp, KeyModifiers{}) };
        }
        return Event{ .unknown = {} };
    }

    return Event{ .key = KeyEvent.init(first, KeyModifiers{}) };
}

fn utf8ExpectedLength(first: u8) ?usize {
    if (first < 0x80) return 1;
    if ((first & 0b1110_0000) == 0b1100_0000) return 2;
    if ((first & 0b1111_0000) == 0b1110_0000) return 3;
    if ((first & 0b1111_1000) == 0b1111_0000) return 4;
    return null;
}

fn readUtf8Key(first: u8, reader: anytype, sink: anytype) !?u21 {
    const expected = utf8ExpectedLength(first) orelse return null;
    if (expected == 1) return first;

    var bytes: [4]u8 = undefined;
    bytes[0] = first;
    var idx: usize = 1;
    while (idx < expected) : (idx += 1) {
        const next = reader.readByte() catch |err| {
            if (isNonBlockingError(err) or err == error.EndOfStream or err == error.InputOutput) return null;
            return err;
        };
        sink.put(next);
        if ((next & 0b1100_0000) != 0b1000_0000) return null;
        bytes[idx] = next;
    }

    return std.unicode.utf8Decode(bytes[0..expected]) catch null;
}

const ByteSink = struct {
    buf: [32]u8 = undefined,
    len: usize = 0,

    fn put(self: *ByteSink, byte: u8) void {
        if (self.len >= self.buf.len) return;
        self.buf[self.len] = byte;
        self.len += 1;
    }
};

/// Editor-style actions used by configurable keybinding profiles.
pub const EditorAction = enum {
    cursor_left,
    cursor_right,
    cursor_up,
    cursor_down,
    word_left,
    word_right,
    line_start,
    line_end,
    page_up,
    page_down,
    undo,
    redo,
    search,
    replace,
    copy,
    paste,
    cut,
};

/// Describes a keybinding for an editor action.
pub const Keybinding = struct {
    action: EditorAction,
    key: KeyEvent,
};

const VI_BINDINGS = [_]Keybinding{
    .{ .action = .cursor_left, .key = KeyEvent.init('h', KeyModifiers{}) },
    .{ .action = .cursor_down, .key = KeyEvent.init('j', KeyModifiers{}) },
    .{ .action = .cursor_up, .key = KeyEvent.init('k', KeyModifiers{}) },
    .{ .action = .cursor_right, .key = KeyEvent.init('l', KeyModifiers{}) },
    .{ .action = .undo, .key = KeyEvent.init('u', KeyModifiers{}) },
    .{ .action = .redo, .key = KeyEvent.init('r', KeyModifiers{ .ctrl = true }) },
    .{ .action = .search, .key = KeyEvent.init('/', KeyModifiers{}) },
};

const EMACS_BINDINGS = [_]Keybinding{
    .{ .action = .cursor_left, .key = KeyEvent.init('b', KeyModifiers{ .ctrl = true }) },
    .{ .action = .cursor_right, .key = KeyEvent.init('f', KeyModifiers{ .ctrl = true }) },
    .{ .action = .cursor_up, .key = KeyEvent.init('p', KeyModifiers{ .ctrl = true }) },
    .{ .action = .cursor_down, .key = KeyEvent.init('n', KeyModifiers{ .ctrl = true }) },
    .{ .action = .line_start, .key = KeyEvent.init('a', KeyModifiers{ .ctrl = true }) },
    .{ .action = .line_end, .key = KeyEvent.init('e', KeyModifiers{ .ctrl = true }) },
    .{ .action = .undo, .key = KeyEvent.init('_', KeyModifiers{ .ctrl = true }) },
    .{ .action = .search, .key = KeyEvent.init('s', KeyModifiers{ .ctrl = true }) },
};

const COMMON_EDITING_BINDINGS = [_]Keybinding{
    .{ .action = .undo, .key = KeyEvent.init('z', KeyModifiers{ .ctrl = true }) },
    .{ .action = .redo, .key = KeyEvent.init('y', KeyModifiers{ .ctrl = true }) },
    .{ .action = .redo, .key = KeyEvent.init('Z', KeyModifiers{ .ctrl = true, .shift = true }) },
    .{ .action = .copy, .key = KeyEvent.init('c', KeyModifiers{ .ctrl = true }) },
    .{ .action = .paste, .key = KeyEvent.init('v', KeyModifiers{ .ctrl = true }) },
    .{ .action = .cut, .key = KeyEvent.init('x', KeyModifiers{ .ctrl = true }) },
};

/// Predefined profiles for popular editing paradigms.
pub const KeybindingProfile = struct {
    bindings: []const Keybinding,

    /// Vim-style bindings (hjkl navigation, dw/yy analogues for text areas).
    ///
    /// Returns: profile that can be passed to `editorActionForEvent`.
    pub fn vi() KeybindingProfile {
        return KeybindingProfile{
            .bindings = &VI_BINDINGS,
        };
    }

    /// Emacs-inspired cursor movement and edit shortcuts.
    ///
    /// Returns: profile that can be passed to `editorActionForEvent`.
    pub fn emacs() KeybindingProfile {
        return KeybindingProfile{
            .bindings = &EMACS_BINDINGS,
        };
    }

    /// Common desktop editing shortcuts (Ctrl+Z/Ctrl+Y/Ctrl+C/V/X).
    pub fn commonEditing() KeybindingProfile {
        return KeybindingProfile{
            .bindings = &COMMON_EDITING_BINDINGS,
        };
    }

    /// Match a single key event against the profile.
    ///
    /// Parameters:
    /// - `event`: key press to resolve into an editor action.
    /// Returns: `.cursor_*`/`.copy`/`.paste` actions on hit, otherwise `null`.
    pub fn match(self: KeybindingProfile, event: KeyEvent) ?EditorAction {
        for (self.bindings) |binding| {
            if (binding.key.equals(event)) return binding.action;
        }
        return null;
    }
};

/// Try a list of profiles in order until one matches the event.
pub fn matchEditorAction(event: KeyEvent, profiles: []const KeybindingProfile) ?EditorAction {
    for (profiles) |profile| {
        if (profile.match(event)) |action| return action;
    }
    return null;
}

/// Resolve an editor action using profiles plus baseline navigation keys.
pub fn editorActionForEvent(event: KeyEvent, profiles: []const KeybindingProfile) ?EditorAction {
    if (matchEditorAction(event, profiles)) |action| return action;

    return switch (event.key) {
        KeyCode.LEFT => .cursor_left,
        KeyCode.RIGHT => .cursor_right,
        KeyCode.UP => .cursor_up,
        KeyCode.DOWN => .cursor_down,
        KeyCode.HOME => .line_start,
        KeyCode.END => .line_end,
        KeyCode.PAGE_UP => .page_up,
        KeyCode.PAGE_DOWN => .page_down,
        else => null,
    };
}

/// Simple undo/redo stack tailored for text-like edits.
pub const UndoRedoStack = struct {
    undo: std.ArrayList([]u8),
    redo: std.ArrayList([]u8),
    allocator: std.mem.Allocator,
    max_depth: usize = 128,

    pub fn init(allocator: std.mem.Allocator) UndoRedoStack {
        return UndoRedoStack{
            .undo = std.ArrayList([]u8).empty,
            .redo = std.ArrayList([]u8).empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *UndoRedoStack) void {
        self.freeList(&self.undo);
        self.freeList(&self.redo);
        self.undo.deinit(self.allocator);
        self.redo.deinit(self.allocator);
    }

    /// Limit the number of remembered states to avoid unbounded memory.
    pub fn setMaxDepth(self: *UndoRedoStack, depth: usize) void {
        self.max_depth = if (depth == 0) 1 else depth;
        self.trim();
    }

    /// Capture a new snapshot as the current state.
    pub fn capture(self: *UndoRedoStack, snapshot: []const u8) !void {
        if (self.undo.items.len > 0) {
            const last = self.undo.items[self.undo.items.len - 1];
            if (std.mem.eql(u8, last, snapshot)) return;
        }

        const copy = try self.allocator.dupe(u8, snapshot);
        errdefer self.allocator.free(copy);
        try self.undo.append(self.allocator, copy);
        self.trim();
        self.clearRedo();
    }

    /// Move backward in history, returning the new active state.
    pub fn undoOp(self: *UndoRedoStack) ?[]const u8 {
        if (self.undo.items.len <= 1) return null;

        self.redo.ensureUnusedCapacity(self.allocator, 1) catch return null;
        const current = self.undo.pop().?;
        self.redo.appendAssumeCapacity(current);

        return self.undo.items[self.undo.items.len - 1];
    }

    /// Move forward in history, returning the new active state.
    pub fn redoOp(self: *UndoRedoStack) ?[]const u8 {
        if (self.redo.items.len == 0) return null;

        self.undo.ensureUnusedCapacity(self.allocator, 1) catch return null;
        const next = self.redo.pop().?;
        self.undo.appendAssumeCapacity(next);
        self.trim();

        return self.undo.items[self.undo.items.len - 1];
    }

    fn freeList(self: *UndoRedoStack, list: *std.ArrayList([]u8)) void {
        for (list.items) |item| self.allocator.free(item);
        list.clearRetainingCapacity();
    }

    fn clearRedo(self: *UndoRedoStack) void {
        self.freeList(&self.redo);
    }

    fn trim(self: *UndoRedoStack) void {
        while (self.undo.items.len > self.max_depth) {
            const dropped = self.undo.orderedRemove(0);
            self.allocator.free(dropped);
        }
    }
};

fn undoRedoCaptureAllocationFailureHarness(allocator: std.mem.Allocator) !void {
    var stack = UndoRedoStack.init(allocator);
    defer stack.deinit();

    try stack.capture("one");
    try stack.capture("two");
}

test "undo redo capture cleans up every allocation failure path" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, undoRedoCaptureAllocationFailureHarness, .{});
}

test "undo preserves history when redo allocation fails" {
    const alloc = std.testing.allocator;
    var stack = UndoRedoStack.init(alloc);
    defer stack.deinit();

    try stack.capture("one");
    try stack.capture("two");

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = stack.allocator;
    stack.allocator = failing.allocator();
    defer stack.allocator = original_allocator;

    try std.testing.expectEqual(@as(?[]const u8, null), stack.undoOp());
    try std.testing.expectEqual(@as(usize, 2), stack.undo.items.len);
    try std.testing.expectEqual(@as(usize, 0), stack.redo.items.len);
    try std.testing.expectEqualStrings("two", stack.undo.items[1]);
}

test "redo preserves history when undo allocation fails" {
    const alloc = std.testing.allocator;
    var stack = UndoRedoStack.init(alloc);
    defer stack.deinit();

    try stack.capture("one");
    try stack.capture("two");
    try std.testing.expectEqualStrings("one", stack.undoOp().?);

    stack.undo.shrinkAndFree(alloc, stack.undo.items.len);
    try std.testing.expectEqual(stack.undo.items.len, stack.undo.capacity);

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = stack.allocator;
    stack.allocator = failing.allocator();
    defer stack.allocator = original_allocator;

    try std.testing.expectEqual(@as(?[]const u8, null), stack.redoOp());
    try std.testing.expectEqual(@as(usize, 1), stack.undo.items.len);
    try std.testing.expectEqual(@as(usize, 1), stack.redo.items.len);
    try std.testing.expectEqualStrings("one", stack.undo.items[0]);
    try std.testing.expectEqualStrings("two", stack.redo.items[0]);
}

/// Clipboard bridge used for copy/paste flows with system fallbacks.
pub const Clipboard = struct {
    buffer: ?[]u8 = null,
    allocator: std.mem.Allocator,
    prefer_system: bool = false,
    max_bytes: usize = 16 * 1024,

    pub fn init(allocator: std.mem.Allocator) Clipboard {
        return Clipboard{ .allocator = allocator };
    }

    pub fn deinit(self: *Clipboard) void {
        self.clearBuffer();
    }

    pub fn copy(self: *Clipboard, data: []const u8) !void {
        const trimmed_len = @min(data.len, self.max_bytes);
        const trimmed = data[0..trimmed_len];

        try self.replaceBuffer(trimmed);

        if (self.prefer_system) {
            _ = self.tryWriteSystem(trimmed);
        }
    }

    pub fn paste(self: *Clipboard) ?[]const u8 {
        if (self.prefer_system) {
            if (self.tryReadSystem()) |system_data| {
                self.storeOwned(system_data);
            }
        }
        return self.buffer;
    }

    pub fn clear(self: *Clipboard) void {
        self.clearBuffer();
    }

    pub fn preferSystem(self: *Clipboard, enable: bool) void {
        self.prefer_system = enable;
    }

    fn replaceBuffer(self: *Clipboard, data: []const u8) !void {
        const owned = try self.allocator.dupe(u8, data);
        self.storeOwned(owned);
    }

    fn clearBuffer(self: *Clipboard) void {
        if (self.buffer) |buf| self.allocator.free(buf);
        self.buffer = null;
    }

    fn storeOwned(self: *Clipboard, owned: []u8) void {
        self.clearBuffer();
        self.buffer = owned;
    }

    fn tryWriteSystem(self: *Clipboard, data: []const u8) bool {
        const os_tag = builtin.os.tag;
        const commands = switch (os_tag) {
            .macos => &[_][]const []const u8{&[_][]const u8{"pbcopy"}},
            else => &[_][]const []const u8{
                &[_][]const u8{"wl-copy"},
                &[_][]const u8{ "xclip", "-selection", "clipboard" },
                &[_][]const u8{ "xsel", "--clipboard", "--input" },
            },
        };

        for (commands) |cmd| {
            if (self.pipeToCommand(cmd, data)) return true;
        }

        return false;
    }

    fn tryReadSystem(self: *Clipboard) ?[]u8 {
        const os_tag = builtin.os.tag;
        const commands = switch (os_tag) {
            .macos => &[_][]const []const u8{&[_][]const u8{"pbpaste"}},
            else => &[_][]const []const u8{
                &[_][]const u8{ "wl-paste", "-n" },
                &[_][]const u8{ "xclip", "-selection", "clipboard", "-o" },
                &[_][]const u8{ "xsel", "--clipboard", "--output" },
            },
        };

        for (commands) |cmd| {
            const result = self.readFromCommand(cmd) catch continue;
            return result;
        }

        return null;
    }

    fn pipeToCommand(self: *Clipboard, argv: []const []const u8, data: []const u8) bool {
        _ = self;
        _ = argv;
        _ = data;
        return false;
    }

    fn readFromCommand(self: *Clipboard, argv: []const []const u8) ![]u8 {
        const io = std.Io.Threaded.global_single_threaded.io();
        const result = try std.process.run(self.allocator, io, .{
            .argv = argv,
            .stdout_limit = .limited(self.max_bytes),
            .stderr_limit = .limited(0),
        });
        self.allocator.free(result.stderr);
        return result.stdout;
    }
};

/// Track multiple cursors using a lightweight value object.
pub const MultiCursor = struct {
    positions: std.ArrayList(struct { x: u16, y: u16 }),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MultiCursor {
        return MultiCursor{
            .positions = std.ArrayList(struct { x: u16, y: u16 }).empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MultiCursor) void {
        self.positions.deinit(self.allocator);
    }

    pub fn add(self: *MultiCursor, x: u16, y: u16) !void {
        try self.positions.append(self.allocator, .{ .x = x, .y = y });
    }

    pub fn clear(self: *MultiCursor) void {
        self.positions.clearRetainingCapacity();
    }
};

/// Represents a key-chord (sequence of two keys)
pub const KeyChord = struct {
    /// First key in the sequence
    first: KeyEvent,
    /// Second key in the sequence
    second: KeyEvent,

    /// Create a new key chord
    pub fn init(first: KeyEvent, second: KeyEvent) KeyChord {
        return KeyChord{
            .first = first,
            .second = second,
        };
    }

    /// Convert to string representation
    pub fn toString(self: KeyChord, allocator: std.mem.Allocator) ![]const u8 {
        const first_mod = try self.first.modifiers.toString(allocator);
        defer allocator.free(first_mod);
        const first_name = try self.first.getName(allocator);
        defer allocator.free(first_name);

        const second_mod = try self.second.modifiers.toString(allocator);
        defer allocator.free(second_mod);
        const second_name = try self.second.getName(allocator);
        defer allocator.free(second_name);

        return try std.fmt.allocPrint(allocator, "{s}{s} → {s}{s}", .{ first_mod, first_name, second_mod, second_name });
    }
};

/// Focus direction for navigating UI elements
pub const FocusDirection = enum {
    next,
    previous,
    up,
    down,
    left,
    right,
};

/// Normalize common navigation keystrokes into focus directions.
pub fn normalizeFocusDirection(event: KeyEvent) ?FocusDirection {
    return switch (event.key) {
        KeyCode.LEFT => .left,
        KeyCode.RIGHT => .right,
        KeyCode.UP => .up,
        KeyCode.DOWN => .down,
        KeyCode.TAB => if (event.modifiers.shift) .previous else .next,
        else => blk: {
            if (event.modifiers.ctrl or event.modifiers.alt) break :blk null;
            break :blk switch (event.key) {
                'h', 'H' => .left,
                'l', 'L' => .right,
                'k', 'K' => .up,
                'j', 'J' => .down,
                else => null,
            };
        },
    };
}

/// Virtual function table for focusables
pub const FocusableVTable = struct {
    /// Get focus ID
    getId: *const fn (self: *const anyopaque) u32,
    /// Handle focus gained
    onFocus: *const fn (self: *anyopaque) void,
    /// Handle focus lost
    onBlur: *const fn (self: *anyopaque) void,
    /// Handle key event while focused
    onKeyEvent: *const fn (self: *anyopaque, key: KeyEvent) bool,
};

/// Interface for focusable UI elements
pub const Focusable = struct {
    /// Interface table containing function pointers
    vtable: *const FocusableVTable,
    /// The context pointer for the implementation
    context: *anyopaque,

    /// Get the focusable's ID
    pub fn getId(self: Focusable) u32 {
        return self.vtable.getId(self.context);
    }

    /// Handle focus gained
    pub fn onFocus(self: Focusable) void {
        self.vtable.onFocus(self.context);
    }

    /// Handle focus lost
    pub fn onBlur(self: Focusable) void {
        self.vtable.onBlur(self.context);
    }

    /// Handle key event
    pub fn onKeyEvent(self: Focusable, key: KeyEvent) bool {
        return self.vtable.onKeyEvent(self.context, key);
    }
};

/// Manages focus between UI elements
pub const FocusManager = struct {
    /// Allocator for focus operations
    allocator: std.mem.Allocator,
    /// List of focusable elements in tab order
    elements: std.ArrayList(*Focusable),
    /// Currently focused element index
    current_focus: ?usize,

    /// Initialize a new focus manager
    pub fn init(allocator: std.mem.Allocator) FocusManager {
        return FocusManager{
            .allocator = allocator,
            .elements = std.ArrayList(*Focusable).empty,
            .current_focus = null,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *FocusManager) void {
        self.elements.deinit(self.allocator);
    }

    /// Add a focusable element
    pub fn addElement(self: *FocusManager, element: *Focusable) !void {
        try self.elements.append(self.allocator, element);

        // If this is the first element, focus it
        if (self.elements.items.len == 1) {
            self.current_focus = 0;
            element.onFocus();
        }
    }

    /// Remove a focusable element
    pub fn removeElement(self: *FocusManager, element: *Focusable) void {
        const element_id = element.getId();

        // Find and remove the element
        for (self.elements.items, 0..) |item, i| {
            if (item.getId() == element_id) {
                // If this is the focused element, clear focus
                if (self.current_focus != null and self.current_focus.? == i) {
                    item.onBlur();
                    self.current_focus = null;
                }

                // Update focus index if needed
                if (self.current_focus != null and self.current_focus.? > i) {
                    self.current_focus.? -= 1;
                }

                _ = self.elements.orderedRemove(i);
                break;
            }
        }

        // If we have elements but no focus, focus the first element
        if (self.elements.items.len > 0 and self.current_focus == null) {
            self.current_focus = 0;
            self.elements.items[0].onFocus();
        }
    }

    /// Move focus in the specified direction
    pub fn moveFocus(self: *FocusManager, direction: FocusDirection) bool {
        if (self.elements.items.len == 0) return false;

        // If nothing is focused, focus the first element
        if (self.current_focus == null) {
            self.current_focus = 0;
            self.elements.items[0].onFocus();
            return true;
        }

        const current = self.current_focus.?;
        var next: usize = current;

        switch (direction) {
            .next => {
                next = (current + 1) % self.elements.items.len;
            },
            .previous => {
                if (current == 0) {
                    next = self.elements.items.len - 1;
                } else {
                    next = current - 1;
                }
            },
            // For now, up/down/left/right just use next/previous
            // In a real implementation, these would need spatial awareness
            .up, .left => {
                if (current == 0) {
                    next = self.elements.items.len - 1;
                } else {
                    next = current - 1;
                }
            },
            .down, .right => {
                next = (current + 1) % self.elements.items.len;
            },
        }

        // Only change focus if it's actually changing
        if (next != current) {
            self.elements.items[current].onBlur();
            self.elements.items[next].onFocus();
            self.current_focus = next;
            return true;
        }

        return false;
    }

    /// Handle a key event by sending it to the focused element
    pub fn handleKeyEvent(self: *FocusManager, key: KeyEvent) bool {
        // If Tab is pressed, handle focus navigation
        if (key.key == KeyCode.TAB and !key.modifiers.ctrl and !key.modifiers.alt) {
            const direction: FocusDirection = if (key.modifiers.shift) .previous else .next;
            return self.moveFocus(direction);
        }

        // Give the focused element first chance at the event
        if (self.current_focus) |idx| {
            if (self.elements.items[idx].onKeyEvent(key)) {
                return true;
            }
        }

        // Fall back to focus navigation keys when the widget didn't consume the event
        if (normalizeFocusDirection(key)) |direction| {
            return self.moveFocus(direction);
        }

        return false;
    }

    /// Get the currently focused element, if any
    pub fn getFocusedElement(self: *FocusManager) ?*Focusable {
        if (self.current_focus == null) return null;
        return self.elements.items[self.current_focus.?];
    }
};

fn isNonBlockingError(err: anyerror) bool {
    return err == error.WouldBlock or err == error.Again;
}

fn readFileByte(file: std.Io.File) !u8 {
    const io = std.Io.Threaded.global_single_threaded.io();
    var buf: [1]u8 = undefined;
    const bytes_read = file.readStreaming(io, &.{buf[0..]}) catch |err| {
        if (isNonBlockingError(err)) return error.WouldBlock;
        return err;
    };
    if (bytes_read == 0) return error.EndOfStream;
    return buf[0];
}

const BufferSink = struct {
    buffer: *[32]u8,
    pos: *usize,

    fn put(self: *BufferSink, byte: u8) void {
        if (self.pos.* >= self.buffer.len) return;
        self.buffer[self.pos.*] = byte;
        self.pos.* += 1;
    }
};

const NullSink = struct {
    fn put(_: *NullSink, _: u8) void {}
};

const FileByteReader = struct {
    file: std.Io.File,

    fn readByte(self: *FileByteReader) !u8 {
        return readFileByte(self.file);
    }
};

const PosixByteReader = struct {
    fd: std.posix.fd_t,

    fn readByte(self: *PosixByteReader) !u8 {
        if (builtin.os.tag == .windows) return error.Unsupported;
        var buf: [1]u8 = undefined;
        const amount = std.posix.read(self.fd, buf[0..1]) catch |err| {
            if (isNonBlockingError(err)) return error.WouldBlock;
            return err;
        };
        if (amount == 0) return error.WouldBlock;
        return buf[0];
    }
};

const SliceByteReader = struct {
    data: []const u8,
    index: usize = 0,

    fn readByte(self: *SliceByteReader) !u8 {
        if (self.index >= self.data.len) return error.EndOfStream;
        const byte = self.data[self.index];
        self.index += 1;
        return byte;
    }
};

/// Input handler for processing terminal input
pub const InputHandler = struct {
    /// Allocator for input operations
    allocator: std.mem.Allocator,
    /// Buffer for reading input
    buffer: [32]u8,
    /// Buffer position
    buffer_pos: usize,
    /// Whether mouse events are enabled
    mouse_enabled: bool,
    /// Terminal instance
    term: *terminal.Terminal,
    /// Focus manager for UI elements
    focus_manager: ?FocusManager,
    /// Key chord mode
    chord_mode: bool,
    /// First key in a potential chord
    first_chord_key: ?KeyEvent,
    /// Timeout for key chord detection (in milliseconds)
    chord_timeout_ms: u64,
    /// Last key press time (for chord detection)
    last_key_time: i64,
    /// Interval for polling terminal size in addition to signal-driven resize.
    resize_poll_interval_ms: u64,
    /// Last terminal-size poll timestamp.
    last_resize_poll_ms: i64,

    /// Initialize a new input handler
    pub fn init(allocator: std.mem.Allocator, term: *terminal.Terminal) InputHandler {
        return InputHandler{
            .allocator = allocator,
            .buffer = [_]u8{0} ** 32,
            .buffer_pos = 0,
            .mouse_enabled = false,
            .term = term,
            .focus_manager = null,
            .chord_mode = false,
            .first_chord_key = null,
            .chord_timeout_ms = 1000, // 1 second timeout for chords
            .last_key_time = 0,
            .resize_poll_interval_ms = default_resize_poll_interval_ms,
            .last_resize_poll_ms = 0,
        };
    }

    /// Configure periodic terminal-size polling.
    ///
    /// Set `interval_ms` to 0 to check on every `pollEvent` call. Signal-driven
    /// resize events are still consumed immediately.
    pub fn setResizePollInterval(self: *InputHandler, interval_ms: u64) void {
        self.resize_poll_interval_ms = interval_ms;
    }

    /// Enable mouse tracking
    pub fn enableMouse(self: *InputHandler) !void {
        if (self.mouse_enabled) return;

        try compat.stdoutWriteAll("\x1b[?1000h"); // Enable mouse clicks
        try compat.stdoutWriteAll("\x1b[?1002h"); // Enable mouse movement
        try compat.stdoutWriteAll("\x1b[?1006h"); // Enable SGR extended mode
        self.mouse_enabled = true;
    }

    /// Disable mouse tracking
    pub fn disableMouse(self: *InputHandler) !void {
        if (!self.mouse_enabled) return;

        try compat.stdoutWriteAll("\x1b[?1006l"); // Disable SGR extended mode
        try compat.stdoutWriteAll("\x1b[?1002l"); // Disable mouse movement
        try compat.stdoutWriteAll("\x1b[?1000l"); // Disable mouse clicks
        self.mouse_enabled = false;
    }

    /// Read an event from input
    pub fn readEvent(self: *InputHandler) !Event {
        self.buffer_pos = 0;
        var sink = BufferSink{ .buffer = &self.buffer, .pos = &self.buffer_pos };

        // On macOS, we need to use a different approach for robust input handling
        if (builtin.os.tag == .macos) {
            var buffer: [1]u8 = undefined;

            // First check if data is available without blocking
            var poll_fds = [_]std.posix.pollfd{
                .{
                    .fd = self.term.stdin_fd,
                    .events = std.posix.POLL.IN,
                    .revents = 0,
                },
            };

            // Very short poll to check data availability
            _ = std.posix.poll(&poll_fds, 0) catch {
                return error.WouldBlock;
            };

            if ((poll_fds[0].revents & std.posix.POLL.IN) == 0) {
                return error.WouldBlock;
            }

            // Use read directly instead of going through Zig's reader abstraction
            // as it's more reliable on macOS for terminal input
            const amount = std.posix.read(self.term.stdin_fd, buffer[0..1]) catch {
                return error.WouldBlock;
            };

            if (amount == 0) {
                return error.WouldBlock;
            }

            sink.put(buffer[0]);

            // Check for escape sequence
            if (buffer[0] == 0x1b) {
                return try self.parseEscapeSequenceMac(&sink);
            }

            if (buffer[0] == KeyCode.BACKSPACE or buffer[0] == 8) {
                return Event{
                    .key = KeyEvent{
                        .key = KeyCode.BACKSPACE,
                        .modifiers = KeyModifiers{},
                    },
                };
            }

            if (buffer[0] == KeyCode.TAB) {
                return Event{
                    .key = KeyEvent{
                        .key = KeyCode.TAB,
                        .modifiers = KeyModifiers{},
                    },
                };
            }

            // Check for control characters
            if (buffer[0] < 32) {
                // Special handling for newline and carriage return
                if (buffer[0] == '\n' or buffer[0] == '\r') {
                    return Event{
                        .key = KeyEvent{
                            .key = KeyCode.ENTER,
                            .modifiers = KeyModifiers{},
                        },
                    };
                }

                return Event{
                    .key = KeyEvent{
                        .key = buffer[0],
                        .modifiers = KeyModifiers{
                            .ctrl = true,
                        },
                    },
                };
            }

            if (buffer[0] >= 0x80) {
                var utf8_reader = PosixByteReader{ .fd = self.term.stdin_fd };
                if (try readUtf8Key(buffer[0], &utf8_reader, &sink)) |cp| {
                    return Event{
                        .key = KeyEvent{
                            .key = cp,
                            .modifiers = KeyModifiers{},
                        },
                    };
                }
                return Event{ .unknown = {} };
            }

            // Regular key press
            return Event{
                .key = KeyEvent{
                    .key = buffer[0],
                    .modifiers = KeyModifiers{},
                },
            };
        }

        const stdin = std.Io.File.stdin();
        var reader = FileByteReader{ .file = stdin };

        // Read a single byte
        const byte = reader.readByte() catch |err| {
            // Handle all possible non-blocking errors consistently
            if (isNonBlockingError(err) or
                err == error.InputOutput or err == error.NotOpenForReading)
            {
                return error.WouldBlock; // Normalize all non-blocking errors
            }
            return err;
        };

        sink.put(byte);

        // Check for escape sequence
        if (byte == 0x1b) {
            return try self.parseEscapeSequenceStandard(&reader, &sink);
        }

        if (byte == KeyCode.BACKSPACE or byte == 8) {
            return Event{
                .key = KeyEvent{
                    .key = KeyCode.BACKSPACE,
                    .modifiers = KeyModifiers{},
                },
            };
        }

        if (byte == KeyCode.TAB) {
            return Event{
                .key = KeyEvent{
                    .key = KeyCode.TAB,
                    .modifiers = KeyModifiers{},
                },
            };
        }

        // Check for control characters
        if (byte < 32) {
            // Special handling for newline and carriage return
            if (byte == '\n' or byte == '\r') {
                return Event{
                    .key = KeyEvent{
                        .key = KeyCode.ENTER,
                        .modifiers = KeyModifiers{},
                    },
                };
            }

            return Event{
                .key = KeyEvent{
                    .key = byte,
                    .modifiers = KeyModifiers{
                        .ctrl = true,
                    },
                },
            };
        }

        if (byte >= 0x80) {
            if (try readUtf8Key(byte, &reader, &sink)) |cp| {
                return Event{
                    .key = KeyEvent{
                        .key = cp,
                        .modifiers = KeyModifiers{},
                    },
                };
            }
            return Event{ .unknown = {} };
        }

        // Regular key press
        return Event{
            .key = KeyEvent{
                .key = byte,
                .modifiers = KeyModifiers{},
            },
        };
    }

    fn parseEscapeSequenceMac(self: *InputHandler, sink: anytype) !Event {
        const escape_event = Event{
            .key = KeyEvent{
                .key = KeyCode.ESCAPE,
                .modifiers = KeyModifiers{},
            },
        };

        var buffer: [1]u8 = undefined;
        var poll_fds = [_]std.posix.pollfd{
            .{
                .fd = self.term.stdin_fd,
                .events = std.posix.POLL.IN,
                .revents = 0,
            },
        };

        // Poll with a very short timeout (5ms) to distinguish solo ESC from sequences
        const poll_result = std.posix.poll(&poll_fds, 5) catch {
            return escape_event;
        };

        if (poll_result <= 0 or (poll_fds[0].revents & std.posix.POLL.IN) == 0) {
            return escape_event;
        }

        const amount = std.posix.read(self.term.stdin_fd, buffer[0..1]) catch {
            return escape_event;
        };

        if (amount == 0) {
            return escape_event;
        }

        sink.put(buffer[0]);

        if (buffer[0] == '[') {
            var reader = PosixByteReader{ .fd = self.term.stdin_fd };
            return try parseCSISequence(&reader, sink);
        }

        return Event{
            .key = KeyEvent{
                .key = buffer[0],
                .modifiers = KeyModifiers{ .alt = true },
            },
        };
    }

    fn parseEscapeSequenceStandard(_: *InputHandler, reader: anytype, sink: anytype) !Event {
        const escape_event = Event{
            .key = KeyEvent{
                .key = KeyCode.ESCAPE,
                .modifiers = KeyModifiers{},
            },
        };

        const next_byte = reader.readByte() catch |err| {
            if (isNonBlockingError(err) or err == error.InputOutput or err == error.EndOfStream) {
                return escape_event;
            }
            return err;
        };

        sink.put(next_byte);

        if (next_byte == '[') {
            return try parseCSISequence(reader, sink);
        }

        return Event{
            .key = KeyEvent{
                .key = next_byte,
                .modifiers = KeyModifiers{ .alt = true },
            },
        };
    }

    fn pollResizeIfDue(self: *InputHandler) !?Event {
        const now_ms = compat.nowMillis();
        if (!shouldPollResize(self.last_resize_poll_ms, now_ms, self.resize_poll_interval_ms)) {
            return null;
        }
        self.last_resize_poll_ms = now_ms;

        if (try self.term.pollResize()) |size| {
            return Event{ .resize = ResizeEvent.init(size.width, size.height) };
        }
        return null;
    }

    /// Poll for an event with timeout
    pub fn pollEvent(self: *InputHandler, timeout_ms: u64) !?Event {
        if (try self.term.takeResize()) |size| {
            return Event{ .resize = ResizeEvent.init(size.width, size.height) };
        }
        if (try self.pollResizeIfDue()) |event| {
            return event;
        }

        if (builtin.os.tag == .windows) {
            const max_wait_ms: u64 = std.math.maxInt(std.os.windows.DWORD);
            const wait_ms: std.os.windows.DWORD = @intCast(@min(timeout_ms, max_wait_ms));
            const wait_result = windows_sync.WaitForSingleObject(self.term.stdin_fd, wait_ms);

            switch (wait_result) {
                windows_sync.WAIT_OBJECT_0 => {},
                windows_sync.WAIT_TIMEOUT => return try self.pollResizeIfDue(),
                else => return try self.pollResizeIfDue(),
            }

            return self.readEvent() catch |err| {
                if (isNonBlockingError(err)) {
                    return try self.pollResizeIfDue();
                }
                return err;
            };
        } else if (builtin.os.tag == .macos) {
            // On macOS we need to be extra careful about polling
            // First check if data is available with a very short timeout
            var poll_fds = [_]std.posix.pollfd{
                .{
                    .fd = self.term.stdin_fd,
                    .events = std.posix.POLL.IN,
                    .revents = 0,
                },
            };

            // Use the provided timeout (converted to milliseconds)
            const poll_result = std.posix.poll(&poll_fds, @intCast(timeout_ms)) catch {
                return null;
            };

            if (poll_result <= 0 or (poll_fds[0].revents & std.posix.POLL.IN) == 0) {
                return try self.pollResizeIfDue();
            }

            // Try to read an event - being careful with error handling
            return self.readEvent() catch |err| {
                if (isNonBlockingError(err)) {
                    // This can happen if the terminal state changes between poll and read
                    compat.sleepMillis(1); // Small pause
                    return try self.pollResizeIfDue();
                }
                // Pass through other errors
                return err;
            };
        } else {
            // For other platforms, use the standard implementation
            var poll_fds = [_]std.posix.pollfd{
                .{
                    .fd = self.term.stdin_fd,
                    .events = std.posix.POLL.IN,
                    .revents = 0,
                },
            };

            // Poll with timeout - don't capture error since we don't use it
            const ready = std.posix.poll(&poll_fds, @intCast(timeout_ms)) catch {
                return null;
            };

            // If there's no data or an error, return null
            if (ready <= 0 or (poll_fds[0].revents & std.posix.POLL.IN) == 0) {
                return try self.pollResizeIfDue();
            }

            // Try to read an event
            return self.readEvent() catch |err| {
                if (isNonBlockingError(err)) {
                    return try self.pollResizeIfDue();
                }
                return err;
            };
        }
    }

    /// Process input events and integrate with the event system
    pub fn processEvents(self: *InputHandler, event_processor: *fn (Event) anyerror!void) !void {
        // Poll for events with a small timeout
        const event = try self.pollEvent(10);

        if (event) |e| {
            try event_processor(e);
        }
    }

    /// Return normalized screen coordinates for a Zit mouse event.
    ///
    /// `pollEvent` and `decodeEventFromBytes` already normalize terminal
    /// protocol coordinates to the zero-based coordinate system used by
    /// rendering and widget layout. This helper is intentionally idempotent so
    /// callers do not accidentally shift clicks one row/column above the
    /// rendered target.
    pub fn translateMouseCoordinates(_: *InputHandler, x: u16, y: u16) struct { x: u16, y: u16 } {
        return .{ .x = x, .y = y };
    }

    /// Convert raw terminal protocol coordinates to Zit screen coordinates.
    ///
    /// Use this only for coordinates read outside `InputHandler`; events
    /// returned by `pollEvent` are already normalized.
    pub fn translateTerminalMouseCoordinates(_: *InputHandler, x: u16, y: u16) struct { x: u16, y: u16 } {
        return .{
            .x = terminalMouseCoordToScreenCoord(x),
            .y = terminalMouseCoordToScreenCoord(y),
        };
    }
};

fn decodeModifierParam(param: u16) KeyModifiers {
    if (param <= 1) return KeyModifiers{};
    const value = param - 1;
    return KeyModifiers{
        .shift = (value & 0x1) != 0,
        .alt = (value & 0x2) != 0,
        .ctrl = (value & 0x4) != 0,
    };
}

fn modifiersFromParams(params: []const u16) KeyModifiers {
    if (params.len < 2) return KeyModifiers{};
    return decodeModifierParam(params[params.len - 1]);
}

fn decodeCSIKey(final_char: u8, params: []const u16) ?KeyEvent {
    switch (final_char) {
        'A', 'B', 'C', 'D', 'H', 'F' => {
            const modifiers = modifiersFromParams(params);
            const key_code: u21 = switch (final_char) {
                'A' => KeyCode.UP,
                'B' => KeyCode.DOWN,
                'C' => KeyCode.RIGHT,
                'D' => KeyCode.LEFT,
                'H' => KeyCode.HOME,
                else => KeyCode.END,
            };

            return KeyEvent{
                .key = key_code,
                .modifiers = modifiers,
            };
        },
        'Z' => {
            return KeyEvent{
                .key = KeyCode.TAB,
                .modifiers = KeyModifiers{ .shift = true },
            };
        },
        '~' => {
            if (params.len == 0) return null;
            const code = params[0];
            const modifiers = if (params.len > 1) decodeModifierParam(params[1]) else KeyModifiers{};

            const key_code: ?u21 = switch (code) {
                1, 7 => KeyCode.HOME,
                2 => KeyCode.INSERT,
                3 => KeyCode.DELETE,
                4, 8 => KeyCode.END,
                5 => KeyCode.PAGE_UP,
                6 => KeyCode.PAGE_DOWN,
                11 => KeyCode.F1,
                12 => KeyCode.F2,
                13 => KeyCode.F3,
                14 => KeyCode.F4,
                15 => KeyCode.F5,
                17 => KeyCode.F6,
                18 => KeyCode.F7,
                19 => KeyCode.F8,
                20 => KeyCode.F9,
                21 => KeyCode.F10,
                23 => KeyCode.F11,
                24 => KeyCode.F12,
                else => null,
            };

            if (key_code) |key| {
                return KeyEvent{
                    .key = key,
                    .modifiers = modifiers,
                };
            }
        },
        else => {},
    }

    return null;
}

fn parseCSISequence(reader: anytype, sink: anytype) !Event {
    var params: [6]u16 = undefined;
    var param_count: usize = 0;
    var current: u16 = 0;
    var has_value = false;

    while (true) {
        const next_byte = reader.readByte() catch |err| {
            if (isNonBlockingError(err) or err == error.EndOfStream) {
                return Event{ .unknown = {} };
            }
            return err;
        };

        sink.put(next_byte);

        if (next_byte == '<') {
            return try parseMouseEventSgr(reader, sink);
        }

        if (param_count == 0 and !has_value and next_byte == 'M') {
            return try parseMouseEventLegacy(reader, sink);
        }

        if (next_byte >= '0' and next_byte <= '9') {
            current = appendDecimalParamDigit(current, next_byte - '0') orelse return Event{ .unknown = {} };
            has_value = true;
            continue;
        }

        if (next_byte == ';') {
            if (param_count < params.len) {
                params[param_count] = current;
                param_count += 1;
            }
            current = 0;
            has_value = false;
            continue;
        }

        if (has_value or param_count > 0) {
            if (param_count < params.len) {
                params[param_count] = current;
                param_count += 1;
            }
        }

        if (decodeCSIKey(next_byte, params[0..param_count])) |key| {
            return Event{ .key = key };
        }

        return Event{ .unknown = {} };
    }
}

fn parseMouseEventLegacy(reader: anytype, sink: anytype) !Event {
    // X10/Normal tracking: ESC [ M Cb Cx Cy
    var bytes: [3]u8 = undefined;
    var idx: usize = 0;

    while (idx < bytes.len) : (idx += 1) {
        const b = reader.readByte() catch |err| {
            if (isNonBlockingError(err) or err == error.EndOfStream) {
                return Event{ .unknown = {} };
            }
            return err;
        };
        sink.put(b);
        bytes[idx] = b;
    }

    const button_param = legacyMouseByteToParam(bytes[0]) orelse return Event{ .unknown = {} };
    const terminal_x = legacyMouseByteToParam(bytes[1]) orelse return Event{ .unknown = {} };
    const terminal_y = legacyMouseByteToParam(bytes[2]) orelse return Event{ .unknown = {} };
    const is_motion = (button_param & 0x20) != 0;
    const is_scroll = (button_param & 0x40) != 0;
    const is_release = (button_param & 0x3) == 3 and !is_scroll;

    var scroll_delta: i16 = 0;
    if (is_scroll) {
        scroll_delta = if ((button_param & 0x1) != 0) 1 else -1;
    }

    const button: u8 = if (is_scroll)
        @intCast(4 + (button_param & 0x1))
    else if (is_release)
        0
    else
        @intCast((button_param & 0x3) + 1);

    const action: MouseAction = if (is_scroll)
        (if (scroll_delta > 0) MouseAction.scroll_down else MouseAction.scroll_up)
    else if (is_motion)
        MouseAction.move
    else if (is_release)
        MouseAction.release
    else
        MouseAction.press;

    return Event{
        .mouse = MouseEvent.fromTerminalCoordinates(action, terminal_x, terminal_y, button, scroll_delta),
    };
}

fn parseMouseEventSgr(reader: anytype, sink: anytype) !Event {
    // Mouse events in SGR mode are of the form: ESC [ < Cb ; Cx ; Cy ; M/m
    // Where:
    // - Cb is the button number + modifiers
    // - Cx is the X coordinate (1-based)
    // - Cy is the Y coordinate (1-based)
    // - M indicates button press, m indicates button release

    var params: [3]u16 = undefined;
    var param_index: usize = 0;
    var param_value: u16 = 0;
    var param_has_value = false;
    var final_char: u8 = 0;

    // Parse parameters
    while (param_index < 3) {
        const c = reader.readByte() catch |err| {
            if (isNonBlockingError(err) or err == error.EndOfStream) {
                return Event{ .unknown = {} };
            }
            return err;
        };

        sink.put(c);

        if (c >= '0' and c <= '9') {
            // Append digit to parameter value.
            param_value = appendDecimalParamDigit(param_value, c - '0') orelse return Event{ .unknown = {} };
            param_has_value = true;
        } else if (c == ';') {
            // End of parameter
            if (!param_has_value) return Event{ .unknown = {} };
            if (param_index < params.len) {
                params[param_index] = param_value;
            }
            param_index += 1;
            param_value = 0;
            param_has_value = false;
        } else if (c == 'M' or c == 'm') {
            // End of mouse sequence
            if (!param_has_value) return Event{ .unknown = {} };
            if (param_index < params.len) {
                params[param_index] = param_value;
            }
            final_char = c;
            break;
        } else {
            // Unexpected character
            return Event{ .unknown = {} };
        }
    }

    if (param_index < 2 or final_char == 0) {
        return Event{ .unknown = {} };
    }

    // Extract the terminal's 1-based coordinates; the MouseEvent constructor
    // below normalizes them to the renderer/layout coordinate system.
    const button_param = params[0];

    // Decode the button parameter
    const button_code = @as(u8, @intCast(button_param & 0x3));
    const is_motion = (button_param & 0x20) != 0;
    const is_scroll = (button_param & 0x40) != 0 or (button_param & 0x80) != 0;

    var scroll_delta: i16 = 0;

    // Determine the action based on the final character and flags
    var action: MouseAction = undefined;
    if (is_scroll) {
        scroll_delta = if ((button_param & 0x1) != 0) 1 else -1;
        action = if (scroll_delta > 0) MouseAction.scroll_down else MouseAction.scroll_up;
    } else if (final_char == 'm') {
        action = MouseAction.release;
    } else if (is_motion) {
        action = MouseAction.move;
    } else {
        action = MouseAction.press;
    }

    const button: u8 = if (is_scroll)
        @intCast(4 + (button_code & 0x1))
    else
        button_code + 1;

    return Event{
        .mouse = MouseEvent.fromTerminalCoordinates(action, params[1], params[2], button, scroll_delta),
    };
}

test "parse CSI arrow modifiers" {
    var reader = SliceByteReader{ .data = "1;5A" };
    var sink = NullSink{};
    const event = try parseCSISequence(&reader, &sink);
    try std.testing.expectEqual(@as(EventType, .key), std.meta.activeTag(event));

    const key_event = event.key;
    try std.testing.expectEqual(@as(u21, KeyCode.UP), key_event.key);
    try std.testing.expect(key_event.modifiers.ctrl);
    try std.testing.expect(!key_event.modifiers.alt);
    try std.testing.expect(!key_event.modifiers.shift);
}

test "parse CSI shift tab" {
    var reader = SliceByteReader{ .data = "Z" };
    var sink = NullSink{};
    const event = try parseCSISequence(&reader, &sink);
    try std.testing.expectEqual(@as(EventType, .key), std.meta.activeTag(event));

    const key_event = event.key;
    try std.testing.expectEqual(@as(u21, KeyCode.TAB), key_event.key);
    try std.testing.expect(key_event.modifiers.shift);
}

test "oversized CSI numeric params are unknown instead of trapping" {
    const parsed = try decodeEventFromBytes("\x1b[999999999999999999999999999999999999A");
    try std.testing.expect(parsed != null);
    try std.testing.expectEqual(@as(EventType, .unknown), std.meta.activeTag(parsed.?));
}

test "parse mouse scroll delta" {
    var reader = SliceByteReader{ .data = "<64;10;5M" };
    var sink = NullSink{};
    const event = try parseCSISequence(&reader, &sink);
    try std.testing.expectEqual(@as(EventType, .mouse), std.meta.activeTag(event));

    const mouse_event = event.mouse;
    try std.testing.expectEqual(MouseAction.scroll_up, mouse_event.action);
    try std.testing.expectEqual(@as(i16, -1), mouse_event.scroll_delta);
    try std.testing.expectEqual(@as(u16, 9), mouse_event.x);
    try std.testing.expectEqual(@as(u16, 4), mouse_event.y);
}

test "parse SGR mouse release preserves button" {
    var reader = SliceByteReader{ .data = "<0;4;7m" };
    var sink = NullSink{};
    const event = try parseCSISequence(&reader, &sink);
    try std.testing.expectEqual(@as(EventType, .mouse), std.meta.activeTag(event));

    const mouse_event = event.mouse;
    try std.testing.expectEqual(MouseAction.release, mouse_event.action);
    try std.testing.expectEqual(@as(u8, 1), mouse_event.button);
    try std.testing.expectEqual(@as(u16, 3), mouse_event.x);
    try std.testing.expectEqual(@as(u16, 6), mouse_event.y);
}

test "parse SGR mouse coordinates are zero based for widgets" {
    var reader = SliceByteReader{ .data = "<0;1;1M" };
    var sink = NullSink{};
    const event = try parseCSISequence(&reader, &sink);
    try std.testing.expectEqual(@as(EventType, .mouse), std.meta.activeTag(event));

    const mouse_event = event.mouse;
    try std.testing.expectEqual(MouseAction.press, mouse_event.action);
    try std.testing.expectEqual(@as(u16, 0), mouse_event.x);
    try std.testing.expectEqual(@as(u16, 0), mouse_event.y);
}

test "MouseEvent terminal constructor normalizes protocol coordinates" {
    const event = MouseEvent.fromTerminalCoordinates(.press, 1, 1, 1, 0);
    try std.testing.expectEqual(@as(u16, 0), event.x);
    try std.testing.expectEqual(@as(u16, 0), event.y);

    const shifted = MouseEvent.fromTerminalCoordinates(.press, 18, 11, 1, 0);
    try std.testing.expectEqual(@as(u16, 17), shifted.x);
    try std.testing.expectEqual(@as(u16, 10), shifted.y);
}

test "oversized SGR mouse numeric params are unknown instead of trapping" {
    const parsed = try decodeEventFromBytes("\x1b[<0;999999999999999999999999999999;1M");
    try std.testing.expect(parsed != null);
    try std.testing.expectEqual(@as(EventType, .unknown), std.meta.activeTag(parsed.?));
}

test "empty SGR mouse numeric params are unknown" {
    const missing_button = try decodeEventFromBytes("\x1b[<;1;1M");
    try std.testing.expect(missing_button != null);
    try std.testing.expectEqual(@as(EventType, .unknown), std.meta.activeTag(missing_button.?));

    const missing_x = try decodeEventFromBytes("\x1b[<0;;1M");
    try std.testing.expect(missing_x != null);
    try std.testing.expectEqual(@as(EventType, .unknown), std.meta.activeTag(missing_x.?));

    const missing_y = try decodeEventFromBytes("\x1b[<0;1;M");
    try std.testing.expect(missing_y != null);
    try std.testing.expectEqual(@as(EventType, .unknown), std.meta.activeTag(missing_y.?));
}

test "translateMouseCoordinates is idempotent for decoded mouse events" {
    var reader = SliceByteReader{ .data = "<0;1;1M" };
    var sink = NullSink{};
    const event = try parseCSISequence(&reader, &sink);

    var handler: InputHandler = undefined;
    const translated = handler.translateMouseCoordinates(event.mouse.x, event.mouse.y);
    try std.testing.expectEqual(@as(u16, 0), translated.x);
    try std.testing.expectEqual(@as(u16, 0), translated.y);
}

test "translateTerminalMouseCoordinates converts raw terminal coordinates" {
    var handler: InputHandler = undefined;
    const translated = handler.translateTerminalMouseCoordinates(1, 1);
    try std.testing.expectEqual(@as(u16, 0), translated.x);
    try std.testing.expectEqual(@as(u16, 0), translated.y);
}

test "parse legacy mouse press" {
    const seq = [_]u8{ 'M', 32 + 0, 32 + 5, 32 + 3 };
    var reader = SliceByteReader{ .data = seq[0..] };
    var sink = NullSink{};
    const event = try parseCSISequence(&reader, &sink);
    try std.testing.expectEqual(@as(EventType, .mouse), std.meta.activeTag(event));

    const mouse_event = event.mouse;
    try std.testing.expectEqual(MouseAction.press, mouse_event.action);
    try std.testing.expectEqual(@as(u8, 1), mouse_event.button);
    try std.testing.expectEqual(@as(u16, 4), mouse_event.x);
    try std.testing.expectEqual(@as(u16, 2), mouse_event.y);
}

test "parse legacy mouse coordinates are zero based at origin" {
    const seq = [_]u8{ 'M', 32 + 0, 32 + 1, 32 + 1 };
    var reader = SliceByteReader{ .data = seq[0..] };
    var sink = NullSink{};
    const event = try parseCSISequence(&reader, &sink);
    try std.testing.expectEqual(@as(EventType, .mouse), std.meta.activeTag(event));

    const mouse_event = event.mouse;
    try std.testing.expectEqual(MouseAction.press, mouse_event.action);
    try std.testing.expectEqual(@as(u16, 0), mouse_event.x);
    try std.testing.expectEqual(@as(u16, 0), mouse_event.y);
}

test "malformed legacy mouse bytes are unknown instead of trapping" {
    const bad = [_]u8{ 0x1b, '[', 'M', 0, 0, 0 };
    const parsed = try decodeEventFromBytes(bad[0..]);
    try std.testing.expect(parsed != null);
    try std.testing.expectEqual(@as(EventType, .unknown), std.meta.activeTag(parsed.?));
}

test "fuzz decodeEventFromBytes handles noisy escape sequences" {
    var prng = std.Random.DefaultPrng.init(0xfeed_beef);
    const rand = prng.random();

    for (0..200) |_| {
        var buf: [32]u8 = undefined;
        const len = rand.intRangeAtMost(usize, 0, buf.len);

        for (buf[0..len], 0..) |*b, idx| {
            _ = idx;
            const choice = rand.intRangeAtMost(u8, 0, 6);
            b.* = switch (choice) {
                0 => '[',
                1 => ';',
                2 => '<',
                3 => 0x1b,
                4 => 'M',
                5 => 'Z',
                else => rand.intRangeAtMost(u8, 1, 126),
            };
        }

        const event = try decodeEventFromBytes(buf[0..len]);
        if (len == 0) {
            try std.testing.expect(event == null);
        } else {
            try std.testing.expect(event != null);
        }
    }
}

test "invalid csi input is treated as unknown event" {
    const bad = "\x1b[999;999;abc";
    const parsed = try decodeEventFromBytes(bad);
    try std.testing.expect(parsed != null);
    try std.testing.expectEqual(@as(EventType, .unknown), std.meta.activeTag(parsed.?));
}

test "decodeEventFromBytes decodes UTF-8 key input" {
    const parsed = try decodeEventFromBytes("é");
    try std.testing.expect(parsed != null);
    try std.testing.expectEqual(@as(EventType, .key), std.meta.activeTag(parsed.?));
    try std.testing.expectEqual(@as(u21, 0x00E9), parsed.?.key.key);
    try std.testing.expect(parsed.?.key.isTextInput());
    try std.testing.expect(!parsed.?.key.isPrintable());
}

test "key event text input names encode UTF-8" {
    const alloc = std.testing.allocator;
    const event = KeyEvent.init(0x03BB, .{});
    try std.testing.expect(event.isTextInput());
    const name = try event.getName(alloc);
    defer alloc.free(name);
    try std.testing.expectEqualStrings("λ", name);

    try std.testing.expect(!KeyEvent.init(KeyCode.UP, .{}).isTextInput());
}

test "key names are allocator-owned for special keys" {
    const alloc = std.testing.allocator;
    const event = KeyEvent.init(KeyCode.UP, .{});
    const name = try event.getName(alloc);
    defer alloc.free(name);

    try std.testing.expectEqualStrings("Up", name);

    const chord = KeyChord.init(
        KeyEvent.init(KeyCode.UP, .{ .ctrl = true }),
        KeyEvent.init(KeyCode.F1, .{}),
    );
    const rendered = try chord.toString(alloc);
    defer alloc.free(rendered);
    try std.testing.expectEqualStrings("Ctrl+Up → F1", rendered);
}

test "resize polling throttle handles first poll interval and clock movement" {
    try std.testing.expect(shouldPollResize(0, 1000, 125));
    try std.testing.expect(shouldPollResize(1000, 1000, 0));
    try std.testing.expect(!shouldPollResize(1000, 1100, 125));
    try std.testing.expect(shouldPollResize(1000, 1125, 125));
    try std.testing.expect(shouldPollResize(1000, 900, 125));
}
