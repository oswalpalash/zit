const std = @import("std");
const event = @import("event.zig");
const compat = @import("../compat.zig");

const file_watch_poll_ms: u64 = 100;
const network_read_buffer_bytes: usize = 4096;
const default_event_id_start: u32 = 0x10000;

/// Module for handling file and network I/O events
/// Using thread-based approach since async/await isn't fully implemented in Zig 0.14.0
/// I/O Event Types
pub const IoEventType = enum {
    /// File system events
    file_read,
    file_write,
    file_open,
    file_close,
    file_watch,

    /// Network events
    network_connect,
    network_disconnect,
    network_data,
    network_error,
};

/// I/O Event Data
pub const IoEventData = struct {
    /// Event type
    type: IoEventType,
    /// Status of the operation
    status: IoStatus,
    /// Allocator used for payload and self cleanup
    allocator: std.mem.Allocator,
    /// Data associated with the event
    data: ?*anyopaque,
    /// Data size
    size: usize,
    /// Error message if status is error
    error_message: ?[]const u8,

    /// Clean up function for owned payloads
    payload_cleanup: ?*const fn (data: ?*anyopaque) void = null,
    /// Whether `data` should be freed as a byte slice
    owns_payload: bool = false,
    /// Whether `error_message` is owned and should be freed
    owns_error_message: bool = false,
};

/// I/O Operation Status
pub const IoStatus = enum {
    /// Operation completed successfully
    success,
    /// Operation in progress
    pending,
    /// Operation failed
    error_,
    /// Operation was cancelled
    cancelled,
};

/// File watcher context
pub const FileWatchContext = struct {
    /// Path to watch
    path: []const u8,
    /// Event queue to send events to
    event_queue: *event.EventQueue,
    /// Event ID to use for custom events
    event_id: u32,
    /// Target widget to send events to
    target: ?*event.widget.Widget,
    /// Whether the watcher is running
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    /// Thread handle
    thread: ?std.Thread = null,
    /// Allocator
    allocator: std.mem.Allocator,

    /// Initialize a file watcher
    ///
    /// Parameters:
    /// - `allocator`: allocator used for the watcher, emitted events, and cleanup.
    /// - `path`: file path to poll for modification time changes.
    /// - `event_queue`: queue that receives `custom` events.
    /// - `event_id`: identifier used when emitting file watch events.
    /// - `target`: optional widget to tag as the event target.
    /// Returns: allocated file watch context.
    /// Errors: allocation failures when duplicating the path or allocating the context.
    /// Example:
    /// ```
    /// const watcher = try manager.watchFile("log.txt", null);
    /// defer watcher.deinit();
    /// ```
    pub fn init(allocator: std.mem.Allocator, path: []const u8, event_queue: *event.EventQueue, event_id: u32, target: ?*event.widget.Widget) !*FileWatchContext {
        const ctx = try allocator.create(FileWatchContext);
        errdefer allocator.destroy(ctx);
        const owned_path = try allocator.dupe(u8, path);
        ctx.* = FileWatchContext{
            .path = owned_path,
            .event_queue = event_queue,
            .event_id = event_id,
            .target = target,
            .allocator = allocator,
        };
        return ctx;
    }

    /// Clean up resources
    ///
    /// Parameters:
    /// - `self`: watcher to tear down.
    /// Safety: Idempotent; safe to call after `stop`.
    pub fn deinit(self: *FileWatchContext) void {
        self.stop();
        self.allocator.free(self.path);
        self.allocator.destroy(self);
    }

    /// Start watching the file
    ///
    /// Parameters:
    /// - `self`: watcher to activate.
    /// Returns: success when the worker thread is spawned.
    /// Errors: allocation or thread creation failures.
    pub fn start(self: *FileWatchContext) !void {
        if (self.running.load(.acquire)) return;

        self.running.store(true, .release);
        self.thread = std.Thread.spawn(.{}, watchThreadFn, .{self}) catch |err| {
            self.running.store(false, .release);
            return err;
        };
    }

    /// Stop watching the file
    ///
    /// Parameters:
    /// - `self`: watcher to stop.
    /// Safety: Joins the worker thread before returning.
    pub fn stop(self: *FileWatchContext) void {
        if (!self.running.load(.acquire) and self.thread == null) return;

        self.running.store(false, .release);
        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }
    }
};

