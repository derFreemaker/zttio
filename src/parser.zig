const std = @import("std");

const Event = @import("event.zig").Event;
const Winsize = @import("winsize.zig").Winsize;
const ParserImpl = @import("parsers/parser_impl.zig");
const Adapter = @import("adapter.zig");

pub const EnableError = error{Failed};
pub const GetWinsizeError = error{Failed};
pub const ParseError = ParserImpl.ParseError || Adapter.ReadError || std.mem.Allocator.Error;

const Parser = @This();

pub const VTable = struct {
    /// Can be called arbitrarily.
    /// Returns `true` when it got enabled with this call.
    enable: *const fn (self_ptr: *anyopaque) EnableError!bool,

    /// Can be called arbitrarily.
    disable: *const fn (self_ptr: *anyopaque) void,

    isEnabled: *const fn (self_ptr: *anyopaque) bool,

    getWinsize: *const fn (self_ptr: *anyopaque) GetWinsizeError!Winsize,

    /// If `should_quit` is `null`, the execution can run as long as it needs to find the next event.
    /// If `should_quit` gets set to `true`, the execution should be aborted/stopped as soon as possible.
    nextEvent: *const fn (self_ptr: *anyopaque, should_quit: ?*const bool) ParseError!?Event,

    /// Reader is not expected to function properly if the adapter is enabled.
    getReader: *const fn (self_ptr: *anyopaque) *std.Io.Reader,
    getWriter: *const fn (self_ptr: *anyopaque) *std.Io.Writer,
};

ptr: *anyopaque,
vtable: *const VTable,

/// Can be called arbitrarily.
/// Returns `true` when it got enabled with this call.
pub inline fn enable(self: Parser) EnableError!bool {
    return self.vtable.enable(self.ptr);
}

/// Can be called arbitrarily.
pub inline fn disable(self: Parser) void {
    return self.vtable.disable(self.ptr);
}

pub inline fn isEnabled(self: Parser) bool {
    return self.vtable.isEnabled(self.ptr);
}

pub inline fn getWinsize(self: Parser) GetWinsizeError!Winsize {
    return self.vtable.getWinsize(self.ptr);
}

/// If `should_quit` is `null`, the execution can run as long as it needs to find the next event.
pub inline fn nextEvent(self: Parser, should_quit: ?*const bool) ParseError!?Event {
    return self.vtable.nextEvent(self.ptr, should_quit);
}

/// Reader is not expected to function properly if the adapter is enabled.
pub inline fn getReader(self: Parser) *std.Io.Reader {
    return self.vtable.getReader(self.ptr);
}

pub inline fn getWriter(self: Parser) *std.Io.Writer {
    return self.vtable.getWriter(self.ptr);
}
