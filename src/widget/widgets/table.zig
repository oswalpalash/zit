const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const memory = @import("../../memory/memory.zig");
const animation = @import("../animation.zig");
const theme = @import("../theme.zig");
const accessibility = @import("../accessibility.zig");
const compat = @import("../../compat.zig");

/// TableCell structure
pub const TableCell = struct {
    /// Cell text
    text: []const u8,
    /// Custom foreground color (optional)
    fg: ?render.Color = null,
    /// Custom background color (optional)
    bg: ?render.Color = null,
};

/// Lightweight view returned by virtual row providers.
pub const TableCellView = struct {
    text: []const u8,
    fg: ?render.Color = null,
    bg: ?render.Color = null,
};

const ViewRow = union(enum) {
    data: usize,
    group: []u8,
};

/// TableColumn structure
pub const TableColumn = struct {
    /// Column header
    header: []const u8,
    /// Column width
    width: u16,
    /// Column is resizable
    resizable: bool = true,
    /// Column can be sorted via header interactions
    sortable: bool = true,
};

/// Delegate for supplying table rows without storing them in the widget.
pub const RowProvider = struct {
    ctx: ?*anyopaque = null,
    row_count: *const fn (?*anyopaque) usize,
    cell_at: *const fn (usize, usize, ?*anyopaque) TableCellView,
};

