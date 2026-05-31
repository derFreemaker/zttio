const std = @import("std");
const BufPrintError = std.fmt.BufPrintError;

const CSI = @import("ctlseqs.zig").CSI;
const ListSeparator = @import("list_separator.zig");

pub const reset = CSI ++ "0m";

const Styling = @This();

fg: Color = .inherit,
bg: Color = .inherit,
thickness: Thickness = .inherit,
attrs: Attributes = .{},
underline: Underline = .{},

pub fn eql(self: Styling, other: Styling) bool {
    if (!self.fg.eql(other.fg)) {
        return false;
    }

    if (!self.bg.eql(other.bg)) {
        return false;
    }

    if (self.thickness != other.thickness) {
        return false;
    }

    if (!self.attrs.eql(other.attrs)) {
        return false;
    }

    if (!self.underline.eql(other.underline)) {
        return false;
    }

    return true;
}

pub inline fn diff(self: Styling, other: Styling) Styling {
    return Styling{
        .fg = self.fg.diff(other.fg),
        .bg = self.bg.diff(other.bg),
        .thickness = if (self.thickness == other.thickness) Thickness.inherit else other.thickness,
        .attrs = self.attrs.diff(other.attrs),
        .underline = self.underline.diff(other.underline),
    };
}

pub fn print(self: *const Styling, writer: *std.Io.Writer) !void {
    try writer.writeAll(CSI);
    var sep = ListSeparator.init(";");

    if (self.fg != .inherit) {
        try sep.print(writer);

        var buf: [16]u8 = undefined;
        try writer.writeAll(self.fg.printAsArg(&buf, .foreground) catch unreachable);
    }

    if (self.bg != .inherit) {
        try sep.print(writer);

        var buf: [16]u8 = undefined;
        try writer.writeAll(self.bg.printAsArg(&buf, .background) catch unreachable);
    }

    if (self.thickness != .inherit) {
        try sep.print(writer);

        var buf: [1]u8 = undefined;
        try writer.writeAll(self.thickness.printAsArg(&buf) catch unreachable);
    }

    if (!self.attrs.isInherit()) {
        try sep.print(writer);

        var buf: [24]u8 = undefined;
        try writer.writeAll(self.attrs.printAsArg(&buf) catch unreachable);
    }

    try writer.writeByte('m');

    if (!self.underline.isInherit()) {
        // we print a underline so that terminals which do not support
        // colored/styled underlines at least show an underline
        try writer.writeAll(CSI ++ "4m");

        var buf: [24]u8 = undefined;
        try writer.print(CSI ++ "{s}m", .{self.underline.printAsArg(&buf) catch unreachable});
    }
}

// redirect
pub const format = print;