/// Thread function for file watching
fn watchThreadFn(ctx: *FileWatchContext) void {
    var last_modified: ?std.Io.Timestamp = null;

    while (ctx.running.load(.acquire)) {
        // Check if file exists and get its modification time
        const io = std.Io.Threaded.global_single_threaded.io();
        const cwd = std.Io.Dir.cwd();
        if (cwd.statFile(io, ctx.path, .{})) |stat| {
            const modified = stat.mtime;

            // If file was modified since the last check
            if (last_modified) |previous| {
                if (modified.nanoseconds > previous.nanoseconds) {
                    const data = createIoEventData(ctx.allocator, .file_watch, .success, null, false, null, 0, null, false) catch continue;
                    _ = postIoEventData(ctx.event_queue, ctx.event_id, data, ctx.target);
                }
            }

            last_modified = modified;
        } else |_| {
            // File doesn't exist or can't be accessed
            last_modified = null;
        }

        // Sleep for a bit to avoid high CPU usage
        compat.sleepMillis(file_watch_poll_ms);
    }
}

/// Cleanup function for IoEventData
fn ioEventDataCleanup(data: *anyopaque) void {
    const io_data = @as(*IoEventData, @ptrCast(@alignCast(data)));

    cleanupIoEventOwnedFields(
        io_data.allocator,
        io_data.data,
        io_data.size,
        io_data.payload_cleanup,
        io_data.owns_payload,
        io_data.error_message,
        io_data.owns_error_message,
    );

    // Destroy the IoEventData itself
    io_data.allocator.destroy(io_data);
}

fn cleanupIoEventOwnedFields(
    allocator: std.mem.Allocator,
    data: ?*anyopaque,
    size: usize,
    payload_cleanup: ?*const fn (data: ?*anyopaque) void,
    owns_payload: bool,
    error_message: ?[]const u8,
    owns_error_message: bool,
) void {
    if (owns_error_message) {
        if (error_message) |msg| allocator.free(msg);
    }

    if (payload_cleanup != null and data != null) {
        payload_cleanup.?(data);
    } else if (owns_payload and data != null) {
        const bytes = @as([*]u8, @ptrCast(data.?))[0..size];
        allocator.free(bytes);
    }
}

fn createIoEventData(
    allocator: std.mem.Allocator,
    event_type: IoEventType,
    status: IoStatus,
    error_message: ?[]const u8,
    owns_error_message: bool,
    data: ?*anyopaque,
    size: usize,
    payload_cleanup: ?*const fn (data: ?*anyopaque) void,
    owns_payload: bool,
) !*IoEventData {
    const io_data = allocator.create(IoEventData) catch |err| {
        cleanupIoEventOwnedFields(allocator, data, size, payload_cleanup, owns_payload, error_message, owns_error_message);
        return err;
    };
    io_data.* = IoEventData{
        .type = event_type,
        .status = status,
        .allocator = allocator,
        .data = data,
        .size = size,
        .error_message = error_message,
        .payload_cleanup = payload_cleanup,
        .owns_payload = owns_payload,
        .owns_error_message = owns_error_message,
    };
    return io_data;
}

fn postIoEventData(queue: *event.EventQueue, event_id: u32, io_data: *IoEventData, target: ?*event.widget.Widget) bool {
    queue.createCustomEvent(event_id, @ptrCast(io_data), ioEventDataCleanup, target) catch |err| {
        std.log.debug("zit.event.io: dropping {s} event after enqueue failure: {s}", .{ @tagName(io_data.type), @errorName(err) });
        ioEventDataCleanup(@ptrCast(io_data));
        return false;
    };
    return true;
}

