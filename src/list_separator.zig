const std = @import("std");

const ListSeparator = @This();

sep: []const u8,
first: bool = true,

pub fn init(sep: []const u8) ListSeparator {
    return ListSeparator{
        .sep = sep,
    };
}

pub inline fn get(self: *ListSeparator) []const u8 {
    return if (self.first) {
        self.first = false;
        return &.{};
    } else self.sep;
}

pub fn writeToBuf(self: *ListSeparator, buf: []u8) error{NoSpaceLeft}!usize {
    const sep = self.get();
    if (buf.len < sep.len) {
        return error.NoSpaceLeft;
    }

    @memcpy(buf[0..sep.len], sep);
    return sep.len;
}

pub fn print(self: *ListSeparator, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    return writer.writeAll(self.get());
}

test get {
    var sep = ListSeparator.init("asd");

    try std.testing.expectEqualStrings("", sep.get());
    try std.testing.expectEqualStrings("asd", sep.get());
    try std.testing.expectEqualStrings("asd", sep.get());
    try std.testing.expectEqualStrings("asd", sep.get());
}

test writeToBuf {
    var sep = ListSeparator.init(";");

    var buf: [4]u8 = undefined;
    @memset(buf[0..4], ' ');
    _ = try sep.writeToBuf(buf[0..]);
    _ = try sep.writeToBuf(buf[1..]);
    _ = try sep.writeToBuf(buf[2..]);

    try std.testing.expectEqualStrings(" ;; ", buf[0..4]);
}

test print {
    var alloc_writer = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer alloc_writer.deinit();
    const writer = &alloc_writer.writer;

    var sep = ListSeparator.init("👍");

    try sep.print(writer);
    try sep.print(writer);
    try sep.print(writer);

    try std.testing.expectEqualStrings("👍👍", alloc_writer.written());
}
