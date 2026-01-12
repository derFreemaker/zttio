const std = @import("std");
const zigimg = @import("zigimg");

const Source = @import("source.zig").Source;

const ctlseqs = @import("../ctlseqs.zig");
const ListSeperator = @import("../list_separator.zig");

pub const INTRODUCER = ctlseqs.APC ++ "G";
pub const HEADER_CLOSE = ";";
pub const CLOSE = ctlseqs.ST;

pub const MAX_CHUNK_LEN = 4096;
pub const MAX_RAW_CHUNK_LEN = std.base64.standard.Decoder.calcSizeUpperBound(MAX_CHUNK_LEN) catch unreachable;

const KittyGraphics = @This();

pub const Error = Source.Error || std.Io.Writer.Error;

pub const TRANSMIT_HEADER = "f=32,t=d";

pub fn transmitOnly(writer: *std.Io.Writer, allocator: std.mem.Allocator, source: Source, options: TransmitOnlyOptions) Error!void {
    var img = try source.getImage(allocator);
    defer img.deinit(allocator);

    var opts = options;
    if (options.width == null) opts.width = @intCast(img.width);
    if (options.height == null) opts.height = @intCast(img.height);

    try writer.print(INTRODUCER ++ "a=t," ++ TRANSMIT_HEADER, .{});
    try writeFlagStruct(writer, opts);
    try writeBytes(writer, img.rawBytes());

    try writer.writeAll(CLOSE);
}

pub const TransmitOnlyOptions = struct {
    num: ?u32 = null,
    placement_id: ?u32 = null,

    width: ?u32 = null,
    height: ?u32 = null,
};

pub fn transmitAndDisplay(writer: *std.Io.Writer, allocator: std.mem.Allocator, source: Source, options: TransmitAndDisplayOptions) Error!void {
    var img = try source.getImage(allocator);
    defer img.deinit(allocator);

    var opts = options;
    if (options.width == null) opts.width = @intCast(img.width);
    if (options.height == null) opts.height = @intCast(img.height);

    try writer.print(INTRODUCER ++ "a=T," ++ TRANSMIT_HEADER, .{});
    try writeFlagStruct(writer, opts);
    try writeBytes(writer, img.rawBytes());

    try writer.writeAll(CLOSE);
}

pub const TransmitAndDisplayOptions = struct {
    num: ?u32 = null,
    placement_id: ?u32 = null,

    width: ?u32 = null,
    height: ?u32 = null,

    relative: ?RelativePlacement = null,
    display_from_image: ?DisplayFromImage = null,

    x_in_cell_offset: ?u32 = null,
    y_in_cell_offset: ?u32 = null,
    display_cell_width: ?u32 = null,
    display_cell_height: ?u32 = null,

    z_index: ?i32 = null,
    do_not_move_cursor: ?bool = null,
};

pub fn display(writer: *std.Io.Writer, opts: DisplayOnlyOptions) std.Io.Writer.Error!void {
    try writer.writeAll(INTRODUCER ++ "a=d");
    try writeFlagStruct(writer, opts);
    try writer.writeAll(HEADER_CLOSE ++ CLOSE);
}

pub const DisplayOnlyOptions = struct {
    id_or_num: IdOrNum,
    placement_id: ?u32 = null,

    relative: ?RelativePlacement = null,
    display_from_image: ?DisplayFromImage = null,

    x_in_cell_offset: ?u32 = null,
    y_in_cell_offset: ?u32 = null,
    display_cell_width: ?u32 = null,
    display_cell_height: ?u32 = null,

    z_index: ?i32 = null,
    do_not_move_cursor: ?bool = null,
};

pub fn erase(writer: *std.Io.Writer, opts: EraseOptions) std.Io.Writer.Error!void {
    try writer.writeAll(INTRODUCER ++ "a=d,d=");

    switch (opts) {
        .all => try writer.writeByte('a'),
        .select => |select| {
            if (select.id_or_num == .id) {
                try writer.writeByte('i');
            } else {
                try writer.writeByte('n');
            }

            try writeFlagStruct(writer, select);
        },
        .intersect_current_cursor => try writer.writeByte('c'),
        .all_animation_frames => try writer.writeByte('f'),
        .intersect_cell => |pos| {
            try writer.writeByte('p');

            try writer.print(",x={d},y={d}", .{ pos.x, pos.y });
        },
        .intersect_cell_at_z => |pos| {
            try writer.writeByte('q');

            try writer.print(",x={d},y={d},z={d}", .{ pos.x, pos.y, pos.z });
        },
        .in_range => |range| {
            try writer.writeByte('r');

            try writer.print(",x={d}", .{range.min});

            if (range.max) |max| {
                try writer.print(",y={d}", .{max});
            }
        },
        .intersect_column => |column| {
            try writer.writeByte('x');

            try writer.print(",x={d}", .{column});
        },
        .intersect_row => |row| {
            try writer.writeByte('y');

            try writer.print(",y={d}", .{row});
        },
        .intersect_z => |z| {
            try writer.writeByte('z');

            try writer.print(",z={d}", .{z});
        },
    }

    try writer.writeAll(CLOSE);
}