/// Table widget for displaying tabular data
pub const Table = struct {
    /// Base widget
    widget: base.Widget,
    /// Table columns
    columns: std.ArrayList(TableColumn),
    /// Table rows (ArrayLists of TableCells)
    rows: std.ArrayList(std.ArrayList(TableCell)),
    /// Virtual row provider for huge datasets
    row_provider: ?RowProvider = null,
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
    on_row_select: ?*const fn (usize) void = null,
    /// Allocator for table operations
    allocator: std.mem.Allocator,
    /// Optional string interner for deduplicating cell/header text
    string_intern: ?memory.StringInterner = null,
    /// Rolling buffer for incremental search
    search_buffer: [64]u8 = undefined,
    /// Current length of the incremental search query
    search_len: usize = 0,
    /// Timestamp of the last search keystroke in milliseconds
    last_search_ms: ?i64 = null,
    /// How long to keep appending to the search buffer (in milliseconds)
    search_timeout_ms: u64 = 900,
    /// Clock source (primarily overridden in tests)
    clock: *const fn () i64 = compat.nowMillis,
    /// Optional animator for smooth scrolling
    animator: ?*animation.Animator = null,
    /// Scroll easing driver
    scroll_driver: animation.ValueDriver = .{},
    /// Scroll animation duration
    scroll_duration_ms: u64 = 140,
    /// Momentum multiplier for wheel deltas
    momentum_multiplier: f32 = 3,
    /// Limit how many rows are sampled for preferred size
    virtual_sample_limit: usize = 256,
    /// Limit for typeahead search when using providers
    typeahead_scan_limit: usize = 1024,
    /// Optional sort column
    sort_column: ?usize = null,
    /// Sort direction
    sort_descending: bool = false,
    /// Optional grouping column
    grouping_column: ?usize = null,
    /// Ordered list of row indices after sorting/grouping
    visible_order: std.ArrayList(usize),
    /// View rows including group headers
    view_rows: std.ArrayList(ViewRow),
    /// Whether the view needs to be rebuilt
    view_dirty: bool = true,
    /// Column currently active for cell-level operations
    selected_column: usize = 0,
    /// Active resize state
    resizing_column: ?usize = null,
    resize_anchor_x: u16 = 0,
    resize_original_width: u16 = 0,
    /// Inline editing buffer
    edit_buffer: std.ArrayListUnmanaged(u8),
    editing_row: ?usize = null,
    editing_col: ?usize = null,

    fn fromWidgetPtr(widget_ptr: *anyopaque) *Table {
        const widget = @as(*base.Widget, @ptrCast(@alignCast(widget_ptr)));
        return @as(*Table, @fieldParentPtr("widget", widget));
    }

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
            .visible_order = std.ArrayList(usize).empty,
            .view_rows = std.ArrayList(ViewRow).empty,
            .view_dirty = true,
            .edit_buffer = .empty,
        };
        self.setTheme(theme.Theme.dark());
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.list), "Table", "");

        return self;
    }

    /// Clean up table resources
    pub fn deinit(self: *Table) void {
        const using_intern = self.string_intern != null;

        // Free column headers
        for (self.columns.items) |column| {
            if (!using_intern) self.allocator.free(column.header);
        }
        self.columns.deinit(self.allocator);

        // Free row cell text
        for (self.rows.items) |*row| {
            if (!using_intern) {
                for (row.items) |cell| {
                    self.allocator.free(cell.text);
                }
            }
            row.deinit(self.allocator);
        }
        self.rows.deinit(self.allocator);

        if (self.string_intern) |*intern| intern.deinit();
        self.visible_order.deinit(self.allocator);
        self.clearViewRows();
        self.view_rows.deinit(self.allocator);
        self.edit_buffer.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    /// Add a column to the table
    pub fn addColumn(self: *Table, header: []const u8, width: u16, resizable: bool) !void {
        try self.columns.ensureUnusedCapacity(self.allocator, 1);
        const header_copy = try self.ownText(header);
        const column_width = if (width == 0) @as(u16, 1) else width;

        self.columns.appendAssumeCapacity(TableColumn{
            .header = header_copy,
            .width = column_width,
            .resizable = resizable,
        });
        self.view_dirty = true;
    }

    /// Enable or disable sorting on a given column.
    pub fn setColumnSortable(self: *Table, column: usize, sortable: bool) void {
        if (column >= self.columns.items.len) return;
        self.columns.items[column].sortable = sortable;
    }

    /// Manually adjust a column width (used by programmatic resize or keyboard).
    pub fn setColumnWidth(self: *Table, column: usize, width: u16) void {
        if (column >= self.columns.items.len) return;
        const clamped = @max(@as(u16, 3), width);
        self.columns.items[column].width = clamped;
    }

    /// Sort the table by the given column (or clear sorting when null).
    pub fn sortBy(self: *Table, column: ?usize, descending: bool) void {
        if (column) |idx| {
            if (idx >= self.columns.items.len or !self.columns.items[idx].sortable) return;
        }
        self.sort_column = column;
        self.sort_descending = descending;
        self.view_dirty = true;
    }

    /// Toggle sort state for the given column.
    pub fn toggleSort(self: *Table, column: usize) void {
        if (column >= self.columns.items.len or !self.columns.items[column].sortable) return;
        if (self.sort_column != null and self.sort_column.? == column) {
            self.sort_descending = !self.sort_descending;
        } else {
            self.sort_column = column;
            self.sort_descending = false;
        }
        self.view_dirty = true;
    }

    /// Group rows by the provided column (null disables grouping).
    pub fn groupBy(self: *Table, column: ?usize) void {
        if (column) |idx| {
            if (idx >= self.columns.items.len) return;
        }
        self.grouping_column = column;
        self.view_dirty = true;
    }

    /// Resize a resizable column by the provided delta.
    pub fn resizeColumn(self: *Table, column: usize, delta: i16) void {
        if (column >= self.columns.items.len) return;
        if (!self.columns.items[column].resizable) return;
        const base_width = self.columns.items[column].width;
        const updated = std.math.clamp(@as(i32, base_width) + @as(i32, delta), 3, @as(i32, std.math.maxInt(u16)));
        self.columns.items[column].width = @intCast(updated);
    }

    /// Add a row to the table
    pub fn addRow(self: *Table, cells: []const []const u8) !void {
        if (self.row_provider != null) return error.VirtualRowsActive;
        var new_row = std.ArrayList(TableCell).empty;
        errdefer self.freeRow(&new_row);
        try new_row.ensureTotalCapacityPrecise(self.allocator, self.columns.items.len);

        for (cells, 0..) |text, i| {
            if (i >= self.columns.items.len) break;

            const text_copy = try self.ownText(text);
            new_row.appendAssumeCapacity(TableCell{
                .text = text_copy,
                .fg = null,
                .bg = null,
            });
        }

        // Fill remaining columns with empty cells if needed
        while (new_row.items.len < self.columns.items.len) {
            try new_row.ensureUnusedCapacity(self.allocator, 1);
            const empty_text = try self.ownText("");
            new_row.appendAssumeCapacity(TableCell{
                .text = empty_text,
                .fg = null,
                .bg = null,
            });
        }

        try self.rows.append(self.allocator, new_row);
        self.view_dirty = true;
    }

    /// Set a cell value
    pub fn setCell(self: *Table, row: usize, col: usize, text: []const u8, fg: ?render.Color, bg: ?render.Color) !void {
        if (self.row_provider != null) return error.VirtualRowsActive;
        if (row >= self.rows.items.len or col >= self.columns.items.len) {
            return error.IndexOutOfBounds;
        }

        const text_copy = try self.ownText(text);
        const previous = self.rows.items[row].items[col].text;

        self.rows.items[row].items[col] = TableCell{
            .text = text_copy,
            .fg = fg,
            .bg = bg,
        };
        if (self.string_intern == null) {
            self.allocator.free(previous);
        }
        self.view_dirty = true;
    }

    fn isEditing(self: *const Table) bool {
        return self.editing_row != null and self.editing_col != null;
    }

    /// Begin inline editing on the currently selected cell.
    pub fn beginEdit(self: *Table) !void {
        if (self.row_provider != null) return error.VirtualRowsActive;
        if (self.selected_row == null or self.selected_column >= self.columns.items.len) return;

        const data_row = self.selected_row.?;
        const next_text = self.cellView(data_row, self.selected_column).text;
        try self.edit_buffer.ensureTotalCapacity(self.allocator, next_text.len);
        self.edit_buffer.clearRetainingCapacity();
        self.edit_buffer.appendSliceAssumeCapacity(next_text);
        self.editing_row = data_row;
        self.editing_col = self.selected_column;
    }

    /// Commit any active inline edit.
    pub fn commitEdit(self: *Table) !void {
        if (!self.isEditing()) return;
        try self.setCell(self.editing_row.?, self.editing_col.?, self.edit_buffer.items, null, null);
        self.cancelEdit();
    }

    /// Cancel inline editing without applying changes.
    pub fn cancelEdit(self: *Table) void {
        self.edit_buffer.clearRetainingCapacity();
        self.editing_row = null;
        self.editing_col = null;
    }

    fn handleEditKey(self: *Table, key_event: input.KeyEvent) !bool {
        if (!self.isEditing()) return false;
        if (key_event.key == input.KeyCode.ESCAPE) {
            self.cancelEdit();
            return true;
        }
        if (key_event.key == input.KeyCode.ENTER) {
            try self.commitEdit();
            return true;
        }
        if (key_event.key == input.KeyCode.BACKSPACE) {
            if (self.edit_buffer.items.len > 0) {
                _ = self.edit_buffer.pop();
            }
            return true;
        }
        if (key_event.isPrintable() and !key_event.modifiers.ctrl and !key_event.modifiers.alt) {
            try self.edit_buffer.append(self.allocator, @as(u8, @intCast(key_event.key)));
            return true;
        }
        return false;
    }

    /// Enable string interning for all future cell/header text.
    pub fn enableStringInterning(self: *Table) !void {
        if (self.string_intern != null) return;

        var intern = try memory.StringInterner.init(self.allocator);
        errdefer intern.deinit();

        // First populate the interner without mutating ownership. If an
        // allocation fails, the table remains a normal non-interned table.
        for (self.columns.items) |*column| {
            _ = try intern.intern(column.header);
        }

        for (self.rows.items) |*row| {
            for (row.items) |*cell| {
                _ = try intern.intern(cell.text);
            }
        }

        // All interning succeeded, so ownership can be migrated in place.
        for (self.columns.items) |*column| {
            const previous = column.header;
            const interned = try intern.intern(previous);
            column.header = interned;
            self.allocator.free(previous);
        }

        for (self.rows.items) |*row| {
            for (row.items) |*cell| {
                const previous = cell.text;
                const interned = try intern.intern(previous);
                cell.text = interned;
                self.allocator.free(previous);
            }
        }

        self.string_intern = intern;
    }

    /// Inspect interner stats if interning is enabled.
    pub fn stringInternStats(self: *Table) ?memory.StringInterner.Stats {
        if (self.string_intern) |*intern| return intern.stats();
        return null;
    }

    /// Remove a row from the table
    pub fn removeRow(self: *Table, row: usize) void {
        if (self.row_provider != null) return;
        if (row >= self.rows.items.len) {
            return;
        }

        const previous_selected = self.selected_row;
        const previous_editing = self.editing_row;

        // Free all cell text in the row
        if (self.string_intern == null) {
            for (self.rows.items[row].items) |cell| {
                self.allocator.free(cell.text);
            }
        }

        // Remove the row
        self.rows.items[row].deinit(self.allocator);
        _ = self.rows.orderedRemove(row);

        // Update selected row if needed
        var notify_replacement = false;
        if (previous_selected) |selected| {
            if (self.rows.items.len == 0) {
                self.selected_row = null;
            } else if (row < selected) {
                self.selected_row = selected - 1;
            } else if (row == selected) {
                self.selected_row = @min(selected, self.rows.items.len - 1);
                notify_replacement = true;
            } else if (selected >= self.rows.items.len) {
                self.selected_row = self.rows.items.len - 1;
                notify_replacement = true;
            }
        }

        if (previous_editing) |editing| {
            if (row < editing) {
                self.editing_row = editing - 1;
            } else if (row == editing) {
                self.cancelEdit();
            }
        }

        self.view_dirty = true;
        if (self.selected_row) |selected| {
            self.ensureRowVisible(selected);
            if (notify_replacement and self.on_row_select != null) {
                self.on_row_select.?(selected);
            }
        } else {
            self.clampScroll();
        }
    }

    /// Clear all rows from the table
    pub fn clearRows(self: *Table) void {
        if (self.row_provider != null) {
            self.selected_row = null;
            self.first_visible_row = 0;
            self.resetTypeahead();
            self.view_dirty = true;
            return;
        }
        // Free all row cell text
        for (self.rows.items) |*row| {
            if (self.string_intern == null) {
                for (row.items) |cell| {
                    self.allocator.free(cell.text);
                }
            }
            row.deinit(self.allocator);
        }

        self.rows.clearRetainingCapacity();
        self.selected_row = null;
        self.first_visible_row = 0;
        self.resetTypeahead();
        self.cancelEdit();
        self.clearViewRows();
        self.visible_order.clearRetainingCapacity();
        self.view_dirty = true;
        if (self.string_intern) |*intern| {
            intern.clearRetainingCapacity();
        }
    }

    fn clearViewRows(self: *Table) void {
        for (self.view_rows.items) |row| {
            switch (row) {
                .group => |label| self.allocator.free(label),
                else => {},
            }
        }
        self.view_rows.clearRetainingCapacity();
    }

    fn freeRow(self: *Table, row: *std.ArrayList(TableCell)) void {
        if (self.string_intern == null) {
            for (row.items) |cell| {
                self.allocator.free(cell.text);
            }
        }
        row.deinit(self.allocator);
    }

    /// Set the selected row
    pub fn setSelectedRow(self: *Table, row: ?usize) void {
        const count = self.dataRowCount();
        if (row != null and row.? >= count) {
            return;
        }

        const old_selected = self.selected_row;
        if (self.isEditing() and (self.editing_row.? != row)) {
            self.cancelEdit();
        }
        self.selected_row = row;

        // Ensure selected row is visible
        if (row != null) {
            if (self.columns.items.len > 0 and self.selected_column >= self.columns.items.len) {
                self.selected_column = self.columns.items.len - 1;
            }
            self.ensureRowVisible(row.?);
        }

        // Call the row selected callback
        if (old_selected != self.selected_row and self.on_row_select != null and self.selected_row != null) {
            self.on_row_select.?(self.selected_row.?);
        }
    }

    /// Ensure a row is visible by adjusting first_visible_row
    fn ensureRowVisible(self: *Table, row: usize) void {
        self.ensureView();
        const view_idx = self.viewIndexForDataRow(row) orelse return;
        const visible_rows = self.getVisibleRowCount();

        if (visible_rows == 0) return;

        if (view_idx < self.first_visible_row) {
            self.scrollTo(@floatFromInt(view_idx));
        } else if (view_idx >= self.first_visible_row + visible_rows) {
            self.scrollTo(@floatFromInt(view_idx - visible_rows + 1));
        }
    }

    /// Get the number of rows that can be displayed
    fn getVisibleRowCount(self: *Table) usize {
        var height = @as(usize, @intCast(self.widget.rect.height));

        if (self.border != .none and height > 2) {
            height -= 2;
        }

        if (self.show_headers) {
            height = if (height > 0) height - 1 else 0;
            if (self.show_grid) {
                height = if (height > 0) height - 1 else 0;
            }
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

    /// Apply theme defaults for table colors.
    pub fn setTheme(self: *Table, theme_value: theme.Theme) void {
        const colors = theme.tableColors(theme_value);
        self.fg = colors.fg;
        self.bg = colors.bg;
        self.header_fg = colors.header_fg;
        self.header_bg = colors.header_bg;
        self.selected_fg = colors.selected_fg;
        self.selected_bg = colors.selected_bg;
        self.focused_fg = colors.focused_fg;
        self.focused_bg = colors.focused_bg;
        self.grid_fg = colors.grid_fg;
    }

    /// Set the on-row-selected callback
    pub fn setOnRowSelect(self: *Table, callback: *const fn (usize) void) void {
        self.on_row_select = callback;
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

    /// Attach a shared animator to enable smooth scrolling.
    pub fn attachAnimator(self: *Table, animator: *animation.Animator) void {
        self.animator = animator;
        self.scroll_driver.snap(@floatFromInt(self.first_visible_row));
    }

    /// Switch to virtual row mode using an external provider.
    pub fn useRowProvider(self: *Table, provider: RowProvider) void {
        self.clearRows();
        self.row_provider = provider;
        self.scroll_driver.snap(@floatFromInt(self.first_visible_row));
        self.cancelEdit();
        self.view_dirty = true;
    }

    /// Return to owned row storage.
    pub fn clearRowProvider(self: *Table) void {
        self.row_provider = null;
        self.scroll_driver.snap(@floatFromInt(self.first_visible_row));
        self.cancelEdit();
        self.view_dirty = true;
    }

    fn rowCount(self: *Table) usize {
        self.ensureView();
        return self.view_rows.items.len;
    }

    fn cellView(self: *Table, row: usize, col: usize) TableCellView {
        if (self.row_provider) |provider| {
            return provider.cell_at(row, col, provider.ctx);
        }
        const cell = self.rows.items[row].items[col];
        return TableCellView{
            .text = cell.text,
            .fg = cell.fg,
            .bg = cell.bg,
        };
    }

    fn dataRowCount(self: *Table) usize {
        if (self.row_provider) |provider| {
            return provider.row_count(provider.ctx);
        }
        return self.rows.items.len;
    }

    fn ensureView(self: *Table) void {
        if (!self.view_dirty) return;

        var next_order = self.buildOrder() catch return;
        const next_rows = self.buildViewRows(next_order.items) catch {
            next_order.deinit(self.allocator);
            return;
        };

        self.visible_order.deinit(self.allocator);
        self.clearViewRows();
        self.view_rows.deinit(self.allocator);
        self.visible_order = next_order;
        self.view_rows = next_rows;
        self.view_dirty = false;
    }

    fn buildOrder(self: *Table) !std.ArrayList(usize) {
        const count = self.dataRowCount();
        var next_order = std.ArrayList(usize).empty;
        if (count == 0) return next_order;

        errdefer next_order.deinit(self.allocator);
        try next_order.ensureTotalCapacityPrecise(self.allocator, count);
        var i: usize = 0;
        while (i < count) : (i += 1) {
            next_order.appendAssumeCapacity(i);
        }

        const lessThan = struct {
            fn less(ctx: *Table, lhs: usize, rhs: usize) bool {
                return ctx.rowLessThan(lhs, rhs);
            }
        }.less;

        std.sort.pdq(usize, next_order.items, self, lessThan);
        return next_order;
    }

    fn rowLessThan(self: *Table, lhs: usize, rhs: usize) bool {
        if (self.grouping_column) |group_col| {
            const ord = self.compareCell(lhs, rhs, group_col);
            if (ord != .eq) return ord == .lt;
        }

        if (self.sort_column) |col| {
            const ord = self.compareCell(lhs, rhs, col);
            if (ord != .eq) {
                return if (self.sort_descending) ord == .gt else ord == .lt;
            }
        }

        return lhs < rhs;
    }

    fn compareCell(self: *Table, lhs: usize, rhs: usize, col: usize) std.math.Order {
        if (col >= self.columns.items.len) return .eq;
        const a_text = self.cellView(lhs, col).text;
        const b_text = self.cellView(rhs, col).text;
        return std.mem.order(u8, a_text, b_text);
    }

    fn freeViewRows(self: *Table, rows: []const ViewRow) void {
        for (rows) |row| {
            switch (row) {
                .group => |label| self.allocator.free(label),
                else => {},
            }
        }
    }

    fn buildViewRows(self: *Table, order: []const usize) !std.ArrayList(ViewRow) {
        var next_rows = std.ArrayList(ViewRow).empty;
        if (order.len == 0) return next_rows;

        errdefer {
            self.freeViewRows(next_rows.items);
            next_rows.deinit(self.allocator);
        }

        const max_view_rows = if (self.grouping_column != null) try std.math.mul(usize, order.len, 2) else order.len;
        try next_rows.ensureTotalCapacity(self.allocator, max_view_rows);

        if (self.grouping_column) |group_col| {
            var last_key: []const u8 = "";
            var has_key = false;
            for (order) |row_idx| {
                const key = self.cellView(row_idx, group_col).text;
                const is_new = !has_key or !std.mem.eql(u8, key, last_key);
                if (is_new) {
                    const copy = try self.allocator.dupe(u8, key);
                    next_rows.append(self.allocator, .{ .group = copy }) catch |err| {
                        self.allocator.free(copy);
                        return err;
                    };
                    last_key = copy;
                    has_key = true;
                }
                try next_rows.append(self.allocator, .{ .data = row_idx });
            }
        } else {
            for (order) |row_idx| {
                next_rows.appendAssumeCapacity(.{ .data = row_idx });
            }
        }

        return next_rows;
    }

    fn viewIndexForDataRow(self: *Table, row: usize) ?usize {
        for (self.view_rows.items, 0..) |entry, idx| {
            if (entry == .data and entry.data == row) {
                return idx;
            }
        }
        return null;
    }

    fn dataIndexForView(self: *Table, view_idx: usize) ?usize {
        if (view_idx >= self.view_rows.items.len) return null;
        return switch (self.view_rows.items[view_idx]) {
            .data => |row| row,
            else => null,
        };
    }

    fn indexInVisibleOrder(self: *Table, row: usize) ?usize {
        for (self.visible_order.items, 0..) |value, idx| {
            if (value == row) return idx;
        }
        return null;
    }

    fn hasDrawableBorder(self: *const Table) bool {
        const rect = self.widget.rect;
        return self.border != .none and rect.width > 2 and rect.height > 2;
    }

    fn contentRect(self: *const Table) layout_module.Rect {
        const rect = self.widget.rect;
        if (self.hasDrawableBorder()) {
            return rect.shrink(layout_module.EdgeInsets.all(1));
        }
        return rect;
    }

    fn headerHeight(self: *const Table, content_rect: layout_module.Rect) u16 {
        if (!self.show_headers or content_rect.height == 0) return 0;
        var rows: u16 = 1;
        if (self.show_grid and content_rect.height > rows) {
            rows += 1;
        }
        return rows;
    }

    fn u16Coord(value: u32) ?u16 {
        if (value > std.math.maxInt(u16)) return null;
        return @intCast(value);
    }

    fn clippedSpanWidth(start: u32, desired: u16, right: u32) u16 {
        if (start >= right) return 0;
        const available = @min(@as(u32, desired), right - start);
        return @intCast(@min(available, @as(u32, std.math.maxInt(u16))));
    }

    fn fillTableSpan(
        renderer: *render.Renderer,
        x: u32,
        y: u32,
        width: u16,
        fill_char: u21,
        fg: render.Color,
        bg: render.Color,
        style: render.Style,
    ) void {
        if (width == 0) return;
        const draw_x = u16Coord(x) orelse return;
        const draw_y = u16Coord(y) orelse return;
        renderer.fillRect(draw_x, draw_y, width, 1, fill_char, fg, bg, style);
    }

    fn drawTableChar(
        renderer: *render.Renderer,
        x: u32,
        y: u32,
        char: u21,
        fg: render.Color,
        bg: render.Color,
        style: render.Style,
    ) void {
        const draw_x = u16Coord(x) orelse return;
        const draw_y = u16Coord(y) orelse return;
        renderer.drawChar(draw_x, draw_y, char, fg, bg, style);
    }

    fn columnIndexAtX(self: *Table, x: u16) ?usize {
        const content_rect = self.contentRect();
        if (!content_rect.contains(x, content_rect.y)) return null;

        var cursor: u32 = @as(u32, content_rect.x);
        const x_u32: u32 = @as(u32, x);
        const right: u32 = @as(u32, content_rect.x) + @as(u32, content_rect.width);
        for (self.columns.items, 0..) |column, idx| {
            const end = @min(cursor + @as(u32, column.width), right);
            if (x_u32 >= cursor and x_u32 < end) {
                return idx;
            }
            cursor = end;
            if (cursor >= right) break;
        }
        return null;
    }

    fn tryStartResize(self: *Table, x: u16) bool {
        const content_rect = self.contentRect();
        if (!content_rect.contains(x, content_rect.y)) return false;

        var cursor: u32 = @as(u32, content_rect.x);
        const x_u32: u32 = @as(u32, x);
        const right: u32 = @as(u32, content_rect.x) + @as(u32, content_rect.width);
        for (self.columns.items, 0..) |column, idx| {
            const end = @min(cursor + @as(u32, column.width), right);
            if (column.resizable and x_u32 + 1 >= end and x_u32 <= end and column.width > 0) {
                self.resizing_column = idx;
                self.resize_anchor_x = x;
                self.resize_original_width = column.width;
                return true;
            }
            cursor = end;
            if (cursor >= right) break;
        }
        return false;
    }

    fn clampScroll(self: *Table) void {
        self.ensureView();
        const visible_rows = self.getVisibleRowCount();
        const total_rows = self.view_rows.items.len;
        const max_offset = if (visible_rows == 0 or total_rows <= visible_rows) 0 else total_rows - visible_rows;
        const clamped = std.math.clamp(self.scroll_driver.current, 0, @as(f32, @floatFromInt(max_offset)));
        self.scroll_driver.current = clamped;
        self.first_visible_row = @as(usize, @intFromFloat(std.math.floor(clamped)));
    }

    fn scrollTo(self: *Table, target: f32) void {
        const visible_rows = self.getVisibleRowCount();
        self.ensureView();
        const total_rows = self.view_rows.items.len;
        const max_offset = if (visible_rows == 0 or total_rows <= visible_rows) 0 else total_rows - visible_rows;
        const clamped = std.math.clamp(target, 0, @as(f32, @floatFromInt(max_offset)));
        if (self.animator) |anim| {
            const onChange = struct {
                fn apply(value: f32, ctx: ?*anyopaque) void {
                    const table = @as(*Table, @ptrCast(@alignCast(ctx.?)));
                    table.scroll_driver.current = value;
                    table.first_visible_row = @as(usize, @intFromFloat(std.math.floor(value)));
                }
            }.apply;

            _ = self.scroll_driver.animate(
                anim,
                self.scroll_driver.current,
                clamped,
                self.scroll_duration_ms,
                animation.Easing.easeInOutQuad,
                onChange,
                @ptrCast(self),
            ) catch {
                self.scroll_driver.snap(clamped);
                self.first_visible_row = @as(usize, @intFromFloat(std.math.floor(clamped)));
            };
        } else {
            self.scroll_driver.snap(clamped);
            self.first_visible_row = @as(usize, @intFromFloat(std.math.floor(clamped)));
        }
    }

    fn scrollBy(self: *Table, delta: f32) void {
        self.scrollTo(self.scroll_driver.current + delta * self.momentum_multiplier);
    }

    /// Draw implementation for Table
    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = fromWidgetPtr(widget_ptr);

        if (!self.widget.visible or self.columns.items.len == 0) {
            return;
        }

        const rect = self.widget.rect;
        const styled = self.widget.applyStyle(
            "table",
            .{ .focus = self.widget.focused, .disabled = !self.widget.enabled },
            render.Style{},
            self.fg,
            self.bg,
        );
        const fg = styled.fg;
        const bg = styled.bg;
        const style = styled.style;

        // Fill table background
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', fg, bg, style);

        self.clampScroll();
        const total_rows = self.rowCount();
        if (self.first_visible_row + self.getVisibleRowCount() > total_rows and total_rows > 0) {
            const visible_rows = self.getVisibleRowCount();
            const new_first = if (total_rows > visible_rows) total_rows - visible_rows else 0;
            self.scroll_driver.snap(@floatFromInt(new_first));
            self.first_visible_row = new_first;
        }

        const has_border = self.hasDrawableBorder();
        if (has_border) {
            renderer.drawBox(rect.x, rect.y, rect.width, rect.height, self.border, self.fg, self.bg, render.Style{});
        }

        const content_rect = self.contentRect();
        const content_x = content_rect.x;
        const content_y = content_rect.y;
        const content_width = content_rect.width;
        const content_height = content_rect.height;
        if (content_width == 0 or content_height == 0) return;
        const content_right = @as(u32, content_x) + @as(u32, content_width);
        const content_bottom = @as(u32, content_y) + @as(u32, content_height);

        var y: u32 = content_y;
        var x: u32 = content_x;

        // Draw headers if enabled
        if (self.show_headers) {
            x = content_x;

            for (self.columns.items, 0..) |column, col_idx| {
                if (x >= content_right) break;
                const column_width = clippedSpanWidth(x, column.width, content_right);
                if (column_width == 0) break;

                // Draw header background
                fillTableSpan(renderer, x, y, column_width, ' ', self.header_fg, self.header_bg, render.Style{});

                const indicator: ?u21 = if (self.sort_column != null and self.sort_column.? == col_idx)
                    (if (self.sort_descending) '▼' else '▲')
                else
                    null;

                // Draw header text
                var cursor = x + 1;
                for (column.header, 0..) |char, i| {
                    if (i >= @as(usize, @intCast(column_width - 1))) {
                        break;
                    }

                    drawTableChar(renderer, cursor, y, char, self.header_fg, self.header_bg, render.Style{});
                    cursor += 1;
                    if (cursor >= x + column_width) break;
                }

                if (indicator != null and cursor < x + column_width) {
                    drawTableChar(renderer, cursor, y, indicator.?, self.header_fg, self.header_bg, render.Style{ .bold = true });
                }

                // Draw grid if enabled
                if (self.show_grid and x > content_x) {
                    drawTableChar(renderer, x, y, '│', self.grid_fg, self.header_bg, render.Style{});
                }

                x += column.width;
                if (x > std.math.maxInt(u16)) break;
            }

            y += 1;

            // Draw horizontal grid line under headers if enabled
            if (self.show_grid and y < content_bottom) {
                x = content_x;
                for (self.columns.items) |column| {
                    if (x >= content_right) break;
                    const column_width = clippedSpanWidth(x, column.width, content_right);
                    if (column_width == 0) break;

                    for (0..@as(usize, @intCast(column_width))) |i| {
                        const char: u21 = if (x > content_x and i == 0) '┼' else '─';
                        drawTableChar(renderer, x + @as(u32, @intCast(i)), y, char, self.grid_fg, bg, render.Style{});
                    }

                    x += column.width;
                    if (x > std.math.maxInt(u16)) break;
                }
                while (x < content_right) : (x += 1) {
                    if (x > std.math.maxInt(u16)) break;
                    drawTableChar(renderer, x, y, '─', self.grid_fg, bg, render.Style{});
                }
                y += 1;
            }
        }

        // Draw visible rows
        const visible_rows = self.getVisibleRowCount();
        const last_visible_row = @min(self.first_visible_row + visible_rows, total_rows);

        for (self.first_visible_row..last_visible_row) |view_idx| {
            if (view_idx >= self.view_rows.items.len) break;
            const view_row = self.view_rows.items[view_idx];
            if (view_row == .group) {
                x = content_x;
                fillTableSpan(renderer, x, y, content_width, ' ', self.header_fg, self.header_bg, render.Style{ .bold = true });
                const group_text = view_row.group;
                if (group_text.len > 0 and content_width > 2) {
                    if (u16Coord(x + 1)) |draw_x| {
                        if (u16Coord(y)) |draw_y| {
                            renderer.drawStr(draw_x, draw_y, group_text[0..@min(group_text.len, @as(usize, @intCast(content_width - 2)))], self.header_fg, self.header_bg, render.Style{ .bold = true });
                        }
                    }
                }
                y += 1;
                continue;
            }

            const row_idx = view_row.data;
            const is_selected = self.selected_row != null and row_idx == self.selected_row.?;

            x = content_x;

            // Choose row colors based on selection and focus
            const row_fg = if (is_selected)
                (if (self.widget.focused) self.focused_fg else self.selected_fg)
            else
                fg;

            const row_bg = if (is_selected)
                (if (self.widget.focused) self.focused_bg else self.selected_bg)
            else
                bg;

            // Draw each cell in the row
            for (self.columns.items, 0..) |column, col_idx| {
                if (x >= content_right) break;
                const column_width = clippedSpanWidth(x, column.width, content_right);
                if (column_width == 0) break;

                var cell_view = TableCellView{
                    .text = "",
                    .fg = null,
                    .bg = null,
                };

                cell_view = self.cellView(row_idx, col_idx);

                if (cell_view.text.len > 0 or cell_view.fg != null or cell_view.bg != null) {
                    // Choose cell colors, using row colors as default
                    const cell_fg = cell_view.fg orelse row_fg;
                    const cell_bg = cell_view.bg orelse row_bg;
                    const editing = self.isEditing() and self.editing_row.? == row_idx and self.editing_col.? == col_idx;
                    const text_slice = if (editing) self.edit_buffer.items else cell_view.text;
                    const cell_style = if (editing) render.Style{ .underline = true } else render.Style{};

                    // Draw cell background
                    fillTableSpan(renderer, x, y, column_width, ' ', cell_fg, cell_bg, render.Style{});

                    // Draw cell text
                    for (text_slice, 0..) |char, i| {
                        if (i >= @as(usize, @intCast(column_width - 1))) {
                            break;
                        }

                        drawTableChar(renderer, x + 1 + @as(u32, @intCast(i)), y, char, cell_fg, cell_bg, cell_style);
                    }

                    // Draw grid if enabled
                    if (self.show_grid and x > content_x) {
                        drawTableChar(renderer, x, y, '│', self.grid_fg, cell_bg, render.Style{});
                    }
                } else {
                    // Draw empty cell
                    fillTableSpan(renderer, x, y, column_width, ' ', row_fg, row_bg, render.Style{});

                    // Draw grid if enabled
                    if (self.show_grid and x > content_x) {
                        drawTableChar(renderer, x, y, '│', self.grid_fg, row_bg, render.Style{});
                    }
                }

                x += column.width;
                if (x > std.math.maxInt(u16)) break;
            }

            y += 1;
            if (y > std.math.maxInt(u16)) break;
        }
    }

    /// Event handling implementation for Table
    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = fromWidgetPtr(widget_ptr);
        self.ensureView();
        const total_rows = self.dataRowCount();

        if (!self.widget.visible or !self.widget.enabled) {
            return false;
        }

        // Handle mouse events
        if (event == .mouse) {
            const mouse_event = event.mouse;
            const rect = self.widget.rect;
            const content_rect = self.contentRect();
            const header_rows = self.headerHeight(content_rect);

            // Header interactions: sorting and resize handles.
            if (self.show_headers and content_rect.height > 0 and mouse_event.y == content_rect.y and content_rect.contains(mouse_event.x, mouse_event.y)) {
                if (mouse_event.action == .press) {
                    if (self.tryStartResize(mouse_event.x)) return true;
                    if (self.columnIndexAtX(mouse_event.x)) |col| {
                        self.selected_column = col;
                        self.toggleSort(col);
                        return true;
                    }
                } else if (mouse_event.action == .move and self.resizing_column != null) {
                    const delta = @as(i16, @intCast(mouse_event.x)) - @as(i16, @intCast(self.resize_anchor_x));
                    self.resizeColumn(self.resizing_column.?, delta);
                    return true;
                } else if (mouse_event.action == .release and self.resizing_column != null) {
                    self.resizing_column = null;
                    return true;
                }
            } else if (mouse_event.action == .move and self.resizing_column != null) {
                const delta = @as(i16, @intCast(mouse_event.x)) - @as(i16, @intCast(self.resize_anchor_x));
                self.resizeColumn(self.resizing_column.?, delta);
                return true;
            } else if (mouse_event.action == .release and self.resizing_column != null) {
                self.resizing_column = null;
                return true;
            }

            // Check if mouse is within table row bounds
            const row_start_y = @as(u32, content_rect.y) + @as(u32, header_rows);
            const mouse_y = @as(u32, mouse_event.y);
            if (content_rect.contains(mouse_event.x, mouse_event.y) and mouse_y >= row_start_y and total_rows > 0) {
                // Convert y position to row index
                const row_idx = self.first_visible_row + @as(usize, @intCast(mouse_y - row_start_y));

                if (row_idx < self.view_rows.items.len) {
                    if (self.dataIndexForView(row_idx)) |data_row| {
                        if (self.columnIndexAtX(mouse_event.x)) |col_idx| {
                            self.selected_column = col_idx;
                        }
                        // Select row on click
                        if (mouse_event.action == .press and mouse_event.button == 1) {
                            self.setSelectedRow(data_row);
                            return true;
                        }
                    }
                }

                return true; // Capture all mouse events within bounds
            }

            // Mouse wheel scrolling
            if (mouse_event.action == .press and mouse_event.button == 4 and
                rect.contains(mouse_event.x, mouse_event.y))
            {
                // kept for backward compatibility with terminals sending button codes
                self.scrollBy(-1);
                return true;
            } else if (mouse_event.action == .press and mouse_event.button == 5 and
                rect.contains(mouse_event.x, mouse_event.y))
            {
                self.scrollBy(1);
                return true;
            } else if ((mouse_event.action == .scroll_up or mouse_event.action == .scroll_down) and rect.contains(mouse_event.x, mouse_event.y)) {
                const scroll_step: i16 = if (mouse_event.scroll_delta != 0)
                    mouse_event.scroll_delta
                else if (mouse_event.action == .scroll_up)
                    -1
                else
                    1;
                self.scrollBy(@as(f32, @floatFromInt(scroll_step)));
                return true;
            }
        }

        // Handle key events
        if (event == .key and self.widget.focused and total_rows > 0) {
            const key_event = event.key;
            if (self.isEditing()) {
                if (try self.handleEditKey(key_event)) return true;
                return true;
            }
            const profiles = [_]input.KeybindingProfile{
                input.KeybindingProfile.commonEditing(),
                input.KeybindingProfile.emacs(),
                input.KeybindingProfile.vi(),
            };

            if (input.editorActionForEvent(key_event, &profiles)) |action| {
                switch (action) {
                    .cursor_down => {
                        if (self.selected_row == null) {
                            var probe = self.first_visible_row;
                            var chosen: ?usize = null;
                            while (probe < self.view_rows.items.len) : (probe += 1) {
                                if (self.dataIndexForView(probe)) |row_idx| {
                                    chosen = row_idx;
                                    break;
                                }
                            }
                            if (chosen == null and self.visible_order.items.len > 0) {
                                chosen = self.visible_order.items[0];
                            }
                            if (chosen) |row_idx| self.setSelectedRow(row_idx);
                        } else {
                            const next_view = (self.viewIndexForDataRow(self.selected_row.?) orelse 0) + 1;
                            var probe = next_view;
                            while (probe < self.view_rows.items.len) : (probe += 1) {
                                if (self.dataIndexForView(probe)) |row_idx| {
                                    self.setSelectedRow(row_idx);
                                    break;
                                }
                            }
                        }
                        self.resetTypeahead();
                        return true;
                    },
                    .cursor_up => {
                        if (self.selected_row == null) {
                            var probe = self.first_visible_row;
                            var chosen: ?usize = null;
                            while (probe < self.view_rows.items.len) : (probe += 1) {
                                if (self.dataIndexForView(probe)) |row_idx| {
                                    chosen = row_idx;
                                    break;
                                }
                            }
                            if (chosen == null and self.visible_order.items.len > 0) {
                                chosen = self.visible_order.items[0];
                            }
                            if (chosen) |row_idx| self.setSelectedRow(row_idx);
                        } else {
                            const current_view = self.viewIndexForDataRow(self.selected_row.?) orelse 0;
                            var probe: i32 = @intCast(current_view);
                            while (probe >= 0) : (probe -= 1) {
                                const idx: usize = @intCast(probe);
                                if (self.dataIndexForView(idx)) |row_idx| {
                                    self.setSelectedRow(row_idx);
                                    break;
                                }
                            }
                        }
                        self.resetTypeahead();
                        return true;
                    },
                    .page_down => {
                        const visible_rows = self.getVisibleRowCount();

                        if (self.selected_row == null) {
                            var target_view = if (self.first_visible_row + visible_rows < self.view_rows.items.len)
                                self.first_visible_row + visible_rows
                            else
                                self.view_rows.items.len - 1;
                            while (target_view < self.view_rows.items.len) : (target_view += 1) {
                                if (self.dataIndexForView(target_view)) |row_idx| {
                                    self.setSelectedRow(row_idx);
                                    break;
                                }
                            }
                        } else {
                            var new_view = (self.viewIndexForDataRow(self.selected_row.?) orelse 0) + visible_rows;
                            if (new_view >= self.view_rows.items.len) new_view = self.view_rows.items.len - 1;
                            if (self.dataIndexForView(new_view)) |row_idx| self.setSelectedRow(row_idx);
                        }
                        self.resetTypeahead();
                        return true;
                    },
                    .page_up => {
                        if (self.selected_row == null) {
                            self.setSelectedRow(0);
                        } else {
                            const visible_rows = self.getVisibleRowCount();
                            var new_view: i32 = @intCast(self.viewIndexForDataRow(self.selected_row.?) orelse 0);
                            new_view -= @intCast(visible_rows);
                            if (new_view < 0) new_view = 0;
                            var probe = @as(usize, @intCast(new_view));
                            while (true) {
                                if (self.dataIndexForView(probe)) |row_idx| {
                                    self.setSelectedRow(row_idx);
                                    break;
                                }
                                if (probe == 0) break;
                                probe -= 1;
                            }
                        }
                        self.resetTypeahead();
                        return true;
                    },
                    .line_start => {
                        if (self.visible_order.items.len > 0) self.setSelectedRow(self.visible_order.items[0]);
                        self.resetTypeahead();
                        return true;
                    },
                    .line_end => {
                        if (self.view_rows.items.len > 0) {
                            var probe = self.view_rows.items.len - 1;
                            while (true) : (probe -= 1) {
                                if (self.dataIndexForView(probe)) |row_idx| {
                                    self.setSelectedRow(row_idx);
                                    break;
                                }
                                if (probe == 0) break;
                            }
                        }
                        self.resetTypeahead();
                        return true;
                    },
                    else => {},
                }
            }

            if (key_event.key == input.KeyCode.ESCAPE) {
                self.resetTypeahead();
                return false;
            } else if (key_event.key == input.KeyCode.ENTER) {
                try self.beginEdit();
                return true;
            } else if (key_event.key == input.KeyCode.LEFT) {
                if (self.selected_column > 0) self.selected_column -= 1;
                return true;
            } else if (key_event.key == input.KeyCode.RIGHT) {
                if (self.selected_column + 1 < self.columns.items.len) self.selected_column += 1;
                return true;
            } else if (key_event.isPrintable() and !key_event.modifiers.ctrl and !key_event.modifiers.alt) {
                if (self.handleTypeaheadKey(@as(u8, @intCast(key_event.key)))) {
                    return true;
                }
            }
        }

        return false;
    }

    fn handleTypeaheadKey(self: *Table, byte: u8) bool {
        self.ensureView();
        const total_rows = self.visible_order.items.len;
        if (total_rows == 0) {
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

        const start = if (self.selected_row) |row| self.indexInVisibleOrder(row) orelse 0 else 0;
        var i: usize = 0;
        const scan_limit = @min(total_rows, self.typeahead_scan_limit);
        while (i < scan_limit) : (i += 1) {
            const idx = (start + i) % total_rows;
            const row_idx = self.visible_order.items[idx];
            if (self.rowStartsWith(row_idx, needle)) {
                self.setSelectedRow(row_idx);
                return true;
            }
        }

        return false;
    }

    fn rowStartsWith(self: *Table, row_idx: usize, needle: []const u8) bool {
        if (needle.len == 0) return false;

        for (self.columns.items, 0..) |_, col_idx| {
            const cell = self.cellView(row_idx, col_idx);
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
        const self = fromWidgetPtr(widget_ptr);
        self.widget.rect = rect;

        self.clampScroll();
        // Ensure selected row is still visible after layout
        if (self.selected_row != null) {
            self.ensureRowVisible(self.selected_row.?);
        }
    }

    /// Get preferred size implementation for Table
    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = fromWidgetPtr(widget_ptr);

        // Calculate width based on columns
        var width: u16 = 0;
        for (self.columns.items) |column| {
            const expanded: u32 = @as(u32, width) + column.width;
            width = @intCast(@min(expanded, @as(u32, std.math.maxInt(u16))));
        }

        // Preferred height depends on number of rows plus header
        const header_height: u16 = if (self.show_headers) 1 else 0;
        const sample_rows = @min(@as(usize, 20), @min(self.virtual_sample_limit, self.rowCount()));
        const height = header_height + @as(u16, @intCast(sample_rows));

        return layout_module.Size.init(width, height);
    }

    /// Can focus implementation for Table
    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = fromWidgetPtr(widget_ptr);
        return self.widget.enabled and self.rowCount() > 0;
    }

    fn ownText(self: *Table, text: []const u8) ![]const u8 {
        if (self.string_intern) |*intern| {
            return intern.intern(text);
        }
        return self.allocator.dupe(u8, text);
    }
};

test "table typeahead search finds matching rows" {
    const alloc = std.testing.allocator;
    var table = try Table.init(alloc);
    defer table.deinit();

    try table.addColumn("Name", 12, true);
    try table.addColumn("Details", 16, true);

    const Provider = struct {
        rows: []const [2][]const u8,

        fn rowCount(ctx: ?*anyopaque) usize {
            const self = @as(*const @This(), @ptrCast(@alignCast(ctx.?)));
            return self.rows.len;
        }

        fn cellAt(row: usize, col: usize, ctx: ?*anyopaque) TableCellView {
            const self = @as(*const @This(), @ptrCast(@alignCast(ctx.?)));
            return .{ .text = self.rows[row][col] };
        }
    };

    var provider_ctx = Provider{
        .rows = &.{
            .{ "Alpha", "First" },
            .{ "Garden", "Plants" },
            .{ "Gamma", "Third" },
            .{ "Zeta", "Last" },
        },
    };

    table.useRowProvider(.{
        .ctx = &provider_ctx,
        .row_count = Provider.rowCount,
        .cell_at = Provider.cellAt,
    });

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

    _ = try table.widget.handleEvent(.{ .key = .{ .key = 'g', .modifiers = .{} } });
    try std.testing.expectEqual(@as(usize, 1), table.selected_row.?); // Garden

    _ = try table.widget.handleEvent(.{ .key = .{ .key = 'a', .modifiers = .{} } });
    try std.testing.expectEqual(@as(usize, 1), table.selected_row.?); // "ga" still Garden

    TestClock.now = 5_000; // Exceeds timeout, clears buffer.
    _ = try table.widget.handleEvent(.{ .key = .{ .key = 'z', .modifiers = .{} } });
    try std.testing.expectEqual(@as(usize, 3), table.selected_row.?); // Zeta
}

test "table border preserves header and row content" {
    const alloc = std.testing.allocator;
    var table = try Table.init(alloc);
    defer table.deinit();

    try table.addColumn("A", 5, true);
    try table.addColumn("B", 5, true);
    try table.addRow(&.{ "x", "y" });
    table.border = .single;
    try table.widget.layout(layout_module.Rect.init(0, 0, 14, 6));

    var renderer = try render.Renderer.init(alloc, 14, 6);
    defer renderer.deinit();
    try table.widget.draw(&renderer);

    try std.testing.expectEqual(@as(u21, '┌'), renderer.back.getCell(0, 0).codepoint());
    try std.testing.expectEqual(@as(u21, 'A'), renderer.back.getCell(2, 1).codepoint());
    try std.testing.expectEqual(@as(u21, '─'), renderer.back.getCell(2, 2).codepoint());
    try std.testing.expectEqual(@as(u21, 'x'), renderer.back.getCell(2, 3).codepoint());
}

test "table draws clipped oversized columns" {
    const alloc = std.testing.allocator;
    var table = try Table.init(alloc);
    defer table.deinit();

    try table.addColumn("Name", 20, true);
    try table.addRow(&.{"abcdef"});
    try table.widget.layout(layout_module.Rect.init(0, 0, 6, 3));

    var renderer = try render.Renderer.init(alloc, 6, 3);
    defer renderer.deinit();
    try table.widget.draw(&renderer);

    try std.testing.expectEqual(@as(u21, 'N'), renderer.back.getCell(1, 0).codepoint());
    try std.testing.expectEqual(@as(u21, 'a'), renderer.back.getCell(1, 2).codepoint());
    try std.testing.expectEqual(@as(u21, 'd'), renderer.back.getCell(4, 2).codepoint());
}

test "table clips edge coordinates before u16 overflow" {
    const alloc = std.testing.allocator;
    var table = try Table.init(alloc);
    defer table.deinit();

    try table.addColumn("A", 4, true);
    try table.addColumn("B", 4, true);
    try table.addRow(&.{ "x", "y" });
    try table.widget.layout(layout_module.Rect.init(std.math.maxInt(u16) - 1, 0, 8, 3));

    var renderer = try render.Renderer.init(alloc, 4, 3);
    defer renderer.deinit();
    try table.widget.draw(&renderer);
}

test "bordered table mouse header uses rendered content row" {
    const alloc = std.testing.allocator;
    var table = try Table.init(alloc);
    defer table.deinit();

    try table.addColumn("A", 5, true);
    try table.addColumn("B", 5, true);
    try table.addRow(&.{ "x", "y" });
    table.border = .single;
    try table.widget.layout(layout_module.Rect.init(0, 0, 14, 6));

    const top_border = input.Event{ .mouse = input.MouseEvent.init(.press, 2, 0, 1, 0) };
    try std.testing.expect(!try table.widget.handleEvent(top_border));
    try std.testing.expectEqual(@as(?usize, null), table.sort_column);
    try std.testing.expectEqual(@as(?usize, null), table.resizing_column);

    const header = input.Event{ .mouse = input.MouseEvent.init(.press, 2, 1, 1, 0) };
    try std.testing.expect(try table.widget.handleEvent(header));
    try std.testing.expectEqual(@as(?usize, 0), table.sort_column);

    const resize_handle = input.Event{ .mouse = input.MouseEvent.init(.press, 6, 1, 1, 0) };
    try std.testing.expect(try table.widget.handleEvent(resize_handle));
    try std.testing.expectEqual(@as(?usize, 0), table.resizing_column);
}

test "bordered table mouse rows skip header separator" {
    const alloc = std.testing.allocator;
    var table = try Table.init(alloc);
    defer table.deinit();

    try table.addColumn("A", 5, true);
    try table.addColumn("B", 5, true);
    try table.addRow(&.{ "x", "y" });
    try table.addRow(&.{ "z", "w" });
    table.border = .single;
    try table.widget.layout(layout_module.Rect.init(0, 0, 14, 6));

    const separator = input.Event{ .mouse = input.MouseEvent.init(.press, 2, 2, 1, 0) };
    try std.testing.expect(!try table.widget.handleEvent(separator));
    try std.testing.expectEqual(@as(?usize, null), table.selected_row);

    const first_row = input.Event{ .mouse = input.MouseEvent.init(.press, 2, 3, 1, 0) };
    try std.testing.expect(try table.widget.handleEvent(first_row));
    try std.testing.expectEqual(@as(?usize, 0), table.selected_row);

    const second_row = input.Event{ .mouse = input.MouseEvent.init(.press, 2, 4, 1, 0) };
    try std.testing.expect(try table.widget.handleEvent(second_row));
    try std.testing.expectEqual(@as(?usize, 1), table.selected_row);
}

test "table preferred size clamps large widths" {
    const alloc = std.testing.allocator;
    var table = try Table.init(alloc);
    defer table.deinit();

    try table.addColumn("A", std.math.maxInt(u16), true);
    try table.addColumn("B", std.math.maxInt(u16), true);

    const size = try Table.getPreferredSizeFn(@ptrCast(@alignCast(&table.widget)));
    try std.testing.expectEqual(std.math.maxInt(u16), size.width);
}

test "table ignores input when empty" {
    const alloc = std.testing.allocator;
    var table = try Table.init(alloc);
    defer table.deinit();

    try table.widget.layout(layout_module.Rect.init(0, 0, 10, 5));
    const handled = try table.widget.handleEvent(.{ .key = .{ .key = input.KeyCode.DOWN, .modifiers = .{} } });
    try std.testing.expectEqual(false, handled);
}

test "table sorts and groups rows" {
    const alloc = std.testing.allocator;
    var table = try Table.init(alloc);
    defer table.deinit();

    try table.addColumn("Group", 8, true);
    try table.addColumn("Value", 8, true);

    try table.addRow(&.{ "B", "2" });
    try table.addRow(&.{ "A", "3" });
    try table.addRow(&.{ "A", "1" });

    table.groupBy(0);
    table.toggleSort(1);
    try table.widget.layout(layout_module.Rect.init(0, 0, 16, 6));
    table.ensureView();

    var group_count: usize = 0;
    for (table.view_rows.items) |row| {
        if (row == .group) group_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), group_count);

    // First data row should be smallest numeric value after sort inside first group.
    const first_data = table.dataIndexForView(1).?;
    const first_cell = table.cellView(first_data, 1).text;
    try std.testing.expectEqualStrings("1", first_cell);
}

