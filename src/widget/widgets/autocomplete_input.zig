const std = @import("std");
const base = @import("base_widget.zig");
const layout_module = @import("../../layout/layout.zig");
const render = @import("../../render/render.zig");
const input = @import("../../input/input.zig");
const theme = @import("../theme.zig");
const accessibility = @import("../accessibility.zig");
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
        errdefer allocator.destroy(self);

        const theme_value = theme.Theme.dark();
        const field = try InputField.init(allocator, max_length);
        errdefer field.deinit();

        var suggestions = try std.ArrayList([]u8).initCapacity(allocator, 0);
        errdefer suggestions.deinit(allocator);
        var filtered = try std.ArrayList(usize).initCapacity(allocator, 0);
        errdefer filtered.deinit(allocator);

        self.* = AutocompleteInput{
            .widget = base.Widget.init(&vtable),
            .allocator = allocator,
            .input_field = field,
            .suggestions = suggestions,
            .filtered = filtered,
            .theme_value = theme_value,
        };
        self.input_field.widget.parent = &self.widget;
        self.widget.setAccessibility(@intFromEnum(accessibility.Role.input), "Autocomplete input", "");
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
        var next_suggestions = try std.ArrayList([]u8).initCapacity(self.allocator, values.len);
        errdefer self.freeSuggestionList(&next_suggestions);

        for (values) |v| {
            const copy = try self.allocator.dupe(u8, v);
            next_suggestions.append(self.allocator, copy) catch |err| {
                self.allocator.free(copy);
                return err;
            };
        }

        var next_filtered = try self.buildFilter(next_suggestions.items);
        errdefer next_filtered.deinit(self.allocator);

        self.freeSuggestionList(&self.suggestions);
        self.filtered.deinit(self.allocator);
        self.suggestions = next_suggestions;
        self.filtered = next_filtered;
        self.clampSelection();
        self.widget.markDirty();
    }

    pub fn setMaxVisible(self: *AutocompleteInput, count: usize) void {
        self.max_visible = @max(count, @as(usize, 1));
        self.clampSelection();
        self.widget.markDirty();
    }

    pub fn setCaseSensitive(self: *AutocompleteInput, enabled: bool) !void {
        if (self.case_sensitive == enabled) return;

        const next_filtered = try self.buildFilterWithCase(self.suggestions.items, enabled);

        self.filtered.deinit(self.allocator);
        self.filtered = next_filtered;
        self.case_sensitive = enabled;
        self.clampSelection();
        self.widget.markDirty();
    }

    pub fn setOnSelect(self: *AutocompleteInput, callback: *const fn ([]const u8) void) void {
        self.on_select = callback;
    }

    pub fn setTheme(self: *AutocompleteInput, t: theme.Theme) !void {
        self.theme_value = t;
    }

    fn drawFn(widget_ptr: *anyopaque, renderer: *render.Renderer) anyerror!void {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *AutocompleteInput = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible) return;
        const rect = self.widget.rect;
        if (rect.width == 0 or rect.height == 0) return;

        self.syncFocusState();

        const input_rect = layout_module.Rect.init(rect.x, rect.y, rect.width, 1);
        try self.input_field.widget.layout(input_rect);
        try self.input_field.widget.draw(renderer);

        self.clampSelection();
        const available_rows = if (rect.height > 1) rect.height - 1 else 0;
        const visible_rows: usize = @intCast(@min(@as(usize, @intCast(available_rows)), @min(self.filtered.items.len, self.max_visible)));
        if (visible_rows == 0) return;

        const bg = self.theme_value.color(.surface);
        const fg = self.theme_value.color(.text);
        const highlight_bg = self.theme_value.color(.accent);
        const muted = self.theme_value.color(.muted);

        var row: usize = 0;
        while (row < visible_rows) : (row += 1) {
            const y_u32 = @as(u32, rect.y) + 1 + @as(u32, @intCast(row));
            const y = u16Coord(y_u32) orelse break;
            const is_selected = row == self.selected;
            const color_bg = if (is_selected) highlight_bg else bg;
            const color_fg = if (is_selected) self.theme_value.color(.background) else fg;

            renderer.fillRect(rect.x, y, rect.width, 1, ' ', color_fg, color_bg, render.Style{});
            const idx = self.filtered.items[row];
            const label = self.suggestions.items[idx];
            if (u16Coord(@as(u32, rect.x) + 1)) |label_x| {
                renderer.drawSmartStr(label_x, y, label, color_fg, color_bg, render.Style{});
            }
            if (rect.width >= 2) {
                const hint_x_u32 = @as(u32, rect.x) + @as(u32, rect.width) - 2;
                if (u16Coord(hint_x_u32)) |hint_x| {
                    renderer.drawSmartStr(hint_x, y, "↵", muted, color_bg, render.Style{ .bold = is_selected });
                }
            }
        }
    }

    fn handleEventFn(widget_ptr: *anyopaque, event: input.Event) anyerror!bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *AutocompleteInput = @fieldParentPtr("widget", widget_ref);
        if (!self.widget.visible or !self.widget.enabled) {
            return false;
        }

        self.syncFocusState();

        if (event == .key and self.widget.focused and self.filtered.items.len > 0) {
            const key_event = event.key;
            self.clampSelection();
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
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *AutocompleteInput = @fieldParentPtr("widget", widget_ref);
        self.widget.rect = rect;
    }

    fn getPreferredSizeFn(_: *anyopaque) anyerror!layout_module.Size {
        return layout_module.Size.init(24, 4);
    }

    fn canFocusFn(widget_ptr: *anyopaque) bool {
        const widget_ref: *base.Widget = @ptrCast(@alignCast(widget_ptr));
        const self: *AutocompleteInput = @fieldParentPtr("widget", widget_ref);
        return self.widget.visible and self.widget.enabled and self.input_field.widget.canFocus();
    }

    fn updateFilter(self: *AutocompleteInput) !void {
        var next_filtered = try self.buildFilter(self.suggestions.items);
        errdefer next_filtered.deinit(self.allocator);

        self.filtered.deinit(self.allocator);
        self.filtered = next_filtered;
        self.clampSelection();
        self.widget.markDirty();
    }

    fn buildFilter(self: *AutocompleteInput, suggestions: []const []u8) !std.ArrayList(usize) {
        return self.buildFilterWithCase(suggestions, self.case_sensitive);
    }

    fn buildFilterWithCase(self: *AutocompleteInput, suggestions: []const []u8, case_sensitive: bool) !std.ArrayList(usize) {
        var next_filtered = try std.ArrayList(usize).initCapacity(self.allocator, 0);
        errdefer next_filtered.deinit(self.allocator);

        const query = self.input_field.getText();
        if (query.len == 0 or suggestions.len == 0) return next_filtered;

        for (suggestions, 0..) |s, idx| {
            if (matches(case_sensitive, query, s)) {
                try next_filtered.append(self.allocator, idx);
            }
        }

        return next_filtered;
    }

    fn clampSelection(self: *AutocompleteInput) void {
        const visible_items = @min(self.filtered.items.len, self.max_visible);
        if (visible_items == 0) {
            self.selected = 0;
        } else if (self.selected >= visible_items) {
            self.selected = visible_items - 1;
        }
    }

    fn freeSuggestionList(self: *AutocompleteInput, suggestions: *std.ArrayList([]u8)) void {
        for (suggestions.items) |s| {
            self.allocator.free(s);
        }
        suggestions.deinit(self.allocator);
    }

    fn matches(case_sensitive: bool, needle: []const u8, haystack: []const u8) bool {
        if (case_sensitive) {
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
        try self.input_field.setText(choice);
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

fn u16Coord(value: u32) ?u16 {
    if (value > std.math.maxInt(u16)) return null;
    return @intCast(value);
}

test "autocomplete filters suggestions" {
    const alloc = std.testing.allocator;
    var ac = try AutocompleteInput.init(alloc, 32);
    defer ac.deinit();
    try ac.setSuggestions(&[_][]const u8{ "alpha", "beta", "alpaca" });
    try ac.input_field.setText("alp");
    try ac.updateFilter();
    try std.testing.expectEqual(@as(usize, 2), ac.filtered.items.len);
}

test "autocomplete selection commits suggestion" {
    const alloc = std.testing.allocator;
    var ac = try AutocompleteInput.init(alloc, 32);
    defer ac.deinit();
    ac.widget.focused = true;
    try ac.setSuggestions(&[_][]const u8{ "one", "two" });
    try ac.input_field.setText("t");
    try ac.updateFilter();
    const enter_event = input.Event{ .key = input.KeyEvent.init(input.KeyCode.ENTER, input.KeyModifiers{}) };
    try std.testing.expect(try ac.widget.handleEvent(enter_event));
    try std.testing.expectEqualStrings("two", ac.input_field.getText());
}

test "autocomplete clamps stale selection before keyboard navigation" {
    const alloc = std.testing.allocator;
    var ac = try AutocompleteInput.init(alloc, 32);
    defer ac.deinit();

    ac.widget.focused = true;
    ac.setMaxVisible(2);
    try ac.setSuggestions(&[_][]const u8{ "alpha", "alpine", "alt" });
    try ac.input_field.setText("al");
    try ac.updateFilter();
    ac.selected = std.math.maxInt(usize);

    const down_event = input.Event{ .key = input.KeyEvent.init(input.KeyCode.DOWN, input.KeyModifiers{}) };
    try std.testing.expect(try ac.widget.handleEvent(down_event));
    try std.testing.expectEqual(@as(usize, 1), ac.selected);

    const up_event = input.Event{ .key = input.KeyEvent.init(input.KeyCode.UP, input.KeyModifiers{}) };
    try std.testing.expect(try ac.widget.handleEvent(up_event));
    try std.testing.expectEqual(@as(usize, 0), ac.selected);
}

test "autocomplete setMaxVisible clamps stale visible selection" {
    const alloc = std.testing.allocator;
    var ac = try AutocompleteInput.init(alloc, 32);
    defer ac.deinit();

    ac.setMaxVisible(3);
    try ac.setSuggestions(&[_][]const u8{ "alpha", "alpine", "alt" });
    try ac.input_field.setText("al");
    try ac.updateFilter();
    ac.selected = 2;

    ac.setMaxVisible(1);
    try std.testing.expectEqual(@as(usize, 0), ac.selected);
}

test "autocomplete draw clamps stale selection" {
    const alloc = std.testing.allocator;
    var ac = try AutocompleteInput.init(alloc, 32);
    defer ac.deinit();

    ac.setMaxVisible(2);
    try ac.setSuggestions(&[_][]const u8{ "alpha", "alpine", "alt" });
    try ac.input_field.setText("al");
    try ac.updateFilter();
    ac.selected = std.math.maxInt(usize);

    var renderer = try render.Renderer.init(alloc, 8, 3);
    defer renderer.deinit();
    try ac.widget.layout(layout_module.Rect.init(0, 0, 8, 3));
    try ac.widget.draw(&renderer);

    try std.testing.expectEqual(@as(usize, 1), ac.selected);
}

test "autocomplete accepts clamped stale selection" {
    const alloc = std.testing.allocator;
    var ac = try AutocompleteInput.init(alloc, 32);
    defer ac.deinit();

    ac.widget.focused = true;
    ac.setMaxVisible(2);
    try ac.setSuggestions(&[_][]const u8{ "alpha", "alpine", "alt" });
    try ac.input_field.setText("al");
    try ac.updateFilter();
    ac.selected = std.math.maxInt(usize);

    const enter_event = input.Event{ .key = input.KeyEvent.init(input.KeyCode.ENTER, input.KeyModifiers{}) };
    try std.testing.expect(try ac.widget.handleEvent(enter_event));
    try std.testing.expectEqualStrings("alpine", ac.input_field.getText());
}

test "autocomplete clips popup edge coordinates before u16 overflow" {
    const alloc = std.testing.allocator;
    var ac = try AutocompleteInput.init(alloc, 32);
    defer ac.deinit();

    try ac.setSuggestions(&[_][]const u8{ "alpha", "alpine" });
    try ac.input_field.setText("al");
    try ac.updateFilter();
    try ac.widget.layout(layout_module.Rect.init(std.math.maxInt(u16), 0, 4, 3));

    var renderer = try render.Renderer.init(alloc, 4, 3);
    defer renderer.deinit();
    try ac.widget.draw(&renderer);
}

fn autocompleteInitAllocationFailureHarness(allocator: std.mem.Allocator) !void {
    const ac = try AutocompleteInput.init(allocator, 32);
    ac.deinit();
}

test "autocomplete init cleans up every allocation failure path" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, autocompleteInitAllocationFailureHarness, .{});
}

