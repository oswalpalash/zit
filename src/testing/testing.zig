const std = @import("std");
const render = @import("../render/render.zig");
const layout = @import("../layout/layout.zig");
const widget = @import("../widget/widget.zig");
const input = @import("../input/input.zig");

/// Errors emitted by snapshot helpers.
pub const SnapshotError = error{GoldenMissing};

/// Options for comparing a snapshot against a golden file.
pub const SnapshotOptions = struct {
    /// Force updating the golden file even if environment variables are unset.
    update: bool = false,
    /// Environment variable that opts into updating or creating golden files.
    env_var: ?[]const u8 = "ZIT_UPDATE_SNAPSHOTS",
    /// Allow creating a golden file when it is missing (only when update is enabled).
    allow_create: bool = true,
};

fn shouldUpdateGolden(opts: SnapshotOptions) bool {
    if (opts.update) return true;
    if (opts.env_var) |name| {
        const allocator = std.heap.page_allocator;
        const value = std.process.getEnvVarOwned(allocator, name) catch |err| switch (err) {
            error.EnvironmentVariableNotFound => return false,
            else => return false,
        };
        defer allocator.free(value);
        return true;
    }
    return false;
}

fn writeGolden(path: []const u8, contents: []const u8) !void {
    const cwd = std.fs.cwd();
    if (std.fs.path.dirname(path)) |dir| {
        try cwd.makePath(dir);
    }

    var file = try cwd.createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(contents);
}

fn readGolden(allocator: std.mem.Allocator, golden_path: []const u8) !?[]u8 {
    const cwd = std.fs.cwd();
    return cwd.readFileAlloc(allocator, golden_path, 4 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
}

fn printDiff(golden_path: []const u8, expected: []const u8, actual: []const u8) void {
    std.debug.print("Snapshot mismatch for {s}\n", .{golden_path});
    std.debug.print("--- golden\n+++ snapshot\n", .{});

    var expected_it = std.mem.splitScalar(u8, expected, '\n');
    var actual_it = std.mem.splitScalar(u8, actual, '\n');
    var line_no: usize = 1;
    while (true) : (line_no += 1) {
        const expected_line = expected_it.next();
        const actual_line = actual_it.next();
        if (expected_line == null and actual_line == null) break;

        const left = expected_line orelse "";
        const right = actual_line orelse "";
        if (std.mem.eql(u8, left, right)) continue;

        std.debug.print("{d:4} - {s}\n", .{ line_no, left });
        std.debug.print("{d:4} + {s}\n", .{ line_no, right });
    }
    std.debug.print("\n", .{});
}

fn normalizeLineEndings(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var normalized = try allocator.alloc(u8, text.len);
    var out: usize = 0;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        if (text[i] == '\r') {
            if (i + 1 < text.len and text[i + 1] == '\n') {
                // Skip the CR in CRLF sequences and emit a single LF.
                i += 1;
            }
            normalized[out] = '\n';
        } else {
            normalized[out] = text[i];
        }
        out += 1;
    }
    // Shrink to actual size so free() gets the right length
    return allocator.realloc(normalized, out) catch normalized[0..out];
}

