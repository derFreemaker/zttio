const builtin = @import("builtin");

pub const ctlseqs = @import("ctlseqs.zig");
pub const gwidth = @import("gwidth.zig");

pub const Styling = @import("styling.zig");
pub const TerminalCapabilities = @import("terminal_capabilities.zig");

pub const Color = @import("color.zig").Color;
pub const Event = @import("event.zig").Event;
pub const Key = @import("key.zig");
pub const Mouse = @import("mouse.zig");
pub const Winsize = @import("winsize.zig").Winsize;

pub const Adapter = @import("adapter.zig");
pub const Adapters = struct {
    pub const NativeAdapter = switch (builtin.os.tag) {
        .windows => WinAdapter,
        else => PosixAdapter,
    };

    pub const PosixAdapter = @import("adapters/posix_adapter.zig");
    pub const WinAdapter = @import("adapters/win_adapter.zig");
};

pub const Parser = @import("parser.zig");
pub const Parsers = struct {
    pub const NormalParser = @import("parsers/normal_parser.zig");
    pub const ThreadedParser = @import("parsers/threaded_parser.zig");
};

pub const Tty = @import("tty.zig");

test {
    const std = @import("std");
    _ = std.testing.refAllDecls(@This());
}
