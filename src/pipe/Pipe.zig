const std = @import("std");
const builtin = @import("builtin");

const WinPipe = @import("WinPipe.zig");
const PosixPipe = @import("PosixPipe.zig");

const Pipe = @This();

internal: if (builtin.os.tag == .windows)
    WinPipe
else
    PosixPipe,

pub fn init(self: *Pipe, io: std.Io, read_buf: []u8, write_buf: []u8, options: Options) error{ Resources, Unexpected }!void {
    if (builtin.os.tag == .windows) {
        try WinPipe.init(&self.internal, io, read_buf, write_buf, .{
            .read = .{
                .mode = .{ .IO = if (options.non_blocking) .ASYNCHRONOUS else .SYNCHRONOUS_NONALERT },
            },
            .write = .{
                .mode = .{ .IO = if (options.non_blocking) .ASYNCHRONOUS else .SYNCHRONOUS_NONALERT },
            },
        });
    } else {
        try PosixPipe.init(&self.internal, io, read_buf, write_buf, .{
            .NONBLOCK = options.non_blocking,
        });
    }
}

pub fn deinit(self: *Pipe) void {
    self.internal.deinit();
}

pub fn reader(self: *Pipe) *std.Io.Reader {
    return self.internal.reader();
}

pub fn writer(self: *Pipe) *std.Io.Writer {
    return self.internal.writer();
}

pub const Options = struct {
    non_blocking: bool = false,
};

test Pipe {
    const allocator = std.testing.allocator;

    var pipe: Pipe = undefined;
    try pipe.init(std.testing.io, &.{}, &.{}, .{});
    defer pipe.deinit();

    const str = "test bytes";

    var pwriter = pipe.writer();
    try pwriter.writeAll(str);
    try pwriter.flush();

    var preader = pipe.reader();
    const read = try preader.readAllocAll(allocator, str.len);
    defer allocator.free(read);

    try std.testing.expectEqualStrings(str, read);
}
