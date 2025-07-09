const std = @import("std");
const assert = std.debug.assert;
const panic = std.debug.panic;
const Allocator = std.mem.Allocator;

const icons = @import("icons").tvg;
const dvui = @import("dvui");
const tailwind = @import("tailwind");
const z2d = @import("z2d");
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
    col_idx: usize = 0,
    alloc: Allocator = undefined,
    color_settings: ColorSettings = .{},
    img_1200x1200: z2d.Surface = undefined,
    img_600x600: z2d.Surface = undefined,

    sched: Sched = undefined,
    pub fn hueToRgb(hue: f32) dvui.Color {
        var h = @mod(hue, 360.0);
        if (h < 0.0) {
            h += 360.0;
        }
        const h_prime = h / 60.0;
        const x = 1.0 - @abs(@mod(h_prime, 2.0) - 1.0);
        var r: f32 = 0.0;
        var g: f32 = 0.0;
        var b: f32 = 0.0;
        if (h_prime >= 0.0 and h_prime < 1.0) {
            r = 1.0;
            g = x;
            b = 0.0;
        } else if (h_prime >= 1.0 and h_prime < 2.0) {
            r = x;
            g = 1.0;
            b = 0.0;
        } else if (h_prime >= 2.0 and h_prime < 3.0) {
            r = 0.0;
            g = 1.0;
            b = x;
        } else if (h_prime >= 3.0 and h_prime < 4.0) {
            r = 0.0;
            g = x;
            b = 1.0;
        } else if (h_prime >= 4.0 and h_prime < 5.0) {
            r = x;
            g = 0.0;
            b = 1.0;
        } else if (h_prime >= 5.0 and h_prime < 6.0) {
            r = 1.0;
            g = 0.0;
            b = x;
        } else {
            r = 0.0;
            g = 0.0;
            b = 0.0;
        }
        return .{
            .r = to_u8(r),
            .g = to_u8(g),
            .b = to_u8(b),
        };
    }
    fn to_u8(f: f32) u8 {
        return @as(u8, @intFromFloat(f * 255.0));
    }
    pub fn random_color(self: *App) void {
        const c = hueToRgb(@floatFromInt(self.col_idx));
        self.col_idx = (self.col_idx + 1) % 360;
        sfc_random_color(&self.img_1200x1200, c);
        sfc_random_color(&self.img_600x600, c);
    }
    pub fn sfc_random_color(sfc: *z2d.Surface, c: dvui.Color) void {
        const width: usize = @intCast(sfc.getWidth());
        const height: usize = @intCast(sfc.getHeight());
        const pix = z2d.pixel.RGBA{
            .r = c.r,
            .g = c.g,
            .b = c.b,
            .a = 255,
        };
        for (0..width) |w| {
            for (0..height) |h| {
                sfc.putPixel(@intCast(w), @intCast(h), .{ .rgba = pix });
            }
        }
    }

    pub fn init(self: *App, alloc: Allocator) !void {
        self.img_1200x1200 = try z2d.Surface.initPixel(.{ .rgba = .{ .r = 255, .g = 0, .b = 255, .a = 255 } }, alloc, 1200, 1200);
        self.img_600x600 = try z2d.Surface.initPixel(.{ .rgba = .{ .r = 255, .g = 0, .b = 255, .a = 255 } }, alloc, 600, 600);
        self.alloc = alloc;
        try self.sched.init(alloc);
    }

    pub fn deinit(self: *App) void {
        const alloc = self.alloc;
        defer self.sched.deinit(alloc);
        self.img_1200x1200.deinit(alloc);
        self.img_600x600.deinit(alloc);
    }
};
