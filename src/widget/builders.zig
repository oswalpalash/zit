const std = @import("std");
const render = @import("../render/render.zig");
const base = @import("widgets/base_widget.zig");
const Button = @import("widgets/button.zig").Button;
const Label = @import("widgets/label.zig").Label;
const Checkbox = @import("widgets/checkbox.zig").Checkbox;
const InputField = @import("widgets/input_field.zig").InputField;
const ProgressBar = @import("widgets/progress_bar.zig").ProgressBar;
const ProgressDirection = @import("widgets/progress_bar.zig").ProgressDirection;

/// Shared configuration for all builders.
const Common = struct {
    id: ?[]const u8 = null,
    class: ?[]const u8 = null,
    enabled: bool = true,
    visible: bool = true,
    focus_ring: ?render.FocusRingStyle = null,

    fn apply(self: Common, widget: *base.Widget) void {
        if (self.id) |id| widget.id = id;
        widget.enabled = self.enabled;
        widget.visible = self.visible;
        widget.style_class = self.class;
        if (self.focus_ring) |ring| widget.setFocusRing(ring);
    }
};

/// Fluent builder for buttons with sensible defaults.
pub const ButtonBuilder = struct {
    allocator: std.mem.Allocator,
    label: []const u8 = "Button",
    fg: render.Color = render.Color.named(render.NamedColor.white),
    bg: render.Color = render.Color.named(render.NamedColor.blue),
    focused_fg: render.Color = render.Color.named(render.NamedColor.black),
    focused_bg: render.Color = render.Color.named(render.NamedColor.cyan),
    disabled_fg: render.Color = render.Color.named(render.NamedColor.bright_black),
    disabled_bg: render.Color = render.Color.named(render.NamedColor.black),
    style: render.Style = render.Style{ .bold = true },
    border: render.BorderStyle = .rounded,
    on_press: ?*const fn () void = null,
    common: Common = .{},

    pub fn init(allocator: std.mem.Allocator) ButtonBuilder {
        return .{ .allocator = allocator };
    }

    pub fn text(self: *ButtonBuilder, value: []const u8) *ButtonBuilder {
        self.label = value;
        return self;
    }

    pub fn colors(self: *ButtonBuilder, fg: render.Color, bg: render.Color) *ButtonBuilder {
        self.fg = fg;
        self.bg = bg;
        return self;
    }

    pub fn focusedColors(self: *ButtonBuilder, fg: render.Color, bg: render.Color) *ButtonBuilder {
        self.focused_fg = fg;
        self.focused_bg = bg;
        return self;
    }

    pub fn disabledColors(self: *ButtonBuilder, fg: render.Color, bg: render.Color) *ButtonBuilder {
        self.disabled_fg = fg;
        self.disabled_bg = bg;
        return self;
    }

    pub fn borderStyle(self: *ButtonBuilder, border: render.BorderStyle) *ButtonBuilder {
        self.border = border;
        return self;
    }

    pub fn withStyle(self: *ButtonBuilder, style: render.Style) *ButtonBuilder {
        self.style = style;
        return self;
    }

    pub fn onPress(self: *ButtonBuilder, callback: *const fn () void) *ButtonBuilder {
        self.on_press = callback;
        return self;
    }

    pub fn id(self: *ButtonBuilder, value: []const u8) *ButtonBuilder {
        self.common.id = value;
        return self;
    }

    pub fn class(self: *ButtonBuilder, value: []const u8) *ButtonBuilder {
        self.common.class = value;
        return self;
    }

    pub fn focusRing(self: *ButtonBuilder, ring: render.FocusRingStyle) *ButtonBuilder {
        self.common.focus_ring = ring;
        return self;
    }

    pub fn enabled(self: *ButtonBuilder, value: bool) *ButtonBuilder {
        self.common.enabled = value;
        return self;
    }

    pub fn visible(self: *ButtonBuilder, value: bool) *ButtonBuilder {
        self.common.visible = value;
        return self;
    }

    pub fn build(self: *ButtonBuilder) !*Button {
        var button = try Button.init(self.allocator, self.label);
        button.setColors(self.fg, self.bg, self.focused_fg, self.focused_bg);
        button.setDisabledColors(self.disabled_fg, self.disabled_bg);
        button.setBorder(self.border);
        button.style = self.style;
        if (self.on_press) |callback| {
            button.setOnPress(callback);
        }
        self.common.apply(&button.widget);
        return button;
    }
};

