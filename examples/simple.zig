const std = @import("std");
const builtin = @import("builtin");
const zttio = @import("zttio");

var global_tty: ?*zttio.Tty = null;

pub const panic = std.debug.FullPanic(testPanic);
pub fn testPanic(msg: []const u8, ret_addr: ?usize) noreturn {
    if (global_tty) |tty| {
        tty.revertTerminal();
    }

    std.debug.defaultPanic(msg, ret_addr);
}

pub fn main() !u8 {
    var gpa: std.heap.DebugAllocator(.{
        .never_unmap = true,
        .retain_metadata = true,
        .stack_trace_frames = 50,
    }) = .init;
    defer if (gpa.deinit() == .leak) @panic("leaks found");
    const allocator = gpa.allocator();
    const event_allocator = allocator;

    const stdin: std.fs.File = .stdin();
    const stdout: std.fs.File = .stdout();

    var tty = try zttio.Tty.init(allocator, event_allocator, stdin, stdout, null, .{});
    global_tty = tty;
    defer {
        global_tty = null;
        tty.deinit();
    }

    try tty.enableAndResetAlternativeScreen();
    defer tty.disableAlternativeScreen() catch {};

    try tty.stdout.print("caps: {any}\n", .{tty.caps});
    try tty.writeHyperlink(.{ .uri = "https://github.com/derFreemaker/zttio" }, "github - zttio");
    try tty.stdout.writeByte('\n');

    try tty.flush();

    var pos_row: u16 = 5;
    while (true) {
        var event = tty.nextEvent();
        defer event.deinit(event_allocator);

        try tty.moveCursor(.{ .pos = .{ .row = pos_row } });
        try tty.clearLine(.entire);
        try tty.stdout.print("{any}", .{event});

        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    break;
                } else if (key.matches(zttio.Key.up, .{})) {
                    pos_row = @max(5, pos_row - 1);

                    try tty.clearLine(.entire);
                    try tty.moveCursor(.{ .pos = .{ .row = pos_row } });
                    try tty.stdout.print("{any}", .{event});
                } else if (key.matches(zttio.Key.down, .{})) {
                    pos_row = @min(20, pos_row + 1);

                    try tty.clearLine(.entire);
                    try tty.moveCursor(.{ .pos = .{ .row = pos_row } });
                    try tty.stdout.print("{any}", .{event});
                }
            },
            .winsize => |winsize| {
                try tty.moveCursor(.{ .pos = .{ .row = 3 } });
                try tty.clearLine(.entire);
                try tty.stdout.print("{any}", .{winsize});
            },
            else => {},
        }

        try tty.flush();
    }

    return 0;
}
