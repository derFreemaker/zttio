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

    var native_adapter = try zttio.Adapters.NativeAdapter.init(allocator, stdin, stdout);
    defer native_adapter.deinit(allocator);
    var normal_parser = zttio.Parsers.NormalParser.init(allocator, event_allocator, native_adapter.adapter());
    defer normal_parser.deinit();
    // var threaded_parser = try zttio.Parsers.ThreadedParser.init(allocator, normal_parser.parser());
    // defer threaded_parser.deinit(event_allocator);

    var tty = try zttio.Tty.init(allocator, normal_parser.parser(), .{
        .caps = try .query(native_adapter.adapter(), 100),
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
