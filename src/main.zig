const std = @import("std");
const f = @import("flags.zig");
const a = @import("api.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var b2f = try f.BackToTheFeature.init("tmp/b2fdb");
    defer b2f.deinit();

    var api = try a.Api.init(allocator, "127.0.0.1", 8080, &b2f);
    defer api.deinit();

    try api.startServer();
}
