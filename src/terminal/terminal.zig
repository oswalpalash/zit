const std = @import("std");
const builtin = @import("builtin");
const capabilities = @import("capabilities.zig");
const compat = @import("../compat.zig");

const windows_console = struct {
    const SmallRect = extern struct {
        Left: i16,
        Top: i16,
        Right: i16,
        Bottom: i16,
    };

    const ScreenBufferInfo = extern struct {
        dwSize: std.os.windows.COORD,
        dwCursorPosition: std.os.windows.COORD,
        wAttributes: std.os.windows.WORD,
        srWindow: SmallRect,
        dwMaximumWindowSize: std.os.windows.COORD,
    };

    const ENABLE_PROCESSED_INPUT: u32 = 0x0001;
    const ENABLE_LINE_INPUT: u32 = 0x0002;
    const ENABLE_ECHO_INPUT: u32 = 0x0004;
    const ENABLE_INSERT_MODE: u32 = 0x0020;
    const ENABLE_QUICK_EDIT_MODE: u32 = 0x0040;
    const ENABLE_EXTENDED_FLAGS: u32 = 0x0080;
    const ENABLE_VIRTUAL_TERMINAL_INPUT: u32 = 0x0200;

    const ENABLE_PROCESSED_OUTPUT: u32 = 0x0001;
    const ENABLE_WRAP_AT_EOL_OUTPUT: u32 = 0x0002;
    const ENABLE_VIRTUAL_TERMINAL_PROCESSING: u32 = 0x0004;

    extern "kernel32" fn GetConsoleMode(hConsoleHandle: std.os.windows.HANDLE, lpMode: *std.os.windows.DWORD) std.os.windows.BOOL;
    extern "kernel32" fn SetConsoleMode(hConsoleHandle: std.os.windows.HANDLE, dwMode: std.os.windows.DWORD) std.os.windows.BOOL;
    extern "kernel32" fn SetConsoleOutputCP(wCodePageID: c_uint) std.os.windows.BOOL;
    extern "kernel32" fn GetConsoleScreenBufferInfo(hConsoleOutput: std.os.windows.HANDLE, lpConsoleScreenBufferInfo: *ScreenBufferInfo) std.os.windows.BOOL;
    extern "kernel32" fn FillConsoleOutputCharacterW(hConsoleOutput: std.os.windows.HANDLE, cCharacter: std.os.windows.WCHAR, nLength: std.os.windows.DWORD, dwWriteCoord: std.os.windows.COORD, lpNumberOfCharsWritten: *std.os.windows.DWORD) std.os.windows.BOOL;
    extern "kernel32" fn FillConsoleOutputAttribute(hConsoleOutput: std.os.windows.HANDLE, wAttribute: std.os.windows.WORD, nLength: std.os.windows.DWORD, dwWriteCoord: std.os.windows.COORD, lpNumberOfAttrsWritten: *std.os.windows.DWORD) std.os.windows.BOOL;
    extern "kernel32" fn SetConsoleCursorPosition(hConsoleOutput: std.os.windows.HANDLE, dwCursorPosition: std.os.windows.COORD) std.os.windows.BOOL;
    extern "kernel32" fn SetConsoleTextAttribute(hConsoleOutput: std.os.windows.HANDLE, wAttributes: std.os.windows.WORD) std.os.windows.BOOL;
};

const windows_cursor = struct {
    const Info = extern struct {
        dwSize: u32,
        bVisible: std.os.windows.BOOL,
    };

    extern "kernel32" fn GetConsoleCursorInfo(hConsoleOutput: std.os.windows.HANDLE, lpConsoleCursorInfo: *Info) std.os.windows.BOOL;
    extern "kernel32" fn SetConsoleCursorInfo(hConsoleOutput: std.os.windows.HANDLE, lpConsoleCursorInfo: *const Info) std.os.windows.BOOL;
};

var winch_signal_flag = std.atomic.Value(u8).init(0);

fn handleSigwinch(_: std.posix.SIG) callconv(.c) void {
    winch_signal_flag.store(1, .monotonic);
}