fn autocompleteSetSuggestionsAllocationFailureHarness(allocator: std.mem.Allocator) !void {
    var ac = try AutocompleteInput.init(allocator, 32);
    defer ac.deinit();

    try ac.setSuggestions(&[_][]const u8{ "alpha", "beta", "alpaca" });
    try ac.input_field.setText("alp");
    try ac.updateFilter();
    try ac.setSuggestions(&[_][]const u8{ "delta", "delphi", "deal" });
}

test "autocomplete setSuggestions cleans up every allocation failure path" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, autocompleteSetSuggestionsAllocationFailureHarness, .{});
}

test "autocomplete suggestions survive allocation failure" {
    const alloc = std.testing.allocator;
    var ac = try AutocompleteInput.init(alloc, 32);
    defer ac.deinit();

    try ac.setSuggestions(&[_][]const u8{ "alpha", "beta", "alpaca" });
    try ac.input_field.setText("alp");
    try ac.updateFilter();
    try std.testing.expectEqual(@as(usize, 2), ac.filtered.items.len);

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = ac.allocator;
    ac.allocator = failing.allocator();
    defer ac.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, ac.setSuggestions(&[_][]const u8{ "delta", "delphi" }));
    try std.testing.expectEqual(@as(usize, 3), ac.suggestions.items.len);
    try std.testing.expectEqualStrings("alpha", ac.suggestions.items[0]);
    try std.testing.expectEqualStrings("beta", ac.suggestions.items[1]);
    try std.testing.expectEqualStrings("alpaca", ac.suggestions.items[2]);
    try std.testing.expectEqual(@as(usize, 2), ac.filtered.items.len);
}

