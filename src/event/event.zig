const std = @import("std");
const input = @import("../input/input.zig");
pub const widget = @import("../widget/widget.zig");
const animation = @import("../widget/animation.zig");
const timer = @import("timer.zig");
const accessibility = @import("../widget/accessibility.zig");
const render = @import("../render/render.zig");
const layout = @import("../layout/layout.zig");
const memory = @import("../memory/memory.zig");
const compat = @import("../compat.zig");

const event_loop_sleep_ms: u64 = 10;
const focus_history_limit: usize = 10;

/// Event system module
///
/// This module provides functionality for event handling and propagation:
/// - Event types and data structures
/// - Event dispatching and bubbling
/// - Event listeners and callbacks
/// Event type enumeration
pub const EventType = enum {
    /// Key press event
    key_press,
    /// Key release event
    key_release,
    /// Mouse press event
    mouse_press,
    /// Mouse release event
    mouse_release,
    /// Mouse move event
    mouse_move,
    /// Mouse wheel event
    mouse_wheel,
    /// Dragging started
    drag_start,
    /// Drag position updated
    drag_update,
    /// Drag ended
    drag_end,
    /// Drop event
    drop,
    /// Window resize event
    resize,
    /// Focus change event
    focus_change,
    /// Custom application event
    custom,
};

/// Event data structure
pub const Event = struct {
    /// Event type
    type: EventType,
    /// Event target (widget that generated the event)
    target: ?*widget.Widget = null,
    /// Event timestamp
    timestamp: i64,
    /// Whether the event was handled
    handled: bool = false,
    /// Event propagation phase
    phase: PropagationPhase = .bubbling,
    /// Whether propagation should stop
    stop_propagation: bool = false,
    /// Node currently processing the event during propagation
    current_target: ?*widget.Widget = null,
    /// Event data
    data: EventData,

    /// Event propagation phases
    pub const PropagationPhase = enum {
        /// Capturing phase (top-down)
        capturing,
        /// Target phase (at the target)
        target,
        /// Bubbling phase (bottom-up)
        bubbling,
    };

    /// Event data union
    pub const EventData = union(EventType) {
        /// Key press event data
        key_press: KeyEventData,
        /// Key release event data
        key_release: KeyEventData,
        /// Mouse press event data
        mouse_press: MouseEventData,
        /// Mouse release event data
        mouse_release: MouseEventData,
        /// Mouse move event data
        mouse_move: MouseEventData,
        /// Mouse wheel event data
        mouse_wheel: MouseWheelEventData,
        /// Dragging start
        drag_start: DragEventData,
        /// Dragging updates
        drag_update: DragEventData,
        /// Dragging end
        drag_end: DragEventData,
        /// Drop payload
        drop: DragEventData,
        /// Window resize event data
        resize: ResizeEventData,
        /// Focus change event data
        focus_change: FocusEventData,
        /// Custom application event data
        custom: CustomEventData,
    };

    /// Create a new event
    pub fn init(event_type: EventType, target: ?*widget.Widget, data: EventData) Event {
        return Event{
            .type = event_type,
            .target = target,
            .current_target = target,
            .timestamp = compat.nowMillis(),
            .data = data,
        };
    }

    /// Mark the event as handled
    pub fn markHandled(self: *Event) void {
        self.handled = true;
    }

    /// Stop event propagation
    pub fn stopPropagation(self: *Event) void {
        self.stop_propagation = true;
    }

    /// Set the propagation phase
    pub fn setPhase(self: *Event, phase: PropagationPhase) void {
        self.phase = phase;
    }

    /// Update the current target while keeping the original target intact.
    pub fn setCurrentTarget(self: *Event, target: ?*widget.Widget) void {
        self.current_target = target;
    }
};

pub fn fromInputEvent(ie: input.Event, target: ?*widget.Widget) Event {
    return switch (ie) {
        .key => |key_event| Event.init(.key_press, target, .{ .key_press = .{
            .key = key_event.key,
            .modifiers = key_event.modifiers,
            .raw = 0,
        } }),
        .mouse => |mouse_event| switch (mouse_event.action) {
            .press => Event.init(.mouse_press, target, .{ .mouse_press = .{
                .x = mouse_event.x,
                .y = mouse_event.y,
                .button = mouse_event.button,
                .clicks = 1,
                .modifiers = .{},
            } }),
            .release => Event.init(.mouse_release, target, .{ .mouse_release = .{
                .x = mouse_event.x,
                .y = mouse_event.y,
                .button = mouse_event.button,
                .clicks = 1,
                .modifiers = .{},
            } }),
            .move => Event.init(.mouse_move, target, .{ .mouse_move = .{
                .x = mouse_event.x,
                .y = mouse_event.y,
                .button = mouse_event.button,
                .clicks = 0,
                .modifiers = .{},
            } }),
            .scroll_up, .scroll_down => {
                const clamped = std.math.clamp(mouse_event.scroll_delta, @as(i16, -127), @as(i16, 127));
                const dy: i8 = @intCast(clamped);
                return Event.init(.mouse_wheel, target, .{ .mouse_wheel = .{
                    .x = mouse_event.x,
                    .y = mouse_event.y,
                    .dx = 0,
                    .dy = dy,
                    .modifiers = .{},
                } });
            },
        },
        .resize => |resize_event| Event.init(.resize, target, .{ .resize = .{
            .width = resize_event.width,
            .height = resize_event.height,
        } }),
        .unknown => Event.init(.custom, target, .{ .custom = .{
            .id = 0,
            .data = null,
            .destructor = null,
            .type_name = "input.unknown",
            .filter_fn = null,
        } }),
    };
}

/// Key event data
pub const KeyEventData = struct {
    /// Key code (unicode scalar or special key identifier)
    key: u21,
    /// Key modifiers
    modifiers: input.KeyModifiers,
    /// Raw key value
    raw: u32,
};

/// Mouse event data
pub const MouseEventData = struct {
    /// Mouse x coordinate
    x: u16,
    /// Mouse y coordinate
    y: u16,
    /// Mouse button (1 = left, 2 = middle, 3 = right)
    button: u8,
    /// Number of clicks (1 = single click, 2 = double click)
    clicks: u8,
    /// Key modifiers
    modifiers: input.KeyModifiers,
};

/// Mouse wheel event data
pub const MouseWheelEventData = struct {
    /// Mouse x coordinate
    x: u16,
    /// Mouse y coordinate
    y: u16,
    /// Horizontal scroll amount
    dx: i8,
    /// Vertical scroll amount
    dy: i8,
    /// Key modifiers
    modifiers: input.KeyModifiers,
};

/// Drag payload used for drop handlers.
///
/// The payload can carry a widget reference, a borrowed/owned string, or a custom
/// typed value allocated on the heap. Helper constructors cover the common cases
/// so handlers can remain type-safe without manual casting.
pub const DragPayload = struct {
    kind: Kind = .none,
    storage: Storage = .{ .none = {} },

    pub const Kind = enum { none, widget, text, custom };

    pub const Storage = union(Kind) {
        none: void,
        widget: *widget.Widget,
        text: Text,
        custom: Custom,
    };

    pub const Text = struct {
        bytes: []const u8 = "",
        allocator: ?std.mem.Allocator = null,

        fn deinit(self: Text) void {
            if (self.allocator) |alloc| {
                alloc.free(self.bytes);
            }
        }
    };

    pub const Custom = struct {
        ptr: ?*anyopaque = null,
        destructor: ?*const fn (*anyopaque) void = null,
        type_name: ?[]const u8 = null,
    };

    /// Borrow an existing widget reference.
    pub fn fromWidget(widget_ptr: *widget.Widget) DragPayload {
        return .{ .kind = .widget, .storage = .{ .widget = widget_ptr } };
    }

    /// Borrow a UTF-8 string slice. The caller owns the backing memory.
    pub fn fromText(text: []const u8) DragPayload {
        return .{ .kind = .text, .storage = .{ .text = .{ .bytes = text } } };
    }

    /// Copy text into an owned buffer so the payload can outlive the source slice.
    pub fn copyText(allocator: std.mem.Allocator, text: []const u8) !DragPayload {
        const buf = try allocator.dupe(u8, text);
        return .{ .kind = .text, .storage = .{ .text = .{ .bytes = buf, .allocator = allocator } } };
    }

    /// Wrap an opaque pointer with an optional destructor. Useful for interop.
    pub fn fromOpaque(ptr: *anyopaque, destructor: ?*const fn (*anyopaque) void, type_name: ?[]const u8) DragPayload {
        return .{ .kind = .custom, .storage = .{ .custom = .{ .ptr = ptr, .destructor = destructor, .type_name = type_name } } };
    }

    fn ValueBox(comptime T: type) type {
        return struct {
            allocator: std.mem.Allocator,
            value: T,
        };
    }

    /// Allocate and copy an arbitrary value onto the heap for the duration of the drag.
    pub fn fromValue(allocator: std.mem.Allocator, value: anytype) !DragPayload {
        const T = @TypeOf(value);
        const Box = ValueBox(T);
        const box = try allocator.create(Box);
        box.* = .{ .allocator = allocator, .value = value };

        return .{
            .kind = .custom,
            .storage = .{ .custom = .{
                .ptr = &box.value,
                .destructor = destroyValue(Box),
                .type_name = @typeName(T),
            } },
        };
    }

    fn destroyValue(comptime BoxT: type) *const fn (*anyopaque) void {
        return struct {
            fn destroy(raw: *anyopaque) void {
                const ValueType = @FieldType(BoxT, "value");
                const value_ptr = @as(*ValueType, @ptrCast(@alignCast(raw)));
                const box_ptr = @as(*BoxT, @fieldParentPtr("value", value_ptr));
                box_ptr.allocator.destroy(box_ptr);
            }
        }.destroy;
    }

    /// Attempt to extract a widget reference.
    pub fn asWidget(self: DragPayload) ?*widget.Widget {
        return if (self.kind == .widget) self.storage.widget else null;
    }

    /// Attempt to extract text stored in the payload.
    pub fn asText(self: DragPayload) ?[]const u8 {
        return if (self.kind == .text) self.storage.text.bytes else null;
    }

    /// Attempt to view the payload as a typed value allocated via `fromValue`.
    pub fn asValue(self: DragPayload, comptime T: type) ?*const T {
        if (self.kind != .custom) return null;
        const ptr = self.storage.custom.ptr orelse return null;
        return @as(*const T, @ptrCast(@alignCast(ptr)));
    }

    /// Release any owned memory associated with the payload.
    pub fn deinit(self: *DragPayload) void {
        switch (self.kind) {
            .text => self.storage.text.deinit(),
            .custom => {
                if (self.storage.custom.destructor) |d| {
                    if (self.storage.custom.ptr) |p| {
                        d(p);
                    }
                }
            },
            else => {},
        }

        self.* = .{};
    }
};

/// Dragging lifecycle data.
pub const DragEventData = struct {
    start_x: u16,
    start_y: u16,
    x: u16,
    y: u16,
    button: u8,
    source: ?*widget.Widget,
    payload: DragPayload = .{},
    accepted: bool = true,
};

/// Resize event data
pub const ResizeEventData = struct {
    /// New width
    width: u16,
    /// New height
    height: u16,
};

/// Focus event data
pub const FocusEventData = struct {
    /// Whether the widget gained focus (true) or lost focus (false)
    gained: bool,
    /// Previous focused widget
    previous: ?*widget.Widget,
};

/// Custom event data
pub const CustomEventData = struct {
    /// Event ID
    id: u32,
    /// Event data pointer
    data: ?*anyopaque,
    /// Data destructor function
    destructor: ?*const fn (data: *anyopaque) void,
    /// Custom event type name
    type_name: ?[]const u8 = null,
    /// Custom event filter function
    filter_fn: ?*const fn (data: ?*anyopaque) bool = null,
};

/// Background task lifecycle notification constants.
pub const BACKGROUND_TASK_EVENT_ID = 0x42544752; // "BTGR"
pub const BackgroundTaskStatus = enum { success, failed, cancelled };
pub const BackgroundTaskResult = struct {
    status: BackgroundTaskStatus,
    message: []const u8 = "",
    allocator: std.mem.Allocator,
};

fn destroyBackgroundTaskResult(data: *anyopaque) void {
    const res = @as(*BackgroundTaskResult, @ptrCast(@alignCast(data)));
    if (res.message.len > 0) res.allocator.free(res.message);
    res.allocator.destroy(res);
}

fn createBackgroundTaskResult(allocator: std.mem.Allocator, status: BackgroundTaskStatus, owned_message: []const u8) !*BackgroundTaskResult {
    const result = allocator.create(BackgroundTaskResult) catch |err| {
        if (owned_message.len > 0) allocator.free(owned_message);
        return err;
    };
    result.* = .{ .status = status, .message = owned_message, .allocator = allocator };
    return result;
}

fn enqueueBackgroundTaskResult(queue: *EventQueue, allocator: std.mem.Allocator, status: BackgroundTaskStatus, owned_message: []const u8, target: ?*widget.Widget) bool {
    const result = createBackgroundTaskResult(allocator, status, owned_message) catch return false;
    queue.createCustomEvent(BACKGROUND_TASK_EVENT_ID, @ptrCast(result), destroyBackgroundTaskResult, target) catch {
        destroyBackgroundTaskResult(@ptrCast(result));
        return false;
    };
    return true;
}

/// Invoke work on a separate thread and monitor for cancellation.
pub const BackgroundTaskFn = *const fn (stop_flag: *std.atomic.Value(bool), ctx: ?*anyopaque) anyerror!void;

const BackgroundTask = struct {
    flag: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    completed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    released: bool = false,
    thread: ?std.Thread = null,
};

pub const BackgroundTaskHandle = struct {
    flag: *std.atomic.Value(bool),
    task: ?*anyopaque = null,
};

/// Event listener function type
pub const EventListenerFn = *const fn (event: *Event) bool;

/// Event listener structure
pub const EventListener = struct {
    /// Event type to listen for
    event_type: EventType,
    /// Listener function
    listener: EventListenerFn,
    /// User data
    user_data: ?*anyopaque,
    /// Listener ID
    id: u32,
};

pub const EventTraceFn = *const fn (event: *Event, phase: Event.PropagationPhase, node: ?*widget.Widget, handled: bool, ctx: ?*anyopaque) void;

pub const DebugHooks = struct {
    event_trace: ?EventTraceFn = null,
    trace_ctx: ?*anyopaque = null,
};

pub inline fn traceEvent(hooks: DebugHooks, ev: *Event, phase: Event.PropagationPhase, node: ?*widget.Widget) void {
    if (hooks.event_trace) |trace_fn| {
        trace_fn(ev, phase, node, ev.handled, hooks.trace_ctx);
    }
}

/// Optional hook executed before an event is dispatched. Return true to consume it.
pub const EventPreprocessorFn = *const fn (event: *Event, ctx: ?*anyopaque) bool;

pub const EventPreprocessor = struct {
    handler: EventPreprocessorFn,
    ctx: ?*anyopaque = null,
};

