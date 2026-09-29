const builtin = @import("builtin");

const WinPipe = @import("WinPipe.zig");
const PosixPipe = @import("PosixPipe.zig");

const Pipe = @This();

internal: if (builtin.os.tag == .windows)
    WinPipe
else
    PosixPipe,

pub fn init(self: *Pipe, options: Options) error{ Resources, Unexpected }!void {
    if (builtin.os.tag == .windows) {
        try WinPipe.init(&self.internal, .{
            .server = .{
                .attributes = .{ .INHERIT = false },
                .mode = .{ .IO = if (options.non_blocking) .ASYNCHRONOUS else .SYNCHRONOUS_NONALERT },
            },
            .client = .{
                .attributes = .{ .INHERIT = false },
                .mode = .{ .IO = if (options.non_blocking) .ASYNCHRONOUS else .SYNCHRONOUS_NONALERT },
            },
            .outbound = true,
        });
    } else {
        try PosixPipe.init(&self.internal, .{
            .non_blocking = options.non_blocking,
        });
    }
}

pub fn deinit(self: *Pipe) void {
    self.internal.deinit();
}

pub const Options = struct {
    non_blocking: bool = false,
};

test "blocking" {
    var pipe: Pipe = undefined;
    try pipe.init(.{
        .non_blocking = false,
    });
    pipe.deinit();
}

test "non blocking" {
    var pipe: Pipe = undefined;
    try pipe.init(.{
        .non_blocking = true,
    });
    pipe.deinit();
}
