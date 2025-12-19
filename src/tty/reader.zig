const std = @import("std");
const builtin = @import("builtin");
const common = @import("common");

const Event = common.Event;
const Queue = common.Queue;
const Parser = @import("parser.zig");

const InternalReader = if (builtin.os.tag == .windows)
    @import("reader/win_reader.zig")
else
    @compileError("not implemented");

const Reader = @This();

allocator: std.mem.Allocator,
event_allocator: std.mem.Allocator,

in_paste: bool = false,
paste_buf: std.ArrayList(u8),

internal: InternalReader,
parser: Parser,

thread: ?std.Thread = null,
should_quit: bool = false,

queue: Queue(Event, 512),

pub fn init(allocator: std.mem.Allocator, event_allocator: std.mem.Allocator, stdin: std.fs.File.Handle, stdout: std.fs.File.Handle) error{OutOfMemory}!Reader {
    return Reader{
        .allocator = allocator,
        .event_allocator = event_allocator,

        .paste_buf = .empty,

        .internal = InternalReader.init(stdin, stdout),
        .parser = .init(allocator),

        .queue = try .init(allocator),
    };
}

pub fn deinit(self: *Reader, allocator: std.mem.Allocator) void {
    self.stop();

    self.parser.deinit();
    self.queue.deinit(allocator);
}

pub fn start(self: *Reader) std.Thread.SpawnError!void {
    if (self.thread != null) return;
    self.thread = try std.Thread.spawn(.{}, runReader, .{self});
}

pub fn stop(self: *Reader) void {
    const thread = self.thread orelse return;

    self.should_quit = true;
    thread.join();

    self.thread = null;
    self.should_quit = false;
}

pub fn postEvent(self: *Reader, event: Event) void {
    return self.queue.push(event);
}

pub fn nextEvent(self: *Reader) Event {
    return self.queue.pop();
}

fn runReader(self: *Reader) !void {
    if (builtin.is_test) return;

    //TODO: use a ring buffer
    const buf: std.ArrayList(u8) = .empty;
    while (!self.should_quit) {
        const may_read_result = try self.internal.next(self.event_allocator);
        const read_result = may_read_result orelse {
            self.parseBuf(buf.items);
            continue;
        };

        switch (read_result) {
            .event => |event| {
                if (!self.parser.consumeInPaste(event)) {
                    self.postEvent(event);
                }
            },
        }
    }
}

fn parseBuf(self: *Reader, buf: []u8) void {
    const result = try self.parser.parse(buf, self.event_allocator);
    switch (result.parse) {
        .none => return,
        .event => |event| {
            self.postEvent(event);
        },
        .skip => {},
        .paste_start => {
            std.debug.assert(!self.in_paste);
            self.in_paste = true;
        },
        .paste_end => unreachable,
    }

    @memmove(buf[0 .. buf.len - result.n], buf[result.n..]);
}

pub const ReadResult = union(enum) {
    event: Event,
    cp: u21,
};
