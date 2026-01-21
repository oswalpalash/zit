const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");

/// TableCell structure
pub const TableCell = struct {
    /// Cell text
    text: []const u8,
    /// Custom foreground color (optional)
    fg: ?render.Color = null,
    /// Custom background color (optional)
    bg: ?render.Color = null,
};

/// TableColumn structure
pub const TableColumn = struct {
    /// Column header
    header: []const u8,
    /// Column width
    width: u16,
    /// Column is resizable
    resizable: bool = true,
};

/// Table widget for displaying tabular data
pub const Table = struct {
    /// Base widget
    widget: base.Widget,
    /// Table columns
    columns: std.ArrayList(TableColumn),
    /// Table rows (ArrayLists of TableCells)
    rows: std.ArrayList(std.ArrayList(TableCell)),
    /// Selected row index
    selected_row: ?usize = null,
    /// First visible row index
    first_visible_row: usize = 0,
    /// Show headers
    show_headers: bool = true,
    /// Border style
    border: render.BorderStyle = .none,
    /// Foreground color
    fg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    /// Background color
    bg: render.Color = render.Color{ .named_color = render.NamedColor.default },
    /// Header foreground color
    header_fg: render.Color = render.Color{ .named_color = render.NamedColor.white },
    /// Header background color
    header_bg: render.Color = render.Color{ .named_color = render.NamedColor.blue },
    /// Selected row foreground color
    selected_fg: render.Color = render.Color{ .named_color = render.NamedColor.black },
    /// Selected row background color
    selected_bg: render.Color = render.Color{ .named_color = render.NamedColor.cyan },
    /// Focused foreground color
    focused_fg: render.Color = render.Color{ .named_color = render.NamedColor.black },
    /// Focused background color
    focused_bg: render.Color = render.Color{ .named_color = render.NamedColor.white },
    /// Grid foreground color
    grid_fg: render.Color = render.Color{ .named_color = render.NamedColor.bright_black },
    /// Show grid
    show_grid: bool = true,
    /// On row selected callback
    on_row_selected: ?*const fn (usize) void = null,
    /// Allocator for table operations
    allocator: std.mem.Allocator,
    /// Rolling buffer for incremental search
    search_buffer: [64]u8 = undefined,
    /// Current length of the incremental search query
    search_len: usize = 0,
    /// Timestamp of the last search keystroke in milliseconds
    last_search_ms: ?i64 = null,
    /// How long to keep appending to the search buffer (in milliseconds)
    search_timeout_ms: u64 = 900,
    /// Clock source (primarily overridden in tests)
    clock: *const fn () i64 = std.time.milliTimestamp,

    /// Virtual method table for Table
    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    /// Initialize a new table
    pub fn init(allocator: std.mem.Allocator) !*Table {
        const self = try allocator.create(Table);

        self.* = Table{
            .widget = base.Widget.init(&vtable),
            .columns = std.ArrayList(TableColumn).empty,
            .rows = std.ArrayList(std.ArrayList(TableCell)).empty,
            .allocator = allocator,
        };

        return self;
    }

    /// Clean up table resources
    pub fn deinit(self: *Table) void {
        // Free column headers
        for (self.columns.items) |column| {
            self.allocator.free(column.header);
        }
        self.columns.deinit(self.allocator);

        // Free row cell text
        for (self.rows.items) |*row| {
            for (row.items) |cell| {
                self.allocator.free(cell.text);
            }
            row.deinit(self.allocator);
        }
        self.rows.deinit(self.allocator);

        self.allocator.destroy(self);
    }

    /// Add a column to the table
    pub fn addColumn(self: *Table, header: []const u8, width: u16, resizable: bool) !void {
        try self.columns.ensureUnusedCapacity(self.allocator, 1);
        const header_copy = try self.allocator.dupe(u8, header);
        const column_width = if (width == 0) @as(u16, 1) else width;

        self.columns.appendAssumeCapacity(TableColumn{
            .header = header_copy,
            .width = column_width,
            .resizable = resizable,
        });
    }

    /// Add a row to the table
    pub fn addRow(self: *Table, cells: []const []const u8) !void {
        var new_row = std.ArrayList(TableCell).empty;
        errdefer self.freeRow(&new_row);
        try new_row.ensureTotalCapacityPrecise(self.allocator, self.columns.items.len);

        for (cells, 0..) |text, i| {
            if (i >= self.columns.items.len) break;

            const text_copy = try self.allocator.dupe(u8, text);
            new_row.appendAssumeCapacity(TableCell{
                .text = text_copy,
                .fg = null,
                .bg = null,
            });
        }

        // Fill remaining columns with empty cells if needed
        while (new_row.items.len < self.columns.items.len) {
            try new_row.ensureUnusedCapacity(self.allocator, 1);
            const empty_text = try self.allocator.alloc(u8, 0);
            new_row.appendAssumeCapacity(TableCell{
                .text = empty_text,
                .fg = null,
                .bg = null,
            });
        }

        try self.rows.append(self.allocator, new_row);
    }

    /// Set a cell value
    pub fn setCell(self: *Table, row: usize, col: usize, text: []const u8, fg: ?render.Color, bg: ?render.Color) !void {
        if (row >= self.rows.items.len or col >= self.columns.items.len) {
            return error.IndexOutOfBounds;
        }

        // Free existing text
        self.allocator.free(self.rows.items[row].items[col].text);

        // Copy new text
        const text_copy = try self.allocator.alloc(u8, text.len);
        @memcpy(text_copy, text);

        // Update cell
        self.rows.items[row].items[col] = TableCell{
            .text = text_copy,
            .fg = fg,
            .bg = bg,
        };
    }

    /// Remove a row from the table
    pub fn removeRow(self: *Table, row: usize) void {
        if (row >= self.rows.items.len) {
            return;
        }

        // Free all cell text in the row
        for (self.rows.items[row].items) |cell| {
            self.allocator.free(cell.text);
        }

        // Remove the row
        self.rows.items[row].deinit(self.allocator);
        _ = self.rows.orderedRemove(row);

        // Update selected row if needed
        if (self.selected_row != null and self.selected_row.? >= self.rows.items.len) {
            self.selected_row = if (self.rows.items.len > 0) self.rows.items.len - 1 else null;
        }
    }

    /// Clear all rows from the table
    pub fn clearRows(self: *Table) void {
        // Free all row cell text
        for (self.rows.items) |*row| {
            for (row.items) |cell| {
                self.allocator.free(cell.text);
            }
            row.deinit(self.allocator);
        }

        self.rows.clearRetainingCapacity();
        self.selected_row = null;
        self.first_visible_row = 0;
        self.resetTypeahead();
    }

    fn freeRow(self: *Table, row: *std.ArrayList(TableCell)) void {
        for (row.items) |cell| {
            self.allocator.free(cell.text);
        }
        row.deinit(self.allocator);
    }

    /// Set the selected row
    pub fn setSelectedRow(self: *Table, row: ?usize) void {
        if (row != null and row.? >= self.rows.items.len) {
            return;
        }

        const old_selected = self.selected_row;
        self.selected_row = row;

        // Ensure selected row is visible
        if (row != null) {
            self.ensureRowVisible(row.?);
        }

        // Call the row selected callback
        if (old_selected != self.selected_row and self.on_row_selected != null and self.selected_row != null) {
            self.on_row_selected.?(self.selected_row.?);
        }
    }

    /// Ensure a row is visible by adjusting first_visible_row
    fn ensureRowVisible(self: *Table, row: usize) void {
        const visible_rows = self.getVisibleRowCount();

        if (row < self.first_visible_row) {
            self.first_visible_row = row;
        } else if (row >= self.first_visible_row + visible_rows) {
            self.first_visible_row = row - visible_rows + 1;
        }
    }

    /// Get the number of rows that can be displayed
    fn getVisibleRowCount(self: *Table) usize {
        var height = @as(usize, @intCast(self.widget.rect.height));

        if (self.show_headers) {
            height = if (height > 0) height - 1 else 0;
        }

        return height;
    }

    /// Set the show headers flag
    pub fn setShowHeaders(self: *Table, show_headers: bool) void {
        self.show_headers = show_headers;
    }

    /// Set the show grid flag
    pub fn setShowGrid(self: *Table, show_grid: bool) void {
        self.show_grid = show_grid;
    }

    /// Set the table colors
    pub fn setColors(self: *Table, fg: render.Color, bg: render.Color) void {
        self.fg = fg;
        self.bg = bg;
    }

    /// Set the header colors
    pub fn setHeaderColors(self: *Table, header_fg: render.Color, header_bg: render.Color) void {
        self.header_fg = header_fg;
        self.header_bg = header_bg;
    }

    /// Set the selected row colors
    pub fn setSelectedColors(self: *Table, selected_fg: render.Color, selected_bg: render.Color) void {
        self.selected_fg = selected_fg;
        self.selected_bg = selected_bg;
    }

    /// Set the on-row-selected callback
    pub fn setOnRowSelected(self: *Table, callback: *const fn (usize) void) void {
        self.on_row_selected = callback;
    }

    /// Set the border style
    pub fn setBorder(self: *Table, border: render.BorderStyle) void {
        self.border = border;
    }

    /// Configure how long to keep accumulating typeahead search input.
    pub fn setTypeaheadTimeout(self: *Table, timeout_ms: u64) void {
        self.search_timeout_ms = timeout_ms;
    }

    /// Clear any buffered typeahead query.
    pub fn resetTypeahead(self: *Table) void {
        self.search_len = 0;
        self.last_search_ms = null;
    }

    /// Override the timing source used for typeahead (test-only hook).
    pub fn setTypeaheadClock(self: *Table, clock: *const fn () i64) void {
        self.clock = clock;
    }

    /// Draw implementation for Table
    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*Table, @ptrCast(@alignCast(widget_ptr)));

        if (!self.widget.visible or self.columns.items.len == 0) {
            return;
        }

        const rect = self.widget.rect;

        // Fill table background
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', self.fg, self.bg, render.Style{});

        var y = rect.y;
        var x = rect.x;

        // Draw headers if enabled
        if (self.show_headers) {
            x = rect.x;

            for (self.columns.items) |column| {
                if (@as(u16, @intCast(x)) + column.width > rect.x + rect.width) {
                    break;
                }

                // Draw header background
                renderer.fillRect(x, y, column.width, 1, ' ', self.header_fg, self.header_bg, render.Style{});

                // Draw header text
                for (column.header, 0..) |char, i| {
                    if (i >= @as(usize, @intCast(column.width - 1))) {
                        break;
                    }

                    renderer.drawChar(x + 1 + @as(u16, @intCast(i)), y, char, self.header_fg, self.header_bg, render.Style{});
                }

                // Draw grid if enabled
                if (self.show_grid and x > rect.x) {
                    renderer.drawChar(x, y, '│', self.grid_fg, self.header_bg, render.Style{});
                }

                x += column.width;
            }

            y += 1;

            // Draw horizontal grid line under headers if enabled
            if (self.show_grid) {
                x = rect.x;
                for (self.columns.items) |column| {
                    if (@as(u16, @intCast(x)) + column.width > rect.x + rect.width) {
                        break;
                    }

                    for (0..@as(usize, @intCast(column.width))) |i| {
                        const char: u21 = if (x > rect.x and i == 0) '┼' else '─';
                        renderer.drawChar(x + @as(u16, @intCast(i)), y - 1, char, self.grid_fg, self.bg, render.Style{});
                    }

                    x += column.width;
                }
            }
        }

        // Draw visible rows
        const visible_rows = self.getVisibleRowCount();
        const last_visible_row = @min(self.first_visible_row + visible_rows, self.rows.items.len);

        for (self.first_visible_row..last_visible_row) |row_idx| {
            const row = self.rows.items[row_idx];
            const is_selected = self.selected_row != null and row_idx == self.selected_row.?;

            x = rect.x;

            // Choose row colors based on selection and focus
            const row_fg = if (is_selected)
                (if (self.widget.focused) self.focused_fg else self.selected_fg)
            else
                self.fg;

            const row_bg = if (is_selected)
                (if (self.widget.focused) self.focused_bg else self.selected_bg)
            else
                self.bg;

            // Draw each cell in the row
            for (self.columns.items, 0..) |column, col_idx| {
                if (@as(u16, @intCast(x)) + column.width > rect.x + rect.width) {
                    break;
                }

                if (col_idx < row.items.len) {
                    const cell = row.items[col_idx];

                    // Choose cell colors, using row colors as default
                    const cell_fg = if (cell.fg != null) cell.fg.? else row_fg;
                    const cell_bg = if (cell.bg != null) cell.bg.? else row_bg;

                    // Draw cell background
                    renderer.fillRect(x, y, column.width, 1, ' ', cell_fg, cell_bg, render.Style{});

                    // Draw cell text
                    for (cell.text, 0..) |char, i| {
                        if (i >= @as(usize, @intCast(column.width - 1))) {
                            break;
                        }

                        renderer.drawChar(x + 1 + @as(u16, @intCast(i)), y, char, cell_fg, cell_bg, render.Style{});
                    }

                    // Draw grid if enabled
                    if (self.show_grid and x > rect.x) {
                        renderer.drawChar(x, y, '│', self.grid_fg, cell_bg, render.Style{});
                    }
                } else {
                    // Draw empty cell
                    renderer.fillRect(x, y, column.width, 1, ' ', row_fg, row_bg, render.Style{});

                    // Draw grid if enabled
                    if (self.show_grid and x > rect.x) {
                        renderer.drawChar(x, y, '│', self.grid_fg, row_bg, render.Style{});
                    }
                }

                x += column.width;
            }

            y += 1;
        }

        // Draw border if enabled
        if (self.border != .none) {
            renderer.drawBox(rect.x, rect.y, rect.width, rect.height, self.border, self.fg, self.bg, render.Style{});
        }
    }

    /// Event handling implementation for Table
    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*Table, @ptrCast(@alignCast(widget_ptr)));

        if (!self.widget.visible or !self.widget.enabled or self.rows.items.len == 0) {
            return false;
        }

        // Handle mouse events
        if (event == .mouse) {
            const mouse_event = event.mouse;
            const rect = self.widget.rect;

            // Ignore events on headers
            const header_offset: i16 = if (self.show_headers) 1 else 0;

            // Check if mouse is within table row bounds
            if (mouse_event.y >= rect.y + @as(u16, @intCast(header_offset)) and mouse_event.y < rect.y + rect.height and
                mouse_event.x >= rect.x and mouse_event.x < rect.x + rect.width)
            {

                // Convert y position to row index
                const row_idx = self.first_visible_row + @as(usize, @intCast(mouse_event.y - rect.y)) - @as(usize, @intCast(header_offset));

                if (row_idx < self.rows.items.len) {
                    // Select row on click
                    if (mouse_event.action == .press and mouse_event.button == 1) {
                        self.setSelectedRow(row_idx);
                        return true;
                    }
                }

                return true; // Capture all mouse events within bounds
            }

            // Mouse wheel scrolling
            if (mouse_event.action == .press and mouse_event.button == 4 and
                rect.contains(mouse_event.x, mouse_event.y))
            {
                // kept for backward compatibility with terminals sending button codes
                if (self.first_visible_row > 0) {
                    self.first_visible_row -= 1;
                    return true;
                }
            } else if (mouse_event.action == .press and mouse_event.button == 5 and
                rect.contains(mouse_event.x, mouse_event.y))
            {
                if (self.first_visible_row + self.getVisibleRowCount() < self.rows.items.len) {
                    self.first_visible_row += 1;
                    return true;
                }
            } else if ((mouse_event.action == .scroll_up or mouse_event.action == .scroll_down) and rect.contains(mouse_event.x, mouse_event.y)) {
                if (mouse_event.action == .scroll_up) {
                    if (self.first_visible_row > 0) {
                        self.first_visible_row -= 1;
                        return true;
                    }
                } else if (self.first_visible_row + self.getVisibleRowCount() < self.rows.items.len) {
                    self.first_visible_row += 1;
                    return true;
                }
            }
        }

        // Handle key events
        if (event == .key and self.widget.focused) {
            const key_event = event.key;
            const profiles = [_]input.KeybindingProfile{
                input.KeybindingProfile.commonEditing(),
                input.KeybindingProfile.emacs(),
                input.KeybindingProfile.vi(),
            };

            if (input.editorActionForEvent(key_event, &profiles)) |action| {
                switch (action) {
                    .cursor_down => {
                        if (self.selected_row == null) {
                            self.setSelectedRow(0);
                        } else if (self.selected_row.? < self.rows.items.len - 1) {
                            self.setSelectedRow(self.selected_row.? + 1);
                        }
                        self.resetTypeahead();
                        return true;
                    },
                    .cursor_up => {
                        if (self.selected_row == null) {
                            self.setSelectedRow(0);
                        } else if (self.selected_row.? > 0) {
                            self.setSelectedRow(self.selected_row.? - 1);
                        }
                        self.resetTypeahead();
                        return true;
                    },
                    .page_down => {
                        const visible_rows = self.getVisibleRowCount();

                        if (self.selected_row == null) {
                            self.setSelectedRow(0);
                        } else {
                            const new_row = @min(self.selected_row.? + visible_rows, self.rows.items.len - 1);
                            self.setSelectedRow(new_row);
                        }
                        self.resetTypeahead();
                        return true;
                    },
                    .page_up => {
                        if (self.selected_row == null) {
                            self.setSelectedRow(0);
                        } else {
                            const visible_rows = self.getVisibleRowCount();
                            const new_row = if (self.selected_row.? > visible_rows)
                                self.selected_row.? - visible_rows
                            else
                                0;
                            self.setSelectedRow(new_row);
                        }
                        self.resetTypeahead();
                        return true;
                    },
                    .line_start => {
                        self.setSelectedRow(0);
                        self.resetTypeahead();
                        return true;
                    },
                    .line_end => {
                        self.setSelectedRow(self.rows.items.len - 1);
                        self.resetTypeahead();
                        return true;
                    },
                    else => {},
                }
            }

            if (key_event.key == input.KeyCode.ESCAPE) {
                self.resetTypeahead();
                return false;
            } else if (key_event.isPrintable() and !key_event.modifiers.ctrl and !key_event.modifiers.alt) {
                if (self.handleTypeaheadKey(@as(u8, @intCast(key_event.key)))) {
                    return true;
                }
            }
        }

        return false;
    }

    fn handleTypeaheadKey(self: *Table, byte: u8) bool {
        if (self.rows.items.len == 0) {
            return false;
        }

        const now = self.clock();
        if (self.last_search_ms) |last| {
            if (now < last or @as(u64, @intCast(now - last)) > self.search_timeout_ms) {
                self.resetTypeahead();
            }
        }
        self.last_search_ms = now;

        if (self.search_len < self.search_buffer.len) {
            self.search_buffer[self.search_len] = std.ascii.toLower(byte);
            self.search_len += 1;
        } else {
            std.mem.copyForwards(u8, self.search_buffer[0 .. self.search_buffer.len - 1], self.search_buffer[1..]);
            self.search_buffer[self.search_buffer.len - 1] = std.ascii.toLower(byte);
            self.search_len = self.search_buffer.len;
        }

        const needle = self.search_buffer[0..self.search_len];
        if (needle.len == 0) return false;

        const start = self.selected_row orelse 0;
        var i: usize = 0;
        while (i < self.rows.items.len) : (i += 1) {
            const idx = (start + i) % self.rows.items.len;
            if (rowStartsWith(self.rows.items[idx], needle)) {
                self.setSelectedRow(idx);
                return true;
            }
        }

        return false;
    }

    fn rowStartsWith(row: std.ArrayList(TableCell), needle: []const u8) bool {
        if (needle.len == 0) return false;

        for (row.items) |cell| {
            if (cell.text.len == 0) continue;
            if (startsWithIgnoreCase(cell.text, needle)) return true;
        }
        return false;
    }

    fn startsWithIgnoreCase(haystack: []const u8, needle: []const u8) bool {
        if (needle.len == 0 or needle.len > haystack.len) {
            return false;
        }

        var i: usize = 0;
        while (i < needle.len) : (i += 1) {
            if (std.ascii.toLower(haystack[i]) != needle[i]) {
                return false;
            }
        }
        return true;
    }

    /// Layout implementation for Table
    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*Table, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;

        // Ensure selected row is still visible after layout
        if (self.selected_row != null) {
            self.ensureRowVisible(self.selected_row.?);
        }
    }

    /// Get preferred size implementation for Table
    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*Table, @ptrCast(@alignCast(widget_ptr)));

        // Calculate width based on columns
        var width: u16 = 0;
        for (self.columns.items) |column| {
            const expanded: u32 = @as(u32, width) + column.width;
            width = @intCast(@min(expanded, @as(u32, std.math.maxInt(u16))));
        }

        // Preferred height depends on number of rows plus header
        const header_height: u16 = if (self.show_headers) 1 else 0;
        const rows_height = @min(20, @as(u16, @intCast(self.rows.items.len)));
        const height = header_height + rows_height;

        return layout_module.Size.init(width, height);
    }

    /// Can focus implementation for Table
    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*Table, @ptrCast(@alignCast(widget_ptr)));
        return self.widget.enabled and self.rows.items.len > 0;
    }
};

