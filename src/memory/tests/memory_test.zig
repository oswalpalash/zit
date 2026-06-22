const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const MemoryManager = @import("../memory.zig").MemoryManager;
const ArenaAllocator = @import("../arena.zig").ArenaAllocator;
const PoolAllocator = @import("../pool.zig").PoolAllocator;

test "MemoryManager initialization and cleanup" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var memory_manager = try MemoryManager.init(allocator, 1024 * 1024, 100);
    defer memory_manager.deinit();

    // Test arena allocator
    const arena = memory_manager.getArenaAllocator();
    const str = try arena.alloc(u8, 100);
    defer arena.free(str);
    try testing.expectEqual(@as(usize, 100), memory_manager.arena_allocator.end_index);

    // Test widget pool
    const widget_pool = memory_manager.getWidgetPoolAllocator();
    const widget = try widget_pool.alloc(u8, @sizeOf(u64));
    defer widget_pool.free(widget);
    const stats = memory_manager.widget_pool.getStats();
    try testing.expectEqual(@as(usize, 1), stats.allocated_nodes);
}

test "MemoryManager statistics" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var memory_manager = try MemoryManager.init(allocator, 1024 * 1024, 100);
    defer memory_manager.deinit();

    const arena = memory_manager.getArenaAllocator();
    const widget_pool = memory_manager.getWidgetPoolAllocator();

    // Allocate some memory
    const str1 = try arena.alloc(u8, 100);
    defer arena.free(str1);
    const str2 = try arena.alloc(u8, 200);
    defer arena.free(str2);
    const widget1 = try widget_pool.alloc(u8, @sizeOf(u64));
    defer widget_pool.free(widget1);
    const widget2 = try widget_pool.alloc(u8, @sizeOf(u64));
    defer widget_pool.free(widget2);

    const stats = memory_manager.getStats();
    try testing.expectEqual(@as(usize, 4), stats.total_allocations);
    try testing.expectEqual(@as(usize, 0), stats.total_deallocations);
    try testing.expectEqual(@as(usize, 300), stats.arena_usage);
    try testing.expectEqual(@as(usize, 2), stats.widget_pool_stats.allocated_nodes);
    try testing.expectEqual(@as(usize, 300 + 2 * memory_manager.widget_pool.node_size), stats.current_memory_usage);
    try testing.expect(stats.peak_memory_usage >= stats.current_memory_usage);
}

test "MemoryManager aggregate stats track allocation lifecycle" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var memory_manager = try MemoryManager.init(allocator, 1024 * 1024, 4);
    defer memory_manager.deinit();

    const arena = memory_manager.getArenaAllocator();
    const widget_pool = memory_manager.getWidgetPoolAllocator();

    var scratch = try arena.alloc(u8, 64);
    const widget = try widget_pool.alloc(u8, @sizeOf(u64));

    var stats = memory_manager.getStats();
    try testing.expectEqual(@as(usize, 2), stats.total_allocations);
    try testing.expectEqual(@as(usize, 0), stats.total_deallocations);
    try testing.expectEqual(@as(usize, 64), stats.arena_usage);
    try testing.expectEqual(@as(usize, 1), stats.widget_pool_stats.allocated_nodes);
    try testing.expectEqual(@as(usize, 64 + memory_manager.widget_pool.node_size), stats.current_memory_usage);

    try testing.expect(arena.resize(scratch, 96));
    scratch = scratch.ptr[0..96];
    stats = memory_manager.getStats();
    try testing.expectEqual(@as(usize, 2), stats.total_allocations);
    try testing.expectEqual(@as(usize, 96), stats.arena_usage);
    try testing.expectEqual(@as(usize, 96 + memory_manager.widget_pool.node_size), stats.current_memory_usage);
    try testing.expectEqual(stats.current_memory_usage, stats.peak_memory_usage);

    arena.free(scratch);
    stats = memory_manager.getStats();
    try testing.expectEqual(@as(usize, 1), stats.total_deallocations);
    try testing.expectEqual(@as(usize, 96), stats.arena_usage);

    memory_manager.resetArena();
    stats = memory_manager.getStats();
    try testing.expectEqual(@as(usize, 0), stats.arena_usage);
    try testing.expectEqual(@as(usize, memory_manager.widget_pool.node_size), stats.current_memory_usage);

    widget_pool.free(widget);
    stats = memory_manager.getStats();
    try testing.expectEqual(@as(usize, 2), stats.total_deallocations);
    try testing.expectEqual(@as(usize, 0), stats.widget_pool_stats.allocated_nodes);
    try testing.expectEqual(@as(usize, 0), stats.current_memory_usage);
    try testing.expect(stats.peak_memory_usage >= 96 + memory_manager.widget_pool.node_size);
}

