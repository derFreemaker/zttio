const std = @import("std");
const builtin = @import("builtin");
const uucode = @import("uucode");

const Event = @import("../event.zig").Event;
const Winsize = @import("../winsize.zig").Winsize;
const Queue = @import("../queue.zig");
const ParserImpl = @import("parser.zig");
const Adapter = @import("../adapter.zig");
const ReadResult = Adapter.ReadResult;
const Parser = @import("../parser.zig");

pub const ParseError = Parser.ParseError;

const NormalParser = @This();

allocator: std.mem.Allocator,
event_allocator: std.mem.Allocator,

paste_buf: std.ArrayList(u8),
in_paste: bool = false,

adapter: Adapter,
parser_impl: ParserImpl,

//TODO: use something like a ring buffer if we encounter heavy memory movement
buf: std.ArrayList(u8),
last_cp: u21 = 0,
break_state: uucode.grapheme.BreakState = .default,

pub fn init(allocator: std.mem.Allocator, event_allocator: std.mem.Allocator, adapter: Adapter) NormalParser {
    return NormalParser{
        .allocator = allocator,
        .event_allocator = event_allocator,

        .paste_buf = .empty,

        .adapter = adapter,
        .parser_impl = ParserImpl.init(allocator),

        .buf = .empty,
    };
}

pub fn deinit(self: *NormalParser) void {
    self.adapter.disable();

    self.parser_impl.deinit();

    self.paste_buf.deinit(self.allocator);
    self.buf.deinit(self.allocator);
}

pub fn parser(self: *NormalParser) Parser {
    return Parser{
        .ptr = self,
        .vtable = &Parser.VTable{
            .enable = enable,
            .disable = disable,
            .isEnabled = isEnabled,

            .getWinsize = getWinsize,

            .nextEvent = nextEvent,

            .getReader = getReader,
            .getWriter = getWriter,
        },
    };
}

fn enable(self_ptr: *anyopaque) Parser.EnableError!bool {
    const self: *NormalParser = @ptrCast(@alignCast(self_ptr));

    return self.adapter.enable();
}

fn disable(self_ptr: *anyopaque) void {
    const self: *NormalParser = @ptrCast(@alignCast(self_ptr));

    return self.adapter.disable();
}

fn isEnabled(self_ptr: *anyopaque) bool {
    const self: *NormalParser = @ptrCast(@alignCast(self_ptr));

    return self.adapter.isEnabled();
}

fn getWinsize(self_ptr: *anyopaque) Parser.GetWinsizeError!Winsize {
    const self: *NormalParser = @ptrCast(@alignCast(self_ptr));

    return self.adapter.getWinsize();
}

fn getReader(self_ptr: *anyopaque) *std.Io.Reader {
    const self: *NormalParser = @ptrCast(@alignCast(self_ptr));

    return self.adapter.getReader();
}

fn getWriter(self_ptr: *anyopaque) *std.Io.Writer {
    const self: *NormalParser = @ptrCast(@alignCast(self_ptr));

    return self.adapter.getWriter();
}

fn nextEvent(self_ptr: *anyopaque, should_quit: ?*const bool) ParseError!?Event {
    const self: *NormalParser = @ptrCast(@alignCast(self_ptr));

    const quit: *const bool = should_quit orelse &false;

    while (!quit.*) {
        const may_read_result = try self.adapter.read();
        const read_result = may_read_result orelse {
            if (self.buf.items.len > 0) {
                return try self.parseBuf(.no_remaining) orelse continue;
            }

            self.adapter.waitForData(20);
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
            .codepoint => |cp| {
                return try self.parseBuf(.{ .remaining = cp }) orelse continue;
            },
        }
    }

    return null;
}

fn parseBuf(self: *NormalParser, token_remaining: RemainingToken) ParseError!?Event {
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

    const result = self.parser_impl.parse(self.buf.items) catch return error.ParseFailed;
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

const RemainingToken = union(enum) {
    remaining: u21,
    no_remaining,
};
