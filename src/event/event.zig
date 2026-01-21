const std = @import("std");
const input = @import("../input/input.zig");
pub const widget = @import("../widget/widget.zig");
const animation = @import("../widget/animation.zig");
const timer = @import("timer.zig");
const accessibility = @import("../widget/accessibility.zig");
const render = @import("../render/render.zig");
const layout = @import("../layout/layout.zig");

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
            .timestamp = std.time.milliTimestamp(),
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

/// Invoke work on a separate thread and monitor for cancellation.
pub const BackgroundTaskFn = *const fn (stop_flag: *std.atomic.Value(bool), ctx: ?*anyopaque) anyerror!void;
pub const BackgroundTaskHandle = struct { flag: *std.atomic.Value(bool) };

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

inline fn traceEvent(hooks: DebugHooks, ev: *Event, phase: Event.PropagationPhase, node: ?*widget.Widget) void {
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
        self.next_id += 1;

        try self.listeners.append(self.allocator, EventListener{
            .event_type = event_type,
            .listener = listener,
            .user_data = user_data,
            .id = id,
        });

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
    lock: std.Thread.Mutex = .{},
    /// Event dispatcher
    dispatcher: EventDispatcher,
    /// Allocator for event queue operations
    allocator: std.mem.Allocator,
    /// Optional debug hooks
    debug_hooks: DebugHooks = .{},
    /// Reusable buffer for propagation paths to avoid per-event allocations
    path_scratch: std.ArrayListUnmanaged(*widget.Widget) = .{},
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
                continue;
            }
            _ = self.dispatcher.dispatchEvent(&event);
            event.setPhase(.target);
            traceEvent(self.debug_hooks, &event, .target, event.target);

            // Clean up custom event data if needed
            if (event.type == .custom) {
                const custom_data = event.data.custom;
                if (custom_data.destructor != null and custom_data.data != null) {
                    custom_data.destructor.?(custom_data.data.?);
                }
            }
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

        // Set new focus
        const previous = self.focused_widget;
        self.focused_widget = target_widget;

        // Add to focus history
        try self.focus_history.append(self.allocator, target_widget);
        if (self.focus_history.items.len > focus_history_limit) {
            _ = self.focus_history.orderedRemove(0);
        }

        if (self.accessibility) |acc| {
            _ = acc.announceFocus(target_widget) catch {};
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

    pub fn init(queue: *EventQueue, allocator: std.mem.Allocator) DragManager {
        return DragManager{
            .queue = queue,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DragManager) void {
        self.targets.deinit(self.allocator);
        self.cleanupPayload();
    }

    pub fn begin(self: *DragManager, source: ?*widget.Widget, x: u16, y: u16, button: u8, payload: DragPayload) !void {
        if (self.active) self.cancel();
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
        self.last_x = x;
        self.last_y = y;
        const resolved = self.resolveTarget(x, y, target);
        try self.queue.createDragEvent(.drag_update, self.eventData(x, y, resolved.accepted), resolved.widget);
    }

    pub fn end(self: *DragManager, x: u16, y: u16, drop_target: ?*widget.Widget) !void {
        if (!self.active) return;
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
        self.cleanupPayload();
        self.active = false;
    }

    pub fn cancel(self: *DragManager) void {
        if (!self.active) return;
        self.cleanupPayload();
        self.active = false;
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
        return x >= rect.x and y >= rect.y and x < rect.x + rect.width and y < rect.y + rect.height;
    }
};

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
        self.next_id += 1;
        const desc_copy = try self.allocator.dupe(u8, description);

        const idx = self.shortcuts.items.len;
        try self.shortcuts.append(self.allocator, ShortcutEntry{
            .id = id,
            .combo = combo,
            .description = desc_copy,
            .callback = callback,
            .user_data = user_data,
            .scope = scope,
        });
        try self.lookup.put(combo, idx);
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
        for (self.shortcuts.items, 0..) |entry, idx| {
            self.lookup.put(entry.combo, idx) catch {};
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
            const desc_copy = try allocator.dupe(u8, entry.description);
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

    var order = std.ArrayList([]const u8).empty;
    defer order.deinit(alloc);

    const Logger = struct {
        pub var log: *std.ArrayList([]const u8) = undefined;
        pub var root_ptr: *widget.Widget = undefined;
        pub var branch_ptr: *widget.Widget = undefined;
        pub var leaf_ptr: *widget.Widget = undefined;
        pub var allocator: std.mem.Allocator = undefined;

        pub fn listener(ev: *Event) bool {
            const current = ev.current_target orelse return false;
            const label: []const u8 = if (current == root_ptr)
                "root"
            else if (current == branch_ptr)
                "branch"
            else
                "leaf";
            log.append(allocator, label) catch unreachable;
            return false;
        }
    };

    Logger.log = &order;
    Logger.root_ptr = &root.widget;
    Logger.branch_ptr = &branch.widget;
    Logger.leaf_ptr = &leaf.widget;
    Logger.allocator = alloc;
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

    try std.testing.expectEqual(@as(usize, 5), order.items.len);
    try std.testing.expect(std.mem.eql(u8, "root", order.items[0]));
    try std.testing.expect(std.mem.eql(u8, "branch", order.items[1]));
    try std.testing.expect(std.mem.eql(u8, "leaf", order.items[2]));
    try std.testing.expect(std.mem.eql(u8, "branch", order.items[3]));
    try std.testing.expect(std.mem.eql(u8, "root", order.items[4]));
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

    var order = std.ArrayList([]const u8).empty;
    defer order.deinit(alloc);

    const Stopper = struct {
        pub var log: *std.ArrayList([]const u8) = undefined;
        pub var branch_ptr: *widget.Widget = undefined;
        pub var allocator: std.mem.Allocator = undefined;

        pub fn listener(ev: *Event) bool {
            const current = ev.current_target orelse return false;
            if (current == branch_ptr) {
                log.append(allocator, "branch") catch unreachable;
                ev.stopPropagation();
            } else {
                log.append(allocator, "root") catch unreachable;
            }
            return false;
        }
    };

    Stopper.log = &order;
    Stopper.branch_ptr = &branch.widget;
    Stopper.allocator = alloc;
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

    try std.testing.expectEqual(@as(usize, 2), order.items.len);
    try std.testing.expect(std.mem.eql(u8, "root", order.items[0]));
    try std.testing.expect(std.mem.eql(u8, "branch", order.items[1]));
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
    /// Global shortcut registry
    shortcut_registry: ShortcutRegistry,

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
        };

        app.focus_manager = FocusManager.init(allocator, &app.event_queue);
        app.drag_manager = DragManager.init(&app.event_queue, allocator);

        return app;
    }

    /// Clean up application resources
    pub fn deinit(self: *Application) void {
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

    /// Connect to a network server
    pub fn connectToServer(self: *Application, address: []const u8, port: u16, target: ?*widget.Widget) !*@import("io_events.zig").NetworkContext {
        if (self.io_manager == null) {
            try self.initIoManager();
        }

        return try self.io_manager.?.connectToServer(address, port, target);
    }

    /// Set the root widget
    pub fn setRoot(self: *Application, root: *widget.Container) void {
        self.root = root;
    }

    /// Process input, timers, and animations once without blocking.
    pub fn tickOnce(self: *Application) !void {
        if (self.root == null) {
            return error.NoRootWidget;
        }

        self.ensureShortcutHook();

        if (self.use_propagation) {
            try self.event_queue.processEventsWithPropagation(self.allocator);
        } else {
            try self.event_queue.processEvents();
        }

        const now_ms: u64 = @intCast(std.time.milliTimestamp());
        const delta = if (self.last_frame_ms == 0) 0 else now_ms - self.last_frame_ms;
        self.animator.tick(delta);
        self.timer_manager.tick(now_ms);
        self.last_frame_ms = now_ms;
    }

    /// Poll until a deadline, useful when embedding zit into an external loop.
    pub fn pollUntil(self: *Application, deadline_ms: u64) !void {
        if (!self.running) self.running = true;
        while (true) {
            const now_ms: u64 = @intCast(std.time.milliTimestamp());
            if (now_ms >= deadline_ms or !self.running) break;
            try self.tickOnce();
            std.Thread.sleep(std.time.ns_per_ms * event_loop_sleep_ms);
        }
    }

    /// Start the application event loop
    pub fn run(self: *Application) !void {
        if (self.root == null) {
            return error.NoRootWidget;
        }

        self.running = true;
        self.last_frame_ms = @as(u64, @intCast(std.time.milliTimestamp()));

        while (self.running) {
            try self.tickOnce();

            // Yield to allow other tasks to run
            std.Thread.sleep(std.time.ns_per_ms * event_loop_sleep_ms);
        }
    }

    /// Start the application event loop asynchronously
    pub fn runAsync(self: *Application, callback: ?*const fn () void) !void {
        if (self.root == null) {
            return error.NoRootWidget;
        }

        self.running = true;
        self.last_frame_ms = @as(u64, @intCast(std.time.milliTimestamp()));

        // Start processing in a separate thread
        var thread = try std.Thread.spawn(.{}, struct {
            fn threadFn(app: *Application, cb: ?*const fn () void) !void {
                while (app.running) {
                    try app.tickOnce();
                    std.Thread.sleep(std.time.ns_per_ms * event_loop_sleep_ms);
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

    /// Begin a drag gesture and emit the start event.
    pub fn beginDrag(self: *Application, source: ?*widget.Widget, x: u16, y: u16, button: u8, payload: DragPayload) !void {
        try self.drag_manager.begin(source, x, y, button, payload);
    }

    /// Update an in-flight drag gesture.
    pub fn updateDrag(self: *Application, x: u16, y: u16, target: ?*widget.Widget) !void {
        try self.drag_manager.update(x, y, target);
    }

    /// Finish a drag gesture and emit drop events.
    pub fn endDrag(self: *Application, x: u16, y: u16, drop_target: ?*widget.Widget) !void {
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
        const now_ms: u64 = @intCast(std.time.milliTimestamp());
        if (self.last_frame_ms == 0) self.last_frame_ms = now_ms;
        return try self.timer_manager.schedule(now_ms, delay_ms, repeat_ms, callback, ctx);
    }

    /// Cancel a timer
    pub fn cancelTimer(self: *Application, handle: timer.TimerHandle) bool {
        return self.timer_manager.cancel(handle);
    }

    /// Start a background task that will emit a custom event on completion.
    pub fn startBackgroundTask(self: *Application, work: BackgroundTaskFn, ctx: ?*anyopaque, target: ?*widget.Widget) !BackgroundTaskHandle {
        const flag = try self.allocator.create(std.atomic.Value(bool));
        flag.* = std.atomic.Value(bool).init(false);
        errdefer self.allocator.destroy(flag);

        const worker = struct {
            fn run(stop_flag: *std.atomic.Value(bool), queue: *EventQueue, allocator: std.mem.Allocator, work_fn: BackgroundTaskFn, ctx_ptr: ?*anyopaque, target_widget: ?*widget.Widget) void {
                var status: BackgroundTaskStatus = .success;
                var message: []const u8 = "";

                work_fn(stop_flag, ctx_ptr) catch |err| {
                    status = .failed;
                    message = std.fmt.allocPrint(allocator, "{s}", .{@errorName(err)}) catch "";
                };

                if (stop_flag.load(.acquire)) {
                    status = .cancelled;
                }

                const result = allocator.create(BackgroundTaskResult) catch {
                    return;
                };

                result.* = .{ .status = status, .message = message, .allocator = allocator };

                const destructor = struct {
                    fn destroy(data: *anyopaque) void {
                        const res = @as(*BackgroundTaskResult, @ptrCast(@alignCast(data)));
                        if (res.message.len > 0) res.allocator.free(res.message);
                        res.allocator.destroy(res);
                    }
                }.destroy;

                queue.createCustomEvent(BACKGROUND_TASK_EVENT_ID, @ptrCast(result), destructor, target_widget) catch {
                    destructor(@ptrCast(result));
                };
            }
        }.run;

        const thread = try std.Thread.spawn(.{}, worker, .{ flag, &self.event_queue, self.allocator, work, ctx, target });
        thread.detach();

        return BackgroundTaskHandle{ .flag = flag };
    }

    /// Request cancellation for a running background task.
    pub fn cancelBackgroundTask(self: *Application, handle: BackgroundTaskHandle) void {
        _ = self;
        handle.flag.store(true, .release);
    }

    /// Free the stop flag associated with a background task handle once it is no longer needed.
    pub fn releaseBackgroundTaskHandle(self: *Application, handle: BackgroundTaskHandle) void {
        self.allocator.destroy(handle.flag);
    }

    /// Enable accessibility support and wire into focus events
    pub fn enableAccessibility(self: *Application) !void {
        if (self.accessibility != null) return;
        const manager = try self.allocator.create(accessibility.Manager);
        manager.* = accessibility.Manager.init(self.allocator);
        self.accessibility = manager;
        self.focus_manager.accessibility = manager;
    }

    /// Disable accessibility and free resources
    pub fn disableAccessibility(self: *Application) void {
        if (self.accessibility) |manager| {
            manager.deinit();
            self.allocator.destroy(manager);
        }
        self.accessibility = null;
        self.focus_manager.accessibility = null;
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

    /// Process an input event
    pub fn processInputEvent(self: *Application, input_event: input.Event) !void {
        if (self.root == null) {
            return;
        }

        // Convert input event to our event system
        switch (input_event) {
            .key => |key_event| {
                // Determine if this is a press or release event
                // For simplicity, we'll treat all key events as press events
                const target: *widget.Widget = &self.root.?.widget;
                try self.event_queue.createKeyPressEvent(key_event.key, key_event.modifiers, 0, target);
            },
            .mouse => |mouse_event| {
                const target: *widget.Widget = &self.root.?.widget;
                switch (mouse_event.action) {
                    .press => {
                        try self.event_queue.createMousePressEvent(mouse_event.x, mouse_event.y, mouse_event.button, 1, .{}, target);
                        try self.beginDrag(target, mouse_event.x, mouse_event.y, mouse_event.button, .{});
                    },
                    .release => {
                        try self.event_queue.createMouseReleaseEvent(mouse_event.x, mouse_event.y, mouse_event.button, 1, .{}, target);
                        try self.endDrag(mouse_event.x, mouse_event.y, target);
                    },
                    .move => {
                        try self.event_queue.createMouseMoveEvent(mouse_event.x, mouse_event.y, mouse_event.button, .{}, target);
                        try self.updateDrag(mouse_event.x, mouse_event.y, target);
                    },
                    .scroll_up, .scroll_down => {},
                }
            },
            // Add other input event conversions here
            else => {},
        }
    }

    /// Set whether to use event propagation
    pub fn setUsePropagation(self: *Application, use_prop: bool) void {
        self.use_propagation = use_prop;
    }
};

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
        std.Thread.sleep(std.time.ns_per_ms * 2);
        try app.tickOnce();
    }

    try std.testing.expect(completed);
    try std.testing.expect(announcement_seen);
    app.releaseBackgroundTaskHandle(handle);
}
