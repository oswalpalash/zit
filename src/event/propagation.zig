const std = @import("std");
const event = @import("event.zig");
const widget = @import("../widget/widget.zig");

/// Functions for working with event propagation paths
/// Build a widget path from child to root for event propagation while reusing scratch storage.
pub fn buildWidgetPathInto(
    allocator: std.mem.Allocator,
    start_widget: *widget.Widget,
    scratch: *std.ArrayListUnmanaged(*widget.Widget),
) ![]*widget.Widget {
    // Count depth first so we can size the scratch list up-front and avoid growth allocations.
    var depth: usize = 1;
    var probe = start_widget;
    while (probe.parent) |parent| {
        depth += 1;
        probe = @ptrCast(parent);
    }

    scratch.clearRetainingCapacity();
    if (depth > 0) {
        try scratch.ensureTotalCapacity(allocator, depth);
    }

    var current = start_widget;
    while (true) {
        scratch.appendAssumeCapacity(current);
        if (current.parent) |parent| {
            current = @ptrCast(parent);
        } else break;
    }

    // Reverse so path is ordered root -> target
    std.mem.reverse(*widget.Widget, scratch.items);
    return scratch.items;
}

/// Build a widget path, returning an owned list for callers that do not reuse scratch buffers.
pub fn buildWidgetPath(allocator: std.mem.Allocator, start_widget: *widget.Widget) !std.ArrayList(*widget.Widget) {
    var scratch = std.ArrayListUnmanaged(*widget.Widget){};
    defer scratch.deinit(allocator);

    const path_slice = try buildWidgetPathInto(allocator, start_widget, &scratch);

    var path = std.ArrayList(*widget.Widget).empty;
    errdefer path.deinit(allocator);
    try path.ensureTotalCapacity(allocator, path_slice.len);
    path.appendSliceAssumeCapacity(path_slice);
    return path;
}

/// Dispatch an event through the capturing and bubbling phases
pub fn dispatchWithPropagationCached(
    dispatcher: *event.EventDispatcher,
    event_item: *event.Event,
    allocator: std.mem.Allocator,
    scratch: *std.ArrayListUnmanaged(*widget.Widget),
    hooks: event.DebugHooks,
) !bool {
    if (event_item.target == null) {
        const handled = dispatcher.dispatchEvent(event_item);
        event_item.setPhase(.target);
        event.traceEvent(hooks, event_item, .target, null);
        return handled;
    }

    const path = try buildWidgetPathInto(allocator, event_item.target.?, scratch);
    return dispatcher.dispatchEventWithPropagation(event_item, path, hooks);
}

/// Dispatch an event with both capturing and bubbling phases using a temporary buffer.
/// Prefer `dispatchWithPropagationCached` inside event loops to avoid repeated allocations.
pub fn dispatchWithPropagation(dispatcher: *event.EventDispatcher, event_item: *event.Event, allocator: std.mem.Allocator, hooks: event.DebugHooks) !bool {
    var scratch = std.ArrayListUnmanaged(*widget.Widget){};
    defer scratch.deinit(allocator);
    return dispatchWithPropagationCached(dispatcher, event_item, allocator, &scratch, hooks);
}

/// Dispatch all events from a queue with propagation
pub fn processEventsWithPropagation(queue: *event.EventQueue, allocator: std.mem.Allocator, scratch: *std.ArrayListUnmanaged(*widget.Widget)) !void {
    while (queue.popFront()) |event_val| {
        var event_item = event_val;

        _ = try dispatchWithPropagationCached(&queue.dispatcher, &event_item, allocator, scratch, queue.debug_hooks);

        // Clean up custom event data if needed
        if (event_item.type == .custom) {
            const custom_data = event_item.data.custom;
            if (custom_data.destructor != null and custom_data.data != null) {
                custom_data.destructor.?(custom_data.data.?);
            }
        }
    }
}
