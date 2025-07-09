const std = @import("std");
const assert = std.debug.assert;
const panic = std.debug.panic;
const Allocator = std.mem.Allocator;

const icons = @import("icons").tvg;
const dvui = @import("dvui");
const tailwind = @import("tailwind");
const util = @import("util.zig");

const Backend = dvui.backend;

pub const Sched = struct {
    pool: std.Thread.Pool = undefined,

    pub fn init(self: *@This(), alloc: Allocator) !void {
        const cpu_cores = std.Thread.getCpuCount() catch 4;
        try self.pool.init(.{ .allocator = alloc, .n_jobs = cpu_cores });
        errdefer self.pool.deinit();
    }
    pub fn deinit(self: *@This(), alloc: Allocator) void {
        _ = alloc;
        defer self.pool.deinit();
    }
};

pub const ColorSettings = struct {
    bg_color: dvui.Options.ColorOrName = .fromColor(.fromHex(tailwind.red500)),
};

pub const App = struct {
    alloc: Allocator = undefined,
    color_settings: ColorSettings = .{},

    sched: Sched = undefined,

    pub fn init(self: *App, alloc: Allocator) !void {
        self.alloc = alloc;
        try self.sched.init(alloc);
    }

    pub fn deinit(self: *App) void {
        const alloc = self.alloc;
        defer self.sched.deinit(alloc);
    }
};
