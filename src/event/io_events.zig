const std = @import("std");
const event = @import("event.zig");

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
    /// Data associated with the event
    data: ?*anyopaque,
    /// Data size
    size: usize,
    /// Error message if status is error
    error_message: ?[]const u8,
    
    /// Clean up function for data
    cleanup_fn: ?*const fn(data: ?*anyopaque) void,
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
    running: bool = false,
    /// Thread handle
    thread: ?std.Thread = null,
    /// Allocator
    allocator: std.mem.Allocator,
    
    /// Initialize a file watcher
    pub fn init(allocator: std.mem.Allocator, path: []const u8, event_queue: *event.EventQueue, event_id: u32, target: ?*event.widget.Widget) !*FileWatchContext {
        const ctx = try allocator.create(FileWatchContext);
        ctx.* = FileWatchContext{
            .path = try allocator.dupe(u8, path),
            .event_queue = event_queue,
            .event_id = event_id,
            .target = target,
            .allocator = allocator,
        };
        return ctx;
    }
    
    /// Clean up resources
    pub fn deinit(self: *FileWatchContext) void {
        self.stop();
        self.allocator.free(self.path);
        self.allocator.destroy(self);
    }
    
    /// Start watching the file
    pub fn start(self: *FileWatchContext) !void {
        if (self.running) return;
        
        self.running = true;
        self.thread = try std.Thread.spawn(.{}, watchThreadFn, .{self});
    }
    
    /// Stop watching the file
    pub fn stop(self: *FileWatchContext) void {
        if (!self.running) return;
        
        self.running = false;
        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }
    }
};

/// Thread function for file watching
fn watchThreadFn(ctx: *FileWatchContext) void {
    var last_modified: i128 = 0;
    
    while (ctx.running) {
        // Check if file exists and get its modification time
        if (std.fs.cwd().statFile(ctx.path)) |stat| {
            const modified = stat.mtime;
            
            // If file was modified since the last check
            if (modified > last_modified and last_modified != 0) {
                // Create an IoEventData
                const data = ctx.allocator.create(IoEventData) catch continue;
                data.* = IoEventData{
                    .type = .file_watch,
                    .status = .success,
                    .data = null,
                    .size = 0,
                    .error_message = null,
                    .cleanup_fn = ioEventDataCleanup,
                };
                
                // Send an event
                ctx.event_queue.createCustomEvent(
                    ctx.event_id,
                    @ptrCast(data),
                    ioEventDataCleanup,
                    ctx.target
                ) catch {};
            }
            
            last_modified = modified;
        } else |_| {
            // File doesn't exist or can't be accessed
            last_modified = 0;
        }
        
        // Sleep for a bit to avoid high CPU usage
        std.time.sleep(std.time.ns_per_ms * 100);
    }
}

/// Cleanup function for IoEventData
fn ioEventDataCleanup(data: *anyopaque) void {
    const io_data = @as(*IoEventData, @ptrCast(@alignCast(data)));
    
    // Free error message if present
    if (io_data.error_message) |_| {
        // We need to know the allocator that created this data
        // Since we don't have it here, we assume the data itself doesn't own the error message
    }
    
    // Call cleanup function for inner data if present
    if (io_data.cleanup_fn != null and io_data.data != null) {
        io_data.cleanup_fn.?(io_data.data.?);
    }
    
    // Free the data itself - again, we don't have the allocator here
    // The allocator should be stored in the event system somewhere, or a global allocator used
}

/// Network connection context
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
    running: bool = false,
    /// Thread handle
    thread: ?std.Thread = null,
    /// Allocator
    allocator: std.mem.Allocator,
    /// Socket
    socket: ?std.net.Stream = null,
    /// Buffer for receiving data
    buffer: []u8,
    
    /// Initialize a network connection
    pub fn init(allocator: std.mem.Allocator, address: []const u8, port: u16, event_queue: *event.EventQueue, event_id: u32, target: ?*event.widget.Widget) !*NetworkContext {
        const ctx = try allocator.create(NetworkContext);
        ctx.* = NetworkContext{
            .address = try allocator.dupe(u8, address),
            .port = port,
            .event_queue = event_queue,
            .event_id = event_id,
            .target = target,
            .allocator = allocator,
            .buffer = try allocator.alloc(u8, 4096),
        };
        return ctx;
    }
    
    /// Clean up resources
    pub fn deinit(self: *NetworkContext) void {
        self.disconnect();
        self.allocator.free(self.address);
        self.allocator.free(self.buffer);
        self.allocator.destroy(self);
    }
    
    /// Connect to the server
    pub fn connect(self: *NetworkContext) !void {
        if (self.running) return;
        
        self.running = true;
        self.thread = try std.Thread.spawn(.{}, connectThreadFn, .{self});
    }
    
    /// Disconnect from the server
    pub fn disconnect(self: *NetworkContext) void {
        if (!self.running) return;
        
        self.running = false;
        if (self.socket) |*socket| {
            socket.close();
            self.socket = null;
        }
        
        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }
    }
    
    /// Send data to the server
    pub fn send(self: *NetworkContext, data: []const u8) !void {
        if (!self.running or self.socket == null) return error.NotConnected;
        
        _ = try self.socket.?.write(data);
    }
};

