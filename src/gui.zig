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
    const n = 100;
    const internal_width = 600;
    const internal_height = 80;
    i: usize = 0,
    is_init: bool = false,
    time: [n]u64 = blk: {
        var arr: [n]u64 = undefined;
        for (0..n) |i| arr[i] = 0;
        break :blk arr;
    },
    current_max: u64 = 0,
    alltime_max: u64 = 0,
    static_buff: [400 * 80 * 4 + 1024]u8 = undefined,
    ximg: z2d.Surface = undefined,
    fn no_inline(function: *const fn () void) void {
        function();
    }
    pub fn init(self: *Stat) void {
        var sal = std.heap.FixedBufferAllocator.init(&self.static_buff);
        const alloc = sal.allocator();
        // const alloc = gState.alloc;
        self.ximg = z2d.Surface.init(.image_surface_rgba, alloc, 400, 80) catch unreachable;
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

        const Static = struct {
            var yaxis: dvui.PlotWidget.Axis = .{
                .name = "Y Axis",
                // let plot figure out min
                .min = 0,
                .max = 5000,
            };
        };

        var plot = dvui.plot(@src(), .{
            .title = "perf",
            .x_axis = null,
            .y_axis = &Static.yaxis,
            .border_thick = 1.0,
            .mouse_hover = true,
        }, .{ .min_size_content = .{ .h = 120, .w = 100 }, .expand = .horizontal, .id_extra = 100000000 + opts.id_extra.? });
        var s1 = plot.line();

        const points: usize = self.time.len;
        for (0..points + 1) |i| {
            const idx = (self.i + i) % n;
            const us_norm = ns_to_us(self.time[idx]);
            s1.point(@as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(points)), us_norm);
        }
        s1.stroke(3, dvui.themeGet().color_accent);
        s1.deinit();
        plot.deinit();
    }
    pub fn drawx(self: *Stat, src: std.builtin.SourceLocation, name: []const u8, opts: dvui.Options) void {
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

        const img = &self.ximg;

        const alloc = dvui.currentWindow()._arena.allocator();
        // const alloc = dvui.currentWindow()._arena.allocator();
        var ctx = z2d.Context.init(alloc, img);
        defer ctx.deinit();
        ctx.setLineWidth(3.0);
        ctx.setSourceToPixel(.{ .rgba = State.z2d_pixel_from(.fromHex(tailwind.red500)) });
        State.sfc_set_bg_color(img, .transparent);

        const window_max_us = 5000.0;
        const width: usize = @intCast(img.getWidth());
        const heightf: f64 = @floatFromInt(img.getHeight());
        const w4 = width / 4;
        const k_points = n / w4;
        assert(k_points > 0); // to little points for this image width
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
            .expand = .horizontal,
            .id_extra = opts.id_extra orelse 0 + 1000000,
        };
        var imgb = img_bytes(img);
        imgb.pixelsPMA.invalidate = .always;
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
        .pixelsPMA = .{
            .rgba = std.mem.bytesAsSlice(dvui.Color.PMA, pix),
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
    pub fn image_1200x1200_always() void {
        var b = img_bytes(&gState.img_1200x1200);
        b.pixelsPMA.invalidate = .always;
        _ = dvui.image(@src(), .{ .source = b }, .{});
    }
    pub fn image_600x600_always() void {
        var b = img_bytes(&gState.img_600x600);
        b.pixelsPMA.invalidate = .always;
        _ = dvui.image(@src(), .{ .source = b }, .{});
    }
    pub fn text_layout() void {
        text_layout_example();
    }
    pub fn plot() void {
        plots_example();
    }
};

