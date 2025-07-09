const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const icons = @import("icons").tvg;
const audioutil = @import("audioutil");
const dvui = @import("dvui");
const tailwind = @import("tailwind");
const util = @import("util.zig");

const Backend = dvui.backend;
const state = @import("state.zig");
const gui = @import("gui.zig");

pub var backend_frame_render_time: gui.Stat = .{};
pub var backend_cursor_management_time: gui.Stat = .{};
const backend_fn_type = @TypeOf(Backend.initWindow);
const backend_fn_err_t = @typeInfo(@typeInfo(backend_fn_type).@"fn".return_type.?).error_union.payload;
pub var backend_ref: *backend_fn_err_t = undefined;
pub var win_ref: *dvui.Window = undefined;
test "all" {
    std.testing.refAllDecls(@This());
}
const winapi = if (builtin.os.tag == .windows) struct {
    extern "kernel32" fn AttachConsole(dwProcessId: std.os.windows.DWORD) std.os.windows.BOOL;
} else struct {};
pub fn main() !void {
    comptime std.debug.assert(@hasDecl(Backend, "SDLBackend"));
    if (@import("builtin").os.tag == .windows) _ = winapi.AttachConsole(0xFFFFFFFF);

    std.log.info("SDL version: {}", .{Backend.getSDLVersion()});
    var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa_instance.deinit() != .ok) @panic("Memory leak on exit!");
    const alloc = gpa_instance.allocator();

    var backend = try Backend.initWindow(.{
        .allocator = alloc,
        .size = .{ .w = 800.0, .h = 600.0 },
        .min_size = .{ .w = 250.0, .h = 350.0 },
        .vsync = false,
        .title = "dvui perf",
    });
    defer backend.deinit();

    try gui.init(alloc);
    defer gui.deinit();

    var win = try dvui.Window.init(@src(), alloc, backend.backend(), .{});
    defer win.deinit();

    var interrupted = false;

    main_loop: while (true) {
        const nstime = win.beginWait(interrupted);

        // marks the beginning of a frame for dvui, can call dvui functions after this
        try win.begin(nstime);

        // send all SDL events to dvui for processing
        const quit = try backend.addAllEvents(&win);
        if (quit) break :main_loop;

        // if dvui widgets might not cover the whole window, then need to clear
        // the previous frame's render
        _ = Backend.c.SDL_SetRenderDrawColor(backend.renderer, 0, 0, 0, 255);
        _ = Backend.c.SDL_RenderClear(backend.renderer);

        // The demos we pass in here show up under "Platform-specific demos"
        const sf_pro_ttf = @embedFile("assets/SF-Pro.ttf");
        try dvui.addFont("base", sf_pro_ttf, null);

        gui.main() catch |e| {
            std.log.err("{}", .{e});
        };

        // marks end of dvui frame, don't call dvui functions after this
        // - sends all dvui stuff to backend for rendering, must be called before renderPresent()
        const end_micros = try win.end(.{});

        // cursor management
        backend_ref = &backend;
        win_ref = &win;

        backend_cursor_management_time.update(backend_cursor_management);
        backend_frame_render_time.update(backend_render_frame);

        // waitTime and beginWait combine to achieve variable framerates
        const wait_event_micros = win.waitTime(end_micros, null);
        interrupted = try backend.waitEventTimeout(wait_event_micros);

        // -----------------------------------------------------------------------------------------
    }
}

fn backend_cursor_management() void {
    const backend = backend_ref;
    const win = win_ref;
    // cursor management
    backend.setCursor(win.cursorRequested()) catch return;
    backend.textInputRect(win.textInputRequested()) catch return;
}
fn backend_render_frame() void {
    const backend = backend_ref;
    // render frame to OS
    backend.renderPresent() catch return;
}
// const win = dvui.currentWindow();
// const frame_alloc = win.arena();
// const gpa = gState.alloc;
// const pool = &gState.pool;
// const wavform_widget = &gState.wavform_widget;
// fn gui_main_frame() !void {
//     const win = dvui.currentWindow();
//     const frame_alloc = win.arena();

//     var fpstext = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font_style = .title_4 });
//     fpstext.addText(try std.fmt.allocPrint(frame_alloc, "fps: {d:.3}", .{dvui.FPS()}), .{});
//     fpstext.deinit();
//     {
//         const gpa = gState.alloc;
//         const pool = &gState.pool;
//         const wavform_widget = &gState.wavform_widget;
//         const wavform_offset = &gState.wavform_widget_offset;

//         if (dvui.button(@src(), "load", .{}, .{})) {
//             try wavform_widget.load(
//                 gpa,
//                 pool,
//                 try std.fs.cwd().realpathAlloc(frame_alloc, "audioutil/testfiles/joyryde.wav"),
//             );
//         }
//         if (dvui.button(@src(), "forwards", .{}, .{})) {
//             wavform_offset.* = wavform_offset.* + 2 * 2048;
//         }
//         if (dvui.button(@src(), "backwards", .{}, .{})) {
//             wavform_offset.* = std.math.sub(u64, wavform_offset.*, 2 * 2048) catch 0;
//         }
//         var ww_rect = mainbox.child_rect;
//         ww_rect.h = 100;
//         ww_rect.y = 100;
//         ww_rect.x = 0;

//         try wavform_widget.draw_wavform_container(gpa, pool, wavform_offset.*, 44100 * 2, ww_rect, bg_color);
//     }
// }