/// Fluent builder for labels.
pub const LabelBuilder = struct {
    allocator: std.mem.Allocator,
    text: []const u8 = "Label",
    fg: render.Color = render.Color.named(render.NamedColor.default),
    bg: render.Color = render.Color.named(render.NamedColor.default),
    style: render.Style = render.Style{},
    alignment: Label.TextAlignment = .left,
    common: Common = .{},

    pub fn init(allocator: std.mem.Allocator) LabelBuilder {
        return .{ .allocator = allocator };
    }

    pub fn content(self: *LabelBuilder, value: []const u8) *LabelBuilder {
        self.text = value;
        return self;
    }

    pub fn alignTo(self: *LabelBuilder, alignment: Label.TextAlignment) *LabelBuilder {
        self.alignment = alignment;
        return self;
    }

    pub fn colors(self: *LabelBuilder, fg: render.Color, bg: render.Color) *LabelBuilder {
        self.fg = fg;
        self.bg = bg;
        return self;
    }

    pub fn textStyle(self: *LabelBuilder, style: render.Style) *LabelBuilder {
        self.style = style;
        return self;
    }

    pub fn id(self: *LabelBuilder, value: []const u8) *LabelBuilder {
        self.common.id = value;
        return self;
    }

    pub fn class(self: *LabelBuilder, value: []const u8) *LabelBuilder {
        self.common.class = value;
        return self;
    }

    pub fn enabled(self: *LabelBuilder, value: bool) *LabelBuilder {
        self.common.enabled = value;
        return self;
    }

    pub fn visible(self: *LabelBuilder, value: bool) *LabelBuilder {
        self.common.visible = value;
        return self;
    }

    pub fn build(self: *LabelBuilder) !*Label {
        var label = try Label.init(self.allocator, self.text);
        label.setAlignment(self.alignment);
        label.setColor(self.fg, self.bg);
        label.setStyle(self.style);
        self.common.apply(&label.widget);
        return label;
    }
};

/// Fluent builder for checkboxes.
pub const CheckboxBuilder = struct {
    allocator: std.mem.Allocator,
    label: []const u8 = "Checkbox",
    checked: bool = false,
    fg: render.Color = render.Color.named(render.NamedColor.default),
    bg: render.Color = render.Color.named(render.NamedColor.default),
    style: render.Style = render.Style{},
    on_toggle: ?*const fn (bool) void = null,
    common: Common = .{},

    pub fn init(allocator: std.mem.Allocator) CheckboxBuilder {
        return .{ .allocator = allocator };
    }

    pub fn text(self: *CheckboxBuilder, value: []const u8) *CheckboxBuilder {
        self.label = value;
        return self;
    }

    pub fn setChecked(self: *CheckboxBuilder, value: bool) *CheckboxBuilder {
        self.checked = value;
        return self;
    }

    pub fn colors(self: *CheckboxBuilder, fg: render.Color, bg: render.Color) *CheckboxBuilder {
        self.fg = fg;
        self.bg = bg;
        return self;
    }

    pub fn textStyle(self: *CheckboxBuilder, style: render.Style) *CheckboxBuilder {
        self.style = style;
        return self;
    }

    pub fn onToggle(self: *CheckboxBuilder, callback: *const fn (bool) void) *CheckboxBuilder {
        self.on_toggle = callback;
        return self;
    }

    pub fn id(self: *CheckboxBuilder, value: []const u8) *CheckboxBuilder {
        self.common.id = value;
        return self;
    }

    pub fn class(self: *CheckboxBuilder, value: []const u8) *CheckboxBuilder {
        self.common.class = value;
        return self;
    }

    pub fn enabled(self: *CheckboxBuilder, value: bool) *CheckboxBuilder {
        self.common.enabled = value;
        return self;
    }

    pub fn visible(self: *CheckboxBuilder, value: bool) *CheckboxBuilder {
        self.common.visible = value;
        return self;
    }

    pub fn build(self: *CheckboxBuilder) !*Checkbox {
        var checkbox = try Checkbox.init(self.allocator, self.label);
        checkbox.checked = self.checked;
        checkbox.fg = self.fg;
        checkbox.bg = self.bg;
        checkbox.style = self.style;
        checkbox.on_toggle = self.on_toggle;
        self.common.apply(&checkbox.widget);
        return checkbox;
    }
};

