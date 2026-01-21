# Widget Guide

How to design and ship custom widgets that integrate with Zit’s rendering, layout, and event pipelines.

## The Widget Interface
The base `widget.Widget` holds state (rect, visibility, focus, optional focus ring, parent pointer) and a vtable:
```zig
pub const VTable = struct {
    draw: *const fn (widget: *anyopaque, renderer: *render.Renderer) anyerror!void,
    handle_event: *const fn (widget: *anyopaque, event: input.Event) anyerror!bool,
    layout: *const fn (widget: *anyopaque, rect: layout.Rect) anyerror!void,
    get_preferred_size: *const fn (widget: *anyopaque) anyerror!layout.Size,
    can_focus: *const fn (widget: *anyopaque) bool,
};
```
Use `Widget.init(&my_vtable)` in your struct and forward calls to your concrete implementation.

## Lifecycle
1. **init** – allocate your struct (usually from `MemoryManager.getWidgetPoolAllocator()`), set default colors/text, and set the vtable.
2. **layout** – store the provided `Rect` and compute any child positions or cached geometry.
3. **draw** – write glyphs/styles into the `render.Renderer` back buffer. Call `widget.drawFocusRing` if you support focus rings.
4. **handleEvent** – react to keys/mouse; return `true` if consumed. Respect `.handled` / `stop_propagation` on the event when appropriate.
5. **deinit** – free any heap-backed data you own and return the struct to the pool.

## Best Practices
- Keep layout pure: don’t mutate state other than geometry; cache expensive measurements.
- Use the arena for ephemeral buffers (measurements, composed strings) and the parent allocator for long-lived assets (text content, icon caches).
- Always check `visible`/`enabled` early in `handleEvent`; the base widget already guards but sibling helpers may call you directly.
- Prefer propagation-friendly handlers: let parents intercept in capturing (e.g., for focus management) and bubble up unhandled events.
- Call `Renderer.render()` once per frame; draw functions should only touch the back buffer.
- Surface IDs/classes via `setId`/`setClass` to integrate with theme helpers and logging.

## Animations and Transitions
- Use `widget.Animator` plus `animation.ValueDriver` to tween scalars like progress, slider positions, or opacity. Drivers call back on every frame so widgets can repaint without blocking.
- Widgets can now fade/slide on show/hide via `Widget.animateVisibility`; the base widget tints rendered cells during fade and shifts the rect during slides while ignoring input on the way out.
- `ProgressBar.attachAnimator` smooths value changes and `transitionFillColors` animates palette swaps, keeping updates visually fluid.

## Async Patterns
- `Application.tickOnce()`/`pollUntil()` let you pump events, animations, and timers from an external loop without sleeping the current thread.
- `Application.startBackgroundTask()` runs work on a helper thread and emits a `BACKGROUND_TASK_EVENT_ID` custom event carrying a `BackgroundTaskResult` (success/failed/cancelled). Use `cancelBackgroundTask()` to flip the shared stop flag and `releaseBackgroundTaskHandle()` once you no longer need the handle.
- Timers stay central for periodic updates: pair `scheduleTimer()` with `TimerManager` ticks to drive clock widgets or auto-refresh data.

## Accessibility and High Contrast
- The accessibility manager now includes ARIA-like roles (`progressbar`, `slider`, `tab*`, `alert`, `status`, `tooltip`), richer focus/state announcements, and a high contrast preference bit.
- Call `Manager.setHighContrast(true)` and `Manager.highContrastTheme()` to flip UI palettes for screen readers or low-vision users; `prefersHighContrast()` lets widgets opt into bolder styles.

## Styling and Theming
- Built-in palettes now include Solarized (light/dark), Monokai, and Catppuccin variants; resolve by name with `widget.theme.Theme.fromName("catppuccin")`.
- User themes can be loaded from simple config files (`background=#0a0e16`, `accent=#ff00aa`, `extends=dark`, `style.bold=true`) via `widget.theme.loadFromFile`; hook `theme_hot_reload.ThemeHotReloader.start` to hot-reload on file saves.
- The CSS helper (`widget.css.StyleSheet`) supports inheritance and pseudo-states: use `:hover`, `:focus`, `:active`, `:disabled` in selectors and pass parent styles into `resolveWithParent` to cascade fg/bg/style values.
- For depth and polish, `render.BoxStyle` accepts gradients and richer borders (`dashed`, `double_rounded`) and still works with drop shadows for layered panels.

## Example: A Minimal Counter Widget
```zig
const Counter = struct {
    widget: widget.Widget = widget.Widget.init(&vtable),
    value: i32 = 0,

    const vtable = widget.Widget.VTable{
        .draw = draw,
        .handle_event = handleEvent,
        .layout = layout,
        .get_preferred_size = preferred,
        .can_focus = canFocus,
    };

    fn layout(self: *Counter, rect: layout.Rect) !void {
        self.widget.rect = rect;
    }

    fn preferred(_: *Counter) !layout.Size {
        // Enough space for "Count: -9999"
        return layout.Size{ .width = 14, .height = 1 };
    }

    fn draw(self: *Counter, r: *render.Renderer) !void {
        var buf: [32]u8 = undefined;
        const text = try std.fmt.bufPrint(&buf, "Count: {d}", .{self.value});
        try r.drawStr(self.widget.rect.x, self.widget.rect.y, text, .{ .named_color = .bright_white }, .{ .named_color = .default }, render.Style{ .bold = true });
        self.widget.drawFocusRing(r);
    }

    fn handleEvent(self: *Counter, e: input.Event) !bool {
        switch (e) {
            .key => |key| {
                if (key.key == '+' or key.key == '=') { self.value += 1; return true; }
                if (key.key == '-' or key.key == '_') { self.value -= 1; return true; }
            },
            else => {},
        }
        return false;
    }

    fn canFocus(_: *Counter) bool {
        return true;
    }
};
```
**Usage**
```zig
var counter = try allocator.create(Counter);
counter.* = Counter{};
try counter.widget.layout(layout.Rect.init(2, 2, 16, 1));
// Hook into your event loop and renderer:
_ = try dispatcher.addEventListener(.key_press, struct {
    fn onKey(ev: *event.Event) bool {
        _ = counter.handleEvent(ev.data.key_press);
        return ev.handled;
    }
}.onKey, null);
try counter.widget.draw(&renderer);
```

Follow the same pattern to wrap more complex widgets: hold children, forward layout/draw to them, and use the event propagation helpers when you build widget trees.