test "MemoryManager arena reset" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var memory_manager = try MemoryManager.init(allocator, 1024 * 1024, 100);
    defer memory_manager.deinit();

    const arena = memory_manager.getArenaAllocator();
    const str = try arena.alloc(u8, 100);
    defer arena.free(str);
    try testing.expectEqual(@as(usize, 100), memory_manager.arena_allocator.end_index);

    memory_manager.resetArena();
    try testing.expectEqual(@as(usize, 0), memory_manager.arena_allocator.end_index);
}

test "MemoryManager thread safety" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var memory_manager = try MemoryManager.init(allocator, 1024 * 1024, 100);
    defer memory_manager.deinit();

    const arena = memory_manager.getArenaAllocator();
    const widget_pool = memory_manager.getWidgetPoolAllocator();

    var threads: [4]std.Thread = undefined;
    var i: usize = 0;
    while (i < threads.len) : (i += 1) {
        threads[i] = try std.Thread.spawn(.{}, struct {
            fn threadFn(arena_: Allocator, widget_pool_: Allocator) !void {
                var j: usize = 0;
                while (j < 100) : (j += 1) {
                    const str = try arena_.alloc(u8, 100);
                    arena_.free(str);
                    const widget = try widget_pool_.alloc(u8, @sizeOf(u64));
                    widget_pool_.free(widget);
                }
            }
        }.threadFn, .{ arena, widget_pool });
    }

    for (threads) |thread| {
        thread.join();
    }

    memory_manager.resetArena();
    const stats = memory_manager.getStats();
    try testing.expectEqual(@as(usize, 0), stats.arena_usage);
    try testing.expectEqual(@as(usize, 0), stats.widget_pool_stats.allocated_nodes);
}

test "PoolAllocator tracks pooled ownership and falls back for foreign frees" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var pool = try PoolAllocator.init(allocator, 64, 2);
    defer pool.deinit();

    const pooled_alloc = pool.allocator();

    const first = try pooled_alloc.alloc(u8, 16);
    const second = try pooled_alloc.alloc(u8, 16);
    try testing.expectEqual(@as(usize, 2), pool.getStats().allocated_nodes);

    pooled_alloc.free(first);
    pooled_alloc.free(second);
    try testing.expectEqual(@as(usize, 0), pool.getStats().allocated_nodes);

    const foreign = try allocator.alloc(u8, 8);
    const before = pool.getStats().allocated_nodes;
    pooled_alloc.free(foreign);
    try testing.expectEqual(before, pool.getStats().allocated_nodes);
}

test "PoolAllocator remaps pooled allocations in place within node size" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var pool = try PoolAllocator.init(allocator, 64, 1);
    defer pool.deinit();

    const pooled_alloc = pool.allocator();
    const ptr = try pooled_alloc.alloc(u8, 16);
    @memset(ptr, 0x42);

    const remapped = pooled_alloc.remap(ptr, 48) orelse return error.UnexpectedRemapFailure;
    try testing.expectEqual(ptr.ptr, remapped.ptr);
    try testing.expectEqual(@as(usize, 48), remapped.len);
    try testing.expectEqual(@as(u8, 0x42), remapped[0]);
    remapped[47] = 0x24;

    try testing.expectEqual(@as(usize, 1), pool.getStats().allocated_nodes);
    pooled_alloc.free(remapped);
    try testing.expectEqual(@as(usize, 0), pool.getStats().allocated_nodes);
}

test "PoolAllocator rejects pooled remap beyond node size" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var pool = try PoolAllocator.init(allocator, 64, 1);
    defer pool.deinit();

    const pooled_alloc = pool.allocator();
    const ptr = try pooled_alloc.alloc(u8, 16);
    defer pooled_alloc.free(ptr);

    try testing.expectEqual(@as(?[]u8, null), pooled_alloc.remap(ptr, 65));
    try testing.expectEqual(@as(usize, 1), pool.getStats().allocated_nodes);
}

test "PoolAllocator forwards pass-through remap to parent allocator" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var pool = try PoolAllocator.init(allocator, 64, 1);
    defer pool.deinit();

    const pooled_alloc = pool.allocator();
    const ptr = try pooled_alloc.alloc(u8, 128);
    @memset(ptr, 0x33);

    const remapped = pooled_alloc.remap(ptr, 96) orelse return error.UnexpectedRemapFailure;
    try testing.expectEqual(@as(usize, 96), remapped.len);
    try testing.expectEqual(@as(u8, 0x33), remapped[0]);
    try testing.expectEqual(@as(usize, 0), pool.getStats().allocated_nodes);

    pooled_alloc.free(remapped);
    try testing.expectEqual(@as(usize, 0), pool.getStats().allocated_nodes);
}

test "ArenaAllocator init cleans up object when buffer allocation fails" {
    var failing = std.testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 1 });
    try testing.expectError(error.OutOfMemory, ArenaAllocator.init(failing.allocator(), 4096, true));
}

test "PoolAllocator init cleans up partial free list when growth fails" {
    var failing = std.testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 3 });
    try testing.expectError(error.OutOfMemory, PoolAllocator.init(failing.allocator(), 64, 2));
}