/// Event dispatcher for managing event listeners and dispatching events
pub const EventDispatcher = struct {
    /// Event listeners
    listeners: std.ArrayList(EventListener),
    /// Next listener ID
    next_id: u32 = 1,
    /// Allocator for event dispatcher operations
    allocator: std.mem.Allocator,

    /// Initialize a new event dispatcher
    pub fn init(allocator: std.mem.Allocator) EventDispatcher {
        return EventDispatcher{
            .listeners = std.ArrayList(EventListener).empty,
            .allocator = allocator,
        };
    }

    /// Clean up event dispatcher resources
    pub fn deinit(self: *EventDispatcher) void {
        self.listeners.deinit(self.allocator);
    }

    /// Add an event listener
    pub fn addEventListener(self: *EventDispatcher, event_type: EventType, listener: EventListenerFn, user_data: ?*anyopaque) !u32 {
        const id = self.next_id;

        try self.listeners.append(self.allocator, EventListener{
            .event_type = event_type,
            .listener = listener,
            .user_data = user_data,
            .id = id,
        });

        self.next_id += 1;
        return id;
    }

    /// Remove an event listener by ID
    pub fn removeEventListener(self: *EventDispatcher, id: u32) bool {
        for (self.listeners.items, 0..) |listener, i| {
            if (listener.id == id) {
                _ = self.listeners.orderedRemove(i);
                return true;
            }
        }

        return false;
    }

    /// Dispatch an event to all registered listeners
    pub fn dispatchEvent(self: *EventDispatcher, event: *Event) bool {
        if (event.current_target == null) {
            event.setCurrentTarget(event.target);
        }
        var handled = false;

        // Iterate through listeners in reverse order (newest first)
        var i: usize = self.listeners.items.len;
        while (i > 0) {
            i -= 1;
            const listener = self.listeners.items[i];

            // Check if this listener is interested in this event type
            if (listener.event_type == event.type) {
                // For custom events, check filter if available
                if (event.type == .custom and event.data.custom.filter_fn != null) {
                    if (!event.data.custom.filter_fn.?(event.data.custom.data)) {
                        continue;
                    }
                }

                // Call the listener
                if (listener.listener(event)) {
                    handled = true;
                    event.handled = true;
                    if (event.current_target) |target| {
                        target.markDirty();
                    }
                }

                // Stop if the event was handled or propagation was stopped
                if (event.handled or event.stop_propagation) {
                    break;
                }
            }
        }

        return handled;
    }

    /// Dispatch an event with both capturing and bubbling phases
    pub fn dispatchEventWithPropagation(self: *EventDispatcher, event: *Event, widget_path: []*widget.Widget, hooks: DebugHooks) bool {
        event.setCurrentTarget(null);
        if (event.target == null and widget_path.len > 0) {
            event.target = widget_path[widget_path.len - 1];
        }
        const original_target = event.target;
        var handled = false;

        // Capturing phase (top-down)
        event.setPhase(.capturing);
        if (widget_path.len > 1) {
            var i: usize = 0;
            while (i + 1 < widget_path.len) {
                const node = widget_path[i];
                event.setCurrentTarget(node);
                if (self.dispatchEvent(event)) {
                    handled = true;
                }

                traceEvent(hooks, event, .capturing, node);
                if (event.stop_propagation) {
                    return handled;
                }
                i += 1;
            }
        }

        // Target phase
        if (original_target != null) {
            event.setPhase(.target);
            event.setCurrentTarget(original_target);
            if (self.dispatchEvent(event)) {
                handled = true;
            }

            traceEvent(hooks, event, .target, original_target);
            if (event.stop_propagation) {
                return handled;
            }
        }

        // Bubbling phase (bottom-up, excluding the target)
        event.setPhase(.bubbling);
        if (widget_path.len > 1) {
            var i: usize = widget_path.len - 1;
            while (i > 0) {
                i -= 1;
                const node = widget_path[i];
                if (node == original_target) continue;
                event.setCurrentTarget(node);
                if (self.dispatchEvent(event)) {
                    handled = true;
                }

                traceEvent(hooks, event, .bubbling, node);
                if (event.stop_propagation) {
                    break;
                }
            }
        }

        return handled;
    }
};

/// Event queue for storing and processing events
pub const EventQueue = struct {
    /// Event queue
    queue: std.ArrayList(Event),
    head: usize = 0,
    lock: compat.Mutex = .{},
    /// Event dispatcher
    dispatcher: EventDispatcher,
    /// Allocator for event queue operations
    allocator: std.mem.Allocator,
    /// Optional debug hooks
    debug_hooks: DebugHooks = .{},
    /// Reusable buffer for propagation paths to avoid per-event allocations
    path_scratch: std.ArrayListUnmanaged(*widget.Widget) = .empty,
    /// Optional pre-dispatch hook (shortcuts, global handlers, etc.)
    preprocessor: ?EventPreprocessor = null,

    /// Initialize a new event queue
    pub fn init(allocator: std.mem.Allocator) EventQueue {
        return EventQueue{
            .queue = std.ArrayList(Event).empty,
            .dispatcher = EventDispatcher.init(allocator),
            .allocator = allocator,
        };
    }

    /// Clean up event queue resources
    pub fn deinit(self: *EventQueue) void {
        self.destroyQueuedCustomPayloads();
        self.queue.deinit(self.allocator);
        self.path_scratch.deinit(self.allocator);
        self.dispatcher.deinit();
    }

    /// Attach or clear a pre-dispatch hook.
    pub fn setPreprocessor(self: *EventQueue, pre: ?EventPreprocessor) void {
        self.preprocessor = pre;
    }

    /// Run the configured preprocessor, if any.
    pub fn preprocess(self: *EventQueue, ev: *Event) bool {
        if (self.preprocessor) |pre| {
            return pre.handler(ev, pre.ctx);
        }
        return false;
    }

    fn recycle(self: *EventQueue) void {
        self.queue.clearRetainingCapacity();
        self.head = 0;
    }

    pub fn destroyCustomPayload(event_item: *const Event) void {
        if (event_item.type != .custom) return;
        const custom_data = event_item.data.custom;
        if (custom_data.destructor != null and custom_data.data != null) {
            custom_data.destructor.?(custom_data.data.?);
        }
    }

    fn destroyQueuedCustomPayloads(self: *EventQueue) void {
        self.lock.lock();
        defer self.lock.unlock();

        if (self.head < self.queue.items.len) {
            for (self.queue.items[self.head..]) |*event_item| {
                destroyCustomPayload(event_item);
            }
        }
        self.recycle();
    }

    pub fn popFront(self: *EventQueue) ?Event {
        self.lock.lock();
        defer self.lock.unlock();
        if (self.head >= self.queue.items.len) return null;
        const ev = self.queue.items[self.head];
        self.head += 1;
        if (self.head >= self.queue.items.len) self.recycle();
        return ev;
    }

    /// Push an event to the queue
    pub fn pushEvent(self: *EventQueue, event: Event) !void {
        self.lock.lock();
        defer self.lock.unlock();
        try self.queue.append(self.allocator, event);
    }

    /// Process all events in the queue
    pub fn processEvents(self: *EventQueue) !void {
        // Use standard dispatch (no propagation)
        while (self.popFront()) |event_val| {
            var event = event_val;
            if (self.preprocess(&event)) {
                destroyCustomPayload(&event);
                continue;
            }
            _ = self.dispatcher.dispatchEvent(&event);
            event.setPhase(.target);
            traceEvent(self.debug_hooks, &event, .target, event.target);

            // Clean up custom event data if needed
            destroyCustomPayload(&event);
        }
    }

    /// Process all events in the queue with propagation
    pub fn processEventsWithPropagation(self: *EventQueue, allocator: std.mem.Allocator) !void {
        const propagation = @import("propagation.zig");
        try propagation.processEventsWithPropagation(self, allocator, &self.path_scratch);
    }

    /// Attach debug hooks to observe event flow.
    pub fn setDebugHooks(self: *EventQueue, hooks: DebugHooks) void {
        self.debug_hooks = hooks;
    }

    /// Add an event listener
    pub fn addEventListener(self: *EventQueue, event_type: EventType, listener: EventListenerFn, user_data: ?*anyopaque) !u32 {
        return try self.dispatcher.addEventListener(event_type, listener, user_data);
    }

    /// Remove an event listener by ID
    pub fn removeEventListener(self: *EventQueue, id: u32) bool {
        return self.dispatcher.removeEventListener(id);
    }

    /// Create a key press event
    pub fn createKeyPressEvent(self: *EventQueue, key: u21, modifiers: input.KeyModifiers, raw: u32, target: ?*widget.Widget) !void {
        const event = Event.init(.key_press, target, Event.EventData{
            .key_press = KeyEventData{
                .key = key,
                .modifiers = modifiers,
                .raw = raw,
            },
        });

        try self.pushEvent(event);
    }

    /// Create a key release event
    pub fn createKeyReleaseEvent(self: *EventQueue, key: u21, modifiers: input.KeyModifiers, raw: u32, target: ?*widget.Widget) !void {
        const event = Event.init(.key_release, target, Event.EventData{
            .key_release = KeyEventData{
                .key = key,
                .modifiers = modifiers,
                .raw = raw,
            },
        });

        try self.pushEvent(event);
    }

    /// Create a mouse press event
    pub fn createMousePressEvent(self: *EventQueue, x: u16, y: u16, button: u8, clicks: u8, modifiers: input.KeyModifiers, target: ?*widget.Widget) !void {
        const event = Event.init(.mouse_press, target, Event.EventData{
            .mouse_press = MouseEventData{
                .x = x,
                .y = y,
                .button = button,
                .clicks = clicks,
                .modifiers = modifiers,
            },
        });

        try self.pushEvent(event);
    }

    /// Create a mouse release event
    pub fn createMouseReleaseEvent(self: *EventQueue, x: u16, y: u16, button: u8, clicks: u8, modifiers: input.KeyModifiers, target: ?*widget.Widget) !void {
        const event = Event.init(.mouse_release, target, Event.EventData{
            .mouse_release = MouseEventData{
                .x = x,
                .y = y,
                .button = button,
                .clicks = clicks,
                .modifiers = modifiers,
            },
        });

        try self.pushEvent(event);
    }

    /// Create a mouse move event
    pub fn createMouseMoveEvent(self: *EventQueue, x: u16, y: u16, button: u8, modifiers: input.KeyModifiers, target: ?*widget.Widget) !void {
        const event = Event.init(.mouse_move, target, Event.EventData{
            .mouse_move = MouseEventData{
                .x = x,
                .y = y,
                .button = button,
                .clicks = 0,
                .modifiers = modifiers,
            },
        });

        try self.pushEvent(event);
    }

    /// Create a mouse wheel event
    pub fn createMouseWheelEvent(self: *EventQueue, x: u16, y: u16, dx: i8, dy: i8, modifiers: input.KeyModifiers, target: ?*widget.Widget) !void {
        const event = Event.init(.mouse_wheel, target, Event.EventData{
            .mouse_wheel = MouseWheelEventData{
                .x = x,
                .y = y,
                .dx = dx,
                .dy = dy,
                .modifiers = modifiers,
            },
        });

        try self.pushEvent(event);
    }

    pub fn createDragEvent(self: *EventQueue, event_type: EventType, data: DragEventData, target: ?*widget.Widget) !void {
        const payload = switch (event_type) {
            .drag_start => Event.EventData{ .drag_start = data },
            .drag_update => Event.EventData{ .drag_update = data },
            .drag_end => Event.EventData{ .drag_end = data },
            .drop => Event.EventData{ .drop = data },
            else => return error.InvalidDragEventType,
        };

        const event = Event.init(event_type, target, payload);
        try self.pushEvent(event);
    }

    /// Create a resize event
    pub fn createResizeEvent(self: *EventQueue, width: u16, height: u16, target: ?*widget.Widget) !void {
        const event = Event.init(.resize, target, Event.EventData{
            .resize = ResizeEventData{
                .width = width,
                .height = height,
            },
        });

        try self.pushEvent(event);
    }

    /// Create a focus change event
    pub fn createFocusChangeEvent(self: *EventQueue, gained: bool, previous: ?*widget.Widget, target: ?*widget.Widget) !void {
        const event = Event.init(.focus_change, target, Event.EventData{
            .focus_change = FocusEventData{
                .gained = gained,
                .previous = previous,
            },
        });

        try self.pushEvent(event);
    }

    /// Create a custom event
    pub fn createCustomEvent(self: *EventQueue, id: u32, data: ?*anyopaque, destructor: ?*const fn (data: *anyopaque) void, target: ?*widget.Widget) !void {
        const event = Event.init(.custom, target, Event.EventData{
            .custom = CustomEventData{
                .id = id,
                .data = data,
                .destructor = destructor,
            },
        });

        try self.pushEvent(event);
    }

    /// Create a custom event with type name and filter
    pub fn createCustomEventWithFilter(self: *EventQueue, id: u32, data: ?*anyopaque, destructor: ?*const fn (data: *anyopaque) void, type_name: ?[]const u8, filter_fn: ?*const fn (data: ?*anyopaque) bool, target: ?*widget.Widget) !void {
        const event = Event.init(.custom, target, Event.EventData{
            .custom = CustomEventData{
                .id = id,
                .data = data,
                .destructor = destructor,
                .type_name = type_name,
                .filter_fn = filter_fn,
            },
        });

        try self.pushEvent(event);
    }

    /// Process events asynchronously (using callbacks since async/await is not fully implemented)
    pub fn processEventsAsync(self: *EventQueue, callback: ?*const fn () void) !void {
        try self.processEvents();
        if (callback != null) {
            callback.?();
        }
    }

    /// Wait for a specific event condition
    pub fn waitForEvent(self: *EventQueue, condition: *const fn (*Event) bool, callback: ?*const fn (Event) void) !void {
        {
            self.lock.lock();
            defer self.lock.unlock();
            // Check current queue for matching event
            for (self.queue.items[self.head..]) |*event| {
                if (condition(event)) {
                    if (callback != null) {
                        callback.?(event.*);
                    }
                    return;
                }
            }
        }

        // Process events and check again
        try self.processEvents();
    }
};

/// Focus management system
pub const FocusManager = struct {
    /// Currently focused widget
    focused_widget: ?*widget.Widget,
    /// Focus history stack
    focus_history: std.ArrayList(*widget.Widget),
    /// Ordered list of focusable widgets for traversal
    focus_chain: std.ArrayList(*widget.Widget),
    /// Event queue reference
    event_queue: *EventQueue,
    /// Allocator
    allocator: std.mem.Allocator,
    /// Whether focus stealing is allowed
    allow_focus_stealing: bool = false,
    /// Accessibility manager (optional)
    accessibility: ?*accessibility.Manager = null,

    /// Initialize a new focus manager
    pub fn init(allocator: std.mem.Allocator, event_queue: *EventQueue) FocusManager {
        return FocusManager{
            .focused_widget = null,
            .focus_history = std.ArrayList(*widget.Widget).empty,
            .focus_chain = std.ArrayList(*widget.Widget).empty,
            .event_queue = event_queue,
            .allocator = allocator,
            .accessibility = null,
        };
    }

    /// Clean up focus manager resources
    pub fn deinit(self: *FocusManager) void {
        self.focus_history.deinit(self.allocator);
        self.focus_chain.deinit(self.allocator);
    }

    /// Request focus for a widget
    pub fn requestFocus(self: *FocusManager, target_widget: *widget.Widget) !bool {
        if (!target_widget.canFocus()) {
            return false;
        }
        try self.ensureTracked(target_widget);
        // Check if focus stealing is allowed
        if (!self.allow_focus_stealing and self.focused_widget != null) {
            // Ask current widget if it's willing to give up focus
            var focus_data = FocusRequestData{
                .requesting_widget = target_widget,
                .current_widget = self.focused_widget.?,
                .allow = true,
            };

            try self.event_queue.createCustomEventWithFilter(FOCUS_REQUEST_EVENT_ID, @ptrCast(&focus_data), null, "focus_request", null, self.focused_widget);

            // Process events to handle the focus request
            try self.event_queue.processEvents();

            // Check if focus change was allowed
            if (!focus_data.allow) {
                return false;
            }
        }

        const previous = self.focused_widget;
        const focus_event_count: usize = if (previous != null) 2 else 1;
        try self.focus_history.ensureUnusedCapacity(self.allocator, 1);
        try self.event_queue.queue.ensureUnusedCapacity(self.event_queue.allocator, focus_event_count);

        // Set new focus
        self.focused_widget = target_widget;
        if (previous) |prev| {
            prev.setFocus(false);
        }
        target_widget.setFocus(true);

        // Add to focus history
        self.focus_history.appendAssumeCapacity(target_widget);
        if (self.focus_history.items.len > focus_history_limit) {
            _ = self.focus_history.orderedRemove(0);
        }

        if (self.accessibility) |acc| {
            acc.announceFocusBestEffort(target_widget);
        }

        // Send focus change events
        if (previous != null) {
            try self.event_queue.createFocusChangeEvent(false, null, previous);
        }
        try self.event_queue.createFocusChangeEvent(true, previous, target_widget);

        return true;
    }

    /// Focus previous widget in history
    pub fn focusPrevious(self: *FocusManager) !bool {
        if (self.focus_history.items.len >= 2) {
            _ = self.focus_history.pop();
            while (self.focus_history.items.len > 0) {
                const previous = self.focus_history.getLast();
                if (previous.canFocus()) {
                    return try self.requestFocus(previous);
                }
                _ = self.focus_history.pop();
            }
        }

        return try self.focusPreviousInChain();
    }

    /// Register a widget as focusable for traversal order.
    pub fn registerFocusable(self: *FocusManager, target_widget: *widget.Widget) !void {
        if (!target_widget.canFocus()) return;
        try self.ensureTracked(target_widget);
    }

    /// Unregister a widget from the focus chain.
    pub fn unregisterFocusable(self: *FocusManager, target_widget: *widget.Widget) void {
        if (self.findInChain(target_widget)) |idx| {
            _ = self.focus_chain.orderedRemove(idx);
        }
        if (self.focused_widget == target_widget) {
            self.focused_widget = null;
        }
    }

    /// Move focus forward through the registered chain, skipping unfocusable items.
    pub fn focusNext(self: *FocusManager) !bool {
        self.pruneChain();
        if (self.focus_chain.items.len == 0) return false;

        const start_idx: isize = if (self.focused_widget) |focused| blk: {
            if (self.findInChain(focused)) |idx| break :blk @as(isize, @intCast(idx));
            break :blk -1;
        } else -1;

        var idx: usize = if (start_idx >= 0) @intCast(start_idx) else self.focus_chain.items.len - 1;
        var attempts: usize = 0;
        while (attempts < self.focus_chain.items.len) : (attempts += 1) {
            idx = (idx + 1) % self.focus_chain.items.len;
            const candidate = self.focus_chain.items[idx];
            if (!candidate.canFocus()) continue;
            return try self.requestFocus(candidate);
        }

        return false;
    }

    fn focusPreviousInChain(self: *FocusManager) !bool {
        self.pruneChain();
        if (self.focus_chain.items.len == 0) return false;

        const start_idx: isize = if (self.focused_widget) |focused| blk: {
            if (self.findInChain(focused)) |idx| break :blk @as(isize, @intCast(idx));
            break :blk 0;
        } else 0;

        var idx: usize = @intCast((start_idx + @as(isize, self.focus_chain.items.len)) % @as(isize, self.focus_chain.items.len));
        var attempts: usize = 0;
        while (attempts < self.focus_chain.items.len) : (attempts += 1) {
            idx = (idx + self.focus_chain.items.len - 1) % self.focus_chain.items.len;
            const candidate = self.focus_chain.items[idx];
            if (!candidate.canFocus()) continue;
            return try self.requestFocus(candidate);
        }

        return false;
    }

    fn ensureTracked(self: *FocusManager, target_widget: *widget.Widget) !void {
        if (self.findInChain(target_widget) != null) return;
        try self.focus_chain.append(self.allocator, target_widget);
    }

    fn findInChain(self: *FocusManager, target_widget: *widget.Widget) ?usize {
        for (self.focus_chain.items, 0..) |w, i| {
            if (w == target_widget) return i;
        }
        return null;
    }

    fn pruneChain(self: *FocusManager) void {
        var i: usize = 0;
        while (i < self.focus_chain.items.len) {
            if (!self.focus_chain.items[i].canFocus()) {
                _ = self.focus_chain.orderedRemove(i);
                continue;
            }
            i += 1;
        }
    }
};

