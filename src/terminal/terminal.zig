const std = @import("std");

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
        const stdin_fd = std.fs.File.stdin().handle;
        const stdout_fd = std.fs.File.stdout().handle;

        var original_termios: OriginalTermAttrs = undefined;
        const is_windows = @import("builtin").os.tag == .windows;

        if (is_windows) {
            if (std.os.windows.kernel32.GetConsoleMode(stdin_fd, @ptrCast(&original_termios.windows.in_mode))) {
                if (std.os.windows.kernel32.GetConsoleMode(stdout_fd, @ptrCast(&original_termios.windows.out_mode))) {
                    original_termios = .{ .windows = .{
                        .in_mode = original_termios.windows.in_mode,
                        .out_mode = original_termios.windows.out_mode,
                    } };
                } else {
                    original_termios = .{ .none = {} };
                }
            } else {
                original_termios = .{ .none = {} };
            }
        } else {
            // Unix systems
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
        };

        try self.updateSize();

        // Set up SIGWINCH handling on Unix platforms
        if (@import("builtin").os.tag != .windows) {
            // Ignore SIGWINCH - we'll handle window size changes manually
            // This prevents the terminal from getting into a bad state
            const SIG = std.posix.SIG;
            _ = std.posix.sigaction(SIG.WINCH, &std.posix.Sigaction{
                .handler = .{ .handler = SIG.IGN },
                .mask = std.posix.sigemptyset(),
                .flags = 0,
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

        // Reset all formatting before exit
        try self.resetFormatting();
    }

    /// Enable raw mode for direct character input
    pub fn enableRawMode(self: *Terminal) !void {
        if (self.is_raw_mode) return;

        // For macOS, use a much simpler approach that's more reliable
        if (@import("builtin").os.tag == .macos) {
            // Save original terminal settings first (so we can restore them later)
            self.original_termios = .{ .unix = try std.posix.tcgetattr(self.stdin_fd) };

            // On macOS, directly use the system command which is more reliable
            const darwin = struct {
                extern "c" fn system(command: [*:0]const u8) c_int;
            };

            _ = darwin.system("stty -echo -icanon -isig -iexten -ixon raw");

            // Also set the terminal to non-blocking mode
            const flags = std.posix.fcntl(self.stdin_fd, std.posix.F.GETFL, 0) catch |err| {
                return err;
            };

            const O_NONBLOCK: u32 = 0x00000004; // macOS value
            _ = std.posix.fcntl(self.stdin_fd, std.posix.F.SETFL, flags | O_NONBLOCK) catch |err| {
                return err;
            };

            // Enable Kitty keyboard protocol
            self.enableKittyKeyboardProtocol() catch {};

            self.is_raw_mode = true;
            return;
        }

        // Normal implementation for other platforms
        const is_windows = @import("builtin").os.tag == .windows;

        if (is_windows) {
            switch (self.original_termios) {
                .windows => |info| {
                    // For Windows, we need to set appropriate console modes
                    // Enable extended input flags and disable processed input
                    const ENABLE_VIRTUAL_TERMINAL_INPUT = 0x0200;
                    const new_in_mode = (info.in_mode & ~@as(u32, 0x0001)) | ENABLE_VIRTUAL_TERMINAL_INPUT;

                    // Enable virtual terminal processing for ANSI sequences
                    const ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004;
                    const new_out_mode = info.out_mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING;

                    if (!std.os.windows.kernel32.SetConsoleMode(self.stdin_fd, new_in_mode)) {
                        return error.SetConsoleModeFailure;
                    }

                    if (!std.os.windows.kernel32.SetConsoleMode(self.stdout_fd, new_out_mode)) {
                        // Try to restore the original mode and report error
                        _ = std.os.windows.kernel32.SetConsoleMode(self.stdin_fd, info.in_mode);
                        return error.SetConsoleModeFailure;
                    }
                },
                else => {}, // Do nothing for .none
            }
        } else {
            // Unix systems
            switch (self.original_termios) {
                .unix => |orig| {
                    var raw = orig;

                    // Disable canonical mode, echo, signals, and extended input
                    // Use hardcoded values since std.posix.system constants are not available
                    const ECHO: u64 = 0x00000008;
                    const ICANON: u64 = 0x00000002;
                    const ISIG: u64 = 0x00000001;
                    const IEXTEN: u64 = 0x00000400;

                    // Create a copy in a regular integer (use u32 for 32-bit Linux)
                    var lflag = @as(u32, @bitCast(raw.lflag));

                    // Perform operations on the regular integer
                    const mask: u32 = ECHO | ICANON | ISIG | IEXTEN;
                    lflag &= ~mask;

                    // Assign back to the packed struct
                    raw.lflag = @bitCast(lflag);

                    // Turn off software flow control
                    const IXON: u32 = 0x00000200;
                    const ICRNL: u32 = 0x00000100;
                    const BRKINT: u32 = 0x00000002;
                    const INPCK: u32 = 0x00000010;
                    const ISTRIP: u32 = 0x00000020;

                    var iflag = @as(u32, @bitCast(raw.iflag));
                    const iflag_mask: u32 = IXON | ICRNL | BRKINT | INPCK | ISTRIP;
                    iflag &= ~iflag_mask;
                    raw.iflag = @bitCast(iflag);

                    // Disable output processing
                    const OPOST: u32 = 0x00000001;

                    var oflag = @as(u32, @bitCast(raw.oflag));
                    oflag &= ~OPOST;
                    raw.oflag = @bitCast(oflag);

                    // Set character size to 8 bits
                    const CS8: u32 = 0x00000300;

                    var cflag = @as(u32, @bitCast(raw.cflag));
                    cflag |= CS8;
                    raw.cflag = @bitCast(cflag);

                    // Set read timeout and minimum input to 0 for non-blocking reads
                    // This is especially important for macOS
                    const V_TIME: usize = 16; // VTIME index on macOS
                    const V_MIN: usize = 17; // VMIN index on macOS

                    raw.cc[V_TIME] = 0; // No timeout, return immediately
                    raw.cc[V_MIN] = 0; // Return even if no characters are available

                    // Apply settings
                    try std.posix.tcsetattr(self.stdin_fd, .FLUSH, raw);
                },
                else => {}, // Do nothing for .none
            }
        }

        // Set stdin to non-blocking mode for non-macOS Unix
        if (@import("builtin").os.tag != .windows and @import("builtin").os.tag != .macos) {
            // Get current flags
            const flags = std.posix.fcntl(self.stdin_fd, std.posix.F.GETFL, 0) catch |err| {
                // Silently handle error - don't pollute stdout
                return err;
            };

            // Set non-blocking flag - use platform-specific constant
            const O_NONBLOCK: u32 = switch (@import("builtin").os.tag) {
                .linux => 0o4000, // Linux O_NONBLOCK value
                .freebsd, .netbsd => 0x4, // BSD O_NONBLOCK value
                else => 0x00000004, // Default to macOS value
            };

            _ = std.posix.fcntl(self.stdin_fd, std.posix.F.SETFL, flags | O_NONBLOCK) catch |err| {
                // Silently handle error - don't pollute stdout
                return err;
            };
        }

        // Try to enable the Kitty keyboard protocol for better key handling
        self.enableKittyKeyboardProtocol() catch {};

        self.is_raw_mode = true;
    }

    /// Disable raw mode and restore original terminal settings
    pub fn disableRawMode(self: *Terminal) !void {
        if (!self.is_raw_mode) return;

        // Disable the Kitty keyboard protocol first
        self.disableKittyKeyboardProtocol() catch {};

        // For macOS, ensure terminal output is flushed and use a reliable method to restore
        if (@import("builtin").os.tag == .macos) {
            // Flush any pending output
            var stdout = std.fs.File.stdout();
            try stdout.writeAll("\r\n"); // Add newline to flush

            // Restore original terminal settings if we have them
            switch (self.original_termios) {
                .unix => |orig| {
                    // Restore original terminal settings
                    std.posix.tcsetattr(self.stdin_fd, .FLUSH, orig) catch {};
                },
                else => {}, // Do nothing for .none
            }

            // Use stty sane as a reliable way to restore a sane terminal state
            const darwin = struct {
                extern "c" fn system(command: [*:0]const u8) c_int;
            };
            _ = darwin.system("stty sane");

            // Small delay to ensure terminal state is fully restored
            std.Thread.sleep(std.time.ns_per_ms * 20);

            // Explicitly reset formatting
            try self.resetFormatting();

            self.is_raw_mode = false;
            return;
        }

        const is_windows = @import("builtin").os.tag == .windows;

        if (is_windows) {
            switch (self.original_termios) {
                .windows => |info| {
                    // Restore original console modes
                    if (!std.os.windows.kernel32.SetConsoleMode(self.stdin_fd, info.in_mode)) {
                        return error.SetConsoleModeFailure;
                    }

                    if (!std.os.windows.kernel32.SetConsoleMode(self.stdout_fd, info.out_mode)) {
                        return error.SetConsoleModeFailure;
                    }
                },
                else => {}, // Do nothing for .none
            }
        } else {
            // Unix systems
            switch (self.original_termios) {
                .unix => |orig| {
                    // Restore original terminal settings
                    try std.posix.tcsetattr(self.stdin_fd, .FLUSH, orig);
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
            var console_screen_buffer_info: std.os.windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;

            if (std.os.windows.kernel32.GetConsoleScreenBufferInfo(self.stdout_fd, &console_screen_buffer_info)) {
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
        var env = try std.process.getEnvMap(self.allocator);
        defer env.deinit();

        if (env.get("COLUMNS")) |cols| {
            self.width = std.fmt.parseInt(u16, cols, 10) catch 80;
        }

        if (env.get("LINES")) |lines| {
            self.height = std.fmt.parseInt(u16, lines, 10) catch 24;
        }

        // If all else fails, use default values
        if (self.width == 0) self.width = 80;
        if (self.height == 0) self.height = 24;
    }

    /// Enable mouse event reporting
    pub fn enableMouseEvents(self: *Terminal) !void {
        if (self.is_mouse_enabled) return;

        var stdout = std.fs.File.stdout();
        try stdout.writeAll("\x1b[?1000h\x1b[?1006h"); // Enable mouse tracking (X10 + SGR)
        self.is_mouse_enabled = true;
    }

    /// Disable mouse event reporting
    pub fn disableMouseEvents(self: *Terminal) !void {
        if (!self.is_mouse_enabled) return;

        var stdout = std.fs.File.stdout();
        try stdout.writeAll("\x1b[?1000l\x1b[?1006l"); // Disable mouse tracking
        self.is_mouse_enabled = false;
    }

    /// Hide the cursor
    pub fn hideCursor(self: *Terminal) !void {
        if (!self.is_cursor_visible) return;

        var stdout = std.fs.File.stdout();
        try stdout.writeAll("\x1b[?25l");
        self.is_cursor_visible = false;
    }

    /// Show the cursor
    pub fn showCursor(self: *Terminal) !void {
        if (self.is_cursor_visible) return;

        var stdout = std.fs.File.stdout();
        try stdout.writeAll("\x1b[?25h");
        self.is_cursor_visible = true;
    }

    /// Clear the screen
    pub fn clear(self: *Terminal) !void {
        _ = self; // Unused parameter
        var stdout = std.fs.File.stdout();
        try stdout.writeAll("\x1b[2J"); // Clear entire screen
        try stdout.writeAll("\x1b[H"); // Move cursor to top-left corner
    }

    /// Move cursor to specified position
    pub fn moveCursor(self: *Terminal, x: u16, y: u16) !void {
        _ = self; // Unused parameter
        var stdout = std.fs.File.stdout();
        var buf: [32]u8 = undefined;
        const seq = try std.fmt.bufPrint(&buf, "\x1b[{d};{d}H", .{ y + 1, x + 1 });
        try stdout.writeAll(seq);
    }

    /// Set text color
    pub fn setForegroundColor(self: *Terminal, color: u8) !void {
        _ = self; // Unused parameter
        var stdout = std.fs.File.stdout();
        var buf: [32]u8 = undefined;
        const seq = try std.fmt.bufPrint(&buf, "\x1b[38;5;{d}m", .{color});
        try stdout.writeAll(seq);
    }

    /// Set background color
    pub fn setBackgroundColor(self: *Terminal, color: u8) !void {
        _ = self; // Unused parameter
        var stdout = std.fs.File.stdout();
        var buf: [32]u8 = undefined;
        const seq = try std.fmt.bufPrint(&buf, "\x1b[48;5;{d}m", .{color});
        try stdout.writeAll(seq);
    }

    /// Reset text formatting
    pub fn resetFormatting(self: *Terminal) !void {
        _ = self; // Unused parameter
        var stdout = std.fs.File.stdout();
        try stdout.writeAll("\x1b[0m");
    }

    /// Set text style (bold, italic, underline)
    pub fn setStyle(self: *Terminal, bold: bool, italic: bool, underline: bool) !void {
        _ = self; // Unused parameter
        var stdout = std.fs.File.stdout();

        if (bold) {
            try stdout.writeAll("\x1b[1m");
        }

        if (italic) {
            try stdout.writeAll("\x1b[3m");
        }

        if (underline) {
            try stdout.writeAll("\x1b[4m");
        }
    }

    /// Check if terminal supports 256 colors
    pub fn supports256Colors(self: *Terminal) bool {
        var env = std.process.getEnvMap(self.allocator) catch {
            return false;
        };
        defer env.deinit();

        const term = env.get("TERM") orelse return false;

        return std.mem.indexOf(u8, term, "256color") != null or
            std.mem.indexOf(u8, term, "xterm") != null;
    }

    /// Check if terminal supports true color (24-bit)
    pub fn supportsTrueColor(self: *Terminal) bool {
        var env = std.process.getEnvMap(self.allocator) catch {
            return false;
        };
        defer env.deinit();

        const colorterm = env.get("COLORTERM") orelse return false;

        return std.mem.indexOf(u8, colorterm, "truecolor") != null or
            std.mem.indexOf(u8, colorterm, "24bit") != null;
    }

    /// Set RGB color (if supported)
    pub fn setRgbColor(self: *Terminal, r: u8, g: u8, b: u8, is_foreground: bool) !void {
        _ = self; // Unused parameter
        var stdout = std.fs.File.stdout();
        const code: u8 = if (is_foreground) 38 else 48;

        var buf: [48]u8 = undefined;
        const seq = try std.fmt.bufPrint(&buf, "\x1b[{d};2;{d};{d};{d}m", .{ code, r, g, b });
        try stdout.writeAll(seq);
    }

    /// Enable Kitty keyboard protocol for enhanced key event handling
    pub fn enableKittyKeyboardProtocol(self: *Terminal) !void {
        _ = self; // Unused parameter
        var stdout = std.fs.File.stdout();

        // Enable Kitty keyboard protocol (if the terminal supports it)
        try stdout.writeAll("\x1b[>1u");
    }

    /// Disable Kitty keyboard protocol
    pub fn disableKittyKeyboardProtocol(self: *Terminal) !void {
        _ = self; // Unused parameter
        var stdout = std.fs.File.stdout();

        // Disable Kitty keyboard protocol
        try stdout.writeAll("\x1b[<1u");
    }

    /// Handle Unicode output
    pub fn writeUtf8(self: *Terminal, str: []const u8) !void {
        _ = self; // Unused parameter
        var stdout = std.fs.File.stdout();
        try stdout.writeAll(str);
    }
};

// Export the init function directly
pub const init = Terminal.init;

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
