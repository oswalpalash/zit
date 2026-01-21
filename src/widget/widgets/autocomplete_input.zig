const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const theme = @import("../theme.zig");
const InputField = @import("input_field.zig").InputField;

/// Text input with live typeahead suggestions.
pub const AutocompleteInput = struct {
    widget: base.Widget,
    allocator: std.mem.Allocator,
    input_field: *InputField,
    suggestions: std.ArrayList([]u8),
    filtered: std.ArrayList(usize),
    selected: usize = 0,
    max_visible: usize = 5,
    case_sensitive: bool = false,
    on_select: ?*const fn ([]const u8) void = null,
    theme_value: theme.Theme,

    pub const vtable = base.Widget.VTable{
        .draw = drawFn,
        .handle_event = handleEventFn,
        .layout = layoutFn,
        .get_preferred_size = getPreferredSizeFn,
        .can_focus = canFocusFn,
    };

    pub fn init(allocator: std.mem.Allocator, max_length: usize) !*AutocompleteInput {
        const self = try allocator.create(AutocompleteInput);
        const theme_value = theme.Theme.dark();
        const field = try InputField.init(allocator, max_length);
        self.* = AutocompleteInput{
            .widget = base.Widget.init(&vtable),
            .allocator = allocator,
            .input_field = field,
            .suggestions = try std.ArrayList([]u8).initCapacity(allocator, 0),
            .filtered = try std.ArrayList(usize).initCapacity(allocator, 0),
            .theme_value = theme_value,
        };
        self.input_field.widget.parent = &self.widget;
        return self;
    }

    pub fn deinit(self: *AutocompleteInput) void {
        for (self.suggestions.items) |s| {
            self.allocator.free(s);
        }
        self.suggestions.deinit(self.allocator);
        self.filtered.deinit(self.allocator);
        self.input_field.deinit();
        self.allocator.destroy(self);
    }

    pub fn setSuggestions(self: *AutocompleteInput, values: []const []const u8) !void {
        for (self.suggestions.items) |s| {
            self.allocator.free(s);
        }
        self.suggestions.clearRetainingCapacity();

        for (values) |v| {
            const copy = try self.allocator.dupe(u8, v);
            try self.suggestions.append(self.allocator, copy);
        }
        try self.updateFilter();
    }

    pub fn setMaxVisible(self: *AutocompleteInput, count: usize) void {
        self.max_visible = @max(count, @as(usize, 1));
    }

    pub fn setCaseSensitive(self: *AutocompleteInput, enabled: bool) void {
        self.case_sensitive = enabled;
        self.updateFilter() catch {};
    }

    pub fn setOnSelect(self: *AutocompleteInput, callback: *const fn ([]const u8) void) void {
        self.on_select = callback;
    }

    pub fn setTheme(self: *AutocompleteInput, t: theme.Theme) !void {
        self.theme_value = t;
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const self = @as(*AutocompleteInput, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible) return;
        const rect = self.widget.rect;
        if (rect.width == 0 or rect.height == 0) return;

        self.syncFocusState();

        const input_rect = layout_module.Rect.init(rect.x, rect.y, rect.width, 1);
        try self.input_field.widget.layout(input_rect);
        try self.input_field.widget.draw(renderer);

        const available_rows = if (rect.height > 1) rect.height - 1 else 0;
        const visible_rows: usize = @intCast(@min(@as(usize, @intCast(available_rows)), @min(self.filtered.items.len, self.max_visible)));
        if (visible_rows == 0) return;

        const bg = self.theme_value.color(.surface);
        const fg = self.theme_value.color(.text);
        const highlight_bg = self.theme_value.color(.accent);
        const muted = self.theme_value.color(.muted);

        var row: usize = 0;
        while (row < visible_rows) : (row += 1) {
            const y = rect.y + 1 + @as(u16, @intCast(row));
            const is_selected = row == self.selected;
            const color_bg = if (is_selected) highlight_bg else bg;
            const color_fg = if (is_selected) self.theme_value.color(.background) else fg;

            renderer.fillRect(rect.x, y, rect.width, 1, ' ', color_fg, color_bg, render.Style{});
            const idx = self.filtered.items[row];
            const label = self.suggestions.items[idx];
            renderer.drawSmartStr(rect.x + 1, y, label, color_fg, color_bg, render.Style{});
            renderer.drawSmartStr(rect.x + rect.width - 2, y, "↵", muted, color_bg, render.Style{ .bold = is_selected });
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const self = @as(*AutocompleteInput, @ptrCast(@alignCast(widget_ptr)));
        if (!self.widget.visible or !self.widget.enabled) {
            return false;
        }

        self.syncFocusState();

        if (event == .key and self.widget.focused and self.filtered.items.len > 0) {
            const key_event = event.key;
            switch (key_event.key) {
                input.KeyCode.UP => {
                    if (self.selected > 0) self.selected -= 1;
                    return true;
                },
                input.KeyCode.DOWN => {
                    if (self.selected + 1 < self.filtered.items.len and self.selected + 1 < self.max_visible) {
                        self.selected += 1;
                    }
                    return true;
                },
                input.KeyCode.ENTER, input.KeyCode.TAB => {
                    return try self.acceptSelection();
                },
                else => {},
            }
        }

        const handled_input = try self.input_field.widget.handleEvent(event);
        if (event == .key and handled_input) {
            try self.updateFilter();
        }
        return handled_input;
    }

    fn layoutFn(widget_ptr: *anyopaque, rect: layout_module.Rect) anyerror!void {
        const self = @as(*AutocompleteInput, @ptrCast(@alignCast(widget_ptr)));
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(_: *anyopaque) anyerror!layout_module.Size {
        return layout_module.Size.init(24, 4);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const self = @as(*AutocompleteInput, @ptrCast(@alignCast(widget_ptr)));
        return self.widget.visible and self.widget.enabled and self.input_field.widget.canFocus();
    }

    fn updateFilter(self: *AutocompleteInput) !void {
        self.filtered.clearRetainingCapacity();
        const query = self.input_field.getText();
        if (query.len == 0 or self.suggestions.items.len == 0) return;

        for (self.suggestions.items, 0..) |s, idx| {
            if (self.matches(query, s)) {
                try self.filtered.append(self.allocator, idx);
            }
        }

        if (self.selected >= self.filtered.items.len) {
            self.selected = if (self.filtered.items.len == 0) 0 else 0;
        }
    }

    fn matches(self: *AutocompleteInput, needle: []const u8, haystack: []const u8) bool {
        if (self.case_sensitive) {
            return std.mem.indexOf(u8, haystack, needle) != null;
        }

        if (needle.len == 0) return true;
        if (haystack.len < needle.len) return false;

        var i: usize = 0;
        while (i + needle.len <= haystack.len) : (i += 1) {
            if (eqIgnoreCase(needle, haystack[i .. i + needle.len])) {
                return true;
            }
        }
        return false;
    }

    fn eqIgnoreCase(a: []const u8, b: []const u8) bool {
        if (a.len != b.len) return false;
        for (a, b) |lhs, rhs| {
            if (std.ascii.toLower(lhs) != std.ascii.toLower(rhs)) return false;
        }
        return true;
    }

    fn acceptSelection(self: *AutocompleteInput) !bool {
        if (self.filtered.items.len == 0) return false;
        const idx = self.filtered.items[@min(self.selected, self.filtered.items.len - 1)];
        const choice = self.suggestions.items[idx];
        self.input_field.setText(choice);
        if (self.on_select) |cb| {
            cb(choice);
        }
        try self.updateFilter();
        return true;
    }

    fn syncFocusState(self: *AutocompleteInput) void {
        self.input_field.widget.focused = self.widget.focused;
        self.input_field.widget.enabled = self.widget.enabled;
    }
};

test "autocomplete filters suggestions" {
    const alloc = std.testing.allocator;
    var ac = try AutocompleteInput.init(alloc, 32);
    defer ac.deinit();
    try ac.setSuggestions(&[_][]const u8{ "alpha", "beta", "alpaca" });
    ac.input_field.setText("alp");
    try ac.updateFilter();
    try std.testing.expectEqual(@as(usize, 2), ac.filtered.items.len);
}

test "autocomplete selection commits suggestion" {
    const alloc = std.testing.allocator;
    var ac = try AutocompleteInput.init(alloc, 32);
    defer ac.deinit();
    ac.widget.focused = true;
    try ac.setSuggestions(&[_][]const u8{ "one", "two" });
    ac.input_field.setText("t");
    try ac.updateFilter();
    const enter_event = input.Event{ .key = input.KeyEvent.init(input.KeyCode.ENTER, input.KeyModifiers{}) };
    try std.testing.expect(try ac.widget.handleEvent(enter_event));
    try std.testing.expectEqualStrings("two", ac.input_field.getText());
}
