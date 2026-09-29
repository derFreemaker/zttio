const std = @import("std");
const posix = std.posix;
const builtin = @import("builtin");

const PosixPipe = @This();

fds: [2]posix.fd_t,

pub fn init(self: *PosixPipe, options: Options) error{ Resources, Unexpected }!void {
    const flags: posix.O = .{
        .NONBLOCK = options.non_blocking,
    };

    if (@TypeOf(posix.system.pipe2) != void) {
        switch (posix.errno(posix.system.pipe2(&self.fds, flags))) {
            .SUCCESS => return,
            .INVAL => |err| return errnoBug(err), // Invalid flags
            .NFILE => return error.Resources,
            .MFILE => return error.Resources,
            else => |err| return posix.unexpectedErrno(err),
        }
    }

    switch (posix.errno(posix.system.pipe(&self.fds))) {
        .SUCCESS => {},
        .NFILE => return error.SystemFdQuotaExceeded,
        .MFILE => return error.ProcessFdQuotaExceeded,
        else => |err| return posix.unexpectedErrno(err),
    }
    errdefer {
        closeFd(self.fds[0]);
        closeFd(self.fds[1]);
    }

    if (@as(u32, @bitCast(flags)) == 0) {
        return;
    }

    for (self.fds) |fd| {
        switch (posix.errno(posix.system.fcntl(fd, posix.F.SETFL, flags))) {
            .SUCCESS => {},
            .INVAL => |err| {
                return errnoBug(err);
            },
            else => |err| {
                return posix.unexpectedErrno(err);
            },
        }
    }
}

pub fn deinit(self: *PosixPipe) void {
    closeFd(self.fds[0]);
    closeFd(self.fds[1]);
}

pub const Options = struct {
    non_blocking: bool = false,
};

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

test "blocking" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    var pipe: PosixPipe = undefined;
    try pipe.init(.{
        .non_blocking = false,
    });
    pipe.deinit();
}

test "non blocking" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    var pipe: PosixPipe = undefined;
    try pipe.init(.{
        .non_blocking = true,
    });
    pipe.deinit();
}