/// Focus request event data
pub const FocusRequestData = struct {
    /// Widget requesting focus
    requesting_widget: *widget.Widget,
    /// Currently focused widget
    current_widget: *widget.Widget,
    /// Whether to allow the focus change
    allow: bool,
};

/// Focus request event ID
pub const FOCUS_REQUEST_EVENT_ID = 0x46435351; // "FCSQ"

/// Callback that determines whether a drop target accepts the current payload.
pub const DropAcceptFn = *const fn (target: *widget.Widget, drag: DragEventData) bool;

/// Callback invoked after a successful drop on a target.
pub const DropHandlerFn = *const fn (target: *widget.Widget, drag: DragEventData) void;

/// Registered drop target entry.
pub const DropTarget = struct {
    widget: *widget.Widget,
    accept: DropAcceptFn,
    on_drop: ?DropHandlerFn = null,
};

/// Helper to emit drag lifecycle events, manage payload cleanup, and coordinate drop targets.
pub const DragManager = struct {
    active: bool = false,
    source: ?*widget.Widget = null,
    payload: DragPayload = .{},
    start_x: u16 = 0,
    start_y: u16 = 0,
    last_x: u16 = 0,
    last_y: u16 = 0,
    button: u8 = 0,
    queue: *EventQueue,
    allocator: std.mem.Allocator,
    targets: std.ArrayList(DropTarget) = std.ArrayList(DropTarget).empty,
    retained_payloads: std.ArrayList(DragPayload) = std.ArrayList(DragPayload).empty,

    pub fn init(queue: *EventQueue, allocator: std.mem.Allocator) DragManager {
        return DragManager{
            .queue = queue,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DragManager) void {
        self.targets.deinit(self.allocator);
        self.cleanupPayload();
        self.cleanupRetainedPayloads();
        self.retained_payloads.deinit(self.allocator);
    }

    pub fn begin(self: *DragManager, source: ?*widget.Widget, x: u16, y: u16, button: u8, payload: DragPayload) !void {
        self.reapRetainedPayloads();
        try self.ensureCurrentPayloadReleaseCapacity();
        try self.queue.queue.ensureUnusedCapacity(self.queue.allocator, 1);
        self.releaseCurrentPayloadAssumeCapacity();

        self.active = true;
        self.source = source;
        self.payload = payload;
        self.start_x = x;
        self.start_y = y;
        self.last_x = x;
        self.last_y = y;
        self.button = button;

        try self.queue.createDragEvent(.drag_start, self.eventData(x, y, true), source);
    }

    pub fn update(self: *DragManager, x: u16, y: u16, target: ?*widget.Widget) !void {
        if (!self.active) return;
        try self.queue.queue.ensureUnusedCapacity(self.queue.allocator, 1);
        self.last_x = x;
        self.last_y = y;
        const resolved = self.resolveTarget(x, y, target);
        try self.queue.createDragEvent(.drag_update, self.eventData(x, y, resolved.accepted), resolved.widget);
    }

    pub fn end(self: *DragManager, x: u16, y: u16, drop_target: ?*widget.Widget) !void {
        if (!self.active) return;
        try self.queue.queue.ensureUnusedCapacity(self.queue.allocator, 2);
        if (payloadNeedsCleanup(self.payload)) {
            try self.retained_payloads.ensureUnusedCapacity(self.allocator, 1);
        }
        self.last_x = x;
        self.last_y = y;
        const resolved = self.resolveTarget(x, y, drop_target);
        try self.queue.createDragEvent(.drag_end, self.eventData(x, y, true), self.source);
        try self.queue.createDragEvent(.drop, self.eventData(x, y, resolved.accepted), resolved.widget);

        if (resolved.accepted) {
            if (resolved.target_entry) |entry| {
                if (entry.on_drop) |cb| {
                    cb(entry.widget, self.eventData(x, y, resolved.accepted));
                }
            }
        }

        self.active = false;
        self.releaseCurrentPayloadAssumeCapacity();
    }

    pub fn cancel(self: *DragManager) void {
        if (!self.active and self.payload.kind == .none) return;
        self.active = false;
        self.releaseCurrentPayloadBestEffort();
    }

    fn eventData(self: *const DragManager, x: u16, y: u16, accepted: bool) DragEventData {
        return DragEventData{
            .start_x = self.start_x,
            .start_y = self.start_y,
            .x = x,
            .y = y,
            .button = self.button,
            .source = self.source,
            .payload = self.payload,
            .accepted = accepted,
        };
    }

    fn cleanupPayload(self: *DragManager) void {
        self.payload.deinit();
    }

    fn cleanupRetainedPayloads(self: *DragManager) void {
        for (self.retained_payloads.items) |*payload| {
            payload.deinit();
        }
        self.retained_payloads.clearRetainingCapacity();
    }

    fn ensureCurrentPayloadReleaseCapacity(self: *DragManager) !void {
        if (payloadNeedsCleanup(self.payload) and self.payloadReferencedByPendingEvents(self.payload)) {
            try self.retained_payloads.ensureUnusedCapacity(self.allocator, 1);
        }
    }

    fn releaseCurrentPayloadAssumeCapacity(self: *DragManager) void {
        if (!payloadNeedsCleanup(self.payload)) {
            self.payload = .{};
            return;
        }

        if (self.payloadReferencedByPendingEvents(self.payload)) {
            self.retained_payloads.appendAssumeCapacity(self.payload);
            self.payload = .{};
            return;
        }

        self.cleanupPayload();
    }

    fn releaseCurrentPayloadBestEffort(self: *DragManager) void {
        if (!payloadNeedsCleanup(self.payload)) {
            self.payload = .{};
            return;
        }

        if (self.payloadReferencedByPendingEvents(self.payload)) {
            self.retained_payloads.append(self.allocator, self.payload) catch {
                return;
            };
            self.payload = .{};
            return;
        }

        self.cleanupPayload();
    }

    fn reapRetainedPayloads(self: *DragManager) void {
        var i: usize = 0;
        while (i < self.retained_payloads.items.len) {
            if (self.payloadReferencedByPendingEvents(self.retained_payloads.items[i])) {
                i += 1;
                continue;
            }

            self.retained_payloads.items[i].deinit();
            _ = self.retained_payloads.orderedRemove(i);
        }
    }

    fn payloadReferencedByPendingEvents(self: *DragManager, payload: DragPayload) bool {
        if (!payloadNeedsCleanup(payload)) return false;
        if (self.queue.head >= self.queue.queue.items.len) return false;

        for (self.queue.queue.items[self.queue.head..]) |event_item| {
            if (dragPayloadFromEvent(event_item)) |queued_payload| {
                if (samePayloadStorage(payload, queued_payload)) return true;
            }
        }

        return false;
    }

    /// Register a widget as a drop target with accept + optional on-drop callbacks.
    pub fn registerTarget(self: *DragManager, target: DropTarget) !void {
        try self.targets.append(self.allocator, target);
    }

    /// Remove a previously registered drop target.
    pub fn unregisterTarget(self: *DragManager, target_widget: *widget.Widget) bool {
        if (self.findTargetIndex(target_widget)) |idx| {
            _ = self.targets.orderedRemove(idx);
            return true;
        }
        return false;
    }

    /// Convenience hit test to find the registered drop target under a coordinate.
    pub fn hitTest(self: *DragManager, x: u16, y: u16) ?*DropTarget {
        return self.targetAtPoint(x, y);
    }

    fn resolveTarget(self: *DragManager, x: u16, y: u16, explicit: ?*widget.Widget) struct { widget: ?*widget.Widget, accepted: bool, target_entry: ?DropTarget } {
        if (explicit) |target_widget| {
            const accepted = self.accepts(target_widget, x, y);
            const entry = self.lookupTarget(target_widget);
            return .{ .widget = target_widget, .accepted = accepted, .target_entry = entry };
        }

        if (self.targetAtPoint(x, y)) |entry| {
            const accepted = entry.accept(entry.widget, self.eventData(x, y, true));
            return .{ .widget = entry.widget, .accepted = accepted, .target_entry = entry.* };
        }

        return .{ .widget = null, .accepted = false, .target_entry = null };
    }

    fn targetAtPoint(self: *DragManager, x: u16, y: u16) ?*DropTarget {
        var i: usize = self.targets.items.len;
        while (i > 0) {
            i -= 1;
            const entry = &self.targets.items[i];
            if (pointInRect(x, y, entry.widget.rect)) {
                return entry;
            }
        }
        return null;
    }

    fn accepts(self: *DragManager, target_widget: *widget.Widget, x: u16, y: u16) bool {
        if (self.lookupTarget(target_widget)) |entry| {
            return entry.accept(target_widget, self.eventData(x, y, true));
        }
        return true;
    }

    fn lookupTarget(self: *DragManager, target_widget: *widget.Widget) ?DropTarget {
        for (self.targets.items) |entry| {
            if (entry.widget == target_widget) return entry;
        }
        return null;
    }

    fn findTargetIndex(self: *DragManager, target_widget: *widget.Widget) ?usize {
        for (self.targets.items, 0..) |entry, i| {
            if (entry.widget == target_widget) return i;
        }
        return null;
    }

    fn pointInRect(x: u16, y: u16, rect: layout.Rect) bool {
        const x_u32: u32 = x;
        const y_u32: u32 = y;
        const rect_x: u32 = rect.x;
        const rect_y: u32 = rect.y;
        const rect_right = rect_x + @as(u32, rect.width);
        const rect_bottom = rect_y + @as(u32, rect.height);
        return x_u32 >= rect_x and y_u32 >= rect_y and x_u32 < rect_right and y_u32 < rect_bottom;
    }
};

fn payloadNeedsCleanup(payload: DragPayload) bool {
    return switch (payload.kind) {
        .text => payload.storage.text.allocator != null,
        .custom => payload.storage.custom.ptr != null and payload.storage.custom.destructor != null,
        else => false,
    };
}

fn dragPayloadFromEvent(event_item: Event) ?DragPayload {
    return switch (event_item.type) {
        .drag_start => event_item.data.drag_start.payload,
        .drag_update => event_item.data.drag_update.payload,
        .drag_end => event_item.data.drag_end.payload,
        .drop => event_item.data.drop.payload,
        else => null,
    };
}

fn samePayloadStorage(a: DragPayload, b: DragPayload) bool {
    if (a.kind != b.kind) return false;

    return switch (a.kind) {
        .none => true,
        .widget => a.storage.widget == b.storage.widget,
        .text => a.storage.text.bytes.ptr == b.storage.text.bytes.ptr and
            a.storage.text.bytes.len == b.storage.text.bytes.len,
        .custom => a.storage.custom.ptr == b.storage.custom.ptr and
            a.storage.custom.destructor == b.storage.custom.destructor,
    };
}

/// Helper utilities for painting drop target feedback.
pub const DropVisuals = struct {
    pub const State = enum { idle, valid, invalid };

    pub const Colors = struct {
        border: render.Color,
        fill: render.Color,
        valid: render.Color,
        invalid: render.Color,
        text: render.Color,
    };

    /// Construct a sensible palette from a theme.
    pub fn colorsFromTheme(th: widget.theme.Theme) Colors {
        return .{
            .border = th.color(.accent),
            .fill = th.color(.surface),
            .valid = th.color(.success),
            .invalid = th.color(.danger),
            .text = th.color(.text),
        };
    }

    /// Draw only the outline for a drop zone.
    pub fn outline(renderer: *render.Renderer, rect: layout.Rect, state: State, colors: Colors) void {
        const color = switch (state) {
            .idle => colors.border,
            .valid => colors.valid,
            .invalid => colors.invalid,
        };
        const style = render.Style{ .bold = state != .idle };
        renderer.drawBox(rect.x, rect.y, rect.width, rect.height, render.BorderStyle.double, color, colors.fill, style);
    }

    /// Draw a filled drop zone with state-aware tint and outline.
    pub fn filled(renderer: *render.Renderer, rect: layout.Rect, state: State, colors: Colors) void {
        const fill_color = switch (state) {
            .idle => colors.fill,
            .valid => widget.theme.adjust(colors.valid, -15),
            .invalid => widget.theme.adjust(colors.invalid, -15),
        };

        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', colors.text, fill_color, render.Style{});
        outline(renderer, rect, state, colors);
    }
};

/// Normalized key combination used for shortcut lookup.
pub const KeyCombo = struct {
    key: u21,
    modifiers: input.KeyModifiers = .{},

    pub fn hash(self: KeyCombo) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(std.mem.asBytes(&self.key));
        hasher.update(std.mem.asBytes(&self.modifiers));
        return hasher.final();
    }

    pub fn eql(a: KeyCombo, b: KeyCombo) bool {
        return a.key == b.key and a.modifiers.ctrl == b.modifiers.ctrl and a.modifiers.alt == b.modifiers.alt and a.modifiers.shift == b.modifiers.shift;
    }
};

pub const ShortcutScope = enum { global, focused_only };

pub const ShortcutContext = struct {
    event: *Event,
    target: ?*widget.Widget,
};

pub const ShortcutCallback = *const fn (ctx: ShortcutContext, user_data: ?*anyopaque) bool;

pub const ShortcutSummary = struct {
    combo: []const u8,
    description: []const u8,
    scope: ShortcutScope,
};

