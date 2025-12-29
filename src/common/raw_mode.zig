const std = @import("std");
const builtin = @import("builtin");

const zigwin = @import("zigwin");
const winconsole = zigwin.system.console;
const windows = std.os.windows;

const OrignalState = if (builtin.os.tag == .windows)
    WindowsState
else
    PosixState;

const RawMode = @This();

original_state: ?OrignalState,

pub fn enable(stdin: std.fs.File.Handle, stdout: std.fs.File.Handle) error{ InvalidHandle, Unexpected }!RawMode {
    return RawMode{ .original_state = if (builtin.os.tag == .windows)
        try enableWindows(stdin, stdout)
    else
        try enablePosix(stdin) };
}

pub fn disable(self: *RawMode) void {
    const org_state = self.original_state orelse return;

    if (builtin.os.tag == .windows) {
        disableWindows(org_state);
    } else {
        disablePosix(org_state);
    }
}

fn enableWindows(stdin: std.fs.File.Handle, stdout: std.fs.File.Handle) error{ InvalidHandle, Unexpected }!OrignalState {
    const input_raw_mode: WIN_CONSOLE_MODE_INPUT = .{
        .WINDOW_INPUT = 1, // resize events
        .MOUSE_INPUT = 1,
        .EXTENDED_FLAGS = 1, // allow mouse events
        .PROCESSED_INPUT = 0,
        .LINE_INPUT = 0,
        .ECHO_INPUT = 0,
        .VIRTUAL_TERMINAL_INPUT = 1,
    };

    const output_raw_mode: WIN_CONSOLE_MODE_OUTPUT = .{
        .PROCESSED_OUTPUT = 1,
        .VIRTUAL_TERMINAL_PROCESSING = 1,
    };

    const org_codepage = winconsole.GetConsoleOutputCP();
    const org_input_mode = try getConsoleMode(WIN_CONSOLE_MODE_INPUT, stdin);
    const org_output_mode = try getConsoleMode(WIN_CONSOLE_MODE_OUTPUT, stdout);

    const original_state = OrignalState{
        .stdin = stdin,
        .stdout = stdout,

        .codepage = org_codepage,
        .input_mode = org_input_mode,
        .output_mode = org_output_mode,
    };

    try setConsoleMode(stdin, input_raw_mode);
    try setConsoleMode(stdout, output_raw_mode);
    if (winconsole.SetConsoleOutputCP(utf8_codepage) == 0) {
        return windows.unexpectedError(windows.kernel32.GetLastError());
    }

    return original_state;
}

fn disableWindows(org_state: WindowsState) void {
    _ = winconsole.SetConsoleOutputCP(org_state.codepage);
    setConsoleMode(org_state.stdin, org_state.input_mode) catch {};
    setConsoleMode(org_state.stdout, org_state.output_mode) catch {};
}

/// see: https://learn.microsoft.com/en-us/windows/console/getconsolemode
pub const WIN_CONSOLE_MODE_INPUT = packed struct(u32) {
    PROCESSED_INPUT: u1 = 0,
    LINE_INPUT: u1 = 0,
    ECHO_INPUT: u1 = 0,
    WINDOW_INPUT: u1 = 0,
    MOUSE_INPUT: u1 = 0,
    INSERT_MODE: u1 = 0,
    QUICK_EDIT_MODE: u1 = 0,
    EXTENDED_FLAGS: u1 = 0,
    AUTO_POSITION: u1 = 0,
    VIRTUAL_TERMINAL_INPUT: u1 = 0,
    _: u22 = 0,
};

/// see: https://learn.microsoft.com/en-us/windows/console/getconsolemode
pub const WIN_CONSOLE_MODE_OUTPUT = packed struct(u32) {
    PROCESSED_OUTPUT: u1 = 0,
    WRAP_AT_EOL_OUTPUT: u1 = 0,
    VIRTUAL_TERMINAL_PROCESSING: u1 = 0,
    DISABLE_NEWLINE_AUTO_RETURN: u1 = 0,
    ENABLE_LVB_GRID_WORLDWIDE: u1 = 0,
    _: u27 = 0,
};

pub fn getConsoleMode(comptime T: type, handle: std.os.windows.HANDLE) !T {
    var mode: u32 = undefined;
    if (winconsole.GetConsoleMode(handle, @ptrCast(&mode)) == 0) return switch (windows.kernel32.GetLastError()) {
        .INVALID_HANDLE => error.InvalidHandle,
        else => |e| windows.unexpectedError(e),
    };
    return @bitCast(mode);
}

pub fn setConsoleMode(handle: std.os.windows.HANDLE, mode: anytype) !void {
    if (winconsole.SetConsoleMode(handle, @bitCast(mode)) == 0) return switch (windows.kernel32.GetLastError()) {
        .INVALID_HANDLE => error.InvalidHandle,
        else => |e| windows.unexpectedError(e),
    };
}

fn enablePosix(stdin_fd: std.posix.fd_t) error{ InvalidHandle, Unexpected }!OrignalState {
    const original = std.posix.tcgetattr(stdin_fd) catch |err| switch (err) {
        error.NotATerminal => return error.InvalidHandle,
        else => return error.Unexpected,
    };

    var raw = original;
    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    raw.lflag.ISIG = false;
    raw.lflag.IEXTEN = false;
    raw.iflag.IXON = false;
    raw.iflag.ICRNL = false;
    raw.iflag.BRKINT = false;
    raw.iflag.INPCK = false;
    raw.iflag.ISTRIP = false;
    raw.oflag.OPOST = true;
    raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;
    raw.cc[@intFromEnum(std.posix.V.MIN)] = 0;

    std.posix.tcsetattr(stdin_fd, .FLUSH, raw) catch |err| switch (err) {
        error.NotATerminal => return error.InvalidHandle,
        else => return error.Unexpected,
    };

    return .{ .termios = original };
}

fn disablePosix(state: PosixState) void {
    std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, state.termios) catch |err| @panic(@errorName(err));
}

const utf8_codepage: c_uint = 65001;

const WindowsState = struct {
    stdin: windows.HANDLE,
    stdout: windows.HANDLE,

    codepage: c_uint,
    input_mode: WIN_CONSOLE_MODE_INPUT,
    output_mode: WIN_CONSOLE_MODE_OUTPUT,
};

const PosixState = struct {
    termios: std.posix.termios,
};
