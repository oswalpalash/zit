const std = @import("std");

/// Simple string interner to deduplicate repeated text and cut down heap churn.
/// Stores interned strings inside an arena so lookups remain stable for the life
/// of the interner. Not thread-safe.
pub const StringInterner = struct {
    arena: std.heap.ArenaAllocator,
    table: std.StringHashMapUnmanaged([]const u8) = .{},
    parent: std.mem.Allocator,

    /// Create a new interner backed by the provided allocator.
    pub fn init(allocator: std.mem.Allocator) !StringInterner {
        return .{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .parent = allocator,
        };
    }

    /// Release all interned strings and backing storage.
    pub fn deinit(self: *StringInterner) void {
        const alloc = self.arena.allocator();
        self.table.deinit(alloc);
        self.arena.deinit();
    }

    /// Clear interned strings but keep capacity for reuse.
    pub fn clearRetainingCapacity(self: *StringInterner) void {
        self.table.clearRetainingCapacity();
        _ = self.arena.reset(.retain_capacity);
    }

    /// Intern a string slice and return a stable view.
    /// If the string is already present, returns the existing copy.
    pub fn intern(self: *StringInterner, value: []const u8) ![]const u8 {
        if (self.table.get(value)) |existing| {
            return existing;
        }

        const alloc = self.arena.allocator();
        const dup = try alloc.dupe(u8, value);
        try self.table.put(alloc, dup, dup);
        return dup;
    }

    pub const Stats = struct {
        unique_strings: usize,
        pooled_bytes: usize,
    };

    /// Inspect current memory use of the interner.
    pub fn stats(self: *StringInterner) Stats {
        return .{
            .unique_strings = self.table.count(),
            .pooled_bytes = self.arena.queryCapacity(),
        };
    }
};
