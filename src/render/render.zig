const std = @import("std");
const text_metrics = @import("text_metrics.zig");

/// Output rendering module
///
/// This module provides functionality for rendering to the terminal:
/// - Screen buffer management
/// - Text styling with ANSI escape codes
/// - Efficient rendering with double buffering
/// - Unicode support
/// - Drawing primitives for UI elements
/// Compact, stack-only ANSI escape representation used to avoid heap allocations.
pub const AnsiCode = struct {
    buf: [24]u8 = undefined,
    len: u8 = 0,

    /// Return the active slice of the encoded ANSI sequence.
    pub fn slice(self: AnsiCode) []const u8 {
        return self.buf[0..self.len];
    }

    /// Copy a slice into the internal buffer, truncating if necessary.
    pub fn fromSlice(data: []const u8) AnsiCode {
        var code = AnsiCode{};
        const copy_len = @as(u8, @intCast(@min(data.len, code.buf.len)));
        if (copy_len > 0) {
            std.mem.copyForwards(u8, code.buf[0..copy_len], data[0..copy_len]);
        }
        code.len = copy_len;
        return code;
    }
};
/// RGB color representation
pub const RgbColor = struct {
    r: u8,
    g: u8,
    b: u8,

    /// Create a new RGB color
    pub fn init(r: u8, g: u8, b: u8) RgbColor {
        return RgbColor{
            .r = r,
            .g = g,
            .b = b,
        };
    }

    /// Convert to ANSI color code
    pub fn toAnsi(self: RgbColor, is_bg: bool) AnsiCode {
        var result: [24]u8 = undefined;
        const prefix = if (is_bg) "48" else "38";

        const written = std.fmt.bufPrint(&result, "{s};2;{d};{d};{d}", .{ prefix, self.r, self.g, self.b }) catch {
            if (is_bg) {
                return NamedColor.default.toBg();
            } else {
                return NamedColor.default.toFg();
            }
        };

        return AnsiCode.fromSlice(written);
    }
};

/// Color type that can be either a named ANSI color or an RGB color
pub const Color = union(enum) {
    named_color: NamedColor,
    rgb_color: RgbColor,

    /// Create a new named color
    pub fn named(color: NamedColor) Color {
        return Color{ .named_color = color };
    }

    /// Create a new RGB color
    pub fn rgb(r: u8, g: u8, b: u8) Color {
        return Color{ .rgb_color = RgbColor.init(r, g, b) };
    }

    /// Convert to foreground color code
    pub fn toFg(self: Color) AnsiCode {
        return switch (self) {
            .named_color => |c| c.toFg(),
            .rgb_color => |c| c.toAnsi(false),
        };
    }

    /// Convert to background color code
    pub fn toBg(self: Color) AnsiCode {
        return switch (self) {
            .named_color => |c| c.toBg(),
            .rgb_color => |c| c.toAnsi(true),
        };
    }
};

/// Gradient stop definition for linear gradients
pub const GradientStop = struct {
    /// Normalized position between 0 and 1
    position: f32,
    /// Color at this stop
    color: Color,
};

/// Gradient direction
pub const GradientDirection = enum {
    horizontal,
    vertical,
};

/// Named ANSI colors
pub const NamedColor = enum(u8) {
    black = 0,
    red = 1,
    green = 2,
    yellow = 3,
    blue = 4,
    magenta = 5,
    cyan = 6,
    white = 7,
    default = 9,
    bright_black = 10,
    bright_red = 11,
    bright_green = 12,
    bright_yellow = 13,
    bright_blue = 14,
    bright_magenta = 15,
    bright_cyan = 16,
    bright_white = 17,

    /// Convert to foreground color code
    pub fn toFg(self: NamedColor) AnsiCode {
        return AnsiCode.fromSlice(switch (self) {
            .black => "30",
            .red => "31",
            .green => "32",
            .yellow => "33",
            .blue => "34",
            .magenta => "35",
            .cyan => "36",
            .white => "37",
            .default => "39",
            .bright_black => "90",
            .bright_red => "91",
            .bright_green => "92",
            .bright_yellow => "93",
            .bright_blue => "94",
            .bright_magenta => "95",
            .bright_cyan => "96",
            .bright_white => "97",
        });
    }

    /// Convert to background color code
    pub fn toBg(self: NamedColor) AnsiCode {
        return AnsiCode.fromSlice(switch (self) {
            .black => "40",
            .red => "41",
            .green => "42",
            .yellow => "43",
            .blue => "44",
            .magenta => "45",
            .cyan => "46",
            .white => "47",
            .default => "49",
            .bright_black => "100",
            .bright_red => "101",
            .bright_green => "102",
            .bright_yellow => "103",
            .bright_blue => "104",
            .bright_magenta => "105",
            .bright_cyan => "106",
            .bright_white => "107",
        });
    }
};

