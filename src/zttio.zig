const builtin = @import("builtin");

pub const Adapter = @import("tty/adapter.zig");
pub const Color = @import("color.zig").Color;
pub const ctlseqs = @import("ctlseqs.zig");
pub const Event = @import("tty/event.zig").Event;
pub const gwidth = @import("gwidth.zig");
pub const Key = @import("key.zig");
pub const Mouse = @import("mouse.zig");
pub const Styling = @import("styling.zig");
pub const TerminalCapabilities = @import("tty/terminal_capabilities.zig");
pub const Tty = @import("tty/tty.zig");
pub const Winsize = @import("winsize.zig").Winsize;

pub const Graphics = struct {
    pub const Kitty = @import("tty/graphics/kitty_graphics.zig");
};

pub const SigwinchHandling = if (builtin.os.tag != .windows) @import("tty/sigwinch_handling.zig") else void;
pub const Adapters = struct {
    pub const NativeAdapter = switch (builtin.os.tag) {
        .windows => @import("tty/adapters/win_adapter.zig"),
        else => @import("tty/adapters/posix_adapter.zig"),
    };

    pub const PipeAdater = @import("tty/adapters/pipe_adapter.zig");
};

test {
    _ = @import("pipe/windows_pipe.zig");

    _ = @import("tty/terminal_capabilities.zig");
    _ = @import("tty/parser.zig");

    _ = @import("color.zig");
    _ = @import("key.zig");
    _ = @import("list_separator.zig");
    _ = @import("styling.zig");

    const testing = @import("testing.zig");
    _ = testing.refAllDeclsRecursive(@This());
}