fn setNonBlocking(fd: std.posix.fd_t) !void {
    switch (builtin.os.tag) {
        .linux => {
            const flags_rc = std.os.linux.fcntl(fd, std.os.linux.F.GETFL, 0);
            if (std.os.linux.errno(flags_rc) != .SUCCESS) return error.FcntlFailure;
            const O_NONBLOCK: usize = 0o4000;
            const set_rc = std.os.linux.fcntl(fd, std.os.linux.F.SETFL, flags_rc | O_NONBLOCK);
            if (std.os.linux.errno(set_rc) != .SUCCESS) return error.FcntlFailure;
        },
        .windows => {},
        else => {
            if (!builtin.link_libc) return;
            const flags = std.c.fcntl(fd, std.c.F.GETFL, @as(c_int, 0));
            if (flags < 0) return error.FcntlFailure;
            const O_NONBLOCK: c_int = 0x00000004;
            if (std.c.fcntl(fd, std.c.F.SETFL, flags | O_NONBLOCK) < 0) return error.FcntlFailure;
        },
    }
}

pub const Size = struct {
    width: u16,
    height: u16,
};

fn changedSize(old_width: u16, old_height: u16, new_width: u16, new_height: u16) ?Size {
    if (old_width == new_width and old_height == new_height) return null;
    return .{ .width = new_width, .height = new_height };
}

