const std = @import("std");
const testing = std.testing;
const MemoryManager = @import("../memory.zig").MemoryManager;

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
                    defer arena_.free(str);
                    const widget = try widget_pool_.alloc(u8, @sizeOf(u64));
                    defer widget_pool_.free(widget);
                }
            }
        }.threadFn, .{ arena, widget_pool });
    }

    for (threads) |thread| {
        thread.join();
    }

    const stats = memory_manager.getStats();
    try testing.expectEqual(@as(usize, 0), stats.arena_usage);
    try testing.expectEqual(@as(usize, 0), stats.widget_pool_stats.allocated_nodes);
} 