pub const ShortcutRegistry = struct {
    allocator: std.mem.Allocator,
    shortcuts: std.ArrayList(ShortcutEntry),
    lookup: std.AutoHashMap(KeyCombo, usize),
    next_id: u32 = 1,

    const ShortcutEntry = struct {
        id: u32,
        combo: KeyCombo,
        description: []const u8,
        callback: ShortcutCallback,
        user_data: ?*anyopaque,
        scope: ShortcutScope,
    };

    pub fn init(allocator: std.mem.Allocator) ShortcutRegistry {
        return ShortcutRegistry{
            .allocator = allocator,
            .shortcuts = std.ArrayList(ShortcutEntry).empty,
            .lookup = std.AutoHashMap(KeyCombo, usize).init(allocator),
        };
    }

    pub fn deinit(self: *ShortcutRegistry) void {
        for (self.shortcuts.items) |entry| {
            self.allocator.free(entry.description);
        }
        self.shortcuts.deinit(self.allocator);
        self.lookup.deinit();
    }

    pub fn register(self: *ShortcutRegistry, combo: KeyCombo, description: []const u8, callback: ShortcutCallback, user_data: ?*anyopaque, scope: ShortcutScope) !u32 {
        if (self.lookup.get(combo) != null) return error.ShortcutConflict;

        const id = self.next_id;
        const desc_copy = try self.allocator.dupe(u8, description);

        const idx = self.shortcuts.items.len;
        {
            errdefer self.allocator.free(desc_copy);
            try self.shortcuts.append(self.allocator, ShortcutEntry{
                .id = id,
                .combo = combo,
                .description = desc_copy,
                .callback = callback,
                .user_data = user_data,
                .scope = scope,
            });
        }
        errdefer {
            const removed = self.shortcuts.orderedRemove(idx);
            self.allocator.free(removed.description);
        }

        try self.lookup.put(combo, idx);
        self.next_id += 1;
        return id;
    }

    pub fn unregister(self: *ShortcutRegistry, id: u32) bool {
        var removed = false;
        var i: usize = 0;
        while (i < self.shortcuts.items.len) {
            if (self.shortcuts.items[i].id == id) {
                self.allocator.free(self.shortcuts.items[i].description);
                _ = self.shortcuts.orderedRemove(i);
                removed = true;
                break;
            }
            i += 1;
        }
        if (!removed) return false;

        self.lookup.clearRetainingCapacity();
        for (self.shortcuts.items, 0..) |entry, entry_idx| {
            self.lookup.putAssumeCapacityNoClobber(entry.combo, entry_idx);
        }
        return true;
    }

    pub fn handle(self: *ShortcutRegistry, ev: *Event) bool {
        if (ev.type != .key_press) return false;
        const combo = KeyCombo{ .key = ev.data.key_press.key, .modifiers = ev.data.key_press.modifiers };
        if (self.lookup.get(combo)) |idx| {
            const entry = self.shortcuts.items[idx];
            if (entry.scope == .focused_only and ev.target == null) return false;
            const ctx = ShortcutContext{ .event = ev, .target = ev.target };
            const handled = entry.callback(ctx, entry.user_data);
            if (handled) {
                ev.handled = true;
            }
            return handled;
        }
        return false;
    }

    pub fn summaries(self: *ShortcutRegistry, allocator: std.mem.Allocator) ![]ShortcutSummary {
        var list = try std.ArrayList(ShortcutSummary).initCapacity(allocator, 0);
        errdefer {
            for (list.items) |entry| {
                allocator.free(entry.combo);
                allocator.free(entry.description);
            }
            list.deinit(allocator);
        }

        for (self.shortcuts.items) |entry| {
            const combo_str = try formatCombo(entry.combo, allocator);
            errdefer allocator.free(combo_str);

            const desc_copy = try allocator.dupe(u8, entry.description);
            errdefer allocator.free(desc_copy);

            try list.append(allocator, .{
                .combo = combo_str,
                .description = desc_copy,
                .scope = entry.scope,
            });
        }

        return list.toOwnedSlice(allocator);
    }

    fn formatCombo(combo: KeyCombo, allocator: std.mem.Allocator) ![]const u8 {
        var buf = try std.ArrayList(u8).initCapacity(allocator, 0);
        errdefer buf.deinit(allocator);

        const mods = try combo.modifiers.toString(allocator);
        defer allocator.free(mods);
        try buf.appendSlice(allocator, mods);

        var key_name: []const u8 = undefined;
        var stack_buf: [8]u8 = undefined;
        if (combo.key < 128 and std.ascii.isPrint(@intCast(combo.key))) {
            stack_buf[0] = @intCast(combo.key);
            key_name = stack_buf[0..1];
        } else {
            key_name = switch (combo.key) {
                input.KeyCode.UP => "Up",
                input.KeyCode.DOWN => "Down",
                input.KeyCode.LEFT => "Left",
                input.KeyCode.RIGHT => "Right",
                input.KeyCode.HOME => "Home",
                input.KeyCode.END => "End",
                input.KeyCode.PAGE_UP => "PageUp",
                input.KeyCode.PAGE_DOWN => "PageDown",
                input.KeyCode.ENTER => "Enter",
                input.KeyCode.ESCAPE => "Esc",
                else => "Key",
            };
        }

        try buf.appendSlice(allocator, key_name);
        return buf.toOwnedSlice(allocator);
    }
};

/// Minimal helper to paint a shortcut cheat-sheet overlay.
pub const ShortcutOverlay = struct {
    pub fn draw(renderer: *render.Renderer, rect: layout.Rect, shortcuts: []const ShortcutSummary, fg: render.Color, bg: render.Color) void {
        renderer.fillRect(rect.x, rect.y, rect.width, rect.height, ' ', fg, bg, render.Style{});
        renderer.drawBox(rect.x, rect.y, rect.width, rect.height, render.BorderStyle.double, fg, bg, render.Style{ .bold = true });

        var y: i16 = rect.y + 1;
        for (shortcuts) |shortcut| {
            if (y >= rect.y + rect.height - 1) break;
            var buf: [256]u8 = undefined;
            const text = std.fmt.bufPrint(&buf, "{s}  {s}", .{ shortcut.combo, shortcut.description }) catch shortcut.description;
            var x: i16 = rect.x + 2;
            for (text) |ch| {
                if (x >= rect.x + rect.width - 1) break;
                renderer.drawChar(x, y, ch, fg, bg, render.Style{});
                x += 1;
            }
            y += 1;
        }
    }
};

fn shortcutTestCallback(_: ShortcutContext, _: ?*anyopaque) bool {
    return true;
}

fn countingShortcutCallback(_: ShortcutContext, user_data: ?*anyopaque) bool {
    const counter = @as(*usize, @ptrCast(@alignCast(user_data orelse return false)));
    counter.* += 1;
    return true;
}

fn freeShortcutSummaries(allocator: std.mem.Allocator, summaries: []ShortcutSummary) void {
    for (summaries) |summary| {
        allocator.free(summary.combo);
        allocator.free(summary.description);
    }
    allocator.free(summaries);
}

fn shortcutRegisterAllocationFailureHarness(allocator: std.mem.Allocator) !void {
    var registry = ShortcutRegistry.init(allocator);
    defer registry.deinit();

    _ = try registry.register(.{
        .key = 's',
        .modifiers = .{ .ctrl = true },
    }, "Save file", shortcutTestCallback, null, .global);
}

test "shortcut register cleans up every allocation failure path" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, shortcutRegisterAllocationFailureHarness, .{});
}

fn shortcutSummariesAllocationFailureHarness(allocator: std.mem.Allocator) !void {
    var registry = ShortcutRegistry.init(allocator);
    defer registry.deinit();

    _ = try registry.register(.{
        .key = 's',
        .modifiers = .{ .ctrl = true },
    }, "Save file", shortcutTestCallback, null, .global);
    _ = try registry.register(.{
        .key = input.KeyCode.F1,
        .modifiers = .{},
    }, "Show help", shortcutTestCallback, null, .focused_only);

    const summaries = try registry.summaries(allocator);
    defer freeShortcutSummaries(allocator, summaries);
    try std.testing.expectEqual(@as(usize, 2), summaries.len);
}

test "shortcut summaries clean up every allocation failure path" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, shortcutSummariesAllocationFailureHarness, .{});
}

test "shortcut unregister rebuilds shifted lookup indices" {
    const alloc = std.testing.allocator;
    var registry = ShortcutRegistry.init(alloc);
    defer registry.deinit();

    var first_count: usize = 0;
    var second_count: usize = 0;
    var third_count: usize = 0;

    const first_id = try registry.register(.{ .key = 'a' }, "First", countingShortcutCallback, &first_count, .global);
    _ = try registry.register(.{ .key = 'b' }, "Second", countingShortcutCallback, &second_count, .global);
    _ = try registry.register(.{ .key = 'c' }, "Third", countingShortcutCallback, &third_count, .global);

    try std.testing.expect(registry.unregister(first_id));

    var removed_event = fromInputEvent(.{ .key = input.KeyEvent.init('a', .{}) }, null);
    try std.testing.expect(!registry.handle(&removed_event));
    try std.testing.expectEqual(@as(usize, 0), first_count);

    var second_event = fromInputEvent(.{ .key = input.KeyEvent.init('b', .{}) }, null);
    try std.testing.expect(registry.handle(&second_event));
    try std.testing.expect(second_event.handled);
    try std.testing.expectEqual(@as(usize, 1), second_count);

    var third_event = fromInputEvent(.{ .key = input.KeyEvent.init('c', .{}) }, null);
    try std.testing.expect(registry.handle(&third_event));
    try std.testing.expect(third_event.handled);
    try std.testing.expectEqual(@as(usize, 1), third_count);
}

test "event queue deinit destroys queued custom payloads" {
    const alloc = std.testing.allocator;
    var queue = EventQueue.init(alloc);

    var destroyed = false;
    const Destructor = struct {
        fn destroy(data: *anyopaque) void {
            const flag = @as(*bool, @ptrCast(@alignCast(data)));
            flag.* = true;
        }
    };

    try queue.createCustomEvent(42, @ptrCast(&destroyed), Destructor.destroy, null);
    queue.deinit();

    try std.testing.expect(destroyed);
}

test "drag manager enqueues lifecycle events" {
    const alloc = std.testing.allocator;
    var queue = EventQueue.init(alloc);
    defer queue.deinit();

    const dummy_vtable = widget.Widget.VTable{
        .draw = struct {
            fn draw(_: *anyopaque, _: *render.Renderer) anyerror!void {}
        }.draw,
        .handle_event = struct {
            fn handle(_: *anyopaque, _: input.Event) anyerror!bool {
                return false;
            }
        }.handle,
        .layout = struct {
            fn layout(_: *anyopaque, _: @import("../layout/layout.zig").Rect) anyerror!void {}
        }.layout,
        .get_preferred_size = struct {
            fn size(_: *anyopaque) anyerror!@import("../layout/layout.zig").Size {
                return @import("../layout/layout.zig").Size.zero();
            }
        }.size,
        .can_focus = struct {
            fn can(_: *anyopaque) bool {
                return false;
            }
        }.can,
    };

    var stub = widget.Widget.init(&dummy_vtable);
    var mgr = DragManager.init(&queue, alloc);
    defer mgr.deinit();

    try mgr.begin(&stub, 1, 1, 1, .{});
    try mgr.update(2, 2, &stub);
    try mgr.end(3, 3, &stub);

    try std.testing.expectEqual(@as(usize, 4), queue.queue.items.len);
    try std.testing.expectEqual(EventType.drag_start, queue.queue.items[0].type);
    try std.testing.expectEqual(EventType.drag_update, queue.queue.items[1].type);
    try std.testing.expectEqual(EventType.drag_end, queue.queue.items[2].type);
    try std.testing.expectEqual(EventType.drop, queue.queue.items[3].type);
}

test "drop targets gate acceptance" {
    const alloc = std.testing.allocator;
    var queue = EventQueue.init(alloc);
    defer queue.deinit();

    const dummy_vtable = widget.Widget.VTable{
        .draw = struct {
            fn draw(_: *anyopaque, _: *render.Renderer) anyerror!void {}
        }.draw,
        .handle_event = struct {
            fn handle(_: *anyopaque, _: input.Event) anyerror!bool {
                return false;
            }
        }.handle,
        .layout = struct {
            fn layout(_: *anyopaque, _: @import("../layout/layout.zig").Rect) anyerror!void {}
        }.layout,
        .get_preferred_size = struct {
            fn size(_: *anyopaque) anyerror!@import("../layout/layout.zig").Size {
                return @import("../layout/layout.zig").Size.zero();
            }
        }.size,
        .can_focus = struct {
            fn can(_: *anyopaque) bool {
                return false;
            }
        }.can,
    };

    var stub = widget.Widget.init(&dummy_vtable);
    stub.rect = layout.Rect.init(0, 0, 10, 10);
    var mgr = DragManager.init(&queue, alloc);
    defer mgr.deinit();

    try mgr.registerTarget(.{
        .widget = &stub,
        .accept = struct {
            fn accept(_: *widget.Widget, drag: DragEventData) bool {
                return drag.x >= 5;
            }
        }.accept,
        .on_drop = null,
    });

    try mgr.begin(&stub, 0, 0, 1, .{});
    try mgr.update(2, 2, null);
    try mgr.end(2, 2, null);
    try std.testing.expectEqual(EventType.drop, queue.queue.items[3].type);
    try std.testing.expect(!queue.queue.items[3].data.drop.accepted);

    queue.queue.clearRetainingCapacity();

    try mgr.begin(&stub, 0, 0, 1, .{});
    try mgr.update(6, 6, null);
    try mgr.end(6, 6, null);
    try std.testing.expectEqual(EventType.drop, queue.queue.items[3].type);
    try std.testing.expect(queue.queue.items[3].data.drop.accepted);
}

test "drag manager keeps ended payload alive for queued drop events" {
    const alloc = std.testing.allocator;
    var queue = EventQueue.init(alloc);
    defer queue.deinit();

    var cleanup_count: usize = 0;
    const Hooks = struct {
        fn cleanup(data: *anyopaque) void {
            const counter = @as(*usize, @ptrCast(@alignCast(data)));
            counter.* += 1;
        }
    };

    var mgr = DragManager.init(&queue, alloc);

    try mgr.begin(null, 1, 2, 1, DragPayload.fromOpaque(@ptrCast(&cleanup_count), Hooks.cleanup, "counter"));
    try mgr.end(3, 4, null);

    try std.testing.expect(!mgr.active);
    try std.testing.expectEqual(@as(usize, 0), cleanup_count);
    try std.testing.expectEqual(@as(usize, 3), queue.queue.items.len);
    try std.testing.expectEqual(EventType.drop, queue.queue.items[2].type);
    try std.testing.expectEqual(@as(?*anyopaque, @ptrCast(&cleanup_count)), queue.queue.items[2].data.drop.payload.storage.custom.ptr);
    try std.testing.expectEqual(@as(usize, 1), mgr.retained_payloads.items.len);

    mgr.deinit();
    try std.testing.expectEqual(@as(usize, 1), cleanup_count);
}

test "drag manager retains ended payload until queued events drain" {
    const alloc = std.testing.allocator;
    var queue = EventQueue.init(alloc);
    defer queue.deinit();

    var cleanup_count: usize = 0;
    const Hooks = struct {
        fn cleanup(data: *anyopaque) void {
            const counter = @as(*usize, @ptrCast(@alignCast(data)));
            counter.* += 1;
        }
    };

    var mgr = DragManager.init(&queue, alloc);
    defer mgr.deinit();

    try mgr.begin(null, 1, 2, 1, DragPayload.fromOpaque(@ptrCast(&cleanup_count), Hooks.cleanup, "counter"));
    try mgr.end(3, 4, null);
    try std.testing.expectEqual(@as(usize, 0), cleanup_count);
    try std.testing.expectEqual(@as(usize, 1), mgr.retained_payloads.items.len);

    try mgr.begin(null, 5, 6, 1, .{});
    try std.testing.expectEqual(@as(usize, 0), cleanup_count);
    try std.testing.expectEqual(@as(usize, 1), mgr.retained_payloads.items.len);

    try queue.processEvents();

    try mgr.begin(null, 7, 8, 1, .{});
    try std.testing.expectEqual(@as(usize, 1), cleanup_count);
    try std.testing.expectEqual(@as(usize, 0), mgr.retained_payloads.items.len);
    mgr.cancel();
    try std.testing.expectEqual(@as(usize, 1), cleanup_count);
}

test "drag manager retains cancelled payload until queued events drain" {
    const alloc = std.testing.allocator;
    var queue = EventQueue.init(alloc);
    defer queue.deinit();

    var cleanup_count: usize = 0;
    const Hooks = struct {
        fn cleanup(data: *anyopaque) void {
            const counter = @as(*usize, @ptrCast(@alignCast(data)));
            counter.* += 1;
        }
    };

    var mgr = DragManager.init(&queue, alloc);
    defer mgr.deinit();

    try mgr.begin(null, 1, 2, 1, DragPayload.fromOpaque(@ptrCast(&cleanup_count), Hooks.cleanup, "counter"));
    mgr.cancel();
    try std.testing.expectEqual(@as(usize, 0), cleanup_count);
    try std.testing.expectEqual(@as(usize, 1), mgr.retained_payloads.items.len);

    try queue.processEvents();
    try mgr.begin(null, 3, 4, 1, .{});
    try std.testing.expectEqual(@as(usize, 1), cleanup_count);
    try std.testing.expectEqual(@as(usize, 0), mgr.retained_payloads.items.len);
}