test "table view cache preserves old rows on rebuild allocation failure" {
    const alloc = std.testing.allocator;
    var table = try Table.init(alloc);
    defer table.deinit();

    try table.addColumn("Group", 8, true);
    try table.addColumn("Value", 8, true);

    try table.addRow(&.{ "B", "2" });
    try table.addRow(&.{ "A", "3" });
    try table.addRow(&.{ "A", "1" });

    table.ensureView();
    try std.testing.expect(!table.view_dirty);
    try std.testing.expectEqual(@as(usize, 3), table.visible_order.items.len);
    try std.testing.expectEqual(@as(usize, 3), table.view_rows.items.len);
    for (table.visible_order.items, 0..) |row_idx, expected| {
        try std.testing.expectEqual(expected, row_idx);
    }
    for (table.view_rows.items) |row| {
        try std.testing.expect(row == .data);
    }

    table.groupBy(0);
    table.toggleSort(1);

    const original_allocator = table.allocator;
    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 1 });
    table.allocator = failing.allocator();
    table.ensureView();
    table.allocator = original_allocator;

    try std.testing.expect(table.view_dirty);
    try std.testing.expectEqual(@as(usize, 3), table.visible_order.items.len);
    try std.testing.expectEqual(@as(usize, 3), table.view_rows.items.len);
    for (table.visible_order.items, 0..) |row_idx, expected| {
        try std.testing.expectEqual(expected, row_idx);
    }
    for (table.view_rows.items) |row| {
        try std.testing.expect(row == .data);
    }

    table.ensureView();
    try std.testing.expect(!table.view_dirty);
    var group_count: usize = 0;
    for (table.view_rows.items) |row| {
        if (row == .group) group_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), group_count);
}

