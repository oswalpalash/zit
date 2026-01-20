const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = @import("arena.zig").ArenaAllocator;
const PoolAllocator = @import("pool.zig").PoolAllocator;
const Widget = @import("../widget/widget.zig").Widget;

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

    /// Initialize the memory manager with an arena and widget pool.
    /// The widget pool is sized to the base widget type so common widgets can be reused safely.
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

    /// Release all managed allocators and return borrowed memory.
    pub fn deinit(self: *Self) void {
        self.arena_allocator.deinit();
        self.widget_pool.deinit();
    }

    /// Reset the arena allocator to reclaim its temporary allocations.
    pub fn resetArena(self: *Self) void {
        self.arena_allocator.reset();
    }

    /// Get the arena allocator for short-lived allocations.
    pub fn getArenaAllocator(self: *Self) Allocator {
        return self.arena_allocator.allocator();
    }

    /// Get the widget pool allocator for widget instances.
    pub fn getWidgetPoolAllocator(self: *Self) Allocator {
        return self.widget_pool.allocator();
    }

    /// Get the parent allocator for long-lived allocations.
    pub fn getParentAllocator(self: *Self) Allocator {
        return self.parent_allocator;
    }

    pub fn getStats(self: *Self) struct {
        total_allocations: usize,
        total_deallocations: usize,
        peak_memory_usage: usize,
        current_memory_usage: usize,
        arena_usage: usize,
        widget_pool_stats: PoolAllocator.Stats,
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
