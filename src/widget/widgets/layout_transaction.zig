const std = @import("std");
const base = @import("base_widget.zig");
const layout = @import("../../layout/layout.zig");

pub const Snapshot = struct {
    widget: *base.Widget,
    rect: layout.Rect,
    dirty: bool,
    dirty_rect: ?layout.Rect,

    pub fn capture(widget: *base.Widget) Snapshot {
        return .{
            .widget = widget,
            .rect = widget.rect,
            .dirty = widget.dirty,
            .dirty_rect = widget.dirty_rect,
        };
    }

    pub fn restore(self: Snapshot) void {
        const bounds_changed = !std.meta.eql(self.widget.rect, self.rect);
        self.widget.rect = self.rect;
        self.widget.dirty = self.dirty;
        self.widget.dirty_rect = self.dirty_rect;

        if (bounds_changed) {
            if (self.widget.accessibility_update_bounds) |callback| {
                callback(self.widget.accessibility_ctx, self.widget, self.rect);
            }
        }
    }
};

pub fn rollback(snapshots: []const Snapshot) void {
    var index = snapshots.len;
    while (index > 0) {
        index -= 1;
        snapshots[index].restore();
    }
}
