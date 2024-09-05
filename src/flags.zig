const std = @import("std");
const c = @import("leveldb/c.zig");

pub const DatabaseOptions = struct {
    base: ?*c.leveldb_options_t = null,
    cache: ?*c.leveldb_cache_t = null,
    env: ?*c.leveldb_env_t = null,
    woptions: ?*c.leveldb_writeoptions_t = null,
    roptions: ?*c.leveldb_readoptions_t = null,

    pub fn init() !@This() {
        var this = DatabaseOptions{};
        this.base = c.leveldb_options_create() orelse {
            return error.FailedToCreateDbOptions;
        };

        this.env = c.leveldb_create_default_env();
        this.cache = c.leveldb_cache_create_lru(100000);
        c.leveldb_options_set_create_if_missing(this.base, 1);
        c.leveldb_options_set_info_log(this.base, null);
        c.leveldb_options_set_write_buffer_size(this.base, 100000);
        c.leveldb_options_set_cache(this.base, this.cache);
        c.leveldb_options_set_env(this.base, this.env);

        this.woptions = c.leveldb_writeoptions_create();
        c.leveldb_writeoptions_set_sync(this.woptions, 1);

        this.roptions = c.leveldb_readoptions_create();
        c.leveldb_readoptions_set_verify_checksums(this.roptions, 1);
        c.leveldb_readoptions_set_fill_cache(this.roptions, 0);

        return this;
    }

    pub fn deinit(this: @This()) void {
        c.leveldb_env_destroy(this.env);
        c.leveldb_cache_destroy(this.cache);
        c.leveldb_options_destroy(this.base);
        c.leveldb_writeoptions_destroy(this.woptions);
        c.leveldb_readoptions_destroy(this.roptions);
    }
};

pub const LevelDbValue = struct {
    inner: [*c]u8,

    pub fn deinit(this: @This()) void {
        if (this.inner) |v| {
            c.leveldb_free(@ptrCast(v));
        }
    }
};

pub const LevelDb = struct {
    _opts: DatabaseOptions = DatabaseOptions{},
    _handle: ?*c.leveldb_t = null,
    _err_msg: ?[*c]u8 = null,

    pub fn init(dbname: [*c]const u8) !@This() {
        const opts = try DatabaseOptions.init();
        errdefer opts.deinit();

        var err_msg: [*c]u8 = null;
        const handle = c.leveldb_open(opts.base, dbname, @ptrCast(&err_msg));
        if (err_msg) |msg| {
            defer c.leveldb_free(@ptrCast(msg));
            std.debug.print("[INIT] error: {s}\n", .{msg});
            return error.FailedToInitializeLevelDb;
        }

        return .{ ._opts = opts, ._handle = handle };
    }

    pub fn deinit(this: @This()) void {
        this._opts.deinit();
        c.leveldb_close(this._handle);
    }

    pub fn put(this: @This(), key: [*c]const u8, value: [*c]const u8) !void {
        const wb: ?*c.leveldb_writebatch_t = c.leveldb_writebatch_create();
        c.leveldb_writebatch_put(wb, key, std.mem.span(key).len, value, std.mem.span(value).len);
        defer c.leveldb_writebatch_destroy(wb);

        c.leveldb_write(this._handle, this._opts.woptions, wb, @constCast(@ptrCast(&this._err_msg)));
        if (this._err_msg) |msg| {
            defer c.leveldb_free(@ptrCast(msg));
            std.debug.print("[PUT] error: {s}\n", .{msg});
            return error.FailedToPutValue;
        }

        std.debug.print("successful write to key {s}\n", .{key});
    }

    pub fn get(this: @This(), key: [*c]const u8) !LevelDbValue {
        var vallen: usize = 0;
        const value = c.leveldb_get(this._handle, this._opts.roptions, key, std.mem.span(key).len, &vallen, @constCast(@ptrCast(&this._err_msg)));
        if (this._err_msg) |msg| {
            defer c.leveldb_free(@ptrCast(msg));
            std.debug.print("[GET] error: {s}\n", .{msg});
            return error.FailedToGetValue;
        }

        std.debug.print("successful retrieval of value from key {s}\n", .{key});
        return LevelDbValue{ .inner = value };
    }
};

pub const BackToTheFeature = struct {
    _db: LevelDb,

    pub fn init(dbname: [*c]const u8) !@This() {
        const db_handle = try LevelDb.init(dbname);
        return .{ ._db = db_handle };
    }

    pub fn deinit(this: @This()) void {
        this._db.deinit();
    }

    pub fn toggleFeatureFlag(this: @This(), ff_name: []const u8, value: bool) !void {
        var buf: [512]u8 = undefined;
        const c_key = try std.fmt.bufPrintZ(&buf, "{s}", .{ff_name});
        try this._db.put(c_key, if (value) "true" else "false");
    }

    pub fn isFeatureFlagOn(this: @This(), ff_name: []const u8) !bool {
        var buf: [512]u8 = undefined;
        const c_key = std.fmt.bufPrintZ(&buf, "{s}", .{ff_name}) catch |err| {
            std.debug.print("failed to add sentinel {s}\n", .{@errorName(err)});
            @panic("failed to add sentinel value to key, reason to break and die!\n");
        };

        const ff_value = try this._db.get(c_key);
        defer ff_value.deinit();

        return std.mem.eql(u8, std.mem.span(ff_value.inner), "true");
    }
};
