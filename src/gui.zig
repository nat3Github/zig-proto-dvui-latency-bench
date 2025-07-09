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
    time: [n]u64 = undefined,
    current_max: u64 = 0,
    alltime_max: u64 = 0,
    fn no_inline(function: *const fn () void) void {
        function();
    }
    pub fn update(self: *Stat, function: *const fn () void) void {
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
    pub fn print(stat: *Stat, src: std.builtin.SourceLocation, name: []const u8, opts: dvui.Options) void {
        const opt = dvui.Options{
            .font_style = .heading,
        };
        dvui.label(
            src,
            \\{s}: 
            \\{d:.0} us (max from {})
            \\{d:.0} us peak
        ,
            .{
                name,
                ns_to_us(stat.current_max),
                Stat.n,
                ns_to_us(stat.alltime_max),
            },
            opt.override(opts),
        );
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
            @import("main.zig").backend_frame_render_time.print(@src(), "frame backend", .{});
            @import("main.zig").backend_cursor_management_time.print(@src(), "cursor management", .{});
            @import("main.zig").dvui_window_end_time.print(@src(), "window.end() call", .{});
            inline for (bfields, 0..) |f, i| {
                const function = @field(benchmark, f.name);
                const stat: *Stat = &@field(bench, f.name);
                stat.update(function);
                stat.print(@src(), f.name, .{ .id_extra = i });
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
