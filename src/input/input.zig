const std = @import("std");
const zit = @import("zit");
const terminal = @import("../terminal/terminal.zig");

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
    
    /// Get a string representation of the key
    pub fn getName(self: KeyEvent, allocator: std.mem.Allocator) ![]const u8 {
        if (self.isPrintable()) {
            var char_buf: [1]u8 = .{@intCast(self.key)};
            return try allocator.dupe(u8, &char_buf);
        }
        
        return switch (self.key) {
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
    }
    
    /// Check if two key events are equal
    pub fn equals(self: KeyEvent, other: KeyEvent) bool {
        return self.key == other.key and
               self.modifiers.ctrl == other.modifiers.ctrl and
               self.modifiers.alt == other.modifiers.alt and
               self.modifiers.shift == other.modifiers.shift;
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
        var parts = std.ArrayList(u8).init(allocator);
        defer parts.deinit();
        
        if (self.ctrl) {
            try parts.appendSlice("Ctrl+");
        }
        
        if (self.alt) {
            try parts.appendSlice("Alt+");
        }
        
        if (self.shift) {
            try parts.appendSlice("Shift+");
        }
        
        return try parts.toOwnedSlice();
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
    
    /// Create a new mouse event
    pub fn init(action: MouseAction, x: u16, y: u16, button: u8) MouseEvent {
        return MouseEvent{
            .action = action,
            .x = x,
            .y = y,
            .button = button,
        };
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
        
        return try std.fmt.allocPrint(allocator, "{s}{s} → {s}{s}", 
            .{ first_mod, first_name, second_mod, second_name });
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
            .elements = std.ArrayList(*Focusable).init(allocator),
            .current_focus = null,
        };
    }
    
    /// Clean up resources
    pub fn deinit(self: *FocusManager) void {
        self.elements.deinit();
    }
    
    /// Add a focusable element
    pub fn addElement(self: *FocusManager, element: *Focusable) !void {
        try self.elements.append(element);
        
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
        if (key.key == KeyCode.TAB) {
            const direction: FocusDirection = if (key.modifiers.shift) .previous else .next;
            return self.moveFocus(direction);
        }
        
        // If nothing is focused, nothing to do
        if (self.current_focus == null) return false;
        
        // Send the key event to the focused element
        return self.elements.items[self.current_focus.?].onKeyEvent(key);
    }
    
    /// Get the currently focused element, if any
    pub fn getFocusedElement(self: *FocusManager) ?*Focusable {
        if (self.current_focus == null) return null;
        return self.elements.items[self.current_focus.?];
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
        };
    }
    
    /// Enable mouse tracking
    pub fn enableMouse(self: *InputHandler) !void {
        if (self.mouse_enabled) return;
        
        const writer = std.io.getStdOut().writer();
        try writer.writeAll("\x1b[?1000h"); // Enable mouse clicks
        try writer.writeAll("\x1b[?1002h"); // Enable mouse movement
        try writer.writeAll("\x1b[?1006h"); // Enable SGR extended mode
        self.mouse_enabled = true;
    }
    
    /// Disable mouse tracking
    pub fn disableMouse(self: *InputHandler) !void {
        if (!self.mouse_enabled) return;
        
        const writer = std.io.getStdOut().writer();
        try writer.writeAll("\x1b[?1006l"); // Disable SGR extended mode
        try writer.writeAll("\x1b[?1002l"); // Disable mouse movement
        try writer.writeAll("\x1b[?1000l"); // Disable mouse clicks
        self.mouse_enabled = false;
    }
    
    /// Read an event from input
    pub fn readEvent(self: *InputHandler) !Event {
        // On macOS, we need to use a different approach for robust input handling
        if (@import("builtin").os.tag == .macos) {
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
            const amount = std.posix.read(
                self.term.stdin_fd,
                buffer[0..1]
            ) catch {
                return error.WouldBlock;
            };
            
            if (amount == 0) {
                return error.WouldBlock;
            }
            
            // Reset buffer position first
            self.buffer_pos = 0;
            
            // Store the byte in the buffer
            self.buffer[self.buffer_pos] = buffer[0];
            self.buffer_pos += 1;
            
            // Check for escape sequence
            if (buffer[0] == 0x1b) {
                return try self.parseEscapeSequence();
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
            
            // Regular key press
            return Event{
                .key = KeyEvent{
                    .key = buffer[0],
                    .modifiers = KeyModifiers{},
                },
            };
        } else {
            // For all other platforms, use the standard implementation
            const stdin = std.io.getStdIn();
            const reader = stdin.reader();
            
            // Reset buffer position
            self.buffer_pos = 0;
            
            // Read a single byte
            const byte = reader.readByte() catch |err| {
                // Handle all possible non-blocking errors consistently
                if (err == error.WouldBlock or err == error.Again or 
                    err == error.InputOutput or err == error.NotOpenForReading) {
                    return error.WouldBlock;  // Normalize all non-blocking errors
                }
                return err;
            };
            
            // Store the byte in the buffer
            self.buffer[self.buffer_pos] = byte;
            self.buffer_pos += 1;
            
            // Check for escape sequence
            if (byte == 0x1b) {
                return try self.parseEscapeSequence();
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
            
            // Regular key press
            return Event{
                .key = KeyEvent{
                    .key = byte,
                    .modifiers = KeyModifiers{},
                },
            };
        }
    }
    
    /// Parse an escape sequence
    fn parseEscapeSequence(self: *InputHandler) !Event {
        // On macOS, use a specialized approach
        if (@import("builtin").os.tag == .macos) {
            // Try to read the next byte with a very small delay
            var buffer: [1]u8 = undefined;
            var poll_fds = [_]std.posix.pollfd{
                .{
                    .fd = self.term.stdin_fd,
                    .events = std.posix.POLL.IN,
                    .revents = 0,
                },
            };
            
            // Poll with a very short timeout (5ms)
            // This is crucial for detecting solo ESC key presses vs sequences
            const poll_result = std.posix.poll(&poll_fds, 5) catch {
                // If poll fails, it's a simple ESC key
                return Event{
                    .key = KeyEvent{
                        .key = KeyCode.ESCAPE,
                        .modifiers = KeyModifiers{},
                    },
                };
            };
            
            // If no input is available, it's a solo ESC key
            if (poll_result <= 0 or (poll_fds[0].revents & std.posix.POLL.IN) == 0) {
                return Event{
                    .key = KeyEvent{
                        .key = KeyCode.ESCAPE,
                        .modifiers = KeyModifiers{},
                    },
                };
            }
            
            // Read the next byte 
            const amount = std.posix.read(
                self.term.stdin_fd,
                buffer[0..1]
            ) catch {
                // If read fails, it's a simple ESC key
                return Event{
                    .key = KeyEvent{
                        .key = KeyCode.ESCAPE,
                        .modifiers = KeyModifiers{},
                    },
                };
            };
            
            if (amount == 0) {
                // If no data, it's a simple ESC key
                return Event{
                    .key = KeyEvent{
                        .key = KeyCode.ESCAPE,
                        .modifiers = KeyModifiers{},
                    },
                };
            }
            
            // Store the byte in the buffer
            self.buffer[self.buffer_pos] = buffer[0];
            self.buffer_pos += 1;
            
            // Check for CSI sequence (ESC [)
            if (buffer[0] == '[') {
                return try self.parseCSISequence();
            }
            
            // Check for Alt+key combination (ESC followed by a key)
            return Event{
                .key = KeyEvent{
                    .key = buffer[0],
                    .modifiers = KeyModifiers{
                        .alt = true,
                    },
                },
            };
        } else {
            // Standard implementation for other platforms
            const stdin = std.io.getStdIn();
            const reader = stdin.reader();
            
            // Try to read the next byte with special handling for macOS
            const next_byte = reader.readByte() catch |err| {
                if (err == error.WouldBlock or err == error.Again or 
                    err == error.InputOutput) {
                    // If we can't read more, it's just an escape key
                    // This is especially common on macOS
                    return Event{
                        .key = KeyEvent{
                            .key = KeyCode.ESCAPE,
                            .modifiers = KeyModifiers{},
                        },
                    };
                }
                return err;
            };
            
            // Store the byte in the buffer
            self.buffer[self.buffer_pos] = next_byte;
            self.buffer_pos += 1;
            
            // Check for CSI sequence (ESC [)
            if (next_byte == '[') {
                return try self.parseCSISequence();
            }
            
            // Check for Alt+key combination (ESC followed by a key)
            return Event{
                .key = KeyEvent{
                    .key = next_byte,
                    .modifiers = KeyModifiers{
                        .alt = true,
                    },
                },
            };
        }
    }
    
    /// Parse a CSI (Control Sequence Introducer) sequence
    fn parseCSISequence(self: *InputHandler) !Event {
        // On macOS, use direct read for better reliability
        if (@import("builtin").os.tag == .macos) {
            // Read the next byte directly
            var next_byte: [1]u8 = undefined;
            const amount = std.posix.read(self.term.stdin_fd, next_byte[0..1]) catch {
                return Event{ .unknown = {} };
            };
            
            if (amount == 0) {
                return Event{ .unknown = {} };
            }
            
            // Store the byte in the buffer
            self.buffer[self.buffer_pos] = next_byte[0];
            self.buffer_pos += 1;
            
            // Check for mouse events (ESC [ <)
            if (next_byte[0] == '<') {
                return try self.parseMouseEvent();
            }
            
            // Check for arrow keys and other special keys
            switch (next_byte[0]) {
                'A' => return Event{ .key = KeyEvent{ .key = KeyCode.UP, .modifiers = KeyModifiers{} } },
                'B' => return Event{ .key = KeyEvent{ .key = KeyCode.DOWN, .modifiers = KeyModifiers{} } },
                'C' => return Event{ .key = KeyEvent{ .key = KeyCode.RIGHT, .modifiers = KeyModifiers{} } },
                'D' => return Event{ .key = KeyEvent{ .key = KeyCode.LEFT, .modifiers = KeyModifiers{} } },
                'H' => return Event{ .key = KeyEvent{ .key = KeyCode.HOME, .modifiers = KeyModifiers{} } },
                'F' => return Event{ .key = KeyEvent{ .key = KeyCode.END, .modifiers = KeyModifiers{} } },
                '5' => {
                    // Read the next byte (should be ~)
                    var tilde: [1]u8 = undefined;
                    const tilde_amount = std.posix.read(self.term.stdin_fd, tilde[0..1]) catch {
                        return Event{ .unknown = {} };
                    };
                    
                    if (tilde_amount == 0) {
                        return Event{ .unknown = {} };
                    }
                    
                    if (tilde[0] == '~') {
                        return Event{ .key = KeyEvent{ .key = KeyCode.PAGE_UP, .modifiers = KeyModifiers{} } };
                    }
                },
                '6' => {
                    // Read the next byte (should be ~)
                    var tilde: [1]u8 = undefined;
                    const tilde_amount = std.posix.read(self.term.stdin_fd, tilde[0..1]) catch {
                        return Event{ .unknown = {} };
                    };
                    
                    if (tilde_amount == 0) {
                        return Event{ .unknown = {} };
                    }
                    
                    if (tilde[0] == '~') {
                        return Event{ .key = KeyEvent{ .key = KeyCode.PAGE_DOWN, .modifiers = KeyModifiers{} } };
                    }
                },
                '2' => {
                    // Read the next byte (should be ~)
                    var tilde: [1]u8 = undefined;
                    const tilde_amount = std.posix.read(self.term.stdin_fd, tilde[0..1]) catch {
                        return Event{ .unknown = {} };
                    };
                    
                    if (tilde_amount == 0) {
                        return Event{ .unknown = {} };
                    }
                    
                    if (tilde[0] == '~') {
                        return Event{ .key = KeyEvent{ .key = KeyCode.INSERT, .modifiers = KeyModifiers{} } };
                    }
                },
                '3' => {
                    // Read the next byte (should be ~)
                    var tilde: [1]u8 = undefined;
                    const tilde_amount = std.posix.read(self.term.stdin_fd, tilde[0..1]) catch {
                        return Event{ .unknown = {} };
                    };
                    
                    if (tilde_amount == 0) {
                        return Event{ .unknown = {} };
                    }
                    
                    if (tilde[0] == '~') {
                        return Event{ .key = KeyEvent{ .key = KeyCode.DELETE, .modifiers = KeyModifiers{} } };
                    }
                },
                else => {},
            }
            
            // Unknown escape sequence
            return Event{ .unknown = {} };
        } else {
            // Original implementation for other platforms
            const stdin = std.io.getStdIn();
            const reader = stdin.reader();
            
            // Read the next byte
            const next_byte = reader.readByte() catch |err| {
                if (err == error.WouldBlock) {
                    return Event{ .unknown = {} };
                }
                return err;
            };
            
            // Store the byte in the buffer
            self.buffer[self.buffer_pos] = next_byte;
            self.buffer_pos += 1;
            
            // Check for mouse events (ESC [ <)
            if (next_byte == '<') {
                return try self.parseMouseEvent();
            }
            
            // Check for arrow keys and other special keys
            switch (next_byte) {
                'A' => return Event{ .key = KeyEvent{ .key = KeyCode.UP, .modifiers = KeyModifiers{} } },
                'B' => return Event{ .key = KeyEvent{ .key = KeyCode.DOWN, .modifiers = KeyModifiers{} } },
                'C' => return Event{ .key = KeyEvent{ .key = KeyCode.RIGHT, .modifiers = KeyModifiers{} } },
                'D' => return Event{ .key = KeyEvent{ .key = KeyCode.LEFT, .modifiers = KeyModifiers{} } },
                'H' => return Event{ .key = KeyEvent{ .key = KeyCode.HOME, .modifiers = KeyModifiers{} } },
                'F' => return Event{ .key = KeyEvent{ .key = KeyCode.END, .modifiers = KeyModifiers{} } },
                '5' => {
                    // Read the next byte (should be ~)
                    const tilde = reader.readByte() catch |err| {
                        if (err == error.WouldBlock) {
                            return Event{ .unknown = {} };
                        }
                        return err;
                    };
                    
                    if (tilde == '~') {
                        return Event{ .key = KeyEvent{ .key = KeyCode.PAGE_UP, .modifiers = KeyModifiers{} } };
                    }
                },
                '6' => {
                    // Read the next byte (should be ~)
                    const tilde = reader.readByte() catch |err| {
                        if (err == error.WouldBlock) {
                            return Event{ .unknown = {} };
                        }
                        return err;
                    };
                    
                    if (tilde == '~') {
                        return Event{ .key = KeyEvent{ .key = KeyCode.PAGE_DOWN, .modifiers = KeyModifiers{} } };
                    }
                },
                '2' => {
                    // Read the next byte (should be ~)
                    const tilde = reader.readByte() catch |err| {
                        if (err == error.WouldBlock) {
                            return Event{ .unknown = {} };
                        }
                        return err;
                    };
                    
                    if (tilde == '~') {
                        return Event{ .key = KeyEvent{ .key = KeyCode.INSERT, .modifiers = KeyModifiers{} } };
                    }
                },
                '3' => {
                    // Read the next byte (should be ~)
                    const tilde = reader.readByte() catch |err| {
                        if (err == error.WouldBlock) {
                            return Event{ .unknown = {} };
                        }
                        return err;
                    };
                    
                    if (tilde == '~') {
                        return Event{ .key = KeyEvent{ .key = KeyCode.DELETE, .modifiers = KeyModifiers{} } };
                    }
                },
                else => {},
            }
            
            // Check for function keys
            if (next_byte >= '0' and next_byte <= '9') {
                var num_str: [3]u8 = undefined;
                num_str[0] = next_byte;
                var num_len: usize = 1;
                
                // Read until we get a non-digit or ~
                while (num_len < 3) {
                    const digit = reader.readByte() catch |err| {
                        if (err == error.WouldBlock) {
                            break;
                        }
                        return err;
                    };
                    
                    if (digit == '~') {
                        // Parse the number
                        const num = try std.fmt.parseInt(u8, num_str[0..num_len], 10);
                        
                        // Map to function keys
                        return switch (num) {
                            11 => Event{ .key = KeyEvent{ .key = KeyCode.F1, .modifiers = KeyModifiers{} } },
                            12 => Event{ .key = KeyEvent{ .key = KeyCode.F2, .modifiers = KeyModifiers{} } },
                            13 => Event{ .key = KeyEvent{ .key = KeyCode.F3, .modifiers = KeyModifiers{} } },
                            14 => Event{ .key = KeyEvent{ .key = KeyCode.F4, .modifiers = KeyModifiers{} } },
                            15 => Event{ .key = KeyEvent{ .key = KeyCode.F5, .modifiers = KeyModifiers{} } },
                            17 => Event{ .key = KeyEvent{ .key = KeyCode.F6, .modifiers = KeyModifiers{} } },
                            18 => Event{ .key = KeyEvent{ .key = KeyCode.F7, .modifiers = KeyModifiers{} } },
                            19 => Event{ .key = KeyEvent{ .key = KeyCode.F8, .modifiers = KeyModifiers{} } },
                            20 => Event{ .key = KeyEvent{ .key = KeyCode.F9, .modifiers = KeyModifiers{} } },
                            21 => Event{ .key = KeyEvent{ .key = KeyCode.F10, .modifiers = KeyModifiers{} } },
                            23 => Event{ .key = KeyEvent{ .key = KeyCode.F11, .modifiers = KeyModifiers{} } },
                            24 => Event{ .key = KeyEvent{ .key = KeyCode.F12, .modifiers = KeyModifiers{} } },
                            else => Event{ .unknown = {} },
                        };
                    } else if (digit >= '0' and digit <= '9') {
                        num_str[num_len] = digit;
                        num_len += 1;
                    } else {
                        break;
                    }
                }
            }
            
            // Unknown escape sequence
            return Event{ .unknown = {} };
        }
    }
    
    /// Parse a mouse event
    fn parseMouseEvent(_: *InputHandler) !Event {
        const stdin = std.io.getStdIn();
        const reader = stdin.reader();
        
        // Mouse events in SGR mode are of the form: ESC [ < Cb ; Cx ; Cy ; M/m
        // Where:
        // - Cb is the button number + modifiers
        // - Cx is the X coordinate (1-based)
        // - Cy is the Y coordinate (1-based)
        // - M indicates button press, m indicates button release
        
        var params: [3]u16 = undefined;
        var param_index: usize = 0;
        var param_value: u16 = 0;
        var final_char: u8 = 0;
        
        // Parse parameters
        while (param_index < 3) {
            const c = reader.readByte() catch |err| {
                if (err == error.WouldBlock) {
                    return Event{ .unknown = {} };
                }
                return err;
            };
            
            if (c >= '0' and c <= '9') {
                // Append digit to parameter value
                param_value = param_value * 10 + (c - '0');
            } else if (c == ';') {
                // End of parameter
                params[param_index] = param_value;
                param_index += 1;
                param_value = 0;
            } else if (c == 'M' or c == 'm') {
                // End of mouse sequence
                params[param_index] = param_value;
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
        
        // Extract the button, x and y values
        const button_param = params[0];
        const x = params[1];
        const y = params[2];
        
        // Decode the button parameter
        const button = @as(u8, @intCast(button_param & 0x3));
        const is_motion = (button_param & 0x20) != 0;
        const is_scroll = (button_param & 0x40) != 0 or (button_param & 0x80) != 0;
        
        // Determine the action based on the final character and flags
        var action: MouseAction = undefined;
        if (is_scroll) {
            action = if ((button_param & 0x1) != 0) MouseAction.scroll_down else MouseAction.scroll_up;
        } else if (is_motion) {
            action = MouseAction.move;
        } else if (final_char == 'M') {
            action = MouseAction.press;
        } else {
            action = MouseAction.release;
        }
        
        return Event{
            .mouse = MouseEvent{
                .action = action,
                .x = x,
                .y = y,
                .button = button + 1, // Button is 1-indexed
            },
        };
    }
    
    /// Poll for an event with timeout
    pub fn pollEvent(self: *InputHandler, timeout_ms: u64) !?Event {
        if (@import("builtin").os.tag == .macos) {
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
                return null;
            }
            
            // Try to read an event - being careful with error handling
            return self.readEvent() catch |err| {
                if (err == error.WouldBlock) {
                    // This can happen if the terminal state changes between poll and read
                    std.time.sleep(std.time.ns_per_ms); // Small pause
                    return null;
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
                return null;
            }

            // Try to read an event
            return self.readEvent() catch |err| {
                if (err == error.WouldBlock) {
                    return null;
                }
                return err;
            };
        }
    }
    
    /// Process input events and integrate with the event system
    pub fn processEvents(self: *InputHandler, event_processor: *fn(Event) anyerror!void) !void {
        // Poll for events with a small timeout
        const event = try self.pollEvent(10);
        
        if (event) |e| {
            try event_processor(e);
        }
    }
    
    /// Convert mouse coordinates to screen coordinates
    pub fn translateMouseCoordinates(_: *InputHandler, x: u16, y: u16) struct { x: u16, y: u16 } {
        // In a TUI application, mouse coordinates are usually 1-indexed
        // This converts them to 0-indexed for internal use
        const adjusted_x = if (x > 0) x - 1 else 0;
        const adjusted_y = if (y > 0) y - 1 else 0;
        
        return .{ .x = adjusted_x, .y = adjusted_y };
    }
};