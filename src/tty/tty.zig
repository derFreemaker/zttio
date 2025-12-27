const std = @import("std");
const builin = @import("builtin");
const common = @import("common");

const ctlseqs = common.cltseqs;
const RawMode = common.RawMode;
const Event = common.Event;
const Winsize = common.Winsize;
const TerminalCapabilities = common.TerminalCapabilities;
const Reader = @import("reader.zig");

const DebugAllocator = if (builin.mode == .Debug)
    std.heap.DebugAllocator(.{
        .never_unmap = true,
        .retain_metadata = true,
        .stack_trace_frames = 50,
    })
else
    void;

const Tty = @This();

stdin: std.fs.File,
stdout: std.fs.File,
raw_mode: RawMode,

arena: std.heap.ArenaAllocator,
debug_allocator: DebugAllocator,
allocator: std.mem.Allocator,
event_allocator: std.mem.Allocator,

stdout_writer_buf: []const u8,
stdout_writer: std.fs.File.Writer,

reader: Reader,

opts: Options,
caps: TerminalCapabilities,

pub fn init(allocator: std.mem.Allocator, event_allocator: std.mem.Allocator, stdin: std.fs.File, stdout: std.fs.File, opts: Options) error{ OutOfMemory, NoTty, UnableToEnterRawMode, UnableToStartReader, UnableToQueryTerminalCapabilities }!*Tty {
    if (!stdin.isTty()) return error.NoTty;
    const raw_mode = RawMode.enable(stdin.handle, stdout.handle) catch return error.UnableToEnterRawMode;

    const ptr = try allocator.create(Tty);
    errdefer allocator.destroy(ptr);

    ptr.stdin = stdin;
    ptr.stdout = stdout;
    ptr.raw_mode = raw_mode;

    ptr.arena = .init(allocator);
    if (builin.mode == .Debug) {
        ptr.debug_allocator = DebugAllocator{
            .backing_allocator = ptr.arena.allocator(),
        };
    }
    errdefer if (builin.mode == .Debug) {
        if (ptr.debug_allocator.deinit() == .leak)
            @panic("leaks found in tty");
    };
    ptr.allocator = if (builin.mode == .Debug)
        ptr.debug_allocator.allocator()
    else
        ptr.arena.allocator();
    ptr.event_allocator = event_allocator;

    ptr.stdout_writer_buf = try ptr.allocator.alloc(u8, 32 * 1024);
    errdefer ptr.allocator.free(ptr.stdout_writer_buf);
    ptr.stdout_writer = stdout.writer(@constCast(ptr.stdout_writer_buf));

    ptr.reader = try .init(ptr.allocator, event_allocator, stdin.handle, stdout.handle);
    errdefer ptr.reader.deinit(ptr.allocator);

    ptr.opts = opts;
    ptr.caps = common.TerminalCapabilities.query(stdin, stdout) catch return error.UnableToQueryTerminalCapabilities;

    ptr.reader.start() catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.UnableToStartReader,
    };

    ptr.stdoutWriter().writeAll(ctlseqs.Terminal.braketed_paste_set) catch unreachable;
    ptr.stdoutWriter().flush() catch unreachable;

    return ptr;
}

pub fn deinit(self: *Tty) void {
    self.reader.deinit(self.allocator);
    self.raw_mode.disable();

    self.stdoutWriter().flush() catch {};
    self.allocator.free(self.stdout_writer_buf);

    if (builin.mode == .Debug) {
        if (self.debug_allocator.deinit() == .leak)
            @panic("leaks found in tty");
    }

    const allocator = self.arena.child_allocator;
    self.arena.deinit();
    allocator.destroy(self);
}

pub inline fn strWidth(self: *Tty, str: []const u8) usize {
    return common.gwidth.gwidth(str, self.caps.unicode_width_method);
}

pub fn getWinsize(self: *const Tty) Winsize {
    return Reader.InternalReader.getWindowSize(self.stdout.handle) catch unreachable;
}

pub inline fn nextEvent(self: *Tty) Event {
    return self.reader.nextEvent();
}

pub inline fn stdoutWriter(self: *Tty) *std.Io.Writer {
    return &self.stdout_writer.interface;
}

pub inline fn flush(self: *Tty) error{WriteFailed}!void {
    return self.stdoutWriter().flush();
}

pub fn requestClipboard(self: *Tty) error{WriteFailed}!void {
    const writer = self.stdoutWriter();

    try writer.writeAll(ctlseqs.Terminal.clipboard_request);
}

pub fn saveScreen(self: *Tty) error{WriteFailed}!void {
    const writer = self.stdoutWriter();

    try writer.writeAll(ctlseqs.Screen.save);
}

pub fn restoreScreen(self: *Tty) error{WriteFailed}!void {
    const writer = self.stdoutWriter();

    try writer.writeAll(ctlseqs.Screen.restore);
}

pub fn clearScreen(self: *Tty) error{WriteFailed}!void {
    const writer = self.stdoutWriter();

    try writer.writeAll(ctlseqs.Erase.screen);
}

pub fn resetScreen(self: *Tty) error{WriteFailed}!void {
    try self.clearScreen();
    try self.moveCursor(.home);
}

pub fn enableAlternativeScreen(self: *Tty) error{WriteFailed}!void {
    const writer = self.stdoutWriter();

    try writer.writeAll(ctlseqs.Screen.alternative_enable);
}

pub fn disableAlternativeScreen(self: *Tty) error{WriteFailed}!void {
    const writer = self.stdoutWriter();

    try writer.writeAll(ctlseqs.Screen.alternative_disable);
}

pub fn enableAndResetAlternativeScreen(self: *Tty) error{WriteFailed}!void {
    try self.enableAlternativeScreen();
    try self.clearScreen();
    try self.moveCursor(.home);
}

pub fn saveCursorPos(self: *Tty) error{WriteFailed}!void {
    const writer = self.stdoutWriter();

    try writer.writeAll(ctlseqs.Cursor.save_position);
}

pub fn restoreCursorPos(self: *Tty) error{WriteFailed}!void {
    const writer = self.stdoutWriter();

    try writer.writeAll(ctlseqs.Cursor.restore_position);
}

pub fn setCursorShape(self: *Tty, shape: ctlseqs.Cursor.Shape) error{WriteFailed}!void {
    const writer = self.stdoutWriter();

    try ctlseqs.Cursor.setCursorShape(writer, shape);
}

pub fn moveCursor(self: *Tty, move_cursor: MoveCursor) error{WriteFailed}!void {
    const writer = self.stdoutWriter();

    switch (move_cursor) {
        .home => {
            try writer.writeAll(ctlseqs.Cursor.home);
        },
    }
}

pub const MoveCursor = union(enum) {
    home,
};

pub fn setStyling(self: *Tty, style: common.Styling) error{WriteFailed}!void {
    return self.stdoutWriter().print("{f}", .{style});
}

pub const Options = struct {
    kitty_keyboard_flags: common.Key.KittyFlags = .{},
};

test {
    _ = std.testing.refAllDeclsRecursive(@This());
}
