const std = @import("std");
const builtin = @import("builtin");

const ntdll = @import("ntdll");

const WinPipe = @This();

server: ntdll.HANDLE,
client: ntdll.HANDLE,

pub fn init(self: *WinPipe, options: Options) error{ Resources, Unexpected }!void {
    const named_pipe_device = try getNamedPipeDevice();

    self.server = server: {
        var handle: ntdll.HANDLE = undefined;
        var iosb: ntdll.IO_STATUS_BLOCK = undefined;
        while (true) switch (ntdll.NtCreateNamedPipeFile(
            &handle,
            .{
                .SPECIFIC = .{ .FILE_PIPE = .{
                    .READ_DATA = options.inbound,
                    .WRITE_DATA = options.outbound,
                    .WRITE_ATTRIBUTES = true,
                } },
                .STANDARD = .{ .SYNCHRONIZE = true },
            },
            &.{
                .RootDirectory = named_pipe_device,
                .Attributes = options.server.attributes,
            },
            &iosb,
            .{ .READ = true, .WRITE = true },
            .CREATE,
            options.server.mode,
            .{ .TYPE = .BYTE_STREAM },
            .{ .MODE = .BYTE_STREAM },
            .{ .OPERATION = .QUEUE },
            options.maximum_instances,
            if (options.inbound) options.quota else 0,
            if (options.outbound) options.quota else 0,
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
    errdefer ntdll.NtCloseSafe(self.server);

    self.client = client: {
        var handle: ntdll.HANDLE = undefined;
        var iosb: ntdll.IO_STATUS_BLOCK = undefined;
        while (true) switch (ntdll.NtOpenFile(
            &handle,
            .{
                .SPECIFIC = .{ .FILE_PIPE = .{
                    .READ_DATA = options.outbound,
                    .WRITE_DATA = options.inbound,
                    .WRITE_ATTRIBUTES = true,
                } },
                .STANDARD = .{ .SYNCHRONIZE = true },
            },
            &.{
                .RootDirectory = self.server,
                .Attributes = options.client.attributes,
            },
            &iosb,
            .{ .READ = true, .WRITE = true },
            options.client.mode,
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
    errdefer ntdll.NtCloseSafe(self.client);
}

pub fn deinit(self: *WinPipe) void {
    ntdll.NtCloseSafe(self.client);
    ntdll.NtCloseSafe(self.server);
}

pub const Options = struct {
    server: End,
    client: End,
    inbound: bool = false,
    outbound: bool = false,
    maximum_instances: u32 = 1,
    quota: u32 = 4 * 1024,
    default_timeout: ntdll.LARGE_INTEGER = -120 * std.time.ns_per_s / 100,

    pub const End = struct {
        attributes: ntdll.OBJECT.ATTRIBUTES.Flags = .{},
        mode: ntdll.FILE.MODE,
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
                ntdll.NtCloseSafe(fresh_handle);
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

    const handle = try getNamedPipeDevice();
    try testing.expect(handle != ntdll.INVALID_HANDLE);
}

test WinPipe {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    var pipe: WinPipe = undefined;
    try pipe.init(.{
        .server = .{
            .attributes = .{ .INHERIT = false },
            .mode = .{ .IO = .SYNCHRONOUS_NONALERT },
        },
        .client = .{
            .attributes = .{ .INHERIT = false },
            .mode = .{ .IO = .SYNCHRONOUS_NONALERT },
        },
        .inbound = true,
    });
    errdefer pipe.deinit();
}
