const std = @import("std");
const testing = std.testing;
const MemoryDebugger = @import("../debug.zig").MemoryDebugger;

test "MemoryDebugger basic operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var debugger = try MemoryDebugger.init(allocator);
    defer debugger.deinit();

    const debug_allocator = debugger.allocator();

    // Test allocation
    const ptr = try debug_allocator.alloc(u8, 100);
    defer debug_allocator.free(ptr);

    var stats = debugger.getStats();
    try testing.expectEqual(@as(usize, 1), stats.total_allocations);
    try testing.expectEqual(@as(usize, 0), stats.total_deallocations);
    try testing.expectEqual(@as(usize, 100), stats.current_memory_usage);
    try testing.expectEqual(@as(usize, 100), stats.peak_memory_usage);
    try testing.expectEqual(@as(usize, 0), stats.leaked_allocations);

    // Test deallocation
    debug_allocator.free(ptr);
    stats = debugger.getStats();
    try testing.expectEqual(@as(usize, 1), stats.total_allocations);
    try testing.expectEqual(@as(usize, 1), stats.total_deallocations);
    try testing.expectEqual(@as(usize, 0), stats.current_memory_usage);
    try testing.expectEqual(@as(usize, 100), stats.peak_memory_usage);
    try testing.expectEqual(@as(usize, 0), stats.leaked_allocations);
}

test "MemoryDebugger resize" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var debugger = try MemoryDebugger.init(allocator);
    defer debugger.deinit();

    const debug_allocator = debugger.allocator();

    // Test allocation and resize
    var ptr = try debug_allocator.alloc(u8, 100);
    defer debug_allocator.free(ptr);

    ptr = try debug_allocator.realloc(ptr, 200);
    defer debug_allocator.free(ptr);

    var stats = debugger.getStats();
    try testing.expectEqual(@as(usize, 1), stats.total_allocations);
    try testing.expectEqual(@as(usize, 0), stats.total_deallocations);
    try testing.expectEqual(@as(usize, 200), stats.current_memory_usage);
    try testing.expectEqual(@as(usize, 200), stats.peak_memory_usage);
}

test "MemoryDebugger leak detection" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var debugger = try MemoryDebugger.init(allocator);
    defer debugger.deinit();

    const debug_allocator = debugger.allocator();

    // Create some leaks
    _ = try debug_allocator.alloc(u8, 100);
    _ = try debug_allocator.alloc(u8, 200);

    var stats = debugger.getStats();
    try testing.expectEqual(@as(usize, 2), stats.total_allocations);
    try testing.expectEqual(@as(usize, 0), stats.total_deallocations);
    try testing.expectEqual(@as(usize, 300), stats.current_memory_usage);
    try testing.expectEqual(@as(usize, 300), stats.peak_memory_usage);
    try testing.expectEqual(@as(usize, 2), stats.leaked_allocations);
}

test "MemoryDebugger thread safety" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var debugger = try MemoryDebugger.init(allocator);
    defer debugger.deinit();

    const debug_allocator = debugger.allocator();

    var threads: [4]std.Thread = undefined;
    var i: usize = 0;
    while (i < threads.len) : (i += 1) {
        threads[i] = try std.Thread.spawn(.{}, struct {
            fn threadFn(alloc: Allocator) !void {
                var j: usize = 0;
                while (j < 100) : (j += 1) {
                    const ptr = try alloc.alloc(u8, 100);
                    defer alloc.free(ptr);
                }
            }
        }.threadFn, .{debug_allocator});
    }

    for (threads) |thread| {
        thread.join();
    }

    var stats = debugger.getStats();
    try testing.expectEqual(@as(usize, 400), stats.total_allocations);
    try testing.expectEqual(@as(usize, 400), stats.total_deallocations);
    try testing.expectEqual(@as(usize, 0), stats.current_memory_usage);
    try testing.expectEqual(@as(usize, 100), stats.peak_memory_usage);
    try testing.expectEqual(@as(usize, 0), stats.leaked_allocations);
} 