test "table inline edit updates cell" {
    const alloc = std.testing.allocator;
    var table = try Table.init(alloc);
    defer table.deinit();

    try table.addColumn("Name", 8, true);
    try table.addColumn("Note", 8, true);
    try table.addRow(&.{ "cpu", "idle" });

    table.widget.focused = true;
    table.setSelectedRow(0);
    table.selected_column = 1;
    try table.beginEdit();

    _ = try table.widget.handleEvent(.{ .key = .{ .key = ' ', .modifiers = .{} } });
    _ = try table.widget.handleEvent(.{ .key = .{ .key = 'x', .modifiers = .{} } });
    _ = try table.widget.handleEvent(.{ .key = .{ .key = input.KeyCode.ENTER, .modifiers = .{} } });

    const updated = table.cellView(0, 1).text;
    try std.testing.expectEqualStrings("idle x", updated);
}

test "table begin edit propagates allocation failure" {
    const alloc = std.testing.allocator;
    var table = try Table.init(alloc);
    defer table.deinit();

    try table.addColumn("Name", 8, true);
    try table.addRow(&.{"cpu"});
    table.widget.focused = true;
    table.setSelectedRow(0);

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = table.allocator;
    table.allocator = failing.allocator();
    defer table.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, table.widget.handleEvent(.{ .key = .{ .key = input.KeyCode.ENTER, .modifiers = .{} } }));
    try std.testing.expect(!table.isEditing());
    try std.testing.expectEqual(@as(usize, 0), table.edit_buffer.items.len);
}

