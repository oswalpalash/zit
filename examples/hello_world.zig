const zit = @import("zit");

pub fn main() !void {
    try zit.quickstart.renderText("Hello, Zit!", .{});
}
