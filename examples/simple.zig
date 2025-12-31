const std = @import("std");
const zttio = @import("zttio");

var global_tty: ?*zttio.Tty = null;

pub const panic = std.debug.FullPanic(testPanic);
pub fn testPanic(msg: []const u8, ret_addr: ?usize) noreturn {
    if (global_tty) |tty| {
        tty.panicDeinit();
    }

    std.debug.defaultPanic(msg, ret_addr);
}

pub fn main() !u8 {
    var gpa: std.heap.GeneralPurposeAllocator(.{
        .retain_metadata = true,
        .never_unmap = true,
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
    try tty.stdout.print("winsize: {any}\n", .{tty.getWinsize()});
    try tty.stdout.print("caps: {any}\n", .{tty.caps});
    try tty.writeHyperlink(.{ .uri = "https://google.com", .params = .{ .id = "go" } }, "google");
    try tty.stdout.writeByte('\n');
    try tty.stdout.writeByte('\n');
    try tty.flush();

    while (true) {
        const event = tty.nextEvent();
        defer event.deinit(event_allocator);

        try tty.moveCursor(.{ .up = 1 });
        try tty.resetLine();
        try tty.stdout.print("{any}\n", .{event});

        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    break;
                }
            },
            else => {},
        }

        try tty.flush();
    }

    try tty.disableAlternativeScreen();
    try tty.flush();

    return 0;
}
