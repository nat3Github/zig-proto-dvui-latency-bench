const std = @import("std");
const assert = std.debug.assert;
const panic = std.debug.panic;
const Allocator = std.mem.Allocator;

const icons = @import("icons").tvg;
const dvui = @import("dvui");
const tailwind = @import("tailwind");
const z2d = @import("z2d");
const util = @import("util.zig");

const fifoasync = @import("fifoasync");
const ThreadControl = fifoasync.thread.ThreadControl;
const ThreadStatus = fifoasync.thread.ThreadStatus;

const Task = struct {};
const FifoMPSC = fifoasync.spsc.FlexFifo(Task, false, true);

tc: ThreadControl = .{},
alloc: Allocator = undefined,
fifo: FifoMPSC = undefined,

pub fn init(alloc: Allocator) @This() {
    var k = @This(){};
    k.alloc = alloc;
    k.fifo.init(alloc, 4096);
    k.tc.spawn(alloc, "allocator", .{}, server, .{});
}

pub fn deinit(self: *@This()) void {
    self.tc.join(self.alloc);
}
const Action = enum(u8) {
    free,
    pre_alloc,
};

fn background_action(self: *@This()) void {
    // switch (ac) {
    //     .free => |_| delayed_free(),
    //     .pre_alloc => |_| pre_alloc(),
    // }
    self.delayed_free();
}

fn server(sig: ThreadStatus, self: *@This()) void {
    while (sig.signal.load() != .stop_signal) {
        while (self.fifo.pop()) |_| {
            self.alloc.deinit();
        }
        sig.wait(1_000_000_000) catch {};
    }
}

pub const LogAllocator = struct {
    const mem = std.mem;
    child_allocator: Allocator,
    log_enabled: bool = true,
    name: []const u8 = "",

    pub fn allocator(self: *LogAllocator) Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }
    fn print(self: *@This(), comptime fmt: []const u8, args: anytype) void {
        if (self.log_enabled) {
            std.debug.print("{s}", .{self.name});
            std.debug.print(fmt, args);
        }
    }

    fn alloc(ctx: *anyopaque, n: usize, alignment: mem.Alignment, ra: usize) ?[*]u8 {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        const allc = self.child_allocator;
        const ret = allc.vtable.alloc(allc.ptr, n, alignment, ra);
        self.print("info: allocated {} bytes\n", .{n * alignment.toByteUnits()});
        return ret;
    }

    fn resize(ctx: *anyopaque, buf: []u8, alignment: mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        const allc = self.child_allocator;
        const ret = allc.vtable.resize(allc.ptr, buf, alignment, new_len, ret_addr);
        self.print("info: allocated {} bytes\n", .{new_len * alignment.toByteUnits()});
        return ret;
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: mem.Alignment, new_len: usize, return_address: usize) ?[*]u8 {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        const allc = self.child_allocator;
        const ret = allc.vtable.remap(allc.ptr, memory, alignment, new_len, return_address);
        self.print("info: remapped {} bytes\n", .{new_len * alignment.toByteUnits()});
        return ret;
    }

    fn free(ctx: *anyopaque, buf: []u8, alignment: mem.Alignment, ret_addr: usize) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        const allc = self.child_allocator;
        self.print("info: freed {} bytes\n", .{buf.len});
        allc.vtable.free(allc.ptr, buf, alignment, ret_addr);
    }
};