/// Terminal abstraction layer
///
/// This module provides cross-platform terminal handling capabilities including:
/// - Raw mode activation/deactivation
/// - Terminal geometry detection
/// - Cursor control
/// - Terminal capabilities detection
/// - Mouse event handling
/// - Unicode support
/// - RGB color support
pub const Terminal = struct {
    /// Standard input file descriptor
    stdin_fd: std.posix.fd_t,
    /// Standard output file descriptor
    stdout_fd: std.posix.fd_t,
    /// Original terminal attributes (for restoring on exit)
    original_termios: OriginalTermAttrs,
    /// Current terminal width in columns
    width: u16,
    /// Current terminal height in rows
    height: u16,
    /// Whether the terminal is in raw mode
    is_raw_mode: bool,
    /// Whether the cursor is visible
    is_cursor_visible: bool,
    /// Whether mouse events are enabled
    is_mouse_enabled: bool,
    /// Allocator for terminal operations
    allocator: std.mem.Allocator,
    /// Detected terminal capabilities
    capabilities: capabilities.CapabilityFlags,
    /// Whether synchronized output mode (DEC 2026) is active
    is_sync_output: bool,
    /// Whether the terminal is using the alternate screen buffer
    is_alt_screen: bool,
    /// Whether bracketed paste mode is active
    is_bracketed_paste: bool,
    /// Whether Windows virtual terminal processing is available
    windows_vt_enabled: bool,

    // Cross-platform terminal attribute storage
    const OriginalTermAttrs = union(enum) {
        unix: std.posix.termios,
        windows: WindowsConsoleInfo,
        none: void,
    };

    const WindowsConsoleInfo = struct {
        in_mode: u32,
        out_mode: u32,
    };

    /// Initialize a new terminal instance
    pub fn init(allocator: std.mem.Allocator) !Terminal {
        const stdin_fd = std.Io.File.stdin().handle;
        const stdout_fd = std.Io.File.stdout().handle;

        var original_termios: OriginalTermAttrs = .none;
        const is_windows = builtin.os.tag == .windows;
        var windows_vt_enabled = true;

        if (is_windows) {
            ensureWindowsUnicodeSupport();
            var in_mode: std.os.windows.DWORD = undefined;
            var out_mode: std.os.windows.DWORD = undefined;
            if (windows_console.GetConsoleMode(stdin_fd, &in_mode).toBool() and
                windows_console.GetConsoleMode(stdout_fd, &out_mode).toBool())
            {
                original_termios = .{ .windows = .{ .in_mode = in_mode, .out_mode = out_mode } };
                windows_vt_enabled = enableWindowsVirtualTerminal(stdout_fd);
            } else {
                windows_vt_enabled = false;
            }
        } else {
            // Unix systems
            switch (builtin.os.tag) {
                .macos, .ios, .tvos, .watchos, .visionos => {
                    if (std.posix.system.isatty(stdin_fd) == 0 or std.posix.system.isatty(stdout_fd) == 0) {
                        return error.NotATerminal;
                    }
                },
                else => {},
            }
            original_termios = .{ .unix = try std.posix.tcgetattr(stdin_fd) };
        }

        var self = Terminal{
            .stdin_fd = stdin_fd,
            .stdout_fd = stdout_fd,
            .original_termios = original_termios,
            .width = 80, // Default values
            .height = 24,
            .is_raw_mode = false,
            .is_cursor_visible = true,
            .is_mouse_enabled = false,
            .allocator = allocator,
            .capabilities = capabilities.detectWithAllocator(allocator),
            .is_sync_output = false,
            .is_alt_screen = false,
            .is_bracketed_paste = false,
            .windows_vt_enabled = windows_vt_enabled,
        };

        if (is_windows and !windows_vt_enabled) {
            self.capabilities = downgradeWindowsCapabilities(self.capabilities);
        }

        try self.updateSize();

        // Set up SIGWINCH handling on Unix platforms
        if (@import("builtin").os.tag != .windows) {
            const SIG = std.posix.SIG;
            _ = std.posix.sigaction(SIG.WINCH, &std.posix.Sigaction{
                .handler = .{ .handler = handleSigwinch },
                .mask = std.posix.sigemptyset(),
                .flags = std.posix.SA.RESTART,
            }, null);
        }

        return self;
    }

    /// Clean up terminal resources and restore original state
    pub fn deinit(self: *Terminal) !void {
        if (self.is_raw_mode) {
            try self.disableRawMode();
        }

        if (!self.is_cursor_visible) {
            try self.showCursor();
        }

        if (self.is_mouse_enabled) {
            try self.disableMouseEvents();
        }

        if (self.is_sync_output) {
            try self.endSynchronizedOutput();
        }

        if (self.is_alt_screen) {
            try self.exitAlternateScreen();
        }

        if (self.is_bracketed_paste) {
            try self.disableBracketedPaste();
        }

        // Reset all formatting before exit
        try self.resetFormatting();
    }

    /// Enable raw mode for direct character input
    pub fn enableRawMode(self: *Terminal) !void {
        if (self.is_raw_mode) return;

        const is_windows = builtin.os.tag == .windows;

        if (is_windows) {
            switch (self.original_termios) {
                .windows => |info| {
                    // Strip line editing/echo while keeping extended flags so the console API is responsive.
                    const sanitized_in_mode: u32 = (info.in_mode | windows_console.ENABLE_EXTENDED_FLAGS) &
                        ~(windows_console.ENABLE_ECHO_INPUT |
                            windows_console.ENABLE_LINE_INPUT |
                            windows_console.ENABLE_PROCESSED_INPUT |
                            windows_console.ENABLE_QUICK_EDIT_MODE |
                            windows_console.ENABLE_INSERT_MODE);

                    const vt_input_mode = sanitized_in_mode | windows_console.ENABLE_VIRTUAL_TERMINAL_INPUT;
                    if (!windows_console.SetConsoleMode(self.stdin_fd, vt_input_mode).toBool()) {
                        if (!windows_console.SetConsoleMode(self.stdin_fd, sanitized_in_mode).toBool()) {
                            return error.SetConsoleModeFailure;
                        }
                    }

                    // Try to enable VT processing but gracefully fall back to console attributes when unavailable.
                    const base_out_mode: u32 = info.out_mode | windows_console.ENABLE_PROCESSED_OUTPUT | windows_console.ENABLE_WRAP_AT_EOL_OUTPUT;
                    if (windows_console.SetConsoleMode(self.stdout_fd, base_out_mode | windows_console.ENABLE_VIRTUAL_TERMINAL_PROCESSING).toBool()) {
                        self.windows_vt_enabled = true;
                    } else {
                        self.windows_vt_enabled = false;
                        if (!windows_console.SetConsoleMode(self.stdout_fd, base_out_mode).toBool()) {
                            _ = windows_console.SetConsoleMode(self.stdin_fd, info.in_mode);
                            return error.SetConsoleModeFailure;
                        }
                        self.capabilities = downgradeWindowsCapabilities(self.capabilities);
                    }
                },
                else => {}, // Do nothing for .none
            }
        } else {
            // Unix systems
            switch (self.original_termios) {
                .unix => |orig| {
                    var raw = orig;

                    raw.lflag.ECHO = false;
                    raw.lflag.ICANON = false;
                    raw.lflag.IEXTEN = false;

                    raw.iflag.IXON = false;
                    raw.iflag.ICRNL = false;
                    raw.iflag.BRKINT = false;
                    raw.iflag.INPCK = false;
                    raw.iflag.ISTRIP = false;

                    raw.oflag.OPOST = false;
                    raw.cflag.CSIZE = .CS8;

                    // Set read timeout and minimum input to 0 for non-blocking reads
                    const v_time: usize = @intFromEnum(std.posix.V.TIME);
                    const v_min: usize = @intFromEnum(std.posix.V.MIN);

                    raw.cc[v_time] = 0; // No timeout, return immediately
                    raw.cc[v_min] = 0; // Return even if no characters are available

                    // Apply settings
                    try std.posix.tcsetattr(self.stdin_fd, .FLUSH, raw);
                },
                else => {}, // Do nothing for .none
            }
        }

        // Set stdin to non-blocking mode for non-macOS Unix
        if (@import("builtin").os.tag != .windows and @import("builtin").os.tag != .macos) {
            try setNonBlocking(self.stdin_fd);
        }

        // Try to enable the Kitty keyboard protocol for better key handling
        if (self.capabilities.kitty_keyboard) {
            self.enableKittyKeyboardProtocol() catch {};
        }

        self.is_raw_mode = true;
    }

    /// Disable raw mode and restore original terminal settings
    pub fn disableRawMode(self: *Terminal) !void {
        if (!self.is_raw_mode) return;

        // Disable the Kitty keyboard protocol first
        if (self.capabilities.kitty_keyboard) {
            self.disableKittyKeyboardProtocol() catch {};
        }

        const is_windows = builtin.os.tag == .windows;

        if (is_windows) {
            switch (self.original_termios) {
                .windows => |info| {
                    // Restore original console modes
                    if (!windows_console.SetConsoleMode(self.stdin_fd, info.in_mode).toBool()) {
                        return error.SetConsoleModeFailure;
                    }

                    if (!windows_console.SetConsoleMode(self.stdout_fd, info.out_mode).toBool()) {
                        return error.SetConsoleModeFailure;
                    }

                    self.windows_vt_enabled = detectWindowsVirtualTerminal(self.stdout_fd);
                    if (!self.windows_vt_enabled) {
                        self.capabilities = downgradeWindowsCapabilities(self.capabilities);
                    }
                },
                else => {}, // Do nothing for .none
            }
        } else {
            // Unix systems
            switch (self.original_termios) {
                .unix => |orig| {
                    // Restore original terminal settings
                    try std.posix.tcsetattr(self.stdin_fd, .NOW, orig);
                },
                else => {}, // Do nothing for .none
            }
        }

        // Explicitly reset formatting to ensure terminal is in a clean state
        try self.resetFormatting();

        self.is_raw_mode = false;
    }

    /// Update terminal size information
    pub fn updateSize(self: *Terminal) !void {
        const is_windows = @import("builtin").os.tag == .windows;

        if (is_windows) {
            // Windows implementation
            var console_screen_buffer_info: windows_console.ScreenBufferInfo = undefined;

            if (windows_console.GetConsoleScreenBufferInfo(self.stdout_fd, &console_screen_buffer_info).toBool()) {
                self.width = @intCast(console_screen_buffer_info.srWindow.Right - console_screen_buffer_info.srWindow.Left + 1);
                self.height = @intCast(console_screen_buffer_info.srWindow.Bottom - console_screen_buffer_info.srWindow.Top + 1);
                return;
            }
        } else {
            // Unix implementation
            const winsize = struct {
                ws_row: u16,
                ws_col: u16,
                ws_xpixel: u16,
                ws_ypixel: u16,
            };

            var ws = winsize{ .ws_row = 0, .ws_col = 0, .ws_xpixel = 0, .ws_ypixel = 0 };

            // TIOCGWINSZ value can vary by OS
            const TIOCGWINSZ = switch (@import("builtin").os.tag) {
                .linux => 0x5413,
                .macos, .ios, .watchos, .tvos => 0x40087468,
                .freebsd, .netbsd, .dragonfly => 0x40087468,
                .openbsd => 0x40087468,
                else => 0x5413, // Default to Linux value
            };

            // Use ioctl safely based on the OS
            var result: c_int = -1;

            if (@import("builtin").os.tag == .macos) {
                // Use direct syscall for macOS
                const darwin = struct {
                    extern "c" fn ioctl(fd: c_int, request: c_ulong, ...) c_int;
                };
                result = darwin.ioctl(@intCast(self.stdout_fd), TIOCGWINSZ, &ws);
            } else {
                // Use Linux ioctl for other platforms
                result = @intCast(std.os.linux.ioctl(self.stdout_fd, TIOCGWINSZ, @intFromPtr(&ws)));
            }

            if (result == 0 and ws.ws_col > 0 and ws.ws_row > 0) {
                self.width = ws.ws_col;
                self.height = ws.ws_row;
                return;
            }
        }

        // Fallback: try to get size from environment variables
        const cols_owned = try compat.getEnv(self.allocator, "COLUMNS");
        defer if (cols_owned) |cols| self.allocator.free(cols);
        const lines_owned = try compat.getEnv(self.allocator, "LINES");
        defer if (lines_owned) |lines| self.allocator.free(lines);

        if (cols_owned) |cols| {
            self.width = std.fmt.parseInt(u16, cols, 10) catch 80;
        }

        if (lines_owned) |lines| {
            self.height = std.fmt.parseInt(u16, lines, 10) catch 24;
        }

        // If all else fails, use default values
        if (self.width == 0) self.width = 80;
        if (self.height == 0) self.height = 24;
    }

    /// Enable mouse event reporting
    pub fn enableMouseEvents(self: *Terminal) !void {
        if (self.is_mouse_enabled) return;
        if (builtin.os.tag == .windows and !self.windows_vt_enabled) return;

        // Enable normal tracking, motion tracking, and SGR encoding
        try compat.stdoutWriteAll("\x1b[?1000h\x1b[?1002h\x1b[?1006h");
        self.is_mouse_enabled = true;
    }

    /// Disable mouse event reporting
    pub fn disableMouseEvents(self: *Terminal) !void {
        if (!self.is_mouse_enabled) return;
        if (builtin.os.tag == .windows and !self.windows_vt_enabled) {
            self.is_mouse_enabled = false;
            return;
        }

        try compat.stdoutWriteAll("\x1b[?1000l\x1b[?1002l\x1b[?1006l");
        self.is_mouse_enabled = false;
    }

    /// Enable synchronized output mode (DEC 2026) to reduce flicker during large updates.
    pub fn beginSynchronizedOutput(self: *Terminal) !void {
        if (self.is_sync_output or !self.capabilities.synchronized_output) return;
        if (builtin.os.tag == .windows and !self.windows_vt_enabled) return;

        try compat.stdoutWriteAll("\x1b[?2026h");
        self.is_sync_output = true;
    }

    /// Disable synchronized output mode (DEC 2026).
    pub fn endSynchronizedOutput(self: *Terminal) !void {
        if (!self.is_sync_output) return;
        if (builtin.os.tag == .windows and !self.windows_vt_enabled) {
            self.is_sync_output = false;
            return;
        }

        try compat.stdoutWriteAll("\x1b[?2026l");
        self.is_sync_output = false;
    }

    /// Enable bracketed paste mode so pasted text is clearly delimited.
    pub fn enableBracketedPaste(self: *Terminal) !void {
        if (self.is_bracketed_paste or !self.capabilities.bracketed_paste) return;
        if (builtin.os.tag == .windows and !self.windows_vt_enabled) return;
        try compat.stdoutWriteAll("\x1b[?2004h");
        self.is_bracketed_paste = true;
    }

    /// Disable bracketed paste mode.
    pub fn disableBracketedPaste(self: *Terminal) !void {
        if (!self.is_bracketed_paste) return;
        if (builtin.os.tag == .windows and !self.windows_vt_enabled) {
            self.is_bracketed_paste = false;
            return;
        }
        try compat.stdoutWriteAll("\x1b[?2004l");
        self.is_bracketed_paste = false;
    }

    /// Switch to the alternate screen buffer (DECSET 1049).
    pub fn enterAlternateScreen(self: *Terminal) !void {
        if (self.is_alt_screen) return;
        if (builtin.os.tag == .windows and !self.windows_vt_enabled) return;
        try compat.stdoutWriteAll("\x1b[?1049h");
        self.is_alt_screen = true;
    }

    /// Return to the primary screen buffer (DECRST 1049).
    pub fn exitAlternateScreen(self: *Terminal) !void {
        if (!self.is_alt_screen) return;
        if (builtin.os.tag == .windows and !self.windows_vt_enabled) {
            self.is_alt_screen = false;
            return;
        }
        try compat.stdoutWriteAll("\x1b[?1049l");
        self.is_alt_screen = false;
    }

    /// Hide the cursor
    pub fn hideCursor(self: *Terminal) !void {
        if (!self.is_cursor_visible) return;

        if (builtin.os.tag == .windows and !self.windows_vt_enabled) {
            windowsSetCursorVisibility(self.stdout_fd, false);
        } else {
            try compat.stdoutWriteAll("\x1b[?25l");
        }
        self.is_cursor_visible = false;
    }

    /// Show the cursor
    pub fn showCursor(self: *Terminal) !void {
        if (self.is_cursor_visible) return;

        if (builtin.os.tag == .windows and !self.windows_vt_enabled) {
            windowsSetCursorVisibility(self.stdout_fd, true);
        } else {
            try compat.stdoutWriteAll("\x1b[?25h");
        }
        self.is_cursor_visible = true;
    }

    /// Clear the screen
    pub fn clear(self: *Terminal) !void {
        if (builtin.os.tag == .windows and !self.windows_vt_enabled) {
            windowsClearConsole(self.stdout_fd);
            return;
        }
        try compat.stdoutWriteAll("\x1b[2J"); // Clear entire screen
        try compat.stdoutWriteAll("\x1b[H"); // Move cursor to top-left corner
    }

    /// Move cursor to specified position
    pub fn moveCursor(self: *Terminal, x: u16, y: u16) !void {
        if (builtin.os.tag == .windows and !self.windows_vt_enabled) {
            windowsMoveCursor(self.stdout_fd, x, y);
            return;
        }
        var buf: [32]u8 = undefined;
        const seq = try std.fmt.bufPrint(&buf, "\x1b[{d};{d}H", .{ y + 1, x + 1 });
        try compat.stdoutWriteAll(seq);
    }

    /// Set text color
    pub fn setForegroundColor(self: *Terminal, color: u8) !void {
        if (builtin.os.tag == .windows and !self.windows_vt_enabled) {
            windowsApplyColor(self.stdout_fd, color, false);
            return;
        }
        var buf: [32]u8 = undefined;
        const seq = try std.fmt.bufPrint(&buf, "\x1b[38;5;{d}m", .{color});
        try compat.stdoutWriteAll(seq);
    }

    /// Set background color
    pub fn setBackgroundColor(self: *Terminal, color: u8) !void {
        if (builtin.os.tag == .windows and !self.windows_vt_enabled) {
            windowsApplyColor(self.stdout_fd, color, true);
            return;
        }
        var buf: [32]u8 = undefined;
        const seq = try std.fmt.bufPrint(&buf, "\x1b[48;5;{d}m", .{color});
        try compat.stdoutWriteAll(seq);
    }

    /// Reset text formatting
    pub fn resetFormatting(self: *Terminal) !void {
        if (builtin.os.tag == .windows and !self.windows_vt_enabled) {
            windowsResetFormatting(self.stdout_fd);
            return;
        }
        try compat.stdoutWriteAll("\x1b[0m");
    }

    /// Set text style (bold, italic, underline)
    pub fn setStyle(self: *Terminal, bold: bool, italic: bool, underline: bool) !void {
        if (builtin.os.tag == .windows and !self.windows_vt_enabled) {
            windowsSetStyleFallback(self.stdout_fd, bold);
            return;
        }
        if (bold) {
            try compat.stdoutWriteAll("\x1b[1m");
        }

        if (italic and self.capabilities.italic) {
            try compat.stdoutWriteAll("\x1b[3m");
        }

        if (underline and self.capabilities.underline) {
            try compat.stdoutWriteAll("\x1b[4m");
        }
    }

    /// Check if terminal supports 256 colors
    pub fn supports256Colors(self: *Terminal) bool {
        return self.capabilities.colors_256 or self.capabilities.rgb_colors;
    }

    /// Check if terminal supports true color (24-bit)
    pub fn supportsTrueColor(self: *Terminal) bool {
        return self.capabilities.rgb_colors;
    }

    /// Set RGB color (if supported)
    pub fn setRgbColor(self: *Terminal, r: u8, g: u8, b: u8, is_foreground: bool) !void {
        if (builtin.os.tag == .windows and !self.windows_vt_enabled) {
            windowsApplyColor(self.stdout_fd, approximateAnsiFromRgb(r, g, b), !is_foreground);
            return;
        }
        const code: u8 = if (is_foreground) 38 else 48;

        var buf: [48]u8 = undefined;
        const seq = try std.fmt.bufPrint(&buf, "\x1b[{d};2;{d};{d};{d}m", .{ code, r, g, b });
        try compat.stdoutWriteAll(seq);
    }

    /// Enable Kitty keyboard protocol for enhanced key event handling
    pub fn enableKittyKeyboardProtocol(self: *Terminal) !void {
        if (!self.capabilities.kitty_keyboard) return;
        if (builtin.os.tag == .windows and !self.windows_vt_enabled) return;
        // Enable Kitty keyboard protocol (if the terminal supports it)
        try compat.stdoutWriteAll("\x1b[>1u");
    }

    /// Disable Kitty keyboard protocol
    pub fn disableKittyKeyboardProtocol(self: *Terminal) !void {
        if (!self.capabilities.kitty_keyboard) return;
        if (builtin.os.tag == .windows and !self.windows_vt_enabled) return;
        // Disable Kitty keyboard protocol
        try compat.stdoutWriteAll("\x1b[<1u");
    }

    /// Handle Unicode output
    pub fn writeUtf8(self: *Terminal, str: []const u8) !void {
        _ = self; // Unused parameter
        try compat.stdoutWriteAll(str);
    }

    /// Refresh cached size and report whether terminal geometry changed.
    pub fn pollResize(self: *Terminal) !?Size {
        const old_width = self.width;
        const old_height = self.height;
        try self.updateSize();
        return changedSize(old_width, old_height, self.width, self.height);
    }

    /// Consume a pending SIGWINCH and refresh cached size.
    pub fn takeResize(self: *Terminal) !?Size {
        if (winch_signal_flag.swap(0, .acq_rel) == 0) return null;
        return try self.pollResize();
    }
};

