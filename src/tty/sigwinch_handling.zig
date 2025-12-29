const std = @import("std");
const posix = std.posix;
const builtin = @import("builtin");

const common = @import("common");
const Winsize = common.Winsize;

pub const SignalHandler = struct {
    context: *anyopaque,
    callback: *const fn (context: *anyopaque) void,
};

/// global signal handlers
var handlers: [8]SignalHandler = undefined;
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
    handler_installed = false;
    var act = posix.Sigaction{
        .handler = .{ .handler = posix.SIG.DFL },
        .mask = switch (builtin.os.tag) {
            .macos => 0,
            else => posix.sigemptyset(),
        },
        .flags = 0,
    };
    posix.sigaction(posix.SIG.WINCH, &act, null);
}

/// Install a signal handler for winsize. A maximum of 8 handlers may be
/// installed
pub fn notifyWinsize(handler: SignalHandler) error{OutOfMemory}!void {
    handler_mutex.lock();
    defer handler_mutex.unlock();
    if (handler_idx == handlers.len) return error.OutOfMemory;
    handlers[handler_idx] = handler;
    handler_idx += 1;
}

pub fn removeNotifyWinsize(context: *anyopaque) void {
    handler_mutex.lock();
    defer handler_mutex.unlock();
    
    for (handlers[0..handler_idx], 0..) |handler, i| {
        if (handler.context == context) {
            handlers[i] = undefined;
            @memmove(handlers[i..handlers.len - 1], handlers[i + 1..]);
            handler_idx -= 1;
        }
    }
}

fn handleWinch(_: c_int) callconv(.c) void {
    handler_mutex.lock();
    defer handler_mutex.unlock();
    var i: usize = 0;
    while (i < handler_idx) : (i += 1) {
        const handler = handlers[i];
        handler.callback(handler.context);
    }
}
