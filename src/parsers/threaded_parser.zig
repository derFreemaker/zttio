const std = @import("std");
const builtin = @import("builtin");

const Winsize = @import("../winsize.zig").Winsize;
const Event = @import("../event.zig").Event;
const Queue = @import("../queue.zig").Queue;

const Parser = @import("../parser.zig");

const QUEUE_LEN = 128;

const ThreadedParser = @This();

allocator: std.mem.Allocator,

child: Parser,

queue: Queue(Event, QUEUE_LEN),

thread: ?std.Thread = null,
should_quit: bool = false,

pub fn init(allocator: std.mem.Allocator, child: Parser) std.mem.Allocator.Error!ThreadedParser {
    var queue = try Queue(Event, QUEUE_LEN).init(allocator);
    errdefer queue.deinit(allocator);

    return ThreadedParser{
        .allocator = allocator,

        .child = child,

        .queue = queue,
    };
}

pub fn deinit(self: *ThreadedParser, event_allocator: std.mem.Allocator) void {
    self.stop();
    self.child.disable();

    const enqueued = self.queue.enqueued();
    for (enqueued.first) |*event| {
        event.deinit(event_allocator);
    }
    for (enqueued.second) |*event| {
        event.deinit(event_allocator);
    }
    self.queue.deinit(self.allocator);
}

pub fn parser(self: *ThreadedParser) Parser {
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
    const self: *ThreadedParser = @ptrCast(@alignCast(self_ptr));

    const got_enabled = try self.child.enable();
    self.start() catch return Parser.EnableError.Failed;

    return got_enabled;
}

fn disable(self_ptr: *anyopaque) void {
    const self: *ThreadedParser = @ptrCast(@alignCast(self_ptr));

    self.stop();
    self.child.disable();
}

fn isEnabled(self_ptr: *anyopaque) bool {
    const self: *ThreadedParser = @ptrCast(@alignCast(self_ptr));

    return self.child.isEnabled();
}

fn getWinsize(self_ptr: *anyopaque) Parser.GetWinsizeError!Winsize {
    const self: *ThreadedParser = @ptrCast(@alignCast(self_ptr));

    return self.child.getWinsize();
}

fn getReader(self_ptr: *anyopaque) *std.Io.Reader {
    const self: *ThreadedParser = @ptrCast(@alignCast(self_ptr));

    return self.child.getReader();
}

fn getWriter(self_ptr: *anyopaque) *std.Io.Writer {
    const self: *ThreadedParser = @ptrCast(@alignCast(self_ptr));

    return self.child.getWriter();
}

pub fn start(self: *ThreadedParser) std.Thread.SpawnError!void {
    if (self.thread != null) return;
    self.thread = try std.Thread.spawn(.{
        .allocator = self.allocator,
    }, runReader, .{self});
}

pub fn stop(self: *ThreadedParser) void {
    const thread = self.thread orelse return;
    self.should_quit = true;
    thread.join();

    self.thread = null;
    self.should_quit = false;
}

fn nextEvent(self_ptr: *anyopaque, should_quit: ?*const bool) Parser.ParseError!?Event {
    const self: *ThreadedParser = @ptrCast(@alignCast(self_ptr));

    if (should_quit) |quit| {
        while (!quit.*) {
            if (self.queue.tryPop()) |event| {
                return event;
            }

            std.Thread.sleep(20 * std.time.ns_per_us);
        }

        return null;
    }

    return self.queue.pop();
}

fn runReader(self: *ThreadedParser) !void {
    while (!self.should_quit) {
        const event = try self.child.nextEvent(&self.should_quit) orelse continue;

        self.queue.push(event);
    }
}
