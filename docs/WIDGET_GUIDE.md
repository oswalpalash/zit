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
