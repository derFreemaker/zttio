const std = @import("std");
const builtin = @import("builtin");

const Event = @import("event.zig").Event;
const Queue = @import("queue.zig").Queue;

const InternalReader = if (builtin.os.tag == .windows)
    @import("reader/win_reader.zig")
else
    @compileError("not implemented");

const Reader = @This();

event_allocator: std.mem.Allocator,

internal: InternalReader,

thread: ?std.Thread = null,
should_quit: bool = false,

queue: Queue(Event, 512),

pub fn init(allocator: std.mem.Allocator, event_allocator: std.mem.Allocator, stdin: std.fs.File.Handle, stdout: std.fs.File.Handle) error{OutOfMemory}!Reader {
    return Reader{
        .event_allocator = event_allocator,
        
        .internal = InternalReader.init(stdin, stdout),

        .queue = try .init(allocator),
    };
}

pub fn deinit(self: *Reader, allocator: std.mem.Allocator) void {
    self.stop();
    
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

pub fn nextEvent(self: *Reader) Event {
    return self.queue.pop();
}

fn runReader(self: *Reader) !void {
    if (builtin.is_test) return;

    while (!self.should_quit) {
        const event = try self.internal.next(self.event_allocator);
        _ = event;
    }
}

pub const ReadResult = union(enum) {
    event: Event,
    cp: u21,
};