const Benchmark = benchmark_t();
var bench: Benchmark = Benchmark{};
var frame: u64 = 0;
var line_height_factor: f32 = 3;

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
    defer dvui.refresh(dvui.currentWindow(), @src(), null);
    switch (mode) {
        .benchmarking => {
            // MAIN
            const bfields = @typeInfo(Benchmark).@"struct".fields;
            @import("main.zig").window_begin_time.draw(@src(), "begin call", .{ .id_extra = 90899 });
            @import("main.zig").backend_frame_render_time.draw(@src(), "frame backend", .{ .id_extra = 90900 });
            @import("main.zig").backend_cursor_management_time.draw(@src(), "cursor management", .{ .id_extra = 90901 });
            @import("main.zig").dvui_window_end_time_1.draw(@src(), "the backend.textureDestroy() call inside window.end", .{ .id_extra = 90902 });
            @import("main.zig").dvui_window_end_time_2.draw(@src(), "window.end() 2", .{ .id_extra = 90903 });
            if (true) {
                inline for (bfields, 0..) |f, i| {
                    const function = @field(benchmark, f.name);
                    const stat: *Stat = &@field(bench, f.name);
                    stat.update(function);
                    stat.draw(@src(), f.name, .{ .id_extra = 1000000 + i });
                }
            }
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

fn text_layout_example() void {
    _ = dvui.sliderEntry(@src(), "line height: {d:0.2}", .{ .value = &line_height_factor, .min = 0.1, .max = 2, .interval = 0.1 }, .{});

    {
        var tl = dvui.TextLayoutWidget.init(@src(), .{}, .{ .expand = .horizontal });
        tl.install(.{});
        defer tl.deinit();

        var cbox = dvui.box(@src(), .vertical, .{ .margin = dvui.Rect.all(6), .min_size_content = .{ .w = 40 } });
        if (dvui.buttonIcon(
            @src(),
            "play",
            dvui.entypo.controller_play,
            .{},
            .{},
            .{ .expand = .ratio },
        )) {
            dvui.dialog(@src(), .{}, .{ .modal = false, .title = "Play", .message = "You clicked play" });
        }
        if (dvui.buttonIcon(
            @src(),
            "more",
            dvui.entypo.dots_three_vertical,
            .{},
            .{},
            .{ .expand = .ratio },
        )) {
            dvui.dialog(@src(), .{}, .{ .modal = false, .title = "More", .message = "You clicked more" });
        }
        cbox.deinit();

        cbox = dvui.box(@src(), .vertical, .{ .margin = dvui.Rect.all(4), .padding = dvui.Rect.all(4), .gravity_x = 1.0, .background = true, .color_fill = .fill_window, .min_size_content = .{ .w = 160 }, .max_size_content = .width(160) });
        dvui.icon(@src(), "aircraft", dvui.entypo.aircraft, .{}, .{ .min_size_content = .{ .h = 30 }, .gravity_x = 0.5 });
        dvui.label(@src(), "Caption Heading", .{}, .{ .font_style = .caption_heading, .gravity_x = 0.5 });
        var tl_caption = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = false });
        tl_caption.addText("Here is some caption text that is in it's own text layout.", .{ .font_style = .caption });
        tl_caption.deinit();
        cbox.deinit();

        if (tl.touchEditing()) |floating_widget| {
            defer floating_widget.deinit();
            tl.touchEditingMenu();
        }

        tl.processEvents();

        const lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. ";
        const lorem2 = " Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.\n";
        tl.addText(lorem, .{ .font = dvui.themeGet().font_body.lineHeightFactor(line_height_factor) });

        if (tl.addTextClick("This text is a link that is part of the text layout and goes to the dvui home page.", .{ .color_text = .{ .color = .{ .r = 0x35, .g = 0x84, .b = 0xe4 } }, .font = dvui.themeGet().font_body.lineHeightFactor(line_height_factor) })) {
            _ = dvui.openURL("https://david-vanderson.github.io/");
        }

        tl.addText(lorem2, .{ .font = dvui.themeGet().font_body.lineHeightFactor(line_height_factor) });

        const start = "\nNotice that the text in this box is wrapping around the stuff in the corners.\n\n";
        tl.addText(start, .{ .font_style = .title_4 });

        const col = dvui.Color.average(dvui.themeGet().color_text, dvui.themeGet().color_fill);
        tl.addTextTooltip(@src(), "Hover this for a tooltip.\n\n", "This is some tooltip", .{ .color_text = .{ .color = col }, .font = dvui.themeGet().font_body.lineHeightFactor(line_height_factor) });

        tl.format("This line uses zig format strings: {d}\n\n", .{12345}, .{});

        tl.addText("Title ", .{ .font_style = .title });
        tl.addText("Title-1 ", .{ .font_style = .title_1 });
        tl.addText("Title-2 ", .{ .font_style = .title_2 });
        tl.addText("Title-3 ", .{ .font_style = .title_3 });
        tl.addText("Title-4 ", .{ .font_style = .title_4 });
        tl.addText("Heading\n", .{ .font_style = .heading });

        tl.addText("Here ", .{ .font_style = .title, .color_text = .{ .color = .{ .r = 100, .b = 100 } } });
        tl.addText("is some ", .{ .font_style = .title_2, .color_text = .{ .color = .{ .b = 100, .g = 100 } } });
        tl.addText("ugly text ", .{ .font_style = .title_1, .color_text = .{ .color = .{ .r = 100, .g = 100 } } });
        tl.addText("that shows styling.", .{ .font_style = .caption, .color_text = .{ .color = .{ .r = 100, .g = 50, .b = 50 } } });
    }
}

pub fn plots_example() void {
    var vbox = dvui.box(@src(), .vertical, .{ .min_size_content = .{ .w = 300, .h = 100 }, .expand = .ratio });
    defer vbox.deinit();

    const Static = struct {
        var xaxis: dvui.PlotWidget.Axis = .{
            .name = "X Axis",
            .min = 0.05,
            .max = 0.95,
        };

        var yaxis: dvui.PlotWidget.Axis = .{
            .name = "Y Axis",
            // let plot figure out min
            .max = 0.8,
        };
    };

    var plot = dvui.plot(@src(), .{
        .title = "Plot Title",
        .x_axis = &Static.xaxis,
        .y_axis = &Static.yaxis,
        .border_thick = 1.0,
        .mouse_hover = true,
    }, .{ .expand = .both });
    var s1 = plot.line();

    const points: usize = 1000;
    const freq: f32 = 5;
    plot_dx += 1;
    for (0..points + 1) |i| {
        const fval: f64 = @sin(1.8 * std.math.pi * @as(f64, @floatFromInt(i + plot_dx)) / @as(f64, @floatFromInt(points)) * freq);
        s1.point(@as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(points)), fval);
    }
    s1.stroke(3, dvui.themeGet().color_accent);
    s1.deinit();
    plot.deinit();
}
var plot_dx: usize = 0;
