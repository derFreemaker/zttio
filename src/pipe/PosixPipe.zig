const std = @import("std");
const posix = std.posix;
const builtin = @import("builtin");

const PosixPipe = @This();

read_f: std.Io.File.Reader,
write_f: std.Io.File.Writer,

pub fn init(self: *PosixPipe, io: std.Io, read_buf: []u8, write_buf: []u8, flags: posix.O) error{ Resources, Unexpected }!void {
    var fds: [2]posix.fd_t = undefined;
    if (@TypeOf(posix.system.pipe2) != void) {
        switch (posix.errno(posix.system.pipe2(&fds, flags))) {
            .SUCCESS => {},
            .INVAL => |err| return errnoBug(err), // Invalid flags
            .NFILE => return error.Resources, // SystemFdQuotaExceeded
            .MFILE => return error.Resources, // ProcessFdQuotaExceeded
            else => |err| return posix.unexpectedErrno(err),
        }

        const read_file = std.Io.File{
            .handle = fds[0],
            .flags = .{
                .nonblocking = flags.NONBLOCK,
            },
        };
        self.read_f = read_file.readerStreaming(io, read_buf);
        const write_file = std.Io.File{
            .handle = fds[1],
            .flags = .{
                .nonblocking = flags.NONBLOCK,
            },
        };
        self.write_f = write_file.writerStreaming(io, write_buf);
        errdefer self.deinit();

        return;
    }

    switch (posix.errno(posix.system.pipe(&self.fds))) {
        .SUCCESS => {},
        .NFILE => return error.Resources, // SystemFdQuotaExceeded
        .MFILE => return error.Resources, // ProcessFdQuotaExceeded
        else => |err| return posix.unexpectedErrno(err),
    }

    const read_file = std.Io.File{
        .handle = fds[0],
        .flags = .{
            .nonblocking = flags.NONBLOCK,
        },
    };
    self.read_f = read_file.readerStreaming(io, read_buf);
    const write_file = std.Io.File{
        .handle = fds[1],
        .flags = .{
            .nonblocking = flags.NONBLOCK,
        },
    };
    self.write_f = write_file.writerStreaming(io, write_buf);
    errdefer self.deinit();

    if (@backingInt(flags) == 0) {
        return;
    }

    // CLOEXEC is special, it's a file descriptor flag and must be set using F.SETFD.
    if (flags.CLOEXEC) {
        for (fds) |fd| {
            switch (posix.errno(posix.system.fcntl(fd, posix.F.SETFD, @as(u32, posix.FD_CLOEXEC)))) {
                .SUCCESS => {},
                .INVAL => |err| return errnoBug(err),
                else => |err| return posix.unexpectedErrno(err),
            }
        }
    }

    const new_flags = f: {
        var new_flags = flags;
        new_flags.CLOEXEC = false;
        break :f @backingInt(new_flags);
    };

    if (new_flags != 0) {
        for (fds) |fd| {
            switch (posix.errno(posix.system.fcntl(fd, posix.F.SETFL, new_flags))) {
                .SUCCESS => {},
                .INVAL => |err| return errnoBug(err),
                else => |err| return posix.unexpectedErrno(err),
            }
        }
    }
}

pub fn deinit(self: *PosixPipe) void {
    if (self.read_f.file.handle != -1) {
        closeFd(self.read_f.file.handle);
    }
    if (self.write_f.file.handle != self.read_f.file.handle) {
        closeFd(self.write_f.file.handle);
    }
}

pub fn reader(self: *PosixPipe) *std.Io.Reader {
    return &self.read_f.interface;
}

pub fn writer(self: *PosixPipe) *std.Io.Writer {
    return &self.write_f.interface;
}

pub fn errnoBug(err: posix.E) posix.UnexpectedError {
    switch (builtin.mode) {
        .Debug => std.debug.panic("programmer bug caused syscall error: {t}", .{err}),
        else => return error.Unexpected,
    }
}

pub fn closeFd(fd: posix.fd_t) void {
    if (builtin.os.tag == .wasi and !builtin.link_libc) {
        switch (std.os.wasi.fd_close(fd)) {
            // INTR still a success, see https://github.com/ziglang/zig/issues/2425
            .SUCCESS, .INTR => {},
            .BADF => recoverableOsBugDetected(), // use after free
            else => recoverableOsBugDetected(),
        }
    } else switch (posix.errno(posix.system.close(fd))) {
        // INTR still a success, see https://github.com/ziglang/zig/issues/2425
        .SUCCESS, .INTR => {},
        .BADF => recoverableOsBugDetected(), // user after free
        else => recoverableOsBugDetected(),
    }
}

pub fn recoverableOsBugDetected() void {
    switch (builtin.mode) {
        .Debug => unreachable,
        else => {},
    }
}

test PosixPipe {
    const allocator = std.testing.allocator;

    if (builtin.os.tag == .windows) return error.SkipZigTest;

    var pipe: PosixPipe = undefined;
    try pipe.init(std.testing.io, &.{}, &.{}, .{
        .CLOEXEC = true,
    });
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
