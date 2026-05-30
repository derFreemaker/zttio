const std = @import("std");

const CSI = @import("ctlseqs.zig").CSI;
const ListSeparator = @import("list_separator.zig");

pub const reset = CSI ++ "0m";

const Styling = @This();

inherit: bool = false,

foreground: ?Color = null,
background: ?Color = null,
thickness: ?Thickness = null,
attrs: ?Attributes = null,
underline: ?Underline = null,

pub fn print(self: *const Styling, writer: *std.Io.Writer) !void {
    try writer.writeAll(CSI);
    var sep = ListSeparator.init(";");

    if (!self.inherit) {
        try sep.print(writer);

        try writer.writeByte('0');
    }

    if (self.thickness) |thickness| {
        try sep.print(writer);

        var buf: [8]u8 = undefined;
        try writer.writeAll(thickness.printAsArg(&buf) catch unreachable);
    }

    if (self.attrs) |attrs| {
        try sep.print(writer);

        var buf: [16]u8 = undefined;
        try writer.writeAll(attrs.printAsArg(&buf) catch unreachable);
    }

    if (self.foreground) |fg| {
        try sep.print(writer);

        var buf: [16]u8 = undefined;
        try writer.writeAll(fg.printAsArg(&buf, .foreground) catch unreachable);
    }

    if (self.background) |bg| {
        try sep.print(writer);

        var buf: [16]u8 = undefined;
        try writer.writeAll(bg.printAsArg(&buf, .background) catch unreachable);
    }

    try writer.writeByte('m');

    if (self.underline) |underline| {
        // we print a underline so that terminals which do not support
        // colored/styled underlines at least show an underline
        try writer.writeAll(CSI ++ "4m");

        if (underline.color != null or underline.style != .single) {
            var buf: [20]u8 = undefined;
            try writer.print(CSI ++ "{s}m", .{underline.printAsArg(&buf)});
        }
    }
}

// redirect
pub const format = print;

pub const Color = union(enum) {
    c8: Color8,
    b8: u8,
    rgb8: Rgb,

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

    pub fn printAsArg(self: Color, buf: []u8, layer: Layer) error{NoSpaceLeft}![]u8 {
        switch (self) {
            .c8 => |c8| {
                return try std.fmt.bufPrint(buf, "{d}", .{@intFromEnum(c8) + layer.modifier()});
            },
            .b8 => |n| {
                return try std.fmt.bufPrint(buf, "{d};5;{d}", .{ layer.index(), n });
            },
            .rgb8 => |rgb8| {
                return try std.fmt.bufPrint(buf, "{d};2;{d};{d};{d}", .{ layer.index(), rgb8.r, rgb8.g, rgb8.b });
            },
        }
    }

    pub fn print(self: Color, writer: *std.Io.Writer, layer: Layer) std.Io.Writer.Error!void {
        try writer.writeAll(CSI);

        var buf: [16]u8 = undefined;
        try writer.writeAll(self.printAsArg(buf[2..], layer) catch unreachable);

        try writer.writeByte('m');
    }

    pub const Color8 = enum(u8) {
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

    pub const Rgb = struct {
        r: u8,
        g: u8,
        b: u8,

        pub fn init(r: u8, g: u8, b: u8) Rgb {
            return Rgb{ .r = r, .g = g, .b = b };
        }
    };

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
};

pub const Thickness = enum(u2) {
    pub const reset = CSI ++ "22m";

    bold = 1,
    dim = 2,

    pub fn printAsArg(self: Thickness, buf: []u8) error{NoSpaceLeft}![]const u8 {
        return std.fmt.bufPrint(buf, "{d}", .{@intFromEnum(self)});
    }

    pub fn print(self: Thickness, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.writeAll(CSI);
        try writer.print("{d}", .{@intFromEnum(self)});
        try writer.writeByte('m');
    }
};

pub const Attributes = packed struct {
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

    pub fn printAsArg(self: Attributes, buf: []u8) error{NoSpaceLeft}![]u8 {
        var i: usize = 0;
        var sep = ListSeparator.init(";");

        inline for (@typeInfo(Attributes).@"struct".fields) |field| {
            if (@as(bool, @field(self, field.name))) {
                i += try sep.writeToBuf(buf[i..]);

                if (buf.len < i) {
                    return error.NoSpaceLeft;
                }
                buf[i] = comptime blk: {
                    if (std.mem.eql(u8, field.name, "italic")) {
                        break :blk '3';
                    }

                    if (std.mem.eql(u8, field.name, "blink")) {
                        break :blk '5';
                    }

                    if (std.mem.eql(u8, field.name, "reverse")) {
                        break :blk '7';
                    }
                    if (std.mem.eql(u8, field.name, "hidden")) {
                        break :blk '8';
                    }
                    if (std.mem.eql(u8, field.name, "strikethrough")) {
                        break :blk '9';
                    }

                    unreachable;
                };
                i += 1;
            }
        }

        return buf[0..i];
    }

    pub fn print(self: Attributes, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.writeAll(CSI);

        var buf: [16]u8 = undefined;
        try writer.writeAll(self.printAsArg(&buf) catch unreachable);

        try writer.writeByte('m');
    }
};

test Attributes {
    const attributes = Attributes{
        .italic = true,

        .blink = true,

        .reverse = true,
        .hidden = true,
        .strikethrough = true,
    };
    const expected = "3;5;7;8;9";

    var buf: [16]u8 = undefined;
    const actual = try attributes.printAsArg(&buf);

    try std.testing.expectEqualStrings(expected, actual);
}

pub const Underline = struct {
    // NOTE: this could be 'CSI 4:0m' but is not as widely supported
    pub const reset = CSI ++ "24m";

    color: ?Color = null,
    style: Style = .single,

    pub fn printAsArg(self: Underline, buf: []u8) error{NoSpaceLeft}![]const u8 {
        var i: usize = 0;

        const style = self.style.arg();
        i += style.len;
        if (buf.len < i) {
            return error.NoSpaceLeft;
        }
        @memcpy(buf[0..i], style);

        if (self.color) |color| {
            if (buf.len <= i) {
                return error.NoSpaceLeft;
            }
            buf[i] = ';';
            i += 1;

            i += (try color.printAsArg(buf[i..], .underline)).len;
        }

        return buf[0..i];
    }

    pub fn print(self: Underline, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.writeAll(CSI);

        var buf: [32]u8 = undefined;
        try writer.writeAll(self.printAsArg(&buf) catch unreachable);

        try writer.writeByte('m');
    }

    pub const Style = enum {
        single,
        double,
        curly,
        dotted,
        dashed,

        pub fn arg(self: Style) []const u8 {
            return switch (self) {
                .single => "4",
                .double => "4:2",
                .curly => "4:3",
                .dotted => "4:4",
                .dashed => "4:5",
            };
        }

        pub fn print(self: Style, writer: *std.Io.Writer) std.Io.Writer.Error!void {
            try writer.writeAll(CSI);
            try writer.writeAll(self.arg());
            try writer.writeByte('m');
        }
    };
};
