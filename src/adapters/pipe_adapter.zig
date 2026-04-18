const std = @import("std");

const Adapter = @import("../adapter.zig");
const Winsize = @import("../winsize.zig");

const PipeAdapter = @This();

reader: *std.Io.Reader,
writer: *std.Io.Writer,

winsize: Winsize,

pub fn init(reader: *std.Io.Reader, writer: *std.Io.Writer, winsize: Winsize) PipeAdapter {
    return PipeAdapter{
        .reader = reader,
        .writer = writer,

        .winsize = winsize,
    };
}

pub fn adapter(self: *PipeAdapter) Adapter {
    return Adapter{ .ptr = self, .vtable = &Adapter.VTable{
        .enable = Adapter.noEnable,
        .disable = Adapter.noDisable,
        .isEnabled = Adapter.neverEnabled,

        .getWinsize = getWinsize,
        .waitForData = Adapter.noWaitForData,

        .read = read,

        .getReader = getReader,
        .getWriter = getWriter,
    } };
}

fn getWinsize(self_ptr: *anyopaque) Adapter.GetWinsizeError!Winsize {
    const self: *PipeAdapter = @ptrCast(@alignCast(self_ptr));
    return self.winsize;
}

fn read(self_ptr: *anyopaque) Adapter.ReadError!?Adapter.ReadResult {
    const self: *PipeAdapter = @ptrCast(@alignCast(self_ptr));

    var buf: [4]u8 = undefined;
    buf[0] = self.reader.takeByte() catch Adapter.ReadError.ReadFailed;

    const n = std.unicode.utf8ByteSequenceLength(buf[0]) catch Adapter.ReadError.ReadFailed;
    if (n > 1) {
        self.reader.readSliceAll(buf[1 .. n - 1]) catch Adapter.ReadError.ReadFailed;
    }

    const codepoint = std.unicode.utf8Decode(buf[0..n]) catch Adapter.ReadError.ReadFailed;
    return Adapter.ReadResult{
        .codepoint = codepoint,
    };
}

fn getReader(self_ptr: *anyopaque) *std.Io.Reader {
    const self: *PipeAdapter = @ptrCast(@alignCast(self_ptr));
    return self.reader;
}

fn getWriter(self_ptr: *anyopaque) *std.Io.Writer {
    const self: *PipeAdapter = @ptrCast(@alignCast(self_ptr));
    return self.writer;
}
