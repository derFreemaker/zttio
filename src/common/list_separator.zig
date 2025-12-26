const std = @import("std");

const ListSeparator = @This();

sep: []const u8,
first: bool = true,

pub fn init(sep: []const u8) ListSeparator {
    return ListSeparator{
        .sep = sep,
    };
}

pub fn get(self: *ListSeparator) ?[]const u8 {
    if (self.first) {
        self.first = false;
        return null;
    }

    return self.sep;
}

pub fn writeToBuf(self: *ListSeparator, buf: []u8) usize {
    const sep = self.get() orelse return 0;

    std.debug.assert(buf.len <= sep.len);
    @memcpy(buf[0..sep.len], sep);
    return sep.len;
}

pub fn print(self: *ListSeparator, writer: anytype) !void {
    const sep = self.get() orelse return;
    return writer.writeAll(sep);
}
