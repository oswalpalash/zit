const std = @import("std");
const testing = std.testing;

// Component imports
pub const terminal = @import("terminal/terminal.zig");
pub const input = @import("input/input.zig");
pub const render = @import("render/render.zig");
pub const layout = @import("layout/layout.zig");
pub const widget = @import("widget/widget.zig");
pub const event = @import("event/event.zig");
pub const memory = @import("memory/memory.zig");
pub const quickstart = @import("quickstart.zig");

/// zit - A Text User Interface (TUI) library for Zig
///
/// This library provides a comprehensive set of tools for building
/// terminal-based user interfaces in Zig.
pub const version = std.SemanticVersion{
    .major = 0,
    .minor = 1,
    .patch = 0,
};

test "zit basic tests" {
    std.testing.refAllDecls(@This());
}
