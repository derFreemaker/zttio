const std = @import("std");

const CSI = @import("ctlseqs.zig").CSI;
const ListSeparator = @import("list_separator.zig");

pub const reset = CSI ++ "0m";

const AnsiStyling = @This();

inherit: bool = false,

foreground: ?Color = null,
background: ?Color = null,
underline: ?Underline = null,
thickness: ?Thickness = null,
attrs: ?Attributes = null,

pub fn print(self: AnsiStyling, writer: *std.Io.Writer) !void {
    try writer.writeAll(CSI);
    var sep = ListSeparator.init(";");

    if (!self.inherit) {
        try sep.print(writer);

        try writer.writeByte('0');
    }

    if (self.thickness) |thickness| {
        try sep.print(writer);

        try writer.print("{d}", .{@intFromEnum(thickness)});
    }

    if (self.attrs) |attrs| {
        try sep.print(writer);

        var buf: [9]u8 = undefined;
        try writer.writeAll(attrs.printAsArg(&buf));
    }

    if (self.foreground) |fg| {
        try sep.print(writer);

        var buf: [16]u8 = undefined;
        try writer.writeAll(fg.printAsArg(&buf, .foreground));
    }

    if (self.background) |bg| {
        try sep.print(writer);

        var buf: [16]u8 = undefined;
        try writer.writeAll(bg.printAsArg(&buf, .background));
    }

    try writer.writeByte('m');

    if (self.underline) |underline| {
        // we print a underline so that terminals which do not support
        // colored/styled underlines at least show an underline
        try writer.writeAll(CSI ++ "4m");

        // wezterm seems to discard the escape sequence when finding an unknown number
        if (underline.color != null or underline.style != .single) {
            var buf: [20]u8 = undefined;
            try writer.print(CSI ++ "{s}m", .{underline.printAsArg(&buf)});
        }
    }
}

// redirect
pub fn format(self: AnsiStyling, writer: *std.Io.Writer) !void {
    return self.print(writer);
}

pub const Layer = enum {
    foreground,
    background,
    underline,

    pub fn modifier(self: Layer) u8 {
        return switch (self) {
            .foreground => 0,
            .background => 10,
            .underline => 20,
        };
    }

    pub fn index(self: Layer) u8 {
        return 38 + self.modifier();
    }

    pub fn reset(self: Layer, writer: *std.Io.Writer) !void {
        return writer.print(CSI ++ "{d}m", .{self.index() + 1});
    }
};

pub const Thickness = enum {
    pub const reset = CSI ++ "22m";

    bold,
    dim,
};

pub const Attributes = struct {
    pub const italic_reset = CSI ++ "23m";
    pub const blink_reset = CSI ++ "25m";

    pub const reverse_reset = CSI ++ "27m";
    pub const hidden_reset = CSI ++ "28m";
    pub const strikethrough_reset = CSI ++ "29m";

    italic: bool = false, // 3,
    blink: bool = false, // 5,

    reverse: bool = false, // 7,
    hidden: bool = false, // 8
    strikethrough: bool = false, // 9

    pub fn printAsArg(self: Attributes, buf: []u8) []const u8 {
        std.debug.assert(buf.len >= 9);

        var i: usize = 0;
        var sep = ListSeparator.init(";");

        if (self.italic) {
            i += sep.writeToBuf(buf[i..]);

            buf[i] = '3';
            i += 1;
        }

        if (self.blink) {
            i += sep.writeToBuf(buf[i..]);

            buf[i] = '5';
            i += 1;
        }

        if (self.reverse) {
            i += sep.writeToBuf(buf[i..]);

            buf[i] = '7';
            i += 1;
        }

        if (self.hidden) {
            i += sep.writeToBuf(buf[i..]);

            buf[i] = '8';
            i += 1;
        }

        if (self.strikethrough) {
            i += sep.writeToBuf(buf[i..]);

            buf[i] = '9';
            i += 1;
        }

        return buf[0..i];
    }
};

pub const Color = union(enum) {
    c8: Color8,
    b8: u8,
    rgb8: RGB,

    pub fn normal(c8: Color8) Color {
        return Color{ .c8 = c8 };
    }

    pub fn bit8(n: u8) Color {
        return Color{ .b8 = n };
    }

    pub fn rgb(r: u8, g: u8, b: u8) Color {
        return Color{ .rgb8 = .{
            .r = r,
            .g = g,
            .b = b,
        } };
    }

    fn printAsArg(self: Color, buf: []u8, layer: Layer) []const u8 {
        switch (self) {
            .c8 => |c8| {
                std.debug.assert(buf.len >= 2);
                return std.fmt.bufPrint(buf, "{d}", .{@intFromEnum(c8) + layer.modifier()}) catch unreachable;
            },
            .b8 => |n| {
                std.debug.assert(buf.len >= 8);
                return std.fmt.bufPrint(buf, "{d};5;{d}", .{ layer.index(), n }) catch unreachable;
            },
            .rgb8 => |rgb8| {
                std.debug.assert(buf.len >= 16);
                return std.fmt.bufPrint(buf, "{d};2;{d};{d};{d}", .{ layer.index(), rgb8.r, rgb8.g, rgb8.b }) catch unreachable;
            },
        }
    }

    pub fn print(self: Color, buf: []u8, layer: Layer) error{NoSpaceLeft}![]const u8 {
        std.debug.assert(buf.len >= 19);

        @memcpy(buf[0..2], CSI);
        const n = self.printAsArg(buf[2..], layer).len;
        buf[2 + n] = 'm';

        return buf[0 .. n + 3];
    }

    pub const Color8 = enum(u7) {
        default = 39,

        black = 30,
        red,
        green,
        yellow,
        blue,
        magenta,
        cyan,
        white,

        bright_black = 90,
        bright_red,
        bright_green,
        bright_yellow,
        bright_blue,
        bright_magenta,
        bright_cyan,
        bright_white,
    };

    pub const RGB = struct {
        r: u8,
        g: u8,
        b: u8,

        pub fn init(r: u8, g: u8, b: u8) RGB {
            return RGB{ .r = r, .g = g, .b = b };
        }
    };
};

pub const Underline = struct {
    // Underlines
    // pub const ul_off = CSI ++ "24m"; // NOTE: this could be \x1b[4:0m but is not as widely supported
    // pub const ul_single = CSI ++ "4m";
    // pub const ul_double = CSI ++ "4:2m";
    // pub const ul_curly = CSI ++ "4:3m";
    // pub const ul_dotted = CSI ++ "4:4m";
    // pub const ul_dashed = CSI ++ "4:5m";

    pub const reset = CSI ++ "24m"; // NOTE: this could be 'CSI 4:0m' but is not as widely supported

    color: ?Color = null,
    style: Style = .single,

    pub fn printAsArg(self: Underline, buf: []u8) []const u8 {
        std.debug.assert(buf.len >= 20);

        var i: usize = 0;

        const style = self.style.print();
        i += style.len;
        @memcpy(buf[0..i], style);

        if (self.color) |color| {
            buf[i] = ';';
            i += 1;

            i += color.printAsArg(buf[i..], .underline).len;
        }

        return buf[0..i];
    }

    pub const Style = enum {
        single,
        double,
        curly,
        dotted,
        dashed,

        pub fn print(self: Style) []const u8 {
            return switch (self) {
                .single => "4",
                .double => "4:2",
                .curly => "4:3",
                .dotted => "4:4",
                .dashed => "4:5",
            };
        }
    };
};
