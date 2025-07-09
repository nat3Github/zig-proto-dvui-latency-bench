const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const icons = @import("icons").tvg;
const dvui = @import("dvui");
const tailwind = @import("tailwind");
const util = @import("util.zig");
const z2d = @import("z2d");

const State = @import("state.zig").App;

pub var gState: State = .{};
const pad_layout = &gState.pad_layout;
const colors = &gState.color_settings;
const Mode = enum {
    benchmarking,
};
var mode: Mode = .benchmarking;

pub fn init(alloc: Allocator) !void {
    try gState.init(alloc);
}
pub fn deinit() void {
    gState.deinit();
}

pub const Stat = struct {
    const n = if (@import("builtin").mode == .Debug) 100 else 1000;
    i: usize = 0,
    is_init: bool = false,
    time: [n]u64 = blk: {
        var arr: [n]u64 = undefined;
        for (0..n) |i| arr[i] = 0;
        break :blk arr;
    },
    current_max: u64 = 0,
    alltime_max: u64 = 0,
    fn no_inline(function: *const fn () void) void {
        function();
    }
    pub fn init(self: *Stat) void {
        // const alloc = gState.alloc;
        // self.img = z2d.Surface.init(.image_surface_rgba, alloc, 300, 30) catch return;
        self.is_init = true;
    }
    pub fn update(self: *Stat, function: *const fn () void) void {
        if (!self.is_init) self.init();
        var t = std.time.Timer.start() catch unreachable;
        t.reset();
        @call(.never_inline, no_inline, .{function});
        const tval = t.read();
        self.time[self.i] = tval;
        if (self.i + 1 == n) {
            self.i = 0;
            self.current_max = std.mem.max(u64, &self.time);
            self.alltime_max = @max(self.alltime_max, self.current_max);
        } else {
            self.i += 1;
        }
    }
    pub fn print_text(self: *Stat, src: std.builtin.SourceLocation, name: []const u8, opts: dvui.Options) void {
        if (!self.is_init) return;
        const opt = dvui.Options{
            .font_style = .heading,
        };
        dvui.label(src,
            \\{s}: 
            \\{d:.0} us (max from {})
            \\{d:.0} us peak
        , .{ name, ns_to_us(self.current_max), Stat.n, ns_to_us(self.alltime_max) }, opt.override(opts));
    }
    pub fn draw(self: *Stat, src: std.builtin.SourceLocation, name: []const u8, opts: dvui.Options) void {
        if (!self.is_init) return;

        var opt = dvui.Options{
            .font_style = .heading,
            .id_extra = 0,
        };
        dvui.label(src,
            \\{s}:
            \\{d:.0} us (max from {})
            \\{d:.0} us peak
        , .{ name, ns_to_us(self.current_max), Stat.n, ns_to_us(self.alltime_max) }, opt.override(opts));

        const alloc = dvui.currentWindow()._arena.allocator();
        var img = z2d.Surface.init(.image_surface_rgba, alloc, 400, 60) catch return;
        defer img.deinit(alloc);
        var ctx = z2d.Context.init(alloc, &img);
        defer ctx.deinit();
        ctx.setLineWidth(3.0);
        ctx.setSourceToPixel(.{ .rgba = State.z2d_pixel_from(.fromHex(tailwind.red400)) });
        State.sfc_set_bg_color(&img, .transparent);

        const window_max_us = 5000.0;
        const width: usize = @intCast(img.getWidth());
        const heightf: f64 = @floatFromInt(img.getHeight());
        const w4 = width / 4;
        const k_points = n / w4;
        const dx = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(w4));
        var dxj: f64 = 0.0;
        var last_y: f64 = heightf;
        for (0..w4) |jw| {
            const sj = jw * k_points;
            var max: u64 = 0;
            for (sj..sj + k_points) |j| {
                const idx = (self.i + j) % n;
                max = @max(self.time[idx], max);
            }
            const us_norm = @min(ns_to_us(max), window_max_us) / window_max_us;
            const us_inv = 1.0 - us_norm;
            ctx.moveTo(dxj, last_y) catch return;
            last_y = us_inv * heightf;
            ctx.lineTo(dxj + dx, last_y) catch return;
            ctx.stroke() catch return;
            ctx.resetPath();
            dxj += dx;
        }
        const opt2 = dvui.Options{
            .font_style = .heading,
            .min_size_content = .{ .w = 400, .h = 80 },
            .expand = .horizontal,
            .id_extra = opts.id_extra orelse 0 + 1000000,
        };
        var imgb = img_bytes(&img);
        imgb.pixels.invalidation_strategy = .always;
        _ = dvui.image(@src(), .{
            .source = imgb,
        }, opt2);
    }
};
fn benchmark_t() type {
    comptime {
        const decls = @typeInfo(benchmark).@"struct".decls;
        var f: [decls.len]std.builtin.Type.StructField = undefined;
        for (&f, decls) |*ff, d| {
            ff.* = .{
                .alignment = @alignOf(Stat),
                .default_value_ptr = &Stat{},
                .is_comptime = false,
                .name = d.name,
                .type = Stat,
            };
        }
        const t: std.builtin.Type = .{ .@"struct" = std.builtin.Type.Struct{
            .decls = &.{},
            .fields = &f,
            .is_tuple = false,
            .layout = .auto,
        } };
        return @Type(t);
    }
}
fn img_bytes(sfc: *z2d.Surface) dvui.ImageSource {
    const pix = std.mem.sliceAsBytes(sfc.image_surface_rgba.buf);
    return dvui.ImageSource{
        .pixels = .{
            .rgba = pix,
            .width = @intCast(sfc.getWidth()),
            .height = @intCast(sfc.getHeight()),
        },
    };
}
const benchmark = struct {
    pub fn big_label() void {
        const txt = "Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor invidunt ut labore et dolore magna aliquyam erat, sed diam voluptua. At vero eos et accusam {} et justo duo dolores et ea rebum.  {} Stet clita kasd gubergren, no sea takimata sanctus est Lorem ipsum dolor sit amet. Lorem ipsum dolor sit amet, {} consetetur sadipscing elitr, sed diam nonumy eirmod tempor invidunt ut labore et dolore magna aliquyam erat, sed diam voluptua. At vero eos et accusam et justo duo dolores et ea rebum. {} Stet clita kasd gubergren, {} no sea takimata sanctus est Lorem ipsum dolor {any} sit amet.";
        dvui.label(@src(), txt, .{ 1, 2, 3, 4, 5, .{ 1, 2, 3 } }, .{});
    }
    pub fn small_label() void {
        dvui.label(@src(), "constant string label", .{}, .{});
    }
    pub fn button() void {
        if (dvui.button(@src(), "click me", .{}, .{ .corner_radius = .all(5) })) {
            std.log.warn("button cliced", .{});
        }
    }
    pub fn buttonIcon() void {
        if (dvui.buttonIcon(@src(), "click me", icons.lucide.plane, .{}, .{}, .{
            .corner_radius = .all(5),
        })) {
            std.log.warn("button cliced", .{});
        }
    }
    pub fn image_1200x1200() void {
        const b = img_bytes(&gState.img_1200x1200);
        _ = dvui.image(@src(), .{ .source = b }, .{});
    }
    pub fn image_600x600() void {
        const b = img_bytes(&gState.img_600x600);
        _ = dvui.image(@src(), .{ .source = b }, .{});
    }
    pub fn invalidate_all_images() void {
        dvui.textureInvalidateCache(dvui.ImageSource.hash(img_bytes(&gState.img_1200x1200)));
        dvui.textureInvalidateCache(dvui.ImageSource.hash(img_bytes(&gState.img_600x600)));
    }
};