pub const Color = union(enum(u2)) {
    inherit,
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

    pub fn eql(self: Color, other: Color) bool {
        if (std.meta.activeTag(self) != std.meta.activeTag(other)) {
            return false;
        }

        return switch (self) {
            .inherit => true,
            .c8 => self.c8 == other.c8,
            .b8 => self.b8 == other.b8,
            .rgb8 => self.rgb8.eql(other.rgb8),
        };
    }

    pub fn diff(self: Color, other: Color) Color {
        if (other == .inherit) {
            return .inherit;
        }

        if (std.meta.activeTag(self) != std.meta.activeTag(other)) {
            return other;
        }

        switch (self) {
            .inherit => unreachable,
            .c8 => {
                if (self.c8 == other.c8) {
                    return .inherit;
                } else {
                    return other;
                }
            },
            .b8 => {
                if (self.b8 == other.b8) {
                    return .inherit;
                } else {
                    return other;
                }
            },
            .rgb8 => {
                if (self.rgb8.eql(other.rgb8)) {
                    return .inherit;
                } else {
                    return other;
                }
            },
        }
    }

    pub fn printAsArg(self: Color, buf: []u8, layer: Layer) BufPrintError![]u8 {
        return switch (self) {
            .inherit => &.{},
            .c8 => |c8| try std.fmt.bufPrint(buf, "{d}", .{@intFromEnum(c8) + layer.modifier()}),
            .b8 => |n| try std.fmt.bufPrint(buf, "{d};5;{d}", .{ layer.index(), n }),
            .rgb8 => |rgb8| try std.fmt.bufPrint(buf, "{d};2;{d};{d};{d}", .{ layer.index(), rgb8.r, rgb8.g, rgb8.b }),
        };
    }

    pub fn print(self: Color, writer: *std.Io.Writer, layer: Layer) std.Io.Writer.Error!void {
        if (self == .inherit) {
            return;
        }

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

    pub const Rgb = packed struct(u24) {
        r: u8,
        g: u8,
        b: u8,

        pub fn init(r: u8, g: u8, b: u8) Rgb {
            return Rgb{ .r = r, .g = g, .b = b };
        }

        pub inline fn eql(self: Rgb, other: Rgb) bool {
            return @as(u24, @bitCast(self)) == @as(u24, @bitCast(other));
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

    inherit = 0,
    bold = 1,
    dim = 2,

    pub fn printAsArg(self: Thickness, buf: []u8) BufPrintError![]u8 {
        if (self == .inherit) {
            return &.{};
        }

        if (buf.len < 1) {
            return BufPrintError.NoSpaceLeft;
        }
        buf[0] = @as(u8, @intFromEnum(self)) + 0x30; // offset into asci
        return buf[0..0];
    }

    pub fn print(self: Thickness, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        if (self == .inherit) {
            return;
        }

        try writer.writeAll(CSI);
        var buf: [1]u8 = undefined;
        try writer.writeAll(self.printAsArg(&buf) catch unreachable);
        try writer.writeByte('m');
    }
};

const TriState = enum(u2) { inherit = 0, unset = 1, set = 2 };

pub const Attributes = packed struct(u12) {
    pub const italic_reset = CSI ++ "23m";

    pub const blink_reset = CSI ++ "25m";
    pub const rapid_blink_reset = CSI ++ "26m";
    pub const reverse_reset = CSI ++ "27m";
    pub const hidden_reset = CSI ++ "28m";
    pub const strikethrough_reset = CSI ++ "29m";

    pub const Map = std.StaticStringMap(u8).initComptime(.{
        // 1 -> Bold (Thickness)
        // 2 -> Dim  (Thickness)
        .{ "italic", '3' },
        // 4 -> Underline
        .{ "blink", '5' },
        .{ "rapid_blink", '6' },
        .{ "reverse", '7' },
        .{ "hidden", '8' },
        .{ "strikethrough", '9' },
    });

    italic: TriState = .inherit,
    blink: TriState = .inherit,
    rapid_blink: TriState = .inherit,
    reverse: TriState = .inherit,
    hidden: TriState = .inherit,
    strikethrough: TriState = .inherit,

    pub inline fn isInherit(self: Attributes) bool {
        return @as(@typeInfo(Attributes).@"struct".backing_integer.?, @bitCast(self)) == 0;
    }

    pub inline fn eql(self: Attributes, other: Attributes) bool {
        return @as(u12, @bitCast(self)) == @as(u12, @bitCast(other));
    }

    pub fn diff(self: Attributes, other: Attributes) Attributes {
        var result = Attributes{};

        inline for (@typeInfo(Attributes).@"struct".fields) |field| {
            if (@field(self, field.name) != @field(other, field.name)) {
                @field(result, field.name) = @field(other, field.name);
            }
        }

        return result;
    }

    pub fn printAsArg(self: Attributes, buf: []u8) BufPrintError![]u8 {
        var i: usize = 0;
        var sep = ListSeparator.init(";");

        inline for (@typeInfo(Attributes).@"struct".fields) |field| {
            const attr_byte = comptime Map.get(field.name).?;

            switch (@field(self, field.name)) {
                .inherit => {},
                .unset => {
                    i += try sep.writeToBuf(buf[i..]);
                    if (buf.len < i + 1) {
                        return BufPrintError.NoSpaceLeft;
                    }

                    buf[i] = '2';
                    buf[i + 1] = attr_byte;
                    i += 2;
                },
                .set => {
                    i += try sep.writeToBuf(buf[i..]);
                    if (buf.len < i) {
                        return BufPrintError.NoSpaceLeft;
                    }

                    buf[i] = attr_byte;
                    i += 1;
                },
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
    {
        const attributes = Attributes{
            .italic = .set,

            .blink = .set,
            .rapid_blink = .set,
            .reverse = .set,
            .hidden = .set,
            .strikethrough = .set,
        };
        const expected = "3;5;6;7;8;9";

        var buf: [16]u8 = undefined;
        const actual = try attributes.printAsArg(&buf);

        try std.testing.expectEqualStrings(expected, actual);
    }

    {
        const attributes = Attributes{
            .italic = .unset,

            .blink = .unset,
            .rapid_blink = .unset,
            .reverse = .unset,
            .hidden = .unset,
            .strikethrough = .unset,
        };
        const expected = "23;25;26;27;28;29";

        var buf: [17]u8 = undefined;
        const actual = try attributes.printAsArg(&buf);

        try std.testing.expectEqualStrings(expected, actual);
    }
}

pub const Underline = struct {
    // NOTE: this could be 'CSI 4:0m' but is not as widely supported
    pub const reset = CSI ++ "24m";

    color: Color = .inherit,
    style: UnderlineStyle = .inherit,

    pub inline fn isInherit(self: Underline) bool {
        return self.color == .inherit and self.style == .inherit;
    }

    pub inline fn eql(self: Underline, other: Underline) bool {
        return self.style != other.style and self.color.eql(other.color);
    }

    pub inline fn diff(self: Underline, other: Underline) Underline {
        return Underline{
            .color = self.color.diff(other.color),
            .style = if (self.style == other.style) UnderlineStyle.inherit else other.style,
        };
    }

    pub fn printAsArg(self: Underline, buf: []u8) BufPrintError![]const u8 {
        var i: usize = 0;

        if (self.style != .inherit) {
            const style = self.style.arg();
            i += style.len;
            if (buf.len < i) {
                return BufPrintError.NoSpaceLeft;
            }
            @memcpy(buf[0..i], style);

            if (self.color != .inherit) {
                if (buf.len <= i) {
                    return BufPrintError.NoSpaceLeft;
                }
                buf[i] = ';';
                i += 1;
            }
        }

        i += (try self.color.printAsArg(buf[i..], .underline)).len;

        return buf[0..i];
    }

    pub fn print(self: Underline, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.writeAll(CSI);

        var buf: [32]u8 = undefined;
        try writer.writeAll(self.printAsArg(&buf) catch unreachable);

        try writer.writeByte('m');
    }

    pub const UnderlineStyle = enum {
        inherit,
        single,
        double,
        curly,
        dotted,
        dashed,

        pub fn arg(self: UnderlineStyle) []const u8 {
            return switch (self) {
                .inherit => "",
                .single => "4",
                .double => "4:2",
                .curly => "4:3",
                .dotted => "4:4",
                .dashed => "4:5",
            };
        }

        pub fn print(self: UnderlineStyle, writer: *std.Io.Writer) std.Io.Writer.Error!void {
            if (self != .inherit) {
                return;
            }

            try writer.writeAll(CSI);
            try writer.writeAll(self.arg());
            try writer.writeByte('m');
        }
    };
};