test "drag manager hit testing accepts edge coordinates above u16 rect end" {
    const alloc = std.testing.allocator;
    var queue = EventQueue.init(alloc);
    defer queue.deinit();

    const dummy_vtable = widget.Widget.VTable{
        .draw = struct {
            fn draw(_: *anyopaque, _: *render.Renderer) anyerror!void {}
        }.draw,
        .handle_event = struct {
            fn handle(_: *anyopaque, _: input.Event) anyerror!bool {
                return false;
            }
        }.handle,
        .layout = struct {
            fn layout(_: *anyopaque, _: @import("../layout/layout.zig").Rect) anyerror!void {}
        }.layout,
        .get_preferred_size = struct {
            fn size(_: *anyopaque) anyerror!@import("../layout/layout.zig").Size {
                return @import("../layout/layout.zig").Size.zero();
            }
        }.size,
        .can_focus = struct {
            fn can(_: *anyopaque) bool {
                return false;
            }
        }.can,
    };

    var stub = widget.Widget.init(&dummy_vtable);
    stub.rect = layout.Rect.init(std.math.maxInt(u16) - 1, std.math.maxInt(u16) - 1, 4, 4);
    var mgr = DragManager.init(&queue, alloc);
    defer mgr.deinit();

    try mgr.registerTarget(.{
        .widget = &stub,
        .accept = struct {
            fn accept(_: *widget.Widget, _: DragEventData) bool {
                return true;
            }
        }.accept,
        .on_drop = null,
    });

    try std.testing.expect(mgr.hitTest(std.math.maxInt(u16), std.math.maxInt(u16)) != null);
}

test "drag manager begin preserves active drag on event allocation failure" {
    const alloc = std.testing.allocator;
    var queue = EventQueue.init(alloc);
    defer queue.deinit();
    var mgr = DragManager.init(&queue, alloc);
    defer mgr.deinit();

    try mgr.begin(null, 1, 2, 3, .{});
    queue.queue.shrinkAndFree(alloc, queue.queue.items.len);
    try std.testing.expectEqual(queue.queue.items.len, queue.queue.capacity);

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = queue.allocator;
    queue.allocator = failing.allocator();
    defer queue.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, mgr.begin(null, 9, 8, 7, .{}));
    try std.testing.expect(mgr.active);
    try std.testing.expectEqual(@as(u16, 1), mgr.start_x);
    try std.testing.expectEqual(@as(u16, 2), mgr.start_y);
    try std.testing.expectEqual(@as(u16, 1), mgr.last_x);
    try std.testing.expectEqual(@as(u16, 2), mgr.last_y);
    try std.testing.expectEqual(@as(u8, 3), mgr.button);
    try std.testing.expectEqual(@as(usize, 1), queue.queue.items.len);
    try std.testing.expectEqual(EventType.drag_start, queue.queue.items[0].type);
}

test "drag manager update preserves coordinates on event allocation failure" {
    const alloc = std.testing.allocator;
    var queue = EventQueue.init(alloc);
    defer queue.deinit();
    var mgr = DragManager.init(&queue, alloc);
    defer mgr.deinit();

    try mgr.begin(null, 1, 2, 3, .{});
    queue.queue.shrinkAndFree(alloc, queue.queue.items.len);
    try std.testing.expectEqual(queue.queue.items.len, queue.queue.capacity);

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = queue.allocator;
    queue.allocator = failing.allocator();
    defer queue.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, mgr.update(9, 8, null));
    try std.testing.expect(mgr.active);
    try std.testing.expectEqual(@as(u16, 1), mgr.last_x);
    try std.testing.expectEqual(@as(u16, 2), mgr.last_y);
    try std.testing.expectEqual(@as(usize, 1), queue.queue.items.len);
    try std.testing.expectEqual(EventType.drag_start, queue.queue.items[0].type);
}

test "drag manager end preserves active drag on event allocation failure" {
    const alloc = std.testing.allocator;
    var queue = EventQueue.init(alloc);
    defer queue.deinit();
    var mgr = DragManager.init(&queue, alloc);
    defer mgr.deinit();

    try mgr.begin(null, 1, 2, 3, .{});
    queue.queue.shrinkAndFree(alloc, queue.queue.items.len);
    try std.testing.expectEqual(queue.queue.items.len, queue.queue.capacity);

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = queue.allocator;
    queue.allocator = failing.allocator();
    defer queue.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, mgr.end(9, 8, null));
    try std.testing.expect(mgr.active);
    try std.testing.expectEqual(@as(u16, 1), mgr.last_x);
    try std.testing.expectEqual(@as(u16, 2), mgr.last_y);
    try std.testing.expectEqual(@as(usize, 1), queue.queue.items.len);
    try std.testing.expectEqual(EventType.drag_start, queue.queue.items[0].type);
}

test "event dispatcher preserves next listener id on allocation failure" {
    const alloc = std.testing.allocator;
    var dispatcher = EventDispatcher.init(alloc);
    defer dispatcher.deinit();

    const Listener = struct {
        fn on(_: *Event) bool {
            return false;
        }
    };

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = dispatcher.allocator;
    dispatcher.allocator = failing.allocator();
    defer dispatcher.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, dispatcher.addEventListener(.key_press, Listener.on, null));
    try std.testing.expectEqual(@as(u32, 1), dispatcher.next_id);
    try std.testing.expectEqual(@as(usize, 0), dispatcher.listeners.items.len);
}

test "processEvents destroys custom payloads consumed by preprocessor" {
    const alloc = std.testing.allocator;
    var queue = EventQueue.init(alloc);
    defer queue.deinit();

    var cleanup_count: usize = 0;
    var consumed = false;

    const Hooks = struct {
        fn cleanup(data: *anyopaque) void {
            const counter = @as(*usize, @ptrCast(@alignCast(data)));
            counter.* += 1;
        }

        fn preprocess(_: *Event, ctx: ?*anyopaque) bool {
            const flag = @as(*bool, @ptrCast(@alignCast(ctx.?)));
            flag.* = true;
            return true;
        }
    };

    queue.setPreprocessor(.{ .handler = Hooks.preprocess, .ctx = @ptrCast(&consumed) });
    try queue.createCustomEvent(1, @ptrCast(&cleanup_count), Hooks.cleanup, null);

    try queue.processEvents();

    try std.testing.expect(consumed);
    try std.testing.expectEqual(@as(usize, 1), cleanup_count);
    try std.testing.expectEqual(@as(usize, 0), queue.queue.items.len);
}

test "processEventsWithPropagation destroys custom payloads consumed by preprocessor" {
    const alloc = std.testing.allocator;
    var queue = EventQueue.init(alloc);
    defer queue.deinit();

    var cleanup_count: usize = 0;
    var consumed = false;

    const Hooks = struct {
        fn cleanup(data: *anyopaque) void {
            const counter = @as(*usize, @ptrCast(@alignCast(data)));
            counter.* += 1;
        }

        fn preprocess(_: *Event, ctx: ?*anyopaque) bool {
            const flag = @as(*bool, @ptrCast(@alignCast(ctx.?)));
            flag.* = true;
            return true;
        }
    };

    queue.setPreprocessor(.{ .handler = Hooks.preprocess, .ctx = @ptrCast(&consumed) });
    try queue.createCustomEvent(1, @ptrCast(&cleanup_count), Hooks.cleanup, null);

    try queue.processEventsWithPropagation(alloc);

    try std.testing.expect(consumed);
    try std.testing.expectEqual(@as(usize, 1), cleanup_count);
    try std.testing.expectEqual(@as(usize, 0), queue.queue.items.len);
}

test "propagation captures target then bubbles with current target set" {
    const alloc = std.testing.allocator;
    var dispatcher = EventDispatcher.init(alloc);
    defer dispatcher.deinit();

    const dummy_vtable = widget.Widget.VTable{
        .draw = struct {
            fn draw(_: *anyopaque, _: *render.Renderer) anyerror!void {}
        }.draw,
        .handle_event = struct {
            fn handle(_: *anyopaque, _: input.Event) anyerror!bool {
                return false;
            }
        }.handle,
        .layout = struct {
            fn doLayout(_: *anyopaque, _: layout.Rect) anyerror!void {}
        }.doLayout,
        .get_preferred_size = struct {
            fn size(_: *anyopaque) anyerror!layout.Size {
                return layout.Size.zero();
            }
        }.size,
        .can_focus = struct {
            fn can(_: *anyopaque) bool {
                return true;
            }
        }.can,
    };

    const Node = struct { widget: widget.Widget };
    var root = Node{ .widget = widget.Widget.init(&dummy_vtable) };
    var branch = Node{ .widget = widget.Widget.init(&dummy_vtable) };
    var leaf = Node{ .widget = widget.Widget.init(&dummy_vtable) };
    branch.widget.parent = &root.widget;
    leaf.widget.parent = &branch.widget;

    var order: [5][]const u8 = undefined;
    var order_len: usize = 0;

    const Logger = struct {
        pub var log: *[5][]const u8 = undefined;
        pub var log_len: *usize = undefined;
        pub var root_ptr: *widget.Widget = undefined;
        pub var branch_ptr: *widget.Widget = undefined;
        pub var leaf_ptr: *widget.Widget = undefined;

        pub fn listener(ev: *Event) bool {
            const current = ev.current_target orelse return false;
            const label: []const u8 = if (current == root_ptr)
                "root"
            else if (current == branch_ptr)
                "branch"
            else
                "leaf";
            if (log_len.* < log.len) {
                log[log_len.*] = label;
                log_len.* += 1;
            }
            return false;
        }
    };

    Logger.log = &order;
    Logger.log_len = &order_len;
    Logger.root_ptr = &root.widget;
    Logger.branch_ptr = &branch.widget;
    Logger.leaf_ptr = &leaf.widget;
    _ = try dispatcher.addEventListener(.key_press, Logger.listener, null);

    var ev = Event.init(.key_press, &leaf.widget, Event.EventData{
        .key_press = KeyEventData{
            .key = @as(u21, input.KeyCode.ENTER),
            .modifiers = .{},
            .raw = 0,
        },
    });

    const propagation = @import("propagation.zig");
    _ = try propagation.dispatchWithPropagation(&dispatcher, &ev, alloc, .{});

    try std.testing.expectEqual(@as(usize, 5), order_len);
    try std.testing.expect(std.mem.eql(u8, "root", order[0]));
    try std.testing.expect(std.mem.eql(u8, "branch", order[1]));
    try std.testing.expect(std.mem.eql(u8, "leaf", order[2]));
    try std.testing.expect(std.mem.eql(u8, "branch", order[3]));
    try std.testing.expect(std.mem.eql(u8, "root", order[4]));
}

test "stopPropagation halts remaining phases" {
    const alloc = std.testing.allocator;
    var dispatcher = EventDispatcher.init(alloc);
    defer dispatcher.deinit();

    const dummy_vtable = widget.Widget.VTable{
        .draw = struct {
            fn draw(_: *anyopaque, _: *render.Renderer) anyerror!void {}
        }.draw,
        .handle_event = struct {
            fn handle(_: *anyopaque, _: input.Event) anyerror!bool {
                return false;
            }
        }.handle,
        .layout = struct {
            fn doLayout(_: *anyopaque, _: layout.Rect) anyerror!void {}
        }.doLayout,
        .get_preferred_size = struct {
            fn size(_: *anyopaque) anyerror!layout.Size {
                return layout.Size.zero();
            }
        }.size,
        .can_focus = struct {
            fn can(_: *anyopaque) bool {
                return true;
            }
        }.can,
    };

    const Node = struct { widget: widget.Widget };
    var root = Node{ .widget = widget.Widget.init(&dummy_vtable) };
    var branch = Node{ .widget = widget.Widget.init(&dummy_vtable) };
    var leaf = Node{ .widget = widget.Widget.init(&dummy_vtable) };
    branch.widget.parent = &root.widget;
    leaf.widget.parent = &branch.widget;

    var order: [2][]const u8 = undefined;
    var order_len: usize = 0;

    const Stopper = struct {
        pub var log: *[2][]const u8 = undefined;
        pub var log_len: *usize = undefined;
        pub var branch_ptr: *widget.Widget = undefined;

        fn append(label: []const u8) void {
            if (log_len.* < log.len) {
                log[log_len.*] = label;
                log_len.* += 1;
            }
        }

        pub fn listener(ev: *Event) bool {
            const current = ev.current_target orelse return false;
            if (current == branch_ptr) {
                append("branch");
                ev.stopPropagation();
            } else {
                append("root");
            }
            return false;
        }
    };

    Stopper.log = &order;
    Stopper.log_len = &order_len;
    Stopper.branch_ptr = &branch.widget;
    _ = try dispatcher.addEventListener(.key_press, Stopper.listener, null);

    var ev = Event.init(.key_press, &leaf.widget, Event.EventData{
        .key_press = KeyEventData{
            .key = @as(u21, input.KeyCode.ENTER),
            .modifiers = .{},
            .raw = 0,
        },
    });

    const propagation = @import("propagation.zig");
    _ = try propagation.dispatchWithPropagation(&dispatcher, &ev, alloc, .{});

    try std.testing.expectEqual(@as(usize, 2), order_len);
    try std.testing.expect(std.mem.eql(u8, "root", order[0]));
    try std.testing.expect(std.mem.eql(u8, "branch", order[1]));
    try std.testing.expect(ev.stop_propagation);
}

test "propagation tolerates deep widget trees" {
    const alloc = std.testing.allocator;
    var dispatcher = EventDispatcher.init(alloc);
    defer dispatcher.deinit();

    const dummy_vtable = widget.Widget.VTable{
        .draw = struct {
            fn draw(_: *anyopaque, _: *render.Renderer) anyerror!void {}
        }.draw,
        .handle_event = struct {
            fn handle(_: *anyopaque, _: input.Event) anyerror!bool {
                return false;
            }
        }.handle,
        .layout = struct {
            fn doLayout(_: *anyopaque, _: layout.Rect) anyerror!void {}
        }.doLayout,
        .get_preferred_size = struct {
            fn size(_: *anyopaque) anyerror!layout.Size {
                return layout.Size.zero();
            }
        }.size,
        .can_focus = struct {
            fn can(_: *anyopaque) bool {
                return true;
            }
        }.can,
    };

    const depth: usize = 128;
    var nodes: [depth]widget.Widget = undefined;
    for (&nodes, 0..) |*node, idx| {
        node.* = widget.Widget.init(&dummy_vtable);
        if (idx > 0) node.parent = &nodes[idx - 1];
    }

    var call_counter: usize = 0;
    const Logger = struct {
        pub var counter: *usize = undefined;
        pub fn listener(ev: *Event) bool {
            if (ev.current_target == null) return false;
            counter.* += 1;
            return false;
        }
    };

    Logger.counter = &call_counter;
    _ = try dispatcher.addEventListener(.key_press, Logger.listener, null);

    var ev = Event.init(.key_press, &nodes[depth - 1], Event.EventData{
        .key_press = KeyEventData{
            .key = @as(u21, input.KeyCode.ENTER),
            .modifiers = .{},
            .raw = 0,
        },
    });

    const propagation = @import("propagation.zig");
    _ = try propagation.dispatchWithPropagation(&dispatcher, &ev, alloc, .{});

    try std.testing.expectEqual(@as(usize, depth * 2 - 1), call_counter);
}