/// Fluent builder for input fields.
pub const InputBuilder = struct {
    allocator: std.mem.Allocator,
    placeholder: []const u8 = "",
    initial: []const u8 = "",
    fg: render.Color = render.Color.named(render.NamedColor.default),
    bg: render.Color = render.Color.named(render.NamedColor.default),
    focused_fg: render.Color = render.Color.named(render.NamedColor.black),
    focused_bg: render.Color = render.Color.named(render.NamedColor.cyan),
    disabled_fg: render.Color = render.Color.named(render.NamedColor.bright_black),
    disabled_bg: render.Color = render.Color.named(render.NamedColor.black),
    style: render.Style = render.Style{},
    on_change: ?*const fn ([]const u8) void = null,
    max_len: usize = 256,
    common: Common = .{},
    prefer_system_clipboard: bool = false,

    pub fn init(allocator: std.mem.Allocator) InputBuilder {
        return .{ .allocator = allocator };
    }

    pub fn withPlaceholder(self: *InputBuilder, placeholder_text: []const u8) *InputBuilder {
        self.placeholder = placeholder_text;
        return self;
    }

    pub fn value(self: *InputBuilder, initial_text: []const u8) *InputBuilder {
        self.initial = initial_text;
        return self;
    }

    pub fn colors(self: *InputBuilder, fg: render.Color, bg: render.Color) *InputBuilder {
        self.fg = fg;
        self.bg = bg;
        return self;
    }

    pub fn focusColors(self: *InputBuilder, fg: render.Color, bg: render.Color) *InputBuilder {
        self.focused_fg = fg;
        self.focused_bg = bg;
        return self;
    }

    pub fn disabledColors(self: *InputBuilder, fg: render.Color, bg: render.Color) *InputBuilder {
        self.disabled_fg = fg;
        self.disabled_bg = bg;
        return self;
    }

    pub fn textStyle(self: *InputBuilder, style: render.Style) *InputBuilder {
        self.style = style;
        return self;
    }

    pub fn onChange(self: *InputBuilder, callback: *const fn ([]const u8) void) *InputBuilder {
        self.on_change = callback;
        return self;
    }

    pub fn maxLength(self: *InputBuilder, limit: usize) *InputBuilder {
        self.max_len = limit;
        return self;
    }

    pub fn id(self: *InputBuilder, identifier: []const u8) *InputBuilder {
        self.common.id = identifier;
        return self;
    }

    pub fn class(self: *InputBuilder, class_name: []const u8) *InputBuilder {
        self.common.class = class_name;
        return self;
    }

    pub fn focusRing(self: *InputBuilder, ring: render.FocusRingStyle) *InputBuilder {
        self.common.focus_ring = ring;
        return self;
    }

    pub fn enabled(self: *InputBuilder, is_enabled: bool) *InputBuilder {
        self.common.enabled = is_enabled;
        return self;
    }

    pub fn visible(self: *InputBuilder, is_visible: bool) *InputBuilder {
        self.common.visible = is_visible;
        return self;
    }

    pub fn systemClipboard(self: *InputBuilder, prefer: bool) *InputBuilder {
        self.prefer_system_clipboard = prefer;
        return self;
    }

    pub fn build(self: *InputBuilder) !*InputField {
        var field = try InputField.init(self.allocator, self.max_len);
        if (self.placeholder.len > 0) try field.setPlaceholder(self.placeholder);
        if (self.initial.len > 0) field.setText(self.initial);
        field.setColors(self.fg, self.bg, self.focused_fg, self.focused_bg);
        field.disabled_fg = self.disabled_fg;
        field.disabled_bg = self.disabled_bg;
        field.style = self.style;
        if (self.on_change) |callback| {
            field.on_change = callback;
        }
        field.preferSystemClipboard(self.prefer_system_clipboard);
        self.common.apply(&field.widget);
        return field;
    }
};