test "changedSize reports only actual terminal geometry changes" {
    try std.testing.expect(changedSize(80, 24, 80, 24) == null);

    const wider = changedSize(80, 24, 120, 24).?;
    try std.testing.expectEqual(@as(u16, 120), wider.width);
    try std.testing.expectEqual(@as(u16, 24), wider.height);

    const taller = changedSize(80, 24, 80, 40).?;
    try std.testing.expectEqual(@as(u16, 80), taller.width);
    try std.testing.expectEqual(@as(u16, 40), taller.height);
}

fn ensureWindowsUnicodeSupport() void {
    if (builtin.os.tag != .windows) return;
    const CP_UTF8: c_uint = 65001;
    _ = windows_console.SetConsoleOutputCP(CP_UTF8);
}

fn enableWindowsVirtualTerminal(handle: std.posix.fd_t) bool {
    if (builtin.os.tag != .windows) return true;
    var mode: std.os.windows.DWORD = 0;
    if (!windows_console.GetConsoleMode(handle, &mode).toBool()) return false;
    if ((mode & windows_console.ENABLE_VIRTUAL_TERMINAL_PROCESSING) != 0) return true;

    const desired = mode |
        windows_console.ENABLE_VIRTUAL_TERMINAL_PROCESSING |
        windows_console.ENABLE_PROCESSED_OUTPUT |
        windows_console.ENABLE_WRAP_AT_EOL_OUTPUT;
    return windows_console.SetConsoleMode(handle, desired).toBool();
}

