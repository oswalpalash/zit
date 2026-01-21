const std = @import("std");
const unicode_width = @import("unicode_width.zig");

pub const ColorLevel = enum {
    ansi16,
    ansi256,
    truecolor,
};

pub const TerminalProgram = enum {
    unknown,
    kitty,
    wezterm,
    iterm2,
    apple_terminal,
    alacritty,
    ghostty,
    vscode,
    windows_terminal,
    gnome_terminal,
    konsole,
    foot,
    xterm,
    tmux,
    screen,
    linux_console,
    dumb,
};

/// Snapshot of environment variables relevant to capability detection.
pub const Environment = struct {
    term: ?[]const u8 = null,
    colorterm: ?[]const u8 = null,
    term_program: ?[]const u8 = null,
    term_program_version: ?[]const u8 = null,
    vte_version: ?[]const u8 = null,
    wt_session: ?[]const u8 = null,
    konsole_profile: ?[]const u8 = null,

    pub fn fromMap(env: *const std.process.EnvMap) Environment {
        return Environment{
            .term = env.get("TERM"),
            .colorterm = env.get("COLORTERM"),
            .term_program = env.get("TERM_PROGRAM"),
            .term_program_version = env.get("TERM_PROGRAM_VERSION"),
            .vte_version = env.get("VTE_VERSION"),
            .wt_session = env.get("WT_SESSION"),
            .konsole_profile = env.get("KONSOLE_PROFILE_NAME"),
        };
    }
};

/// Capability flags detected from the environment.
pub const CapabilityFlags = struct {
    rgb_colors: bool = false,
    colors_256: bool = false,
    italic: bool = false,
    unicode: bool = true,
    underline: bool = true,
    strikethrough: bool = false,
    emoji: bool = false,
    ligatures: bool = false,
    double_width: bool = true,
    bidi: bool = true,
    bracketed_paste: bool = false,
    kitty_keyboard: bool = false,
    kitty_graphics: bool = false,
    iterm2_integration: bool = false,
    synchronized_output: bool = false,
    program: TerminalProgram = .unknown,
    color_level: ColorLevel = .ansi16,
};

pub fn detect() CapabilityFlags {
    return detectWithAllocator(std.heap.page_allocator);
}

pub fn detectWithAllocator(allocator: std.mem.Allocator) CapabilityFlags {
    var env_map = std.process.getEnvMap(allocator) catch {
        return CapabilityFlags{};
    };
    defer env_map.deinit();

    return detectFrom(Environment.fromMap(&env_map));
}

pub fn detectFrom(env: Environment) CapabilityFlags {
    var caps = CapabilityFlags{};

    caps.program = detectProgram(env);
    caps.color_level = detectColorDepth(env, caps.program);
    caps.colors_256 = caps.color_level == .truecolor or caps.color_level == .ansi256;
    caps.rgb_colors = caps.color_level == .truecolor;

    caps.italic = caps.program != .linux_console and caps.program != .dumb;
    caps.unicode = caps.program != .linux_console and caps.program != .dumb;
    caps.underline = true;
    caps.strikethrough = caps.colors_256;
    caps.ligatures = programSupportsLigatures(caps.program);
    caps.kitty_keyboard = programSupportsKittyKeyboard(caps.program);
    caps.kitty_graphics = caps.program == .kitty or caps.program == .wezterm;
    caps.iterm2_integration = caps.program == .iterm2;
    caps.synchronized_output = detectSyncSupport(env, caps.program);
    caps.bracketed_paste = programSupportsBracketedPaste(caps.program);

    caps.emoji = unicode_width.measure("✅").has_emoji;
    caps.double_width = true;
    caps.bidi = caps.unicode;

    return caps;
}

fn detectProgram(env: Environment) TerminalProgram {
    if (env.term_program) |prog| {
        if (containsIgnoreCase(prog, "WezTerm")) return .wezterm;
        if (containsIgnoreCase(prog, "iTerm")) return .iterm2;
        if (containsIgnoreCase(prog, "Apple_Terminal")) return .apple_terminal;
        if (containsIgnoreCase(prog, "vscode")) return .vscode;
        if (containsIgnoreCase(prog, "Ghostty")) return .ghostty;
    }

    if (env.wt_session != null) return .windows_terminal;

    if (env.term) |term| {
        if (containsIgnoreCase(term, "kitty")) return .kitty;
        if (containsIgnoreCase(term, "wezterm")) return .wezterm;
        if (containsIgnoreCase(term, "alacritty")) return .alacritty;
        if (containsIgnoreCase(term, "tmux")) return .tmux;
        if (containsIgnoreCase(term, "screen")) return .screen;
        if (containsIgnoreCase(term, "xterm")) return .xterm;
        if (std.ascii.eqlIgnoreCase(term, "linux")) return .linux_console;
        if (std.ascii.eqlIgnoreCase(term, "dumb")) return .dumb;
        if (containsIgnoreCase(term, "foot")) return .foot;
        if (containsIgnoreCase(term, "konsole")) return .konsole;
        if (containsIgnoreCase(term, "gnome")) return .gnome_terminal;
    }

    return .unknown;
}

