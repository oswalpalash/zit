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
            .columns = std.ArrayList(TableColumn).init(allocator),
            .rows = std.ArrayList(std.ArrayList(TableCell)).init(allocator),
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
        self.columns.deinit();
        
        // Free row cell text
        for (self.rows.items) |row| {
            for (row.items) |cell| {
                self.allocator.free(cell.text);
            }
            row.deinit();
        }
        self.rows.deinit();
        
        self.allocator.destroy(self);
    }
    
    /// Add a column to the table
    pub fn addColumn(self: *Table, header: []const u8, width: i16, resizable: bool) !void {
        const header_copy = try self.allocator.alloc(u8, header.len);
        std.mem.copy(u8, header_copy, header);
        
        try self.columns.append(TableColumn{
            .header = header_copy,
            .width = width,
            .resizable = resizable,
        });
    }
    
    /// Add a row to the table
    pub fn addRow(self: *Table, cells: []const []const u8) !void {
        var new_row = std.ArrayList(TableCell).init(self.allocator);
        errdefer new_row.deinit();

        for (cells, 0..) |text, i| {
            if (i >= self.columns.items.len) break;

            const text_copy = try self.allocator.alloc(u8, text.len);
            @memcpy(text_copy, text);

            try new_row.append(TableCell{
                .text = text_copy,
                .fg = null,
                .bg = null,
            });
        }

        // Fill remaining columns with empty cells if needed
        while (new_row.items.len < self.columns.items.len) {
            const empty_text = try self.allocator.alloc(u8, 0);
            try new_row.append(TableCell{
                .text = empty_text,
                .fg = null,
                .bg = null,
            });
        }

        try self.rows.append(new_row);
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
        std.mem.copy(u8, text_copy, text);
        
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
        self.rows.items[row].deinit();
        _ = self.rows.orderedRemove(row);
        
        // Update selected row if needed
        if (self.selected_row != null and self.selected_row.? >= self.rows.items.len) {
            self.selected_row = if (self.rows.items.len > 0) self.rows.items.len - 1 else null;
        }
    }
    
    /// Clear all rows from the table
    pub fn clearRows(self: *Table) void {
        // Free all row cell text
        for (self.rows.items) |row| {
            for (row.items) |cell| {
                self.allocator.free(cell.text);
            }
            row.deinit();
        }
        
        self.rows.clearRetainingCapacity();
        self.selected_row = null;
        self.first_visible_row = 0;
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
    
    /// Draw implementation for Table
    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*Table, @alignCast(@ptrCast(widget_ptr)));
        
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
        const self = @as(*Table, @alignCast(@ptrCast(widget_ptr)));
        
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
                mouse_event.x >= rect.x and mouse_event.x < rect.x + rect.width) {
                
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
                rect.contains(mouse_event.x, mouse_event.y)) {
                if (self.first_visible_row > 0) {
                    self.first_visible_row -= 1;
                    return true;
                }
            } else if (mouse_event.action == .press and mouse_event.button == 5 and 
                       rect.contains(mouse_event.x, mouse_event.y)) {
                if (self.first_visible_row + self.getVisibleRowCount() < self.rows.items.len) {
                    self.first_visible_row += 1;
                    return true;
                }
            }
        }
        
        // Handle key events
        if (event == .key and self.widget.focused) {
            const key_event = event.key;
            
            if (key_event.key == 'j' or key_event.key == 'J' or key_event.key == 2) { // Down
                if (self.selected_row == null) {
                    self.setSelectedRow(0);
                } else if (self.selected_row.? < self.rows.items.len - 1) {
                    self.setSelectedRow(self.selected_row.? + 1);
                }
                return true;
            } else if (key_event.key == 'k' or key_event.key == 'K' or key_event.key == 1) { // Up
                if (self.selected_row == null) {
                    self.setSelectedRow(0);
                } else if (self.selected_row.? > 0) {
                    self.setSelectedRow(self.selected_row.? - 1);
                }
                return true;
            } else if (key_event.key == 6) { // Page down
                const visible_rows = self.getVisibleRowCount();
                
                if (self.selected_row == null) {
                    self.setSelectedRow(0);
                } else {
                    const new_row = @min(self.selected_row.? + visible_rows, self.rows.items.len - 1);
                    self.setSelectedRow(new_row);
                }
                return true;
            } else if (key_event.key == 5) { // Page up
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
                return true;
            } else if (key_event.key == 7) { // Home
                self.setSelectedRow(0);
                return true;
            } else if (key_event.key == 8) { // End
                self.setSelectedRow(self.rows.items.len - 1);
                return true;
            }
        }
        
        return false;
    }
    
    /// Layout implementation for Table
    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*Table, @alignCast(@ptrCast(widget_ptr)));
        self.widget.rect = rect;
        
        // Ensure selected row is still visible after layout
        if (self.selected_row != null) {
            self.ensureRowVisible(self.selected_row.?);
        }
    }
    
    /// Get preferred size implementation for Table
    fn getPreferredSizeFn(widget_ptr: *anyopaque) anyerror!layout_module.Size {
        const self = @as(*Table, @alignCast(@ptrCast(widget_ptr)));
        
        // Calculate width based on columns
        var width: u16 = 0;
        for (self.columns.items) |column| {
            width += column.width;
        }
        
        // Preferred height depends on number of rows plus header
        const header_height: u16 = if (self.show_headers) 1 else 0;
        const rows_height = @min(20, @as(u16, @intCast(self.rows.items.len)));
        const height = header_height + rows_height;
        
        return layout_module.Size.init(width, height);
    }
    
    /// Can focus implementation for Table
    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*Table, @alignCast(@ptrCast(widget_ptr)));
        return self.widget.enabled and self.rows.items.len > 0;
    }
}; 