test "table setCell preserves existing text on allocation failure" {
    const alloc = std.testing.allocator;
    var table = try Table.init(alloc);
    defer table.deinit();

    try table.addColumn("Name", 8, true);
    try table.addRow(&.{"cpu"});

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = table.allocator;
    table.allocator = failing.allocator();
    defer table.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, table.setCell(0, 0, "memory", null, null));
    try std.testing.expectEqualStrings("cpu", table.cellView(0, 0).text);
}

test "table begin edit preserves active edit on allocation failure" {
    const alloc = std.testing.allocator;
    var table = try Table.init(alloc);
    defer table.deinit();

    try table.addColumn("Name", 8, true);
    try table.addColumn("Status", 8, true);
    try table.addRow(&.{ "cpu", "ready and waiting" });
    table.widget.focused = true;
    table.setSelectedRow(0);
    table.selected_column = 0;
    try table.beginEdit();
    try table.edit_buffer.appendSlice(table.allocator, "-draft");
    try std.testing.expect(table.isEditing());
    try std.testing.expectEqual(@as(usize, 0), table.editing_row.?);
    try std.testing.expectEqual(@as(usize, 0), table.editing_col.?);
    try std.testing.expectEqualStrings("cpu-draft", table.edit_buffer.items);

    table.selected_column = 1;
    table.edit_buffer.shrinkAndFree(table.allocator, table.edit_buffer.items.len);

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = table.allocator;
    table.allocator = failing.allocator();
    defer table.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, table.beginEdit());
    try std.testing.expect(table.isEditing());
    try std.testing.expectEqual(@as(usize, 0), table.editing_row.?);
    try std.testing.expectEqual(@as(usize, 0), table.editing_col.?);
    try std.testing.expectEqualStrings("cpu-draft", table.edit_buffer.items);
    try std.testing.expectEqualStrings("ready and waiting", table.cellView(0, 1).text);
}

