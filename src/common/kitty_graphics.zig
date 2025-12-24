// on ice for now

// const std = @import("std");
// const zigimg = @import("zigimg");
// 
// const ctlseqs = @import("ctlseqs.zig");
// 
// pub const Introducer = ctlseqs.APC ++ "G";
// // pub const Introducer = "<ESC>_" ++ "G";
// pub const Close = ctlseqs.ST;
// 
// pub const MAX_CHUNK_LEN = 4096;
// pub const MAX_RAW_CHUNK_LEN = std.base64.standard.Decoder.calcSizeUpperBound(MAX_CHUNK_LEN) catch unreachable;
// 
// const KittyGraphics = @This();
// 
// pub const Error = Source.Error || error{ OutOfMemory, WriteFailed };
// 
// pub const Source = union(enum) {
//     img: zigimg.Image,
//     buf: []const u8,
//     file: std.fs.File,
//     path: []const u8,
//     shared_memory: []const u8,
// 
//     pub const Error = std.fs.File.OpenError || zigimg.Image.ReadError || zigimg.Image.ConvertError;
// 
//     pub fn getImage(self: *const Source, allocator: std.mem.Allocator) Source.Error!zigimg.Image {
//         switch (self.*) {
//             .img => |src_img| {
//                 var img = src_img;
//                 try img.convertNoFree(allocator, .rgba32);
//                 return img;
//             },
//             .buf => |data| {
//                 var img = try zigimg.Image.fromMemory(allocator, data);
//                 errdefer img.deinit(allocator);
// 
//                 try img.convert(allocator, .rgba32);
//                 return img;
//             },
//             .file => |file| {
//                 var buf: [128]u8 = undefined;
//                 var img = try zigimg.Image.fromFile(allocator, file, &buf);
//                 errdefer img.deinit(allocator);
// 
//                 try img.convert(allocator, .rgba32);
//                 return img;
//             },
//             .path => |path| {
//                 var buf: [128]u8 = undefined;
//                 var img = try zigimg.Image.fromFilePath(allocator, path, &buf);
//                 errdefer img.deinit(allocator);
// 
//                 try img.convert(allocator, .rgba32);
//                 return img;
//             },
//             .shared_memory => {
//                 @panic("not implemented");
//             },
//         }
//     }
// };
// 
// pub fn transmitOnly(writer: *std.Io.Writer, allocator: std.mem.Allocator, source: Source, opts: TransmitOnlyOptions) KittyGraphics.Error!void {
//     var img = try source.getImage(allocator);
//     defer img.deinit(allocator);
//     const raw_bytes = img.rawBytes();
// 
//     try writer.print(Introducer ++ "a=t,f=32,t=d,S={d}", .{raw_bytes.len});
// 
//     // if (opts.image) |id_or_num| {
//     //     try writer.writeByte(',');
//     //     try id_or_num.writeTo(writer);
//     // }
//     // if (opts.parent_image_id) |id| {
//     //     std.debug.assert(id > 0);
//     //     try writer.print(",P={d}", .{id});
//     // }
//     // if (opts.placement_id) |id| {
//     //     try writer.print(",p={d}", .{id});
//     // }
//     // if (opts.parent_placement_id) |id| {
//     //     std.debug.assert(id > 0);
//     //     try writer.print(",Q={d}", .{id});
//     // }
//     // if (opts.width) |width| {
//     //     try writer.print(",s={d}", .{width});
//     // }
//     // if (opts.height) |height| {
//     //     try writer.print(",v={d}", .{height});
//     // }
// 
//     try writeOptionFlags(writer, opts);
// 
//     try writeBytes(writer, raw_bytes);
//     try writer.writeAll(Close);
// }
// 
// pub const TransmitOnlyOptions = struct {
//     image: ?IdOrNum = null,
//     parent_image_id: ?u32 = null,
// 
//     placement_id: ?u32 = null,
//     parent_placement_id: ?u32 = null,
// 
//     width: ?u32 = null,
//     height: ?u32 = null,
// };
// 
// pub fn transmitAndDisplay(writer: *std.Io.Writer, allocator: std.mem.Allocator, source: Source, opts: TransmitAndDisplayOptions) KittyGraphics.Error!void {
//     var img = try source.getImage(allocator);
//     defer img.deinit(allocator);
// 
//     try writer.print(Introducer ++ "a=T,f=100,t=d,q=2", .{});
// 
//     // if (opts.image_id) |id| {
//     //     try writer.print(",i={d}", .{id});
//     // }
//     // if (opts.image_num) |num| {
//     //     try writer.print(",I={d}", .{num});
//     // }
//     // if (opts.placement_id) |id| {
//     //     try writer.print(",p={d}", .{id});
//     // }
//     // if (opts.placement_num) |num| {
//     //     try writer.print(",P={d}", .{num});
//     // }
//     // if (opts.width) |width| {
//     //     try writer.print(",s={d}", .{width});
//     // }
//     // if (opts.height) |height| {
//     //     try writer.print(",v={d}", .{height});
//     // }
// 
//     try writeOptionFlags(writer, opts);
// 
//     try writeBytes(writer, allocator, img.rawBytes());
//     try writer.writeAll(Close);
// }
// 
// pub const TransmitAndDisplayOptions = struct {
//     image: ?IdOrNum = null,
//     parent_image_id: ?u32 = null,
// 
//     placement_id: ?u32 = null,
//     parent_placement_id: ?u32 = null,
//     z_index: ?i32 = null,
// 
//     width: ?u32 = null,
//     height: ?u32 = null,
// 
//     column: ?u32 = null,
//     row: ?u32 = null,
//     x_offset: ?u32 = null,
//     y_offset: ?u32 = null,
// 
//     display_cell_width: ?u32 = null,
//     display_cell_height: ?u32 = null,
//     display_width: ?u32 = null,
//     display_height: ?u32 = null,
// 
//     move_cursor: bool = false,
// };
// 
// fn writeBytes(writer: *std.Io.Writer, allocator: std.mem.Allocator, raw_bytes: []const u8) error{ WriteFailed, OutOfMemory }!void {
//     // if (raw_bytes.len > MAX_RAW_CHUNK_LEN) {
//     //     var chunker = std.mem.window(u8, raw_bytes, MAX_RAW_CHUNK_LEN, MAX_RAW_CHUNK_LEN);
//     //
//     //     try writer.writeAll(",m=1;");
//     //     try std.base64.standard.Encoder.encodeWriter(writer, chunker.next().?);
//     //
//     //     while (chunker.next()) |chunk| {
//     //         try writer.print(Close ++
//     //             Introducer ++
//     //             "m={d};", .{
//     //             if (chunker.index == null) @as(u32, 0) else @as(u32, 1),
//     //         });
//     //
//     //         try std.base64.standard.Encoder.encodeWriter(writer, chunk);
//     //     }
//     // } else {
//     //     try writer.writeByte(';');
//     //
//     //     try std.base64.standard.Encoder.encodeWriter(writer, raw_bytes);
//     // }
// 
//     const buf = try allocator.alloc(u8, std.base64.standard.Encoder.calcSize(raw_bytes.len));
//     defer allocator.free(buf);
// 
//     _ = std.base64.standard.Encoder.encode(buf, raw_bytes);
// 
//     if (buf.len > MAX_CHUNK_LEN) {
//         var chunker = std.mem.window(u8, buf, MAX_CHUNK_LEN, MAX_CHUNK_LEN);
// 
//         try writer.writeAll(",m=1;");
//         try writer.writeAll(chunker.next().?);
// 
//         while (chunker.next()) |chunk| {
//             try writer.print(Close ++
//                 Introducer ++
//                 "m={d};", .{
//                 if (chunker.index == null) @as(u32, 0) else @as(u32, 1),
//             });
// 
//             try writer.writeAll(chunk);
//         }
//     } else {
//         try writer.writeByte(';');
//         try writer.writeAll(buf);
//     }
// }
// 
// pub fn erase(writer: *std.Io.Writer, opts: EraseOptions) error{WriteFailed}!void {
//     try writer.writeAll(ctlseqs.KittyGraphics.introducer ++ "a=d,d=");
// 
//     switch (opts) {
//         .all => try writer.writeByte('a'),
//         .id => |ids| {
//             try writer.writeByte('i');
// 
//             try writer.print(",i={d}", .{ids.id});
// 
//             if (ids.placement_id) |p_id| {
//                 try writer.print(",p={d}", .{p_id});
//             }
//         },
//         .newest => |n| {
//             try writer.writeByte('n');
// 
//             try writer.print(",I={d}", .{n.num});
// 
//             if (n.placement_id) |p_id| {
//                 try writer.print(",p={d}", .{p_id});
//             }
//         },
//         .intersect_current_cursor => try writer.writeByte('c'),
//         .all_animation_frames => try writer.writeByte('f'),
//         .intersect_cell => |pos| {
//             try writer.writeByte('p');
// 
//             try writer.print(",x={d},y={d}", .{ pos.x, pos.y });
//         },
//         .intersect_cell_at_z => |pos| {
//             try writer.writeByte('q');
// 
//             try writer.print(",x={d},y={d},z={d}", .{ pos.x, pos.y, pos.z });
//         },
//         .in_range => |range| {
//             try writer.writeByte('r');
// 
//             try writer.print(",x={d}", .{range.min});
// 
//             if (range.max) |max| {
//                 try writer.print(",y={d}", .{max});
//             }
//         },
//         .intersect_column => |column| {
//             try writer.writeByte('x');
// 
//             try writer.print(",x={d}", .{column});
//         },
//         .intersect_row => |row| {
//             try writer.writeByte('y');
// 
//             try writer.print(",y={d}", .{row});
//         },
//         .intersect_z => |z| {
//             try writer.writeByte('z');
// 
//             try writer.print(",z={d}", .{z});
//         },
//     }
// 
//     try writer.writeAll(ctlseqs.KittyGraphics.close);
// }
// 
// pub const EraseOptions = union(enum) {
//     all, // a
//     id: ById, // i
//     newest: ByNumber, // n
//     intersect_current_cursor, // c
//     all_animation_frames, // f
//     intersect_cell: CellPosition, // p
//     intersect_cell_at_z: ZCellPosition, // q
//     in_range: InRange, // r
//     intersect_column: u32, // x
//     intersect_row: u32, // y
//     intersect_z: u32, // z
// 
//     pub const ById = struct {
//         id: u32 = 0,
//         placement_id: ?u32 = null,
//     };
// 
//     pub const ByNumber = struct {
//         num: u32 = 0,
//         placement_id: ?u32 = null,
//     };
// 
//     pub const CellPosition = struct {
//         x: u32 = 0,
//         y: u32 = 0,
//     };
// 
//     pub const ZCellPosition = struct {
//         x: u32 = 0,
//         y: u32 = 0,
//         z: u32 = 0,
//     };
// 
//     pub const InRange = struct {
//         min: u32 = 0,
//         max: ?u32 = null,
//     };
// };
// 
// pub fn writeOptionFlags(writer: *std.Io.Writer, flags: anytype) error{WriteFailed}!void {
//     const FlagsT = @TypeOf(flags);
//     if (@typeInfo(FlagsT) != .@"struct" and !@typeInfo(FlagsT).@"struct".is_tuple) @compileError(std.fmt.comptimePrint("expected a struct (T: {s}) as flags set", .{@typeName(FlagsT)}));
//     const info = @typeInfo(FlagsT).@"struct";
// 
//     inline for (info.fields) |field| {
//         const mapping = comptime FlagsMap.get(field.name) orelse @compileError("not supported key flag: " ++ field.name);
//         map: switch (mapping) {
//             .integer => |key| {
//                 const value = if (@typeInfo(@FieldType(FlagsT, field.name)) == .optional)
//                     @field(flags, field.name) orelse break :map
//                 else
//                     @field(flags, field.name);
// 
//                 try writer.print(",{c}={d}", .{ key, value });
//             },
//             .bool => |key| {
//                 const value: bool = if (@typeInfo(@FieldType(FlagsT, field.name)) == .optional)
//                     @field(flags, field.name) orelse break :map
//                 else
//                     @field(flags, field.name);
// 
//                 try writer.print(",{c}={d}", .{ key, if (value) @as(u32, 1) else @as(u32, 0) });
//             },
//             .custom => |FlagT| {
//                 const value: FlagT = if (@typeInfo(@FieldType(FlagsT, field.name)) == .optional)
//                     @field(flags, field.name) orelse break :map
//                 else
//                     @field(flags, field.name);
// 
//                 try writer.writeByte(',');
//                 try value.writeTo(writer);
//             },
//         }
//     }
// }
// 
// pub const FlagsMapping = union(enum) {
//     integer: u8,
//     bool: u8,
//     custom: type,
// };
// 
// pub const IdOrNum = union(enum) {
//     id: u32,
//     num: u32,
// 
//     pub inline fn writeTo(self: IdOrNum, writer: *std.Io.Writer) error{WriteFailed}!void {
//         const key: u8 = switch (self) {
//             .id => 'i',
//             .num => 'I',
//         };
//         const value = switch (self) {
//             .id => |v| v,
//             .num => |v| v,
//         };
//         return writer.print("{c}={d}", .{ key, value });
//     }
// };
// 
// pub const FlagsMap = std.StaticStringMap(FlagsMapping).initComptime(.{
//     .{ "id", FlagsMapping{ .integer = 'i' } },
//     .{ "num", FlagsMapping{ .integer = 'I' } },
//     .{ "parent_image_id", FlagsMapping{ .integer = 'P' } },
//     .{ "image", FlagsMapping{ .custom = IdOrNum } },
// 
//     .{ "placement_id", FlagsMapping{ .integer = 'p' } },
//     .{ "parent_placement_id", FlagsMapping{ .integer = 'Q' } },
// 
//     .{ "z_index", FlagsMapping{ .integer = 'z' } },
// 
//     .{ "width", FlagsMapping{ .integer = 's' } },
//     .{ "height", FlagsMapping{ .integer = 'v' } },
//     .{ "column", FlagsMapping{ .integer = 'x' } },
//     .{ "row", FlagsMapping{ .integer = 'y' } },
//     .{ "x_offset", FlagsMapping{ .integer = 'X' } },
//     .{ "y_offset", FlagsMapping{ .integer = 'Y' } },
//     .{ "display_cell_width", FlagsMapping{ .integer = 'c' } },
//     .{ "display_cell_height", FlagsMapping{ .integer = 'r' } },
//     .{ "display_width", FlagsMapping{ .integer = 'w' } },
//     .{ "display_height", FlagsMapping{ .integer = 'h' } },
// 
//     .{ "move_cursor", FlagsMapping{ .bool = 'C' } },
// });
