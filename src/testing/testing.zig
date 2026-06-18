const std = @import("std");
const render = @import("../render/render.zig");
const layout = @import("../layout/layout.zig");
const widget = @import("../widget/widget.zig");
const input = @import("../input/input.zig");
const compat = @import("../compat.zig");

/// Errors emitted by snapshot helpers.
pub const SnapshotError = error{
    GoldenMissing,
    InvalidSnapshotUtf8,
    InvalidSnapshotControlCode,
    InvalidSnapshotWidth,
    InvalidSnapshotHeight,
    InvalidSnapshotBuffer,
    MissingSnapshotTrailingNewline,
    SnapshotTextMissing,
};

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
        const value = compat.getEnv(allocator, name) catch return false;
        const actual = value orelse return false;
        defer allocator.free(actual);
        return true;
    }
    return false;
}

fn writeGolden(path: []const u8, contents: []const u8) !void {
    const io = std.Io.Threaded.global_single_threaded.io();
    const cwd = std.Io.Dir.cwd();
    if (std.fs.path.dirname(path)) |dir| {
        try cwd.createDirPath(io, dir);
    }

    try cwd.writeFile(io, .{ .sub_path = path, .data = contents, .flags = .{ .truncate = true } });
}

fn readGolden(allocator: std.mem.Allocator, golden_path: []const u8) !?[]u8 {
    const io = std.Io.Threaded.global_single_threaded.io();
    const cwd = std.Io.Dir.cwd();
    return cwd.readFileAlloc(io, golden_path, allocator, .limited(4 * 1024 * 1024)) catch |err| switch (err) {
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

    /// Assert that a snapshot contains expected text.
    pub fn expectContains(self: Snapshot, needle: []const u8) !void {
        if (std.mem.indexOf(u8, self.text(), needle) == null) {
            std.debug.print("Snapshot did not contain expected text: {s}\n", .{needle});
            return SnapshotError.SnapshotTextMissing;
        }
    }

    /// Assert that a text snapshot is deterministic renderer output.
    ///
    /// The invariant intentionally checks visible-cell shape rather than byte width:
    /// UTF-8 glyphs may use multiple bytes, but each rendered cell should contribute
    /// exactly one codepoint and each row should end with a newline.
    pub fn expectWellFormed(self: Snapshot) !void {
        const text_value = self.text();
        if (!std.unicode.utf8ValidateSlice(text_value)) return SnapshotError.InvalidSnapshotUtf8;

        var rows = std.mem.splitScalar(u8, text_value, '\n');
        var row_count: usize = 0;
        while (rows.next()) |row| {
            if (row.len == 0 and row_count == self.height) break;
            if (row_count >= self.height) return SnapshotError.InvalidSnapshotHeight;

            var visible_cells: usize = 0;
            var utf8 = (std.unicode.Utf8View.init(row) catch return SnapshotError.InvalidSnapshotUtf8).iterator();
            while (utf8.nextCodepoint()) |cp| {
                if (cp < 0x20 or cp == 0x7f) return SnapshotError.InvalidSnapshotControlCode;
                visible_cells += 1;
            }

            if (visible_cells != self.width) return SnapshotError.InvalidSnapshotWidth;
            row_count += 1;
        }

        if (row_count != self.height) return SnapshotError.InvalidSnapshotHeight;
        if (text_value.len > 0 and text_value[text_value.len - 1] != '\n') return SnapshotError.MissingSnapshotTrailingNewline;
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
                const cell = (buffer.getCellOrNull(@intCast(x), @intCast(y)) orelse return SnapshotError.InvalidSnapshotBuffer).*;
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
    input_queue: std.ArrayListUnmanaged(input.Event) = .empty,
    input_cursor: usize = 0,
    output_log: std.ArrayListUnmanaged(u8) = .empty,

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
        var writer = std.Io.Writer.Allocating.init(self.allocator);
        defer writer.deinit();
        try self.renderer.renderToWriter(&writer.writer);
        try self.output_log.appendSlice(self.allocator, writer.written());
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
    try snap.expectWellFormed();

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
    try snap.expectWellFormed();

    try snap.expectEqual("Zit Rocks   \n");
}

test "renderWidget tolerates zero-sized targets" {
    const alloc = std.testing.allocator;
    var label_builder = widget.LabelBuilder.init(alloc);
    var label = try label_builder.content("tiny").build();
    defer label.deinit();

    var snap = try renderWidget(alloc, &label.widget, layout.Size.init(0, 0));
    defer snap.deinit(alloc);
    try snap.expectWellFormed();
    try std.testing.expectEqual(@as(usize, 0), snap.text().len);
}

test "snapshot well formed check rejects malformed output" {
    var invalid_width = Snapshot{
        .buffer = @constCast("ab\n"),
        .len = 3,
        .width = 3,
        .height = 1,
    };
    try std.testing.expectError(SnapshotError.InvalidSnapshotWidth, invalid_width.expectWellFormed());

    var control_code = Snapshot{
        .buffer = @constCast("a\x1b\n"),
        .len = 3,
        .width = 2,
        .height = 1,
    };
    try std.testing.expectError(error.InvalidSnapshotControlCode, control_code.expectWellFormed());
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

test "real-world htop snapshot remains well formed" {
    const alloc = std.testing.allocator;
    var mock = try MockTerminal.init(alloc, 80, 24);
    defer mock.deinit();

    var cpu = try widget.Gauge.init(alloc);
    defer cpu.deinit();
    cpu.setValue(72);
    try cpu.setLabel("CPU 72%");
    try cpu.widget.layout(layout.Rect.init(1, 1, 30, 3));
    try cpu.widget.draw(&mock.renderer);

    var mem = try widget.Gauge.init(alloc);
    defer mem.deinit();
    mem.setValue(48);
    try mem.setLabel("MEM 48%");
    mem.fill = render.Color.named(.magenta);
    try mem.widget.layout(layout.Rect.init(35, 1, 30, 3));
    try mem.widget.draw(&mock.renderer);

    var table = try widget.Table.init(alloc);
    defer table.deinit();
    try table.addColumn("PID", 6, false);
    try table.addColumn("USER", 8, false);
    try table.addColumn("CPU%", 6, false);
    try table.addColumn("MEM%", 6, false);
    try table.addColumn("COMMAND", 30, true);
    const rows = [_][5][]const u8{
        .{ "1203", "root", "23.1", "12.4", "zig build test --summary" },
        .{ "992", "palash", "12.3", "08.1", "tailscaled" },
        .{ "4431", "palash", "07.9", "02.0", "zit demo render" },
    };
    for (rows) |row| try table.addRow(&row);
    table.show_grid = false;
    table.border = .rounded;
    table.selected_row = 0;
    try table.widget.layout(layout.Rect.init(1, 5, 78, 15));
    try table.widget.draw(&mock.renderer);

    var status = try widget.StatusBar.init(alloc);
    defer status.deinit();
    status.setSegments("load: 1.04 0.98 0.77", "htop-clone", "q quit");
    try status.widget.layout(layout.Rect.init(0, 22, 80, 1));
    try status.widget.draw(&mock.renderer);

    var snap = try mock.snapshot(alloc);
    defer snap.deinit(alloc);
    try snap.expectWellFormed();
    try snap.expectContains("1203");
    try snap.expectContains("zig build test");
    try snap.expectContains("htop-clone");
}

test "real-world file manager snapshot remains well formed" {
    const alloc = std.testing.allocator;
    var mock = try MockTerminal.init(alloc, 80, 22);
    defer mock.deinit();

    var crumbs = try widget.Breadcrumbs.init(alloc, &[_][]const u8{ "home", "dev", "projects", "zit" });
    defer crumbs.deinit();
    try crumbs.widget.layout(layout.Rect.init(1, 0, 60, 1));
    try crumbs.widget.draw(&mock.renderer);

    var toolbar = try widget.Toolbar.init(alloc, &[_][]const u8{ "Open", "New Folder", "Delete", "Refresh" });
    defer toolbar.deinit();
    toolbar.setActive(1);
    try toolbar.widget.layout(layout.Rect.init(0, 1, 80, 1));
    try toolbar.widget.draw(&mock.renderer);

    var table = try widget.Table.init(alloc);
    defer table.deinit();
    try table.addColumn("Name", 28, true);
    try table.addColumn("Type", 10, true);
    try table.addColumn("Size", 8, true);
    try table.addColumn("Modified", 20, true);
    const rows = [_][4][]const u8{
        .{ "src", "dir", "-", "2024-04-02 10:12" },
        .{ "examples", "dir", "-", "2024-04-01 08:31" },
        .{ "README.md", "file", "12 KB", "2024-03-30 18:04" },
        .{ "build.zig", "file", "6 KB", "2024-03-30 17:59" },
    };
    for (rows) |row| try table.addRow(&row);
    table.selected_row = 2;
    table.border = .double;
    try table.widget.layout(layout.Rect.init(1, 3, 78, 15));
    try table.widget.draw(&mock.renderer);

    var status = try widget.StatusBar.init(alloc);
    defer status.deinit();
    status.setSegments("4 items", "file manager", "F5 refresh");
    try status.widget.layout(layout.Rect.init(0, 20, 80, 1));
    try status.widget.draw(&mock.renderer);

    var snap = try mock.snapshot(alloc);
    defer snap.deinit(alloc);
    try snap.expectWellFormed();
    try snap.expectContains("README.md");
    try snap.expectContains("file manager");
    try snap.expectContains("New Folder");
}

test "real-world dashboard snapshot remains well formed" {
    const alloc = std.testing.allocator;
    var mock = try MockTerminal.init(alloc, 80, 22);
    defer mock.deinit();

    var toolbar = try widget.Toolbar.init(alloc, &[_][]const u8{ "Overview", "Pipelines", "Alerts", "Settings" });
    defer toolbar.deinit();
    toolbar.setActive(0);
    try toolbar.widget.layout(layout.Rect.init(0, 0, 80, 1));
    try toolbar.widget.draw(&mock.renderer);

    var rating = try widget.RatingStars.init(alloc, 5);
    defer rating.deinit();
    rating.setValue(4);
    try rating.widget.layout(layout.Rect.init(2, 2, 10, 1));
    try rating.widget.draw(&mock.renderer);
    mock.renderer.drawStr(13, 2, "service health", render.Color.named(.bright_white), render.Color.named(.default), render.Style{});

    var wizard = try widget.WizardStepper.init(alloc, &[_][]const u8{ "Build", "Test", "Deploy", "Verify" });
    defer wizard.deinit();
    wizard.setStep(2);
    try wizard.widget.layout(layout.Rect.init(2, 6, 70, 2));
    try wizard.widget.draw(&mock.renderer);

    var center = try widget.NotificationCenter.init(alloc);
    defer center.deinit();
    try center.push("Deploy", "p99 +8ms", .warning);
    try center.push("Canary", "2 pods pending", .info);
    try center.widget.layout(layout.Rect.init(2, 9, 50, 5));
    try center.widget.draw(&mock.renderer);

    var status = try widget.StatusBar.init(alloc);
    defer status.deinit();
    status.setSegments("status: green", "dashboard", "shift+q quit");
    try status.widget.layout(layout.Rect.init(0, 20, 80, 1));
    try status.widget.draw(&mock.renderer);

    var snap = try mock.snapshot(alloc);
    defer snap.deinit(alloc);
    try snap.expectWellFormed();
    try snap.expectContains("service health");
    try snap.expectContains("Deploy");
    try snap.expectContains("dashboard");
}

test "real-world editor snapshot remains well formed" {
    const alloc = std.testing.allocator;
    var mock = try MockTerminal.init(alloc, 80, 20);
    defer mock.deinit();

    mock.renderer.fillRect(0, 0, 80, 16, ' ', render.Color.named(.bright_white), render.Color.named(.black), render.Style{});
    const lines = [_][]const u8{
        "fn main() !void {",
        "    var app = try zit.quickstart.renderText(\"Hello\", .{});",
        "    _ = app;",
        "}",
        "",
        "// Press : to open the palette",
    };
    for (lines, 0..) |line, idx| {
        mock.renderer.drawStr(2, @intCast(idx + 1), line, render.Color.named(.bright_white), render.Color.named(.black), render.Style{});
    }

    var palette = try widget.CommandPalette.init(alloc, &[_][]const u8{
        "Save file",
        "Close buffer",
        "Toggle minimap",
        "Search symbol",
        "Replace in file",
    });
    defer palette.deinit();
    palette.setQuery(":");
    palette.selected = 3;
    try palette.widget.layout(layout.Rect.init(10, 7, 60, 8));
    try palette.widget.draw(&mock.renderer);

    var status = try widget.StatusBar.init(alloc);
    defer status.deinit();
    status.setSegments("main.zig  UTF-8  LF", "INSERT", "Ln 42, Col 3");
    try status.widget.layout(layout.Rect.init(0, 18, 80, 1));
    try status.widget.draw(&mock.renderer);

    var snap = try mock.snapshot(alloc);
    defer snap.deinit(alloc);
    try snap.expectWellFormed();
    try snap.expectContains("renderText");
    try snap.expectContains("Search symbol");
    try snap.expectContains("Ln 42");
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

test "snapshot progress bar 0 percent" {
    const alloc = std.testing.allocator;
    var bar_builder = widget.ProgressBarBuilder.init(alloc);
    var bar = try bar_builder.percentage(0).build();
    defer bar.deinit();

    var harness = try WidgetHarness.init(alloc, layout.Size.init(12, 1));
    defer harness.deinit();
    try harness.expectGolden(&bar.widget, "src/testing/golden/progress_bar_0.snap", .{});
}

test "snapshot progress bar 50 percent" {
    const alloc = std.testing.allocator;
    var bar_builder = widget.ProgressBarBuilder.init(alloc);
    var bar = try bar_builder.percentage(50).build();
    defer bar.deinit();

    var harness = try WidgetHarness.init(alloc, layout.Size.init(12, 1));
    defer harness.deinit();
    try harness.expectGolden(&bar.widget, "src/testing/golden/progress_bar_50.snap", .{});
}

test "snapshot progress bar 100 percent" {
    const alloc = std.testing.allocator;
    var bar_builder = widget.ProgressBarBuilder.init(alloc);
    var bar = try bar_builder.percentage(100).build();
    defer bar.deinit();

    var harness = try WidgetHarness.init(alloc, layout.Size.init(12, 1));
    defer harness.deinit();
    try harness.expectGolden(&bar.widget, "src/testing/golden/progress_bar_100.snap", .{});
}

test "snapshot list with items" {
    const alloc = std.testing.allocator;
    var list = try widget.List.init(alloc);
    defer list.deinit();
    const Items = struct {
        items: []const []const u8,
        fn count(ctx: ?*anyopaque) usize {
            const data = @as(*@This(), @ptrCast(@alignCast(ctx.?)));
            return data.items.len;
        }
        fn itemAt(index: usize, ctx: ?*anyopaque) []const u8 {
            const data = @as(*@This(), @ptrCast(@alignCast(ctx.?)));
            return data.items[index];
        }
    };
    var items = Items{
        .items = &[_][]const u8{ "One", "Two", "Three" },
    };
    list.useItemProvider(.{
        .ctx = &items,
        .count = Items.count,
        .item_at = Items.itemAt,
    });

    var harness = try WidgetHarness.init(alloc, layout.Size.init(10, 3));
    defer harness.deinit();
    try harness.expectGolden(&list.widget, "src/testing/golden/list_items.snap", .{});
}

test "snapshot list empty" {
    const alloc = std.testing.allocator;
    var list = try widget.List.init(alloc);
    defer list.deinit();
    const Items = struct {
        items: []const []const u8,
        fn count(ctx: ?*anyopaque) usize {
            const data = @as(*@This(), @ptrCast(@alignCast(ctx.?)));
            return data.items.len;
        }
        fn itemAt(index: usize, ctx: ?*anyopaque) []const u8 {
            const data = @as(*@This(), @ptrCast(@alignCast(ctx.?)));
            return data.items[index];
        }
    };
    var items = Items{
        .items = &[_][]const u8{},
    };
    list.useItemProvider(.{
        .ctx = &items,
        .count = Items.count,
        .item_at = Items.itemAt,
    });

    var harness = try WidgetHarness.init(alloc, layout.Size.init(10, 3));
    defer harness.deinit();
    try harness.expectGolden(&list.widget, "src/testing/golden/list_empty.snap", .{});
}

test "snapshot list selected state" {
    const alloc = std.testing.allocator;
    var list = try widget.List.init(alloc);
    defer list.deinit();
    const Items = struct {
        items: []const []const u8,
        fn count(ctx: ?*anyopaque) usize {
            const data = @as(*@This(), @ptrCast(@alignCast(ctx.?)));
            return data.items.len;
        }
        fn itemAt(index: usize, ctx: ?*anyopaque) []const u8 {
            const data = @as(*@This(), @ptrCast(@alignCast(ctx.?)));
            return data.items[index];
        }
    };
    var items = Items{
        .items = &[_][]const u8{ "One", "Two", "Three" },
    };
    list.useItemProvider(.{
        .ctx = &items,
        .count = Items.count,
        .item_at = Items.itemAt,
    });
    list.setSelectedIndex(1);
    list.widget.focused = true;

    var harness = try WidgetHarness.init(alloc, layout.Size.init(10, 3));
    defer harness.deinit();
    try harness.expectGolden(&list.widget, "src/testing/golden/list_selected.snap", .{});
}

test "snapshot table with headers and data" {
    const alloc = std.testing.allocator;
    var builder = widget.TableBuilder.init(alloc);
    _ = try builder.addColumn(.{ .header = "Name", .width = 8 });
    _ = try builder.addColumn(.{ .header = "Qty", .width = 6 });
    var table = try builder.build();
    defer table.deinit();
    try table.addRow(&.{ "Apples", "5" });
    try table.addRow(&.{ "Oranges", "12" });

    var harness = try WidgetHarness.init(alloc, layout.Size.init(14, 4));
    defer harness.deinit();
    try harness.expectGolden(&table.widget, "src/testing/golden/table_basic.snap", .{});
}

test "snapshot modal with content" {
    const alloc = std.testing.allocator;
    var modal = try widget.Modal.init(alloc);
    defer modal.deinit();
    try modal.setTitle("Confirm");
    modal.width = 20;
    modal.height = 6;

    var label_builder = widget.LabelBuilder.init(alloc);
    var label = try label_builder.content("Proceed?").build();
    defer label.deinit();
    modal.setContent(&label.widget);

    var harness = try WidgetHarness.init(alloc, layout.Size.init(24, 8));
    defer harness.deinit();
    try harness.expectGolden(&modal.widget, "src/testing/golden/modal_basic.snap", .{});
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
