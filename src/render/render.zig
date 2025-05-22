const std = @import("std");

/// Output rendering module
///
/// This module provides functionality for rendering to the terminal:
/// - Screen buffer management
/// - Text styling with ANSI escape codes
/// - Efficient rendering with double buffering
/// - Unicode support
/// - Drawing primitives for UI elements

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
    pub fn toAnsi(self: RgbColor, is_bg: bool) []const u8 {
        var result: [20]u8 = undefined;
        const prefix = if (is_bg) "48" else "38";
        
        // Format directly to the result buffer
        const len = std.fmt.bufPrint(
            &result,
            "{s};2;{d};{d};{d}",
            .{ prefix, self.r, self.g, self.b }
        ) catch {
            if (is_bg) {
                return NamedColor.default.toBg();
            } else {
                return NamedColor.default.toFg();
            }
        };
        
        return result[0..len.len];
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
    pub fn toFg(self: Color) []const u8 {
        return switch (self) {
            .named_color => |c| c.toFg(),
            .rgb_color => |c| c.toAnsi(false),
        };
    }

    /// Convert to background color code
    pub fn toBg(self: Color) []const u8 {
        return switch (self) {
            .named_color => |c| c.toBg(),
            .rgb_color => |c| c.toAnsi(true),
        };
    }
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
    pub fn toFg(self: NamedColor) []const u8 {
        return switch (self) {
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
        };
    }
    
    /// Convert to background color code
    pub fn toBg(self: NamedColor) []const u8 {
        return switch (self) {
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
        };
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
    
    /// Convert to ANSI style codes
    pub fn toAnsi(self: Style, allocator: std.mem.Allocator) ![]const u8 {
        var codes = std.ArrayList(u8).init(allocator);
        defer codes.deinit();
        
        if (self.bold) {
            try codes.appendSlice("1;");
        }
        
        if (self.italic) {
            try codes.appendSlice("3;");
        }
        
        if (self.underline) {
            try codes.appendSlice("4;");
        }

        if (self.blink) {
            try codes.appendSlice("5;");
        }

        if (self.reverse) {
            try codes.appendSlice("7;");
        }

        if (self.strikethrough) {
            try codes.appendSlice("9;");
        }
        
        if (codes.items.len > 0) {
            // Remove trailing semicolon
            return try allocator.dupe(u8, codes.items[0 .. codes.items.len - 1]);
        } else {
            return try allocator.dupe(u8, "0");
        }
    }
};

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
            .none => [_]u21{' ', ' ', ' ', ' ', ' ', ' ', ' ', ' '},
            .single => [_]u21{'┌', '┐', '└', '┘', '─', '─', '│', '│'},
            .double => [_]u21{'╔', '╗', '╚', '╝', '═', '═', '║', '║'},
            .rounded => [_]u21{'╭', '╮', '╰', '╯', '─', '─', '│', '│'},
            .thick => [_]u21{'┏', '┓', '┗', '┛', '━', '━', '┃', '┃'},
        };
    }
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
            std.mem.indexOf(u8, term, "alacritty") != null) {
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
                    colorterm[i+1] == 'r' and
                    colorterm[i+2] == 'u' and
                    colorterm[i+3] == 'e' and
                    colorterm[i+4] == 'c' and
                    colorterm[i+5] == 'o' and
                    colorterm[i+6] == 'l' and
                    colorterm[i+7] == 'o' and
                    colorterm[i+8] == 'r') {
                    has_truecolor = true;
                    break;
                }
                
                if (i + 4 <= colorterm_len and 
                    colorterm[i] == '2' and
                    colorterm[i+1] == '4' and
                    colorterm[i+2] == 'b' and
                    colorterm[i+3] == 'i' and
                    colorterm[i+4] == 't') {
                    has_truecolor = true;
                    break;
                }
            }
            
            if (has_truecolor) {
                caps.rgb_colors = true;
            }
        }
        
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

    /// Draw a box with the specified border style
    pub fn drawBox(self: *Renderer, x: u16, y: u16, width: u16, height: u16, 
                  border_style: BorderStyle, fg: Color, bg: Color, style: Style) void {
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

    /// Draw a horizontal line
    pub fn drawHLine(self: *Renderer, x: u16, y: u16, width: u16, 
                    line_char: u21, fg: Color, bg: Color, style: Style) void {
        for (0..width) |i| {
            if (x + @as(u16, @intCast(i)) >= self.back.width) break;
            self.drawChar(x + @as(u16, @intCast(i)), y, line_char, fg, bg, style);
        }
    }

    /// Draw a vertical line
    pub fn drawVLine(self: *Renderer, x: u16, y: u16, height: u16, 
                    line_char: u21, fg: Color, bg: Color, style: Style) void {
        for (0..height) |i| {
            if (y + @as(u16, @intCast(i)) >= self.back.height) break;
            self.drawChar(x, y + @as(u16, @intCast(i)), line_char, fg, bg, style);
        }
    }

    /// Fill a rectangular area
    pub fn fillRect(self: *Renderer, x: u16, y: u16, width: u16, height: u16, 
                   fill_char: u21, fg: Color, bg: Color, style: Style) void {
        const cell = Cell.init(fill_char, fg, bg, style);
        self.back.fillRect(x, y, width, height, cell);
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
        const writer = std.io.getStdOut().writer();
        var style_buf = std.ArrayList(u8).init(self.allocator);
        defer style_buf.deinit();
        
        // Hide cursor during rendering to prevent flicker
        try writer.writeAll("\x1b[?25l");
        
        // Buffer for batched writes to reduce syscalls
        var output_buffer = std.ArrayList(u8).init(self.allocator);
        defer output_buffer.deinit();
        
        var current_fg: ?Color = null;
        var current_bg: ?Color = null;
        var current_style = Style{};
        var style_str: []const u8 = "0";
        var style_str_owned = false;
        defer if (style_str_owned) self.allocator.free(style_str);
        
        // Perform diff-based updates between front and back buffers
        for (0..self.back.height) |y| {
            for (0..self.back.width) |x| {
                const back_cell = self.back.getCell(@as(u16, @intCast(x)), @as(u16, @intCast(y)));
                const front_cell = self.front.getCell(@as(u16, @intCast(x)), @as(u16, @intCast(y)));
                
                // Skip if cell hasn't changed
                if (front_cell.eql(back_cell.*)) continue;
                
                // Position cursor
                try std.fmt.format(output_buffer.writer(), "\x1b[{};{}H", .{ y + 1, x + 1 });
                
                // Update styles if needed
                var need_style_update = false;
                
                // Check if foreground color changed
                if (current_fg == null or !std.meta.eql(current_fg.?, back_cell.fg)) {
                    current_fg = back_cell.fg;
                    need_style_update = true;
                }
                
                // Check if background color changed
                if (current_bg == null or !std.meta.eql(current_bg.?, back_cell.bg)) {
                    current_bg = back_cell.bg;
                    need_style_update = true;
                }
                
                // Check if style attributes changed
                if (!std.meta.eql(current_style, back_cell.style)) {
                    current_style = back_cell.style;
                    need_style_update = true;
                }
                
                // Apply style changes if needed
                if (need_style_update) {
                    style_buf.clearRetainingCapacity();
                    
                    // Start SGR sequence
                    try style_buf.appendSlice("\x1b[");
                    
                    // Get style attributes
                    if (style_str_owned) {
                        self.allocator.free(style_str);
                        style_str_owned = false;
                    }
                    style_str = try back_cell.style.toAnsi(self.allocator);
                    style_str_owned = true;
                    try style_buf.appendSlice(style_str);
                    
                    // Add foreground color
                    try style_buf.appendSlice(";");
                    try style_buf.appendSlice(back_cell.fg.toFg());
                    
                    // Add background color
                    try style_buf.appendSlice(";");
                    try style_buf.appendSlice(back_cell.bg.toBg());
                    
                    // End SGR sequence
                    try style_buf.appendSlice("m");
                    
                    // Add to output buffer
                    try output_buffer.appendSlice(style_buf.items);
                }
                
                // Write the character (supporting Unicode)
                var char_buf: [4]u8 = undefined;
                const len = try std.unicode.utf8Encode(back_cell.char, &char_buf);
                try output_buffer.appendSlice(char_buf[0..len]);
                
                // If buffer is getting large, flush it to reduce memory usage
                if (output_buffer.items.len > 1024) {
                    writer.writeAll(output_buffer.items) catch |err| {
                        if (err == error.WouldBlock) {
                            // If output would block, keep trying (with a reasonable limit)
                            var retry_count: u8 = 0;
                            while (retry_count < 10) : (retry_count += 1) {
                                writer.writeAll(output_buffer.items) catch |retry_err| {
                                    if (retry_err != error.WouldBlock) {
                                        return retry_err;
                                    }
                                    // Small delay before retry
                                    std.time.sleep(1 * std.time.ns_per_ms);
                                    continue;
                                };
                                break; // Success
                            }
                        } else {
                            return err;
                        }
                    };
                    output_buffer.clearRetainingCapacity();
                }
            }
        }
        
        // Flush any remaining output
        if (output_buffer.items.len > 0) {
            writer.writeAll(output_buffer.items) catch |err| {
                if (err == error.WouldBlock) {
                    // If output would block, keep trying (with a reasonable limit)
                    var retry_count: u8 = 0;
                    while (retry_count < 10) : (retry_count += 1) {
                        writer.writeAll(output_buffer.items) catch |retry_err| {
                            if (retry_err != error.WouldBlock) {
                                return retry_err;
                            }
                            // Small delay before retry
                            std.time.sleep(1 * std.time.ns_per_ms);
                            continue;
                        };
                        break; // Success
                    }
                } else {
                    return err;
                }
            };
        }
        
        // Reset styles
        writer.writeAll("\x1b[0m") catch |err| {
            if (err != error.WouldBlock) return err;
        };
        
        // Position and show/hide cursor as needed
        std.fmt.format(writer, "\x1b[{};{}H", .{ self.cursor_y + 1, self.cursor_x + 1 }) catch |err| {
            if (err != error.WouldBlock) return err;
        };
        if (self.cursor_visible) {
            writer.writeAll("\x1b[?25h") catch |err| {
                if (err != error.WouldBlock) return err;
            };
        }
        
        // Swap buffers
        const temp = self.front;
        self.front = self.back;
        self.back = temp;
    }
};