const std = @import("std");
const builtin = @import("builtin");
const uucode = @import("uucode");
const common = @import("common");

const Event = common.Event;
const Winsize = common.Winsize;
const Queue = common.Queue;
const Parser = @import("parser.zig");

pub const InternalReader = if (builtin.os.tag == .windows)
    @import("reader/win_reader.zig")
else
    @import("reader/posix_reader.zig");

const Reader = @This();

allocator: std.mem.Allocator,
event_allocator: std.mem.Allocator,

paste_buf: std.ArrayList(u8),
in_paste: bool = false,

internal: InternalReader,
parser: Parser,

thread: ?std.Thread = null,
should_quit: bool = false,

//TODO: use something like a ring buffer if we encounter heavy memory moving
buf: std.ArrayList(u8),
last_cp: u21 = 0,
break_state: uucode.grapheme.BreakState = .default,

queue: Queue(Event, 512),

winsize: *std.atomic.Value(Winsize),

pub fn init(allocator: std.mem.Allocator, event_allocator: std.mem.Allocator, stdin: std.fs.File.Handle, stdout: std.fs.File.Handle, winsize: *std.atomic.Value(Winsize)) error{OutOfMemory}!Reader {
    return Reader{
        .allocator = allocator,
        .event_allocator = event_allocator,

        .paste_buf = .empty,

        .internal = InternalReader.init(stdin, stdout),
        .parser = .init(allocator),

        .buf = .empty,

        .queue = try .init(allocator),

        .winsize = winsize,
    };
}

pub fn deinit(self: *Reader, allocator: std.mem.Allocator) void {
    self.stop();

    self.parser.deinit();

    self.paste_buf.deinit(self.allocator);
    self.buf.deinit(self.allocator);

    const enqueued = self.queue.enqueued();
    for (enqueued.first) |*event| {
        event.deinit(self.event_allocator);
    }
    for (enqueued.second) |*event| {
        event.deinit(self.event_allocator);
    }
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
    if (event == .winsize) {
        self.winsize.store(event.winsize, .release);
    }

    return self.queue.push(event);
}

pub fn nextEvent(self: *Reader) Event {
    return self.queue.pop();
}

fn runReader(self: *Reader) !void {
    if (builtin.is_test) return;

    while (!self.should_quit) {
        const may_read_result = try self.internal.next(self.event_allocator);
        const read_result = may_read_result orelse {
            if (self.buf.items.len > 0) {
                try self.parseBuf(.no_remaining);
            }

            self.internal.waitForStdinData();
            continue;
        };

        switch (read_result) {
            .event => |event| {
                switch (event) {
                    .key_press => |key| {
                        if (key.text) |text| {
                            if (self.in_paste) {
                                try self.paste_buf.appendSlice(self.allocator, text);
                            } else {
                                try self.buf.appendSlice(self.allocator, text);
                            }
                            continue;
                        }
                    },
                    .key_release => {
                        // This causes an issue if a key is held before entering paste
                        // and somehow released inside the paste.
                        // Should be very unlikly though.
                        if (self.in_paste) {
                            continue;
                        }

                        self.postEvent(event);
                        continue;
                    },
                    else => {
                        self.postEvent(event);
                        continue;
                    },
                }
            },
            .cp => |cp| {
                try self.parseBuf(.{ .remaining = cp });
            },
        }
    }
}

fn parseBuf(self: *Reader, token_remaining: RemainingToken) !void {
    if (token_remaining == .remaining) {
        const cp = token_remaining.remaining;
        var buf: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(cp, &buf) catch unreachable;
        try self.buf.appendSlice(self.allocator, buf[0..n]);

        // check if we have a break and if not there is more data to check
        if (self.last_cp == 0 or
            !uucode.grapheme.isBreak(self.last_cp, token_remaining.remaining, &self.break_state))
        {
            self.last_cp = token_remaining.remaining;
            return;
        }
    }

    const result = try self.parser.parse(self.buf.items);
    defer {
        if (result.parse != .none and result.n > 0) {
            @memmove(self.buf.items[0 .. self.buf.items.len - result.n], self.buf.items[result.n..]);
            self.buf.items.len -= result.n;

            if (self.buf.items.len == 0) {
                self.last_cp = 0;
                self.break_state = .default;
            }
        }
    }

    if (self.in_paste and result.parse != .paste_end) {
        try self.paste_buf.appendSlice(self.allocator, self.buf.items[0..result.n]);
        return;
    }

    switch (result.parse) {
        .none, .skip => {},
        .event => |event| {
            self.postEvent(try event.clone(self.event_allocator));
        },

        .paste_start => {
            std.debug.assert(!self.in_paste);
            self.in_paste = true;
        },
        .paste_end => {
            std.debug.assert(self.in_paste);
            self.in_paste = false;
            defer self.paste_buf.clearRetainingCapacity();

            const event = Event{
                .paste = try self.event_allocator.dupe(u8, self.paste_buf.items),
            };
            self.postEvent(event);
        },
    }
}

const RemainingToken = union(enum) {
    remaining: u21,
    no_remaining,
};

pub const ReadResult = union(enum) {
    event: Event,
    cp: u21,
};