/// Network connection context.
///
/// Transport is currently unsupported on the Zig 0.16 baseline. Connecting starts a worker
/// that emits `.network_error`; the type remains available so callers can handle this
/// capability explicitly while the transport is rebuilt.
pub const NetworkContext = struct {
    /// Server address
    address: []const u8,
    /// Port
    port: u16,
    /// Event queue to send events to
    event_queue: *event.EventQueue,
    /// Event ID to use for custom events
    event_id: u32,
    /// Target widget to send events to
    target: ?*event.widget.Widget,
    /// Whether the connection is running
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    /// Thread handle
    thread: ?std.Thread = null,
    /// Allocator
    allocator: std.mem.Allocator,
    /// Whether a transport is connected.
    socket_connected: bool = false,
    /// Buffer for receiving data
    buffer: []u8,

    /// Initialize a network connection
    ///
    /// Parameters:
    /// - `allocator`: allocator used for connection state, buffers, and event payloads.
    /// - `address`: IPv4/IPv6 address string to connect to.
    /// - `port`: destination port.
    /// - `event_queue`: queue that receives `custom` events.
    /// - `event_id`: identifier used for emitted network events.
    /// - `target`: optional widget to tag as the event target.
    /// Returns: allocated network context.
    /// Errors: allocation failures for the context, address, or buffer.
    /// Example:
    /// ```
    /// const conn = try manager.connectToServer("127.0.0.1", 8080, null);
    /// defer conn.deinit();
    /// ```
    pub fn init(allocator: std.mem.Allocator, address: []const u8, port: u16, event_queue: *event.EventQueue, event_id: u32, target: ?*event.widget.Widget) !*NetworkContext {
        const ctx = try allocator.create(NetworkContext);
        errdefer allocator.destroy(ctx);
        const owned_address = try allocator.dupe(u8, address);
        errdefer allocator.free(owned_address);
        const buffer = try allocator.alloc(u8, network_read_buffer_bytes);
        ctx.* = NetworkContext{
            .address = owned_address,
            .port = port,
            .event_queue = event_queue,
            .event_id = event_id,
            .target = target,
            .allocator = allocator,
            .buffer = buffer,
        };
        return ctx;
    }

    /// Clean up resources
    ///
    /// Parameters:
    /// - `self`: network context to destroy.
    /// Safety: Idempotent; ensures socket is closed and thread joined.
    pub fn deinit(self: *NetworkContext) void {
        self.disconnect();
        self.allocator.free(self.address);
        self.allocator.free(self.buffer);
        self.allocator.destroy(self);
    }

    /// Connect to the server
    ///
    /// Parameters:
    /// - `self`: network context to connect.
    /// Returns: success when the worker thread is spawned.
    /// Errors: thread creation failures.
    pub fn connect(self: *NetworkContext) !void {
        if (self.running.load(.acquire)) return;

        self.running.store(true, .release);
        self.thread = std.Thread.spawn(.{}, connectThreadFn, .{self}) catch |err| {
            self.running.store(false, .release);
            return err;
        };
    }

    /// Disconnect from the server
    ///
    /// Parameters:
    /// - `self`: network context to close.
    /// Safety: Joins the worker thread and closes the socket.
    pub fn disconnect(self: *NetworkContext) void {
        if (!self.running.load(.acquire) and self.thread == null) return;

        self.running.store(false, .release);
        self.socket_connected = false;

        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }
    }

    /// Send data to the server
    ///
    /// Parameters:
    /// - `self`: active network context.
    /// - `data`: bytes to write to the socket.
    /// Returns: success when the write succeeds.
    /// Errors: `error.NotConnected` if the socket is not established, or any socket write error.
    pub fn send(self: *NetworkContext, data: []const u8) !void {
        _ = data;
        if (!self.running.load(.acquire) or !self.socket_connected) return error.NotConnected;
        return error.Unsupported;
    }
};

/// Thread function for network connection
fn connectThreadFn(ctx: *NetworkContext) void {
    _ = sendNetworkEvent(ctx, .network_error, .error_, "Network I/O is unsupported on this Zig baseline", null);
    ctx.running.store(false, .release);
}

/// Helper function to send a network event
fn sendNetworkEvent(ctx: *NetworkContext, event_type: IoEventType, status: IoStatus, error_msg: ?[]const u8, owned_data: ?[]u8) bool {
    const io_data = createIoEventData(
        ctx.allocator,
        event_type,
        status,
        error_msg,
        false,
        if (owned_data) |bytes| @ptrCast(bytes.ptr) else null,
        if (owned_data) |bytes| bytes.len else 0,
        null,
        owned_data != null,
    ) catch |err| {
        std.log.debug("zit.event.io: dropping {s} event after allocation failure: {s}", .{ @tagName(event_type), @errorName(err) });
        return false;
    };

    return postIoEventData(ctx.event_queue, ctx.event_id, io_data, ctx.target);
}