/// Text style attributes
pub const Style = struct {
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,
    blink: bool = false,
    reverse: bool = false,
    strikethrough: bool = false,

    /// Create a new style
    pub fn init(bold: bool, italic: bool, underline: bool) Style {
        return Style{
            .bold = bold,
            .italic = italic,
            .underline = underline,
        };
    }

    /// Create a style with all attributes
    pub fn initFull(bold: bool, italic: bool, underline: bool, blink: bool, reverse: bool, strikethrough: bool) Style {
        return Style{
            .bold = bold,
            .italic = italic,
            .underline = underline,
            .blink = blink,
            .reverse = reverse,
            .strikethrough = strikethrough,
        };
    }

    /// Convert to ANSI style codes without heap allocations.
    pub fn toAnsi(self: Style) AnsiCode {
        var code = AnsiCode{};

        if (self.bold) {
            code = appendAnsi(code, "1;");
        }

        if (self.italic) {
            code = appendAnsi(code, "3;");
        }

        if (self.underline) {
            code = appendAnsi(code, "4;");
        }

        if (self.blink) {
            code = appendAnsi(code, "5;");
        }

        if (self.reverse) {
            code = appendAnsi(code, "7;");
        }

        if (self.strikethrough) {
            code = appendAnsi(code, "9;");
        }

        if (code.len == 0) {
            return AnsiCode.fromSlice("0");
        }

        // Drop trailing semicolon
        code.len -= 1;
        return code;
    }
};

fn appendAnsi(current: AnsiCode, fragment: []const u8) AnsiCode {
    var out = current;
    const available = out.buf.len - out.len;
    if (fragment.len > available) {
        return out; // truncate rather than overflow; caller treats empty as reset
    }
    std.mem.copyForwards(u8, out.buf[out.len .. out.len + fragment.len], fragment);
    out.len += @intCast(fragment.len);
    return out;
}

fn colorToRgb(color: Color) RgbColor {
    return switch (color) {
        .rgb_color => |rgb| rgb,
        .named_color => |named| switch (named) {
            .black => RgbColor.init(0, 0, 0),
            .red => RgbColor.init(255, 0, 0),
            .green => RgbColor.init(0, 255, 0),
            .yellow => RgbColor.init(255, 255, 0),
            .blue => RgbColor.init(0, 0, 255),
            .magenta => RgbColor.init(255, 0, 255),
            .cyan => RgbColor.init(0, 255, 255),
            .white => RgbColor.init(255, 255, 255),
            .default => RgbColor.init(0, 0, 0),
            .bright_black => RgbColor.init(80, 80, 80),
            .bright_red => RgbColor.init(255, 64, 64),
            .bright_green => RgbColor.init(64, 255, 64),
            .bright_yellow => RgbColor.init(255, 255, 128),
            .bright_blue => RgbColor.init(64, 64, 255),
            .bright_magenta => RgbColor.init(255, 64, 255),
            .bright_cyan => RgbColor.init(64, 255, 255),
            .bright_white => RgbColor.init(255, 255, 255),
        },
    };
}

fn lerpChannel(a: u8, b: u8, t: f32) u8 {
    const start = @as(f32, @floatFromInt(a));
    const end = @as(f32, @floatFromInt(b));
    const value = start + (end - start) * t;
    const clamped = std.math.clamp(value, 0.0, 255.0);
    return @intFromFloat(std.math.round(clamped));
}

fn lerpColor(start: RgbColor, end: RgbColor, t: f32) RgbColor {
    return RgbColor.init(
        lerpChannel(start.r, end.r, t),
        lerpChannel(start.g, end.g, t),
        lerpChannel(start.b, end.b, t),
    );
}

fn copyAndSortStops(allocator: std.mem.Allocator, stops: []const GradientStop) ![]GradientStop {
    var buffer = try allocator.alloc(GradientStop, stops.len);
    @memcpy(buffer, stops);

    var i: usize = 0;
    while (i < buffer.len) : (i += 1) {
        var j: usize = i + 1;
        while (j < buffer.len) : (j += 1) {
            if (buffer[j].position < buffer[i].position) {
                const tmp = buffer[i];
                buffer[i] = buffer[j];
                buffer[j] = tmp;
            }
        }
    }

    return buffer;
}

fn sampleGradientColor(sorted: []const GradientStop, t_in: f32) RgbColor {
    if (sorted.len == 0) return RgbColor.init(0, 0, 0);
    var clamped = t_in;
    if (clamped < 0) clamped = 0;
    if (clamped > 1) clamped = 1;

    var prev = sorted[0];
    for (sorted[1..]) |stop| {
        if (clamped <= stop.position) {
            const denom = stop.position - prev.position;
            const local_t = if (denom <= 0) 0 else (clamped - prev.position) / denom;
            return lerpColor(colorToRgb(prev.color), colorToRgb(stop.color), local_t);
        }
        prev = stop;
    }

    return colorToRgb(sorted[sorted.len - 1].color);
}

