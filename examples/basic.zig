const std = @import("std");
const builtin = @import("builtin");
const zttio = @import("zttio");

var global_tty: ?*zttio.Tty = null;

pub const panic = std.debug.FullPanic(testPanic);
pub fn testPanic(msg: []const u8, ret_addr: ?usize) noreturn {
    if (global_tty) |tty| {
        tty.deinit();
    }

    std.debug.defaultPanic(msg, ret_addr);
}

pub fn main(init: std.process.Init) !u8 {
    if (comptime builtin.os.tag != .windows) zttio.SigwinchHandling.setSignalHandler();
    defer if (comptime builtin.os.tag != .windows) zttio.SigwinchHandling.resetSignalHandler();

    var gpa: std.heap.DebugAllocator(.{
        .never_unmap = true,
        .retain_metadata = true,
        .stack_trace_frames = 50,
    }) = .init;
    defer if (gpa.deinit() == .leak) @panic("leaks found");
    const allocator = gpa.allocator();
    const event_allocator = allocator;

    const stdin: std.Io.File = .stdin();
    const stdout: std.Io.File = .stdout();

    var native_adapter = try zttio.Adapters.NativeAdapter.init(allocator, init.io, stdin, stdout);
    defer native_adapter.deinit(allocator);
    if (comptime builtin.os.tag != .windows) try zttio.SigwinchHandling.notifyWinsize(native_adapter.getSigWinchHook());
    defer if (comptime builtin.os.tag != .windows) zttio.SigwinchHandling.removeNotifyWinsize(&native_adapter);

    var tty = try zttio.Tty.init(allocator, event_allocator, native_adapter.adapter(), .{
        .caps = try .query(init.io, init.environ_map, native_adapter.adapter(), .fromMilliseconds(100)),
    });
    global_tty = &tty;
    defer {
        global_tty = null;
        tty.deinit();
    }

    try tty.enableAndResetAlternativeScreen();
    defer tty.disableAlternativeScreen() catch {};

    try tty.writer.print("caps: {any}\n", .{tty.caps});
    try tty.writeHyperlink(.{ .uri = "https://github.com/derFreemaker/zttio" }, "github - zttio");
    try tty.writer.writeByte('\n');

    try tty.flush();

    var pos_row: u16 = 5;
    while (true) {
        var event = try tty.nextEvent();
        defer event.deinit(event_allocator);

        try tty.moveCursor(.{ .pos = .{ .row = pos_row } });
        try tty.clearLine(.entire);
        try tty.writer.print("{any}", .{event});

        switch (event) {
            .key_press => |key| {
                if (key.matches(.from('c'), .{ .ctrl = true })) {
                    break;
                } else if (key.matches(.up, .{})) {
                    pos_row = @max(5, pos_row - 1);

                    try tty.setStyling(&zttio.Styling{
                        .background = .{ .c8 = .blue },
                    });

                    try tty.clearLine(.entire);
                    try tty.moveCursor(.{ .pos = .{ .row = pos_row } });
                    try tty.writer.print("{any}", .{event});
                } else if (key.matches(.down, .{})) {
                    pos_row = @min(20, pos_row + 1);

                    try tty.setStyling(&zttio.Styling{
                        .background = .{ .c8 = .magenta },
                    });

                    try tty.clearLine(.entire);
                    try tty.moveCursor(.{ .pos = .{ .row = pos_row } });
                    try tty.writer.print("{any}", .{event});
                }
            },
            .winsize => |winsize| {
                try tty.moveCursor(.{ .pos = .{ .row = 3 } });
                try tty.clearLine(.entire);
                try tty.writer.print("winsize: {any}", .{winsize});
            },
            else => {},
        }

        try tty.flush();
    }

    return 0;
}