test "autocomplete filter survives allocation failure" {
    const alloc = std.testing.allocator;
    var ac = try AutocompleteInput.init(alloc, 32);
    defer ac.deinit();

    try ac.setSuggestions(&[_][]const u8{ "alpha", "beta", "alpaca" });
    try ac.input_field.setText("alp");
    try ac.updateFilter();
    try std.testing.expectEqual(@as(usize, 2), ac.filtered.items.len);

    try ac.input_field.setText("beta");
    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = ac.allocator;
    ac.allocator = failing.allocator();
    defer ac.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, ac.updateFilter());
    try std.testing.expectEqual(@as(usize, 2), ac.filtered.items.len);
    try std.testing.expectEqual(@as(usize, 0), ac.filtered.items[0]);
    try std.testing.expectEqual(@as(usize, 2), ac.filtered.items[1]);
}

test "autocomplete case sensitivity survives allocation failure" {
    const alloc = std.testing.allocator;
    var ac = try AutocompleteInput.init(alloc, 32);
    defer ac.deinit();

    try ac.setSuggestions(&[_][]const u8{ "Alpha", "alpine" });
    try ac.input_field.setText("alp");
    try ac.updateFilter();
    try std.testing.expect(!ac.case_sensitive);
    try std.testing.expectEqual(@as(usize, 2), ac.filtered.items.len);

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = ac.allocator;
    ac.allocator = failing.allocator();
    defer ac.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, ac.setCaseSensitive(true));
    try std.testing.expect(!ac.case_sensitive);
    try std.testing.expectEqual(@as(usize, 2), ac.filtered.items.len);
    try std.testing.expectEqual(@as(usize, 0), ac.filtered.items[0]);
    try std.testing.expectEqual(@as(usize, 1), ac.filtered.items[1]);
}