/// Represents a cell in the screen buffer
pub const Cell = struct {
    /// Character to display
    char: u21 = ' ',
    /// Foreground color
    fg: Color = Color{ .named_color = NamedColor.default },
    /// Background color
    bg: Color = Color{ .named_color = NamedColor.default },
    /// Text style attributes
    style: Style = Style{},

    /// Create a new cell
    pub fn init(char: u21, fg: Color, bg: Color, style: Style) Cell {
        return Cell{
            .char = char,
            .fg = fg,
            .bg = bg,
            .style = style,
        };
    }

    /// Check if this cell is equal to another
    pub fn eql(self: Cell, other: Cell) bool {
        if (self.char != other.char) return false;

        // Compare foreground colors
        switch (self.fg) {
            .named_color => |self_named| {
                switch (other.fg) {
                    .named_color => |other_named| {
                        if (self_named != other_named) return false;
                    },
                    .rgb_color => return false,
                }
            },
            .rgb_color => |self_rgb| {
                switch (other.fg) {
                    .named_color => return false,
                    .rgb_color => |other_rgb| {
                        if (self_rgb.r != other_rgb.r or
                            self_rgb.g != other_rgb.g or
                            self_rgb.b != other_rgb.b) return false;
                    },
                }
            },
        }

        // Compare background colors
        switch (self.bg) {
            .named_color => |self_named| {
                switch (other.bg) {
                    .named_color => |other_named| {
                        if (self_named != other_named) return false;
                    },
                    .rgb_color => return false,
                }
            },
            .rgb_color => |self_rgb| {
                switch (other.bg) {
                    .named_color => return false,
                    .rgb_color => |other_rgb| {
                        if (self_rgb.r != other_rgb.r or
                            self_rgb.g != other_rgb.g or
                            self_rgb.b != other_rgb.b) return false;
                    },
                }
            },
        }

        // Compare styles
        if (self.style.bold != other.style.bold or
            self.style.italic != other.style.italic or
            self.style.underline != other.style.underline or
            self.style.blink != other.style.blink or
            self.style.reverse != other.style.reverse or
            self.style.strikethrough != other.style.strikethrough) return false;

        return true;
    }
};

/// Screen buffer for terminal rendering
pub const Buffer = struct {
    /// Width of the buffer in columns
    width: u16,
    /// Height of the buffer in rows
    height: u16,
    /// Cells in the buffer
    cells: []Cell,
    /// Allocator for buffer operations
    allocator: std.mem.Allocator,

    /// Initialize a new buffer
    pub fn init(allocator: std.mem.Allocator, width: u16, height: u16) !Buffer {
        const cells = try allocator.alloc(Cell, width * height);

        // Initialize all cells with default values
        for (cells) |*cell| {
            cell.* = Cell{};
        }

        return Buffer{
            .width = width,
            .height = height,
            .cells = cells,
            .allocator = allocator,
        };
    }

    /// Clean up buffer resources
    pub fn deinit(self: *Buffer) void {
        self.allocator.free(self.cells);
    }

    /// Get cell at specified coordinates
    pub fn getCell(self: *Buffer, x: u16, y: u16) *Cell {
        if (x >= self.width or y >= self.height) {
            // Out of bounds, return a reference to the first cell
            return &self.cells[0];
        }

        return &self.cells[y * self.width + x];
    }

    /// Set cell at specified coordinates
    pub fn setCell(self: *Buffer, x: u16, y: u16, cell: Cell) void {
        if (x >= self.width or y >= self.height) {
            return; // Out of bounds
        }

        self.cells[y * self.width + x] = cell;
    }

    /// Clear the buffer
    pub fn clear(self: *Buffer) void {
        for (self.cells) |*cell| {
            cell.* = Cell{};
        }
    }

    /// Fill a rectangular area with a specific cell
    pub fn fillRect(self: *Buffer, x: u16, y: u16, width: u16, height: u16, cell: Cell) void {
        const max_x = @min(x + width, self.width);
        const max_y = @min(y + height, self.height);

        var cy = y;
        while (cy < max_y) : (cy += 1) {
            var cx = x;
            while (cx < max_x) : (cx += 1) {
                self.setCell(cx, cy, cell);
            }
        }
    }
};

