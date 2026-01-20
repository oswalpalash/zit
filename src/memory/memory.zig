const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = @import("arena.zig").ArenaAllocator;
const PoolAllocator = @import("pool.zig").PoolAllocator;

pub const MemoryManager = struct {
    const Self = @This();

    parent_allocator: Allocator,
    arena_allocator: *ArenaAllocator,
    widget_pool: PoolAllocator,
    stats: struct {
        total_allocations: usize,
        total_deallocations: usize,
        peak_memory_usage: usize,
        current_memory_usage: usize,
    },

    pub fn init(parent_allocator: Allocator, arena_size: usize, widget_pool_size: usize) !Self {
        var arena = try ArenaAllocator.init(parent_allocator, arena_size, true);
        errdefer arena.deinit();

        var widget_pool = try PoolAllocator.init(parent_allocator, @sizeOf(Widget), widget_pool_size);
        errdefer widget_pool.deinit();

        return Self{
            .parent_allocator = parent_allocator,
            .arena_allocator = arena,
            .widget_pool = widget_pool,
            .stats = .{
                .total_allocations = 0,
                .total_deallocations = 0,
                .peak_memory_usage = 0,
                .current_memory_usage = 0,
            },
        };
    }

    pub fn deinit(self: *Self) void {
        self.arena_allocator.deinit();
        self.widget_pool.deinit();
    }

    pub fn resetArena(self: *Self) void {
        self.arena_allocator.reset();
    }

    pub fn getArenaAllocator(self: *Self) Allocator {
        return self.arena_allocator.allocator();
    }

    pub fn getWidgetPoolAllocator(self: *Self) Allocator {
        return self.widget_pool.allocator();
    }

    pub fn getParentAllocator(self: *Self) Allocator {
        return self.parent_allocator;
    }

    pub fn getStats(self: *Self) struct {
        total_allocations: usize,
        total_deallocations: usize,
        peak_memory_usage: usize,
        current_memory_usage: usize,
        arena_usage: usize,
        widget_pool_stats: struct {
            allocations: usize,
            deallocations: usize,
            peak_usage: usize,
            current_usage: usize,
            total_nodes: usize,
            allocated_nodes: usize,
        },
    } {
        const widget_stats = self.widget_pool.getStats();
        return .{
            .total_allocations = self.stats.total_allocations,
            .total_deallocations = self.stats.total_deallocations,
            .peak_memory_usage = self.stats.peak_memory_usage,
            .current_memory_usage = self.stats.current_memory_usage,
            .arena_usage = self.arena_allocator.end_index,
            .widget_pool_stats = widget_stats,
        };
    }
};

// Forward declarations for widget types
const Widget = struct {
    // This is a placeholder for the actual Widget type
    // The actual type will be defined in the widget module
};
