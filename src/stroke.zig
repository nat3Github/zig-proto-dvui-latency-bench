/// Alternative Stroking implementation / Alternative to stroking with z2d
const std = @import("std");
const root = @import("root.zig");
const Pixel = z2d.pixel.RGBA;
const Image = root;
const math = std.math;
const z2d = root.z2d;
pub const Adapter = struct {
    sfc: *z2d.Surface,
    width: usize,
    height: usize,
    pub fn getPixel(self: *@This(), x: usize, y: usize) Pixel {
        const px = self.sfc.getPixel(@intCast(x), @intCast(y)).?.rgba;
        return px;
    }
    pub fn putPixel(self: *@This(), x: usize, y: usize, px: Pixel) void {
        self.sfc.putPixel(@intCast(x), @intCast(y), .{ .rgba = px });
    }
};

fn fpart(x: f32) f32 {
    return x - @floor(x);
}
fn rfpart(x: f32) f32 {
    return 1.0 - fpart(x);
}

fn pointToSegmentDistance(px: f32, py: f32, x0: f32, y0: f32, x1: f32, y1: f32) f32 {
    const dx = x1 - x0;
    const dy = y1 - y0;
    const len_sq = dx * dx + dy * dy;

    if (len_sq == 0.0) return @sqrt((px - x0) * (px - x0) + (py - y0) * (py - y0));

    const t = math.clamp(((px - x0) * dx + (py - y0) * dy) / len_sq, 0.0, 1.0);
    const proj_x = x0 + t * dx;
    const proj_y = y0 + t * dy;

    return @sqrt((proj_x - px) * (proj_x - px) + (proj_y - py) * (proj_y - py));
}
pub fn strokeLineSegmentAA(fb: anytype, p0: [2]f32, p1: [2]f32, width: f32, color: Pixel) void {
    const hw = (width / 2.0);
    const aa_blend_width = 1.0;
    const hwbbox = hw + aa_blend_width + 0.5;

    const min_x_float = @floor(@min(p0[0], p1[0]) - hwbbox);
    const max_x_float = @ceil(@max(p0[0], p1[0]) + hwbbox);
    const min_y_float = @floor(@min(p0[1], p1[1]) - hwbbox);
    const max_y_float = @ceil(@max(p0[1], p1[1]) + hwbbox);

    var y = min_y_float;
    while (y <= max_y_float) : (y += 1.0) {
        var x = min_x_float;
        while (x <= max_x_float) : (x += 1.0) {
            const dist = pointToSegmentDistance(x + 0.5, y + 0.5, p0[0], p0[1], p1[0], p1[1]);

            var base_alpha: f32 = 0.0;
            if (width < 1.0) {
                base_alpha = math.clamp(width * (1.0 - (dist - hw) / aa_blend_width), 0.0, width);
            } else {
                base_alpha = math.clamp(1.0 - (dist - hw) / aa_blend_width, 0.0, 1.0);
            }

            const color_alpha_norm = @as(f32, @floatFromInt(color.a)) / 255.0;
            const final_alpha = base_alpha * color_alpha_norm;

            if (final_alpha > 0.0001) {
                // --- FIX STARTS HERE ---
                // Clamp 'x' and 'y' to valid drawing coordinates BEFORE casting to u32
                const clamped_x = math.clamp(x, 0.0, @as(f32, @floatFromInt(fb.width)) - 1.0);
                const clamped_y = math.clamp(y, 0.0, @as(f32, @floatFromInt(fb.height)) - 1.0);

                const ix = @as(u32, @intFromFloat(clamped_x));
                const iy = @as(u32, @intFromFloat(clamped_y));

                // The inner check `if (ix < fb.width and iy < fb.height)`
                // is technically redundant if clamping is done correctly and the
                // original bounds were reasonable. But it's harmless.
                // We don't need `ix >= 0` since it's u32.
                if (ix < fb.width and iy < fb.height) {
                    var col_to_blend = color;
                    col_to_blend.a = @intFromFloat(255.0 * final_alpha);

                    blendPixel(
                        fb,
                        ix,
                        iy,
                        col_to_blend.multiply(),
                    );
                }
            }
        }
    }
}

