const std = @import("std");
const posix = std.posix;
const builtin = @import("builtin");

const SigwinchHandling = @import("../sigwinch_handling.zig");
const Winsize = @import("../winsize.zig").Winsize;
const Adapter = @import("../adapter.zig");
const ReadResult = Adapter.ReadResult;

const log = std.log.scoped(.zttio_posix_adapter);

const PosixAdapter = @This();

stdin: std.posix.fd_t,
stdin_buf: []u8,
stdin_reader: std.fs.File.Reader,

stdout: std.posix.fd_t,
stdout_buf: []u8,
stdout_writer: std.fs.File.Writer,

termios: ?posix.termios = null,

winsize_mutex: std.Thread.Mutex = .{},
winsize: ?Winsize = null,

pub fn init(allocator: std.mem.Allocator, stdin: std.fs.File, stdout: std.fs.File) error{ OutOfMemory, NoTty }!PosixAdapter {
    if (!stdout.isTty()) return error.NoTty;

    const stdin_buf = try allocator.alloc(u8, 1024);
    errdefer allocator.free(stdin_buf);

    const stdout_buf = try allocator.alloc(u8, 16 * 1024);
    errdefer allocator.free(stdout_buf);

    return PosixAdapter{
        .stdin = stdin.handle,
        .stdin_buf = stdin_buf,
        .stdin_reader = stdin.reader(stdin_buf),

        .stdout = stdout.handle,
        .stdout_buf = stdout_buf,
        .stdout_writer = stdout.writer(stdout_buf),
    };
}

pub fn deinit(self: *PosixAdapter, allocator: std.mem.Allocator) void {
    allocator.free(self.stdin_buf);
    allocator.free(self.stdout_buf);
}

pub fn adapter(self: *PosixAdapter) Adapter {
    return Adapter{
        .ptr = self,
        .vtable = &Adapter.VTable{
            .enable = enable,
            .disable = disable,
            .isEnabled = isEnabled,

            .getWinsize = getWinsize,

            .read = read,
            .waitForData = waitForStdinData,

            .getReader = getReader,
            .getWriter = getWriter,
        },
    };
}

pub fn getSigWinchHook(self: *PosixAdapter) SigwinchHandling.SignalCallback {
    return SigwinchHandling.SignalCallback{
        .context = self,
        .func = setWinsize,
    };
}

fn setWinsize(self_ptr: *anyopaque) void {
    const self: *PosixAdapter = @ptrCast(@alignCast(self_ptr));

    const winsize = getWinsize(self_ptr) catch return;

    self.winsize_mutex.lock();
    defer self.winsize_mutex.unlock();
    self.winsize = winsize;
}

fn getWinsize(self_ptr: *anyopaque) Adapter.GetWinsizeError!Winsize {
    const self: *PosixAdapter = @ptrCast(@alignCast(self_ptr));

    var winsize = posix.winsize{
        .row = 0,
        .col = 0,
        .xpixel = 0,
        .ypixel = 0,
    };

    const err = posix.system.ioctl(self.stdin, posix.T.IOCGWINSZ, @intFromPtr(&winsize));
    const errno = posix.errno(err);
    if (errno != .SUCCESS) {
        log.warn("unable to get winsize: {s}", .{@tagName(errno)});
        return Adapter.GetWinsizeError.Failed;
    }

    return Winsize{
        .rows = winsize.row,
        .cols = winsize.col,
        .x_pixel = winsize.xpixel,
        .y_pixel = winsize.ypixel,
    };
}

fn read(self_ptr: *anyopaque) Adapter.ReadError!?ReadResult {
    const self: *PosixAdapter = @ptrCast(@alignCast(self_ptr));

    if (self.winsize_mutex.tryLock()) {
        defer self.winsize_mutex.unlock();

        if (self.winsize) |winsize| {
            self.winsize = null;

            return ReadResult{
                .event = .{ .winsize = winsize },
            };
        }
    }

    var buf: [4]u8 = undefined;
    const n = posix.read(self.stdin, buf[0..1]) catch |err| switch (err) {
        error.WouldBlock => return null,
        else => return error.ReadFailed,
    };
    if (n == 0) {
        return null;
    }

    const required = std.unicode.utf8ByteSequenceLength(buf[0]) catch return error.ReadFailed;
    var i: usize = 1;
    while (required > i) : (i += 1) {
        _ = posix.read(self.stdin, buf[i .. i + 1]) catch |err| switch (err) {
            error.WouldBlock => continue,
            else => return error.ReadFailed,
        };
    }

    return ReadResult{
        .codepoint = std.unicode.utf8Decode(buf[0..required]) catch return error.ReadFailed,
    };
}

fn waitForStdinData(self_ptr: *anyopaque, milliseconds: u16) void {
    const self: *PosixAdapter = @ptrCast(@alignCast(self_ptr));

    var pollfds = [_]std.posix.pollfd{
        std.posix.pollfd{
            .fd = self.stdin,
            .events = 1,
            .revents = 0,
        },
    };

    _ = std.posix.poll(&pollfds, milliseconds) catch {};
}

fn enable(self_ptr: *anyopaque) Adapter.EnableError!bool {
    const self: *PosixAdapter = @ptrCast(@alignCast(self_ptr));
    if (self.termios != null) return false;

    const original = std.posix.tcgetattr(self.stdin) catch |err| {
        log.err("failed to enable when getting termios: {s}", .{@errorName(err)});
        return Adapter.EnableError.Failed;
    };

    var raw = original;
    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    raw.lflag.ISIG = false;
    raw.lflag.IEXTEN = false;
    raw.iflag.IXON = false;
    raw.iflag.ICRNL = false;
    raw.iflag.BRKINT = false;
    raw.iflag.INPCK = false;
    raw.iflag.ISTRIP = false;
    raw.oflag.OPOST = true;
    raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;
    raw.cc[@intFromEnum(std.posix.V.MIN)] = 0;

    std.posix.tcsetattr(self.stdin, .FLUSH, raw) catch |err| {
        log.err("failed to enable when setting termios: {s}", .{@errorName(err)});
        return Adapter.EnableError.Failed;
    };

    self.termios = original;
    return true;
}

fn disable(self_ptr: *anyopaque) void {
    const self: *PosixAdapter = @ptrCast(@alignCast(self_ptr));
    const termios = self.termios orelse return;

    std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, termios) catch |err| {
        log.err("failed to disable when setting termios: {s}", .{@errorName(err)});
    };

    self.termios = null;
}

fn isEnabled(self_ptr: *anyopaque) bool {
    const self: *PosixAdapter = @ptrCast(@alignCast(self_ptr));

    return self.termios != null;
}

fn getReader(self_ptr: *anyopaque) *std.Io.Reader {
    const self: *PosixAdapter = @ptrCast(@alignCast(self_ptr));

    return &self.stdin_reader.interface;
}

fn getWriter(self_ptr: *anyopaque) *std.Io.Writer {
    const self: *PosixAdapter = @ptrCast(@alignCast(self_ptr));

    return &self.stdout_writer.interface;
}
