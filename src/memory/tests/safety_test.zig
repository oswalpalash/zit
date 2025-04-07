const std = @import("std");
const testing = std.testing;
const MemorySafety = @import("../safety.zig").MemorySafety;

test "MemorySafety basic operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var safety = try MemorySafety.init(allocator);
    defer safety.deinit();

    const safe_allocator = safety.allocator();

    // Test allocation
    const ptr = try safe_allocator.alloc(u8, 100);
    defer safe_allocator.free(ptr);

    // Test pointer validation
    try testing.expectEqual(true, safety.validatePointer(ptr, 100));
    try testing.expectEqual(false, safety.validatePointer(ptr, 101));

    // Test zero memory
    safety.zeroMemory(ptr, 100);
    for (ptr[0..100]) |byte| {
        try testing.expectEqual(@as(u8, 0), byte);
    }
}

test "MemorySafety buffer overflow detection" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var safety = try MemorySafety.init(allocator);
    defer safety.deinit();

    const safe_allocator = safety.allocator();

    // Test buffer overflow
    const ptr = try safe_allocator.alloc(u8, 100);
    defer safe_allocator.free(ptr);

    // This should trigger a buffer overflow
    ptr[100] = 0;
    try testing.expectError(error.BufferOverflow, safety.checkAllocations());
}

test "MemorySafety resize" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var safety = try MemorySafety.init(allocator);
    defer safety.deinit();

    const safe_allocator = safety.allocator();

    // Test allocation and resize
    var ptr = try safe_allocator.alloc(u8, 100);
    defer safe_allocator.free(ptr);

    ptr = try safe_allocator.realloc(ptr, 200);
    defer safe_allocator.free(ptr);

    // Test pointer validation after resize
    try testing.expectEqual(true, safety.validatePointer(ptr, 200));
    try testing.expectEqual(false, safety.validatePointer(ptr, 201));
}

test "MemorySafety thread safety" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var safety = try MemorySafety.init(allocator);
    defer safety.deinit();

    const safe_allocator = safety.allocator();

    var threads: [4]std.Thread = undefined;
    var i: usize = 0;
    while (i < threads.len) : (i += 1) {
        threads[i] = try std.Thread.spawn(.{}, struct {
            fn threadFn(alloc: Allocator) !void {
                var j: usize = 0;
                while (j < 100) : (j += 1) {
                    const ptr = try alloc.alloc(u8, 100);
                    defer alloc.free(ptr);
                    @memset(ptr[0..100], 0);
                }
            }
        }.threadFn, .{safe_allocator});
    }

    for (threads) |thread| {
        thread.join();
    }

    try testing.expectEqual(true, safety.checkAllocations() catch false);
}

test "MemorySafety zero memory bounds" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var safety = try MemorySafety.init(allocator);
    defer safety.deinit();

    const safe_allocator = safety.allocator();

    const ptr = try safe_allocator.alloc(u8, 100);
    defer safe_allocator.free(ptr);

    // This should panic due to out of bounds
    testing.expectPanic(@panic, "Attempt to zero memory beyond allocation!", struct {
        fn panicFn() void {
            var safety_ = safety;
            safety_.zeroMemory(ptr, 101);
        }
    }.panicFn);
} 