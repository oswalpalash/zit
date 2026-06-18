const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = @import("arena.zig").ArenaAllocator;
const PoolAllocator = @import("pool.zig").PoolAllocator;
const Widget = @import("../widget/widget.zig").Widget;
const compat = @import("../compat.zig");
pub const StringInterner = @import("string_intern.zig").StringInterner;

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
    cached_pool_usage_bytes: usize,
    stats_mutex: compat.Mutex,

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
            .cached_pool_usage_bytes = 0,
            .stats_mutex = .{},
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
        self.refreshUsage();
    }

    /// Reset per-frame temporary allocations.
    pub fn resetFrame(self: *Self) void {
        self.resetArena();
    }

    /// Get the arena allocator for short-lived allocations.
    pub fn getArenaAllocator(self: *Self) Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = arenaAlloc,
                .resize = arenaResize,
                .free = arenaFree,
                .remap = arenaRemap,
            },
        };
    }

    /// Get the frame allocator for per-frame scratch.
    pub fn frameAllocator(self: *Self) Allocator {
        return self.getArenaAllocator();
    }

    /// Get the widget pool allocator for widget instances.
    pub fn getWidgetPoolAllocator(self: *Self) Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = poolAlloc,
                .resize = poolResize,
                .free = poolFree,
                .remap = poolRemap,
            },
        };
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
        self.stats_mutex.lock();
        defer self.stats_mutex.unlock();

        const widget_stats = self.widget_pool.getStats();
        const current_usage = self.currentManagedUsage(widget_stats);
        self.cached_pool_usage_bytes = widgetPoolUsageBytes(self, widget_stats);
        self.stats.current_memory_usage = current_usage;
        if (current_usage > self.stats.peak_memory_usage) {
            self.stats.peak_memory_usage = current_usage;
        }

        return .{
            .total_allocations = self.stats.total_allocations,
            .total_deallocations = self.stats.total_deallocations,
            .peak_memory_usage = self.stats.peak_memory_usage,
            .current_memory_usage = current_usage,
            .arena_usage = self.arena_allocator.usage(),
            .widget_pool_stats = widget_stats,
        };
    }

    fn arenaAlloc(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const ptr = self.arena_allocator.allocator().rawAlloc(len, ptr_align, ret_addr) orelse return null;
        self.recordArenaAllocation();
        return ptr;
    }

    fn arenaResize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const resized = self.arena_allocator.allocator().rawResize(buf, buf_align, new_len, ret_addr);
        if (resized) self.refreshArenaUsage();
        return resized;
    }

    fn arenaRemap(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const ptr = self.arena_allocator.allocator().rawRemap(buf, buf_align, new_len, ret_addr) orelse return null;
        self.refreshArenaUsage();
        return ptr;
    }

    fn arenaFree(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.arena_allocator.allocator().rawFree(buf, buf_align, ret_addr);
        self.recordArenaDeallocation();
    }

    fn poolAlloc(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const ptr = self.widget_pool.allocator().rawAlloc(len, ptr_align, ret_addr) orelse return null;
        self.recordPoolAllocation();
        return ptr;
    }

    fn poolResize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const resized = self.widget_pool.allocator().rawResize(buf, buf_align, new_len, ret_addr);
        if (resized) self.refreshPoolUsage();
        return resized;
    }

    fn poolRemap(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const ptr = self.widget_pool.allocator().rawRemap(buf, buf_align, new_len, ret_addr) orelse return null;
        self.refreshPoolUsage();
        return ptr;
    }

    fn poolFree(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.widget_pool.allocator().rawFree(buf, buf_align, ret_addr);
        self.recordPoolDeallocation();
    }

    fn recordArenaAllocation(self: *Self) void {
        self.stats_mutex.lock();
        defer self.stats_mutex.unlock();

        self.stats.total_allocations += 1;
        self.refreshUsageFromCachedPoolLocked();
    }

    fn recordArenaDeallocation(self: *Self) void {
        self.stats_mutex.lock();
        defer self.stats_mutex.unlock();

        self.stats.total_deallocations += 1;
        self.refreshUsageFromCachedPoolLocked();
    }

    fn recordPoolAllocation(self: *Self) void {
        const widget_stats = self.widget_pool.getStats();
        self.stats_mutex.lock();
        defer self.stats_mutex.unlock();

        self.stats.total_allocations += 1;
        self.cached_pool_usage_bytes = widgetPoolUsageBytes(self, widget_stats);
        self.refreshUsageFromCachedPoolLocked();
    }

    fn recordPoolDeallocation(self: *Self) void {
        const widget_stats = self.widget_pool.getStats();
        self.stats_mutex.lock();
        defer self.stats_mutex.unlock();

        self.stats.total_deallocations += 1;
        self.cached_pool_usage_bytes = widgetPoolUsageBytes(self, widget_stats);
        self.refreshUsageFromCachedPoolLocked();
    }

    fn refreshArenaUsage(self: *Self) void {
        self.stats_mutex.lock();
        defer self.stats_mutex.unlock();

        self.refreshUsageFromCachedPoolLocked();
    }

    fn refreshPoolUsage(self: *Self) void {
        const widget_stats = self.widget_pool.getStats();
        self.stats_mutex.lock();
        defer self.stats_mutex.unlock();

        self.cached_pool_usage_bytes = widgetPoolUsageBytes(self, widget_stats);
        self.refreshUsageFromCachedPoolLocked();
    }

    fn refreshUsage(self: *Self) void {
        self.refreshPoolUsage();
    }

    fn refreshUsageFromCachedPoolLocked(self: *Self) void {
        const current_usage = self.arena_allocator.usage() + self.cached_pool_usage_bytes;
        self.stats.current_memory_usage = current_usage;
        if (current_usage > self.stats.peak_memory_usage) {
            self.stats.peak_memory_usage = current_usage;
        }
    }

    fn currentManagedUsage(self: *Self, widget_stats: PoolAllocator.Stats) usize {
        return self.arena_allocator.usage() + widgetPoolUsageBytes(self, widget_stats);
    }

    fn widgetPoolUsageBytes(self: *Self, widget_stats: PoolAllocator.Stats) usize {
        return widget_stats.current_usage * self.widget_pool.node_size;
    }
};
