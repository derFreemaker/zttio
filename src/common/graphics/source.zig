const std = @import("std");
const zigimg = @import("zigimg");

pub const Source = union(enum) {
    img: zigimg.Image,
    buf: []const u8,
    file: std.fs.File,
    path: []const u8,

    pub const Error = std.fs.File.OpenError || zigimg.Image.ReadError || zigimg.Image.ConvertError;

    pub fn getImage(self: *const Source, allocator: std.mem.Allocator) Source.Error!zigimg.Image {
        const img: zigimg.Image = blk: switch (self.*) {
            .img => |src_img| {
                var img = src_img;
                try img.convertNoFree(allocator, .rgba32);
                break :blk img;
            },
            .buf => |data| {
                var img = try zigimg.Image.fromMemory(allocator, data);
                errdefer img.deinit(allocator);

                try img.convert(allocator, .rgba32);
                break :blk img;
            },
            .file => |file| {
                var buf: [128]u8 = undefined;
                var img = try zigimg.Image.fromFile(allocator, file, &buf);
                errdefer img.deinit(allocator);

                try img.convert(allocator, .rgba32);
                break :blk img;
            },
            .path => |path| {
                var buf: [128]u8 = undefined;
                var img = try zigimg.Image.fromFilePath(allocator, path, &buf);
                errdefer img.deinit(allocator);

                try img.convert(allocator, .rgba32);
                break :blk img;
            },
        };

        return img;
    }
};