fn detectWindowsVirtualTerminal(handle: std.posix.fd_t) bool {
    if (builtin.os.tag != .windows) return true;
    var mode: std.os.windows.DWORD = 0;
    if (!windows_console.GetConsoleMode(handle, &mode).toBool()) return false;
    return (mode & windows_console.ENABLE_VIRTUAL_TERMINAL_PROCESSING) != 0;
}

fn downgradeWindowsCapabilities(flags: capabilities.CapabilityFlags) capabilities.CapabilityFlags {
    var downgraded = flags;
    downgraded.colors_256 = false;
    downgraded.rgb_colors = false;
    downgraded.color_level = .ansi16;
    downgraded.bracketed_paste = false;
    downgraded.synchronized_output = false;
    downgraded.kitty_keyboard = false;
    downgraded.kitty_graphics = false;
    return downgraded;
}

fn windowsClearConsole(handle: std.posix.fd_t) void {
    if (builtin.os.tag != .windows) return;
    var info: windows_console.ScreenBufferInfo = undefined;
    if (!windows_console.GetConsoleScreenBufferInfo(handle, &info).toBool()) return;

    const cells: u32 = @intCast(@as(i32, info.dwSize.X) * @as(i32, info.dwSize.Y));
    var written: u32 = 0;
    _ = windows_console.FillConsoleOutputCharacterW(handle, @as(std.os.windows.WCHAR, ' '), cells, info.dwCursorPosition, &written);
    _ = windows_console.FillConsoleOutputAttribute(handle, info.wAttributes, cells, info.dwCursorPosition, &written);
    _ = windows_console.SetConsoleCursorPosition(handle, .{ .X = 0, .Y = 0 });
}

