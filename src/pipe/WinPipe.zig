const std = @import("std");
const builtin = @import("builtin");

const ntdll = @import("ntdll");

const WinPipe = @This();

read_f: std.Io.File.Reader,
write_f: std.Io.File.Writer,

pub fn init(self: *WinPipe, io: std.Io, read_buf: []u8, write_buf: []u8, options: Options) error{ Resources, Unexpected }!void {
    const named_pipe_device = try getNamedPipeDevice();

    const read_fd = server: {
        var handle: ntdll.HANDLE = undefined;
        var iosb: ntdll.IO_STATUS_BLOCK = undefined;
        while (true) switch (ntdll.NtCreateNamedPipeFile(
            &handle,
            .{
                .SPECIFIC = .{ .FILE_PIPE = .{
                    .READ_DATA = true,
                    .WRITE_ATTRIBUTES = true,
                } },
                .STANDARD = .{ .SYNCHRONIZE = true },
            },
            &.{
                .RootDirectory = named_pipe_device,
                .Attributes = options.read.attributes,
            },
            &iosb,
            .{ .READ = true, .WRITE = true },
            .CREATE,
            options.read.mode,
            .{ .TYPE = .BYTE_STREAM },
            .{ .MODE = .BYTE_STREAM },
            .{ .OPERATION = .QUEUE },
            1,
            options.quota,
            0,
            &options.default_timeout,
        )) {
            .SUCCESS => break,
            .CANCELLED => {
                // @TODO: add something which allows us to cancel the pipe creation
                continue;
            },
            .INVALID_HANDLE,
            .INVALID_PARAMETER,
            => |status| {
                return ntdll.statusBug(status);
            },
            .INSUFFICIENT_RESOURCES => return error.Resources,
            else => |status| {
                return ntdll.unexpectedStatus(status);
            },
        };
        break :server handle;
    };
    errdefer _ = ntdll.NtClose(read_fd);
    const read_file = std.Io.File{
        .handle = read_fd,
        .flags = .{
            .nonblocking = options.read.mode.IO == .ASYNCHRONOUS,
        },
    };
    self.read_f = read_file.readerStreaming(io, read_buf);

    const write_fd = client: {
        var handle: ntdll.HANDLE = undefined;
        var iosb: ntdll.IO_STATUS_BLOCK = undefined;
        while (true) switch (ntdll.NtOpenFile(
            &handle,
            .{
                .SPECIFIC = .{ .FILE_PIPE = .{
                    .WRITE_DATA = true,
                    .WRITE_ATTRIBUTES = true,
                } },
                .STANDARD = .{ .SYNCHRONIZE = true },
            },
            &.{
                .RootDirectory = read_fd,
                .Attributes = options.write.attributes,
            },
            &iosb,
            .{ .READ = true, .WRITE = true },
            options.write.mode,
        )) {
            .SUCCESS => break,
            .CANCELLED => {
                // @TODO: add something which allows us to cancel the pipe creation
                continue;
            },
            .INVALID_PARAMETER => |status| {
                return ntdll.statusBug(status);
            },
            .INSUFFICIENT_RESOURCES => return error.Resources,
            else => |status| {
                return ntdll.unexpectedStatus(status);
            },
        };
        break :client handle;
    };
    errdefer _ = ntdll.NtClose(write_fd);
    const write_file = std.Io.File{
        .handle = write_fd,
        .flags = .{
            .nonblocking = options.read.mode.IO == .ASYNCHRONOUS,
        },
    };
    self.write_f = write_file.writerStreaming(io, write_buf);
}

pub fn deinit(self: *WinPipe) void {
    _ = ntdll.NtClose(self.write_f.file.handle);
    _ = ntdll.NtClose(self.read_f.file.handle);
}

pub fn reader(self: *WinPipe) *std.Io.Reader {
    return &self.read_f.interface;
}

pub fn writer(self: *WinPipe) *std.Io.Writer {
    return &self.write_f.interface;
}

pub const Options = struct {
    read: End = .{},
    write: End = .{},
    quota: u32 = 4 * 1024,
    default_timeout: ntdll.LARGE_INTEGER = -120 * std.time.ns_per_s / 100,

    pub const End = struct {
        attributes: ntdll.OBJECT.ATTRIBUTES.Flags = .{},
        mode: ntdll.FILE.MODE = .{ .IO = .SYNCHRONOUS_NONALERT },
    };
};

var _named_pipe_device: ?ntdll.HANDLE = null;

fn getNamedPipeDevice() ntdll.UnexpectedError!ntdll.HANDLE {
    {
        if (@atomicLoad(?ntdll.HANDLE, &_named_pipe_device, .acquire)) |handle| {
            return handle;
        }
    }

    var fresh_handle: ntdll.HANDLE = undefined;
    var iosb: ntdll.IO_STATUS_BLOCK = undefined;
    while (true) switch (ntdll.NtOpenFile(
        &fresh_handle,
        .{ .STANDARD = .{ .SYNCHRONIZE = true } },
        &.{
            .ObjectName = @constCast(&ntdll.UNICODE_STRING.initFromUTF8Comptime("\\Device\\NamedPipe\\")),
        },
        &iosb,
        .VALID_FLAGS,
        .{ .IO = .SYNCHRONOUS_NONALERT, .DIRECTORY_FILE = true },
    )) {
        .SUCCESS => {
            const compare_result: ??ntdll.HANDLE = @cmpxchgStrong(
                ?ntdll.HANDLE,
                &_named_pipe_device,
                null,
                fresh_handle,
                .release,
                .monotonic,
            );
            if (compare_result) |prev_handle| {
                _ = ntdll.NtClose(fresh_handle);
                return prev_handle.?;
            } else {
                return fresh_handle;
            }
        },
        .DELETE_PENDING => {
            // convert from milliseconds to 100 nanosecond units
            const timeout: ntdll.LARGE_INTEGER = -(1 * 10);
            switch (ntdll.NtDelayExecution(
                .FALSE,
                &timeout,
            )) {
                .SUCCESS => {},
                else => |status| {
                    return ntdll.unexpectedStatus(status);
                },
            }
            continue;
        },
        .INVALID_PARAMETER,
        .OBJECT_PATH_SYNTAX_BAD,
        .INVALID_HANDLE,
        .OBJECT_NAME_INVALID,
        .OBJECT_NAME_NOT_FOUND,
        .OBJECT_PATH_NOT_FOUND,
        .SHARING_VIOLATION,
        .ACCESS_DENIED,
        => |status| {
            return ntdll.statusBug(status);
        },
        else => |status| {
            return ntdll.unexpectedStatus(status);
        },
    };
}

const testing = std.testing;

test getNamedPipeDevice {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const file_handle = try getNamedPipeDevice();
    try testing.expect(file_handle != ntdll.INVALID_HANDLE);
}

test WinPipe {
    const allocator = std.testing.allocator;

    if (builtin.os.tag != .windows) return error.SkipZigTest;

    var pipe: WinPipe = undefined;
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
