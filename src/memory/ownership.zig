const std = @import("std");
const Allocator = std.mem.Allocator;

pub const RefCounted = struct {
    const Self = @This();
    
    ref_count: usize,
    mutex: std.Thread.Mutex,

    pub fn init() Self {
        return Self{
            .ref_count = 1,
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn acquire(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.ref_count += 1;
    }

    pub fn release(self: *Self) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.ref_count -= 1;
        return self.ref_count == 0;
    }

    pub fn getCount(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.ref_count;
    }
};

pub const WeakRef = struct {
    const Self = @This();
    
    ptr: ?*anyopaque,
    cleanup_fn: *const fn (*anyopaque) void,

    pub fn init(ptr: *anyopaque, cleanup_fn: *const fn (*anyopaque) void) Self {
        return Self{
            .ptr = ptr,
            .cleanup_fn = cleanup_fn,
        };
    }

    pub fn getPtr(self: *Self) ?*anyopaque {
        return self.ptr;
    }

    pub fn clear(self: *Self) void {
        if (self.ptr) |ptr| {
            self.cleanup_fn(ptr);
            self.ptr = null;
        }
    }
};

pub const WidgetNode = struct {
    const Self = @This();
    
    parent: ?*Self,
    first_child: ?*Self,
    last_child: ?*Self,
    next_sibling: ?*Self,
    prev_sibling: ?*Self,
    ref_count: RefCounted,
    weak_refs: std.ArrayList(WeakRef),
    allocator: Allocator,

    pub fn init(allocator: Allocator) !Self {
        return Self{
            .parent = null,
            .first_child = null,
            .last_child = null,
            .next_sibling = null,
            .prev_sibling = null,
            .ref_count = RefCounted.init(),
            .weak_refs = std.ArrayList(WeakRef).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        // Clear all weak references
        for (self.weak_refs.items) |*weak_ref| {
            weak_ref.clear();
        }
        self.weak_refs.deinit();

        // Detach from parent
        if (self.parent) |parent| {
            if (self.prev_sibling) |prev| {
                prev.next_sibling = self.next_sibling;
            } else {
                parent.first_child = self.next_sibling;
            }
            if (self.next_sibling) |next| {
                next.prev_sibling = self.prev_sibling;
            } else {
                parent.last_child = self.prev_sibling;
            }
        }

        // Recursively deinit children
        var child = self.first_child;
        while (child) |c| {
            const next = c.next_sibling;
            c.deinit();
            child = next;
        }
    }

    pub fn addChild(self: *Self, child: *Self) void {
        // Remove from current parent if any
        if (child.parent) |parent| {
            if (child.prev_sibling) |prev| {
                prev.next_sibling = child.next_sibling;
            } else {
                parent.first_child = child.next_sibling;
            }
            if (child.next_sibling) |next| {
                next.prev_sibling = child.prev_sibling;
            } else {
                parent.last_child = child.prev_sibling;
            }
        }

        // Add to new parent
        child.parent = self;
        child.prev_sibling = self.last_child;
        child.next_sibling = null;

        if (self.last_child) |last| {
            last.next_sibling = child;
        } else {
            self.first_child = child;
        }
        self.last_child = child;
    }

    pub fn removeChild(self: *Self, child: *Self) void {
        if (child.parent != self) return;

        if (child.prev_sibling) |prev| {
            prev.next_sibling = child.next_sibling;
        } else {
            self.first_child = child.next_sibling;
        }
        if (child.next_sibling) |next| {
            next.prev_sibling = child.prev_sibling;
        } else {
            self.last_child = child.prev_sibling;
        }

        child.parent = null;
        child.prev_sibling = null;
        child.next_sibling = null;
    }

    pub fn addWeakRef(self: *Self, weak_ref: WeakRef) !void {
        try self.weak_refs.append(weak_ref);
    }

    pub fn removeWeakRef(self: *Self, ptr: *anyopaque) void {
        for (self.weak_refs.items, 0..) |weak_ref, i| {
            if (weak_ref.ptr == ptr) {
                _ = self.weak_refs.swapRemove(i);
                return;
            }
        }
    }
}; 