const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const icons = @import("icons").tvg;
const dvui = @import("dvui");
const tailwind = @import("tailwind");
const util = @import("util.zig");

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

const Stat = struct {
    const n = 100;
    i: usize = 0,
    time: [n]u64 = undefined,
    current_max: u64 = 0,
    alltime_max: u64 = 0,
    fn update(self: *Stat, function: anytype) void {
        var t = std.time.Timer.start() catch unreachable;
        function();
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
    pub fn label() void {
        const txt = "Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor invidunt ut labore et dolore magna aliquyam erat, sed diam voluptua. At vero eos et accusam {} et justo duo dolores et ea rebum.  {} Stet clita kasd gubergren, no sea takimata sanctus est Lorem ipsum dolor sit amet. Lorem ipsum dolor sit amet, {} consetetur sadipscing elitr, sed diam nonumy eirmod tempor invidunt ut labore et dolore magna aliquyam erat, sed diam voluptua. At vero eos et accusam et justo duo dolores et ea rebum. {} Stet clita kasd gubergren, {} no sea takimata sanctus est Lorem ipsum dolor {any} sit amet.";
        dvui.label(@src(), txt, .{ 1, 2, 3, 4, 5, .{ 1, 2, 3 } }, .{});
    }
};

const Benchmark = benchmark_t();
var bench: Benchmark = Benchmark{};

fn ns_to_us(ns: u64) f64 {
    var k: f64 = @floatFromInt(ns);
    k /= 1_000.0;
    return k;
}
pub fn main() !void {
    var box = dvui.box(@src(), .vertical, .{
        .expand = .both,
        .color_fill = colors.bg_color,
        .background = true,
    });
    defer box.deinit();
    var sa = dvui.scrollArea(@src(), .{}, .{});
    sa.deinit();
    switch (mode) {
        .benchmarking => {
            const bfields = @typeInfo(Benchmark).@"struct".fields;
            inline for (bfields) |f| {
                const function = @field(benchmark, f.name);
                const stat: *Stat = &@field(bench, f.name);
                stat.update(function);
                dvui.label(@src(), "{s}: {d:.3} us current max", .{
                    f.name,
                    ns_to_us(stat.current_max),
                }, .{
                    .font_style = .heading,
                });
                dvui.label(@src(), "{s}: {d:.3} us peak", .{
                    f.name,
                    ns_to_us(stat.alltime_max),
                }, .{
                    .font_style = .heading,
                });
            }
            dvui.refresh(dvui.currentWindow(), @src(), null);
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
