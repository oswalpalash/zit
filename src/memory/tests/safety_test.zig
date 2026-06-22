const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const MemorySafety = @import("../safety.zig").MemorySafety;

test "MemorySafety basic operations" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var safety = try MemorySafety.init(allocator);
    defer safety.deinit();

    const safe_allocator = safety.allocator();

    // Test allocation
    const ptr = try safe_allocator.alloc(u8, 100);
    defer safe_allocator.free(ptr);

    // Test pointer validation
    try testing.expectEqual(true, safety.validatePointer(ptr.ptr, 100));
    try testing.expectEqual(false, safety.validatePointer(ptr.ptr, 101));

    // Test zero memory
    safety.zeroMemory(ptr.ptr, 100);
    for (ptr[0..100]) |byte| {
        try testing.expectEqual(@as(u8, 0), byte);
    }
}

test "MemorySafety buffer overflow detection" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var safety = try MemorySafety.init(allocator);
    defer safety.deinit();

    const safe_allocator = safety.allocator();

    // Test buffer overflow
    const ptr = try safe_allocator.alloc(u8, 100);

    // This should trigger a buffer overflow
    ptr.ptr[100] ^= 0xff;
    try testing.expectError(error.BufferOverflow, safety.checkAllocations());
}

test "MemorySafety resize" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var safety = try MemorySafety.init(allocator);
    defer safety.deinit();

    const safe_allocator = safety.allocator();

    // Test allocation and resize
    var ptr = try safe_allocator.alloc(u8, 100);

    ptr = try safe_allocator.realloc(ptr, 200);
    defer safe_allocator.free(ptr);

    // Test pointer validation after resize
    try testing.expectEqual(true, safety.validatePointer(ptr.ptr, 200));
    try testing.expectEqual(false, safety.validatePointer(ptr.ptr, 201));
}

test "MemorySafety handles odd allocation sizes without aligned canary writes" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var safety = try MemorySafety.init(allocator);
    defer safety.deinit();

    const safe_allocator = safety.allocator();

    var len: usize = 1;
    while (len <= 17) : (len += 1) {
        const ptr = try safe_allocator.alloc(u8, len);
        try testing.expect(safety.validatePointer(ptr.ptr, len));
        safe_allocator.free(ptr);
    }
}

test "MemorySafety direct resize uses backing allocation length" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var safety = try MemorySafety.init(allocator);
    defer safety.deinit();

    const safe_allocator = safety.allocator();

    var ptr = try safe_allocator.alloc(u8, 13);
    try testing.expect(safety.validatePointer(ptr.ptr, 13));

    try testing.expect(safe_allocator.resize(ptr, 7));
    ptr = ptr.ptr[0..7];

    try testing.expect(safety.validatePointer(ptr.ptr, 7));
    safe_allocator.free(ptr);
}

test "MemorySafety remap updates tracked size and canary" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var safety = try MemorySafety.init(allocator);
    defer safety.deinit();

    const safe_allocator = safety.allocator();

    const ptr = try safe_allocator.alloc(u8, 13);
    @memset(ptr, 0x7a);

    const remapped = safe_allocator.remap(ptr, 7) orelse return error.UnexpectedRemapFailure;
    try testing.expectEqual(ptr.ptr, remapped.ptr);
    try testing.expectEqual(@as(usize, 7), remapped.len);
    try testing.expectEqual(@as(u8, 0x7a), remapped[0]);
    try testing.expect(safety.validatePointer(remapped.ptr, 7));
    try testing.expect(!safety.validatePointer(remapped.ptr, 8));
    try safety.checkAllocations();

    safe_allocator.free(remapped);
}

test "MemorySafety remap can grow when backing allocation resizes in place" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var safety = try MemorySafety.init(allocator);
    defer safety.deinit();

    const safe_allocator = safety.allocator();

    const ptr = try safe_allocator.alloc(u8, 13);
    @memset(ptr, 0x19);

    if (safe_allocator.remap(ptr, 17)) |remapped| {
        try testing.expectEqual(ptr.ptr, remapped.ptr);
        try testing.expectEqual(@as(usize, 17), remapped.len);
        try testing.expectEqual(@as(u8, 0x19), remapped[0]);
        try testing.expect(safety.validatePointer(remapped.ptr, 17));
        try testing.expect(!safety.validatePointer(remapped.ptr, 18));
        try safety.checkAllocations();
        safe_allocator.free(remapped);
    } else {
        try testing.expect(safety.validatePointer(ptr.ptr, 13));
        try safety.checkAllocations();
        safe_allocator.free(ptr);
    }
}

test "MemorySafety forwards untracked remap to parent allocator" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var safety = try MemorySafety.init(allocator);
    defer safety.deinit();

    const safe_allocator = safety.allocator();
    const foreign = try allocator.alloc(u8, 128);
    @memset(foreign, 0x33);

    const remapped = safe_allocator.remap(foreign, 96) orelse return error.UnexpectedRemapFailure;
    try testing.expectEqual(@as(usize, 96), remapped.len);
    try testing.expectEqual(@as(u8, 0x33), remapped[0]);
    try testing.expect(!safety.validatePointer(remapped.ptr, 96));

    safe_allocator.free(remapped);
}

test "MemorySafety thread safety" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
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
                    @memset(ptr[0..100], 0);
                    alloc.free(ptr);
                }
            }
        }.threadFn, .{safe_allocator});
    }

    for (threads) |thread| {
        thread.join();
    }

    try safety.checkAllocations();
}

test "MemorySafety zero memory preserves canary and rejects oversized validation" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var safety = try MemorySafety.init(allocator);
    defer safety.deinit();

    const safe_allocator = safety.allocator();

    const ptr = try safe_allocator.alloc(u8, 100);
    defer safe_allocator.free(ptr);

    safety.zeroMemory(ptr.ptr, 100);
    try safety.checkAllocations();
    try testing.expect(!safety.validatePointer(ptr.ptr, 101));
}
