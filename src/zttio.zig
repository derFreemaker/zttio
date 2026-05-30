const builtin = @import("builtin");

pub const Adapter = @import("adapter.zig");
pub const Color = @import("color.zig").Color;
pub const ctlseqs = @import("ctlseqs.zig");
pub const Event = @import("event.zig").Event;
pub const gwidth = @import("gwidth.zig");
pub const Key = @import("key.zig");
pub const Mouse = @import("mouse.zig");
pub const Styling = @import("styling.zig");
pub const TerminalCapabilities = @import("terminal_capabilities.zig");
pub const Tty = @import("tty.zig");
pub const Winsize = @import("winsize.zig").Winsize;

pub const SigwinchHandling = if (builtin.is_test and builtin.os.tag != .windows) @import("sigwinch_handling.zig") else void;
pub const Adapters = struct {
    pub const NativeAdapter = switch (builtin.os.tag) {
        .windows => WinAdapter,
        else => PosixAdapter,
    };

    pub const PosixAdapter = if (builtin.is_test and builtin.os.tag != .windows) @import("adapters/posix_adapter.zig") else void;
    pub const WinAdapter = if (builtin.is_test and builtin.os.tag == .windows) @import("adapters/win_adapter.zig") else void;
};

test {
    _ = @import("color.zig");
    _ = @import("key.zig");
    _ = @import("list_separator.zig");
    _ = @import("terminal_capabilities.zig");
    _ = @import("parser.zig");
    _ = @import("styling.zig");

    const testing = @import("testing.zig");
    _ = testing.refAllDeclsRecursive(@This());
}
