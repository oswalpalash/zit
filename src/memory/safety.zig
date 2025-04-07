const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");

pub const MemorySafety = struct {
    const Self = @This();
    const SafetyCheck = struct {
        ptr: [*]u8,
        size: usize,
        alignment: u8,
        canary: u64,
    };

    parent_allocator: Allocator,
    checks: std.AutoHashMap([*]u8, SafetyCheck),
    mutex: std.Thread.Mutex,
    canary_value: u64,

    pub fn init(parent_allocator: Allocator) !Self {
        var prng = std.rand.DefaultPrng.init(@bitCast(u64, std.time.milliTimestamp()));
        const canary = prng.random().int(u64);

        return Self{
            .parent_allocator = parent_allocator,
            .checks = std.AutoHashMap([*]u8, SafetyCheck).init(parent_allocator),
            .mutex = std.Thread.Mutex{},
            .canary_value = canary,
        };
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.checks.deinit();
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

        // Add canary size to allocation
        const total_size = len + @sizeOf(u64);
        const ptr = self.parent_allocator.rawAlloc(total_size, ptr_align, ret_addr) orelse return null;

        // Write canary at the end of the allocation
        const canary_ptr = @ptrCast(*u64, @alignCast(@alignOf(u64), ptr + len));
        canary_ptr.* = self.canary_value;

        try self.checks.put(ptr, .{
            .ptr = ptr,
            .size = len,
            .alignment = ptr_align,
            .canary = self.canary_value,
        });

        return ptr;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.mutex.lock();
        defer self.mutex.unlock();

        // Check if the canary is still intact
        if (self.checks.get(buf.ptr)) |check| {
            const canary_ptr = @ptrCast(*u64, @alignCast(@alignOf(u64), buf.ptr + check.size));
            if (canary_ptr.* != self.canary_value) {
                @panic("Buffer overflow detected!");
            }
        }

        const total_size = new_len + @sizeOf(u64);
        const success = self.parent_allocator.rawResize(buf, buf_align, total_size, ret_addr);
        
        if (success) {
            if (self.checks.getPtr(buf.ptr)) |check| {
                // Update canary position
                const canary_ptr = @ptrCast(*u64, @alignCast(@alignOf(u64), buf.ptr + new_len));
                canary_ptr.* = self.canary_value;
                check.size = new_len;
            }
        }

        return success;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.checks.get(buf.ptr)) |check| {
            // Check if the canary is still intact
            const canary_ptr = @ptrCast(*u64, @alignCast(@alignOf(u64), buf.ptr + check.size));
            if (canary_ptr.* != self.canary_value) {
                @panic("Buffer overflow detected!");
            }

            _ = self.checks.remove(buf.ptr);
        }

        self.parent_allocator.rawFree(buf, buf_align, ret_addr);
    }

    pub fn checkAllocations(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var it = self.checks.iterator();
        while (it.next()) |entry| {
            const check = entry.value_ptr;
            const canary_ptr = @ptrCast(*u64, @alignCast(@alignOf(u64), check.ptr + check.size));
            if (canary_ptr.* != self.canary_value) {
                return error.BufferOverflow;
            }
        }
    }

    pub fn zeroMemory(self: *Self, ptr: [*]u8, len: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.checks.get(ptr)) |check| {
            if (len > check.size) {
                @panic("Attempt to zero memory beyond allocation!");
            }
        }

        @memset(ptr[0..len], 0);
    }

    pub fn validatePointer(self: *Self, ptr: [*]u8, len: usize) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.checks.get(ptr)) |check| {
            if (len > check.size) {
                return false;
            }
            const canary_ptr = @ptrCast(*u64, @alignCast(@alignOf(u64), ptr + check.size));
            return canary_ptr.* == self.canary_value;
        }
        return false;
    }
}; 