test "table edit buffer append propagates allocation failure" {
    const alloc = std.testing.allocator;
    var table = try Table.init(alloc);
    defer table.deinit();

    try table.addColumn("Name", 8, true);
    try table.addRow(&.{"cpu"});
    table.widget.focused = true;
    table.setSelectedRow(0);
    try table.beginEdit();
    try std.testing.expectEqualStrings("cpu", table.edit_buffer.items);
    table.edit_buffer.shrinkAndFree(table.allocator, table.edit_buffer.items.len);

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = table.allocator;
    table.allocator = failing.allocator();
    defer table.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, table.widget.handleEvent(.{ .key = .{ .key = 'x', .modifiers = .{} } }));
    try std.testing.expect(table.isEditing());
    try std.testing.expectEqualStrings("cpu", table.edit_buffer.items);
    try std.testing.expectEqualStrings("cpu", table.cellView(0, 0).text);
}

test "table string interning migration is transactional on allocation failure" {
    const alloc = std.testing.allocator;
    var table = try Table.init(alloc);
    defer table.deinit();

    try table.addColumn("Name", 8, true);
    try table.addColumn("Status", 8, true);
    try table.addRow(&.{ "api", "ready" });
    try table.addRow(&.{ "web", "ready" });

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    table.allocator = failing.allocator();

    try std.testing.expectError(error.OutOfMemory, table.enableStringInterning());
    try std.testing.expect(table.stringInternStats() == null);
    try std.testing.expectEqualStrings("Name", table.columns.items[0].header);
    try std.testing.expectEqualStrings("api", table.rows.items[0].items[0].text);
    try std.testing.expectEqualStrings("ready", table.rows.items[1].items[1].text);
}