/// Compare a snapshot against a golden file with optional auto-update.
///
/// Parameters:
/// - `allocator`: allocator used for reading/writing golden files.
/// - `snapshot`: rendered buffer produced by `renderWidget` or friends.
/// - `golden_path`: path to the golden file on disk.
/// - `opts`: controls update behavior and environment toggle.
/// Returns: `SnapshotError.GoldenMissing` when the golden is absent and updates are disabled; writer or fs errors otherwise.
/// Example:
/// ```zig
/// try expectSnapshotMatch(alloc, snap, "goldens/button.txt", .{ .env_var = "UPDATE" });
/// ```
pub fn expectSnapshotMatch(
    allocator: std.mem.Allocator,
    snapshot: Snapshot,
    golden_path: []const u8,
    opts: SnapshotOptions,
) !void {
    const update = shouldUpdateGolden(opts);
    const golden = try readGolden(allocator, golden_path);
    defer if (golden) |buf| allocator.free(buf);

    const snapshot_text = snapshot.text();
    if (golden == null) {
        if (update and opts.allow_create) {
            try writeGolden(golden_path, snapshot_text);
            return;
        }
        printDiff(golden_path, "", snapshot_text);
        return SnapshotError.GoldenMissing;
    }

    const expected = golden.?;
    const expected_normalized = try normalizeLineEndings(allocator, expected);
    defer allocator.free(expected_normalized);

    const snapshot_normalized = try normalizeLineEndings(allocator, snapshot_text);
    defer allocator.free(snapshot_normalized);

    if (!std.mem.eql(u8, expected_normalized, snapshot_normalized)) {
        if (update) {
            try writeGolden(golden_path, snapshot_text);
            return;
        }

        printDiff(golden_path, expected_normalized, snapshot_normalized);
        try std.testing.expectEqualStrings(expected_normalized, snapshot_normalized);
    }
}

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

    /// Assert that this snapshot matches a golden file.
    ///
    /// Parameters:
    /// - `allocator`: allocator used to load/create the golden file.
    /// - `golden_path`: path relative to the repo root or cwd.
    /// - `opts`: controls update behavior (env var, allow create).
    /// Returns: `SnapshotError.GoldenMissing` or fs errors.
    /// Example:
    /// ```zig
    /// try snap.expectGolden(alloc, "goldens/table.txt", .{ .update = std.debug.runtime_safety });
    /// ```
    pub fn expectGolden(
        self: Snapshot,
        allocator: std.mem.Allocator,
        golden_path: []const u8,
        opts: SnapshotOptions,
    ) !void {
        try expectSnapshotMatch(allocator, self, golden_path, opts);
    }

    fn fromBuffer(allocator: std.mem.Allocator, buffer: *render.Buffer) !Snapshot {
        const max_utf8_bytes_per_cell = 32;
        const newline_bytes = 1;
        const row_stride: usize = (@as(usize, buffer.width) * max_utf8_bytes_per_cell) + newline_bytes;
        var buf = try allocator.alloc(u8, row_stride * buffer.height);
        var idx: usize = 0;

        for (0..buffer.height) |y| {
            for (0..buffer.width) |x| {
                const cell = buffer.getCell(@intCast(x), @intCast(y)).*;
                const glyph_bytes = if (cell.continuation) " " else cell.glyph.slice();
                const active = if (glyph_bytes.len == 0) " " else glyph_bytes;
                @memcpy(buf[idx .. idx + active.len], active);
                idx += active.len;
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
    allocator: std.mem.Allocator,
    size: layout.Size,
    input_queue: std.ArrayListUnmanaged(input.Event) = .{},
    input_cursor: usize = 0,
    output_log: std.ArrayListUnmanaged(u8) = .{},

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
        return MockTerminal{
            .renderer = renderer,
            .allocator = allocator,
            .size = layout.Size.init(width, height),
        };
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
        self.input_queue.deinit(self.allocator);
        self.output_log.deinit(self.allocator);
    }

    /// Resize the simulated terminal and underlying buffers.
    pub fn resize(self: *MockTerminal, width: u16, height: u16) !void {
        self.size = layout.Size.init(width, height);
        try self.renderer.resize(width, height);
    }

    /// Queue a synthetic input event for consumption by tests.
    pub fn pushInput(self: *MockTerminal, event: input.Event) !void {
        try self.input_queue.append(self.allocator, event);
    }

    /// Queue printable characters as key events.
    pub fn pushKeys(self: *MockTerminal, text: []const u8) !void {
        var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
        while (it.nextCodepoint()) |cp| {
            try self.pushInput(input.Event{ .key = input.KeyEvent.init(cp, input.KeyModifiers{}) });
        }
    }

    /// Pop the next queued input event if available.
    pub fn nextInput(self: *MockTerminal) ?input.Event {
        if (self.input_cursor >= self.input_queue.items.len) return null;
        defer self.input_cursor += 1;
        return self.input_queue.items[self.input_cursor];
    }

    /// Clear the recorded input events.
    pub fn clearInputs(self: *MockTerminal) void {
        self.input_queue.clearRetainingCapacity();
        self.input_cursor = 0;
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

    /// Capture the renderer's ANSI output for the current back buffer.
    pub fn captureOutput(self: *MockTerminal) ![]const u8 {
        self.output_log.clearRetainingCapacity();
        const writer = self.output_log.writer(self.allocator);
        try self.renderer.renderToWriter(writer);
        return self.output_log.items;
    }
};

/// Lightweight harness that keeps a mock terminal, sizing, and rendering helpers together.
pub const WidgetHarness = struct {
    allocator: std.mem.Allocator,
    size: layout.Size,
    terminal: MockTerminal,

    /// Construct a harness with a mock terminal sized to `size`.
    ///
    /// Parameters:
    /// - `allocator`: allocator forwarded into the mock terminal.
    /// - `size`: initial renderer dimensions.
    /// Returns: ready-to-use harness; call `deinit` when done.
    pub fn init(allocator: std.mem.Allocator, size: layout.Size) !WidgetHarness {
        return WidgetHarness{
            .allocator = allocator,
            .size = size,
            .terminal = try MockTerminal.init(allocator, size.width, size.height),
        };
    }

    /// Release renderer buffers and cursor state.
    pub fn deinit(self: *WidgetHarness) void {
        self.terminal.deinit();
    }

    /// Resize the backing mock terminal and future layouts.
    ///
    /// Parameters:
    /// - `size`: new width/height to apply to the renderer.
    /// Returns: any renderer allocation error on resize.
    pub fn resize(self: *WidgetHarness, size: layout.Size) !void {
        self.size = size;
        try self.terminal.resize(size.width, size.height);
    }

    fn applyLayout(self: *WidgetHarness, widget_ptr: *widget.Widget) !void {
        try widget_ptr.layout(layout.Rect.init(0, 0, self.size.width, self.size.height));
    }

    /// Render a widget to the mock terminal and return a text snapshot.
    pub fn render(self: *WidgetHarness, widget_ptr: *widget.Widget) !Snapshot {
        try self.applyLayout(widget_ptr);
        try widget_ptr.draw(&self.terminal.renderer);
        return self.terminal.snapshot(self.allocator);
    }

    /// Render a widget and return the ANSI bytes a real terminal would receive.
    pub fn renderAnsi(self: *WidgetHarness, widget_ptr: *widget.Widget) ![]const u8 {
        try self.applyLayout(widget_ptr);
        try widget_ptr.draw(&self.terminal.renderer);
        return self.terminal.captureOutput();
    }

    /// Render a widget and assert it matches inline text.
    pub fn expectRenders(self: *WidgetHarness, widget_ptr: *widget.Widget, expected: []const u8) !void {
        var snap = try self.render(widget_ptr);
        defer snap.deinit(self.allocator);
        try snap.expectEqual(expected);
    }

    /// Render a widget and assert it matches a golden snapshot.
    pub fn expectGolden(
        self: *WidgetHarness,
        widget_ptr: *widget.Widget,
        golden_path: []const u8,
        opts: SnapshotOptions,
    ) !void {
        var snap = try self.render(widget_ptr);
        defer snap.deinit(self.allocator);
        try expectSnapshotMatch(self.allocator, snap, golden_path, opts);
    }

    fn ensureLayout(self: *WidgetHarness, widget_ptr: *widget.Widget) !void {
        if (widget_ptr.rect.width == 0 and widget_ptr.rect.height == 0) {
            try self.applyLayout(widget_ptr);
        }
    }

    /// Send a single event to a widget, laying it out first if needed.
    pub fn sendEvent(self: *WidgetHarness, widget_ptr: *widget.Widget, event: input.Event) !bool {
        try self.ensureLayout(widget_ptr);
        return widget_ptr.handleEvent(event);
    }

    /// Send multiple events and return how many were handled.
    pub fn sendEvents(self: *WidgetHarness, widget_ptr: *widget.Widget, events: []const input.Event) !usize {
        var handled: usize = 0;
        for (events) |ev| {
            if (try self.sendEvent(widget_ptr, ev)) handled += 1;
        }
        return handled;
    }

    /// Send printable characters as key events and return how many were handled.
    pub fn sendKeys(self: *WidgetHarness, widget_ptr: *widget.Widget, text: []const u8) !usize {
        var handled: usize = 0;
        var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
        while (it.nextCodepoint()) |cp| {
            const ev = input.Event{ .key = input.KeyEvent.init(cp, input.KeyModifiers{}) };
            if (try self.sendEvent(widget_ptr, ev)) handled += 1;
        }
        return handled;
    }

    /// Simulate a primary button click at a coordinate.
    pub fn click(self: *WidgetHarness, widget_ptr: *widget.Widget, x: u16, y: u16) !bool {
        return self.sendEvent(widget_ptr, input.Event{ .mouse = input.MouseEvent.init(.press, x, y, 1, 0) });
    }

    /// Mark a widget focused for input-heavy tests.
    pub fn focus(self: *WidgetHarness, widget_ptr: *widget.Widget) void {
        _ = self;
        widget_ptr.setFocus(true);
    }
};

/// Convenience helper for rendering a widget into a mock terminal.
pub fn renderWidget(
    allocator: std.mem.Allocator,
    widget_ptr: *widget.Widget,
    size: layout.Size,
) !Snapshot {
    var harness = try WidgetHarness.init(allocator, size);
    defer harness.deinit();
    return harness.render(widget_ptr);
}

/// Minimal builders tuned for tests so common widgets are one call away.
pub const TestWidgetBuilders = struct {
    pub fn button(allocator: std.mem.Allocator, text: []const u8) !widget.Button {
        var builder = widget.ButtonBuilder.init(allocator);
        return builder.text(text).build();
    }

    pub fn label(allocator: std.mem.Allocator, text: []const u8) !widget.Label {
        var builder = widget.LabelBuilder.init(allocator);
        return builder.content(text).build();
    }

    pub fn focusedInput(allocator: std.mem.Allocator, placeholder: []const u8) !*widget.InputField {
        var builder = widget.InputBuilder.init(allocator);
        var field = try builder.withPlaceholder(placeholder).build();
        field.widget.focused = true;
        return field;
    }
};

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

test "snapshot comparison uses golden files" {
    const alloc = std.testing.allocator;
    var btn_builder = widget.ButtonBuilder.init(alloc);
    var btn = try btn_builder.text("Go").build();
    defer btn.deinit();

    var snap = try renderWidget(alloc, &btn.widget, layout.Size.init(12, 3));
    defer snap.deinit(alloc);

    try snap.expectGolden(alloc, "src/testing/golden/button_basic.snap", .{});
}

test "snapshot label basic render" {
    const alloc = std.testing.allocator;
    var label_builder = widget.LabelBuilder.init(alloc);
    var label = try label_builder.content("Hello").build();
    defer label.deinit();

    var harness = try WidgetHarness.init(alloc, layout.Size.init(10, 1));
    defer harness.deinit();
    try harness.expectGolden(&label.widget, "src/testing/golden/label_basic.snap", .{});
}

test "snapshot label multiline render" {
    const alloc = std.testing.allocator;
    var label_builder = widget.LabelBuilder.init(alloc);
    var label = try label_builder.content("Hello\nWorld").build();
    defer label.deinit();

    var harness = try WidgetHarness.init(alloc, layout.Size.init(10, 2));
    defer harness.deinit();
    try harness.expectGolden(&label.widget, "src/testing/golden/label_multiline.snap", .{});
}

test "snapshot label alignment variations" {
    const alloc = std.testing.allocator;
    var left_builder = widget.LabelBuilder.init(alloc);
    var left = try left_builder.content("Hi").alignTo(.left).build();
    defer left.deinit();
    var left_harness = try WidgetHarness.init(alloc, layout.Size.init(8, 1));
    defer left_harness.deinit();
    try left_harness.expectGolden(&left.widget, "src/testing/golden/label_align_left.snap", .{});

    var center_builder = widget.LabelBuilder.init(alloc);
    var center = try center_builder.content("Hi").alignTo(.center).build();
    defer center.deinit();
    var center_harness = try WidgetHarness.init(alloc, layout.Size.init(8, 1));
    defer center_harness.deinit();
    try center_harness.expectGolden(&center.widget, "src/testing/golden/label_align_center.snap", .{});

    var right_builder = widget.LabelBuilder.init(alloc);
    var right = try right_builder.content("Hi").alignTo(.right).build();
    defer right.deinit();
    var right_harness = try WidgetHarness.init(alloc, layout.Size.init(8, 1));
    defer right_harness.deinit();
    try right_harness.expectGolden(&right.widget, "src/testing/golden/label_align_right.snap", .{});
}

test "snapshot checkbox unchecked render" {
    const alloc = std.testing.allocator;
    var checkbox = try widget.Checkbox.init(alloc, "Accept");
    defer checkbox.deinit();

    var mock = try MockTerminal.init(alloc, 14, 1);
    defer mock.deinit();
    try checkbox.widget.layout(layout.Rect.init(1, 0, 13, 1));
    try checkbox.widget.draw(&mock.renderer);

    var snap = try mock.snapshot(alloc);
    defer snap.deinit(alloc);
    try snap.expectGolden(alloc, "src/testing/golden/checkbox_unchecked.snap", .{});
}

test "snapshot checkbox checked render" {
    const alloc = std.testing.allocator;
    var checkbox = try widget.Checkbox.init(alloc, "Accept");
    checkbox.setChecked(true);
    defer checkbox.deinit();

    var mock = try MockTerminal.init(alloc, 14, 1);
    defer mock.deinit();
    try checkbox.widget.layout(layout.Rect.init(1, 0, 13, 1));
    try checkbox.widget.draw(&mock.renderer);

    var snap = try mock.snapshot(alloc);
    defer snap.deinit(alloc);
    try snap.expectGolden(alloc, "src/testing/golden/checkbox_checked.snap", .{});
}

test "mock terminal captures ansi output and queues input" {
    const alloc = std.testing.allocator;
    var mock = try MockTerminal.init(alloc, 6, 2);
    defer mock.deinit();

    try mock.pushKeys("hi");
    if (mock.nextInput()) |first| {
        try std.testing.expectEqual(input.EventType.key, std.meta.activeTag(first));
        try std.testing.expectEqual(@as(u21, 'h'), first.key.key);
    } else return error.TestExpectedEqual;

    if (mock.nextInput()) |second| {
        try std.testing.expectEqual(input.EventType.key, std.meta.activeTag(second));
        try std.testing.expectEqual(@as(u21, 'i'), second.key.key);
    } else return error.TestExpectedEqual;

    try std.testing.expectEqual(@as(?input.Event, null), mock.nextInput());

    mock.renderer.drawStr(0, 0, "Hi!", render.Color.named(render.NamedColor.white), render.Color.named(render.NamedColor.black), render.Style{});
    const ansi = try mock.captureOutput();
    try std.testing.expect(ansi.len > 0);
}

test "widget harness simulates typing and assertions" {
    const alloc = std.testing.allocator;
    var field_builder = widget.InputBuilder.init(alloc);
    var field = try field_builder.withPlaceholder("name").build();
    defer field.deinit();

    var harness = try WidgetHarness.init(alloc, layout.Size.init(12, 1));
    defer harness.deinit();
    harness.focus(&field.widget);

    _ = try harness.sendKeys(&field.widget, "ok");

    var snap = try harness.render(&field.widget);
    defer snap.deinit(alloc);
    try std.testing.expect(std.mem.indexOf(u8, snap.text(), "ok") != null);
}