fn detectColorDepth(env: Environment, program: TerminalProgram) ColorLevel {
    var depth: ColorLevel = .ansi16;

    if (env.term) |term| {
        if (containsIgnoreCase(term, "256color")) depth = .ansi256;
        if (containsIgnoreCase(term, "direct") or containsIgnoreCase(term, "truecolor")) depth = .truecolor;
    }

    if (env.colorterm) |ct| {
        if (containsIgnoreCase(ct, "truecolor") or containsIgnoreCase(ct, "24bit")) {
            depth = .truecolor;
        } else if (containsIgnoreCase(ct, "256")) {
            depth = maxDepth(depth, .ansi256);
        }
    }

    switch (program) {
        .kitty, .wezterm, .alacritty, .ghostty, .iterm2, .windows_terminal, .vscode => depth = .truecolor,
        .apple_terminal, .gnome_terminal, .konsole, .foot => depth = maxDepth(depth, .truecolor),
        else => {},
    }

    if (parseVteVersion(env.vte_version)) |vte_version| {
        if (vte_version >= 3600) {
            depth = .truecolor;
        } else if (vte_version >= 1000) {
            depth = maxDepth(depth, .ansi256);
        }
    }

    if (program == .dumb) depth = .ansi16;

    return depth;
}

fn detectSyncSupport(env: Environment, program: TerminalProgram) bool {
    if (program == .dumb or program == .linux_console) return false;

    switch (program) {
        .kitty, .wezterm, .alacritty, .ghostty, .iterm2, .windows_terminal => return true,
        else => {},
    }

    if (env.term) |term| {
        if (containsIgnoreCase(term, "xterm")) return true;
        if (containsIgnoreCase(term, "tmux")) return true;
        if (containsIgnoreCase(term, "screen")) return true;
        if (containsIgnoreCase(term, "rxvt")) return true;
    }

    return false;
}

fn programSupportsLigatures(program: TerminalProgram) bool {
    return switch (program) {
        .kitty, .wezterm, .ghostty, .alacritty, .vscode, .windows_terminal, .foot => true,
        else => false,
    };
}

fn programSupportsKittyKeyboard(program: TerminalProgram) bool {
    return switch (program) {
        .kitty, .wezterm, .ghostty => true,
        else => false,
    };
}

fn programSupportsBracketedPaste(program: TerminalProgram) bool {
    return switch (program) {
        .dumb, .linux_console => false,
        else => true,
    };
}

fn parseVteVersion(vte: ?[]const u8) ?u32 {
    if (vte) |raw| {
        return std.fmt.parseUnsigned(u32, raw, 10) catch null;
    }
    return null;
}

fn maxDepth(a: ColorLevel, b: ColorLevel) ColorLevel {
    return if (@intFromEnum(a) >= @intFromEnum(b)) a else b;
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0 or haystack.len < needle.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        var matched = true;
        for (needle, 0..) |c, idx| {
            if (std.ascii.toLower(haystack[i + idx]) != std.ascii.toLower(c)) {
                matched = false;
                break;
            }
        }
        if (matched) return true;
    }
    return false;
}

test "detects truecolor from environment" {
    const env = Environment{
        .term = "xterm-256color",
        .colorterm = "truecolor",
        .term_program = "WezTerm",
    };
    const caps = detectFrom(env);
    try std.testing.expect(caps.rgb_colors);
    try std.testing.expect(caps.colors_256);
    try std.testing.expect(caps.color_level == .truecolor);
}

test "kitty specific features are surfaced" {
    const env = Environment{
        .term = "xterm-kitty",
        .colorterm = "24bit",
    };
    const caps = detectFrom(env);
    try std.testing.expect(caps.kitty_keyboard);
    try std.testing.expect(caps.kitty_graphics);
    try std.testing.expect(caps.synchronized_output);
}

test "linux console stays conservative" {
    const env = Environment{ .term = "linux" };
    const caps = detectFrom(env);
    try std.testing.expect(!caps.unicode);
    try std.testing.expect(!caps.rgb_colors);
    try std.testing.expect(!caps.synchronized_output);
    try std.testing.expect(!caps.bracketed_paste);
}

test "xterm style terminals support synchronized output" {
    const env = Environment{ .term = "xterm-256color" };
    const caps = detectFrom(env);
    try std.testing.expect(caps.synchronized_output);
    try std.testing.expect(caps.colors_256);
}