test "table resizes columns from header drag handles" {
    const alloc = std.testing.allocator;
    var table = try Table.init(alloc);
    defer table.deinit();

    try table.addColumn("A", 5, true);
    try table.addColumn("B", 6, true);

    try table.widget.layout(layout_module.Rect.init(0, 0, 20, 4));

    _ = try table.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.press, 5, 0, 1, 0) });
    try std.testing.expectEqual(@as(?usize, 0), table.resizing_column);

    _ = try table.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.move, 7, 0, 1, 0) });
    try std.testing.expectEqual(@as(u16, 7), table.columns.items[0].width);

    _ = try table.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.move, 1, 0, 1, 0) });
    try std.testing.expectEqual(@as(u16, 3), table.columns.items[0].width);

    _ = try table.widget.handleEvent(.{ .mouse = input.MouseEvent.init(.release, 1, 0, 1, 0) });
    try std.testing.expectEqual(@as(?usize, null), table.resizing_column);
}

test "table row provider sampling caps preferred height" {
    const alloc = std.testing.allocator;
    var table = try Table.init(alloc);
    defer table.deinit();

    try table.addColumn("Name", 8, true);
    try table.addColumn("Value", 8, true);

    const Provider = struct {
        fn rowCount(ctx: ?*anyopaque) usize {
            _ = ctx;
            return 50;
        }

        fn cellAt(row: usize, col: usize, ctx: ?*anyopaque) TableCellView {
            _ = row;
            _ = col;
            _ = ctx;
            return .{ .text = "x" };
        }
    };

    table.virtual_sample_limit = 3;
    table.useRowProvider(.{
        .ctx = null,
        .row_count = Provider.rowCount,
        .cell_at = Provider.cellAt,
    });

    const size = try Table.getPreferredSizeFn(@ptrCast(@alignCast(&table.widget)));
    try std.testing.expectEqual(@as(u16, 4), size.height);
}