fn windowsMoveCursor(handle: std.posix.fd_t, x: u16, y: u16) void {
    if (builtin.os.tag != .windows) return;
    _ = windows_console.SetConsoleCursorPosition(handle, .{
        .X = @intCast(x),
        .Y = @intCast(y),
    });
}

fn windowsSetCursorVisibility(handle: std.posix.fd_t, visible: bool) void {
    if (builtin.os.tag != .windows) return;
    var cursor_info: windows_cursor.Info = undefined;
    if (!windows_cursor.GetConsoleCursorInfo(handle, &cursor_info).toBool()) return;
    cursor_info.bVisible = std.os.windows.BOOL.fromBool(visible);
    _ = windows_cursor.SetConsoleCursorInfo(handle, &cursor_info);
}

fn windowsResetFormatting(handle: std.posix.fd_t) void {
    if (builtin.os.tag != .windows) return;
    const default_attributes: u16 = 0x0007; // Gray on black
    _ = windows_console.SetConsoleTextAttribute(handle, default_attributes);
}

fn windowsApplyColor(handle: std.posix.fd_t, color: u8, is_bg: bool) void {
    if (builtin.os.tag != .windows) return;
    var info: windows_console.ScreenBufferInfo = undefined;
    if (!windows_console.GetConsoleScreenBufferInfo(handle, &info).toBool()) return;
    var attrs = info.wAttributes;

    const mask: u16 = if (is_bg) 0x00F0 else 0x000F;
    attrs &= ~mask;
    attrs |= windowsColorAttribute(color, is_bg);
    _ = windows_console.SetConsoleTextAttribute(handle, attrs);
}

