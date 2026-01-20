const std = @import("std");
const input = @import("../input/input.zig");
pub const widget = @import("../widget/widget.zig");

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
};

/// Key event data
pub const KeyEventData = struct {
    /// Key code
    key: input.KeyCode,
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
    pub fn dispatchEventWithPropagation(self: *EventDispatcher, event: *Event, widget_path: []*widget.Widget) bool {
        var handled = false;

        // Capturing phase (top-down)
        event.setPhase(.capturing);
        for (widget_path) |w| {
            event.target = w;
            if (self.dispatchEvent(event)) {
                handled = true;
            }

            if (event.stop_propagation) {
                return handled;
            }
        }

        // Target phase
        if (event.target != null) {
            event.setPhase(.target);
            if (self.dispatchEvent(event)) {
                handled = true;
            }

            if (event.stop_propagation) {
                return handled;
            }
        }

        // Bubbling phase (bottom-up)
        event.setPhase(.bubbling);
        var i: usize = widget_path.len;
        while (i > 0) {
            i -= 1;
            event.target = widget_path[i];
            if (self.dispatchEvent(event)) {
                handled = true;
            }

            if (event.stop_propagation) {
                break;
            }
        }

        return handled;
    }
};

/// Event queue for storing and processing events
pub const EventQueue = struct {
    /// Event queue
    queue: std.ArrayList(Event),
    /// Event dispatcher
    dispatcher: EventDispatcher,
    /// Allocator for event queue operations
    allocator: std.mem.Allocator,

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
        self.dispatcher.deinit();
    }

    /// Push an event to the queue
    pub fn pushEvent(self: *EventQueue, event: Event) !void {
        try self.queue.append(self.allocator, event);
    }

    /// Process all events in the queue
    pub fn processEvents(self: *EventQueue) !void {
        // Use standard dispatch (no propagation)
        while (self.queue.items.len > 0) {
            var event = self.queue.orderedRemove(0);
            _ = self.dispatcher.dispatchEvent(&event);

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
        try propagation.processEventsWithPropagation(self, allocator);
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
    pub fn createKeyPressEvent(self: *EventQueue, key: input.KeyCode, modifiers: input.KeyModifiers, raw: u32, target: ?*widget.Widget) !void {
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
    pub fn createKeyReleaseEvent(self: *EventQueue, key: input.KeyCode, modifiers: input.KeyModifiers, raw: u32, target: ?*widget.Widget) !void {
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
        // Check current queue for matching event
        for (self.queue.items) |*event| {
            if (condition(event)) {
                if (callback != null) {
                    callback.?(event.*);
                }
                return;
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
    /// Event queue reference
    event_queue: *EventQueue,
    /// Allocator
    allocator: std.mem.Allocator,
    /// Whether focus stealing is allowed
    allow_focus_stealing: bool = false,

    /// Initialize a new focus manager
    pub fn init(allocator: std.mem.Allocator, event_queue: *EventQueue) FocusManager {
        return FocusManager{
            .focused_widget = null,
            .focus_history = std.ArrayList(*widget.Widget).empty,
            .event_queue = event_queue,
            .allocator = allocator,
        };
    }

    /// Clean up focus manager resources
    pub fn deinit(self: *FocusManager) void {
        self.focus_history.deinit(self.allocator);
    }

    /// Request focus for a widget
    pub fn requestFocus(self: *FocusManager, target_widget: *widget.Widget) !bool {
        // Check if focus stealing is allowed
        if (!self.allow_focus_stealing and self.focused_widget != null) {
            // Ask current widget if it's willing to give up focus
            const focus_data = FocusRequestData{
                .requesting_widget = target_widget,
                .current_widget = self.focused_widget.?,
                .allow = false,
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
        if (self.focus_history.items.len > 10) {
            _ = self.focus_history.orderedRemove(0);
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
        if (self.focus_history.items.len < 2) {
            return false;
        }

        _ = self.focus_history.pop();
        const previous = self.focus_history.getLast();
        return try self.requestFocus(previous);
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

    /// Initialize a new application
    pub fn init(allocator: std.mem.Allocator) Application {
        var app = Application{
            .event_queue = EventQueue.init(allocator),
            .allocator = allocator,
            .focus_manager = undefined,
        };

        app.focus_manager = FocusManager.init(allocator, &app.event_queue);

        return app;
    }

    /// Clean up application resources
    pub fn deinit(self: *Application) void {
        if (self.io_manager) |manager| {
            manager.deinit();
            self.allocator.destroy(manager);
        }

        self.focus_manager.deinit();
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

    /// Start the application event loop
    pub fn run(self: *Application) !void {
        if (self.root == null) {
            return error.NoRootWidget;
        }

        self.running = true;

        while (self.running) {
            // Process events with or without propagation
            if (self.use_propagation) {
                try self.event_queue.processEventsWithPropagation(self.allocator);
            } else {
                try self.event_queue.processEvents();
            }

            // Yield to allow other tasks to run
            std.Thread.sleep(std.time.ns_per_ms * 10);
        }
    }

    /// Start the application event loop asynchronously
    pub fn runAsync(self: *Application, callback: ?*const fn () void) !void {
        if (self.root == null) {
            return error.NoRootWidget;
        }

        self.running = true;

        // Start processing in a separate thread
        var thread = try std.Thread.spawn(.{}, struct {
            fn threadFn(app: *Application, cb: ?*const fn () void) !void {
                while (app.running) {
                    // Process events
                    try app.event_queue.processEvents();

                    // Yield to allow other tasks to run
                    std.Thread.sleep(std.time.ns_per_ms * 10);
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

    /// Request focus for a widget
    pub fn requestFocus(self: *Application, target_widget: *widget.Widget) !bool {
        return try self.focus_manager.requestFocus(target_widget);
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
                try self.event_queue.createKeyPressEvent(key_event.key, key_event.modifiers, 0, // We don't have raw key codes in our input system
                    @ptrCast(self.root.?));
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
