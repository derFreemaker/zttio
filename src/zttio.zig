const builtin = @import("builtin");

pub const Adapter = @import("adapter.zig");
pub const Color = @import("color.zig").Color;
pub const ctlseqs = @import("ctlseqs.zig");
pub const Event = @import("event.zig").Event;
pub const gwidth = @import("gwidth.zig");
pub const Key = @import("key.zig");
pub const Mouse = @import("mouse.zig");
pub const SigwinchHandling = @import("sigwinch_handling.zig");
pub const Styling = @import("styling.zig");
pub const TerminalCapabilities = @import("terminal_capabilities.zig");
pub const Tty = @import("tty.zig");
pub const Winsize = @import("winsize.zig").Winsize;

pub const Adapters = struct {
    pub const NativeAdapter = switch (builtin.os.tag) {
        .windows => WinAdapter,
        else => PosixAdapter,
    };

    pub const PosixAdapter = @import("adapters/posix_adapter.zig");
    pub const WinAdapter = @import("adapters/win_adapter.zig");
};

test {
    _ = @import("color.zig");
    _ = @import("key.zig");
    _ = @import("list_separator.zig");
    _ = @import("terminal_capabilities.zig");
    _ = @import("parser.zig");
    _ = @import("styling.zig");

    const std = @import("std");
    _ = std.testing.refAllDecls(@This());
}
