const std = @import("std");
const zttio = @import("zttio");

var raw_mode: ?zttio.RawMode = null;

pub const panic = std.debug.FullPanic(testPanic);
pub fn testPanic(msg: []const u8, ret_addr: ?usize) noreturn {
    if (raw_mode) |*mode| {
        mode.disable();
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

    raw_mode = try zttio.RawMode.enable(stdin.handle, stdout.handle);
    defer raw_mode.?.disable();

    var tty = try zttio.Tty.init(allocator, event_allocator, stdin, stdout, null, .{});
    defer tty.deinit();

    try tty.enableAndResetAlternativeScreen();
    try tty.stdout.print("winsize: {any}\n", .{tty.getWinsize()});
    try tty.stdout.print("caps: {any}\n", .{tty.caps});
    try tty.writeHyperlink(.{ .uri = "https://google.com" }, "google");
    try tty.stdout.writeByte('\n');
    try tty.flush();

    while (true) {
        const event = tty.nextEvent();
        defer event.deinit(event_allocator);

        try tty.resetLine();
        try tty.stdout.print("{any}", .{event});

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
