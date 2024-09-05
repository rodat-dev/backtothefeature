const std = @import("std");
const f = @import("flags.zig");

const FeatureToggleRequest = struct {
    featureFlag: []u8,
    toggle: bool,
};

fn handleFeatureToggle(request: *std.http.Server.Request, feature_flag_name: []const u8, toggle: bool, db: *f.BackToTheFeature) void {
    db.toggleFeatureFlag(feature_flag_name, toggle) catch |err| {
        std.debug.print("failed to toggle feature flag: {s}", .{@errorName(err)});
        return request.respond(@errorName(err), .{ .keep_alive = false, .status = .internal_server_error }) catch return;
    };

    std.debug.print("successfully handled request...", .{});
    return request.respond("", .{ .status = .ok, .keep_alive = false }) catch return;
}

fn handleClientConnection(allocator: std.mem.Allocator, listener: *std.net.Server, db: *f.BackToTheFeature) void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const connection = listener.accept() catch |err| {
        std.debug.print("error accepting client connection: {s}", .{@errorName(err)});
        return;
    };

    var rbuf: [512]u8 = undefined;
    var client_handle = std.http.Server.init(connection, rbuf[0..]);

    var request = client_handle.receiveHead() catch |err| {
        std.debug.print("failed to receive client's connection headers: {s}", .{@errorName(err)});
        return;
    };

    if (std.ascii.startsWithIgnoreCase(request.head.target, "/switch")) {
        var path = std.mem.splitScalar(u8, request.head.target, '/');
        _ = path.first();
        const feature_flag = path.next() orelse {
            std.debug.print("invalid path, missing feature flag name in path", .{});
            return request.respond("missing feature flag name in path", .{ .status = .bad_request, .keep_alive = false }) catch return;
        };

        switch (request.head.method) {
            .POST => {
                _ = path.next() orelse {
                    std.debug.print("invalid path, missing toggle value in path", .{});
                    return request.respond("missing toggle value in path", .{ .status = .bad_request, .keep_alive = false }) catch return;
                };
                handleFeatureToggle(&request, feature_flag, std.mem.eql(u8, "true", path.next() orelse ""), db);
            },
            .GET => {
                const is_on = db.isFeatureFlagOn(feature_flag) catch |err| {
                    std.debug.print("failed to read feature flag - {s}: {s}", .{ feature_flag, @errorName(err) });
                    return request.respond("", .{ .status = .internal_server_error }) catch return;
                };
                return request.respond(std.json.stringifyAlloc(arena.allocator(), .{ .isOn = is_on }, .{}) catch "", .{ .status = .ok, .keep_alive = false }) catch return;
            },
            else => return request.respond("", .{ .status = .not_found, .keep_alive = false }) catch return,
        }
    } else {
        return request.respond("", .{ .status = .not_found, .keep_alive = false }) catch return;
    }
}

pub const Api = struct {
    listener: std.net.Server,
    pool: *std.Thread.Pool,
    db: *f.BackToTheFeature,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: u16, db: *f.BackToTheFeature) !@This() {
        var pool = try allocator.create(std.Thread.Pool);
        errdefer allocator.destroy(pool);
        try pool.init(.{ .allocator = allocator });
        errdefer pool.deinit();

        const server = try std.net.Address.resolveIp(host, port);
        const listener = try server.listen(.{ .reuse_port = true });
        std.debug.print("started listening on port {d}\n", .{server.getPort()});
        return .{ .listener = listener, .pool = pool, .allocator = allocator, .db = db };
    }

    pub fn deinit(this: *@This()) void {
        this.listener.deinit();
        this.pool.deinit();
        this.allocator.destroy(this.pool);

        std.debug.print("cleaned up the server's resources\n", .{});
    }

    pub fn startServer(this: *@This()) !void {
        while (true) {
            try this.pool.spawn(handleClientConnection, .{ this.allocator, &this.listener, this.db });
        }
    }
};