const Benchmark = benchmark_t();
var bench: Benchmark = Benchmark{};
var frame: u64 = 0;

fn ns_to_us(ns: u64) f64 {
    var k: f64 = @floatFromInt(ns);
    k /= 1_000.0;
    return k;
}
pub fn main() !void {
    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .background = false });
    defer scroll.deinit();
    var hbox = dvui.box(@src(), .vertical, .{ .background = true, .color_fill = colors.bg_color });
    defer hbox.deinit();
    dvui.label(@src(), "frame: {}", .{frame}, .{});
    frame += 1;
    switch (mode) {
        .benchmarking => {
            const bfields = @typeInfo(Benchmark).@"struct".fields;
            @import("main.zig").backend_frame_render_time.draw(@src(), "frame backend", .{ .id_extra = 90900 });
            @import("main.zig").backend_cursor_management_time.draw(@src(), "cursor management", .{ .id_extra = 90901 });
            @import("main.zig").dvui_window_end_time.draw(@src(), "window.end() call", .{ .id_extra = 90902 });
            inline for (bfields, 0..) |f, i| {
                const function = @field(benchmark, f.name);
                const stat: *Stat = &@field(bench, f.name);
                stat.update(function);
                stat.draw(@src(), f.name, .{ .id_extra = 1000000 + i });
            }
            dvui.refresh(dvui.currentWindow(), @src(), null);
            gState.random_color();
        },
    }
}

pub const layout = struct {
    pub fn center_split(
        main_content: ?*const fn () anyerror!void,
        left_sidebar: ?*const fn () anyerror!void,
        right_sidebar: ?*const fn () anyerror!void,
        topbar: ?*const fn () anyerror!void,
    ) !void {
        {
            var mainbox = dvui.box(@src(), .vertical, .{
                .background = true,
                .expand = .both,
                .color_fill = colors.bg_color,
                .padding = .all(5),
            });
            defer mainbox.deinit();
            if (topbar) |f| try f();
            {
                var botbox = dvui.box(@src(), .horizontal, .{
                    .background = false,
                    .color_fill = .blue,
                    .expand = .both,
                });
                defer botbox.deinit();
                if (left_sidebar) |f| {
                    try f();
                }
                if (main_content) |f| try f();
                if (right_sidebar) |f| {
                    try f();
                }
            }
        }
    }
};