test "table typeahead search finds matching rows" {
    const alloc = std.testing.allocator;
    var table = try Table.init(alloc);
    defer table.deinit();

    try table.addColumn("Name", 12, true);
    try table.addColumn("Details", 16, true);

    try table.addRow(&.{ "Alpha", "First" });
    try table.addRow(&.{ "Garden", "Plants" });
    try table.addRow(&.{ "Gamma", "Third" });
    try table.addRow(&.{ "Zeta", "Last" });

    table.widget.focused = true;
    try table.widget.layout(layout_module.Rect.init(0, 0, 30, 4));
    table.setSelectedRow(0);

    const TestClock = struct {
        var now: i64 = 0;
        fn tick() i64 {
            return now;
        }
    };

    table.setTypeaheadClock(TestClock.tick);
    table.setTypeaheadTimeout(1_000);

    _ = try table.handleEvent(.{ .key = .{ .key = 'g', .modifiers = .{} } });
    try std.testing.expectEqual(@as(usize, 1), table.selected_row.?); // Garden

    _ = try table.handleEvent(.{ .key = .{ .key = 'a', .modifiers = .{} } });
    try std.testing.expectEqual(@as(usize, 1), table.selected_row.?); // "ga" still Garden

    TestClock.now = 5_000; // Exceeds timeout, clears buffer.
    _ = try table.handleEvent(.{ .key = .{ .key = 'z', .modifiers = .{} } });
    try std.testing.expectEqual(@as(usize, 3), table.selected_row.?); // Zeta
}

test "table preferred size clamps large widths" {
    const alloc = std.testing.allocator;
    var table = try Table.init(alloc);
    defer table.deinit();

    try table.addColumn("A", std.math.maxInt(u16), true);
    try table.addColumn("B", std.math.maxInt(u16), true);

    const size = try Table.getPreferredSizeFn(@ptrCast(@alignCast(table)));
    try std.testing.expectEqual(std.math.maxInt(u16), size.width);
}

test "table ignores input when empty" {
    const alloc = std.testing.allocator;
    var table = try Table.init(alloc);
    defer table.deinit();

    try table.widget.layout(layout_module.Rect.init(0, 0, 10, 5));
    const handled = try table.handleEvent(.{ .key = .{ .key = input.KeyCode.DOWN, .modifiers = .{} } });
    try std.testing.expectEqual(false, handled);
}
