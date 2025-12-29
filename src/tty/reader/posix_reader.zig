const std = @import("std");
const posix = std.posix;
const builtin = @import("builtin");

const common = @import("common");
const Winsize = common.Winsize;

const ReadResult = @import("../reader.zig").ReadResult;

const PosixReader = @This();

stdin_fd: std.posix.fd_t,

pub fn init(stdin_fd: std.fs.File.Handle, _: std.fs.File.Handle) PosixReader {
    return PosixReader{
        .stdin_fd = stdin_fd,
    };
}

pub fn next(self: *PosixReader, _: std.mem.Allocator) error{ OutOfMemory, ReadFailed, EOF }!?ReadResult {
    var buf: [4]u8 = undefined;
    const n = posix.read(self.stdin_fd, buf[0..1]) catch |err| switch (err) {
        error.WouldBlock => return null,
        else => return error.ReadFailed,
    };
    if (n == 0) {
        return null;
    }

    const required = std.unicode.utf8ByteSequenceLength(buf[0]) catch return error.ReadFailed;
    var i: usize = 1;
    while (required > i) : (i += 1) {
        _ = posix.read(self.stdin_fd, buf[i .. i + 1]) catch |err| switch (err) {
            error.WouldBlock => continue,
            else => return error.ReadFailed,
        };
    }

    return ReadResult{
        .cp = std.unicode.utf8Decode(buf[0..required]) catch return error.ReadFailed,
    };
}

/// Get the window size from the kernel
pub fn getWinsize(fd: posix.fd_t) !Winsize {
    var winsize = posix.winsize{
        .row = 0,
        .col = 0,
        .xpixel = 0,
        .ypixel = 0,
    };

    const err = posix.system.ioctl(fd, posix.T.IOCGWINSZ, @intFromPtr(&winsize));
    if (posix.errno(err) == .SUCCESS)
        return Winsize{
            .rows = winsize.row,
            .cols = winsize.col,
            .x_pixel = winsize.xpixel,
            .y_pixel = winsize.ypixel,
        };
    return error.IoctlError;
}
