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

pub fn Reader(comptime config: ReaderConfig) type {
    if (config.run_own_thread and builtin.single_threaded) {
        @compileError("can not run reader in own thread on a single threaded target");
    }

    return struct {
        pub const ParseError = error{ Quit, ReadFailed } || Parser.ParseError || std.mem.Allocator.Error;

        const Self = @This();

        allocator: std.mem.Allocator,
        event_allocator: std.mem.Allocator,

        paste_buf: std.ArrayList(u8),
        in_paste: bool = false,

        internal: InternalReader,
        parser: Parser,

        thread: if (config.run_own_thread) ?std.Thread else void = if (config.run_own_thread) null else void{},
        should_quit: if (config.run_own_thread) bool else void = if (config.run_own_thread) false else void{},

        //TODO: use something like a ring buffer if we encounter heavy memory movement
        buf: std.ArrayList(u8),
        last_cp: u21 = 0,
        break_state: uucode.grapheme.BreakState = .default,

        queue: Queue(Event, 128),

        winsize: *std.atomic.Value(Winsize),

        pub fn init(allocator: std.mem.Allocator, event_allocator: std.mem.Allocator, stdin: std.fs.File.Handle, stdout: std.fs.File.Handle, winsize: *std.atomic.Value(Winsize)) error{OutOfMemory}!Self {
            return Self{
                .allocator = allocator,
                .event_allocator = event_allocator,

                .paste_buf = .empty,

                .internal = InternalReader.init(stdin, stdout),
                .parser = Parser.init(allocator),

                .buf = .empty,

                .queue = try .init(allocator),

                .winsize = winsize,
            };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
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

        /// Has no effect when config option `run_own_thread` is `false`.
        pub fn start(self: *Self) std.Thread.SpawnError!void {
            if (comptime !config.run_own_thread) return;

            if (self.thread != null) return;
            self.thread = try std.Thread.spawn(.{
                .allocator = self.allocator,
                .stack_size = 8 * 1024,
            }, runReader, .{self});
        }

        /// Has no effect when config option `run_own_thread` is `false`.
        pub fn stop(self: *Self) void {
            if (comptime !config.run_own_thread) return;

            const thread = self.thread orelse return;
            self.should_quit = true;
            thread.join();

            self.thread = null;
            self.should_quit = false;
        }

        pub fn postEvent(self: *Self, event: Event) void {
            if (event == .winsize) {
                self.winsize.store(event.winsize, .release);
            }

            return self.queue.push(event);
        }

        pub fn nextEvent(self: *Self) ParseError!Event {
            if (comptime !config.run_own_thread) {
                if (self.queue.tryPop()) |event| {
                    return event;
                }

                const event = try self.parseNext(null);
                if (event == .winsize) {
                    self.winsize.store(event.winsize, .release);
                }

                return event;
            } else {
                return self.queue.pop();
            }
        }

        fn runReader(self: *Self) !void {
            if (comptime !config.run_own_thread) @panic("reader is in single thread mode");
            if (comptime builtin.is_test) return;

            while (!self.should_quit) {
                const event = self.parseNext(&self.should_quit) catch |err| switch (err) {
                    error.Quit => return,
                    else => |e| return e,
                };
                self.postEvent(event);
            }
        }

        fn parseNext(self: *Self, should_quit: ?*const bool) ParseError!Event {
            const quit_flag = should_quit orelse &false;

            while (!quit_flag.*) {
                const may_read_result = try self.internal.next();
                const read_result = may_read_result orelse {
                    if (self.buf.items.len > 0) {
                        return try self.parseBuf(.no_remaining) orelse continue;
                    }

                    self.internal.waitForStdinData();
                    continue;
                };

                switch (read_result) {
                    .event => |event| {
                        switch (event) {
                            .key_press => |key| {
                                if (key.text != .empty) {
                                    const text = key.text.get();
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
                            },
                            else => {},
                        }

                        return event;
                    },
                    .cp => |cp| {
                        return try self.parseBuf(.{ .remaining = cp }) orelse continue;
                    },
                }
            }

            return error.Quit;
        }

        fn parseBuf(self: *Self, token_remaining: RemainingToken) ParseError!?Event {
            if (token_remaining == .remaining) {
                const cp = token_remaining.remaining;
                var buf: [4]u8 = undefined;
                const n = std.unicode.utf8Encode(cp, &buf) catch {
                    std.log.scoped(.zttio).warn("unable to encode codepoint '{d}' in utf-8", .{cp});
                    // warn and ignore codepoints we cannot encode in utf-8
                    return null;
                };
                try self.buf.appendSlice(self.allocator, buf[0..n]);

                // check if we have a break and if not there is more data to check
                if (self.last_cp == 0 or
                    !uucode.grapheme.isBreak(self.last_cp, token_remaining.remaining, &self.break_state))
                {
                    self.last_cp = token_remaining.remaining;
                    return null;
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
                return null;
            }

            switch (result.parse) {
                .none, .skip => {
                    return null;
                },

                .event => |event| {
                    return try event.clone(self.event_allocator);
                },

                .paste_start => {
                    std.debug.assert(!self.in_paste);
                    self.in_paste = true;
                    return null;
                },
                .paste_end => {
                    std.debug.assert(self.in_paste);
                    self.in_paste = false;
                    defer self.paste_buf.clearRetainingCapacity();

                    const event = Event{
                        .paste = try self.event_allocator.dupe(u8, self.paste_buf.items),
                    };
                    return event;
                },
            }
        }
    };
}

const RemainingToken = union(enum) {
    remaining: u21,
    no_remaining,
};

pub const ReadResult = union(enum) {
    event: Event,
    cp: u21,
};

pub const ReaderConfig = struct {
    /// If `true` runs the reader in its own thread.
    /// Has to be started with `start`
    /// and can be stopped with `stop` if needed.
    /// Will always be stopped on `deinit`.
    run_own_thread: bool = false,
};