test "event propagation fuzzes random widget trees" {
    const alloc = std.testing.allocator;
    const dummy_vtable = widget.Widget.VTable{
        .draw = struct {
            fn draw(_: *anyopaque, _: *render.Renderer) anyerror!void {}
        }.draw,
        .handle_event = struct {
            fn handle(_: *anyopaque, _: input.Event) anyerror!bool {
                return false;
            }
        }.handle,
        .layout = struct {
            fn doLayout(_: *anyopaque, _: layout.Rect) anyerror!void {}
        }.doLayout,
        .get_preferred_size = struct {
            fn size(_: *anyopaque) anyerror!layout.Size {
                return layout.Size.zero();
            }
        }.size,
        .can_focus = struct {
            fn can(_: *anyopaque) bool {
                return true;
            }
        }.can,
    };

    var prng = std.Random.DefaultPrng.init(0xabad1dea);
    const rand = prng.random();

    for (0..16) |_| {
        var dispatcher = EventDispatcher.init(alloc);
        defer dispatcher.deinit();

        var call_counter: usize = 0;
        const Logger = struct {
            pub var counter: *usize = undefined;
            pub fn listener(ev: *Event) bool {
                if (ev.current_target == null) return false;
                counter.* += 1;
                return false;
            }
        };
        Logger.counter = &call_counter;
        _ = try dispatcher.addEventListener(.key_press, Logger.listener, null);

        const node_count = rand.intRangeAtMost(usize, 2, 32);
        var nodes = try alloc.alloc(widget.Widget, node_count);
        defer alloc.free(nodes);

        for (nodes, 0..) |*node, idx| {
            node.* = widget.Widget.init(&dummy_vtable);
            if (idx > 0) {
                const parent_idx = rand.intRangeAtMost(usize, 0, idx - 1);
                node.parent = &nodes[parent_idx];
            }
        }

        const target_idx = rand.intRangeAtMost(usize, 0, node_count - 1);
        var ev = Event.init(.key_press, &nodes[target_idx], Event.EventData{
            .key_press = KeyEventData{
                .key = @as(u21, input.KeyCode.ENTER),
                .modifiers = .{},
                .raw = 0,
            },
        });

        var depth: usize = 0;
        var cursor: ?*widget.Widget = ev.target;
        while (cursor) |ptr| {
            depth += 1;
            cursor = ptr.parent;
        }

        const propagation = @import("propagation.zig");
        _ = try propagation.dispatchWithPropagation(&dispatcher, &ev, alloc, .{});

        try std.testing.expectEqual(@as(usize, depth * 2 - 1), call_counter);
    }
}

test "focus traversal respects registered order and focusability" {
    const alloc = std.testing.allocator;
    var queue = EventQueue.init(alloc);
    defer queue.deinit();
    var manager = FocusManager.init(alloc, &queue);
    defer manager.deinit();

    const vtable = widget.Widget.VTable{
        .draw = struct {
            fn draw(_: *anyopaque, _: *render.Renderer) anyerror!void {}
        }.draw,
        .handle_event = struct {
            fn handle(_: *anyopaque, _: input.Event) anyerror!bool {
                return false;
            }
        }.handle,
        .layout = struct {
            fn doLayout(_: *anyopaque, _: layout.Rect) anyerror!void {}
        }.doLayout,
        .get_preferred_size = struct {
            fn size(_: *anyopaque) anyerror!layout.Size {
                return layout.Size.zero();
            }
        }.size,
        .can_focus = struct {
            fn can(widget_ptr: *anyopaque) bool {
                const self = @as(*widget.Widget, @ptrCast(@alignCast(widget_ptr)));
                return self.enabled;
            }
        }.can,
    };

    var first = widget.Widget.init(&vtable);
    var second = widget.Widget.init(&vtable);

    try manager.registerFocusable(&first);
    try manager.registerFocusable(&second);

    try std.testing.expect(try manager.focusNext());
    try std.testing.expectEqual(&first, manager.focused_widget.?);
    try std.testing.expectEqual(@as(usize, 1), queue.queue.items.len);
    try std.testing.expectEqual(EventType.focus_change, queue.queue.items[0].type);
    try std.testing.expect(queue.queue.items[0].data.focus_change.gained);
    try std.testing.expectEqual(&first, queue.queue.items[0].target.?);

    try std.testing.expect(try manager.focusNext());
    try std.testing.expectEqual(&second, manager.focused_widget.?);
    try std.testing.expectEqual(@as(usize, 2), queue.queue.items.len);
    try std.testing.expectEqual(&first, queue.queue.items[0].target.?);
    try std.testing.expect(!queue.queue.items[0].data.focus_change.gained);
    try std.testing.expectEqual(&second, queue.queue.items[1].target.?);

    // Disable second to ensure traversal skips it.
    second.setEnabled(false);
    try std.testing.expect(try manager.focusNext());
    try std.testing.expectEqual(&first, manager.focused_widget.?);
    try std.testing.expectEqual(@as(usize, 2), queue.queue.items.len);
    try std.testing.expect(queue.queue.items[1].data.focus_change.gained);
    try std.testing.expectEqual(&first, queue.queue.items[1].target.?);
}

test "focus request preserves current focus on history allocation failure" {
    const alloc = std.testing.allocator;
    var queue = EventQueue.init(alloc);
    defer queue.deinit();
    var manager = FocusManager.init(alloc, &queue);
    defer manager.deinit();

    const vtable = widget.Widget.VTable{
        .draw = struct {
            fn draw(_: *anyopaque, _: *render.Renderer) anyerror!void {}
        }.draw,
        .handle_event = struct {
            fn handle(_: *anyopaque, _: input.Event) anyerror!bool {
                return false;
            }
        }.handle,
        .layout = struct {
            fn doLayout(_: *anyopaque, _: layout.Rect) anyerror!void {}
        }.doLayout,
        .get_preferred_size = struct {
            fn size(_: *anyopaque) anyerror!layout.Size {
                return layout.Size.zero();
            }
        }.size,
        .can_focus = struct {
            fn can(_: *anyopaque) bool {
                return true;
            }
        }.can,
    };

    var first = widget.Widget.init(&vtable);
    var second = widget.Widget.init(&vtable);

    try manager.registerFocusable(&first);
    try manager.registerFocusable(&second);
    try std.testing.expect(try manager.requestFocus(&first));
    manager.focus_history.shrinkAndFree(alloc, manager.focus_history.items.len);
    try std.testing.expectEqual(manager.focus_history.items.len, manager.focus_history.capacity);

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = manager.allocator;
    manager.allocator = failing.allocator();
    defer manager.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, manager.requestFocus(&second));
    try std.testing.expectEqual(&first, manager.focused_widget.?);
    try std.testing.expect(first.focused);
    try std.testing.expect(!second.focused);
    try std.testing.expectEqual(@as(usize, 1), manager.focus_history.items.len);
    try std.testing.expectEqual(&first, manager.focus_history.items[0]);
}

test "focus request preserves current focus on event queue allocation failure" {
    const alloc = std.testing.allocator;
    var queue = EventQueue.init(alloc);
    defer queue.deinit();
    var manager = FocusManager.init(alloc, &queue);
    defer manager.deinit();
    manager.allow_focus_stealing = true;

    const vtable = widget.Widget.VTable{
        .draw = struct {
            fn draw(_: *anyopaque, _: *render.Renderer) anyerror!void {}
        }.draw,
        .handle_event = struct {
            fn handle(_: *anyopaque, _: input.Event) anyerror!bool {
                return false;
            }
        }.handle,
        .layout = struct {
            fn doLayout(_: *anyopaque, _: layout.Rect) anyerror!void {}
        }.doLayout,
        .get_preferred_size = struct {
            fn size(_: *anyopaque) anyerror!layout.Size {
                return layout.Size.zero();
            }
        }.size,
        .can_focus = struct {
            fn can(_: *anyopaque) bool {
                return true;
            }
        }.can,
    };

    var first = widget.Widget.init(&vtable);
    var second = widget.Widget.init(&vtable);

    try manager.registerFocusable(&first);
    try manager.registerFocusable(&second);
    try std.testing.expect(try manager.requestFocus(&first));
    try manager.focus_history.ensureUnusedCapacity(alloc, 1);
    queue.queue.shrinkAndFree(alloc, queue.queue.items.len);
    try std.testing.expectEqual(queue.queue.items.len, queue.queue.capacity);

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = queue.allocator;
    queue.allocator = failing.allocator();
    defer queue.allocator = original_allocator;

    try std.testing.expectError(error.OutOfMemory, manager.requestFocus(&second));
    try std.testing.expectEqual(&first, manager.focused_widget.?);
    try std.testing.expect(first.focused);
    try std.testing.expect(!second.focused);
    try std.testing.expectEqual(@as(usize, 1), manager.focus_history.items.len);
    try std.testing.expectEqual(@as(usize, 1), queue.queue.items.len);
    try std.testing.expectEqual(&first, queue.queue.items[0].target.?);
}

test "focus request records accessibility announcement failure without failing focus" {
    const alloc = std.testing.allocator;
    var queue = EventQueue.init(alloc);
    defer queue.deinit();
    var manager = FocusManager.init(alloc, &queue);
    defer manager.deinit();

    const vtable = widget.Widget.VTable{
        .draw = struct {
            fn draw(_: *anyopaque, _: *render.Renderer) anyerror!void {}
        }.draw,
        .handle_event = struct {
            fn handle(_: *anyopaque, _: input.Event) anyerror!bool {
                return false;
            }
        }.handle,
        .layout = struct {
            fn doLayout(_: *anyopaque, _: layout.Rect) anyerror!void {}
        }.doLayout,
        .get_preferred_size = struct {
            fn size(_: *anyopaque) anyerror!layout.Size {
                return layout.Size.zero();
            }
        }.size,
        .can_focus = struct {
            fn can(_: *anyopaque) bool {
                return true;
            }
        }.can,
    };

    var accessible = accessibility.Manager.init(alloc);
    defer accessible.deinit();
    manager.accessibility = &accessible;

    var target = widget.Widget.init(&vtable);
    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    const original_allocator = accessible.allocator;
    accessible.allocator = failing.allocator();

    try std.testing.expect(try manager.requestFocus(&target));

    accessible.allocator = original_allocator;
    try std.testing.expectEqual(&target, manager.focused_widget.?);
    try std.testing.expect(target.focused);
    try std.testing.expectEqual(@as(usize, 1), queue.queue.items.len);
    try std.testing.expectEqual(EventType.focus_change, queue.queue.items[0].type);
    try std.testing.expectEqual(@as(usize, 1), accessible.bestEffortFailureCount());
    const failure = accessible.lastBestEffortFailure().?;
    try std.testing.expectEqual(accessibility.BestEffortOperation.announce_focus, failure.operation);
    try std.testing.expectEqual(error.OutOfMemory, failure.err);
}

