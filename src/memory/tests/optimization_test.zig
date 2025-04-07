const std = @import("std");
const testing = std.testing;
const MemoryOptimizer = @import("../optimization.zig").MemoryOptimizer;

test "MemoryOptimizer basic operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var optimizer = try MemoryOptimizer.init(allocator);
    defer optimizer.deinit();

    const opt_allocator = optimizer.allocator();

    // Test allocation within cache line size
    const ptr = try opt_allocator.alloc(u8, 32);
    defer opt_allocator.free(ptr);

    var stats = optimizer.getStats();
    try testing.expectEqual(@as(usize, 0), stats.cache_hits);
    try testing.expectEqual(@as(usize, 1), stats.cache_misses);
    try testing.expectEqual(@as(usize, 1), stats.allocations);
    try testing.expectEqual(@as(usize, 0), stats.deallocations);

    // Test deallocation and caching
    opt_allocator.free(ptr);
    stats = optimizer.getStats();
    try testing.expectEqual(@as(usize, 0), stats.cache_hits);
    try testing.expectEqual(@as(usize, 1), stats.cache_misses);
    try testing.expectEqual(@as(usize, 1), stats.allocations);
    try testing.expectEqual(@as(usize, 1), stats.deallocations);
    try testing.expectEqual(@as(usize, 1), stats.cache_size);
}

test "MemoryOptimizer cache hits" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var optimizer = try MemoryOptimizer.init(allocator);
    defer optimizer.deinit();

    const opt_allocator = optimizer.allocator();

    // Allocate and free to populate cache
    const ptr1 = try opt_allocator.alloc(u8, 32);
    opt_allocator.free(ptr1);

    // This allocation should hit the cache
    const ptr2 = try opt_allocator.alloc(u8, 32);
    defer opt_allocator.free(ptr2);

    var stats = optimizer.getStats();
    try testing.expectEqual(@as(usize, 1), stats.cache_hits);
    try testing.expectEqual(@as(usize, 1), stats.cache_misses);
}

test "MemoryOptimizer resize" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var optimizer = try MemoryOptimizer.init(allocator);
    defer optimizer.deinit();

    const opt_allocator = optimizer.allocator();

    // Test resize within cache line size
    var ptr = try opt_allocator.alloc(u8, 32);
    defer opt_allocator.free(ptr);

    const success = opt_allocator.resize(ptr[0..32], 1, 48);
    try testing.expectEqual(true, success);

    // Test resize beyond cache line size
    const success2 = opt_allocator.resize(ptr[0..32], 1, 65);
    try testing.expectEqual(false, success2);
}

test "MemoryOptimizer thread safety" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var optimizer = try MemoryOptimizer.init(allocator);
    defer optimizer.deinit();

    const opt_allocator = optimizer.allocator();

    var threads: [4]std.Thread = undefined;
    var i: usize = 0;
    while (i < threads.len) : (i += 1) {
        threads[i] = try std.Thread.spawn(.{}, struct {
            fn threadFn(alloc: Allocator) !void {
                var j: usize = 0;
                while (j < 100) : (j += 1) {
                    const ptr = try alloc.alloc(u8, 32);
                    defer alloc.free(ptr);
                }
            }
        }.threadFn, .{opt_allocator});
    }

    for (threads) |thread| {
        thread.join();
    }

    var stats = optimizer.getStats();
    try testing.expectEqual(@as(usize, 400), stats.allocations + stats.cache_hits);
    try testing.expectEqual(@as(usize, 400), stats.deallocations);
}

test "MemoryOptimizer pre-allocation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var optimizer = try MemoryOptimizer.init(allocator);
    defer optimizer.deinit();

    // Pre-allocate cache lines
    optimizer.optimize(256);

    var stats = optimizer.getStats();
    const expected_lines = @divTrunc(256, 64) + 1;
    try testing.expectEqual(expected_lines, stats.cache_size);

    // Test allocation after pre-allocation
    const opt_allocator = optimizer.allocator();
    const ptr = try opt_allocator.alloc(u8, 32);
    defer opt_allocator.free(ptr);

    stats = optimizer.getStats();
    try testing.expectEqual(@as(usize, 1), stats.cache_hits);
    try testing.expectEqual(@as(usize, 0), stats.cache_misses);
} 