const std = @import("std");
const zttio = @import("zttio");

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{
        .retain_metadata = true,
        .never_unmap = true,
        .stack_trace_frames = 50,
    }) = .init;
    defer if (gpa.deinit() == .leak) @panic("leaks found");
    const allocator = gpa.allocator();
    const event_allocator = allocator;
    
    const stdin = std.fs.File.stdin();
    const stdout = std.fs.File.stdout();
    const tty = try zttio.Tty.init(allocator, event_allocator, stdin, stdout);
    defer tty.deinit();

    const writer = tty.writer();
    writer.writeAll("\x1b[?2004h") catch unreachable;
    writer.flush() catch unreachable;
    
    while (true) {
        const event = tty.nextEvent();
        defer event.deinit(event_allocator);
        std.debug.print("{any}\n", .{event});

        switch (event) {
            .key_press => |key| {
                std.debug.print("key: '{s}'\n", .{key.text orelse "<null>"});
                if (key.matches('c', .{ .ctrl = true })) {
                    break;
                }
            },
            .paste => |paste| {
                std.debug.print("paste: {s}\n", .{paste});
            },
            else => {},
        }
    }
}