pub const EraseOptions = union(enum) {
    all, // a
    select: Select, // i/n
    intersect_current_cursor, // c
    all_animation_frames, // f
    intersect_cell: CellPosition, // p
    intersect_cell_at_z: ZCellPosition, // q
    in_range: InRange, // r
    intersect_column: u32, // x
    intersect_row: u32, // y
    intersect_z: u32, // z

    pub const Select = struct {
        id_or_num: IdOrNum,
        placement_id: ?u32 = null,
    };

    pub const CellPosition = struct {
        x: u32 = 0,
        y: u32 = 0,
    };

    pub const ZCellPosition = struct {
        x: u32 = 0,
        y: u32 = 0,
        z: u32 = 0,
    };

    pub const InRange = struct {
        min: u32 = 0,
        max: ?u32 = null,
    };
};

pub fn transmitAnimationFrame(writer: *std.Io.Writer, allocator: std.mem.Allocator, opts: TransmitAnimationFrameOptions) Error!void {
    try writer.writeAll(INTRODUCER ++ "a=f");
    try writeFlag(writer, "id_or_num", opts.id_or_num);
    try writeFlag(writer, "display_at_x", opts.x);
    try writeFlag(writer, "display_at_y", opts.y);
    try writeFlag(writer, "replace_pixels", opts.replace_pixels);
    try writeFlag(writer, "background_color_rgba", opts.background_color_rgba);
    try writeFlag(writer, "edit_frame", opts.edit_frame);

    switch (opts.img) {
        .transmit => |transmit| {
            try writeFlag(writer, "height", transmit.height);
            try writeFlag(writer, "width", transmit.width);
            try writeFlag(writer, "animation_gap_ms", transmit.gap_ms);

            var img = try transmit.source.getImage(allocator);
            defer img.deinit(allocator);

            try writeBytes(writer, img.rawBytes());
        },
        .previous => |prev| {
            try writeFlag(writer, "previous_frame", prev);
        },
    }

    try writer.writeAll(CLOSE);
}

pub const TransmitAnimationFrameOptions = struct {
    id_or_num: IdOrNum,

    x: ?u32 = null,
    y: ?u32 = null,
    img: DataSource,
    edit_frame: u32,

    replace_pixels: ?bool = null,
    background_color_rgba: ?u32 = null,

    pub const DataSource = union(enum) {
        transmit: DataSource.Transmit,
        previous: u32,

        pub const Transmit = struct {
            source: Source,

            width: u32,
            height: u32,
            gap_ms: ?u32 = null,
        };
    };
};

pub fn controlAnimation(writer: *std.Io.Writer, opts: ControlAnimationOptions) std.Io.Writer.Error!void {
    try writer.writeAll(INTRODUCER ++ "a=a");
    try writeFlagStruct(writer, opts);
    try writer.writeAll(CLOSE);
}

pub const ControlAnimationOptions = struct {
    id_or_num: IdOrNum,
    
    set_current_frame: ?u32 = null,
    animation_state: ?AnimationState = null,
    loop_state: ?LoopState = null,

    edit_frame: ?u32 = null,
    animation_gap_ms: ?u32 = null,
};

pub fn composeAnimation(writer: *std.Io.Writer, opts: ComposeAnimationOptions) std.Io.Writer.Error!void {
    try writer.writeAll(INTRODUCER ++ "a=c");
    try writeFlagStruct(writer, opts);
    try writer.writeAll(CLOSE);
}

pub const ComposeAnimationOptions = struct {
    id_or_num: IdOrNum,
    
    source_frame: u32,
    source_frame_x: ?u32 = null,
    source_frame_y: ?u32 = null,
    
    dest_frame: u32,
    dest_frame_x: ?u32 = null,
    dest_frame_y: ?u32 = null,
    
    replace_frame_pixels: ?bool = null,
};

