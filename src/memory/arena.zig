const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

pub const ArenaAllocator = struct {
    fallback_allocator: Allocator,
    buffer: []u8,
    end_index: usize,
    is_thread_safe: bool,
    mutex: std.Thread.Mutex,

    pub fn init(parent_alloc: Allocator, size: usize, is_thread_safe: bool) !*ArenaAllocator {
        const self = try parent_alloc.create(ArenaAllocator);
        self.* = ArenaAllocator{
            .fallback_allocator = parent_alloc,
            .buffer = try parent_alloc.alloc(u8, size),
            .end_index = 0,
            .is_thread_safe = is_thread_safe,
            .mutex = std.Thread.Mutex{},
        };
        return self;
    }

    pub fn deinit(self: *ArenaAllocator) void {
        self.fallback_allocator.free(self.buffer);
        self.fallback_allocator.destroy(self);
    }

    pub fn reset(self: *ArenaAllocator) void {
        if (self.is_thread_safe) {
            self.mutex.lock();
            defer self.mutex.unlock();
        }
        self.end_index = 0;
    }

    pub fn allocator(self: *ArenaAllocator) Allocator {
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
        const self = @as(*ArenaAllocator, @ptrCast(@alignCast(ctx)));
        _ = ret_addr;

        if (self.is_thread_safe) {
            self.mutex.lock();
            defer self.mutex.unlock();
        }

        // Calculate aligned address
        const start_addr = @intFromPtr(self.buffer.ptr) + self.end_index;
        const alignment = @as(usize, 1) << @as(u6, @intFromEnum(ptr_align));
        const adjusted_addr = mem.alignForward(usize, start_addr, alignment);
        const adjusted_index = adjusted_addr - @intFromPtr(self.buffer.ptr);
        const new_end_index = adjusted_index + len;

        if (new_end_index <= self.buffer.len) {
            const result = self.buffer.ptr + adjusted_index;
            self.end_index = new_end_index;
            return @ptrCast(result);
        }

        return null;
    }

    pub fn resize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self = @as(*ArenaAllocator, @ptrCast(@alignCast(ctx)));
        _ = buf_align;
        _ = ret_addr;

        if (self.is_thread_safe) {
            self.mutex.lock();
            defer self.mutex.unlock();
        }

        // Check if the buffer is the most recent allocation
        const buf_start = @intFromPtr(buf.ptr);
        const arena_start = @intFromPtr(self.buffer.ptr);
        if (buf_start < arena_start or buf_start >= arena_start + self.buffer.len) {
            return false;
        }

        const buf_end = buf_start + buf.len;
        if (buf_end != arena_start + self.end_index) {
            return false;
        }

        // Calculate new end index
        const new_end_index = (buf_start - arena_start) + new_len;
        if (new_end_index > self.buffer.len) {
            return false;
        }

        self.end_index = new_end_index;
        return true;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        const self = @as(*ArenaAllocator, @ptrCast(@alignCast(ctx)));
        _ = buf;
        _ = buf_align;
        _ = ret_addr;

        if (self.is_thread_safe) {
            self.mutex.lock();
            defer self.mutex.unlock();
        }

        // No need to free individual allocations in an arena
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