/// I/O event manager to simplify working with I/O events
pub const IoEventManager = struct {
    /// Event queue to send events to
    event_queue: *event.EventQueue,
    /// Allocator
    allocator: std.mem.Allocator,
    /// File watchers
    file_watchers: std.ArrayList(*FileWatchContext),
    /// Network connections
    network_connections: std.ArrayList(*NetworkContext),
    /// Next event ID
    next_event_id: u32 = default_event_id_start, // Start from a high number to avoid conflicts

    /// Initialize an I/O event manager
    ///
    /// Parameters:
    /// - `allocator`: allocator used for watchers, connections, and events.
    /// - `event_queue`: queue that receives emitted custom events.
    /// Returns: initialized manager with empty watcher/connection sets.
    /// Example:
    /// ```
    /// var manager = IoEventManager.init(alloc, queue);
    /// defer manager.deinit();
    /// ```
    pub fn init(allocator: std.mem.Allocator, event_queue: *event.EventQueue) IoEventManager {
        return IoEventManager{
            .event_queue = event_queue,
            .allocator = allocator,
            .file_watchers = std.ArrayList(*FileWatchContext).empty,
            .network_connections = std.ArrayList(*NetworkContext).empty,
        };
    }

    /// Clean up resources
    ///
    /// Parameters:
    /// - `self`: manager to tear down.
    /// Safety: Stops all watches and network connections before freeing.
    pub fn deinit(self: *IoEventManager) void {
        // Stop and free all file watchers
        for (self.file_watchers.items) |watcher| {
            watcher.deinit();
        }
        self.file_watchers.deinit(self.allocator);

        // Disconnect and free all network connections
        for (self.network_connections.items) |connection| {
            connection.deinit();
        }
        self.network_connections.deinit(self.allocator);
    }

    /// Create a file watcher
    ///
    /// Parameters:
    /// - `self`: manager used to allocate and track the watcher.
    /// - `path`: file path to poll for modifications.
    /// - `target`: widget to tag as the event target; may be null.
    /// Returns: started file watcher context.
    /// Errors: allocation failures, thread spawn failures, or duplicate path allocation errors.
    /// Example:
    /// ```
    /// var manager = IoEventManager.init(alloc, queue);
    /// defer manager.deinit();
    /// const watch = try manager.watchFile("log.txt", null);
    /// defer _ = manager.unwatchFile(watch);
    /// ```
    pub fn watchFile(self: *IoEventManager, path: []const u8, target: ?*event.widget.Widget) !*FileWatchContext {
        const event_id = self.next_event_id;
        const watcher = try FileWatchContext.init(self.allocator, path, self.event_queue, event_id, target);
        errdefer watcher.deinit();

        try self.file_watchers.append(self.allocator, watcher);
        errdefer _ = self.file_watchers.pop();

        try watcher.start();

        self.next_event_id += 1;
        return watcher;
    }

    /// Stop, unregister, and destroy a file watcher returned by `watchFile`.
    ///
    /// Returns `true` when the watcher belonged to this manager. Returned
    /// watcher pointers are manager-owned; use this method instead of calling
    /// `watcher.deinit()` directly.
    pub fn unwatchFile(self: *IoEventManager, watcher: *FileWatchContext) bool {
        for (self.file_watchers.items, 0..) |item, idx| {
            if (item == watcher) {
                _ = self.file_watchers.orderedRemove(idx);
                watcher.deinit();
                return true;
            }
        }

        return false;
    }

    /// Create a network connection context.
    ///
    /// Current behavior: starts a worker that emits `.network_error` because network
    /// transport is not yet implemented for the Zig 0.16 baseline.
    ///
    /// Parameters:
    /// - `self`: manager used to allocate and track the connection.
    /// - `address`: IPv4/IPv6 address string.
    /// - `port`: destination port.
    /// - `target`: widget to tag as the event target; may be null.
    /// Returns: started network context.
    /// Errors: allocation failures or thread spawn failures.
    /// Example:
    /// ```
    /// var manager = IoEventManager.init(alloc, queue);
    /// defer manager.deinit();
    /// const conn = try manager.connectToServer("127.0.0.1", 5555, null);
    /// defer _ = manager.disconnectFromServer(conn);
    /// ```
    pub fn connectToServer(self: *IoEventManager, address: []const u8, port: u16, target: ?*event.widget.Widget) !*NetworkContext {
        const event_id = self.next_event_id;
        const connection = try NetworkContext.init(self.allocator, address, port, self.event_queue, event_id, target);
        errdefer connection.deinit();

        try self.network_connections.append(self.allocator, connection);
        errdefer _ = self.network_connections.pop();

        try connection.connect();

        self.next_event_id += 1;
        return connection;
    }

    /// Disconnect, unregister, and destroy a network context returned by `connectToServer`.
    ///
    /// Returns `true` when the connection belonged to this manager. Returned
    /// connection pointers are manager-owned; use this method instead of calling
    /// `connection.deinit()` directly.
    pub fn disconnectFromServer(self: *IoEventManager, connection: *NetworkContext) bool {
        for (self.network_connections.items, 0..) |item, idx| {
            if (item == connection) {
                _ = self.network_connections.orderedRemove(idx);
                connection.deinit();
                return true;
            }
        }

        return false;
    }
};