/// Application class for managing the event loop and UI components
pub const Application = struct {
    /// Event queue
    event_queue: EventQueue,
    /// Root widget
    root: ?*widget.Container = null,
    /// Whether the application is running
    running: bool = false,
    /// Allocator for application operations
    allocator: std.mem.Allocator,
    /// Optional memory manager for per-frame scratch allocations
    memory_manager: ?*memory.MemoryManager = null,
    /// Focus manager
    focus_manager: FocusManager,
    /// I/O event manager
    io_manager: ?*@import("io_events.zig").IoEventManager = null,
    /// Whether to use event propagation
    use_propagation: bool = true,
    /// Animation driver
    animator: animation.Animator,
    /// Last frame timestamp for animation deltas
    last_frame_ms: u64 = 0,
    /// Timer manager for async tasks
    timer_manager: timer.TimerManager,
    /// Accessibility manager (optional)
    accessibility: ?*accessibility.Manager = null,
    /// Drag-and-drop coordinator
    drag_manager: DragManager,
    /// Whether processInputEvent synthesizes drag lifecycle events from mouse input.
    automatic_drag: bool = true,
    /// Global shortcut registry
    shortcut_registry: ShortcutRegistry,
    /// Optional stylesheet for CSS-like styling
    style_sheet: ?*widget.css.StyleSheet = null,
    /// Optional theme for stylesheet resolution
    style_theme: ?widget.theme.Theme = null,
    /// Optional terminal-size binding for automatic renderer/root relayout.
    resize_binding: ResizeBinding = .{},
    /// Optional input binding for application-owned event polling.
    input_binding: InputBinding = .{},
    /// Whether user code already polled bound input before the next tick.
    input_polled_before_tick: bool = false,
    /// Background tasks owned by the application until released or shutdown.
    background_tasks: std.ArrayList(*BackgroundTask),

    /// Components updated when a resize event reaches the application.
    pub const ResizeBinding = struct {
        renderer: ?*render.Renderer = null,
        reflow: ?*layout.ReflowManager = null,
    };

    /// Components used when the application loop owns input polling.
    pub const InputBinding = struct {
        handler: ?*input.InputHandler = null,
        poll_timeout_ms: u64 = 0,
    };

    /// Initialize a new application
    pub fn init(allocator: std.mem.Allocator) Application {
        var app = Application{
            .event_queue = EventQueue.init(allocator),
            .allocator = allocator,
            .focus_manager = undefined,
            .animator = animation.Animator.init(allocator),
            .timer_manager = timer.TimerManager.init(allocator),
            .drag_manager = undefined,
            .shortcut_registry = ShortcutRegistry.init(allocator),
            .background_tasks = std.ArrayList(*BackgroundTask).empty,
        };

        app.focus_manager = FocusManager.init(allocator, &app.event_queue);
        app.drag_manager = DragManager.init(&app.event_queue, allocator);

        return app;
    }

    /// Initialize an application backed by a memory manager.
    pub fn initWithMemoryManager(manager: *memory.MemoryManager) Application {
        var app = Application.init(manager.getParentAllocator());
        app.memory_manager = manager;
        return app;
    }

    fn syncInternalPointers(self: *Application) void {
        self.focus_manager.event_queue = &self.event_queue;
        self.drag_manager.queue = &self.event_queue;
    }

    /// Attach a memory manager for per-frame scratch allocations.
    pub fn setMemoryManager(self: *Application, manager: ?*memory.MemoryManager) void {
        self.memory_manager = manager;
    }

    /// Get the allocator used for per-frame scratch work.
    pub fn frameAllocator(self: *Application) std.mem.Allocator {
        if (self.memory_manager) |manager| {
            return manager.frameAllocator();
        }
        return self.allocator;
    }

    /// Clean up application resources
    pub fn deinit(self: *Application) void {
        self.syncInternalPointers();
        self.cancelAndJoinBackgroundTasks();

        if (self.io_manager) |manager| {
            manager.deinit();
            self.allocator.destroy(manager);
        }

        if (self.accessibility) |manager| {
            manager.deinit();
            self.allocator.destroy(manager);
        }

        self.animator.deinit();
        self.timer_manager.deinit();
        self.focus_manager.deinit();
        self.drag_manager.deinit();
        self.shortcut_registry.deinit();
        self.background_tasks.deinit(self.allocator);
        self.event_queue.deinit();
    }

    /// Initialize I/O event manager
    pub fn initIoManager(self: *Application) !void {
        if (self.io_manager != null) return;

        const io_events = @import("io_events.zig");
        const manager = try self.allocator.create(io_events.IoEventManager);
        manager.* = io_events.IoEventManager.init(self.allocator, &self.event_queue);

        self.io_manager = manager;
    }

    /// Watch a file for changes
    pub fn watchFile(self: *Application, path: []const u8, target: ?*widget.Widget) !*@import("io_events.zig").FileWatchContext {
        if (self.io_manager == null) {
            try self.initIoManager();
        }

        return try self.io_manager.?.watchFile(path, target);
    }

    /// Stop and unregister a file watcher returned by `watchFile`.
    pub fn unwatchFile(self: *Application, watcher: *@import("io_events.zig").FileWatchContext) bool {
        if (self.io_manager) |manager| {
            return manager.unwatchFile(watcher);
        }
        return false;
    }

    /// Create a network context. Network transport is currently unsupported on the Zig 0.16 baseline;
    /// the context emits a `.network_error` event instead of opening a socket.
    pub fn connectToServer(self: *Application, address: []const u8, port: u16, target: ?*widget.Widget) !*@import("io_events.zig").NetworkContext {
        if (self.io_manager == null) {
            try self.initIoManager();
        }

        return try self.io_manager.?.connectToServer(address, port, target);
    }

    /// Disconnect and unregister a network context returned by `connectToServer`.
    pub fn disconnectFromServer(self: *Application, connection: *@import("io_events.zig").NetworkContext) bool {
        if (self.io_manager) |manager| {
            return manager.disconnectFromServer(connection);
        }
        return false;
    }

    /// Set the root widget
    pub fn setRoot(self: *Application, root: *widget.Container) void {
        self.root = root;
        self.applyStyleContext();
        self.applyAccessibilityContext();
    }

    /// Bind resize handling to renderer buffers and optional reflow layout.
    ///
    /// Once bound, `processInputEvent(.resize)` automatically resizes the
    /// renderer and relayouts the root before user resize listeners run.
    pub fn bindResize(self: *Application, renderer_ptr: *render.Renderer, reflow_ptr: ?*layout.ReflowManager) void {
        self.resize_binding = .{
            .renderer = renderer_ptr,
            .reflow = reflow_ptr,
        };
    }

    /// Remove automatic renderer/reflow resize handling.
    pub fn unbindResize(self: *Application) void {
        self.resize_binding = .{};
    }

    /// Bind terminal input polling to the application loop.
    ///
    /// Once bound, `tickOnce` polls this handler, routes the event through
    /// `processInputEvent`, and applies resize events through the active resize
    /// binding before listeners run. The default poll timeout is zero so
    /// `tickOnce` stays non-blocking.
    pub fn bindInput(self: *Application, input_handler: *input.InputHandler) void {
        self.input_binding = .{ .handler = input_handler };
    }

    /// Configure how long `tickOnce` may wait for bound terminal input.
    pub fn setInputPollTimeout(self: *Application, timeout_ms: u64) void {
        self.input_binding.poll_timeout_ms = timeout_ms;
    }

    /// Remove application-owned input polling.
    pub fn unbindInput(self: *Application) void {
        self.input_binding = .{};
        self.input_polled_before_tick = false;
    }

    fn pollInputOnceInternal(self: *Application) !?input.Event {
        const input_handler = self.input_binding.handler orelse return null;
        const input_event = try input_handler.pollEvent(self.input_binding.poll_timeout_ms) orelse return null;
        try self.processInputEvent(input_event);
        return input_event;
    }

    /// Poll the bound input handler once and process the event if one is ready.
    ///
    /// Calling this before `tickOnce` lets application code inspect a key or
    /// mouse event without causing `tickOnce` to poll input a second time.
    pub fn pollInputOnce(self: *Application) !?input.Event {
        if (self.input_binding.handler == null) return null;
        self.input_polled_before_tick = true;
        return try self.pollInputOnceInternal();
    }

    /// Apply a terminal size to bound rendering/layout state.
    pub fn handleResize(self: *Application, width: u16, height: u16) !layout.Size {
        if (self.resize_binding.renderer) |renderer_ptr| {
            if (renderer_ptr.back.width != width or renderer_ptr.back.height != height) {
                try renderer_ptr.resize(width, height);
            }
        }

        if (self.resize_binding.reflow) |reflow_ptr| {
            return try reflow_ptr.handleResize(width, height);
        }

        if (self.root) |root| {
            try root.widget.layout(layout.Rect.init(0, 0, width, height));
            return layout.Size.init(width, height);
        }

        return layout.Size.init(width, height);
    }

    /// Attach a stylesheet for CSS-like widget styling.
    pub fn setStyleSheet(self: *Application, sheet: ?*widget.css.StyleSheet) void {
        self.style_sheet = sheet;
        self.applyStyleContext();
    }

    /// Attach a theme to resolve stylesheet role() references.
    pub fn setStyleTheme(self: *Application, theme_value: widget.theme.Theme) void {
        self.style_theme = theme_value;
        self.applyStyleContext();
    }

    fn applyStyleContext(self: *Application) void {
        if (self.root) |root| {
            widget.Widget.applyStyleContext(&root.widget, self.style_sheet, self.style_theme);
        }
    }

    fn applyAccessibilityContext(self: *Application) void {
        if (self.root) |root| {
            if (self.accessibility) |manager| {
                widget.Widget.applyAccessibilityContext(&root.widget, manager, registerAccessibleNodeCallback, updateAccessibleBoundsCallback);
            } else {
                widget.Widget.applyAccessibilityContext(&root.widget, null, null, null);
            }
        }
    }

    fn registerAccessibleNodeCallback(ctx: ?*anyopaque, w: *widget.Widget) void {
        const manager = @as(*accessibility.Manager, @ptrCast(@alignCast(ctx orelse return)));
        if (w.accessibility_role == 0 and w.accessibility_name.len == 0 and w.accessibility_description.len == 0) {
            return;
        }
        const role: accessibility.Role = @enumFromInt(w.accessibility_role);
        manager.registerNodeBestEffort(accessibility.AccessibleNode{
            .widget_ptr = w,
            .role = role,
            .name = w.accessibility_name,
            .description = w.accessibility_description,
            .bounds = w.rect,
        });
    }

    fn updateAccessibleBoundsCallback(ctx: ?*anyopaque, w: *widget.Widget, rect: @import("../layout/layout.zig").Rect) void {
        const manager = @as(*accessibility.Manager, @ptrCast(@alignCast(ctx orelse return)));
        manager.updateBounds(w, rect);
    }

    /// Process input, timers, and animations once without blocking.
    pub fn tickOnce(self: *Application) !void {
        if (self.root == null) {
            return error.NoRootWidget;
        }

        self.ensureShortcutHook();
        self.collectReleasedBackgroundTasks();

        if (self.input_polled_before_tick) {
            self.input_polled_before_tick = false;
        } else {
            _ = try self.pollInputOnceInternal();
        }

        if (self.memory_manager) |manager| {
            manager.resetFrame();
        }

        const frame_allocator = self.frameAllocator();
        if (self.use_propagation) {
            try self.event_queue.processEventsWithPropagation(frame_allocator);
        } else {
            try self.event_queue.processEvents();
        }

        const now_ms: u64 = @intCast(compat.nowMillis());
        const delta = if (self.last_frame_ms == 0) 0 else now_ms - self.last_frame_ms;
        self.animator.tick(delta);
        self.timer_manager.tick(now_ms);
        self.last_frame_ms = now_ms;
        self.collectReleasedBackgroundTasks();
    }

    /// Poll until a deadline, useful when embedding zit into an external loop.
    pub fn pollUntil(self: *Application, deadline_ms: u64) !void {
        if (!self.running) self.running = true;
        while (true) {
            const now_ms: u64 = @intCast(compat.nowMillis());
            if (now_ms >= deadline_ms or !self.running) break;
            try self.tickOnce();
            compat.sleepMillis(event_loop_sleep_ms);
        }
    }

    /// Start the application event loop
    pub fn run(self: *Application) !void {
        if (self.root == null) {
            return error.NoRootWidget;
        }

        self.running = true;
        self.last_frame_ms = @as(u64, @intCast(compat.nowMillis()));

        while (self.running) {
            try self.tickOnce();

            // Yield to allow other tasks to run
            compat.sleepMillis(event_loop_sleep_ms);
        }
    }

    /// Start the application event loop asynchronously
    pub fn runAsync(self: *Application, callback: ?*const fn () void) !void {
        if (self.root == null) {
            return error.NoRootWidget;
        }

        self.running = true;
        self.last_frame_ms = @as(u64, @intCast(compat.nowMillis()));

        // Start processing in a separate thread
        var thread = try std.Thread.spawn(.{}, struct {
            fn threadFn(app: *Application, cb: ?*const fn () void) !void {
                while (app.running) {
                    try app.tickOnce();
                    compat.sleepMillis(event_loop_sleep_ms);
                }

                if (cb != null) {
                    cb.?();
                }
            }
        }.threadFn, .{ self, callback });

        thread.detach();
    }

    /// Stop the application event loop
    pub fn stop(self: *Application) void {
        self.running = false;
    }

    /// Add an event listener
    pub fn addEventListener(self: *Application, event_type: EventType, listener: EventListenerFn, user_data: ?*anyopaque) !u32 {
        return try self.event_queue.addEventListener(event_type, listener, user_data);
    }

    /// Remove an event listener by ID
    pub fn removeEventListener(self: *Application, id: u32) bool {
        return self.event_queue.removeEventListener(id);
    }

    /// Route debug hooks (event tracing, etc.) into the event queue.
    pub fn setDebugHooks(self: *Application, hooks: DebugHooks) void {
        self.event_queue.setDebugHooks(hooks);
    }

    fn ensureShortcutHook(self: *Application) void {
        if (self.event_queue.preprocessor == null) {
            self.event_queue.setPreprocessor(.{ .handler = Application.shortcutPreprocessor, .ctx = self });
        }
    }

    fn shortcutPreprocessor(ev: *Event, ctx: ?*anyopaque) bool {
        const app = @as(*Application, @ptrCast(@alignCast(ctx.?)));
        return app.shortcut_registry.handle(ev);
    }

    /// Register a global or focused-only shortcut.
    pub fn registerShortcut(self: *Application, combo: KeyCombo, description: []const u8, callback: ShortcutCallback, user_data: ?*anyopaque, scope: ShortcutScope) !u32 {
        self.ensureShortcutHook();
        return try self.shortcut_registry.register(combo, description, callback, user_data, scope);
    }

    /// Remove a previously registered shortcut.
    pub fn unregisterShortcut(self: *Application, id: u32) bool {
        return self.shortcut_registry.unregister(id);
    }

    /// Materialize summaries suitable for a help overlay. Caller owns the slices.
    pub fn shortcutSummaries(self: *Application, allocator: std.mem.Allocator) ![]ShortcutSummary {
        return try self.shortcut_registry.summaries(allocator);
    }

    /// Request focus for a widget
    pub fn requestFocus(self: *Application, target_widget: *widget.Widget) !bool {
        self.syncInternalPointers();
        return try self.focus_manager.requestFocus(target_widget);
    }

    /// Add an animation to the application animator
    pub fn addAnimation(self: *Application, spec: animation.AnimationSpec) !animation.AnimationHandle {
        return try self.animator.add(spec);
    }

    /// Cancel an animation by handle
    pub fn cancelAnimation(self: *Application, handle: animation.AnimationHandle) bool {
        return self.animator.cancel(handle);
    }

    /// Configure whether processInputEvent automatically maps mouse press/move/release
    /// events to drag lifecycle events. Disable this when an app starts payload
    /// drags explicitly from selected hit targets.
    pub fn setAutomaticDrag(self: *Application, enabled: bool) void {
        if (!enabled and self.automatic_drag and self.drag_manager.active) {
            self.drag_manager.cancel();
        }
        self.automatic_drag = enabled;
    }

    /// Begin a drag gesture and emit the start event.
    pub fn beginDrag(self: *Application, source: ?*widget.Widget, x: u16, y: u16, button: u8, payload: DragPayload) !void {
        self.syncInternalPointers();
        try self.drag_manager.begin(source, x, y, button, payload);
    }

    /// Update an in-flight drag gesture.
    pub fn updateDrag(self: *Application, x: u16, y: u16, target: ?*widget.Widget) !void {
        self.syncInternalPointers();
        try self.drag_manager.update(x, y, target);
    }

    /// Finish a drag gesture and emit drop events.
    pub fn endDrag(self: *Application, x: u16, y: u16, drop_target: ?*widget.Widget) !void {
        self.syncInternalPointers();
        try self.drag_manager.end(x, y, drop_target);
    }

    /// Register a widget as a drop target.
    pub fn registerDropTarget(self: *Application, target: DropTarget) !void {
        try self.drag_manager.registerTarget(target);
    }

    /// Remove a registered drop target.
    pub fn unregisterDropTarget(self: *Application, target: *widget.Widget) bool {
        return self.drag_manager.unregisterTarget(target);
    }

    /// Hit-test registered drop targets at the given coordinates.
    pub fn hitTestDropTarget(self: *Application, x: u16, y: u16) ?*DropTarget {
        return self.drag_manager.hitTest(x, y);
    }

    /// Schedule a timer callback
    pub fn scheduleTimer(self: *Application, delay_ms: u64, repeat_ms: ?u64, callback: timer.TimerCallback, ctx: ?*anyopaque) !timer.TimerHandle {
        const now_ms: u64 = @intCast(compat.nowMillis());
        if (self.last_frame_ms == 0) self.last_frame_ms = now_ms;
        return try self.timer_manager.schedule(now_ms, delay_ms, repeat_ms, callback, ctx);
    }

    /// Cancel a timer
    pub fn cancelTimer(self: *Application, handle: timer.TimerHandle) bool {
        return self.timer_manager.cancel(handle);
    }

    /// Start a background task that will emit a custom event on completion.
    pub fn startBackgroundTask(self: *Application, work: BackgroundTaskFn, ctx: ?*anyopaque, target: ?*widget.Widget) !BackgroundTaskHandle {
        const task = try self.allocator.create(BackgroundTask);
        task.* = BackgroundTask{};
        errdefer self.allocator.destroy(task);

        const worker = struct {
            fn run(task_ptr: *BackgroundTask, queue: *EventQueue, allocator: std.mem.Allocator, work_fn: BackgroundTaskFn, ctx_ptr: ?*anyopaque, target_widget: ?*widget.Widget) void {
                defer task_ptr.completed.store(true, .release);

                var status: BackgroundTaskStatus = .success;
                var message: []const u8 = "";
                const stop_flag = &task_ptr.flag;

                work_fn(stop_flag, ctx_ptr) catch |err| {
                    status = .failed;
                    message = std.fmt.allocPrint(allocator, "{s}", .{@errorName(err)}) catch "";
                };

                if (stop_flag.load(.acquire)) {
                    status = .cancelled;
                }

                _ = enqueueBackgroundTaskResult(queue, allocator, status, message, target_widget);
            }
        }.run;

        task.thread = try std.Thread.spawn(.{}, worker, .{ task, &self.event_queue, self.allocator, work, ctx, target });
        errdefer {
            task.flag.store(true, .release);
            if (task.thread) |thread| thread.join();
            self.allocator.destroy(task);
        }

        try self.background_tasks.append(self.allocator, task);

        return BackgroundTaskHandle{ .flag = &task.flag, .task = task };
    }

    /// Request cancellation for a running background task.
    pub fn cancelBackgroundTask(self: *Application, handle: BackgroundTaskHandle) void {
        _ = self;
        handle.flag.store(true, .release);
    }

    /// Mark a background task handle as no longer needed and collect it after completion.
    pub fn releaseBackgroundTaskHandle(self: *Application, handle: BackgroundTaskHandle) void {
        const task_ptr = handle.task orelse {
            self.allocator.destroy(handle.flag);
            return;
        };
        const task = @as(*BackgroundTask, @ptrCast(@alignCast(task_ptr)));
        task.released = true;
        self.collectReleasedBackgroundTasks();
    }

    fn collectReleasedBackgroundTasks(self: *Application) void {
        var i: usize = 0;
        while (i < self.background_tasks.items.len) {
            const task = self.background_tasks.items[i];
            if (task.released and task.completed.load(.acquire)) {
                self.joinAndDestroyBackgroundTask(i);
                continue;
            }
            i += 1;
        }
    }

    fn joinAndDestroyBackgroundTask(self: *Application, index: usize) void {
        const task = self.background_tasks.orderedRemove(index);
        if (task.thread) |thread| {
            thread.join();
            task.thread = null;
        }
        self.allocator.destroy(task);
    }

    fn cancelAndJoinBackgroundTasks(self: *Application) void {
        for (self.background_tasks.items) |task| {
            task.flag.store(true, .release);
        }

        while (self.background_tasks.items.len > 0) {
            self.joinAndDestroyBackgroundTask(self.background_tasks.items.len - 1);
        }
    }

    /// Enable accessibility support and wire into focus events
    pub fn enableAccessibility(self: *Application) !void {
        if (self.accessibility != null) return;
        const manager = try self.allocator.create(accessibility.Manager);
        manager.* = accessibility.Manager.init(self.allocator);
        self.accessibility = manager;
        self.focus_manager.accessibility = manager;
        self.applyAccessibilityContext();
    }

    /// Disable accessibility and free resources
    pub fn disableAccessibility(self: *Application) void {
        if (self.accessibility) |manager| {
            manager.deinit();
            self.allocator.destroy(manager);
        }
        self.accessibility = null;
        self.focus_manager.accessibility = null;
        self.applyAccessibilityContext();
    }

    /// Register an accessible node for a widget
    pub fn registerAccessibleNode(self: *Application, node: accessibility.AccessibleNode) !void {
        if (self.accessibility) |manager| {
            try manager.registerNode(node);
        }
    }

    /// Update accessibility bounds for a widget
    pub fn updateAccessibleBounds(self: *Application, w: *widget.Widget, rect: @import("../layout/layout.zig").Rect) void {
        if (self.accessibility) |manager| {
            manager.updateBounds(w, rect);
        }
    }

    /// Number of non-fatal accessibility hook failures since the manager was enabled.
    pub fn accessibilityBestEffortFailureCount(self: *const Application) usize {
        return if (self.accessibility) |manager| manager.bestEffortFailureCount() else 0;
    }

    /// Last non-fatal accessibility hook failure, if accessibility is enabled.
    pub fn lastAccessibilityBestEffortFailure(self: *const Application) ?accessibility.BestEffortFailure {
        return if (self.accessibility) |manager| manager.lastBestEffortFailure() else null;
    }

    /// Process an input event
    pub fn processInputEvent(self: *Application, input_event: input.Event) !void {
        self.syncInternalPointers();
        switch (input_event) {
            .resize => |resize_event| {
                _ = try self.handleResize(resize_event.width, resize_event.height);
            },
            else => {},
        }

        if (self.root == null) {
            return;
        }

        const target: *widget.Widget = &self.root.?.widget;
        const event = fromInputEvent(input_event, target);
        try self.event_queue.pushEvent(event);

        if (self.automatic_drag) {
            switch (input_event) {
                .mouse => |mouse_event| switch (mouse_event.action) {
                    .press => {
                        try self.beginDrag(target, mouse_event.x, mouse_event.y, mouse_event.button, .{});
                    },
                    .release => {
                        try self.endDrag(mouse_event.x, mouse_event.y, target);
                    },
                    .move => {
                        try self.updateDrag(mouse_event.x, mouse_event.y, target);
                    },
                    .scroll_up, .scroll_down => {},
                },
                else => {},
            }
        }
    }

    /// Set whether to use event propagation
    pub fn setUsePropagation(self: *Application, use_prop: bool) void {
        self.use_propagation = use_prop;
    }
};

