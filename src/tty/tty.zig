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

stdin_handle: std.fs.File.Handle,
stdout_handle: std.fs.File.Handle,
raw_mode: RawMode,

arena: std.heap.ArenaAllocator,
debug_allocator: DebugAllocator,
allocator: std.mem.Allocator,
event_allocator: std.mem.Allocator,

stdout_writer_buf: []const u8,
stdout_writer: std.fs.File.Writer,
stdout: *std.Io.Writer,

reader: Reader,

opts: Options,
caps: TerminalCapabilities,

pub fn init(allocator: std.mem.Allocator, event_allocator: std.mem.Allocator, stdin: std.fs.File, stdout: std.fs.File, opts: Options) error{ OutOfMemory, NoTty, UnableToEnterRawMode, UnableToStartReader, UnableToQueryTerminalCapabilities }!*Tty {
    if (!stdin.isTty()) return error.NoTty;
    const raw_mode = RawMode.enable(stdin.handle, stdout.handle) catch return error.UnableToEnterRawMode;

    const ptr = try allocator.create(Tty);
    errdefer allocator.destroy(ptr);

    ptr.stdin_handle = stdin.handle;
    ptr.stdout_handle = stdout.handle;
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
    ptr.stdout = &ptr.stdout_writer.interface;

    ptr.reader = try .init(ptr.allocator, event_allocator, stdin.handle, stdout.handle);
    errdefer ptr.reader.deinit(ptr.allocator);

    ptr.opts = opts;
    ptr.caps = common.TerminalCapabilities.query(stdin, stdout) catch return error.UnableToQueryTerminalCapabilities;

    ptr.reader.start() catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.UnableToStartReader,
    };

    ptr.stdout.writeAll(ctlseqs.Terminal.braketed_paste_set) catch unreachable;
    ptr.stdout.flush() catch unreachable;

    return ptr;
}

pub fn deinit(self: *Tty) void {
    self.reader.deinit(self.allocator);
    self.raw_mode.disable();

    self.stdout.flush() catch {};
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
    return Reader.InternalReader.getWindowSize(self.stdout_handle) catch @panic("unable to get winsize");
}

pub inline fn nextEvent(self: *Tty) Event {
    return self.reader.nextEvent();
}

pub inline fn flush(self: *Tty) !void {
    return self.stdout.flush();
}

pub fn requestClipboard(self: *Tty) error{WriteFailed}!void {
    try self.stdout.writeAll(ctlseqs.Terminal.clipboard_request);
}

pub fn saveScreen(self: *Tty) error{WriteFailed}!void {
    try self.stdout.writeAll(ctlseqs.Screen.save);
}

pub fn restoreScreen(self: *Tty) error{WriteFailed}!void {
    try self.stdout.writeAll(ctlseqs.Screen.restore);
}

pub fn clearScreen(self: *Tty) error{WriteFailed}!void {
    try self.stdout.writeAll(ctlseqs.Erase.screen);
}

pub fn resetScreen(self: *Tty) error{WriteFailed}!void {
    try self.clearScreen();
    try self.moveCursor(.home);
}

pub fn enableAlternativeScreen(self: *Tty) error{WriteFailed}!void {
    try self.stdout.writeAll(ctlseqs.Screen.alternative_enable);
}

pub fn disableAlternativeScreen(self: *Tty) error{WriteFailed}!void {
    try self.stdout.writeAll(ctlseqs.Screen.alternative_disable);
}

pub fn enableAndResetAlternativeScreen(self: *Tty) error{WriteFailed}!void {
    try self.enableAlternativeScreen();
    try self.clearScreen();
    try self.moveCursor(.home);
}

pub fn saveCursorPos(self: *Tty) error{WriteFailed}!void {
    try self.stdout.writeAll(ctlseqs.Cursor.save_position);
}

pub fn restoreCursorPos(self: *Tty) error{WriteFailed}!void {
    try self.stdout.writeAll(ctlseqs.Cursor.restore_position);
}

pub fn setCursorShape(self: *Tty, shape: ctlseqs.Cursor.Shape) error{WriteFailed}!void {
    try ctlseqs.Cursor.setCursorShape(self.stdout, shape);
}

pub fn moveCursor(self: *Tty, move_cursor: MoveCursor) error{WriteFailed}!void {
    const cursor = ctlseqs.Cursor;

    switch (move_cursor) {
        .home => {
            try self.stdout.writeAll(cursor.home);
        },
        .pos => |pos| {
            try cursor.moveTo(self.stdout, pos.row, pos.column);
        },
        .up => |x| {
            try cursor.moveUp(self.stdout, x);
        },
        .down => |x| {
            try cursor.moveDown(self.stdout, x);
        },
        .left => |x| {
            try cursor.moveLeft(self.stdout, x);
        },
        .right => |x| {
            try cursor.moveRight(self.stdout, x);
        },
        .front_up => |x| {
            try cursor.moveFrontUp(self.stdout, x);
        },
        .front_down => |x| {
            try cursor.moveFrontDown(self.stdout, x);
        },
        .column => |x| {
            try cursor.moveToColumn(self.stdout, x);
        },
        .up_scroll_if_needed => {
            try self.stdout.writeAll(cursor.move_up_scroll_if_needed);
        },
    }
}

pub const MoveCursor = union(enum) {
    home,
    pos: Pos,
    up: u16,
    down: u16,
    left: u16,
    right: u16,
    front_up: u16,
    front_down: u16,
    column: u16,
    up_scroll_if_needed,

    pub const Pos = struct {
        row: u16,
        column: u16,
    };
};

pub fn setStyling(self: *Tty, style: common.Styling) error{WriteFailed}!void {
    return self.stdout.print("{f}", .{style});
}

pub const Options = struct {
    kitty_keyboard_flags: common.Key.KittyFlags = .{},
};

test {
    _ = std.testing.refAllDeclsRecursive(@This());
}
