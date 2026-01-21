const std = @import("std");
const theme = @import("widget/theme.zig");
const event = @import("event/event.zig");

/// Watches a theme config file and reloads it whenever it changes.
pub const ThemeHotReloader = struct {
    allocator: std.mem.Allocator,
    app: *event.Application,
    path: []const u8,
    watcher: ?*event.io_events.FileWatchContext = null,
    listener_id: ?u32 = null,
    current: theme.Theme,
    on_reload: ?ReloadFn = null,
    ctx: ?*anyopaque = null,

    pub const ReloadFn = *const fn (theme.Theme, ?*anyopaque) void;

    /// Start watching `path` and return a managed reloader.
    ///
    /// Parameters:
    /// - `allocator`: allocator used to duplicate the path and hold registry state.
    /// - `app`: running `Application` whose event loop drives reload notifications.
    /// - `path`: filesystem path to the theme TOML/JSON file to monitor.
    /// - `fallback`: theme to use when the file cannot be read or parsed.
    /// - `on_reload`: optional callback invoked after each successful reload.
    /// - `ctx`: opaque pointer forwarded to `on_reload`.
    /// Returns: heap-allocated reloader handle that must be stopped to free resources.
    /// Example:
    /// ```zig
    /// var reloader = try ThemeHotReloader.start(alloc, &app, "theme.toml", theme.Theme.dark(), myReload, null);
    /// defer reloader.stop();
    /// ```
    pub fn start(allocator: std.mem.Allocator, app: *event.Application, path: []const u8, fallback: theme.Theme, on_reload: ?ReloadFn, ctx: ?*anyopaque) !*ThemeHotReloader {
        initRegistry(allocator);
        const cloned_path = try allocator.dupe(u8, path);
        errdefer allocator.free(cloned_path);

        const loaded = try theme.loadFromFile(allocator, cloned_path, fallback);

        const self = try allocator.create(ThemeHotReloader);
        self.* = ThemeHotReloader{
            .allocator = allocator,
            .app = app,
            .path = cloned_path,
            .current = loaded,
            .on_reload = on_reload,
            .ctx = ctx,
        };

        self.watcher = try app.watchFile(cloned_path, null);
        errdefer self.stop();

        const listener_id = try app.addEventListener(.custom, onCustomEvent, null);
        self.listener_id = listener_id;
        try registry.put(self.watcher.?.event_id, self);
        return self;
    }

    /// Stop watching and free resources.
    ///
    /// Parameters:
    /// - `self`: reloader created by `start`.
    /// Returns: nothing. All registered listeners and file watches are removed.
    /// Example:
    /// ```zig
    /// const reloader = try ThemeHotReloader.start(alloc, &app, "theme.toml", theme.Theme.dark(), null, null);
    /// defer reloader.stop();
    /// ```
    pub fn stop(self: *ThemeHotReloader) void {
        if (self.listener_id) |id| {
            _ = self.app.removeEventListener(id);
            self.listener_id = null;
        }

        if (self.watcher) |watcher| {
            _ = registry.remove(watcher.event_id);
            watcher.deinit();
            self.watcher = null;
        }

        self.allocator.free(self.path);
        self.allocator.destroy(self);
    }

    fn reload(self: *ThemeHotReloader) void {
        const updated = theme.loadFromFile(self.allocator, self.path, self.current) catch self.current;
        self.current = updated;
        if (self.on_reload) |cb| cb(updated, self.ctx);
    }
};

var registry_ready = false;
var registry_allocator: std.mem.Allocator = undefined;
var registry: std.AutoHashMap(u32, *ThemeHotReloader) = undefined;

fn initRegistry(allocator: std.mem.Allocator) void {
    if (registry_ready) return;
    registry_allocator = allocator;
    registry = std.AutoHashMap(u32, *ThemeHotReloader).init(registry_allocator);
    registry_ready = true;
}

fn onCustomEvent(ev: *event.Event) bool {
    if (ev.type != .custom) return false;
    if (!registry_ready) return false;

    const id = ev.data.custom.id;
    if (registry.get(id)) |reloader_ptr| {
        reloader_ptr.*.reload();
        return true;
    }

    return false;
}