/// Border style for boxes
pub const BorderStyle = enum {
    none,
    single,
    double,
    rounded,
    thick,

    /// Get the characters for this border style
    pub fn getChars(self: BorderStyle) [8]u21 {
        return switch (self) {
            .none => [_]u21{ ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ' },
            .single => [_]u21{ '┌', '┐', '└', '┘', '─', '─', '│', '│' },
            .double => [_]u21{ '╔', '╗', '╚', '╝', '═', '═', '║', '║' },
            .rounded => [_]u21{ '╭', '╮', '╰', '╯', '─', '─', '│', '│' },
            .thick => [_]u21{ '┏', '┓', '┗', '┛', '━', '━', '┃', '┃' },
        };
    }
};

/// Drop shadow styling for boxed UI.
pub const ShadowStyle = struct {
    /// Horizontal offset from the box (positive draws to the right).
    offset_x: u16 = 1,
    /// Vertical offset from the box (positive draws downward).
    offset_y: u16 = 1,
    /// Shadow tint.
    color: Color = Color.named(NamedColor.bright_black),
    /// Use a softer shade character when true.
    soft: bool = true,
};

/// Combined box style including border, fill, and optional shadow.
pub const BoxStyle = struct {
    border: BorderStyle = .single,
    border_color: Color = Color.named(NamedColor.default),
    background: Color = Color.named(NamedColor.default),
    style: Style = Style{},
    fill_style: Style = Style{},
    shadow: ?ShadowStyle = null,
};

/// Terminal capabilities that may not be available on all terminals
pub const TerminalCapabilities = struct {
    /// Support for RGB colors
    rgb_colors: bool = false,
    /// Support for 256 colors
    colors_256: bool = false,
    /// Support for italic text
    italic: bool = false,
    /// Support for unicode characters
    unicode: bool = true,
    /// Support for underline style
    underline: bool = true,
    /// Support for strikethrough
    strikethrough: bool = false,
    /// Terminal can safely display emoji
    emoji: bool = false,
    /// Terminal renders ligatures
    ligatures: bool = false,
    /// Terminal needs double-width accounting
    double_width: bool = true,
    /// Terminal can display bidi text coherently
    bidi: bool = true,

    /// Create default capabilities (conservative defaults)
    pub fn init() TerminalCapabilities {
        return TerminalCapabilities{};
    }

    /// Detect capabilities from TERM env variable
    pub fn detect() TerminalCapabilities {
        var caps = TerminalCapabilities{};

        const term = std.process.getEnvVarOwned(std.heap.page_allocator, "TERM") catch {
            return caps; // Return default if TERM not found
        };
        defer std.heap.page_allocator.free(term);

        // Check terminal type for capabilities
        if (std.mem.indexOf(u8, term, "256color") != null) {
            caps.colors_256 = true;
        }

        if (std.mem.indexOf(u8, term, "xterm") != null or
            std.mem.indexOf(u8, term, "iterm") != null or
            std.mem.indexOf(u8, term, "kitty") != null or
            std.mem.indexOf(u8, term, "alacritty") != null)
        {
            caps.rgb_colors = true;
            caps.italic = true;
            caps.strikethrough = true;
        }

        if (std.mem.indexOf(u8, term, "linux") != null) {
            caps.unicode = false;
        }

        // Check for COLORTERM env variable
        var colorterm_buf: [64]u8 = undefined;
        var colorterm_len: usize = 0;

        const ct = std.process.getEnvVarOwned(std.heap.page_allocator, "COLORTERM") catch null;
        if (ct) |colorterm| {
            defer std.heap.page_allocator.free(colorterm);
            colorterm_len = @min(colorterm.len, colorterm_buf.len - 1);
            @memcpy(colorterm_buf[0..colorterm_len], colorterm[0..colorterm_len]);
            colorterm_buf[colorterm_len] = 0;
        }

        if (colorterm_len > 0) {
            const colorterm = colorterm_buf[0..colorterm_len];
            // Check if the colorterm contains truecolor or 24bit
            var has_truecolor = false;
            for (colorterm, 0..) |_, i| {
                if (i + 9 <= colorterm_len and
                    colorterm[i] == 't' and
                    colorterm[i + 1] == 'r' and
                    colorterm[i + 2] == 'u' and
                    colorterm[i + 3] == 'e' and
                    colorterm[i + 4] == 'c' and
                    colorterm[i + 5] == 'o' and
                    colorterm[i + 6] == 'l' and
                    colorterm[i + 7] == 'o' and
                    colorterm[i + 8] == 'r')
                {
                    has_truecolor = true;
                    break;
                }

                if (i + 4 <= colorterm_len and
                    colorterm[i] == '2' and
                    colorterm[i + 1] == '4' and
                    colorterm[i + 2] == 'b' and
                    colorterm[i + 3] == 'i' and
                    colorterm[i + 4] == 't')
                {
                    has_truecolor = true;
                    break;
                }
            }

            if (has_truecolor) {
                caps.rgb_colors = true;
            }
        }

        // Feature survey based on environment hints and pragmatic defaults.
        caps.emoji = text_metrics.measureWidth("✅").has_emoji;
        caps.double_width = true; // keep accounting for safety
        caps.ligatures = std.mem.indexOf(u8, term, "kitty") != null or
            std.mem.indexOf(u8, term, "wezterm") != null or
            std.mem.indexOf(u8, term, "vscode") != null;
        caps.bidi = true; // optimistic but sanitizers are available
        caps.rgb_colors = caps.rgb_colors or text_metrics.detectTrueColor();

        return caps;
    }

    /// Get the best available color for the given color
    pub fn bestColor(self: TerminalCapabilities, color: Color) Color {
        return switch (color) {
            .rgb_color => |rgb| {
                if (self.rgb_colors) {
                    return color;
                } else if (self.colors_256) {
                    // Convert RGB to approximate 256 color index
                    // This is a simple approximation, a real implementation would use a proper mapping
                    const r = @divFloor(rgb.r, 51);
                    const g = @divFloor(rgb.g, 51);
                    const b = @divFloor(rgb.b, 51);

                    if (r == g and g == b) {
                        // Grayscale
                        const gray = r;
                        if (gray == 0) return Color.named(NamedColor.default); // Changed from .black to .default
                        if (gray == 5) return Color.named(NamedColor.white);
                        return Color.named(NamedColor.default); // Fallback
                    }

                    // Find closest basic color
                    if (r > 3 and g < 2 and b < 2) return Color.named(NamedColor.red);
                    if (r < 2 and g > 3 and b < 2) return Color.named(NamedColor.green);
                    if (r < 2 and g < 2 and b > 3) return Color.named(NamedColor.blue);
                    if (r > 3 and g > 3 and b < 2) return Color.named(NamedColor.yellow);
                    if (r > 3 and g < 2 and b > 3) return Color.named(NamedColor.magenta);
                    if (r < 2 and g > 3 and b > 3) return Color.named(NamedColor.cyan);

                    return Color.named(NamedColor.default); // Fallback
                } else {
                    // Find closest basic color
                    const r = rgb.r;
                    const g = rgb.g;
                    const b = rgb.b;

                    if (r > 200 and g < 100 and b < 100) return Color.named(NamedColor.red);
                    if (r < 100 and g > 200 and b < 100) return Color.named(NamedColor.green);
                    if (r < 100 and g < 100 and b > 200) return Color.named(NamedColor.blue);
                    if (r > 200 and g > 200 and b < 100) return Color.named(NamedColor.yellow);
                    if (r > 200 and g < 100 and b > 200) return Color.named(NamedColor.magenta);
                    if (r < 100 and g > 200 and b > 200) return Color.named(NamedColor.cyan);
                    if (r > 200 and g > 200 and b > 200) return Color.named(NamedColor.white);
                    // For very dark colors, use default instead of black
                    if (r < 100 and g < 100 and b < 100) return Color.named(NamedColor.default); // Changed from .black to .default

                    return Color.named(NamedColor.default); // Fallback
                }
            },
            .named_color => color,
        };
    }

    /// Get fallback character for complex unicode
    pub fn bestChar(self: TerminalCapabilities, char: u21) u21 {
        if (self.unicode) return char;

        // Fallback mapping for box drawing characters when unicode not supported
        return switch (char) {
            '─' => '-',
            '│' => '|',
            '┌' => '+',
            '┐' => '+',
            '└' => '+',
            '┘' => '+',
            '├' => '+',
            '┤' => '+',
            '┬' => '+',
            '┴' => '+',
            '┼' => '+',
            '═' => '=',
            '║' => '|',
            '╔' => '+',
            '╗' => '+',
            '╚' => '+',
            '╝' => '+',
            '╠' => '+',
            '╣' => '+',
            '╦' => '+',
            '╩' => '+',
            '╬' => '+',
            '╭' => '+',
            '╮' => '+',
            '╯' => '+',
            '╰' => '+',
            '━' => '-',
            '┃' => '|',
            '┏' => '+',
            '┓' => '+',
            '┗' => '+',
            '┛' => '+',
            '▒' => '#',
            '░' => '.',
            '█' => '@',
            '▓' => '%',
            '■' => '#',
            '●' => 'O',
            '◆' => '*',
            '★' => '*',
            '☆' => '*',
            '⚠' => '!',
            '❌' => 'X',
            '✓' => 'v',
            '➜' => '>',
            else => char,
        };
    }

    /// Get style with unsupported features disabled
    pub fn bestStyle(self: TerminalCapabilities, style: Style) Style {
        var new_style = style;

        if (!self.italic) {
            new_style.italic = false;
        }

        if (!self.strikethrough) {
            new_style.strikethrough = false;
        }

        return new_style;
    }

    /// Measure a string respecting the terminal's width expectations.
    pub fn measure(self: TerminalCapabilities, text: []const u8) text_metrics.Metrics {
        _ = self; // reserved for future capability-aware adjustments
        return text_metrics.measureWidth(text);
    }
};

/// Renderer for drawing to the terminal
pub const Renderer = struct {
    /// Front buffer (currently displayed)
    front: Buffer,
    /// Back buffer (being prepared)
    back: Buffer,
    /// Allocator for renderer operations
    allocator: std.mem.Allocator,
    /// Current cursor position
    cursor_x: u16 = 0,
    cursor_y: u16 = 0,
    /// Whether the cursor is visible
    cursor_visible: bool = true,
    /// Terminal capabilities
    capabilities: TerminalCapabilities,

    /// Initialize a new renderer
    pub fn init(allocator: std.mem.Allocator, width: u16, height: u16) !Renderer {
        const front = try Buffer.init(allocator, width, height);
        const back = try Buffer.init(allocator, width, height);

        return Renderer{
            .front = front,
            .back = back,
            .allocator = allocator,
            .capabilities = TerminalCapabilities.detect(),
        };
    }

    /// Clean up renderer resources
    pub fn deinit(self: *Renderer) void {
        self.front.deinit();
        self.back.deinit();
    }

    /// Resize the buffers
    pub fn resize(self: *Renderer, width: u16, height: u16) !void {
        // Clean up old buffers
        self.front.deinit();
        self.back.deinit();

        // Create new buffers with the new size
        self.front = try Buffer.init(self.allocator, width, height);
        self.back = try Buffer.init(self.allocator, width, height);
    }

    /// Draw a character at the specified position with capability fallbacks
    pub fn drawChar(self: *Renderer, x: u16, y: u16, char: u21, fg: Color, bg: Color, style: Style) void {
        // Apply capability-based adjustments for graceful degradation
        const adjusted_char = self.capabilities.bestChar(char);
        const adjusted_fg = self.capabilities.bestColor(fg);
        const adjusted_bg = self.capabilities.bestColor(bg);
        const adjusted_style = self.capabilities.bestStyle(style);

        const cell = Cell.init(adjusted_char, adjusted_fg, adjusted_bg, adjusted_style);
        self.back.setCell(x, y, cell);
    }

    /// Draw a string at the specified position
    pub fn drawStr(self: *Renderer, x: u16, y: u16, str: []const u8, fg: Color, bg: Color, style: Style) void {
        var utf8_it = std.unicode.Utf8Iterator{
            .bytes = str,
            .i = 0,
        };

        var i: u16 = 0;
        while (utf8_it.nextCodepoint()) |codepoint| {
            if (x + i >= self.back.width) break;
            self.drawChar(x + i, y, codepoint, fg, bg, style);
            i += 1;
        }
    }

    /// Draw text that may include bidi/double-width content using sanitized output.
    pub fn drawSmartStr(self: *Renderer, x: u16, y: u16, str: []const u8, fg: Color, bg: Color, style: Style) void {
        const metrics = self.capabilities.measure(str);
        if (metrics.has_bidi and !self.capabilities.bidi) {
            const cleaned = text_metrics.sanitizeBidi(str, self.allocator) catch {
                self.drawStr(x, y, str, fg, bg, style);
                return;
            };
            defer self.allocator.free(cleaned);
            self.drawStr(x, y, cleaned, fg, bg, style);
            return;
        }

        self.drawStr(x, y, str, fg, bg, style);
    }

    /// Draw a box with the specified border style
    pub fn drawBox(self: *Renderer, x: u16, y: u16, width: u16, height: u16, border_style: BorderStyle, fg: Color, bg: Color, style: Style) void {
        if (width < 2 or height < 2) return;

        const chars = border_style.getChars();
        const top_left = chars[0];
        const top_right = chars[1];
        const bottom_left = chars[2];
        const bottom_right = chars[3];
        const horizontal = chars[4];
        const horizontal_bottom = chars[5];
        const vertical = chars[6];
        const vertical_right = chars[7];

        // Draw corners
        self.drawChar(x, y, top_left, fg, bg, style);
        self.drawChar(x + width - 1, y, top_right, fg, bg, style);
        self.drawChar(x, y + height - 1, bottom_left, fg, bg, style);
        self.drawChar(x + width - 1, y + height - 1, bottom_right, fg, bg, style);

        // Draw horizontal edges
        for (1..width - 1) |i| {
            self.drawChar(x + @as(u16, @intCast(i)), y, horizontal, fg, bg, style);
            self.drawChar(x + @as(u16, @intCast(i)), y + height - 1, horizontal_bottom, fg, bg, style);
        }

        // Draw vertical edges
        for (1..height - 1) |i| {
            self.drawChar(x, y + @as(u16, @intCast(i)), vertical, fg, bg, style);
            self.drawChar(x + width - 1, y + @as(u16, @intCast(i)), vertical_right, fg, bg, style);
        }
    }

    /// Draw a styled box with optional fill and shadow.
    pub fn drawStyledBox(self: *Renderer, x: u16, y: u16, width: u16, height: u16, box_style: BoxStyle) void {
        if (width == 0 or height == 0) return;

        // Fill background first so shadows sit underneath the border.
        self.fillRect(x, y, width, height, ' ', box_style.border_color, box_style.background, box_style.fill_style);

        if (box_style.shadow) |shadow| {
            const shade: u21 = if (shadow.soft) '░' else '▒';

            if (shadow.offset_x > 0) {
                const sx: u32 = @as(u32, x) + @as(u32, width) + @as(u32, shadow.offset_x) - 1;
                if (sx < self.back.width) {
                    const y_start: u32 = @as(u32, y) + @as(u32, shadow.offset_y);
                    if (y_start < self.back.height) {
                        self.fillRect(@intCast(sx), @intCast(y_start), 1, height, shade, shadow.color, shadow.color, Style{});
                    }
                }
            }

            if (shadow.offset_y > 0) {
                const sy: u32 = @as(u32, y) + @as(u32, height) + @as(u32, shadow.offset_y) - 1;
                if (sy < self.back.height) {
                    const start_x_u32: u32 = @as(u32, x) + @as(u32, shadow.offset_x);
                    if (start_x_u32 < self.back.width) {
                        const max_draw = @as(u32, self.back.width) - start_x_u32;
                        const desired = @as(u32, width) + @as(u32, shadow.offset_x);
                        const draw_width: u16 = @intCast(@min(max_draw, desired));
                        self.fillRect(@intCast(start_x_u32), @intCast(sy), draw_width, 1, shade, shadow.color, shadow.color, Style{});
                    }
                }
            }
        }

        self.drawBox(x, y, width, height, box_style.border, box_style.border_color, box_style.background, box_style.style);
    }

    /// Draw a horizontal line
    pub fn drawHLine(self: *Renderer, x: u16, y: u16, width: u16, line_char: u21, fg: Color, bg: Color, style: Style) void {
        for (0..width) |i| {
            if (x + @as(u16, @intCast(i)) >= self.back.width) break;
            self.drawChar(x + @as(u16, @intCast(i)), y, line_char, fg, bg, style);
        }
    }

    /// Draw a vertical line
    pub fn drawVLine(self: *Renderer, x: u16, y: u16, height: u16, line_char: u21, fg: Color, bg: Color, style: Style) void {
        for (0..height) |i| {
            if (y + @as(u16, @intCast(i)) >= self.back.height) break;
            self.drawChar(x, y + @as(u16, @intCast(i)), line_char, fg, bg, style);
        }
    }

    /// Fill a rectangular area
    pub fn fillRect(self: *Renderer, x: u16, y: u16, width: u16, height: u16, fill_char: u21, fg: Color, bg: Color, style: Style) void {
        const cell = Cell.init(fill_char, fg, bg, style);
        self.back.fillRect(x, y, width, height, cell);
    }

    /// Fill a rectangular area with a linear gradient background
    pub fn fillGradient(self: *Renderer, x: u16, y: u16, width: u16, height: u16, stops: []const GradientStop, direction: GradientDirection, style: Style) void {
        if (width == 0 or height == 0 or stops.len == 0) return;

        const sorted = copyAndSortStops(self.allocator, stops) catch return;
        defer self.allocator.free(sorted);

        const axis_len: u16 = if (direction == .horizontal) width else height;
        if (axis_len == 0) return;

        var idx: u16 = 0;
        while (idx < axis_len) : (idx += 1) {
            const denom: u16 = if (axis_len <= 1) 1 else axis_len - 1;
            const t = @as(f32, @floatFromInt(idx)) / @as(f32, @floatFromInt(denom));
            const rgb = sampleGradientColor(sorted, t);
            const bg = Color.rgb(rgb.r, rgb.g, rgb.b);

            if (direction == .horizontal) {
                var row: u16 = 0;
                while (row < height) : (row += 1) {
                    self.drawChar(x + idx, y + row, ' ', Color.named(NamedColor.default), bg, style);
                }
            } else {
                var col: u16 = 0;
                while (col < width) : (col += 1) {
                    self.drawChar(x + col, y + idx, ' ', Color.named(NamedColor.default), bg, style);
                }
            }
        }
    }

    /// Set cursor position
    pub fn setCursor(self: *Renderer, x: u16, y: u16) void {
        self.cursor_x = x;
        self.cursor_y = y;
    }

    /// Show or hide cursor
    pub fn showCursor(self: *Renderer, visible: bool) void {
        self.cursor_visible = visible;
    }

    /// Render the back buffer to the terminal
    pub fn render(self: *Renderer) !void {
        var stdout = std.fs.File.stdout();
        var style_buf = std.ArrayList(u8).empty;
        defer style_buf.deinit(self.allocator);

        // Hide cursor during rendering to prevent flicker
        try stdout.writeAll("\x1b[?25l");

        // Buffer for batched writes to reduce syscalls
        var output_buffer = std.ArrayList(u8).empty;
        defer output_buffer.deinit(self.allocator);

        var current_fg: ?Color = null;
        var current_bg: ?Color = null;
        var current_style = Style{};
        // Perform diff-based updates between front and back buffers
        for (0..self.back.height) |y| {
            for (0..self.back.width) |x| {
                const back_cell = self.back.getCell(@as(u16, @intCast(x)), @as(u16, @intCast(y)));
                const front_cell = self.front.getCell(@as(u16, @intCast(x)), @as(u16, @intCast(y)));

                // Skip if cell hasn't changed
                if (front_cell.eql(back_cell.*)) continue;

                // Position cursor
                try std.fmt.format(output_buffer.writer(self.allocator), "\x1b[{};{}H", .{ y + 1, x + 1 });

                // Update styles if needed
                var need_style_update = false;

                if (current_fg == null or !std.meta.eql(current_fg.?, back_cell.fg)) {
                    current_fg = back_cell.fg;
                    need_style_update = true;
                }

                if (current_bg == null or !std.meta.eql(current_bg.?, back_cell.bg)) {
                    current_bg = back_cell.bg;
                    need_style_update = true;
                }

                if (!std.meta.eql(current_style, back_cell.style)) {
                    current_style = back_cell.style;
                    need_style_update = true;
                }

                if (need_style_update) {
                    style_buf.clearRetainingCapacity();

                    try style_buf.appendSlice(self.allocator, "\x1b[");
                    const style_code = back_cell.style.toAnsi();
                    try style_buf.appendSlice(self.allocator, style_code.slice());

                    try style_buf.appendSlice(self.allocator, ";");
                    const fg_code = back_cell.fg.toFg();
                    try style_buf.appendSlice(self.allocator, fg_code.slice());

                    try style_buf.appendSlice(self.allocator, ";");
                    const bg_code = back_cell.bg.toBg();
                    try style_buf.appendSlice(self.allocator, bg_code.slice());

                    try style_buf.appendSlice(self.allocator, "m");

                    try output_buffer.appendSlice(self.allocator, style_buf.items);
                }

                var char_buf: [4]u8 = undefined;
                const len = try std.unicode.utf8Encode(back_cell.char, &char_buf);
                try output_buffer.appendSlice(self.allocator, char_buf[0..len]);

                if (output_buffer.items.len > 1024) {
                    stdout.writeAll(output_buffer.items) catch |err| {
                        if (err == error.WouldBlock) {
                            var retry_count: u8 = 0;
                            while (retry_count < 10) : (retry_count += 1) {
                                stdout.writeAll(output_buffer.items) catch |retry_err| {
                                    if (retry_err != error.WouldBlock) {
                                        return retry_err;
                                    }
                                    std.Thread.sleep(1 * std.time.ns_per_ms);
                                    continue;
                                };
                                break;
                            }
                        } else {
                            return err;
                        }
                    };
                    output_buffer.clearRetainingCapacity();
                }
            }
        }

        if (output_buffer.items.len > 0) {
            stdout.writeAll(output_buffer.items) catch |err| {
                if (err == error.WouldBlock) {
                    var retry_count: u8 = 0;
                    while (retry_count < 10) : (retry_count += 1) {
                        stdout.writeAll(output_buffer.items) catch |retry_err| {
                            if (retry_err != error.WouldBlock) {
                                return retry_err;
                            }
                            std.Thread.sleep(1 * std.time.ns_per_ms);
                            continue;
                        };
                        break;
                    }
                } else {
                    return err;
                }
            };
        }

        stdout.writeAll("\x1b[0m") catch |err| {
            if (err != error.WouldBlock) return err;
        };

        var cursor_buf: [32]u8 = undefined;
        const cursor_seq = try std.fmt.bufPrint(&cursor_buf, "\x1b[{};{}H", .{ self.cursor_y + 1, self.cursor_x + 1 });
        stdout.writeAll(cursor_seq) catch |err| {
            if (err != error.WouldBlock) return err;
        };
        if (self.cursor_visible) {
            stdout.writeAll("\x1b[?25h") catch |err| {
                if (err != error.WouldBlock) return err;
            };
        }

        // Swap buffers
        const temp = self.front;
        self.front = self.back;
        self.back = temp;
    }
};

test "renderer draws box outlines" {
    const alloc = std.testing.allocator;
    var renderer = try Renderer.init(alloc, 8, 4);
    defer renderer.deinit();

    renderer.capabilities.unicode = true;
    renderer.drawBox(0, 0, 8, 4, BorderStyle.double, Color.named(NamedColor.white), Color.named(NamedColor.black), Style{});

    try std.testing.expectEqual(@as(u21, '╔'), renderer.back.getCell(0, 0).char);
    try std.testing.expectEqual(@as(u21, '╝'), renderer.back.getCell(7, 3).char);
    try std.testing.expectEqual(@as(u21, '═'), renderer.back.getCell(3, 0).char);
    try std.testing.expectEqual(@as(u21, '║'), renderer.back.getCell(0, 2).char);
}

test "styled box paints drop shadow" {
    const alloc = std.testing.allocator;
    var renderer = try Renderer.init(alloc, 12, 6);
    defer renderer.deinit();

    renderer.capabilities.unicode = true;
    const style = BoxStyle{
        .border = BorderStyle.rounded,
        .border_color = Color.named(NamedColor.white),
        .background = Color.named(NamedColor.black),
        .shadow = ShadowStyle{
            .offset_x = 1,
            .offset_y = 1,
            .color = Color.named(NamedColor.bright_black),
            .soft = true,
        },
    };

    renderer.drawStyledBox(1, 1, 6, 3, style);

    const right_shadow = renderer.back.getCell(1 + 6, 1 + 1).*;
    try std.testing.expectEqual(@as(u21, '░'), right_shadow.char);

    const bottom_shadow = renderer.back.getCell(1 + 1, 1 + 3).*;
    try std.testing.expectEqual(@as(u21, '░'), bottom_shadow.char);
}

test "fillGradient paints interpolated colors" {
    const alloc = std.testing.allocator;
    var renderer = try Renderer.init(alloc, 4, 2);
    defer renderer.deinit();

    const stops = [_]GradientStop{
        GradientStop{ .position = 0.0, .color = Color.rgb(0, 0, 0) },
        GradientStop{ .position = 1.0, .color = Color.rgb(255, 0, 0) },
    };

    renderer.capabilities.rgb_colors = true;
    renderer.capabilities.colors_256 = true;
    renderer.capabilities.unicode = true;
    renderer.fillGradient(0, 0, 4, 1, &stops, GradientDirection.horizontal, Style{});

    const first = renderer.back.getCell(0, 0).bg;
    const second = renderer.back.getCell(1, 0).bg;
    const third = renderer.back.getCell(2, 0).bg;
    const fourth = renderer.back.getCell(3, 0).bg;

    try std.testing.expect(std.meta.eql(first, Color.rgb(0, 0, 0)));
    try std.testing.expect(std.meta.eql(second, Color.rgb(85, 0, 0)));
    try std.testing.expect(std.meta.eql(third, Color.rgb(170, 0, 0)));
    try std.testing.expect(std.meta.eql(fourth, Color.rgb(255, 0, 0)));

    var vertical_renderer = try Renderer.init(alloc, 1, 2);
    defer vertical_renderer.deinit();
    vertical_renderer.capabilities.rgb_colors = true;
    vertical_renderer.capabilities.colors_256 = true;
    vertical_renderer.capabilities.unicode = true;
    vertical_renderer.fillGradient(0, 0, 1, 2, &stops, GradientDirection.vertical, Style{});

    const top = vertical_renderer.back.getCell(0, 0).bg;
    const bottom = vertical_renderer.back.getCell(0, 1).bg;
    try std.testing.expect(std.meta.eql(top, Color.rgb(0, 0, 0)));
    try std.testing.expect(std.meta.eql(bottom, Color.rgb(255, 0, 0)));
}

test "ansi helpers produce stable sequences" {
    const fg = Color.rgb(1, 2, 3).toFg();
    try std.testing.expectEqualStrings("38;2;1;2;3", fg.slice());

    const bg = Color.named(NamedColor.bright_white).toBg();
    try std.testing.expectEqualStrings("107", bg.slice());

    const style = (Style{ .bold = true, .underline = true }).toAnsi();
    try std.testing.expectEqualStrings("1;4", style.slice());
}
