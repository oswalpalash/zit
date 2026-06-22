const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const compat = @import("../compat.zig");

pub const MemorySafety = struct {
    const Self = @This();
    const canary_len = @sizeOf(u64);

    const SafetyCheck = struct {
        ptr: [*]u8,
        size: usize,
        backing_size: usize,
        alignment: std.mem.Alignment,
        canary: [canary_len]u8,
    };

    parent_allocator: Allocator,
    checks: std.AutoHashMap([*]u8, SafetyCheck),
    mutex: compat.Mutex,
    canary_value: [canary_len]u8,

    pub fn init(parent_allocator: Allocator) !Self {
        var prng = std.Random.DefaultPrng.init(@bitCast(compat.nowMillis()));
        var canary: [canary_len]u8 = undefined;
        std.mem.writeInt(u64, &canary, prng.random().int(u64), .little);

        return Self{
            .parent_allocator = parent_allocator,
            .checks = std.AutoHashMap([*]u8, SafetyCheck).init(parent_allocator),
            .mutex = .{},
            .canary_value = canary,
        };
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var it = self.checks.iterator();
        while (it.next()) |entry| {
            const check = entry.value_ptr.*;
            self.parent_allocator.rawFree(check.ptr[0..check.backing_size], check.alignment, @returnAddress());
        }
        self.checks.deinit();
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

    fn backingSize(len: usize) ?usize {
        return std.math.add(usize, len, canary_len) catch null;
    }

    fn canarySlice(check: SafetyCheck) []u8 {
        return check.ptr[check.size..][0..canary_len];
    }

    fn writeCanary(canary: *const [canary_len]u8, check: SafetyCheck) void {
        @memcpy(canarySlice(check), canary);
    }

    fn isCanaryIntact(check: SafetyCheck) bool {
        return std.mem.eql(u8, canarySlice(check), &check.canary);
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.mutex.lock();
        defer self.mutex.unlock();

        const total_size = backingSize(len) orelse return null;
        const ptr = self.parent_allocator.rawAlloc(total_size, ptr_align, ret_addr) orelse return null;

        const check = SafetyCheck{
            .ptr = ptr,
            .size = len,
            .backing_size = total_size,
            .alignment = ptr_align,
            .canary = self.canary_value,
        };
        writeCanary(&self.canary_value, check);

        self.checks.put(ptr, check) catch {
            self.parent_allocator.rawFree(ptr[0..total_size], ptr_align, ret_addr);
            return null;
        };

        return ptr;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.mutex.lock();
        defer self.mutex.unlock();

        const new_backing_size = backingSize(new_len) orelse return false;

        if (self.checks.getPtr(buf.ptr)) |check| {
            if (buf_align != check.alignment or buf.len != check.size) return false;
            if (!isCanaryIntact(check.*)) @panic("Buffer overflow detected!");

            if (new_backing_size > check.backing_size) {
                const success = self.parent_allocator.rawResize(check.ptr[0..check.backing_size], check.alignment, new_backing_size, ret_addr);
                if (!success) return false;
                check.backing_size = new_backing_size;
            }

            check.size = new_len;
            writeCanary(&check.canary, check.*);
            return true;
        }

        return self.parent_allocator.rawResize(buf, buf_align, new_len, ret_addr);
    }

    fn remap(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.mutex.lock();
        defer self.mutex.unlock();

        const new_backing_size = backingSize(new_len) orelse return null;

        if (self.checks.getPtr(buf.ptr)) |check| {
            if (buf_align != check.alignment or buf.len != check.size) return null;
            if (!isCanaryIntact(check.*)) @panic("Buffer overflow detected!");

            if (new_backing_size > check.backing_size) {
                const success = self.parent_allocator.rawResize(check.ptr[0..check.backing_size], check.alignment, new_backing_size, ret_addr);
                if (!success) return null;
                check.backing_size = new_backing_size;
            }

            check.size = new_len;
            writeCanary(&check.canary, check.*);
            return check.ptr;
        }

        return self.parent_allocator.rawRemap(buf, buf_align, new_len, ret_addr);
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.checks.fetchRemove(buf.ptr)) |entry| {
            const check = entry.value;

            if (buf_align != check.alignment or buf.len != check.size) {
                @panic("Invalid allocation metadata passed to MemorySafety.free");
            }
            if (!isCanaryIntact(check)) @panic("Buffer overflow detected!");

            self.parent_allocator.rawFree(check.ptr[0..check.backing_size], check.alignment, ret_addr);
            return;
        }

        self.parent_allocator.rawFree(buf, buf_align, ret_addr);
    }

    pub fn checkAllocations(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var it = self.checks.iterator();
        while (it.next()) |entry| {
            const check = entry.value_ptr;
            if (!isCanaryIntact(check.*)) {
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
            return isCanaryIntact(check);
        }
        return false;
    }
};
