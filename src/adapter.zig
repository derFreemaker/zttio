const std = @import("std");

const Event = @import("event.zig").Event;
const Winsize = @import("winsize.zig").Winsize;

const Adapter = @This();

pub const EnableError = error{Failed};
pub const GetWinsizeError = error{Failed};
pub const ReadError = error{ReadFailed};

pub const VTable = struct {
    /// Can be called arbitrarily.
    /// Returns `true` when it got enabled with this call.
    enable: *const fn (self_ptr: *anyopaque) EnableError!bool,

    /// Can be called arbitrarily.
    disable: *const fn (self_ptr: *anyopaque) void,

    isEnabled: *const fn (self_ptr: *anyopaque) bool,

    getWinsize: *const fn (self_ptr: *anyopaque) GetWinsizeError!Winsize,

    /// Returning `null` indicates that there is no more data.
    read: *const fn (self_ptr: *anyopaque) ReadError!?ReadResult,
    waitForData: *const fn (self_ptr: *anyopaque, milliseconds: u16) void,

    /// Reader is not expected to function properly if the adapter is enabled.
    getReader: *const fn (self_ptr: *anyopaque) *std.Io.Reader,
    getWriter: *const fn (self_ptr: *anyopaque) *std.Io.Writer,
};

ptr: *anyopaque,
vtable: *const VTable,

/// Can be called arbitrarily.
/// Returns `true` when it got enabled with this call.
pub inline fn enable(self: Adapter) EnableError!bool {
    return self.vtable.enable(self.ptr);
}

/// Can be called arbitrarily.
pub inline fn disable(self: Adapter) void {
    return self.vtable.disable(self.ptr);
}

pub inline fn isEnabled(self: Adapter) bool {
    return self.vtable.isEnabled(self.ptr);
}

pub inline fn getWinsize(self: Adapter) GetWinsizeError!Winsize {
    return self.vtable.getWinsize(self.ptr);
}

pub inline fn waitForData(self: Adapter, milliseconds: u16) void {
    self.vtable.waitForData(self.ptr, milliseconds);
}

pub const ReadResult = union(enum) {
    event: Event,
    codepoint: u21,
};

pub inline fn read(self: Adapter) ReadError!?ReadResult {
    return self.vtable.read(self.ptr);
}

/// Reader is not expected to function properly if the adapter is enabled.
pub inline fn getReader(self: Adapter) *std.Io.Reader {
    return self.vtable.getReader(self.ptr);
}

pub inline fn getWriter(self: Adapter) *std.Io.Writer {
    return self.vtable.getWriter(self.ptr);
}

pub fn noEnable(self_ptr: *anyopaque) EnableError!bool {
    _ = self_ptr;
    return false;
}

pub fn noDisable(self_ptr: *anyopaque) void {
    _ = self_ptr;
}

pub fn neverEnabled(self_ptr: *anyopaque) bool {
    _ = self_ptr;
    return false;
}

pub fn fixedWinsize(comptime winsize: ?Winsize) fn (self_ptr: *anyopaque) GetWinsizeError!Winsize {
    return struct {
        pub fn func(self_ptr: *anyopaque) GetWinsizeError!Winsize {
            _ = self_ptr;
            return comptime winsize orelse Winsize{
                .cols = 0,
                .rows = 0,
                .x_pixel = 0,
                .y_pixel = 0,
            };
        }
    }.func;
}

pub fn noWaitForData(self_ptr: *anyopaque, milliseconds: u16) bool {
    _ = self_ptr;
    _ = milliseconds;
    return false;
}
