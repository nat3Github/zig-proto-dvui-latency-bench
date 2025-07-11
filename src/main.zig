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

const fifoasync = @import("fifoasync");
pub var backend_frame_render_time: gui.Stat = .{};
pub var backend_cursor_management_time: gui.Stat = .{};
pub var dvui_window_end_time_1: gui.Stat = .{};
pub var dvui_window_end_time_2: gui.Stat = .{};
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
    try fifoasync.thread.prio.set_realtime_critical_highest();
    comptime std.debug.assert(@hasDecl(Backend, "SDLBackend"));
    if (@import("builtin").os.tag == .windows) _ = winapi.AttachConsole(0xFFFFFFFF);

    std.log.info("SDL version: {}", .{Backend.getSDLVersion()});
    var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa_instance.deinit() != .ok) @panic("Memory leak on exit!");
    var log_alloc = @import("alloc.zig").LogAllocator{
        .child_allocator = gpa_instance.allocator(),
        .log_enabled = false,
        .name = "main allocator",
    };
    const alloc = log_alloc.allocator();
    // const alloc = gpa_instance.allocator();

    var backend = try Backend.initWindow(.{
        .allocator = alloc,
        .size = .{ .w = 800.0, .h = 600.0 },
        .min_size = .{ .w = 250.0, .h = 350.0 },
        .vsync = true,
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

        backend_ref = &backend;
        win_ref = &win;

        const end_micros = end_whole() catch @panic("");

        // sdl stuff
        backend_cursor_management_time.update(backend_cursor_management);
        backend_frame_render_time.update(backend_render_frame);

        // waitTime and beginWait combine to achieve variable framerates
        const wait_event_micros = win.waitTime(end_micros, null);
        interrupted = try backend.waitEventTimeout(wait_event_micros);

        // -----------------------------------------------------------------------------------------
        if (@import("builtin").mode == .Debug) {
            std.Thread.sleep(5_000_000);
        } else {
            std.Thread.sleep(15_000_000);
        }
    }
}
// var end_micros: ?u32 = null;
// marks end of dvui frame, don't call dvui functions after this
// - sends all dvui stuff to backend for rendering, must be called before renderPresent()
pub fn end1() void {
    const self = win_ref;
    for (self.texture_trash.items) |tex| {
        self.backend.textureDestroy(tex);
    }
    self.texture_trash = .empty;
}
pub fn end2() void {
    const self = win_ref;
    if (self.events.pop()) |e| {
        if (e.evt != .mouse or e.evt.mouse.action != .position) {
            std.log.err("positionMouseEventRemove removed a non-mouse or non-position event\n", .{});
        }
    }
    _ = self._arena.reset(.shrink_to_peak_usage);
    if (self._lifo_arena.current_usage != 0 and !self._lifo_arena.has_expanded()) {
        std.log.warn("Arena was not empty at the end of the frame, {d} bytes left. Did you forget to free memory somewhere?", .{self._lifo_arena.current_usage});
    }
    _ = self._lifo_arena.reset(.shrink_to_peak_usage);

    if (self._widget_stack.current_usage != 0 and !self._widget_stack.has_expanded()) {
        std.log.warn("Widget stack was not empty at the end of the frame, {d} bytes left. Did you forget to call deinit?", .{self._widget_stack.current_usage});
    }
    _ = self._widget_stack.reset(.shrink_to_peak_usage);

    self.events = .{};
    self.event_num = 0;
    const widget_id = if (self.capture) |cap| cap.id else null;
    self.events.append(self.arena(), .{
        .num = self.event_num + 1,
        .target_widgetId = widget_id,
        .evt = .{ .mouse = .{
            .action = .position,
            .button = .none,
            .mod = self.modifiers,
            .p = self.mouse_pt,
            .floating_win = self.windowFor(self.mouse_pt),
        } },
    }) catch @panic("");

    if (self.inject_motion_event) {
        self.inject_motion_event = false;
        _ = self.addEventMouseMotion(self.mouse_pt) catch @panic("");
    }
}

pub fn end_whole() !?u32 {
    const self = win_ref;
    if (!self.end_rendering_done) self.endRendering(.{});
    self.backend.end() catch @panic("");

    for (self.datas_trash.items) |sd| sd.free(self.gpa);
    self.datas_trash = .empty;

    dvui_window_end_time_1.update(end1);

    for (dvui.events()) |*e| {
        if (self.drag_state == .dragging and e.evt == .mouse and e.evt.mouse.action == .release) {
            self.drag_state = .none;
            self.drag_name = "";
        }
        if (!dvui.eventMatch(e, .{ .id = self.data().id, .r = self.rect_pixels, .cleanup = true }))
            continue;

        if (e.evt == .mouse) {
            if (e.evt.mouse.action == .focus) {
                // unhandled click, clear focus
                dvui.focusWidget(null, null, null);
            }
        } else if (e.evt == .key) {
            if (e.evt.key.action == .down and e.evt.key.matchBind("next_widget")) {
                e.handle(@src(), self.data());
                dvui.tabIndexNext(e.num);
            }

            if (e.evt.key.action == .down and e.evt.key.matchBind("prev_widget")) {
                e.handle(@src(), self.data());
                dvui.tabIndexPrev(e.num);
            }
        }
    }

    self.mouse_pt_prev = self.mouse_pt;

    if (!self.subwindowFocused().used) {
        var i = self.subwindows.items.len;
        while (i > 0) : (i -= 1) {
            const sw = self.subwindows.items[i - 1];
            if (sw.used) {
                dvui.focusSubwindow(sw.id, null);
                break;
            }
        }

        dvui.refresh(null, @src(), null);
    }
    dvui_window_end_time_2.update(end2);

    defer dvui.current_window = self.previous_window;

    if (self.extra_frames_needed > 0) return 0;
    var ret: ?u32 = null;
    var it = self.animations.iterator();
    while (it.next_used()) |kv| {
        if (kv.value_ptr.start_time > 0) {
            const st = @as(u32, @intCast(kv.value_ptr.start_time));
            ret = @min(ret orelse st, st);
        } else if (kv.value_ptr.end_time > 0) {
            ret = 0;
            break;
        }
    }
    return ret;
}

fn backend_cursor_management() void {
    const backend = backend_ref;
    const win = win_ref;
    // cursor management
    backend.setCursor(win.cursorRequested()) catch unreachable;
    backend.textInputRect(win.textInputRequested()) catch unreachable;
}
fn backend_render_frame() void {
    const backend = backend_ref;
    // render frame to OS
    backend.renderPresent() catch unreachable;
}
