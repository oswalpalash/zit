const std = @import("std");
const zit = @import("zit");
const render = zit.render;
const layout = zit.layout;
const widget = zit.widget;
const memory = zit.memory;
const form = widget.form;

fn enterAlternateScreen() !void {
    try std.fs.File.stdout().writeAll("\x1b[?1049h");
}

fn exitAlternateScreen() !void {
    try std.fs.File.stdout().writeAll("\x1b[?1049l");
}

const Action = enum { none, next, back, submit };
var pending_action: Action = .none;

fn requestNext() void {
    pending_action = .next;
}

fn requestBack() void {
    pending_action = .back;
}

fn requestSubmit() void {
    pending_action = .submit;
}

const StatusLine = struct {
    buffer: [200]u8 = undefined,
    text: []const u8 = "Fill the fields, Tab to move, Enter to advance, q quits",
};

fn setStatus(status: *StatusLine, comptime fmt: []const u8, args: anytype) void {
    status.text = std.fmt.bufPrint(&status.buffer, fmt, args) catch status.text;
}

fn applyFocus(chain: []const *widget.Widget, idx: usize) void {
    for (chain) |w| w.setFocus(false);
    if (chain.len > 0 and idx < chain.len) chain[idx].setFocus(true);
}

fn cycleFocus(chain: []const *widget.Widget, idx: *usize, forward: bool) void {
    if (chain.len == 0) return;
    const len = chain.len;
    const delta: usize = if (forward) 1 else len - 1;
    idx.* = (idx.* + delta) % len;
    applyFocus(chain, idx.*);
}

fn validateAccount(allocator: std.mem.Allocator, name: *widget.InputField, email: *widget.InputField, agree: *widget.Checkbox, status: *StatusLine) !bool {
    const rules_name = [_]form.Rule{
        form.required("Name is required"),
        form.minLength(2, "Name is too short"),
    };
    const rules_email = [_]form.Rule{
        form.required("Email is required"),
        form.contains("@", "Email must contain @"),
    };

    const fields = [_]form.Field{
        .{ .name = "name", .value = name.text[0..name.len], .rules = &rules_name },
        .{ .name = "email", .value = email.text[0..email.len], .rules = &rules_email },
    };

    var result = try form.validateForm(allocator, &fields);
    defer result.deinit();

    if (!result.isValid()) {
        if (result.firstError()) |err| {
            setStatus(status, "{s}: {s}", .{ err.field, err.message });
        }
        return false;
    }

    if (!agree.checked) {
        setStatus(status, "Please accept the terms to continue", .{});
        return false;
    }

    return true;
}