fn windowsColorAttribute(color: u8, is_bg: bool) u16 {
    const idx = color & 0x0F;
    const intensity: u16 = if ((idx & 0x08) != 0) 0x08 else 0;
    const base: u16 = switch (idx & 0x07) {
        0 => 0,
        1 => 0x01, // blue
        2 => 0x02, // green
        3 => 0x03, // cyan
        4 => 0x04, // red
        5 => 0x05, // magenta
        6 => 0x06, // yellow/brown
        else => 0x07, // white
    };
    const attr = base | intensity;
    return if (is_bg) attr << 4 else attr;
}

fn windowsSetStyleFallback(handle: std.posix.fd_t, bold: bool) void {
    if (builtin.os.tag != .windows) return;
    var info: windows_console.ScreenBufferInfo = undefined;
    if (!windows_console.GetConsoleScreenBufferInfo(handle, &info).toBool()) return;
    var attrs = info.wAttributes;
    if (bold) {
        attrs |= 0x08 | 0x80; // foreground/background intensity
    } else {
        attrs &= ~@as(u16, 0x88);
    }
    _ = windows_console.SetConsoleTextAttribute(handle, attrs);
}

fn approximateAnsiFromRgb(r: u8, g: u8, b: u8) u8 {
    const max_val = @max(r, @max(g, b));
    if (max_val == 0) return 0;
    const normalized_r = @as(f32, @floatFromInt(r)) / @as(f32, @floatFromInt(max_val));
    const normalized_g = @as(f32, @floatFromInt(g)) / @as(f32, @floatFromInt(max_val));
    const normalized_b = @as(f32, @floatFromInt(b)) / @as(f32, @floatFromInt(max_val));

    const is_bright = max_val > 192;
    const base: u8 = blk: {
        if (normalized_r > 0.6 and normalized_g < 0.4 and normalized_b < 0.4) break :blk @as(u8, 4); // red
        if (normalized_r < 0.4 and normalized_g > 0.6 and normalized_b < 0.4) break :blk @as(u8, 2); // green
        if (normalized_r < 0.4 and normalized_g < 0.4 and normalized_b > 0.6) break :blk @as(u8, 1); // blue
        if (normalized_r > 0.6 and normalized_g > 0.6 and normalized_b < 0.4) break :blk @as(u8, 6); // yellow
        if (normalized_r > 0.6 and normalized_g < 0.4 and normalized_b > 0.6) break :blk @as(u8, 5); // magenta
        if (normalized_r < 0.4 and normalized_g > 0.6 and normalized_b > 0.6) break :blk @as(u8, 3); // cyan
        break :blk @as(u8, 7); // white/gray
    };

    return if (is_bright) base | 0x08 else base;
}

// Export the init function directly
pub const init = Terminal.init;

/// Initialize a terminal for an interactive example.
///
/// Returns `null` when launched without a real TTY so public `zig build`
/// example steps can stay automation-safe while still launching normally from
/// an interactive terminal.
pub fn initInteractive(allocator: std.mem.Allocator, example_name: []const u8) anyerror!?Terminal {
    return Terminal.init(allocator) catch |err| {
        const any_err: anyerror = err;
        if (any_err == error.NotATerminal) {
            std.debug.print("{s}: interactive terminal required; run this command from a real terminal or launch the installed binary in zig-out/bin.\n", .{example_name});
            return null;
        }
        return any_err;
    };
}

test "terminal initialization" {
    const allocator = std.testing.allocator;

    // Try to initialize terminal, but skip test if we're not in a real terminal
    var term = Terminal.init(allocator) catch |err| {
        if (err == error.NotATerminal) {
            // Skip test when not running in a real terminal
            return error.SkipZigTest;
        }
        return err;
    };
    defer term.deinit() catch {};

    try std.testing.expect(term.width > 0);
    try std.testing.expect(term.height > 0);
    try std.testing.expect(!term.is_raw_mode);
    try std.testing.expect(term.is_cursor_visible);
}
