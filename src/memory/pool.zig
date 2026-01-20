const std = @import("std");
const Allocator = std.mem.Allocator;

pub const PoolAllocator = struct {
    const Self = @This();
    const Node = struct {
        next: ?*Node,
        data: []u8,
    };

    parent_allocator: Allocator,
    node_size: usize,
    free_list: ?*Node,
    allocated_count: usize,
    total_count: usize,
    mutex: std.Thread.Mutex,
    stats: struct {
        allocations: usize,
        deallocations: usize,
        peak_usage: usize,
        current_usage: usize,
    },

    pub fn init(parent_allocator: Allocator, node_size: usize, initial_capacity: usize) !Self {
        var self = Self{
            .parent_allocator = parent_allocator,
            .node_size = node_size,
            .free_list = null,
            .allocated_count = 0,
            .total_count = 0,
            .mutex = std.Thread.Mutex{},
            .stats = .{
                .allocations = 0,
                .deallocations = 0,
                .peak_usage = 0,
                .current_usage = 0,
            },
        };

        try self.grow(initial_capacity);
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var current = self.free_list;
        while (current) |node| {
            const next = node.next;
            self.parent_allocator.free(node.data);
            self.parent_allocator.destroy(node);
            current = next;
        }
    }

    fn grow(self: *Self, count: usize) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var i: usize = 0;
        while (i < count) : (i += 1) {
            const node = try self.parent_allocator.create(Node);
            node.data = try self.parent_allocator.alloc(u8, self.node_size);
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

        if (len > self.node_size) {
            return self.parent_allocator.rawAlloc(len, ptr_align, ret_addr);
        }

        if (self.free_list == null) {
            // Grow pool by 50% when empty
            const new_nodes = self.total_count / 2;
            if (new_nodes == 0) return null;
            self.grow(new_nodes) catch return null;
        }

        const node = self.free_list.?;
        self.free_list = node.next;
        self.allocated_count += 1;
        self.stats.allocations += 1;
        self.stats.current_usage += 1;
        if (self.stats.current_usage > self.stats.peak_usage) {
            self.stats.peak_usage = self.stats.current_usage;
        }

        return node.data.ptr;
    }

    pub fn resize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self = @as(*PoolAllocator, @ptrCast(@alignCast(ctx)));

        if (new_len > self.node_size) {
            // If new size is larger than block size, fall back to parent allocator
            return self.parent_allocator.rawResize(buf, buf_align, new_len, ret_addr);
        }

        // For pool allocations, we can't resize - the block size is fixed
        return new_len <= buf.len;
    }

    pub fn free(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        const self = @as(*PoolAllocator, @ptrCast(@alignCast(ctx)));
        self.mutex.lock();
        defer self.mutex.unlock();

        if (buf.len > self.node_size) {
            self.parent_allocator.rawFree(buf, buf_align, ret_addr);
            return;
        }

        const node = @as(*Node, @ptrCast(@alignCast(buf.ptr)));
        node.next = self.free_list;
        self.free_list = node;
        self.allocated_count -= 1;
        self.stats.deallocations += 1;
        self.stats.current_usage -= 1;
    }

    pub fn getStats(self: *Self) struct {
        allocations: usize,
        deallocations: usize,
        peak_usage: usize,
        current_usage: usize,
        total_nodes: usize,
        allocated_nodes: usize,
    } {
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
