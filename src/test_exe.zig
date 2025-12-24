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

    const tty = try zttio.Tty.init(allocator, event_allocator, .stdin(), .stdout(), .{});
    defer tty.deinit();
    std.debug.print("caps: {any}\n", .{tty.caps});

    while (true) {
        const event = tty.nextEvent();
        defer event.deinit(event_allocator);
        std.debug.print("{any}\n", .{event});

        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    break;
                }
            },
            else => {},
        }
    }
}
