const Key = @import("key.zig");
const Mouse = @import("mouse.zig");
const Color = @import("color.zig").Color;
const Winsize = @import("winsize.zig");

pub const Event = union(enum) {
    key_press: Key,
    key_release: Key,

    mouse: Mouse,
    mouse_leave,

    focus_in,
    focus_out,

    paste: []const u8,
    color_report: Color.Report,
    color_scheme: Color.Scheme,

    winsize: Winsize,
};