/// Fluent builder for progress bars.
pub const ProgressBarBuilder = struct {
    allocator: std.mem.Allocator,
    progress: u8 = 0,
    direction: ProgressDirection = .horizontal,
    show_text: bool = true,
    fill_char: u21 = '█',
    fg: render.Color = render.Color.named(render.NamedColor.default),
    bg: render.Color = render.Color.named(render.NamedColor.default),
    fill: render.Color = render.Color.named(render.NamedColor.green),
    fill_bg: render.Color = render.Color.named(render.NamedColor.default),
    common: Common = .{},

    pub fn init(allocator: std.mem.Allocator) ProgressBarBuilder {
        return .{ .allocator = allocator };
    }

    pub fn percentage(self: *ProgressBarBuilder, percent: u8) *ProgressBarBuilder {
        self.progress = percent;
        return self;
    }

    pub fn colors(self: *ProgressBarBuilder, fg: render.Color, bg: render.Color, fill: render.Color, fill_bg: render.Color) *ProgressBarBuilder {
        self.fg = fg;
        self.bg = bg;
        self.fill = fill;
        self.fill_bg = fill_bg;
        return self;
    }

    pub fn flow(self: *ProgressBarBuilder, dir: ProgressDirection) *ProgressBarBuilder {
        self.direction = dir;
        return self;
    }

    pub fn id(self: *ProgressBarBuilder, value: []const u8) *ProgressBarBuilder {
        self.common.id = value;
        return self;
    }

    pub fn class(self: *ProgressBarBuilder, value: []const u8) *ProgressBarBuilder {
        self.common.class = value;
        return self;
    }

    pub fn enabled(self: *ProgressBarBuilder, value: bool) *ProgressBarBuilder {
        self.common.enabled = value;
        return self;
    }

    pub fn visible(self: *ProgressBarBuilder, value: bool) *ProgressBarBuilder {
        self.common.visible = value;
        return self;
    }

    pub fn showText(self: *ProgressBarBuilder, value: bool) *ProgressBarBuilder {
        self.show_text = value;
        return self;
    }

    pub fn fillChar(self: *ProgressBarBuilder, value: u21) *ProgressBarBuilder {
        self.fill_char = value;
        return self;
    }

    pub fn build(self: *ProgressBarBuilder) !*ProgressBar {
        var bar = try ProgressBar.init(self.allocator);
        bar.setProgress(self.progress);
        bar.direction = self.direction;
        bar.show_text = self.show_text;
        bar.fill_char = self.fill_char;
        bar.setColors(self.fg, self.bg, self.fill, self.fill_bg);
        self.common.apply(&bar.widget);
        return bar;
    }
};

test "button builder creates focused button with defaults and chaining" {
    const alloc = std.testing.allocator;
    const State = struct {
        var pressed = false;
    };
    const onPress = struct {
        fn run() void {
            State.pressed = true;
        }
    }.run;

    var builder = ButtonBuilder.init(alloc);
    var button = try builder.text("Launch").focusedColors(render.Color.named(.white), render.Color.named(.green)).onPress(onPress).build();
    defer button.deinit();

    try std.testing.expectEqualStrings("Launch", button.button_text);
    try std.testing.expect(button.widget.enabled);
    try std.testing.expect(button.on_press != null);
    State.pressed = false;
    button.on_press.?();
    try std.testing.expect(State.pressed);
}

test "label builder applies alignment and colors" {
    const alloc = std.testing.allocator;
    var builder = LabelBuilder.init(alloc);
    var label = try builder.content("Docs").alignTo(.center).colors(render.Color.named(.yellow), render.Color.named(.black)).build();
    defer label.deinit();

    try std.testing.expectEqual(render.NamedColor.yellow, label.fg.named_color);
    try std.testing.expectEqual(Label.TextAlignment.center, label.alignment);
}

test "input builder configures placeholder and limits" {
    const alloc = std.testing.allocator;
    const Capture = struct {
        var last: []const u8 = "";
    };
    const onChange = struct {
        fn run(new_value: []const u8) void {
            Capture.last = new_value;
        }
    }.run;

    var builder = InputBuilder.init(alloc);
    var field = try builder.withPlaceholder("Type").value("ok").maxLength(8).onChange(onChange).build();
    defer field.deinit();

    try std.testing.expectEqualStrings("Type", field.placeholder);
    try std.testing.expectEqual(@as(usize, 8), field.max_length);
    field.on_change.?(field.getText());
    try std.testing.expectEqualStrings("ok", Capture.last);
}

test "progress bar builder wires value and colors" {
    const alloc = std.testing.allocator;
    var builder = ProgressBarBuilder.init(alloc);
    var bar = try builder.percentage(42).colors(render.Color.named(.white), render.Color.named(.black), render.Color.named(.cyan), render.Color.named(.default)).build();
    defer bar.deinit();

    try std.testing.expectEqual(@as(u8, 42), bar.progress);
    try std.testing.expectEqual(render.NamedColor.cyan, bar.fill_fg.named_color);
}