test "ioEventDataCleanup frees owned payloads" {
    const alloc = std.testing.allocator;
    const payload = try alloc.dupe(u8, "ping");
    const ptr = try alloc.create(IoEventData);
    ptr.* = IoEventData{
        .type = .network_data,
        .status = .success,
        .allocator = alloc,
        .data = @ptrCast(payload.ptr),
        .size = payload.len,
        .error_message = null,
        .payload_cleanup = null,
        .owns_payload = true,
        .owns_error_message = false,
    };

    ioEventDataCleanup(@ptrCast(ptr));
}

test "createIoEventData frees owned payload when wrapper allocation fails" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const alloc = failing.allocator();
    const payload = try alloc.dupe(u8, "packet");

    failing.fail_index = failing.alloc_index;

    try std.testing.expectError(
        error.OutOfMemory,
        createIoEventData(alloc, .network_data, .success, null, false, @ptrCast(payload.ptr), payload.len, null, true),
    );
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
}

test "file watch context init cleans context when path allocation fails" {
    const alloc = std.testing.allocator;
    var queue = event.EventQueue.init(alloc);
    defer queue.deinit();

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 1 });

    try std.testing.expectError(
        error.OutOfMemory,
        FileWatchContext.init(failing.allocator(), "watched.txt", &queue, 1, null),
    );
}

test "network context init cleans partial allocations when buffer allocation fails" {
    const alloc = std.testing.allocator;
    var queue = event.EventQueue.init(alloc);
    defer queue.deinit();

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 2 });

    try std.testing.expectError(
        error.OutOfMemory,
        NetworkContext.init(failing.allocator(), "127.0.0.1", 8080, &queue, 1, null),
    );
}

test "file watcher stop clears atomic running flag and joins thread" {
    const alloc = std.testing.allocator;
    var queue = event.EventQueue.init(alloc);
    defer queue.deinit();

    const watcher = try FileWatchContext.init(alloc, "definitely-missing-zit-watch-file.txt", &queue, 1, null);
    defer watcher.deinit();

    try watcher.start();
    try std.testing.expect(watcher.running.load(.acquire));

    watcher.stop();
    try std.testing.expect(!watcher.running.load(.acquire));
    try std.testing.expect(watcher.thread == null);

    watcher.stop();
    try std.testing.expect(!watcher.running.load(.acquire));
    try std.testing.expect(watcher.thread == null);
}

test "network disconnect joins worker after it reports completion" {
    const alloc = std.testing.allocator;
    var queue = event.EventQueue.init(alloc);
    defer queue.deinit();

    const connection = try NetworkContext.init(alloc, "127.0.0.1", 8080, &queue, 1, null);
    defer connection.deinit();

    try connection.connect();

    var attempts: usize = 0;
    while (connection.running.load(.acquire) and attempts < 1000) : (attempts += 1) {
        compat.sleepMillis(1);
    }
    try std.testing.expect(!connection.running.load(.acquire));

    connection.disconnect();
    try std.testing.expect(!connection.running.load(.acquire));
    try std.testing.expect(connection.thread == null);
}