fn validatePreferences(newsletter: *widget.Checkbox, updates: *widget.ToggleSwitch, status: *StatusLine) bool {
    if (!newsletter.checked and !updates.on) {
        setStatus(status, "Choose at least one notification option", .{});
        return false;
    }
    return true;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var memory_manager = try memory.MemoryManager.init(allocator, 1024 * 512, 128);
    defer memory_manager.deinit();

    var term = try zit.terminal.init(memory_manager.getArenaAllocator());
    defer term.deinit() catch {};

    var renderer = try render.Renderer.init(memory_manager.getArenaAllocator(), term.width, term.height);
    defer renderer.deinit();

    var input_handler = zit.input.InputHandler.init(memory_manager.getArenaAllocator(), &term);

    try enterAlternateScreen();
    defer exitAlternateScreen() catch {};

    try term.enableRawMode();
    defer term.disableRawMode() catch {};

    try term.hideCursor();
    defer term.showCursor() catch {};

    try input_handler.enableMouse();
    defer input_handler.disableMouse() catch {};

    // Step indicator across the top.
    var stepper = try widget.WizardStepper.init(memory_manager.getWidgetPoolAllocator(), &[_][]const u8{ "Account", "Preferences" });
    defer stepper.deinit();

    // Step 1 fields.
    var name = try widget.InputField.init(memory_manager.getWidgetPoolAllocator(), 48);
    defer name.deinit();
    name.placeholder = "Your full name";
    name.widget.setFocus(true);

    var email = try widget.InputField.init(memory_manager.getWidgetPoolAllocator(), 64);
    defer email.deinit();
    email.placeholder = "you@example.com";

    var agree = try widget.Checkbox.init(memory_manager.getWidgetPoolAllocator(), "I agree to the terms");
    defer agree.deinit();

    var next_button = try widget.Button.init(memory_manager.getWidgetPoolAllocator(), "Next →");
    defer next_button.deinit();
    next_button.setOnPress(requestNext);

    // Step 2 fields.
    var newsletter = try widget.Checkbox.init(memory_manager.getWidgetPoolAllocator(), "Send me the weekly digest");
    defer newsletter.deinit();
    newsletter.checked = true;

    var updates = try widget.ToggleSwitch.init(memory_manager.getWidgetPoolAllocator(), "Product updates");
    defer updates.deinit();
    updates.set(true);

    var theme_choice = try widget.RadioGroup.init(memory_manager.getWidgetPoolAllocator(), &[_][]const u8{ "Dark", "Light", "High contrast" });
    defer theme_choice.deinit();

    var back_button = try widget.Button.init(memory_manager.getWidgetPoolAllocator(), "← Back");
    defer back_button.deinit();
    back_button.setOnPress(requestBack);

    var submit_button = try widget.Button.init(memory_manager.getWidgetPoolAllocator(), "Submit");
    defer submit_button.deinit();
    submit_button.setOnPress(requestSubmit);
    submit_button.setBorder(.double);

    var status = StatusLine{};

    var focus_index: usize = 0;
    var step: usize = 0;
    var running = true;

    while (running) {
        const focus_chain = if (step == 0)
            &[_]*widget.Widget{ &name.widget, &email.widget, &agree.widget, &next_button.widget }
        else
            &[_]*widget.Widget{ &newsletter.widget, &updates.widget, &theme_choice.widget, &back_button.widget, &submit_button.widget };

        applyFocus(focus_chain, focus_index);
        stepper.setStep(step);

        renderer.back.clear();
        renderer.fillRect(0, 0, renderer.back.width, renderer.back.height, ' ', render.Color.named(render.NamedColor.white), render.Color.named(render.NamedColor.black), render.Style{});

        renderer.drawSmartStr(1, 0, "Form wizard: Tab/Shift+Tab to move, Enter to advance, q quits", render.Color.named(render.NamedColor.bright_black), render.Color.named(render.NamedColor.black), render.Style{});
        renderer.drawBox(0, 0, renderer.back.width, renderer.back.height, render.BorderStyle.single, render.Color.named(render.NamedColor.bright_blue), render.Color.named(render.NamedColor.black), render.Style{});

        if (renderer.back.width > 8 and renderer.back.height > 6) {
            const form_rect = layout.Rect.init(2, 2, renderer.back.width - 4, renderer.back.height - 4);
            const stepper_rect = layout.Rect.init(form_rect.x + 1, form_rect.y + 1, form_rect.width - 2, 2);
            try stepper.widget.layout(stepper_rect);
            try stepper.widget.draw(&renderer);

            var cursor_y: u16 = stepper_rect.y + stepper_rect.height + 1;
            const field_width: u16 = if (form_rect.width > 6) form_rect.width - 4 else form_rect.width;

            if (step == 0) {
                renderer.drawStr(form_rect.x + 1, cursor_y, "Name", render.Color.named(render.NamedColor.cyan), render.Color.named(render.NamedColor.black), render.Style{ .bold = true });
                cursor_y += 1;
                try name.widget.layout(layout.Rect.init(form_rect.x + 1, cursor_y, field_width, 3));
                try name.widget.draw(&renderer);
                cursor_y += 4;

                renderer.drawStr(form_rect.x + 1, cursor_y, "Email", render.Color.named(render.NamedColor.cyan), render.Color.named(render.NamedColor.black), render.Style{ .bold = true });
                cursor_y += 1;
                try email.widget.layout(layout.Rect.init(form_rect.x + 1, cursor_y, field_width, 3));
                try email.widget.draw(&renderer);
                cursor_y += 4;

                renderer.drawStr(form_rect.x + 1, cursor_y, "Legal", render.Color.named(render.NamedColor.cyan), render.Color.named(render.NamedColor.black), render.Style{ .bold = true });
                cursor_y += 1;
                try agree.widget.layout(layout.Rect.init(form_rect.x + 2, cursor_y, field_width, 1));
                try agree.widget.draw(&renderer);
                cursor_y += 3;

                try next_button.widget.layout(layout.Rect.init(form_rect.x + form_rect.width - 14, cursor_y, 12, 3));
                try next_button.widget.draw(&renderer);
            } else {
                renderer.drawStr(form_rect.x + 1, cursor_y, "Notifications", render.Color.named(render.NamedColor.cyan), render.Color.named(render.NamedColor.black), render.Style{ .bold = true });
                cursor_y += 1;
                try newsletter.widget.layout(layout.Rect.init(form_rect.x + 2, cursor_y, field_width, 1));
                try newsletter.widget.draw(&renderer);
                cursor_y += 2;

                try updates.widget.layout(layout.Rect.init(form_rect.x + 2, cursor_y, field_width, 1));
                try updates.widget.draw(&renderer);
                cursor_y += 3;

                renderer.drawStr(form_rect.x + 1, cursor_y, "Theme", render.Color.named(render.NamedColor.cyan), render.Color.named(render.NamedColor.black), render.Style{ .bold = true });
                cursor_y += 1;
                try theme_choice.widget.layout(layout.Rect.init(form_rect.x + 2, cursor_y, field_width, 3));
                try theme_choice.widget.draw(&renderer);
                cursor_y += 4;

                try back_button.widget.layout(layout.Rect.init(form_rect.x + 1, cursor_y, 10, 3));
                try back_button.widget.draw(&renderer);
                try submit_button.widget.layout(layout.Rect.init(form_rect.x + form_rect.width - 14, cursor_y, 12, 3));
                try submit_button.widget.draw(&renderer);
            }
        }

        if (renderer.back.height > 0) {
            const status_y: u16 = renderer.back.height - 1;
            renderer.fillRect(0, status_y, renderer.back.width, 1, ' ', render.Color.named(render.NamedColor.black), render.Color.named(render.NamedColor.white), render.Style{});
            renderer.drawSmartStr(1, status_y, status.text, render.Color.named(render.NamedColor.black), render.Color.named(render.NamedColor.white), render.Style{});
        }

        try renderer.render();

        if (try input_handler.pollEvent(72)) |event| {
            switch (event) {
                .key => |key| {
                    if (key.key == 'q') {
                        running = false;
                        continue;
                    }

                    const forward = !(key.modifiers.shift);
                    if (key.key == '\t') {
                        cycleFocus(focus_chain, &focus_index, forward);
                        continue;
                    }

                    if (key.key == '\n' or key.key == zit.input.KeyCode.ENTER) {
                        pending_action = if (step == 0) .next else .submit;
                    }

                    // Allow keyboard to step indicator for demos.
                    _ = try stepper.widget.handleEvent(event);

                    if (step == 0) {
                        _ = try name.widget.handleEvent(event);
                        _ = try email.widget.handleEvent(event);
                        _ = try agree.widget.handleEvent(event);
                        _ = try next_button.widget.handleEvent(event);
                    } else {
                        _ = try newsletter.widget.handleEvent(event);
                        _ = try updates.widget.handleEvent(event);
                        _ = try theme_choice.widget.handleEvent(event);
                        _ = try back_button.widget.handleEvent(event);
                        _ = try submit_button.widget.handleEvent(event);
                    }
                },
                .mouse => |mouse| {
                    _ = try stepper.widget.handleEvent(event);
                    if (step == 0) {
                        _ = try name.widget.handleEvent(event);
                        _ = try email.widget.handleEvent(event);
                        _ = try agree.widget.handleEvent(event);
                        _ = try next_button.widget.handleEvent(event);
                    } else {
                        _ = try newsletter.widget.handleEvent(event);
                        _ = try updates.widget.handleEvent(event);
                        _ = try theme_choice.widget.handleEvent(event);
                        _ = try back_button.widget.handleEvent(event);
                        _ = try submit_button.widget.handleEvent(event);
                    }

                    if (mouse.button == 1 and mouse.action == .press) {
                        // Click selects nearest widget for focus cycling.
                        focus_index = 0;
                        applyFocus(focus_chain, focus_index);
                    }
                },
                .resize => |size| {
                    try renderer.resize(size.width, size.height);
                },
                else => {},
            }
        }

        switch (pending_action) {
            .next => {
                if (try validateAccount(memory_manager.getArenaAllocator(), name, email, agree, &status)) {
                    step = 1;
                    focus_index = 0;
                    setStatus(&status, "Account info looks good. Preferences next.", .{});
                }
                pending_action = .none;
            },
            .back => {
                if (step > 0) {
                    step = 0;
                    focus_index = 0;
                    setStatus(&status, "Back to account details", .{});
                }
                pending_action = .none;
            },
            .submit => {
                if (try validateAccount(memory_manager.getArenaAllocator(), name, email, agree, &status) and validatePreferences(newsletter, updates, &status)) {
                    var summary: [160]u8 = undefined;
                    const theme_label = theme_choice.options.items[theme_choice.selected];
                    const msg = std.fmt.bufPrint(&summary, "Saved! User {s} ({s}), updates: {s}/{s}, theme: {s}", .{
                        name.text[0..name.len],
                        email.text[0..email.len],
                        if (newsletter.checked) "newsletter" else "no-news",
                        if (updates.on) "product" else "mute",
                        theme_label,
                    }) catch summary[0..0];
                    setStatus(&status, "{s}", .{msg});
                    step = 0;
                    focus_index = 0;
                    pending_action = .none;
                } else {
                    pending_action = .none;
                }
            },
            .none => {},
        }
    }

    try term.clear();
    try term.moveCursor(0, 0);
}
