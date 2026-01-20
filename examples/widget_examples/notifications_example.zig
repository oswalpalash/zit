const std = @import("std");
const zit = @import("zit");
const render = zit.render;
const layout = zit.layout;
const widget = zit.widget;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var renderer = try render.Renderer.init(allocator, 60, 16);
    defer renderer.deinit();

    // Menu bar pinned to the top.
    var menu = try widget.MenuBar.init(allocator);
    defer menu.deinit();
    try menu.addItem("File", null);
    try menu.addItem("Help", null);
    try menu.widget.layout(layout.Rect.init(0, 0, 60, 1));

    // Toast stack in the lower right.
    var toasts = try widget.ToastManager.init(allocator);
    defer toasts.deinit();
    try toasts.push("Saved", .success, 2);
    try toasts.push("Syncing…", .info, 4);
    try toasts.widget.layout(layout.Rect.init(35, 9, 24, 6));

    // Popup centered message.
    var popup = try widget.Popup.init(allocator, "Press any key to close");
    defer popup.deinit();
    try popup.widget.layout(layout.Rect.init(15, 3, 30, 6));

    // Canvas with a quick doodle.
    var canvas = try widget.Canvas.init(allocator, 20, 6);
    defer canvas.deinit();
    canvas.drawLine(0, 0, 19, 5, '*', render.Color.named(render.NamedColor.yellow), render.Color.named(render.NamedColor.black), render.Style{});
    canvas.drawRect(2, 1, 8, 3, '#', render.Color.named(render.NamedColor.green), render.Color.named(render.NamedColor.black), render.Style{});
    try canvas.widget.layout(layout.Rect.init(2, 8, 24, 6));

    try menu.widget.draw(&renderer);
    try popup.widget.draw(&renderer);
    try toasts.widget.draw(&renderer);
    try canvas.widget.draw(&renderer);

    // Flush the buffer to stdout for quick inspection.
    try renderer.render();
}
