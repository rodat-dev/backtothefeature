//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.
const std = @import("std");
const f = @import("flags.zig");

pub fn main() !void {
    const b2f = try f.BackToTheFeature.init("tmp/b2fdb");
    defer b2f.deinit();

    const isOn = try b2f.isFeatureFlagOn("feature_flag_one");
    std.debug.print("Is it on: {}\n", .{isOn});

    if (isOn) {
        try b2f.toggleFeatureFlag("feature_flag_one", false);
    }

    const isOff = try b2f.isFeatureFlagOn("feature_flag_one");
    std.debug.print("Is it off now: {}\n", .{isOff});
}
