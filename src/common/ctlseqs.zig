const std = @import("std");

const ListSeparator = @import("list_separator.zig");
const Key = @import("key.zig");

pub const ESC = "\x1b";
pub const CSI = ESC ++ "[";
pub const DCS = ESC ++ "P";
pub const OSC = ESC ++ "]";
pub const APC = ESC ++ "_";
pub const ST = ESC ++ "\\";
pub const BEL = "\x07";

pub const Queries = struct {
    pub const primary_device_attrs = CSI ++ "c";
    pub const tertiary_device_attrs = CSI ++ "=c";
    pub const device_status_report = CSI ++ "5n";
    pub const xtversion = CSI ++ ">0q";
    pub const decrqm_focus = CSI ++ "?1004$p";
    pub const decrqm_sgr_pixels = CSI ++ "?1016$p";
    pub const decrqm_sync = CSI ++ "?2026$p";
    pub const decrqm_unicode = CSI ++ "?2027$p";
    pub const decrqm_color_scheme = CSI ++ "?2031$p";
    pub const kitty_keyboard_query = CSI ++ "?u";
    pub const kitty_graphics_query = APC ++ "Gi=1,a=q,q=2" ++ ST;
    pub const sixel_geometry_query = CSI ++ "?2;1;0S";
    pub const cursor_position_request = CSI ++ "6n";
    pub const explicit_width_query = OSC ++ "66;w=1; " ++ ST;
    pub const scaled_text_query = OSC ++ "66;s=2; " ++ ST;
    pub const multi_cursor_query = CSI ++ "> q";
};

pub const Cursor = struct {
    pub const home = CSI ++ "H";

    pub const move_to_line_column = CSI ++ "{d};{d}H";
    pub fn moveTo(writer: *std.Io.Writer, line: usize, column: usize) !void {
        return writer.print(move_to_line_column, .{ line, column });
    }

    pub const move_up_x = CSI ++ "{d}A";
    pub fn moveUp(writer: *std.Io.Writer, num: usize) !void {
        return writer.print(move_up_x, .{num});
    }

    pub const move_down_x = CSI ++ "{d}B";
    pub fn moveDown(writer: *std.Io.Writer, num: usize) !void {
        return writer.print(move_down_x, .{num});
    }

    pub const move_right_x = CSI ++ "{d}C";
    pub fn moveRight(writer: *std.Io.Writer, num: usize) !void {
        return writer.print(move_right_x, .{num});
    }

    pub const move_left_x = CSI ++ "{d}D";
    pub fn moveLeft(writer: *std.Io.Writer, num: usize) !void {
        return writer.print(move_left_x, .{num});
    }

    pub const move_front_down_x = CSI ++ "{d}E";
    pub fn moveFrontDown(writer: *std.Io.Writer, num: usize) !void {
        return writer.print(move_front_down_x, .{num});
    }

    pub const move_front_up_x = CSI ++ "{d}F";
    pub fn moveFrontUp(writer: *std.Io.Writer, num: usize) !void {
        return writer.print(move_front_up_x, .{num});
    }

    pub const move_to_column = CSI ++ "{d}G";
    pub fn moveToColumn(writer: *std.Io.Writer, num: usize) !void {
        return writer.print(move_to_column, .{num});
    }

    pub const request_cursor = CSI ++ "6n";
    pub const move_up_scroll_if_needed = ESC ++ "M";
    pub const save_position = ESC ++ "7";
    pub const restore_position = ESC ++ "8";

    pub const hide_cursor = CSI ++ "?25l";
    pub const show_cursor = CSI ++ "?25h";

    pub const set_cursor_shape = CSI ++ "{d} q";
    pub fn setCursorShape(writer: *std.Io.Writer, shape: Shape) !void {
        return writer.print(set_cursor_shape, .{@intFromEnum(shape)});
    }
    pub const Shape = enum(u8) {
        blinking_block = 1,
        steady_block = 2,
        blinking_underline = 3,
        steady_underline = 4,
        blinking_bar = 5,
        steady_bar = 6,
    };
};

pub const Erase = struct {
    pub const cursor_to_screen_end = CSI ++ "0J";
    pub const screen_begin_to_cursor = CSI ++ "1J";
    pub const screen = CSI ++ "2J";

    pub const saved_lines = CSI ++ "3J";

    pub const cursor_to_line_end = CSI ++ "0K";
    pub const line_begin_to_cursor = CSI ++ "1K";
    pub const line = CSI ++ "2K";
};

pub const Screen = struct {
    pub const save = CSI ++ "?47l";
    pub const restore = CSI ++ "?47h";

    pub const alternative_enable = CSI ++ "?1049h";
    pub const alternative_disable = CSI ++ "?1049l";
};

pub const Hyperlink = struct {
    pub const reset = OSC ++ "8;;" ++ ST;

    uri: []const u8,
    params: Params = .{},

    pub fn introduce(self: Hyperlink, writer: *std.Io.Writer) !void {
        try writer.writeAll(OSC ++ "8;");

        var sep = ListSeparator.init(":");

        if (self.params.id) |id| {
            try sep.print(writer);

            try writer.print("id={s}", .{id});
        }

        try writer.writeAll(ST);
    }

    pub const Params = struct {
        id: ?[]const u8 = null,
    };
};

