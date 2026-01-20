const std = @import("std");
const testing = std.testing;
const RefCounted = @import("../ownership.zig").RefCounted;
const WeakRef = @import("../ownership.zig").WeakRef;
const WidgetNode = @import("../ownership.zig").WidgetNode;

test "RefCounted basic operations" {
    var rc = RefCounted.init();
    try testing.expectEqual(@as(usize, 1), rc.getCount());

    rc.acquire();
    try testing.expectEqual(@as(usize, 2), rc.getCount());

    const should_deinit = rc.release();
    try testing.expectEqual(@as(usize, 1), rc.getCount());
    try testing.expectEqual(false, should_deinit);

    const should_deinit2 = rc.release();
    try testing.expectEqual(@as(usize, 0), rc.getCount());
    try testing.expectEqual(true, should_deinit2);
}

test "WeakRef operations" {
    var cleanup_called = false;
    const cleanup_fn = struct {
        fn cleanup(ptr: *anyopaque) void {
            _ = ptr;
            cleanup_called = true;
        }
    }.cleanup;

    var data: i32 = 42;
    var weak_ref = WeakRef.init(&data, cleanup_fn);
    try testing.expectEqual(@as(?*anyopaque, &data), weak_ref.getPtr());

    weak_ref.clear();
    try testing.expectEqual(@as(?*anyopaque, null), weak_ref.getPtr());
    try testing.expectEqual(true, cleanup_called);
}

test "WidgetNode tree operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create root node
    var root = try WidgetNode.init(allocator);
    defer root.deinit();

    // Create child nodes
    var child1 = try WidgetNode.init(allocator);
    defer child1.deinit();
    var child2 = try WidgetNode.init(allocator);
    defer child2.deinit();

    // Test adding children
    root.addChild(&child1);
    try testing.expectEqual(@as(?*WidgetNode, &root), child1.parent);
    try testing.expectEqual(@as(?*WidgetNode, &child1), root.first_child);
    try testing.expectEqual(@as(?*WidgetNode, &child1), root.last_child);

    root.addChild(&child2);
    try testing.expectEqual(@as(?*WidgetNode, &root), child2.parent);
    try testing.expectEqual(@as(?*WidgetNode, &child1), root.first_child);
    try testing.expectEqual(@as(?*WidgetNode, &child2), root.last_child);
    try testing.expectEqual(@as(?*WidgetNode, &child2), child1.next_sibling);
    try testing.expectEqual(@as(?*WidgetNode, &child1), child2.prev_sibling);

    // Test removing children
    root.removeChild(&child1);
    try testing.expectEqual(@as(?*WidgetNode, null), child1.parent);
    try testing.expectEqual(@as(?*WidgetNode, &child2), root.first_child);
    try testing.expectEqual(@as(?*WidgetNode, &child2), root.last_child);
    try testing.expectEqual(@as(?*WidgetNode, null), child1.next_sibling);
    try testing.expectEqual(@as(?*WidgetNode, null), child1.prev_sibling);
}

test "WidgetNode weak references" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var node = try WidgetNode.init(allocator);
    defer node.deinit();

    var cleanup_called = false;
    const cleanup_fn = struct {
        fn cleanup(ptr: *anyopaque) void {
            _ = ptr;
            cleanup_called = true;
        }
    }.cleanup;

    var data: i32 = 42;
    var weak_ref = WeakRef.init(&data, cleanup_fn);
    try node.addWeakRef(weak_ref);
    try testing.expectEqual(@as(usize, 1), node.weak_refs.items.len);

    node.removeWeakRef(&data);
    try testing.expectEqual(@as(usize, 0), node.weak_refs.items.len);
    try testing.expectEqual(false, cleanup_called);
}

test "WidgetNode thread safety" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var root = try WidgetNode.init(allocator);
    defer root.deinit();

    var threads: [4]std.Thread = undefined;
    var i: usize = 0;
    while (i < threads.len) : (i += 1) {
        threads[i] = try std.Thread.spawn(.{}, struct {
            fn threadFn(node: *WidgetNode) !void {
                var j: usize = 0;
                while (j < 100) : (j += 1) {
                    var child = try WidgetNode.init(node.allocator);
                    defer child.deinit();
                    node.addChild(&child);
                    node.removeChild(&child);
                }
            }
        }.threadFn, .{&root});
    }

    for (threads) |thread| {
        thread.join();
    }
}