pub fn strokeLineSegmentAA1(fb: anytype, p0: [2]f32, p1: [2]f32, width: f32, color: Pixel) void {
    const hw = (width / 2.0);
    // This is the effective anti-aliasing "radius" or spread.
    // A value of 0.5 to 1.0 is common. This determines how quickly alpha drops to 0.
    // If width is very small, we might want the AA zone to be wider relative to hw.
    const aa_feather_width = 2.0; // The distance over which alpha fades from 1 to 0
    const hwbbox = hw + aa_feather_width + 0.5; // Added 0.5 to ensure full coverage (pixel center to edge)

    const min_x = @floor(@min(p0[0], p1[0]) - hwbbox);
    const max_x = @ceil(@max(p0[0], p1[0]) + hwbbox);
    const min_y = @floor(@min(p0[1], p1[1]) - hwbbox);
    const max_y = @ceil(@max(p0[1], p1[1]) + hwbbox);

    var y = min_y;
    while (y <= max_y) : (y += 1.0) {
        var x = min_x;
        while (x <= max_x) : (x += 1.0) {
            const dist = pointToSegmentDistance(x + 0.5, y + 0.5, p0[0], p0[1], p1[0], p1[1]);
            const alpha_unclamped = (aa_feather_width - (dist - hw)) / aa_feather_width;
            const alpha = math.clamp(alpha_unclamped, 0.0, 1.0);

            if (alpha > 0.0) {
                const ix = @as(i32, @intFromFloat(x));
                const iy = @as(i32, @intFromFloat(y));
                if (ix >= 0 and iy >= 0 and
                    @as(u32, @intCast(ix)) < fb.width and
                    @as(u32, @intCast(iy)) < fb.height)
                {
                    var col = color;
                    col.a = @intFromFloat(255 * alpha);
                    blendPixel(
                        fb,
                        @as(u32, @intCast(ix)),
                        @as(u32, @intCast(iy)),
                        col.multiply(),
                    );
                }
            }
        }
    }
}

pub fn strokeLineSegmentAA2(fb: anytype, p0: [2]f32, p1: [2]f32, width: f32, color: Pixel) void {
    const hw = (width / 2.0);
    const hwbbox = hw + 1.5;

    const min_x = @floor(@min(p0[0], p1[0]) - hwbbox);
    const max_x = @ceil(@max(p0[0], p1[0]) + hwbbox);
    const min_y = @floor(@min(p0[1], p1[1]) - hwbbox);
    const max_y = @ceil(@max(p0[1], p1[1]) + hwbbox);

    var y = min_y;
    while (y <= max_y) : (y += 1.0) {
        var x = min_x;
        while (x <= max_x) : (x += 1.0) {
            const dist = pointToSegmentDistance(x + 0.5, y + 0.5, p0[0], p0[1], p1[0], p1[1]);
            const alpha = math.clamp(1.0 - (dist - hw), 0.0, 1.0);
            if (alpha > 0.0) {
                const ix = @as(i32, @intFromFloat(x));
                const iy = @as(i32, @intFromFloat(y));
                if (ix >= 0 and iy >= 0 and
                    @as(u32, @intCast(ix)) < fb.width and
                    @as(u32, @intCast(iy)) < fb.height)
                {
                    var col = color;
                    col.a = @intFromFloat(255 * alpha);
                    blendPixel(
                        fb,
                        @as(u32, @intCast(ix)),
                        @as(u32, @intCast(iy)),
                        col.multiply(),
                    );
                }
            }
        }
    }
}
pub fn strokeBezierAA(fb: anytype, p0: [2]f32, p1: [2]f32, p2: [2]f32, p3: [2]f32, width: f32, color: Pixel) void {
    var prev = p0;
    var t: f32 = 0.0;
    while (t <= 1.0) : (t += 0.02) {
        const x = bezierPoint(t, p0[0], p1[0], p2[0], p3[0]);
        const y = bezierPoint(t, p0[1], p1[1], p2[1], p3[1]);
        strokeLineSegmentAA(fb, prev, .{ x, y }, width, color);
        prev = .{ x, y };
    }
}

fn bezierPoint(t: f32, p0: f32, p1: f32, p2: f32, p3: f32) f32 {
    const u = 1.0 - t;
    return u * u * u * p0 + 3.0 * u * u * t * p1 + 3.0 * u * t * t * p2 + t * t * t * p3;
}

fn blendPixel(fb: anytype, x: u32, y: u32, color: Pixel) void {
    if (x >= fb.width or y >= fb.height) return;
    const dst = fb.getPixel(x, y);
    const out2 = z2d.compositor.runPixel(.float, .{ .rgba = dst }, .{ .rgba = color }, .dst_over).rgba;
    fb.putPixel(x, y, out2);
}
fn col_a(col: Pixel) u8 {
    return col[3];
}
fn col_b(col: Pixel) u8 {
    return col[2];
}
fn col_g(col: Pixel) u8 {
    return col[1];
}
fn col_r(col: Pixel) u8 {
    return col[0];
}
