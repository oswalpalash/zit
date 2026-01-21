const std = @import("std");
const render = @import("../render/render.zig");
const layout = @import("../layout/layout.zig");
const widget = @import("../widget/widget.zig");

/// Snapshot of a rendered buffer for assertions.
pub const Snapshot = struct {
    buffer: []u8,
    len: usize,
    width: u16,
    height: u16,

    /// Release the snapshot buffer.
    ///
    /// Parameters:
    /// - `allocator`: allocator originally used to allocate the snapshot buffer.
    /// Errors: none.
    /// Example:
    /// ```
    /// var snap = try renderWidget(alloc, &widget, layout.Size.init(10, 2));
    /// defer snap.deinit(alloc);
    /// ```
    pub fn deinit(self: *Snapshot, allocator: std.mem.Allocator) void {
        allocator.free(self.buffer);
    }

    /// Access the rendered text backing this snapshot.
    ///
    /// Returns: immutable view into the buffered text (width * height with trailing newlines).
    /// Errors: none.
    /// Example:
    /// ```
    /// const buffer = snap.text();
    /// try std.testing.expect(buffer.len > 0);
    /// ```
    pub fn text(self: Snapshot) []const u8 {
        return self.buffer[0..self.len];
    }

    /// Assert that the snapshot matches expected text.
    ///
    /// Parameters:
    /// - `expected`: UTF-8 text to compare against the buffer.
    /// Returns: success when the buffers are identical.
    /// Errors: `std.testing` failure if the buffers differ.
    /// Example:
    /// ```
    /// try snap.expectEqual("hello\n");
    /// ```
    pub fn expectEqual(self: Snapshot, expected: []const u8) !void {
        try std.testing.expectEqualStrings(expected, self.text());
    }

    fn fromBuffer(allocator: std.mem.Allocator, buffer: *render.Buffer) !Snapshot {
        const max_utf8_bytes_per_codepoint = 4;
        const newline_bytes = 1;
        const row_stride: usize = (@as(usize, buffer.width) * max_utf8_bytes_per_codepoint) + newline_bytes;
        var buf = try allocator.alloc(u8, row_stride * buffer.height);
        var idx: usize = 0;

        for (0..buffer.height) |y| {
            for (0..buffer.width) |x| {
                const cell = buffer.getCell(@intCast(x), @intCast(y)).*;
                var tmp: [4]u8 = undefined;
                const len = blk: {
                    const encoded = std.unicode.utf8Encode(cell.char, &tmp) catch {
                        tmp[0] = '?';
                        break :blk 1;
                    };
                    break :blk encoded;
                };
                @memcpy(buf[idx .. idx + len], tmp[0..len]);
                idx += len;
            }
            buf[idx] = '\n';
            idx += 1;
        }

        return Snapshot{
            .buffer = buf,
            .len = idx,
            .width = buffer.width,
            .height = buffer.height,
        };
    }
};

/// Headless renderer wrapper for widget tests.
pub const MockTerminal = struct {
    renderer: render.Renderer,

    /// Initialize a deterministic renderer for tests.
    ///
    /// Parameters:
    /// - `allocator`: allocator used for renderer buffers.
    /// - `width`: width of the simulated terminal.
    /// - `height`: height of the simulated terminal.
    /// Returns: initialized mock terminal with Unicode and color support enabled.
    /// Errors: renderer allocation failures.
    /// Example:
    /// ```
    /// var mock = try MockTerminal.init(alloc, 80, 24);
    /// defer mock.deinit();
    /// ```
    pub fn init(allocator: std.mem.Allocator, width: u16, height: u16) !MockTerminal {
        var renderer = try render.Renderer.init(allocator, width, height);
        // Make tests deterministic and expressive.
        renderer.capabilities.unicode = true;
        renderer.capabilities.colors_256 = true;
        renderer.capabilities.rgb_colors = true;
        renderer.capabilities.bidi = false;
        return MockTerminal{ .renderer = renderer };
    }

    /// Tear down renderer resources.
    ///
    /// Parameters:
    /// - `self`: mock terminal to destroy.
    /// Errors: none.
    /// Example:
    /// ```
    /// var mock = try MockTerminal.init(alloc, 10, 5);
    /// defer mock.deinit();
    /// ```
    pub fn deinit(self: *MockTerminal) void {
        self.renderer.deinit();
    }

    /// Produce a snapshot of the current back buffer (no terminal IO).
    ///
    /// Parameters:
    /// - `allocator`: allocator used for the snapshot buffer.
    /// Returns: immutable snapshot of the renderer back buffer.
    /// Errors: allocation failures when copying the buffer.
    /// Example:
    /// ```
    /// const snap = try mock.snapshot(alloc);
    /// defer snap.deinit(alloc);
    /// ```
    pub fn snapshot(self: *MockTerminal, allocator: std.mem.Allocator) !Snapshot {
        return Snapshot.fromBuffer(allocator, &self.renderer.back);
    }
};

/// Convenience helper for rendering a widget into a mock terminal.
///
/// Parameters:
/// - `allocator`: allocator used for the renderer and returned snapshot.
/// - `widget_ptr`: widget to lay out and draw.
/// - `size`: dimensions of the simulated terminal.
/// Returns: snapshot of the widget rendering.
/// Errors: layout, draw, or allocation failures.
/// Example:
/// ```
/// var label = try widget.LabelBuilder.init(alloc).content("Hi").build();
/// defer label.deinit();
/// const snap = try renderWidget(alloc, &label.widget, layout.Size.init(4, 1));
/// defer snap.deinit(alloc);
/// ```
pub fn renderWidget(
    allocator: std.mem.Allocator,
    widget_ptr: *widget.Widget,
    size: layout.Size,
) !Snapshot {
    var mock = try MockTerminal.init(allocator, size.width, size.height);
    defer mock.deinit();

    try widget_ptr.layout(layout.Rect.init(0, 0, size.width, size.height));
    try widget_ptr.draw(&mock.renderer);
    return mock.snapshot(allocator);
}

test "mock terminal captures widget output" {
    const alloc = std.testing.allocator;
    var btn_builder = widget.ButtonBuilder.init(alloc);
    var btn = try btn_builder.text("Go").build();
    defer btn.deinit();

    var snap = try renderWidget(alloc, &btn.widget, layout.Size.init(12, 3));
    defer snap.deinit(alloc);

    try snap.expectEqual(
        \\╭──────────╮
        \\│    Go    │
        \\╰──────────╯
        \\
    );
}

test "snapshot helper respects text styling choices" {
    const alloc = std.testing.allocator;
    var label_builder = widget.LabelBuilder.init(alloc);
    var label = try label_builder
        .content("Zit Rocks")
        .textStyle(render.Style{ .bold = true })
        .build();
    defer label.deinit();

    var snap = try renderWidget(alloc, &label.widget, layout.Size.init(12, 1));
    defer snap.deinit(alloc);

    try snap.expectEqual("Zit Rocks   \n");
}

test "renderWidget tolerates zero-sized targets" {
    const alloc = std.testing.allocator;
    var label_builder = widget.LabelBuilder.init(alloc);
    var label = try label_builder.content("tiny").build();
    defer label.deinit();

    var snap = try renderWidget(alloc, &label.widget, layout.Size.init(0, 0));
    defer snap.deinit(alloc);
    try std.testing.expectEqual(@as(usize, 0), snap.text().len);
}