fn writeBytes(writer: *std.Io.Writer, raw_bytes: []const u8) error{ WriteFailed, OutOfMemory }!void {
    const multiple_parts_flag = comptime getFlagMapping("multiple_parts").getFlag();
    const encoder = std.base64.standard.Encoder;

    if (raw_bytes.len > MAX_RAW_CHUNK_LEN) {
        var chunker = std.mem.window(u8, raw_bytes, MAX_RAW_CHUNK_LEN, MAX_RAW_CHUNK_LEN);

        try writer.print(",{c}=1" ++ HEADER_CLOSE, .{
            multiple_parts_flag,
        });
        try encoder.encodeWriter(writer, chunker.next().?);

        while (chunker.next()) |chunk| {
            try writer.print(CLOSE ++ INTRODUCER ++ "{c}={d}" ++ HEADER_CLOSE, .{
                multiple_parts_flag,
                if (chunker.index == null) @as(u32, 0) else @as(u32, 1),
            });

            try encoder.encodeWriter(writer, chunk);
        }
    } else {
        try writer.writeAll(HEADER_CLOSE);
        try encoder.encodeWriter(writer, raw_bytes);
    }
}

pub inline fn writeFlagStruct(writer: *std.Io.Writer, flags: anytype) std.Io.Writer.Error!void {
    const FlagsT = @TypeOf(flags);
    if (@typeInfo(FlagsT) != .@"struct" and !@typeInfo(FlagsT).@"struct".is_tuple) @compileError(std.fmt.comptimePrint("expected a struct (T: {s}) as flags set", .{@typeName(FlagsT)}));
    const info = @typeInfo(FlagsT).@"struct";

    inline for (info.fields) |field| {
        try writeFlag(writer, field.name, @field(flags, field.name));
    }
}

pub inline fn writeFlag(writer: *std.Io.Writer, comptime flag: []const u8, value: anytype) std.Io.Writer.Error!void {
    const mapping = comptime getFlagMapping(flag);
    return switch (mapping) {
        .integer => |key| {
            const unwraped_value = if (@typeInfo(@TypeOf(value)) == .optional)
                value orelse return
            else
                value;

            try writer.print(",{c}={d}", .{ key, unwraped_value });
        },
        .bool => |key| {
            const unwraped_value: bool = if (@typeInfo(@TypeOf(value)) == .optional)
                value orelse return
            else
                value;

            try writer.print(",{c}={d}", .{ key, if (unwraped_value) @as(u32, 1) else @as(u32, 0) });
        },
        .custom => |FlagT| {
            const unwraped_value: FlagT = if (@typeInfo(@TypeOf(value)) == .optional)
                value orelse return
            else
                value;

            try unwraped_value.writeTo(writer);
        },
    };
}

pub fn getFlagMapping(comptime flag: []const u8) FlagMapping {
    comptime {
        const mapping = FlagsMap.get(flag) orelse @compileError("not supported flag: " ++ flag);
        return mapping;
    }
}

pub const FlagMapping = union(enum) {
    integer: u8,
    bool: u8,
    custom: type,

    pub fn getFlag(self: FlagMapping) u8 {
        return switch (self) {
            .integer => |flag| flag,
            .bool => |flag| flag,
            .custom => @compileError("cannot get flag of custom mapping"),
        };
    }
};

pub const IdOrNum = union(enum) {
    id: u32,
    num: u32,

    pub inline fn writeTo(self: IdOrNum, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self) {
            .id => |v| return writeFlag(writer, "id", v),
            .num => |v| return writeFlag(writer, "num", v),
        }
    }
};

pub const RelativePlacement = struct {
    parent_image_id: ?u32 = null,
    parent_placement_id: ?u32 = null,
    x_cell_offset: ?i32 = null,
    y_cell_offset: ?i32 = null,

    pub inline fn writeTo(self: *const RelativePlacement, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writeFlag(writer, "parent_image_id", self.parent_image_id);
        try writeFlag(writer, "parent_placement_id", self.parent_placement_id);
        try writeFlag(writer, "x_cell_offset_relative", self.x_cell_offset);
        try writeFlag(writer, "y_cell_offset_relative", self.y_cell_offset);
    }
};

/// What to display from within the image.
pub const DisplayFromImage = struct {
    x: ?u32 = null,
    y: ?u32 = null,
    width: ?u32 = null,
    height: ?u32 = null,

    pub inline fn writeTo(self: *const DisplayFromImage, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writeFlag(writer, "display_at_x", self.x);
        try writeFlag(writer, "display_at_y", self.y);
        try writeFlag(writer, "display_width_from_image", self.width);
        try writeFlag(writer, "display_height_from_image", self.height);
    }
};

pub const AnimationState = enum(u8) {
    stop = 1,
    /// waits for more frames to arrive at the last frame
    loading = 2,
    /// loop back to the first frame after the last one
    normal = 3,

    pub inline fn writeTo(self: *const AnimationState, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writeFlag(writer, "set_animation_state", @intFromEnum(self.*));
    }
};

