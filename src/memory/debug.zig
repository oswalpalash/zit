const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");

pub const MemoryDebugger = struct {
    const Self = @This();
    const Allocation = struct {
        ptr: [*]u8,
        size: usize,
        alignment: u8,
        stack_trace: ?[]usize,
    };

    parent_allocator: Allocator,
    allocations: std.AutoHashMap([*]u8, Allocation),
    mutex: std.Thread.Mutex,
    stats: struct {
        total_allocations: usize,
        total_deallocations: usize,
        peak_memory_usage: usize,
        current_memory_usage: usize,
        leaked_allocations: usize,
    },

    pub fn init(parent_allocator: Allocator) !Self {
        return Self{
            .parent_allocator = parent_allocator,
            .allocations = std.AutoHashMap([*]u8, Allocation).init(parent_allocator),
            .mutex = std.Thread.Mutex{},
            .stats = .{
                .total_allocations = 0,
                .total_deallocations = 0,
                .peak_memory_usage = 0,
                .current_memory_usage = 0,
                .leaked_allocations = 0,
            },
        };
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var it = self.allocations.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.stack_trace) |trace| {
                self.parent_allocator.free(trace);
            }
        }
        self.allocations.deinit();
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

        const ptr = self.parent_allocator.rawAlloc(len, ptr_align, ret_addr) orelse return null;
        
        var stack_trace: ?[]usize = null;
        if (builtin.mode == .Debug) {
            var trace_buffer: [32]usize = undefined;
            const trace = std.debug.captureStackTrace(ret_addr, &trace_buffer) catch null;
            if (trace) |t| {
                stack_trace = self.parent_allocator.dupe(usize, t) catch null;
            }
        }

        try self.allocations.put(ptr, .{
            .ptr = ptr,
            .size = len,
            .alignment = ptr_align,
            .stack_trace = stack_trace,
        });

        self.stats.total_allocations += 1;
        self.stats.current_memory_usage += len;
        if (self.stats.current_memory_usage > self.stats.peak_memory_usage) {
            self.stats.peak_memory_usage = self.stats.current_memory_usage;
        }

        return ptr;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.mutex.lock();
        defer self.mutex.unlock();

        const old_size = if (self.allocations.get(buf.ptr)) |alloc| alloc.size else 0;
        const success = self.parent_allocator.rawResize(buf, buf_align, new_len, ret_addr);
        
        if (success) {
            if (self.allocations.getPtr(buf.ptr)) |alloc| {
                self.stats.current_memory_usage -= alloc.size;
                alloc.size = new_len;
                self.stats.current_memory_usage += new_len;
                if (self.stats.current_memory_usage > self.stats.peak_memory_usage) {
                    self.stats.peak_memory_usage = self.stats.current_memory_usage;
                }
            }
        }

        return success;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.allocations.fetchRemove(buf.ptr)) |entry| {
            self.stats.total_deallocations += 1;
            self.stats.current_memory_usage -= entry.value.size;
            if (entry.value.stack_trace) |trace| {
                self.parent_allocator.free(trace);
            }
        }

        self.parent_allocator.rawFree(buf, buf_align, ret_addr);
    }

    pub fn getStats(self: *Self) struct {
        total_allocations: usize,
        total_deallocations: usize,
        peak_memory_usage: usize,
        current_memory_usage: usize,
        leaked_allocations: usize,
    } {
        self.mutex.lock();
        defer self.mutex.unlock();

        return .{
            .total_allocations = self.stats.total_allocations,
            .total_deallocations = self.stats.total_deallocations,
            .peak_memory_usage = self.stats.peak_memory_usage,
            .current_memory_usage = self.stats.current_memory_usage,
            .leaked_allocations = self.allocations.count(),
        };
    }

    pub fn dumpLeaks(self: *Self, writer: anytype) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var it = self.allocations.iterator();
        while (it.next()) |entry| {
            try writer.print("Leaked allocation at {*}: size={}, alignment={}\n", .{
                entry.key_ptr.*,
                entry.value_ptr.size,
                entry.value_ptr.alignment,
            });

            if (entry.value_ptr.stack_trace) |trace| {
                try writer.writeAll("Stack trace:\n");
                for (trace) |addr| {
                    try writer.print("  {x}\n", .{addr});
                }
            }
        }
    }
}; 