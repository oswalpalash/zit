const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const compat = @import("../compat.zig");

pub const MemoryDebugger = struct {
    const Self = @This();
    const Allocation = struct {
        ptr: [*]u8,
        size: usize,
        alignment: std.mem.Alignment,
        stack_trace: ?[]usize,
    };

    parent_allocator: Allocator,
    allocations: std.AutoHashMap([*]u8, Allocation),
    mutex: compat.Mutex,
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
            .mutex = .{},
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
            self.parent_allocator.rawFree(entry.value_ptr.ptr[0..entry.value_ptr.size], entry.value_ptr.alignment, @returnAddress());
        }
        self.allocations.deinit();
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

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.mutex.lock();
        defer self.mutex.unlock();

        const ptr = self.parent_allocator.rawAlloc(len, ptr_align, ret_addr) orelse return null;

        var stack_trace: ?[]usize = null;
        if (builtin.mode == .Debug) {
            stack_trace = self.parent_allocator.dupe(usize, &.{ret_addr}) catch null;
        }

        self.allocations.put(ptr, .{
            .ptr = ptr,
            .size = len,
            .alignment = ptr_align,
            .stack_trace = stack_trace,
        }) catch {
            if (stack_trace) |trace| self.parent_allocator.free(trace);
            self.parent_allocator.rawFree(ptr[0..len], ptr_align, ret_addr);
            return null;
        };

        self.recordAllocation(len);
        return ptr;
    }

    fn recordAllocation(self: *Self, len: usize) void {
        self.stats.total_allocations += 1;
        self.stats.current_memory_usage += len;
        if (self.stats.current_memory_usage > self.stats.peak_memory_usage) {
            self.stats.peak_memory_usage = self.stats.current_memory_usage;
        }
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.allocations.getPtr(buf.ptr)) |tracked| {
            if (buf_align != tracked.alignment or buf.len != tracked.size) return false;
            const success = self.parent_allocator.rawResize(buf, buf_align, new_len, ret_addr);
            if (!success) return false;

            self.stats.current_memory_usage -= tracked.size;
            tracked.size = new_len;
            self.stats.current_memory_usage += new_len;
            if (self.stats.current_memory_usage > self.stats.peak_memory_usage) {
                self.stats.peak_memory_usage = self.stats.current_memory_usage;
            }
            return true;
        }

        return self.parent_allocator.rawResize(buf, buf_align, new_len, ret_addr);
    }

    fn remap(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.mutex.lock();
        defer self.mutex.unlock();

        const tracked = self.allocations.get(buf.ptr) orelse {
            return self.parent_allocator.rawRemap(buf, buf_align, new_len, ret_addr);
        };
        if (buf_align != tracked.alignment or buf.len != tracked.size) return null;

        if (self.parent_allocator.rawResize(buf, buf_align, new_len, ret_addr)) {
            if (self.allocations.getPtr(buf.ptr)) |entry| {
                self.stats.current_memory_usage -= entry.size;
                entry.size = new_len;
                self.stats.current_memory_usage += new_len;
                if (self.stats.current_memory_usage > self.stats.peak_memory_usage) {
                    self.stats.peak_memory_usage = self.stats.current_memory_usage;
                }
            }
            return buf.ptr;
        }

        const new_ptr = self.parent_allocator.rawAlloc(new_len, buf_align, ret_addr) orelse return null;

        var moved = tracked;
        moved.ptr = new_ptr;
        moved.size = new_len;
        self.allocations.put(new_ptr, moved) catch {
            self.parent_allocator.rawFree(new_ptr[0..new_len], buf_align, ret_addr);
            return null;
        };
        @memcpy(new_ptr[0..@min(buf.len, new_len)], buf[0..@min(buf.len, new_len)]);
        self.parent_allocator.rawFree(buf, buf_align, ret_addr);
        _ = self.allocations.remove(buf.ptr);

        self.stats.current_memory_usage -= tracked.size;
        self.stats.current_memory_usage += new_len;
        if (self.stats.current_memory_usage > self.stats.peak_memory_usage) {
            self.stats.peak_memory_usage = self.stats.current_memory_usage;
        }
        return new_ptr;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.allocations.fetchRemove(buf.ptr)) |entry| {
            if (buf_align != entry.value.alignment or buf.len != entry.value.size) {
                @panic("Invalid allocation metadata passed to MemoryDebugger.free");
            }
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