pub const Terminal = struct {
    // mouse. We try for button motion and any motion. terminals will enable the
    // last one we tried (any motion). This was added because zellij doesn't
    // support any motion currently
    // See: https://github.com/zellij-org/zellij/issues/1679
    pub const mouse_set = CSI ++ "?1002;1003;1004;1006h";
    pub const mouse_set_pixels = CSI ++ "?1002;1003;1004;1016h";
    pub const mouse_reset = CSI ++ "?1002;1003;1004;1006;1016l";

    // in-band window size reports
    pub const in_band_resize_set = CSI ++ "?2048h";
    pub const in_band_resize_reset = CSI ++ "?2048l";

    // sync
    pub const sync_set = CSI ++ "?2026h";
    pub const sync_reset = CSI ++ "?2026l";

    // unicode
    pub const unicode_set = CSI ++ "?2027h";
    pub const unicode_reset = CSI ++ "?2027l";
    pub const explicit_width = OSC ++ "66;w={d};{s}" ++ ST;

    // text sizing
    pub const scaled_text = OSC ++ "66;s={d}:w={d};{s}" ++ ST;
    pub const scaled_text_with_fractions = OSC ++ "66;s={d}:w={d}:n={d}:d={d}:v={d};{s}" ++ ST;

    // bracketed paste
    pub const braketed_paste_set = CSI ++ "?2004h";
    pub const braketed_paste_reset = CSI ++ "?2004l";

    // color scheme updates
    pub const color_scheme_request = CSI ++ "?996n";
    pub const color_scheme_set = CSI ++ "?2031h";
    pub const color_scheme_reset = CSI ++ "?2031l";

    pub const keyboard_handling_reset = CSI ++ "<u";
    pub const keyboard_handling_set_x = CSI ++ ">{d}u";
    pub fn setKeyboardHandling(writer: *std.Io.Writer, detail: Key.KittyFlags) !void {
        const flag_int: u5 = @bitCast(detail);
        return writer.print(keyboard_handling_set_x, .{flag_int});
    }

    pub const title_set_x = OSC ++ "0;{s}" ++ ST;
    pub fn setTitle(writer: *std.Io.Writer, title: []const u8) !void {
        return writer.print(title_set_x, .{title});
    }

    pub const cd_uri_x = OSC ++ "7;{s}" ++ ST;
    pub fn cdUri(writer: *std.Io.Writer, dir_uri: []const u8) !void {
        return writer.print(cd_uri_x, .{dir_uri});
    }

    pub const cd_x = OSC ++ "7;file://{s}" ++ ST;
    pub fn cd(writer: *std.Io.Writer, dir: []const u8) !void {
        return writer.print(cd_x, .{dir});
    }

    pub const notify_x = OSC ++ "9;{s}" ++ ST;
    pub const notify_title_x = OSC ++ "777;notify;{s};{s}" ++ ST;
    pub fn notify(writer: *std.Io.Writer, title: ?[]const u8, msg: []const u8) !void {
        if (title) |t| {
            return writer.print(notify_title_x, .{ t, msg });
        }

        return writer.print(notify_x, .{msg});
    }

    pub const progress_type_x = OSC ++ "9;{d};{d}" ++ ST;
    pub fn progress(writer: *std.Io.Writer, state: Progress) !void {
        switch (state) {
            .default => return writer.print(progress_type_x, .{ 0, 0 }),
            .in_progress => |v| {
                std.debug.assert(v <= 100);
                return writer.print(progress_type_x, .{ 1, v });
            },
            .in_error => |v| {
                std.debug.assert(v <= 100);
                return writer.print(progress_type_x, .{ 2, v });
            },
            .indeterminate => return writer.print(progress_type_x, .{ 3, 0 }),
            .paused => |v| {
                std.debug.assert(v <= 100);
                return writer.print(progress_type_x, .{ 4, v });
            },
        }
    }
    pub const Progress = union(enum) {
        default,
        in_progress: u8,
        in_error: u8,
        indeterminate,
        paused: u8,
    };

    pub const clipboard_copy_x = OSC ++ "52;c;{s}" ++ ST;
    pub fn copyToClipboard(writer: *std.Io.Writer, encoder_allocator: std.mem.Allocator, content: []const u8) !void {
        const encoder = std.base64.standard.Encoder;

        const size = encoder.calcSize(content.len);
        const buf = try encoder_allocator.alloc(u8, size);
        defer encoder_allocator.free(buf);

        const b64 = encoder.encode(buf, content);
        return writer.print(clipboard_copy_x, .{b64});
    }

    pub const clipboard_request = OSC ++ "52;c;?" ++ ST;
};

pub const KittyGraphics = @import("kitty_graphics.zig");

// Color control sequences
// pub const osc4_query = "\x1b]4;{d};?\x1b\\"; // color index {d}
// pub const osc4_reset = "\x1b]104\x1b\\"; // this resets _all_ color indexes
// pub const osc10_query = "\x1b]10;?\x1b\\"; // fg
// pub const osc10_set = "\x1b]10;rgb:{x:0>2}{x:0>2}/{x:0>2}{x:0>2}/{x:0>2}{x:0>2}\x1b\\"; // set default terminal fg
// pub const osc10_reset = "\x1b]110\x1b\\"; // reset fg to terminal default
// pub const osc11_query = "\x1b]11;?\x1b\\"; // bg
// pub const osc11_set = "\x1b]11;rgb:{x:0>2}{x:0>2}/{x:0>2}{x:0>2}/{x:0>2}{x:0>2}\x1b\\"; // set default terminal bg
// pub const osc11_reset = "\x1b]111\x1b\\"; // reset bg to terminal default
// pub const osc12_query = "\x1b]12;?\x1b\\"; // cursor color
// pub const osc12_set = "\x1b]12;rgb:{x:0>2}{x:0>2}/{x:0>2}{x:0>2}/{x:0>2}{x:0>2}\x1b\\"; // set terminal cursor color
// pub const osc12_reset = "\x1b]112\x1b\\"; // reset cursor to terminal default
