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

    std.debug.assert(buf.len >= sep.len);
    @memcpy(buf[0..sep.len], sep);
    return sep.len;
}

pub fn print(self: *ListSeparator, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    const sep = self.get() orelse return;
    return writer.writeAll(sep);
}

test get {
    var sep = ListSeparator.init("asd");

    try std.testing.expectEqual(null, sep.get());
    try std.testing.expectEqualStrings("asd", sep.get().?);
    try std.testing.expectEqualStrings("asd", sep.get().?);
    try std.testing.expectEqualStrings("asd", sep.get().?);
}

test writeToBuf {
    var sep = ListSeparator.init(";");

    var buf: [4]u8 = undefined;
    @memset(buf[0..4], ' ');
    _ = sep.writeToBuf(buf[0..]);
    _ = sep.writeToBuf(buf[1..]);
    _ = sep.writeToBuf(buf[2..]);

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
