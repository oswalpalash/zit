const std = @import("std");
const text_metrics = @import("text_metrics.zig");
const term_caps = @import("../terminal/capabilities.zig");

fn validateColorComponent(value: anytype, comptime label: []const u8) u8 {
    if (@TypeOf(value) == comptime_int) {
        if (value < 0 or value > 255) {
            const msg = std.fmt.comptimePrint("zit: color component {s} must be between 0 and 255", .{label});
            @compileError(msg);
        }
        return @intCast(value);
    }
    if (@TypeOf(value) == comptime_float) {
        if (value < 0 or value > 255) {
            const msg = std.fmt.comptimePrint("zit: color component {s} must be between 0 and 255", .{label});
            @compileError(msg);
        }
        return @intFromFloat(value);
    }

    return std.math.cast(u8, value) orelse std.debug.panic("zit: color component {s} must be between 0 and 255 (got {any})", .{ label, value });
}

fn validateAnsiIndex(value: anytype) u8 {
    if (@TypeOf(value) == comptime_int) {
        if (value < 0 or value > 255) {
            @compileError("zit: ANSI 256-color index must be between 0 and 255");
        }
        return @intCast(value);
    }
    if (@TypeOf(value) == comptime_float) {
        if (value < 0 or value > 255) {
            @compileError("zit: ANSI 256-color index must be between 0 and 255");
        }
        return @intFromFloat(value);
    }

    return std.math.cast(u8, value) orelse std.debug.panic("zit: ANSI 256-color index must be between 0 and 255 (got {any})", .{value});
}

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
    pub fn init(r: anytype, g: anytype, b: anytype) RgbColor {
        return RgbColor{
            .r = validateColorComponent(r, "r"),
            .g = validateColorComponent(g, "g"),
            .b = validateColorComponent(b, "b"),
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
    ansi_256: u8,

    /// Create a new named color
    pub fn named(color: NamedColor) Color {
        return Color{ .named_color = color };
    }

    /// Create a new RGB color
    pub fn rgb(r: anytype, g: anytype, b: anytype) Color {
        return Color{ .rgb_color = RgbColor.init(r, g, b) };
    }

    /// Create a 256-color palette entry
    pub fn ansi256(index: anytype) Color {
        return Color{ .ansi_256 = validateAnsiIndex(index) };
    }

    /// Convert to foreground color code
    pub fn toFg(self: Color) AnsiCode {
        return switch (self) {
            .named_color => |c| c.toFg(),
            .rgb_color => |c| c.toAnsi(false),
            .ansi_256 => |idx| ansi256ToAnsi(idx, false),
        };
    }

    /// Convert to background color code
    pub fn toBg(self: Color) AnsiCode {
        return switch (self) {
            .named_color => |c| c.toBg(),
            .rgb_color => |c| c.toAnsi(true),
            .ansi_256 => |idx| ansi256ToAnsi(idx, true),
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

const color_cube_levels = [_]u8{ 0, 95, 135, 175, 215, 255 };
const base16_palette = [_]NamedColor{
    .black,
    .red,
    .green,
    .yellow,
    .blue,
    .magenta,
    .cyan,
    .white,
    .bright_black,
    .bright_red,
    .bright_green,
    .bright_yellow,
    .bright_blue,
    .bright_magenta,
    .bright_cyan,
    .bright_white,
};

fn namedColorToRgb(named: NamedColor) RgbColor {
    return switch (named) {
        .black => RgbColor.init(0, 0, 0),
        .red => RgbColor.init(205, 0, 0),
        .green => RgbColor.init(0, 205, 0),
        .yellow => RgbColor.init(205, 205, 0),
        .blue => RgbColor.init(0, 0, 238),
        .magenta => RgbColor.init(205, 0, 205),
        .cyan => RgbColor.init(0, 205, 205),
        .white => RgbColor.init(229, 229, 229),
        .default => RgbColor.init(0, 0, 0),
        .bright_black => RgbColor.init(102, 102, 102),
        .bright_red => RgbColor.init(255, 0, 0),
        .bright_green => RgbColor.init(0, 255, 0),
        .bright_yellow => RgbColor.init(255, 255, 0),
        .bright_blue => RgbColor.init(92, 92, 255),
        .bright_magenta => RgbColor.init(255, 0, 255),
        .bright_cyan => RgbColor.init(0, 255, 255),
        .bright_white => RgbColor.init(255, 255, 255),
    };
}

fn colorDistanceSquared(a: RgbColor, b: RgbColor) u32 {
    const dr = @as(i32, a.r) - @as(i32, b.r);
    const dg = @as(i32, a.g) - @as(i32, b.g);
    const db = @as(i32, a.b) - @as(i32, b.b);
    return @intCast((dr * dr) + (dg * dg) + (db * db));
}

fn componentToIndex(value: u8) u8 {
    if (value < 48) return 0;
    if (value > 248) return 5;
    return @intCast((@as(u16, value) - 35) / 40);
}

fn componentToValue(idx: u8) u8 {
    return color_cube_levels[idx];
}

fn grayscaleIndex(value: u8) u8 {
    if (value < 8) return 0;
    if (value > 238) return 23;
    return @intCast((@as(u16, value) - 8) / 10);
}

fn rgbToAnsi256(rgb: RgbColor) u8 {
    const r_idx = componentToIndex(rgb.r);
    const g_idx = componentToIndex(rgb.g);
    const b_idx = componentToIndex(rgb.b);

    const cube = RgbColor.init(componentToValue(r_idx), componentToValue(g_idx), componentToValue(b_idx));
    const cube_index: u8 = @intCast(16 + (36 * r_idx) + (6 * g_idx) + b_idx);
    const avg = (@as(u32, rgb.r) + @as(u32, rgb.g) + @as(u32, rgb.b)) / 3;
    const gray_level = grayscaleIndex(@intCast(avg));
    const gray_value: u8 = @intCast(8 + gray_level * 10);
    const gray_rgb = RgbColor.init(gray_value, gray_value, gray_value);
    const gray_index: u8 = @intCast(232 + gray_level);

    const cube_dist = colorDistanceSquared(rgb, cube);
    const gray_dist = colorDistanceSquared(rgb, gray_rgb);

    return if (gray_dist < cube_dist) gray_index else cube_index;
}

fn ansi256ToRgb(index: u8) RgbColor {
    if (index < 16) {
        return namedColorToRgb(base16_palette[index]);
    }

    if (index >= 232) {
        const level: u8 = @intCast(8 + (index - 232) * 10);
        return RgbColor.init(level, level, level);
    }

    const idx = index - 16;
    const r_idx = idx / 36;
    const g_idx = (idx / 6) % 6;
    const b_idx = idx % 6;

    return RgbColor.init(
        componentToValue(r_idx),
        componentToValue(g_idx),
        componentToValue(b_idx),
    );
}

fn ansi256ToAnsi(index: u8, is_bg: bool) AnsiCode {
    var result: [16]u8 = undefined;
    const written = (if (is_bg)
        std.fmt.bufPrint(&result, "48;5;{d}", .{index})
    else
        std.fmt.bufPrint(&result, "38;5;{d}", .{index})) catch {
        return if (is_bg) NamedColor.default.toBg() else NamedColor.default.toFg();
    };

    return AnsiCode.fromSlice(written);
}

fn closestNamedColor(rgb: RgbColor) NamedColor {
    var best = NamedColor.black;
    var best_distance: u32 = std.math.maxInt(u32);
    for (base16_palette) |named| {
        const dist = colorDistanceSquared(rgb, namedColorToRgb(named));
        if (dist < best_distance) {
            best_distance = dist;
            best = named;
        }
    }
    return best;
}

fn colorsEqual(lhs: Color, rhs: Color) bool {
    return switch (lhs) {
        .named_color => |ln| switch (rhs) {
            .named_color => |rn| ln == rn,
            else => false,
        },
        .rgb_color => |lr| switch (rhs) {
            .rgb_color => |rr| lr.r == rr.r and lr.g == rr.g and lr.b == rr.b,
            else => false,
        },
        .ansi_256 => |li| switch (rhs) {
            .ansi_256 => |ri| li == ri,
            else => false,
        },
    };
}

pub fn colorToRgb(color: Color) RgbColor {
    return switch (color) {
        .rgb_color => |rgb| rgb,
        .ansi_256 => |idx| ansi256ToRgb(idx),
        .named_color => |named| namedColorToRgb(named),
    };
}

/// Linearly blend two colors, clamping the factor between 0 and 1.
pub fn mixColor(start: Color, end: Color, t_in: f32) Color {
    const t = std.math.clamp(t_in, 0, 1);
    const blended = lerpColor(colorToRgb(start), colorToRgb(end), t);
    return Color.rgb(blended.r, blended.g, blended.b);
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

    for (buffer) |stop| {
        if (stop.position < 0 or stop.position > 1) {
            std.debug.panic("zit: gradient stop positions must be between 0 and 1 (got {any})", .{stop.position});
        }
        if (std.math.isNan(stop.position)) {
            std.debug.panic("zit: gradient stop positions cannot be NaN", .{});
        }
    }

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

fn saturatingAddU16(a: u16, b: u16) u16 {
    const sum = std.math.add(u32, a, b) catch std.math.maxInt(u32);
    return @intCast(@min(sum, std.math.maxInt(u16)));
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

        if (!colorsEqual(self.fg, other.fg)) return false;
        if (!colorsEqual(self.bg, other.bg)) return false;

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
        const cell_count = std.math.mul(usize, @as(usize, width), @as(usize, height)) catch {
            return error.InvalidBufferDimensions;
        };
        const cells = try allocator.alloc(Cell, cell_count);

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
    pub fn deinit(self: *const Buffer) void {
        self.allocator.free(self.cells);
    }

    /// Get cell at specified coordinates
    pub fn getCell(self: *Buffer, x: u16, y: u16) *Cell {
        if (self.cells.len == 0) {
            std.debug.panic("zit: attempted to access a cell in an uninitialized buffer", .{});
        }
        if (x >= self.width or y >= self.height) {
            std.debug.assert(false);
            return &self.cells[0];
        }
        const idx = self.cellIndex(x, y);
        return &self.cells[idx];
    }

    /// Set cell at specified coordinates
    pub fn setCell(self: *Buffer, x: u16, y: u16, cell: Cell) void {
        if (self.cells.len == 0) {
            std.debug.assert(false);
            return;
        }
        if (x >= self.width or y >= self.height) {
            std.debug.assert(false);
            return; // Out of bounds
        }

        const idx = self.cellIndex(x, y);
        self.cells[idx] = cell;
    }

    /// Clear the buffer
    pub fn clear(self: *Buffer) void {
        for (self.cells) |*cell| {
            cell.* = Cell{};
        }
    }

    /// Fill a rectangular area with a specific cell
    pub fn fillRect(self: *Buffer, x: u16, y: u16, width: u16, height: u16, cell: Cell) void {
        const max_x = @min(saturatingAddU16(x, width), self.width);
        const max_y = @min(saturatingAddU16(y, height), self.height);

        var cy = y;
        while (cy < max_y) : (cy += 1) {
            var cx = x;
            while (cx < max_x) : (cx += 1) {
                self.setCell(cx, cy, cell);
            }
        }
    }

    fn cellIndex(self: *Buffer, x: u16, y: u16) usize {
        const stride = std.math.mul(usize, @as(usize, self.width), @as(usize, y)) catch {
            std.debug.panic("zit: buffer row stride overflow for {d}x{d}", .{ self.width, self.height });
        };
        const offset = std.math.add(usize, stride, @as(usize, x)) catch {
            std.debug.panic("zit: buffer index overflow for {d}x{d}", .{ self.width, self.height });
        };
        return offset;
    }
};

const DirtyRow = struct {
    min_x: u16,
    max_x: u16,
    dirty: bool,
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

/// Visual treatment for focused widgets.
pub const FocusRingStyle = struct {
    color: Color = Color.named(NamedColor.cyan),
    style: Style = Style{ .bold = true },
    border: BorderStyle = .rounded,
    /// Shrink the ring inward by this amount on each edge.
    inset: u16 = 0,
    /// Optional highlight fill behind the ring.
    fill: ?Color = null,
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
    /// Terminal understands the Kitty keyboard protocol
    kitty_keyboard: bool = false,
    /// Kitty graphics/extended escapes are accepted
    kitty_graphics: bool = false,
    /// iTerm2 proprietary extensions are supported
    iterm2_integration: bool = false,
    /// DEC 2026 synchronized output mode supported
    synchronized_output: bool = false,
    /// Identified terminal program
    program: term_caps.TerminalProgram = .unknown,
    /// Negotiated color depth
    color_level: term_caps.ColorLevel = .ansi16,

    /// Create default capabilities (conservative defaults)
    pub fn init() TerminalCapabilities {
        return TerminalCapabilities{};
    }

    /// Detect capabilities from environment hints.
    pub fn detect() TerminalCapabilities {
        return TerminalCapabilities.fromSurvey(term_caps.detect());
    }

    pub fn detectWithAllocator(allocator: std.mem.Allocator) TerminalCapabilities {
        return TerminalCapabilities.fromSurvey(term_caps.detectWithAllocator(allocator));
    }

    pub fn detectFromEnv(env: term_caps.Environment) TerminalCapabilities {
        return TerminalCapabilities.fromSurvey(term_caps.detectFrom(env));
    }

    fn fromSurvey(survey: term_caps.CapabilityFlags) TerminalCapabilities {
        var caps = TerminalCapabilities{};
        caps.rgb_colors = survey.rgb_colors;
        caps.colors_256 = survey.colors_256 or survey.rgb_colors;
        caps.italic = survey.italic;
        caps.unicode = survey.unicode;
        caps.underline = survey.underline;
        caps.strikethrough = survey.strikethrough;
        caps.emoji = survey.emoji;
        caps.ligatures = survey.ligatures;
        caps.double_width = survey.double_width;
        caps.bidi = survey.bidi;
        caps.kitty_keyboard = survey.kitty_keyboard;
        caps.kitty_graphics = survey.kitty_graphics;
        caps.iterm2_integration = survey.iterm2_integration;
        caps.synchronized_output = survey.synchronized_output;
        caps.program = survey.program;
        caps.color_level = survey.color_level;
        return caps;
    }

    /// Get the best available color for the given color
    pub fn bestColor(self: TerminalCapabilities, color: Color) Color {
        return switch (color) {
            .rgb_color => |rgb| bestColorFromRgb(self, rgb),
            .ansi_256 => |idx| {
                if (self.rgb_colors) {
                    const rgb = ansi256ToRgb(idx);
                    return Color.rgb(rgb.r, rgb.g, rgb.b);
                }
                if (self.colors_256) return color;
                return Color.named(closestNamedColor(ansi256ToRgb(idx)));
            },
            .named_color => color,
        };
    }

    fn bestColorFromRgb(caps: TerminalCapabilities, rgb: RgbColor) Color {
        if (caps.rgb_colors) return Color.rgb(rgb.r, rgb.g, rgb.b);
        const idx = rgbToAnsi256(rgb);
        if (caps.colors_256) return Color.ansi256(idx);
        return Color.named(closestNamedColor(rgb));
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
    /// Last cursor state for detecting changes
    last_cursor_x: u16 = 0,
    last_cursor_y: u16 = 0,
    last_cursor_visible: bool = true,
    /// Dirty region tracking (inclusive bounds)
    dirty_min_x: u16 = 0,
    dirty_min_y: u16 = 0,
    dirty_max_x: u16 = 0,
    dirty_max_y: u16 = 0,
    has_dirty: bool = false,
    cursor_dirty: bool = true,
    dirty_rows: []DirtyRow = &.{},
    /// Terminal capabilities
    capabilities: TerminalCapabilities,
    /// Reusable scratch buffers to minimize per-frame allocations
    style_scratch: std.ArrayListUnmanaged(u8) = .{},
    output_batch: std.ArrayListUnmanaged(u8) = .{},

    /// Initialize a new renderer
    pub fn init(allocator: std.mem.Allocator, width: u16, height: u16) !Renderer {
        const front = try Buffer.init(allocator, width, height);
        errdefer front.deinit();
        const back = try Buffer.init(allocator, width, height);
        errdefer back.deinit();
        const dirty_rows = try allocator.alloc(DirtyRow, height);
        errdefer allocator.free(dirty_rows);

        var renderer = Renderer{
            .front = front,
            .back = back,
            .allocator = allocator,
            .dirty_rows = dirty_rows,
            .capabilities = TerminalCapabilities.detect(),
        };
        renderer.resetDirty();
        renderer.primeBuffers();
        return renderer;
    }

    /// Clean up renderer resources
    pub fn deinit(self: *Renderer) void {
        self.front.deinit();
        self.back.deinit();
        if (self.dirty_rows.len > 0) self.allocator.free(self.dirty_rows);
        self.style_scratch.deinit(self.allocator);
        self.output_batch.deinit(self.allocator);
    }

    /// Resize the buffers
    pub fn resize(self: *Renderer, width: u16, height: u16) !void {
        const new_front = try Buffer.init(self.allocator, width, height);
        errdefer new_front.deinit();
        const new_back = try Buffer.init(self.allocator, width, height);
        errdefer new_back.deinit();
        const new_dirty_rows = try self.allocator.alloc(DirtyRow, height);
        errdefer self.allocator.free(new_dirty_rows);

        self.front.deinit();
        self.back.deinit();
        if (self.dirty_rows.len > 0) self.allocator.free(self.dirty_rows);
        self.front = new_front;
        self.back = new_back;
        self.dirty_rows = new_dirty_rows;
        self.resetDirty();
        self.markDirtyRect(0, 0, width, height);
        self.primeBuffers();
    }

    fn resetDirtyRows(self: *Renderer) void {
        if (self.dirty_rows.len == 0) return;
        for (self.dirty_rows) |*row| {
            row.* = DirtyRow{ .min_x = self.back.width, .max_x = 0, .dirty = false };
        }
    }

    fn primeBuffers(self: *Renderer) void {
        const est_cells = std.math.mul(u64, self.back.width, self.back.height) catch 0;
        const estimated_bytes = std.math.mul(u64, est_cells, 8) catch std.math.maxInt(u64);
        const desired_bytes: u64 = @min(estimated_bytes, 512 * 1024);
        if (desired_bytes > 0 and desired_bytes <= std.math.maxInt(usize)) {
            self.output_batch.ensureTotalCapacity(self.allocator, @intCast(desired_bytes)) catch {};
        }
        self.style_scratch.ensureTotalCapacity(self.allocator, 64) catch {};
    }

    fn resetDirty(self: *Renderer) void {
        self.dirty_min_x = self.back.width;
        self.dirty_min_y = self.back.height;
        self.dirty_max_x = 0;
        self.dirty_max_y = 0;
        self.has_dirty = false;
        self.cursor_dirty = false;
        self.resetDirtyRows();
    }

    fn markDirtyRect(self: *Renderer, x: u16, y: u16, width: u16, height: u16) void {
        if (width == 0 or height == 0 or self.back.width == 0 or self.back.height == 0) return;
        const x_end = saturatingAddU16(x, width - 1);
        const y_end = saturatingAddU16(y, height - 1);
        const max_x = @min(x_end, self.back.width - 1);
        const max_y = @min(y_end, self.back.height - 1);
        self.dirty_min_x = @min(self.dirty_min_x, x);
        self.dirty_min_y = @min(self.dirty_min_y, y);
        self.dirty_max_x = @max(self.dirty_max_x, max_x);
        self.dirty_max_y = @max(self.dirty_max_y, max_y);
        self.has_dirty = true;

        if (self.dirty_rows.len == 0) return;
        const max_row: usize = max_y;
        var row_idx: usize = @intCast(y);
        while (row_idx <= max_row and row_idx < self.dirty_rows.len) : (row_idx += 1) {
            const target = &self.dirty_rows[row_idx];
            if (!target.dirty) {
                target.* = DirtyRow{ .min_x = x, .max_x = max_x, .dirty = true };
            } else {
                target.min_x = @min(target.min_x, x);
                target.max_x = @max(target.max_x, max_x);
            }
        }
    }

    fn writeAllGeneric(writer: anytype, data: []const u8) !void {
        var remaining = data;
        while (remaining.len > 0) {
            const written = try writer.write(remaining);
            remaining = remaining[written..];
        }
    }

    fn flushOutput(self: *Renderer, writer: anytype) !void {
        if (self.output_batch.items.len == 0) return;
        try writeAllGeneric(writer, self.output_batch.items);
        self.output_batch.clearRetainingCapacity();
    }

    fn appendCursorMove(self: *Renderer, x: u16, y: u16) !void {
        var cursor_buf: [32]u8 = undefined;
        const cursor_seq = try std.fmt.bufPrint(&cursor_buf, "\x1b[{};{}H", .{ @as(u32, y) + 1, @as(u32, x) + 1 });
        try self.output_batch.appendSlice(self.allocator, cursor_seq);
    }

    /// Draw a character at the specified position with capability fallbacks
    pub fn drawChar(self: *Renderer, x: u16, y: u16, char: u21, fg: Color, bg: Color, style: Style) void {
        if (x >= self.back.width or y >= self.back.height) {
            std.debug.assert(false);
            return;
        }
        // Apply capability-based adjustments for graceful degradation
        const adjusted_char = self.capabilities.bestChar(char);
        const adjusted_fg = self.capabilities.bestColor(fg);
        const adjusted_bg = self.capabilities.bestColor(bg);
        const adjusted_style = self.capabilities.bestStyle(style);

        const cell = Cell.init(adjusted_char, adjusted_fg, adjusted_bg, adjusted_style);
        self.back.setCell(x, y, cell);
        self.markDirtyRect(x, y, 1, 1);
    }

    /// Draw a string at the specified position
    pub fn drawStr(self: *Renderer, x: u16, y: u16, str: []const u8, fg: Color, bg: Color, style: Style) void {
        var utf8_it = std.unicode.Utf8Iterator{
            .bytes = str,
            .i = 0,
        };

        var i: u16 = 0;
        while (utf8_it.nextCodepoint()) |codepoint| {
            const target_x = std.math.add(u32, @as(u32, x), @as(u32, i)) catch break;
            if (target_x >= self.back.width) break;
            self.drawChar(@intCast(target_x), y, codepoint, fg, bg, style);
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
        if (x >= self.back.width or y >= self.back.height) return;

        const capped_width = @min(width, self.back.width - x);
        const capped_height = @min(height, self.back.height - y);
        if (capped_width < 2 or capped_height < 2) return;

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
        self.drawChar(x + capped_width - 1, y, top_right, fg, bg, style);
        self.drawChar(x, y + capped_height - 1, bottom_left, fg, bg, style);
        self.drawChar(x + capped_width - 1, y + capped_height - 1, bottom_right, fg, bg, style);

        // Draw horizontal edges
        for (1..capped_width - 1) |i| {
            self.drawChar(x + @as(u16, @intCast(i)), y, horizontal, fg, bg, style);
            self.drawChar(x + @as(u16, @intCast(i)), y + capped_height - 1, horizontal_bottom, fg, bg, style);
        }

        // Draw vertical edges
        for (1..capped_height - 1) |i| {
            self.drawChar(x, y + @as(u16, @intCast(i)), vertical, fg, bg, style);
            self.drawChar(x + capped_width - 1, y + @as(u16, @intCast(i)), vertical_right, fg, bg, style);
        }
    }

    /// Draw a styled box with optional fill and shadow.
    pub fn drawStyledBox(self: *Renderer, x: u16, y: u16, width: u16, height: u16, box_style: BoxStyle) void {
        if (width == 0 or height == 0) return;
        if (x >= self.back.width or y >= self.back.height) return;
        const clamped_width = @min(width, self.back.width - x);
        const clamped_height = @min(height, self.back.height - y);
        if (clamped_width == 0 or clamped_height == 0) return;

        // Fill background first so shadows sit underneath the border.
        self.fillRect(x, y, clamped_width, clamped_height, ' ', box_style.border_color, box_style.background, box_style.fill_style);

        if (box_style.shadow) |shadow| {
            const shade: u21 = if (shadow.soft) '░' else '▒';

            if (shadow.offset_x > 0) {
                const sx: u32 = @as(u32, x) + @as(u32, clamped_width) + @as(u32, shadow.offset_x) - 1;
                if (sx < self.back.width) {
                    const y_start: u32 = @as(u32, y) + @as(u32, shadow.offset_y);
                    if (y_start < self.back.height) {
                        self.fillRect(@intCast(sx), @intCast(y_start), 1, clamped_height, shade, shadow.color, shadow.color, Style{});
                    }
                }
            }

            if (shadow.offset_y > 0) {
                const sy: u32 = @as(u32, y) + @as(u32, clamped_height) + @as(u32, shadow.offset_y) - 1;
                if (sy < self.back.height) {
                    const start_x_u32: u32 = @as(u32, x) + @as(u32, shadow.offset_x);
                    if (start_x_u32 < self.back.width) {
                        const max_draw = @as(u32, self.back.width) - start_x_u32;
                        const desired = @as(u32, clamped_width) + @as(u32, shadow.offset_x);
                        const draw_width: u16 = @intCast(@min(max_draw, desired));
                        self.fillRect(@intCast(start_x_u32), @intCast(sy), draw_width, 1, shade, shadow.color, shadow.color, Style{});
                    }
                }
            }
        }

        self.drawBox(x, y, clamped_width, clamped_height, box_style.border, box_style.border_color, box_style.background, box_style.style);
    }

    /// Draw a horizontal line
    pub fn drawHLine(self: *Renderer, x: u16, y: u16, width: u16, line_char: u21, fg: Color, bg: Color, style: Style) void {
        if (x >= self.back.width) return;
        const capped_width = @min(width, self.back.width - x);
        for (0..capped_width) |i| {
            const i_u32: u32 = @as(u32, @intCast(i));
            const target_x: u16 = @intCast(std.math.add(u32, @as(u32, x), i_u32) catch break);
            self.drawChar(target_x, y, line_char, fg, bg, style);
        }
    }

    /// Draw a vertical line
    pub fn drawVLine(self: *Renderer, x: u16, y: u16, height: u16, line_char: u21, fg: Color, bg: Color, style: Style) void {
        if (y >= self.back.height) return;
        const capped_height = @min(height, self.back.height - y);
        for (0..capped_height) |i| {
            const i_u32: u32 = @as(u32, @intCast(i));
            const target_y: u16 = @intCast(std.math.add(u32, @as(u32, y), i_u32) catch break);
            self.drawChar(x, target_y, line_char, fg, bg, style);
        }
    }

    /// Fill a rectangular area
    pub fn fillRect(self: *Renderer, x: u16, y: u16, width: u16, height: u16, fill_char: u21, fg: Color, bg: Color, style: Style) void {
        if (width == 0 or height == 0) return;
        if (x >= self.back.width or y >= self.back.height) return;
        const clamped_width = @min(width, self.back.width - x);
        const clamped_height = @min(height, self.back.height - y);
        if (clamped_width == 0 or clamped_height == 0) return;
        const cell = Cell.init(fill_char, fg, bg, style);
        self.back.fillRect(x, y, clamped_width, clamped_height, cell);
        self.markDirtyRect(x, y, clamped_width, clamped_height);
    }

    /// Fill a rectangular area with a linear gradient background
    pub fn fillGradient(self: *Renderer, x: u16, y: u16, width: u16, height: u16, stops: []const GradientStop, direction: GradientDirection, style: Style) void {
        if (width == 0 or height == 0 or stops.len == 0) return;
        if (x >= self.back.width or y >= self.back.height) return;
        const clamped_width = @min(width, self.back.width - x);
        const clamped_height = @min(height, self.back.height - y);
        if (clamped_width == 0 or clamped_height == 0) return;

        const sorted = copyAndSortStops(self.allocator, stops) catch return;
        defer self.allocator.free(sorted);

        const axis_len: u16 = if (direction == .horizontal) clamped_width else clamped_height;
        if (axis_len == 0) return;

        var idx: u16 = 0;
        while (idx < axis_len) : (idx += 1) {
            const denom: u16 = if (axis_len <= 1) 1 else axis_len - 1;
            const t = @as(f32, @floatFromInt(idx)) / @as(f32, @floatFromInt(denom));
            const rgb = sampleGradientColor(sorted, t);
            const bg = Color.rgb(rgb.r, rgb.g, rgb.b);

            if (direction == .horizontal) {
                var row: u16 = 0;
                while (row < clamped_height) : (row += 1) {
                    const target_x: u16 = @intCast(std.math.add(u32, @as(u32, x), @as(u32, idx)) catch break);
                    const target_y: u16 = @intCast(std.math.add(u32, @as(u32, y), @as(u32, row)) catch break);
                    self.drawChar(target_x, target_y, ' ', Color.named(NamedColor.default), bg, style);
                }
            } else {
                var col: u16 = 0;
                while (col < clamped_width) : (col += 1) {
                    const target_x: u16 = @intCast(std.math.add(u32, @as(u32, x), @as(u32, col)) catch break);
                    const target_y: u16 = @intCast(std.math.add(u32, @as(u32, y), @as(u32, idx)) catch break);
                    self.drawChar(target_x, target_y, ' ', Color.named(NamedColor.default), bg, style);
                }
            }
        }
    }

    /// Set cursor position
    pub fn setCursor(self: *Renderer, x: u16, y: u16) void {
        if (self.cursor_x != x or self.cursor_y != y) {
            self.cursor_dirty = true;
            self.cursor_x = x;
            self.cursor_y = y;
        }
    }

    /// Show or hide cursor
    pub fn showCursor(self: *Renderer, visible: bool) void {
        if (self.cursor_visible != visible) {
            self.cursor_visible = visible;
            self.cursor_dirty = true;
        }
    }

    /// Render the back buffer to the terminal
    pub fn render(self: *Renderer) !void {
        const stdout = std.fs.File.stdout();
        try self.renderToWriter(stdout);
    }

    /// Render the back buffer to a provided writer (useful for tests)
    pub fn renderToWriter(self: *Renderer, writer: anytype) !void {
        if (!self.has_dirty and !self.cursor_dirty) return;

        self.style_scratch.clearRetainingCapacity();
        self.output_batch.clearRetainingCapacity();

        var current_fg: ?Color = null;
        var current_bg: ?Color = null;
        var current_style = Style{};
        // Hide cursor during rendering to prevent flicker
        try self.output_batch.appendSlice(self.allocator, "\x1b[?25l");

        if (self.has_dirty) {
            // Perform diff-based updates between front and back buffers
            for (self.dirty_rows, 0..) |row, y_idx| {
                if (!row.dirty) continue;
                const dirty_start_x: u16 = row.min_x;
                const dirty_end_x: u16 = row.max_x + 1;
                const y: u16 = @intCast(y_idx);
                for (dirty_start_x..dirty_end_x) |x| {
                    const back_cell = self.back.getCell(@as(u16, @intCast(x)), y);
                    const front_cell = self.front.getCell(@as(u16, @intCast(x)), y);

                    // Skip if cell hasn't changed
                    if (front_cell.eql(back_cell.*)) continue;

                    // Position cursor
                    try self.appendCursorMove(@intCast(x), @intCast(y));

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
                        self.style_scratch.clearRetainingCapacity();

                        try self.style_scratch.appendSlice(self.allocator, "\x1b[");
                        const style_code = back_cell.style.toAnsi();
                        try self.style_scratch.appendSlice(self.allocator, style_code.slice());

                        try self.style_scratch.appendSlice(self.allocator, ";");
                        const fg_code = back_cell.fg.toFg();
                        try self.style_scratch.appendSlice(self.allocator, fg_code.slice());

                        try self.style_scratch.appendSlice(self.allocator, ";");
                        const bg_code = back_cell.bg.toBg();
                        try self.style_scratch.appendSlice(self.allocator, bg_code.slice());

                        try self.style_scratch.appendSlice(self.allocator, "m");

                        try self.output_batch.appendSlice(self.allocator, self.style_scratch.items);
                    }

                    var char_buf: [4]u8 = undefined;
                    const len = try std.unicode.utf8Encode(back_cell.char, &char_buf);
                    try self.output_batch.appendSlice(self.allocator, char_buf[0..len]);

                    if (self.output_batch.items.len > 4096) {
                        try self.flushOutput(writer);
                    }
                }
            }
        }

        try self.flushOutput(writer);

        try self.output_batch.appendSlice(self.allocator, "\x1b[0m");
        try self.appendCursorMove(self.cursor_x, self.cursor_y);
        if (self.cursor_visible) try self.output_batch.appendSlice(self.allocator, "\x1b[?25h");
        try self.flushOutput(writer);

        // Swap buffers
        const temp = self.front;
        self.front = self.back;
        self.back = temp;
        self.last_cursor_x = self.cursor_x;
        self.last_cursor_y = self.cursor_y;
        self.last_cursor_visible = self.cursor_visible;
        self.resetDirty();
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

test "mixColor blends rgb endpoints" {
    const red = Color.rgb(255, 0, 0);
    const blue = Color.rgb(0, 0, 255);
    const mid = mixColor(red, blue, 0.5);
    try std.testing.expectEqual(@as(std.meta.Tag(Color), .rgb_color), std.meta.activeTag(mid));
    try std.testing.expectEqual(@as(u8, 128), mid.rgb_color.r);
    try std.testing.expectEqual(@as(u8, 0), mid.rgb_color.g);
    try std.testing.expectEqual(@as(u8, 128), mid.rgb_color.b);
}

test "bestColor maps rgb to ansi256 palette when needed" {
    var caps = TerminalCapabilities.init();
    caps.colors_256 = true;
    caps.rgb_colors = false;

    const resolved = caps.bestColor(Color.rgb(255, 0, 0));
    try std.testing.expectEqual(@as(std.meta.Tag(Color), .ansi_256), std.meta.activeTag(resolved));
    try std.testing.expectEqual(@as(u8, 196), resolved.ansi_256);
}

test "bestColor upgrades ansi256 to rgb when supported" {
    var caps = TerminalCapabilities.init();
    caps.rgb_colors = true;

    const resolved = caps.bestColor(Color.ansi256(46));
    try std.testing.expectEqual(@as(std.meta.Tag(Color), .rgb_color), std.meta.activeTag(resolved));
    const rgb = resolved.rgb_color;
    const expected = ansi256ToRgb(46);
    try std.testing.expectEqual(expected.r, rgb.r);
    try std.testing.expectEqual(expected.g, rgb.g);
    try std.testing.expectEqual(expected.b, rgb.b);
}

test "bestColor collapses to nearest named color on ansi16 terminals" {
    var caps = TerminalCapabilities.init();
    caps.colors_256 = false;
    caps.rgb_colors = false;

    const resolved = caps.bestColor(Color.rgb(10, 200, 10));
    try std.testing.expectEqual(@as(std.meta.Tag(Color), .named_color), std.meta.activeTag(resolved));
    try std.testing.expectEqual(NamedColor.green, resolved.named_color);
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

test "capability detection degrades gracefully on allocation failure" {
    var empty_buf: [0]u8 = .{};
    var fallback_alloc = std.heap.FixedBufferAllocator.init(&empty_buf);
    const caps = TerminalCapabilities.detectWithAllocator(fallback_alloc.allocator());
    try std.testing.expect(!caps.rgb_colors);
    try std.testing.expect(!caps.colors_256);
    try std.testing.expect(caps.unicode);
}

test "drawSmartStr falls back when bidi sanitization cannot allocate" {
    var backing: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&backing);
    var renderer = try Renderer.init(fba.allocator(), 1, 1);
    defer renderer.deinit();

    renderer.capabilities.bidi = false;
    renderer.capabilities.unicode = true;

    const pattern = "אבג";
    var text: [192]u8 = undefined;
    var idx: usize = 0;
    while (idx + pattern.len <= text.len) : (idx += pattern.len) {
        @memcpy(text[idx .. idx + pattern.len], pattern);
    }

    renderer.drawSmartStr(0, 0, text[0..], Color.named(NamedColor.white), Color.named(NamedColor.black), Style{});
    try std.testing.expect(renderer.back.getCell(0, 0).char != ' ');
}
