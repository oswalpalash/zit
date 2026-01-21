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

    return path;
}

/// Dispatch an event through the capturing and bubbling phases
pub fn dispatchWithPropagation(dispatcher: *event.EventDispatcher, event_item: *event.Event, allocator: std.mem.Allocator) !bool {
    if (event_item.target == null) {
        return dispatcher.dispatchEvent(event_item);
    }

    var path = try buildWidgetPath(allocator, event_item.target.?);
    defer path.deinit(allocator);

    // Reverse the path for top-down traversal
    var reversed_path = try allocator.alloc(*widget.Widget, path.items.len);
    defer allocator.free(reversed_path);

    for (path.items, 0..) |w, i| {
        reversed_path[path.items.len - i - 1] = w;
    }

    var handled = false;

    // Capturing phase (top-down)
    event_item.setPhase(.capturing);
    for (reversed_path) |w| {
        const original_target = event_item.target;
        event_item.target = w;

        if (dispatcher.dispatchEvent(event_item)) {
            handled = true;
        }

        // Restore original target
        event_item.target = original_target;

        if (event_item.stop_propagation) {
            return handled;
        }
    }

    // Target phase
    event_item.setPhase(.target);
    if (dispatcher.dispatchEvent(event_item)) {
        handled = true;
    }

    if (event_item.stop_propagation) {
        return handled;
    }

    // Bubbling phase (bottom-up)
    event_item.setPhase(.bubbling);
    for (path.items) |w| {
        const original_target = event_item.target;
        event_item.target = w;

        if (dispatcher.dispatchEvent(event_item)) {
            handled = true;
        }

        // Restore original target
        event_item.target = original_target;

        if (event_item.stop_propagation) {
            break;
        }
    }

    return handled;
}

/// Dispatch all events from a queue with propagation
pub fn processEventsWithPropagation(queue: *event.EventQueue, allocator: std.mem.Allocator) !void {
    while (queue.popFront()) |event_val| {
        var event_item = event_val;

        _ = try dispatchWithPropagation(&queue.dispatcher, &event_item, allocator);

        // Clean up custom event data if needed
        if (event_item.type == .custom) {
            const custom_data = event_item.data.custom;
            if (custom_data.destructor != null and custom_data.data != null) {
                custom_data.destructor.?(custom_data.data.?);
            }
        }
    }
}
