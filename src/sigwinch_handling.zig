const std = @import("std");
const posix = std.posix;
const builtin = @import("builtin");

const Winsize = @import("winsize.zig").Winsize;

pub const SignalCallback = struct {
    context: *anyopaque,
    func: *const fn (context: *anyopaque) void,
};

/// global signal handlers
var handlers: [8]SignalCallback = undefined;
var handler_mutex: std.Thread.Mutex = .{};
var handler_idx: usize = 0;

var handler_installed: bool = false;

pub fn setSignalHandler() void {
    if (handler_installed) return;

    var act = posix.Sigaction{
        .handler = .{ .handler = handleWinch },
        .mask = switch (builtin.os.tag) {
            .macos => 0,
            else => posix.sigemptyset(),
        },
        .flags = 0,
    };
    posix.sigaction(posix.SIG.WINCH, &act, null);
    handler_installed = true;
}

/// Resets the signal handler to it's default
pub fn resetSignalHandler() void {
    if (!handler_installed) return;

    var act = posix.Sigaction{
        .handler = .{ .handler = posix.SIG.DFL },
        .mask = switch (builtin.os.tag) {
            .macos => 0,
            else => posix.sigemptyset(),
        },
        .flags = 0,
    };
    posix.sigaction(posix.SIG.WINCH, &act, null);
    handler_installed = false;
}

/// Install a signal handler for winsize. A maximum of 8 handlers may be
/// installed
pub fn notifyWinsize(handler: SignalCallback) error{OutOfMemory}!void {
    handler_mutex.lock();
    defer handler_mutex.unlock();
    if (handler_idx == handlers.len) return error.OutOfMemory;

    handlers[handler_idx] = handler;
    handler_idx += 1;
}

pub fn removeNotifyWinsize(context: *anyopaque) void {
    handler_mutex.lock();
    defer handler_mutex.unlock();

    for (handlers[0..handler_idx], 0..) |*handler, i| {
        if (handler.context != context) continue;

        handler.* = undefined;
        @memmove(handlers[i .. handlers.len - 1], handlers[i + 1 ..]);
        handler_idx -= 1;
    }
}

fn handleWinch(_: c_int) callconv(.c) void {
    handler_mutex.lock();
    defer handler_mutex.unlock();

    for (handlers[0..handler_idx]) |callback| {
        callback.func(callback.context);
    }
}