test "fromInputEvent converts key events with modifiers" {
    const mods = input.KeyModifiers.init(true, false, true);
    const input_event = input.Event{ .key = input.KeyEvent.init('k', mods) };
    const event = fromInputEvent(input_event, null);

    try std.testing.expectEqual(EventType.key_press, event.type);
    try std.testing.expect(event.target == null);
    try std.testing.expectEqual(@as(u21, 'k'), event.data.key_press.key);
    try std.testing.expectEqual(mods, event.data.key_press.modifiers);
    try std.testing.expectEqual(@as(u32, 0), event.data.key_press.raw);
}

test "fromInputEvent converts mouse press/release/move" {
    const press_input = input.Event{ .mouse = input.MouseEvent.init(.press, 10, 20, 1, 0) };
    const press_event = fromInputEvent(press_input, null);
    try std.testing.expectEqual(EventType.mouse_press, press_event.type);
    try std.testing.expectEqual(@as(u16, 10), press_event.data.mouse_press.x);
    try std.testing.expectEqual(@as(u16, 20), press_event.data.mouse_press.y);
    try std.testing.expectEqual(@as(u8, 1), press_event.data.mouse_press.button);
    try std.testing.expectEqual(@as(u8, 1), press_event.data.mouse_press.clicks);
    try std.testing.expectEqual(input.KeyModifiers{}, press_event.data.mouse_press.modifiers);

    const release_input = input.Event{ .mouse = input.MouseEvent.init(.release, 11, 21, 2, 0) };
    const release_event = fromInputEvent(release_input, null);
    try std.testing.expectEqual(EventType.mouse_release, release_event.type);
    try std.testing.expectEqual(@as(u16, 11), release_event.data.mouse_release.x);
    try std.testing.expectEqual(@as(u16, 21), release_event.data.mouse_release.y);
    try std.testing.expectEqual(@as(u8, 2), release_event.data.mouse_release.button);
    try std.testing.expectEqual(@as(u8, 1), release_event.data.mouse_release.clicks);
    try std.testing.expectEqual(input.KeyModifiers{}, release_event.data.mouse_release.modifiers);

    const move_input = input.Event{ .mouse = input.MouseEvent.init(.move, 12, 22, 3, 0) };
    const move_event = fromInputEvent(move_input, null);
    try std.testing.expectEqual(EventType.mouse_move, move_event.type);
    try std.testing.expectEqual(@as(u16, 12), move_event.data.mouse_move.x);
    try std.testing.expectEqual(@as(u16, 22), move_event.data.mouse_move.y);
    try std.testing.expectEqual(@as(u8, 3), move_event.data.mouse_move.button);
    try std.testing.expectEqual(@as(u8, 0), move_event.data.mouse_move.clicks);
    try std.testing.expectEqual(input.KeyModifiers{}, move_event.data.mouse_move.modifiers);
}

test "fromInputEvent converts mouse wheel scroll events" {
    const up_input = input.Event{ .mouse = input.MouseEvent.init(.scroll_up, 5, 6, 0, -200) };
    const up_event = fromInputEvent(up_input, null);
    try std.testing.expectEqual(EventType.mouse_wheel, up_event.type);
    try std.testing.expectEqual(@as(u16, 5), up_event.data.mouse_wheel.x);
    try std.testing.expectEqual(@as(u16, 6), up_event.data.mouse_wheel.y);
    try std.testing.expectEqual(@as(i8, 0), up_event.data.mouse_wheel.dx);
    try std.testing.expectEqual(@as(i8, -127), up_event.data.mouse_wheel.dy);
    try std.testing.expectEqual(input.KeyModifiers{}, up_event.data.mouse_wheel.modifiers);

    const down_input = input.Event{ .mouse = input.MouseEvent.init(.scroll_down, 7, 8, 0, 200) };
    const down_event = fromInputEvent(down_input, null);
    try std.testing.expectEqual(EventType.mouse_wheel, down_event.type);
    try std.testing.expectEqual(@as(u16, 7), down_event.data.mouse_wheel.x);
    try std.testing.expectEqual(@as(u16, 8), down_event.data.mouse_wheel.y);
    try std.testing.expectEqual(@as(i8, 0), down_event.data.mouse_wheel.dx);
    try std.testing.expectEqual(@as(i8, 127), down_event.data.mouse_wheel.dy);
    try std.testing.expectEqual(input.KeyModifiers{}, down_event.data.mouse_wheel.modifiers);
}

test "fromInputEvent converts resize events" {
    const input_event = input.Event{ .resize = input.ResizeEvent.init(80, 24) };
    const event = fromInputEvent(input_event, null);

    try std.testing.expectEqual(EventType.resize, event.type);
    try std.testing.expectEqual(@as(u16, 80), event.data.resize.width);
    try std.testing.expectEqual(@as(u16, 24), event.data.resize.height);
}

test "fromInputEvent converts unknown events to custom" {
    const input_event = input.Event{ .unknown = {} };
    const event = fromInputEvent(input_event, null);

    try std.testing.expectEqual(EventType.custom, event.type);
    try std.testing.expectEqual(@as(u32, 0), event.data.custom.id);
    try std.testing.expect(event.data.custom.data == null);
    try std.testing.expect(event.data.custom.destructor == null);
    try std.testing.expectEqualStrings("input.unknown", event.data.custom.type_name.?);
    try std.testing.expect(event.data.custom.filter_fn == null);
}

test "application resize binding updates renderer reflow and queues resize event" {
    const alloc = std.testing.allocator;
    var app = Application.init(alloc);
    defer app.deinit();

    var root = try widget.Container.init(alloc);
    defer root.deinit();
    app.setRoot(root);

    var renderer_instance = try render.Renderer.init(alloc, 20, 10);
    defer renderer_instance.deinit();

    var reflow = layout.ReflowManager.init();
    reflow.setRoot(root.widget.asLayoutElement());
    app.bindResize(&renderer_instance, &reflow);

    try app.processInputEvent(input.Event{ .resize = input.ResizeEvent.init(100, 30) });

    try std.testing.expectEqual(@as(u16, 100), renderer_instance.back.width);
    try std.testing.expectEqual(@as(u16, 30), renderer_instance.back.height);
    try std.testing.expectEqual(@as(u16, 100), reflow.constraints.max_width);
    try std.testing.expectEqual(@as(u16, 30), reflow.constraints.max_height);
    try std.testing.expectEqual(@as(u16, 100), root.widget.rect.width);
    try std.testing.expectEqual(@as(u16, 30), root.widget.rect.height);

    const queued = app.event_queue.popFront().?;
    try std.testing.expectEqual(EventType.resize, queued.type);
    try std.testing.expectEqual(@as(u16, 100), queued.data.resize.width);
    try std.testing.expectEqual(@as(u16, 30), queued.data.resize.height);
}

test "application resize binding works without a root widget" {
    const alloc = std.testing.allocator;
    var app = Application.init(alloc);
    defer app.deinit();

    var renderer_instance = try render.Renderer.init(alloc, 12, 5);
    defer renderer_instance.deinit();
    app.bindResize(&renderer_instance, null);

    try app.processInputEvent(input.Event{ .resize = input.ResizeEvent.init(64, 18) });

    try std.testing.expectEqual(@as(u16, 64), renderer_instance.back.width);
    try std.testing.expectEqual(@as(u16, 18), renderer_instance.back.height);
    try std.testing.expect(app.event_queue.popFront() == null);
}

test "application input binding stores non-blocking poll configuration" {
    const alloc = std.testing.allocator;
    var app = Application.init(alloc);
    defer app.deinit();

    try std.testing.expect(try app.pollInputOnce() == null);
    try std.testing.expect(!app.input_polled_before_tick);

    var term = @import("../terminal/terminal.zig").Terminal{
        .stdin_fd = std.Io.File.stdin().handle,
        .stdout_fd = std.Io.File.stdout().handle,
        .original_termios = .none,
        .original_stdin_flags = null,
        .width = 80,
        .height = 24,
        .is_raw_mode = false,
        .is_cursor_visible = true,
        .is_mouse_enabled = false,
        .allocator = alloc,
        .capabilities = .{},
        .is_sync_output = false,
        .is_alt_screen = false,
        .is_bracketed_paste = false,
        .is_kitty_keyboard_enabled = false,
        .windows_vt_enabled = true,
        .sigwinch_registered = false,
    };
    var input_handler = input.InputHandler.init(alloc, &term);

    app.bindInput(&input_handler);
    try std.testing.expect(app.input_binding.handler == &input_handler);
    try std.testing.expectEqual(@as(u64, 0), app.input_binding.poll_timeout_ms);

    app.setInputPollTimeout(7);
    try std.testing.expectEqual(@as(u64, 7), app.input_binding.poll_timeout_ms);

    app.input_polled_before_tick = true;
    app.unbindInput();
    try std.testing.expect(app.input_binding.handler == null);
    try std.testing.expectEqual(@as(u64, 0), app.input_binding.poll_timeout_ms);
    try std.testing.expect(!app.input_polled_before_tick);
}

test "application records automatic accessibility registration failures" {
    const alloc = std.testing.allocator;
    var app = Application.init(alloc);
    defer app.deinit();
    try app.enableAccessibility();

    const original_allocator = app.accessibility.?.allocator;
    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 0 });
    app.accessibility.?.allocator = failing.allocator();

    var root = try widget.Container.init(alloc);
    defer root.deinit();
    app.setRoot(root);

    app.accessibility.?.allocator = original_allocator;
    try std.testing.expectEqual(@as(usize, 1), app.accessibilityBestEffortFailureCount());
    const failure = app.lastAccessibilityBestEffortFailure().?;
    try std.testing.expectEqual(accessibility.BestEffortOperation.register_node, failure.operation);
    try std.testing.expectEqual(error.OutOfMemory, failure.err);
}

test "application automatic drag can be disabled for explicit payload drags" {
    const alloc = std.testing.allocator;
    var app = Application.init(alloc);
    defer app.deinit();

    var root = try widget.Container.init(alloc);
    defer root.deinit();
    app.setRoot(root);

    try std.testing.expect(app.automatic_drag);
    app.setAutomaticDrag(false);
    try std.testing.expect(!app.automatic_drag);

    try app.processInputEvent(input.Event{ .mouse = input.MouseEvent.init(.press, 1, 2, 1, 0) });
    try std.testing.expect(!app.drag_manager.active);

    const queued = app.event_queue.popFront().?;
    try std.testing.expectEqual(EventType.mouse_press, queued.type);
    try std.testing.expectEqual(@as(u16, 1), queued.data.mouse_press.x);
    try std.testing.expectEqual(@as(u16, 2), queued.data.mouse_press.y);

    app.setAutomaticDrag(true);
    try app.processInputEvent(input.Event{ .mouse = input.MouseEvent.init(.press, 3, 4, 1, 0) });
    try std.testing.expect(app.drag_manager.active);
}

test "application unwatchFile unregisters manager-owned watcher" {
    const alloc = std.testing.allocator;
    var app = Application.init(alloc);
    defer app.deinit();

    const watcher = try app.watchFile("definitely-missing-zit-app-watch-file.txt", null);
    try std.testing.expect(app.io_manager != null);
    try std.testing.expectEqual(@as(usize, 1), app.io_manager.?.file_watchers.items.len);

    try std.testing.expect(app.unwatchFile(watcher));
    try std.testing.expectEqual(@as(usize, 0), app.io_manager.?.file_watchers.items.len);
    try std.testing.expect(!app.unwatchFile(watcher));
}

test "application disconnectFromServer unregisters manager-owned connection" {
    const alloc = std.testing.allocator;
    var app = Application.init(alloc);
    defer app.deinit();

    const connection = try app.connectToServer("127.0.0.1", 8080, null);
    try std.testing.expect(app.io_manager != null);
    try std.testing.expectEqual(@as(usize, 1), app.io_manager.?.network_connections.items.len);

    try std.testing.expect(app.disconnectFromServer(connection));
    try std.testing.expectEqual(@as(usize, 0), app.io_manager.?.network_connections.items.len);
    try std.testing.expect(!app.disconnectFromServer(connection));
}

test "background task result frees message when result allocation fails" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const alloc = failing.allocator();
    const message = try alloc.dupe(u8, "background failed");

    failing.fail_index = failing.alloc_index;

    try std.testing.expectError(error.OutOfMemory, createBackgroundTaskResult(alloc, .failed, message));
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
}

test "background task result enqueue cleans up when event allocation fails" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const alloc = failing.allocator();
    var queue = EventQueue.init(alloc);
    defer queue.deinit();

    const message = try alloc.dupe(u8, "background failed");
    failing.fail_index = failing.alloc_index + 1;

    try std.testing.expect(!enqueueBackgroundTaskResult(&queue, alloc, .failed, message, null));
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectEqual(@as(usize, 0), queue.queue.items.len);
    try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
}

test "background tasks emit completion events" {
    const alloc = std.testing.allocator;
    var app = Application.init(alloc);
    defer app.deinit();

    var root = try widget.Container.init(alloc);
    defer root.deinit();
    app.setRoot(root);

    var completed = false;
    var announcement_seen = false;

    const Listener = struct {
        pub var seen: *bool = undefined;
        pub fn on(ev: *Event) bool {
            if (ev.type != .custom) return false;
            if (ev.data.custom.id != BACKGROUND_TASK_EVENT_ID) return false;
            seen.* = true;
            return true;
        }
    };
    Listener.seen = &announcement_seen;
    _ = try app.addEventListener(.custom, Listener.on, null);

    const Worker = struct {
        fn run(_: *std.atomic.Value(bool), ctx: ?*anyopaque) anyerror!void {
            const flag = @as(*bool, @ptrCast(@alignCast(ctx.?)));
            flag.* = true;
        }
    };

    const handle = try app.startBackgroundTask(Worker.run, @ptrCast(&completed), null);

    var attempts: usize = 0;
    while (attempts < 50 and !announcement_seen) : (attempts += 1) {
        compat.sleepMillis(2);
        try app.tickOnce();
    }

    try std.testing.expect(completed);
    try std.testing.expect(announcement_seen);
    app.releaseBackgroundTaskHandle(handle);
}

test "application deinit cancels and joins running background tasks" {
    const alloc = std.testing.allocator;
    var app = Application.init(alloc);

    var stopped = std.atomic.Value(bool).init(false);
    const Worker = struct {
        fn run(stop_flag: *std.atomic.Value(bool), ctx: ?*anyopaque) anyerror!void {
            const stopped_flag = @as(*std.atomic.Value(bool), @ptrCast(@alignCast(ctx.?)));
            while (!stop_flag.load(.acquire)) {
                compat.sleepMillis(1);
            }
            stopped_flag.store(true, .release);
        }
    };

    const handle = try app.startBackgroundTask(Worker.run, @ptrCast(&stopped), null);
    try std.testing.expectEqual(@as(usize, 1), app.background_tasks.items.len);

    app.releaseBackgroundTaskHandle(handle);
    try std.testing.expectEqual(@as(usize, 1), app.background_tasks.items.len);

    app.cancelAndJoinBackgroundTasks();
    try std.testing.expect(stopped.load(.acquire));
    try std.testing.expectEqual(@as(usize, 0), app.background_tasks.items.len);

    app.deinit();
}
