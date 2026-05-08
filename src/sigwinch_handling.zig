const std = @import("std");
const posix = std.posix;
const builtin = @import("builtin");

const Winsize = @import("winsize.zig").Winsize;

pub const SignalCallback = struct {
    pub const Func = fn (context: *anyopaque) void;

    context: *anyopaque,
    func: *const Func,
};

const Handler = struct {
    active: std.atomic.Value(bool) = .init(false),
    callback: SignalCallback = undefined,
};

/// global signal handlers
var handlers = [_]Handler{Handler{}} ** 8;
var handler_installed: std.atomic.Value(bool) = .init(false);

pub fn setSignalHandler() void {
    if (handler_installed.cmpxchgStrong(false, true, .acq_rel, .acquire) != null) {
        return;
    }

    var act = posix.Sigaction{
        .handler = .{ .handler = handleWinch },
        .mask = switch (builtin.os.tag) {
            .macos => 0,
            else => posix.sigemptyset(),
        },
        .flags = 0,
    };
    posix.sigaction(posix.SIG.WINCH, &act, null);
}

/// Resets the signal handler to its default
pub fn resetSignalHandler() void {
    if (handler_installed.cmpxchgStrong(true, false, .acq_rel, .acquire) != null) {
        return;
    }

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

/// Install a signal handler for winsize, a maximum of 8 handlers may be installed.
pub fn notifyWinsize(callback: SignalCallback) error{OutOfMemory}!void {
    for (&handlers) |*handler| {
        if (handler.active.cmpxchgStrong(false, true, .acq_rel, .acquire) != null) {
            continue;
        }

        handler.callback = callback;
        return;
    }

    return error.OutOfMemory;
}

pub fn removeNotifyWinsize(context: *anyopaque) void {
    for (&handlers) |*handler| {
        if (!handler.active.load(.acquire)) {
            continue;
        }
        if (handler.callback.context != context) {
            continue;
        }

        handler.active.store(false, .release);
        break;
    }
}

fn handleWinch(_: std.posix.SIG) callconv(.c) void {
    for (&handlers) |handler| {
        if (!handler.active.load(.acquire)) {
            continue;
        }

        const callback = handler.callback;
        callback.func(callback.context);
    }
}
