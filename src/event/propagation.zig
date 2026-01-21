const std = @import("std");
const event = @import("event.zig");
const widget = @import("../widget/widget.zig");

/// Functions for working with event propagation paths
/// Build a widget path from child to root for event propagation
/// The returned slice is owned by the caller and must be freed
pub fn buildWidgetPath(allocator: std.mem.Allocator, start_widget: *widget.Widget) !std.ArrayList(*widget.Widget) {
    var path = std.ArrayList(*widget.Widget).empty;
    errdefer path.deinit(allocator);

    // Start with the target widget
    try path.append(allocator, start_widget);

    // Walk up the parent chain to build the path
    var current = start_widget;
    while (current.parent) |parent| {
        try path.append(allocator, @ptrCast(parent));
        current = @ptrCast(parent);
    }

    // Reverse so path is ordered root -> target
    std.mem.reverse(*widget.Widget, path.items);

    return path;
}

/// Dispatch an event through the capturing and bubbling phases
pub fn dispatchWithPropagation(dispatcher: *event.EventDispatcher, event_item: *event.Event, allocator: std.mem.Allocator, hooks: event.DebugHooks) !bool {
    if (event_item.target == null) {
        const handled = dispatcher.dispatchEvent(event_item);
        event_item.setPhase(.target);
        event.traceEvent(hooks, event_item, .target, null);
        return handled;
    }

    var path = try buildWidgetPath(allocator, event_item.target.?);
    defer path.deinit(allocator);

    return dispatcher.dispatchEventWithPropagation(event_item, path.items, hooks);
}

/// Dispatch all events from a queue with propagation
pub fn processEventsWithPropagation(queue: *event.EventQueue, allocator: std.mem.Allocator) !void {
    while (queue.popFront()) |event_val| {
        var event_item = event_val;

        _ = try dispatchWithPropagation(&queue.dispatcher, &event_item, allocator, queue.debug_hooks);

        // Clean up custom event data if needed
        if (event_item.type == .custom) {
            const custom_data = event_item.data.custom;
            if (custom_data.destructor != null and custom_data.data != null) {
                custom_data.destructor.?(custom_data.data.?);
            }
        }
    }
}
