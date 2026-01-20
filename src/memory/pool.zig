const std = @import("std");
const Allocator = std.mem.Allocator;

pub const PoolAllocator = struct {
    const Self = @This();
    const Node = struct {
        next: ?*Node,
        block: []u8,
    };
    pub const Stats = struct {
        allocations: usize,
        deallocations: usize,
        peak_usage: usize,
        current_usage: usize,
        total_nodes: usize,
        allocated_nodes: usize,
    };

    parent_allocator: Allocator,
    node_size: usize,
    node_alignment_log2: u6,
    block_alignment: std.mem.Alignment,
    free_list: ?*Node,
    allocated_count: usize,
    total_count: usize,
    in_use: std.AutoHashMap([*]u8, *Node),
    mutex: std.Thread.Mutex,
    stats: struct {
        allocations: usize,
        deallocations: usize,
        peak_usage: usize,
        current_usage: usize,
    },

    pub fn init(parent_allocator: Allocator, node_size: usize, initial_capacity: usize) !Self {
        if (node_size == 0) return error.InvalidNodeSize;

        const default_align_log2: u6 = std.math.log2_int(u6, @alignOf(usize));
        var self = Self{
            .parent_allocator = parent_allocator,
            .node_size = node_size,
            .node_alignment_log2 = default_align_log2,
            .block_alignment = @enumFromInt(default_align_log2),
            .free_list = null,
            .allocated_count = 0,
            .total_count = 0,
            .in_use = std.AutoHashMap([*]u8, *Node).init(parent_allocator),
            .mutex = std.Thread.Mutex{},
            .stats = .{
                .allocations = 0,
                .deallocations = 0,
                .peak_usage = 0,
                .current_usage = 0,
            },
        };

        try self.growUnlocked(initial_capacity);
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var live_it = self.in_use.iterator();
        while (live_it.next()) |entry| {
            const node = entry.value_ptr.*;
            self.parent_allocator.rawFree(node.block, self.block_alignment, @returnAddress());
            self.parent_allocator.destroy(node);
        }
        self.in_use.deinit();

        var current = self.free_list;
        while (current) |node| {
            const next = node.next;
            self.parent_allocator.rawFree(node.block, self.block_alignment, @returnAddress());
            self.parent_allocator.destroy(node);
            current = next;
        }

        self.free_list = null;
    }

    fn growUnlocked(self: *Self, count: usize) !void {
        if (count == 0) return;

        var i: usize = 0;
        while (i < count) : (i += 1) {
            const node = try self.parent_allocator.create(Node);
            const block_ptr = self.parent_allocator.rawAlloc(self.node_size, self.block_alignment, @returnAddress()) orelse {
                self.parent_allocator.destroy(node);
                return error.OutOfMemory;
            };
            node.block = block_ptr[0..self.node_size];
            node.next = self.free_list;
            self.free_list = node;
            self.total_count += 1;
        }
    }

    pub fn allocator(self: *Self) Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
                .remap = remap,
            },
        };
    }

    pub fn alloc(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self = @as(*PoolAllocator, @ptrCast(@alignCast(ctx)));

        if (len == 0 or len > self.node_size or @intFromEnum(ptr_align) > self.node_alignment_log2) {
            return self.parent_allocator.rawAlloc(len, ptr_align, ret_addr);
        }

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.free_list == null) {
            const new_nodes = @max(self.total_count / 2, @as(usize, 1));
            self.growUnlocked(new_nodes) catch {
                return self.parent_allocator.rawAlloc(len, ptr_align, ret_addr);
            };
        }

        const node = self.free_list.?;
        self.free_list = node.next;

        self.allocated_count += 1;
        self.stats.allocations += 1;
        self.stats.current_usage += 1;
        if (self.stats.current_usage > self.stats.peak_usage) {
            self.stats.peak_usage = self.stats.current_usage;
        }

        self.in_use.put(node.block.ptr, node) catch {
            // Roll back allocation accounting if bookkeeping fails
            self.allocated_count -= 1;
            self.stats.current_usage -= 1;
            node.next = self.free_list;
            self.free_list = node;
            return self.parent_allocator.rawAlloc(len, ptr_align, ret_addr);
        };

        return node.block.ptr;
    }

    pub fn resize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self = @as(*PoolAllocator, @ptrCast(@alignCast(ctx)));

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.in_use.contains(buf.ptr)) {
            return new_len <= self.node_size and @intFromEnum(buf_align) <= self.node_alignment_log2;
        }

        // If not tracked, defer to parent allocator
        return self.parent_allocator.rawResize(buf, buf_align, new_len, ret_addr);
    }

    pub fn free(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        const self = @as(*PoolAllocator, @ptrCast(@alignCast(ctx)));
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.in_use.fetchRemove(buf.ptr)) |entry| {
            const node = entry.value;
            node.next = self.free_list;
            self.free_list = node;
            self.allocated_count -= 1;
            self.stats.deallocations += 1;
            self.stats.current_usage -= 1;
            return;
        }

        self.parent_allocator.rawFree(buf, buf_align, ret_addr);
    }

    pub fn getStats(self: *Self) Stats {
        self.mutex.lock();
        defer self.mutex.unlock();

        return .{
            .allocations = self.stats.allocations,
            .deallocations = self.stats.deallocations,
            .peak_usage = self.stats.peak_usage,
            .current_usage = self.stats.current_usage,
            .total_nodes = self.total_count,
            .allocated_nodes = self.allocated_count,
        };
    }

    pub fn remap(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = new_len;
        _ = ret_addr;
        return null;
    }
};