/// Thread function for network connection
fn connectThreadFn(ctx: *NetworkContext) void {
    // Try to connect to the server
    const address = std.net.Address.parseIp(ctx.address, ctx.port) catch {
        sendNetworkEvent(ctx, .network_error, .error_, "Invalid address or port", null, 0);
        return;
    };
    
    ctx.socket = std.net.tcpConnectToAddress(address) catch {
        sendNetworkEvent(ctx, .network_error, .error_, "Connection failed", null, 0);
        return;
    };
    
    // Send connect event
    sendNetworkEvent(ctx, .network_connect, .success, null, null, 0);
    
    // Read loop
    while (ctx.running) {
        const bytes_read = ctx.socket.?.read(ctx.buffer) catch {
            sendNetworkEvent(ctx, .network_error, .error_, "Read error", null, 0);
            break;
        };
        
        if (bytes_read == 0) {
            // Connection closed
            sendNetworkEvent(ctx, .network_disconnect, .success, null, null, 0);
            break;
        }
        
        // Copy the data for the event
        const data = ctx.allocator.dupe(u8, ctx.buffer[0..bytes_read]) catch continue;
        
        // Send data event
        sendNetworkEvent(ctx, .network_data, .success, null, data, bytes_read);
    }
    
    // Close socket if still open
    if (ctx.socket) |*socket| {
        socket.close();
        ctx.socket = null;
    }
}

/// Helper function to send a network event
fn sendNetworkEvent(ctx: *NetworkContext, event_type: IoEventType, status: IoStatus, error_msg: ?[]const u8, data: ?[]u8, size: usize) void {
    // Create an IoEventData
    const io_data = ctx.allocator.create(IoEventData) catch return;
    io_data.* = IoEventData{
        .type = event_type,
        .status = status,
        .data = if (data) |d| @ptrCast(d.ptr) else null,
        .size = size,
        .error_message = error_msg,
        .cleanup_fn = ioEventDataCleanup,
    };
    
    // Send an event
    ctx.event_queue.createCustomEvent(
        ctx.event_id,
        @ptrCast(io_data),
        ioEventDataCleanup,
        ctx.target
    ) catch {};
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
    next_event_id: u32 = 0x10000, // Start from a high number to avoid conflicts
    
    /// Initialize an I/O event manager
    pub fn init(allocator: std.mem.Allocator, event_queue: *event.EventQueue) IoEventManager {
        return IoEventManager{
            .event_queue = event_queue,
            .allocator = allocator,
            .file_watchers = std.ArrayList(*FileWatchContext).init(allocator),
            .network_connections = std.ArrayList(*NetworkContext).init(allocator),
        };
    }
    
    /// Clean up resources
    pub fn deinit(self: *IoEventManager) void {
        // Stop and free all file watchers
        for (self.file_watchers.items) |watcher| {
            watcher.deinit();
        }
        self.file_watchers.deinit();
        
        // Disconnect and free all network connections
        for (self.network_connections.items) |connection| {
            connection.deinit();
        }
        self.network_connections.deinit();
    }
    
    /// Create a file watcher
    pub fn watchFile(self: *IoEventManager, path: []const u8, target: ?*event.widget.Widget) !*FileWatchContext {
        const event_id = self.next_event_id;
        self.next_event_id += 1;
        
        const watcher = try FileWatchContext.init(
            self.allocator,
            path,
            self.event_queue,
            event_id,
            target
        );
        
        try self.file_watchers.append(watcher);
        try watcher.start();
        
        return watcher;
    }
    
    /// Create a network connection
    pub fn connectToServer(self: *IoEventManager, address: []const u8, port: u16, target: ?*event.widget.Widget) !*NetworkContext {
        const event_id = self.next_event_id;
        self.next_event_id += 1;
        
        const connection = try NetworkContext.init(
            self.allocator,
            address,
            port,
            self.event_queue,
            event_id,
            target
        );
        
        try self.network_connections.append(connection);
        try connection.connect();
        
        return connection;
    }
}; 