const std = @import("std");
const Allocator = std.mem.Allocator;

pub const MemoryOptimizer = struct {
    const Self = @This();
    const CacheLine = struct {
        data: [64]u8,
        next: ?*CacheLine,
    };

    parent_allocator: Allocator,
    cache_lines: ?*CacheLine,
    mutex: std.Thread.Mutex,
    stats: struct {
        cache_hits: usize,
        cache_misses: usize,
        allocations: usize,
        deallocations: usize,
    },

    pub fn init(parent_allocator: Allocator) !Self {
        return Self{
            .parent_allocator = parent_allocator,
            .cache_lines = null,
            .mutex = std.Thread.Mutex{},
            .stats = .{
                .cache_hits = 0,
                .cache_misses = 0,
                .allocations = 0,
                .deallocations = 0,
            },
        };
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var current = self.cache_lines;
        while (current) |line| {
            const next = line.next;
            self.parent_allocator.destroy(line);
            current = next;
        }
    }

    pub fn allocator(self: *Self) Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.mutex.lock();
        defer self.mutex.unlock();

        // Check if we can use a cached cache line
        if (len <= @sizeOf(CacheLine) and ptr_align <= @alignOf(CacheLine)) {
            if (self.cache_lines) |line| {
                self.cache_lines = line.next;
                self.stats.cache_hits += 1;
                return @ptrCast([*]u8, line);
            }
        }

        self.stats.cache_misses += 1;
        self.stats.allocations += 1;
        return self.parent_allocator.rawAlloc(len, ptr_align, ret_addr);
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.mutex.lock();
        defer self.mutex.unlock();

        // Check if the buffer is a cached cache line
        if (buf.len <= @sizeOf(CacheLine) and buf_align <= @alignOf(CacheLine)) {
            if (new_len > @sizeOf(CacheLine)) {
                return false;
            }
            return true;
        }

        return self.parent_allocator.rawResize(buf, buf_align, new_len, ret_addr);
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.mutex.lock();
        defer self.mutex.unlock();

        // Check if we can cache this allocation
        if (buf.len <= @sizeOf(CacheLine) and buf_align <= @alignOf(CacheLine)) {
            const line = @ptrCast(*CacheLine, @alignCast(@alignOf(CacheLine), buf.ptr));
            line.next = self.cache_lines;
            self.cache_lines = line;
            self.stats.deallocations += 1;
            return;
        }

        self.parent_allocator.rawFree(buf, buf_align, ret_addr);
    }

    pub fn getStats(self: *Self) struct {
        cache_hits: usize,
        cache_misses: usize,
        allocations: usize,
        deallocations: usize,
        cache_size: usize,
    } {
        self.mutex.lock();
        defer self.mutex.unlock();

        var cache_size: usize = 0;
        var current = self.cache_lines;
        while (current) |line| {
            cache_size += 1;
            current = line.next;
        }

        return .{
            .cache_hits = self.stats.cache_hits,
            .cache_misses = self.stats.cache_misses,
            .allocations = self.stats.allocations,
            .deallocations = self.stats.deallocations,
            .cache_size = cache_size,
        };
    }

    pub fn optimize(self: *Self, size_hint: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Pre-allocate cache lines based on size hint
        const num_lines = @divTrunc(size_hint, @sizeOf(CacheLine)) + 1;
        var i: usize = 0;
        while (i < num_lines) : (i += 1) {
            const line = self.parent_allocator.create(CacheLine) catch continue;
            line.next = self.cache_lines;
            self.cache_lines = line;
        }
    }
};