pub const LoopState = enum(u32) {
    infinite = 0,
    _,
    
    pub inline fn writeTo(self: *const LoopState, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writeFlag(writer, "set_loop_state", @intFromEnum(self.*));
    }
};

pub const FlagsMap = std.StaticStringMap(FlagMapping).initComptime(.{
    .{ "id", FlagMapping{ .integer = 'i' } },
    .{ "num", FlagMapping{ .integer = 'I' } },
    .{ "id_or_num", FlagMapping{ .custom = IdOrNum } },
    .{ "placement_id", FlagMapping{ .integer = 'p' } },

    .{ "width", FlagMapping{ .integer = 's' } },
    .{ "height", FlagMapping{ .integer = 'v' } },

    .{ "parent_image_id", FlagMapping{ .integer = 'P' } },
    .{ "parent_placement_id", FlagMapping{ .integer = 'Q' } },
    .{ "x_cell_offset_relative", FlagMapping{ .integer = 'H' } },
    .{ "y_cell_offset_relative", FlagMapping{ .integer = 'V' } },
    .{ "relative", FlagMapping{ .custom = RelativePlacement } },

    .{ "display_at_x", FlagMapping{ .integer = 'x' } },
    .{ "display_at_y", FlagMapping{ .integer = 'y' } },
    .{ "display_width_from_image", FlagMapping{ .integer = 'w' } },
    .{ "display_height_from_image", FlagMapping{ .integer = 'h' } },
    .{ "display_from_image", FlagMapping{ .custom = DisplayFromImage } },

    .{ "z_index", FlagMapping{ .integer = 'z' } },

    .{ "x_in_cell_offset", FlagMapping{ .integer = 'X' } },
    .{ "y_in_cell_offset", FlagMapping{ .integer = 'Y' } },
    .{ "display_cell_width", FlagMapping{ .integer = 'c' } },
    .{ "display_cell_height", FlagMapping{ .integer = 'r' } },

    .{ "multiple_parts", FlagMapping{ .bool = 'm' } },
    .{ "unicode_placeholder", FlagMapping{ .bool = 'U' } },
    .{ "do_not_move_cursor", FlagMapping{ .bool = 'C' } },

    .{ "previous_frame", FlagMapping{ .integer = 'c' } },
    .{ "edit_frame", FlagMapping{ .integer = 'r' } },
    .{ "animation_gap_ms", FlagMapping{ .integer = 'z' } },
    .{ "set_animation_state", FlagMapping{ .integer = 's' } },
    .{ "animation_state", FlagMapping{ .custom = AnimationState } },
    .{ "set_current_frame", FlagMapping{ .integer = 'c' } },
    .{ "set_loop_state", FlagMapping{ .integer = 'v' } },
    .{ "loop_state", FlagMapping{ .custom = LoopState } },

    .{ "replace_pixels", FlagMapping{ .bool = 'X' } },
    .{ "background_color_rgba", FlagMapping{ .integer = 'Y' } },
    
    .{ "source_frame", FlagMapping{ .integer = 'r' } },
    .{ "source_frame_x", FlagMapping{ .integer = 'x' } },
    .{ "source_frame_y", FlagMapping{ .integer = 'y' } },
    .{ "dest_frame", FlagMapping{ .integer = 'c' } },
    .{ "dest_frame_x", FlagMapping{ .integer = 'X' } },
    .{ "dest_frame_y", FlagMapping{ .integer = 'Y' } },
    .{ "replace_frame_pixels", FlagMapping{ .bool = 'C' } },
});

pub const Response = struct {
    id: u32,
    num: ?u32 = null,

    msg: Message,

    pub fn deinit(self: *Response, allocator: std.mem.Allocator) void {
        switch (self.msg) {
            .ok => {},
            .err => |err| {
                allocator.free(err.type);

                if (err.msg) |msg| {
                    allocator.free(msg);
                }
            },
        }
    }

    pub fn clone(self: *const Response, allocator: std.mem.Allocator) error{OutOfMemory}!Response {
        const result: Message = blk: switch (self.msg) {
            .ok => break :blk .ok,
            .err => |err| {
                break :blk Message{ .err = Message.Err{
                    .type = try allocator.dupe(u8, err.type),
                    .msg = if (err.msg) |msg| try allocator.dupe(u8, msg) else null,
                } };
            },
        };

        return Response{
            .id = self.id,
            .num = self.num,
            .msg = result,
        };
    }

    pub const Message = union(enum) {
        ok,
        err: Err,

        pub const Err = struct {
            type: []const u8,
            msg: ?[]const u8 = null,
        };
    };
};
