const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const MemoryManager = @import("../memory.zig").MemoryManager;
const PoolAllocator = @import("../pool.zig").PoolAllocator;

test "MemoryManager initialization and cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
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
    try testing.expectEqual(@as(usize, 300), stats.arena_usage);
    try testing.expectEqual(@as(usize, 2), stats.widget_pool_stats.allocated_nodes);
}

test "MemoryManager arena reset" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
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
