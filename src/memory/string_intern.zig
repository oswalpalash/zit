const std = @import("std");

/// Simple string interner to deduplicate repeated text and cut down heap churn.
/// Stores interned strings inside an arena so lookups remain stable for the life
/// of the interner. Not thread-safe.
pub const StringInterner = struct {
    arena: std.heap.ArenaAllocator,
    table: std.StringHashMapUnmanaged([]const u8) = .{},
    parent: std.mem.Allocator,
    unique_bytes: usize = 0,

    /// Create a new interner backed by the provided allocator.
    pub fn init(allocator: std.mem.Allocator) !StringInterner {
        return .{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .parent = allocator,
        };
    }

    /// Release all interned strings and backing storage.
    pub fn deinit(self: *StringInterner) void {
        self.table.deinit(self.parent);
        self.arena.deinit();
    }

    /// Clear interned strings but keep capacity for reuse.
    pub fn clearRetainingCapacity(self: *StringInterner) void {
        self.table.clearRetainingCapacity();
        self.unique_bytes = 0;
        _ = self.arena.reset(.retain_capacity);
    }

    /// Intern a string slice and return a stable view.
    /// If the string is already present, returns the existing copy.
    pub fn intern(self: *StringInterner, value: []const u8) ![]const u8 {
        if (self.table.get(value)) |existing| {
            return existing;
        }

        try self.table.ensureUnusedCapacity(self.parent, 1);
        const alloc = self.arena.allocator();
        const dup = try alloc.dupe(u8, value);
        self.table.putAssumeCapacityNoClobber(dup, dup);
        self.unique_bytes += dup.len;
        return dup;
    }

    pub const Stats = struct {
        unique_strings: usize,
        unique_bytes: usize,
        pooled_bytes: usize,
        index_slots: usize,
    };

    /// Inspect current memory use of the interner.
    pub fn stats(self: *StringInterner) Stats {
        return .{
            .unique_strings = self.table.count(),
            .unique_bytes = self.unique_bytes,
            .pooled_bytes = self.arena.queryCapacity(),
            .index_slots = self.table.capacity(),
        };
    }
};

test "string interner reports unique logical bytes" {
    const alloc = std.testing.allocator;
    var interner = try StringInterner.init(alloc);
    defer interner.deinit();

    const first = try interner.intern("ready");
    const second = try interner.intern("ready");
    const third = try interner.intern("busy");

    try std.testing.expectEqual(@intFromPtr(first.ptr), @intFromPtr(second.ptr));
    try std.testing.expect(@intFromPtr(first.ptr) != @intFromPtr(third.ptr));

    const stats = interner.stats();
    try std.testing.expectEqual(@as(usize, 2), stats.unique_strings);
    try std.testing.expectEqual(@as(usize, "ready".len + "busy".len), stats.unique_bytes);
    try std.testing.expect(stats.pooled_bytes >= stats.unique_bytes);
    try std.testing.expect(stats.index_slots >= stats.unique_strings);
}
