const std = @import("std");
const Allocator = std.mem.Allocator;
const compat = @import("../compat.zig");

pub const MemoryOptimizer = struct {
    const Self = @This();
    const cache_payload_size: usize = 64;

    const CacheLine = struct {
        data: [cache_payload_size]u8,
        next: ?*CacheLine,
    };

    parent_allocator: Allocator,
    cache_lines: ?*CacheLine,
    in_use: std.AutoHashMap([*]u8, *CacheLine),
    mutex: compat.Mutex,
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
            .in_use = std.AutoHashMap([*]u8, *CacheLine).init(parent_allocator),
            .mutex = .{},
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

        var live_it = self.in_use.iterator();
        while (live_it.next()) |entry| {
            self.parent_allocator.destroy(entry.value_ptr.*);
        }
        self.in_use.deinit();

        var current = self.cache_lines;
        while (current) |line| {
            const next = line.next;
            self.parent_allocator.destroy(line);
            current = next;
        }
        self.cache_lines = null;
    }

    pub fn allocator(self: *Self) Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    fn canOptimize(len: usize, ptr_align: std.mem.Alignment) bool {
        return len <= cache_payload_size and ptr_align.compare(.lte, .of(CacheLine));
    }

    fn returnToCacheUnlocked(self: *Self, line: *CacheLine) void {
        line.next = self.cache_lines;
        self.cache_lines = line;
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));

        if (!canOptimize(len, ptr_align)) {
            const ptr = self.parent_allocator.rawAlloc(len, ptr_align, ret_addr);
            if (ptr != null) {
                self.mutex.lock();
                defer self.mutex.unlock();
                self.stats.cache_misses += 1;
                self.stats.allocations += 1;
            }
            return ptr;
        }

        self.mutex.lock();
        defer self.mutex.unlock();

        const from_cache = self.cache_lines != null;
        const line = if (self.cache_lines) |cached| blk: {
            self.cache_lines = cached.next;
            self.stats.cache_hits += 1;
            break :blk cached;
        } else blk: {
            const fresh = self.parent_allocator.create(CacheLine) catch return null;
            self.stats.cache_misses += 1;
            self.stats.allocations += 1;
            break :blk fresh;
        };

        line.next = null;
        const ptr = line.data[0..].ptr;
        self.in_use.put(ptr, line) catch {
            if (from_cache) {
                self.stats.cache_hits -= 1;
                self.returnToCacheUnlocked(line);
            } else {
                self.stats.cache_misses -= 1;
                self.stats.allocations -= 1;
                self.parent_allocator.destroy(line);
            }
            return null;
        };

        return ptr;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.in_use.contains(buf.ptr)) {
            return canOptimize(new_len, buf_align);
        }

        return self.parent_allocator.rawResize(buf, buf_align, new_len, ret_addr);
    }

    fn remap(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.in_use.contains(buf.ptr)) {
            return if (canOptimize(new_len, buf_align)) buf.ptr else null;
        }

        return self.parent_allocator.rawRemap(buf, buf_align, new_len, ret_addr);
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.in_use.fetchRemove(buf.ptr)) |entry| {
            const line = entry.value;
            if (!canOptimize(buf.len, buf_align)) {
                @panic("Invalid allocation metadata passed to MemoryOptimizer.free");
            }
            self.returnToCacheUnlocked(line);
            self.stats.deallocations += 1;
            return;
        }

        self.parent_allocator.rawFree(buf, buf_align, ret_addr);
        self.stats.deallocations += 1;
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
        const num_lines = @divTrunc(size_hint, cache_payload_size) + 1;
        var i: usize = 0;
        while (i < num_lines) : (i += 1) {
            const line = self.parent_allocator.create(CacheLine) catch continue;
            line.next = self.cache_lines;
            self.cache_lines = line;
        }
    }
};
