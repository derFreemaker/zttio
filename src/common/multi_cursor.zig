const std = @import("std");

const ctlseqs = @import("ctlseqs.zig");

pub const INTRODUCER = ctlseqs.CSI ++ ">";
pub const TRAILER = " q";

pub const Report = struct {
    shape: Shape,
    pos: Position,
};

pub const ColorReport = struct {
    text_under_cursor: ColorSpace,
    cursor: ColorSpace,
};

pub const ColorSpace = union(Enum) {
    follow_main,
    special,
    rgb: [3]u8,
    index: u8,

    pub fn parse(color_space_buf: []const u8) error{InvalidColorSpace}!ColorSpace {
        var color_space_iter = std.mem.splitScalar(u8, color_space_buf, ':');
        const type_buf = color_space_iter.next() orelse return error.InvalidColorSpace;
        const type_num = std.fmt.parseUnsigned(u8, type_buf, 10) catch return error.InvalidColorSpace;

        switch (type_num) {
            @intFromEnum(Enum.follow_main) => return .follow_main,
            @intFromEnum(Enum.special) => return .special,
            @intFromEnum(Enum.rgb) => {
                const r_buf = color_space_iter.next() orelse return error.InvalidColorSpace;
                const r = std.fmt.parseUnsigned(u8, r_buf, 10) catch return error.InvalidColorSpace;

                const g_buf = color_space_iter.next() orelse return error.InvalidColorSpace;
                const g = std.fmt.parseUnsigned(u8, g_buf, 10) catch return error.InvalidColorSpace;

                const b_buf = color_space_iter.next() orelse return error.InvalidColorSpace;
                const b = std.fmt.parseUnsigned(u8, b_buf, 10) catch return error.InvalidColorSpace;

                return ColorSpace{
                    .rgb = .{ r, g, b },
                };
            },
            @intFromEnum(Enum.index) => {
                const index_buf = color_space_iter.next() orelse return error.InvalidColorSpace;
                const index = std.fmt.parseUnsigned(u8, index_buf, 10) catch return error.InvalidColorSpace;
                
                return ColorSpace{ .index = index };
            },

            else => return error.InvalidColorSpace,
        }
    }

    pub const Enum = enum(u8) {
        follow_main = 0,
        special = 1,
        rgb = 2,
        index = 5,
    };
};

pub const Shape = enum(u8) {
    block = 1,
    beam = 2,
    underline = 3,
    follow_main = 29,
};

pub const Position = union(Enum) {
    follow_main,
    xy: XY,
    area: Rectangle,

    pub fn parse(pos_buf: []const u8) error{InvalidPosition}!Position {
        var pos_param_iter = std.mem.splitScalar(u8, pos_buf, ':');
        const type_buf = pos_param_iter.next() orelse return error.InvalidPosition;
        const type_num = std.fmt.parseUnsigned(u8, type_buf, 10) catch return error.InvalidPosition;

        switch (type_num) {
            @intFromEnum(Enum.follow_main) => return .follow_main,
            @intFromEnum(Enum.xy) => {
                const x_buf = pos_param_iter.next() orelse return error.InvalidPosition;
                const x = std.fmt.parseUnsigned(u16, x_buf, 10) catch return error.InvalidPosition;

                const y_buf = pos_param_iter.next() orelse return error.InvalidPosition;
                const y = std.fmt.parseUnsigned(u16, y_buf, 10) catch return error.InvalidPosition;

                return Position{ .xy = .{
                    .x = x,
                    .y = y,
                } };
            },
            @intFromEnum(Enum.area) => {
                const top_left_x_buf = pos_param_iter.next() orelse return error.InvalidPosition;
                const top_left_x = std.fmt.parseUnsigned(u16, top_left_x_buf, 10) catch return error.InvalidPosition;

                const top_left_y_buf = pos_param_iter.next() orelse return error.InvalidPosition;
                const top_left_y = std.fmt.parseUnsigned(u16, top_left_y_buf, 10) catch return error.InvalidPosition;

                const bottom_right_x_buf = pos_param_iter.next() orelse return error.InvalidPosition;
                const bottom_right_x = std.fmt.parseUnsigned(u16, bottom_right_x_buf, 10) catch return error.InvalidPosition;

                const bottom_right_y_buf = pos_param_iter.next() orelse return error.InvalidPosition;
                const bottom_right_y = std.fmt.parseUnsigned(u16, bottom_right_y_buf, 10) catch return error.InvalidPosition;

                return Position{ .area = .{
                    .top_left = .{
                        .x = top_left_x,
                        .y = top_left_y,
                    },
                    .bottom_right = .{
                        .x = bottom_right_x,
                        .y = bottom_right_y,
                    },
                } };
            },
            else => return error.InvalidPosition,
        }
    }

    pub const Rectangle = struct {
        top_left: XY,
        bottom_right: XY,
    };

    pub const XY = struct {
        x: u16,
        y: u16,
    };

    pub const Enum = enum(u8) {
        follow_main = 0,
        xy = 2,
        area = 4,
    };
};