test "watchFile preserves manager state when registration allocation fails" {
    const alloc = std.testing.allocator;
    var queue = event.EventQueue.init(alloc);
    defer queue.deinit();

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 2 });
    var manager = IoEventManager.init(failing.allocator(), &queue);
    defer manager.deinit();

    const original_next_id = manager.next_event_id;

    try std.testing.expectError(error.OutOfMemory, manager.watchFile("watched.txt", null));
    try std.testing.expectEqual(original_next_id, manager.next_event_id);
    try std.testing.expectEqual(@as(usize, 0), manager.file_watchers.items.len);
}

test "unwatchFile unregisters and destroys manager-owned watcher" {
    const alloc = std.testing.allocator;
    var queue = event.EventQueue.init(alloc);
    defer queue.deinit();

    var manager = IoEventManager.init(alloc, &queue);
    defer manager.deinit();

    const watcher = try manager.watchFile("definitely-missing-zit-watch-file.txt", null);
    try std.testing.expectEqual(@as(usize, 1), manager.file_watchers.items.len);
    try std.testing.expect(watcher.running.load(.acquire));

    try std.testing.expect(manager.unwatchFile(watcher));
    try std.testing.expectEqual(@as(usize, 0), manager.file_watchers.items.len);
    try std.testing.expect(!manager.unwatchFile(watcher));
}

test "connectToServer preserves manager state when registration allocation fails" {
    const alloc = std.testing.allocator;
    var queue = event.EventQueue.init(alloc);
    defer queue.deinit();

    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 3 });
    var manager = IoEventManager.init(failing.allocator(), &queue);
    defer manager.deinit();

    const original_next_id = manager.next_event_id;

    try std.testing.expectError(error.OutOfMemory, manager.connectToServer("127.0.0.1", 8080, null));
    try std.testing.expectEqual(original_next_id, manager.next_event_id);
    try std.testing.expectEqual(@as(usize, 0), manager.network_connections.items.len);
}

test "disconnectFromServer unregisters and destroys manager-owned connection" {
    const alloc = std.testing.allocator;
    var queue = event.EventQueue.init(alloc);
    defer queue.deinit();

    var manager = IoEventManager.init(alloc, &queue);
    defer manager.deinit();

    const connection = try manager.connectToServer("127.0.0.1", 8080, null);
    try std.testing.expectEqual(@as(usize, 1), manager.network_connections.items.len);

    try std.testing.expect(manager.disconnectFromServer(connection));
    try std.testing.expectEqual(@as(usize, 0), manager.network_connections.items.len);
    try std.testing.expect(!manager.disconnectFromServer(connection));
}

test "sendNetworkEvent frees owned payload when event allocation fails" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const alloc = failing.allocator();

    var queue = event.EventQueue.init(alloc);
    defer queue.deinit();

    var buffer: [0]u8 = .{};
    var ctx = NetworkContext{
        .address = "127.0.0.1",
        .port = 8080,
        .event_queue = &queue,
        .event_id = 1,
        .target = null,
        .allocator = alloc,
        .buffer = buffer[0..],
    };

    const payload = try alloc.dupe(u8, "packet");
    failing.fail_index = failing.alloc_index;

    try std.testing.expect(!sendNetworkEvent(&ctx, .network_data, .success, null, payload));
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectEqual(@as(usize, 0), queue.queue.items.len);
    try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
}

test "postIoEventData cleans payload when enqueue fails" {
    const alloc = std.testing.allocator;
    var failing = std.testing.FailingAllocator.init(alloc, .{ .fail_index = 1 });
    const fail_alloc = failing.allocator();

    var queue = event.EventQueue.init(fail_alloc);
    defer queue.deinit();

    var cleaned = false;
    const Hooks = struct {
        fn cleanup(data: ?*anyopaque) void {
            const flag = @as(*bool, @ptrCast(@alignCast(data.?)));
            flag.* = true;
        }
    };

    const ptr = try fail_alloc.create(IoEventData);
    ptr.* = IoEventData{
        .type = .network_data,
        .status = .success,
        .allocator = fail_alloc,
        .data = @ptrCast(&cleaned),
        .size = 0,
        .error_message = null,
        .payload_cleanup = Hooks.cleanup,
        .owns_payload = false,
        .owns_error_message = false,
    };

    try std.testing.expect(!postIoEventData(&queue, 1, ptr, null));

    try std.testing.expect(cleaned);
    try std.testing.expectEqual(@as(usize, 0), queue.queue.items.len);
}