test "table selection clamps after row removal" {
    const alloc = std.testing.allocator;
    var table = try Table.init(alloc);
    defer table.deinit();

    try table.addColumn("A", 4, true);
    try table.addColumn("B", 4, true);

    try table.addRow(&.{ "one", "1" });
    try table.addRow(&.{ "two", "2" });
    try table.addRow(&.{ "three", "3" });

    table.setSelectedRow(2);
    table.removeRow(2);

    try std.testing.expectEqual(@as(usize, 2), table.rows.items.len);
    try std.testing.expectEqual(@as(usize, 1), table.selected_row.?);
}

test "table remove before selection preserves selected row" {
    const alloc = std.testing.allocator;
    var table = try Table.init(alloc);
    defer table.deinit();

    try table.addColumn("A", 8, true);
    try table.addColumn("B", 4, true);

    try table.addRow(&.{ "one", "1" });
    try table.addRow(&.{ "two", "2" });
    try table.addRow(&.{ "three", "3" });
    try table.addRow(&.{ "four", "4" });

    table.setSelectedRow(2);

    const Callback = struct {
        var count: usize = 0;
        fn selected(_: usize) void {
            count += 1;
        }
    };
    table.setOnRowSelect(Callback.selected);

    table.removeRow(0);

    try std.testing.expectEqual(@as(usize, 3), table.rows.items.len);
    try std.testing.expectEqual(@as(usize, 1), table.selected_row.?);
    try std.testing.expectEqualStrings("three", table.cellView(table.selected_row.?, 0).text);
    try std.testing.expectEqual(@as(usize, 0), Callback.count);
}

test "table remove selected row notifies when replacement selected" {
    const alloc = std.testing.allocator;
    var table = try Table.init(alloc);
    defer table.deinit();

    try table.addColumn("A", 8, true);
    try table.addColumn("B", 4, true);

    try table.addRow(&.{ "one", "1" });
    try table.addRow(&.{ "two", "2" });
    try table.addRow(&.{ "three", "3" });

    table.setSelectedRow(1);

    const Callback = struct {
        var count: usize = 0;
        var last: usize = 99;
        fn selected(row: usize) void {
            count += 1;
            last = row;
        }
    };
    table.setOnRowSelect(Callback.selected);

    table.removeRow(1);

    try std.testing.expectEqual(@as(usize, 2), table.rows.items.len);
    try std.testing.expectEqual(@as(usize, 1), table.selected_row.?);
    try std.testing.expectEqualStrings("three", table.cellView(table.selected_row.?, 0).text);
    try std.testing.expectEqual(@as(usize, 1), Callback.count);
    try std.testing.expectEqual(@as(usize, 1), Callback.last);
}

test "table remove before edit preserves edited row" {
    const alloc = std.testing.allocator;
    var table = try Table.init(alloc);
    defer table.deinit();

    try table.addColumn("A", 8, true);

    try table.addRow(&.{"one"});
    try table.addRow(&.{"two"});
    try table.addRow(&.{"three"});

    table.setSelectedRow(2);
    try table.beginEdit();
    try std.testing.expectEqual(@as(?usize, 2), table.editing_row);

    table.removeRow(0);

    try std.testing.expectEqual(@as(?usize, 1), table.editing_row);
    try std.testing.expectEqual(@as(?usize, 0), table.editing_col);
    try std.testing.expectEqualStrings("three", table.edit_buffer.items);

    try table.edit_buffer.append(table.allocator, '!');
    try table.commitEdit();

    try std.testing.expectEqualStrings("two", table.cellView(0, 0).text);
    try std.testing.expectEqualStrings("three!", table.cellView(1, 0).text);
}

test "table remove edited row cancels edit" {
    const alloc = std.testing.allocator;
    var table = try Table.init(alloc);
    defer table.deinit();

    try table.addColumn("A", 8, true);

    try table.addRow(&.{"one"});
    try table.addRow(&.{"two"});
    try table.addRow(&.{"three"});

    table.setSelectedRow(1);
    try table.beginEdit();
    try table.edit_buffer.append(table.allocator, '!');

    table.removeRow(1);

    try std.testing.expectEqual(@as(?usize, null), table.editing_row);
    try std.testing.expectEqual(@as(?usize, null), table.editing_col);
    try std.testing.expectEqual(@as(usize, 0), table.edit_buffer.items.len);
    try std.testing.expectEqualStrings("three", table.cellView(table.selected_row.?, 0).text);
}
