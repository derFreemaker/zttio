const std = @import("std");
const win32 = @import("win32");
const windows = std.os.windows;
const winconsole = win32.system.console;

const Key = @import("../key.zig");
const Mouse = @import("../mouse.zig");
const Winsize = @import("../winsize.zig").Winsize;
const Adapter = @import("../adapter.zig");
const ReadResult = Adapter.ReadResult;

const log = std.log.scoped(.zttio_win_adapter);

const INPUT_RECORD_BUF_LEN = 16;

const WinAdapter = @This();

stdin: windows.HANDLE,
stdin_buf: []u8,
stdin_reader: std.Io.File.Reader,

stdout: windows.HANDLE,
stdout_buf: []u8,
stdout_writer: std.Io.File.Writer,

events: [INPUT_RECORD_BUF_LEN]winconsole.INPUT_RECORD = undefined,
events_count: usize = 0,
events_pos: usize = 0,

last_mouse_button_press: u16 = 0,

org_state: ?ConsoleMode = null,

pub fn init(allocator: std.mem.Allocator, io: std.Io, stdin: std.Io.File, stdout: std.Io.File) error{ OutOfMemory, NoTty }!WinAdapter {
    if (!(stdin.isTty(io) catch false)) return error.NoTty;

    const stdin_buf = try allocator.alloc(u8, 1024);
    errdefer allocator.free(stdin_buf);

    const stdout_buf = try allocator.alloc(u8, 16 * 1024);
    errdefer allocator.free(stdout_buf);

    return WinAdapter{
        .stdin = stdin.handle,
        .stdin_buf = stdin_buf,
        .stdin_reader = stdin.readerStreaming(io, stdin_buf),

        .stdout = stdout.handle,
        .stdout_buf = stdout_buf,
        .stdout_writer = stdout.writer(io, stdout_buf),
    };
}

pub fn deinit(self: *WinAdapter, allocator: std.mem.Allocator) void {
    allocator.free(self.stdin_buf);
    allocator.free(self.stdout_buf);
}

pub fn adapter(self: *WinAdapter) Adapter {
    return Adapter{
        .ptr = self,
        .vtable = &Adapter.VTable{
            .enable = enable,
            .disable = disable,
            .isEnabled = isEnabled,

            .getWinsize = getWinsize,

            .waitForData = waitForStdinData,
            .read = read,

            .getReader = getReader,
            .getWriter = getWriter,
        },
    };
}

fn getWinsize(self_ptr: *anyopaque) Adapter.GetWinsizeError!Winsize {
    const self: *WinAdapter = @ptrCast(@alignCast(self_ptr));

    var console_info: winconsole.CONSOLE_SCREEN_BUFFER_INFO = undefined;
    if (winconsole.GetConsoleScreenBufferInfo(self.stdout, &console_info) == 0) {
        windows.unexpectedError(windows.GetLastError()) catch {};
        return Adapter.GetWinsizeError.Failed;
    }

    return Winsize{
        .cols = @intCast(console_info.dwSize.X),
        .rows = @intCast(console_info.dwSize.Y),
        .x_pixel = 0,
        .y_pixel = 0,
    };
}

fn read(self_ptr: *anyopaque) Adapter.ReadError!?ReadResult {
    const self: *WinAdapter = @ptrCast(@alignCast(self_ptr));

    var utf16_buf: [2]u16 = undefined;
    var utf16_half: bool = false;

    while (true) {
        const record = try self.peekEvent() orelse return null;
        self.tossEvent();

        switch (record.EventType) {
            winconsole.KEY_EVENT => {
                const event = record.Event.KeyEvent;

                if (utf16_half and std.unicode.utf16IsLowSurrogate(event.uChar.UnicodeChar)) {
                    utf16_half = false;
                    utf16_buf[1] = event.uChar.UnicodeChar;
                    const cp: u21 = std.unicode.utf16DecodeSurrogatePair(&utf16_buf) catch unreachable;

                    return ReadResult{ .codepoint = cp };
                }

                const base_layout: u16 = switch (event.wVirtualKeyCode) {
                    0x00 => { // delivered when we get an escape sequence or a unicode codepoint
                        if (std.unicode.utf16IsHighSurrogate(event.uChar.UnicodeChar)) {
                            utf16_buf[0] = event.uChar.UnicodeChar;
                            utf16_half = true;
                            continue;
                        }

                        if (std.unicode.utf16IsLowSurrogate(event.uChar.UnicodeChar)) {
                            continue;
                        }

                        return ReadResult{ .codepoint = event.uChar.UnicodeChar };
                    },
                    0x08 => Key.backspace,
                    0x09 => Key.tab,
                    0x0D => Key.enter,
                    0x13 => Key.pause,
                    0x14 => Key.caps_lock,
                    0x1B => Key.escape,
                    0x20 => Key.space,
                    0x21 => Key.page_up,
                    0x22 => Key.page_down,
                    0x23 => Key.end,
                    0x24 => Key.home,
                    0x25 => Key.left,
                    0x26 => Key.up,
                    0x27 => Key.right,
                    0x28 => Key.down,
                    0x2c => Key.print_screen,
                    0x2d => Key.insert,
                    0x2e => Key.delete,
                    0x30...0x39 => |k| k,
                    0x41...0x5a => |k| k + 0x20, // translate to lowercase
                    0x5b => Key.left_meta,
                    0x5c => Key.right_meta,
                    0x60 => Key.kp_0,
                    0x61 => Key.kp_1,
                    0x62 => Key.kp_2,
                    0x63 => Key.kp_3,
                    0x64 => Key.kp_4,
                    0x65 => Key.kp_5,
                    0x66 => Key.kp_6,
                    0x67 => Key.kp_7,
                    0x68 => Key.kp_8,
                    0x69 => Key.kp_9,
                    0x6a => Key.kp_multiply,
                    0x6b => Key.kp_add,
                    0x6c => Key.kp_separator,
                    0x6d => Key.kp_subtract,
                    0x6e => Key.kp_decimal,
                    0x6f => Key.kp_divide,
                    0x70 => Key.f1,
                    0x71 => Key.f2,
                    0x72 => Key.f3,
                    0x73 => Key.f4,
                    0x74 => Key.f5,
                    0x75 => Key.f6,
                    0x76 => Key.f8,
                    0x77 => Key.f8,
                    0x78 => Key.f9,
                    0x79 => Key.f10,
                    0x7a => Key.f11,
                    0x7b => Key.f12,
                    0x7c => Key.f13,
                    0x7d => Key.f14,
                    0x7e => Key.f15,
                    0x7f => Key.f16,
                    0x80 => Key.f17,
                    0x81 => Key.f18,
                    0x82 => Key.f19,
                    0x83 => Key.f20,
                    0x84 => Key.f21,
                    0x85 => Key.f22,
                    0x86 => Key.f23,
                    0x87 => Key.f24,
                    0x90 => Key.num_lock,
                    0x91 => Key.scroll_lock,
                    0xa0 => Key.left_shift,
                    0x10 => Key.left_shift,
                    0xa1 => Key.right_shift,
                    0xa2 => Key.left_control,
                    0x11 => Key.left_control,
                    0xa3 => Key.right_control,
                    0xa4 => Key.left_alt,
                    0x12 => Key.left_alt,
                    0xa5 => Key.right_alt,
                    0xad => Key.mute_volume,
                    0xae => Key.lower_volume,
                    0xaf => Key.raise_volume,
                    0xb0 => Key.media_track_next,
                    0xb1 => Key.media_track_previous,
                    0xb2 => Key.media_stop,
                    0xb3 => Key.media_play_pause,
                    0xba => ';',
                    0xbb => '+',
                    0xbc => ',',
                    0xbd => '-',
                    0xbe => '.',
                    0xbf => '/',
                    0xc0 => '`',
                    0xdb => '[',
                    0xdc => '\\',
                    0xdf => '\\',
                    0xe2 => '\\',
                    0xdd => ']',
                    0xde => '\'',
                    else => {
                        log.warn("unknown input wVirtualKeyCode: 0x{x}", .{event.wVirtualKeyCode});
                        continue;
                    },
                };

                if (std.unicode.utf16IsHighSurrogate(base_layout)) {
                    utf16_buf[0] = base_layout;
                    utf16_half = true;
                    continue;
                }

                if (std.unicode.utf16IsLowSurrogate(base_layout)) {
                    continue;
                }

                comptime std.debug.assert(4 <= Key.KeyText.MaxShortLength);
                var text: [4]u8 = std.mem.zeroes([4]u8);

                var codepoint: u21 = base_layout;
                var len: u3 = 0;
                switch (event.uChar.UnicodeChar) {
                    0x00...0x1F => {},
                    else => |cp| {
                        codepoint = cp;
                        len = std.unicode.utf8Encode(codepoint, &text) catch unreachable;
                    },
                }

                const key = Key{
                    .codepoint = .from(codepoint),
                    .base_layout_codepoint = .from(base_layout),
                    .mods = translateMods(event.dwControlKeyState),
                    .text = .from(text[0..len]),
                };

                switch (event.bKeyDown) {
                    0 => return ReadResult{ .event = .{ .key_release = key } },
                    else => return ReadResult{ .event = .{ .key_press = key } },
                }
            },
            winconsole.MOUSE_EVENT => {
                // see https://learn.microsoft.com/en-us/windows/console/mouse-event-record-str
                const event = record.Event.MouseEvent;

                // High word of dwButtonState represents mouse wheel.
                // Positive is wheel_up, negative is wheel_down
                // Low word represents button state
                const mouse_wheel_direction: i16 = blk: {
                    const wheelu32: u32 = event.dwButtonState >> 16;
                    const wheelu16: u16 = @truncate(wheelu32);
                    break :blk @bitCast(wheelu16);
                };

                const buttons: u16 = @truncate(event.dwButtonState);
                // save the current state when we are done
                defer self.last_mouse_button_press = buttons;
                const button_xor = self.last_mouse_button_press ^ buttons;

                var event_type: Mouse.Type = .press;
                const btn: Mouse.Button = switch (button_xor) {
                    0x0000 => blk: {
                        // Check wheel event
                        if (event.dwEventFlags & 0x0004 > 0) {
                            if (mouse_wheel_direction > 0)
                                break :blk .wheel_up
                            else
                                break :blk .wheel_down;
                        }

                        // If we have no change but one of the buttons is still pressed we have a
                        // drag event. Find out which button is held down
                        if (buttons > 0 and event.dwEventFlags & 0x0001 > 0) {
                            event_type = .drag;
                            if (buttons & 0x0001 > 0) break :blk .left;
                            if (buttons & 0x0002 > 0) break :blk .right;
                            if (buttons & 0x0004 > 0) break :blk .middle;
                            if (buttons & 0x0008 > 0) break :blk .button_8;
                            if (buttons & 0x0010 > 0) break :blk .button_9;
                        }

                        if (event.dwEventFlags & 0x0001 > 0) event_type = .motion;
                        break :blk .none;
                    },
                    0x0001 => blk: {
                        if (buttons & 0x0001 == 0) event_type = .release;
                        break :blk .left;
                    },
                    0x0002 => blk: {
                        if (buttons & 0x0002 == 0) event_type = .release;
                        break :blk .right;
                    },
                    0x0004 => blk: {
                        if (buttons & 0x0004 == 0) event_type = .release;
                        break :blk .middle;
                    },
                    0x0008 => blk: {
                        if (buttons & 0x0008 == 0) event_type = .release;
                        break :blk .button_8;
                    },
                    0x0010 => blk: {
                        if (buttons & 0x0010 == 0) event_type = .release;
                        break :blk .button_9;
                    },
                    else => {
                        log.warn("unknown mouse event: {}", .{event});
                        continue;
                    },
                };

                const shift: u32 = 0x0010;
                const alt: u32 = 0x0001 | 0x0002;
                const ctrl: u32 = 0x0004 | 0x0008;
                const mods: Mouse.Modifiers = .{
                    .shift = event.dwControlKeyState & shift > 0,
                    .alt = event.dwControlKeyState & alt > 0,
                    .ctrl = event.dwControlKeyState & ctrl > 0,
                };

                const mouse: Mouse = .{
                    .col = @intCast(event.dwMousePosition.X), // Windows reports with 0 index
                    .row = @intCast(event.dwMousePosition.Y), // Windows reports with 0 index
                    .mods = mods,
                    .type = event_type,
                    .button = btn,
                };
                return ReadResult{ .event = .{ .mouse = mouse } };
            },
            winconsole.WINDOW_BUFFER_SIZE_EVENT => {
                // NOTE: Even though the event comes with a size, it may not be accurate.
                // We ask for the size directly when we get this event
                return ReadResult{
                    .event = .{ .winsize = getWinsize(self) catch return error.ReadFailed },
                };
            },
            winconsole.FOCUS_EVENT => {
                switch (record.Event.FocusEvent.bSetFocus) {
                    0 => return ReadResult{ .event = .focus_out },
                    else => return ReadResult{ .event = .focus_in },
                }
            },
            else => {
                log.warn("unknown input EventType: {}", .{record.EventType});
                continue;
            },
        }
    }
}

inline fn translateMods(mods: u32) Key.Modifiers {
    return .{
        .shift = mods & winconsole.SHIFT_PRESSED > 0,
        .alt = mods & (winconsole.LEFT_ALT_PRESSED | winconsole.RIGHT_ALT_PRESSED) > 0,
        .ctrl = mods & (winconsole.LEFT_CTRL_PRESSED | winconsole.RIGHT_CTRL_PRESSED) > 0,
        .caps_lock = mods & winconsole.CAPSLOCK_ON > 0,
        .num_lock = mods & winconsole.NUMLOCK_ON > 0,
    };
}

fn peekEvent(self: *WinAdapter) error{ReadFailed}!?winconsole.INPUT_RECORD {
    if (self.events_pos >= self.events_count) {
        if (!(self.readNextEvents() catch |err| switch (err) {
            error.Unexpected => return error.ReadFailed,
        })) {
            return null;
        }
    }

    return self.events[self.events_pos];
}

fn tossEvent(self: *WinAdapter) void {
    if (self.events_pos >= self.events_count) return;
    self.events_pos += 1;
}

inline fn remainingEvents(self: *const WinAdapter) usize {
    return self.events_count - self.events_pos;
}

fn readNextEvents(self: *WinAdapter) error{Unexpected}!bool {
    self.events_count = 0;
    self.events_pos = 0;

    var numEvents: u32 = 0;
    if (winconsole.GetNumberOfConsoleInputEvents(self.stdin, &numEvents) == 0) {
        return windows.unexpectedError(windows.GetLastError());
    }
    if (numEvents == 0) {
        return false;
    }
    const events_to_read = @min(numEvents, INPUT_RECORD_BUF_LEN);

    if (winconsole.ReadConsoleInputW(self.stdin, &self.events, events_to_read, &numEvents) == 0) {
        return windows.unexpectedError(windows.GetLastError());
    }
    self.events_count = numEvents;

    return true;
}

fn waitForStdinData(self_ptr: *anyopaque, milliseconds: u16) void {
    const self: *WinAdapter = @ptrCast(@alignCast(self_ptr));

    const timeout: i64 = milliseconds;
    // @Check
    _ = windows.ntdll.NtWaitForSingleObject(self.stdin, .TRUE, &timeout);
}

const ConsoleMode = struct {
    pub const utf8_codepage: c_uint = 65001;

    codepage: c_uint,
    input_mode: WIN_CONSOLE_MODE_INPUT,
    output_mode: WIN_CONSOLE_MODE_OUTPUT,
};

fn enable(self_ptr: *anyopaque) Adapter.EnableError!bool {
    const self: *WinAdapter = @ptrCast(@alignCast(self_ptr));
    if (self.org_state != null) return false;

    const org_codepage = winconsole.GetConsoleOutputCP();
    const org_input_mode = getConsoleMode(WIN_CONSOLE_MODE_INPUT, self.stdin) catch return Adapter.EnableError.Failed;
    const org_output_mode = getConsoleMode(WIN_CONSOLE_MODE_OUTPUT, self.stdout) catch return Adapter.EnableError.Failed;

    const org_state = ConsoleMode{
        .codepage = org_codepage,
        .input_mode = org_input_mode,
        .output_mode = org_output_mode,
    };

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

    setConsoleMode(self.stdin, input_raw_mode) catch return Adapter.EnableError.Failed;
    setConsoleMode(self.stdout, output_raw_mode) catch return Adapter.EnableError.Failed;
    if (winconsole.SetConsoleOutputCP(ConsoleMode.utf8_codepage) == 0) {
        windows.unexpectedError(windows.GetLastError()) catch {};
        return Adapter.EnableError.Failed;
    }

    self.org_state = org_state;
    return true;
}

fn disable(self_ptr: *anyopaque) void {
    const self: *WinAdapter = @ptrCast(@alignCast(self_ptr));
    const org_state = self.org_state orelse return;
    defer self.org_state = null;

    _ = winconsole.SetConsoleOutputCP(org_state.codepage);
    setConsoleMode(self.stdin, org_state.input_mode) catch {};
    setConsoleMode(self.stdout, org_state.output_mode) catch {};
}

fn isEnabled(self_ptr: *anyopaque) bool {
    const self: *WinAdapter = @ptrCast(@alignCast(self_ptr));

    return self.org_state != null;
}

/// see: https://learn.microsoft.com/en-us/windows/console/getconsolemode
const WIN_CONSOLE_MODE_INPUT = packed struct(u32) {
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
const WIN_CONSOLE_MODE_OUTPUT = packed struct(u32) {
    PROCESSED_OUTPUT: u1 = 0,
    WRAP_AT_EOL_OUTPUT: u1 = 0,
    VIRTUAL_TERMINAL_PROCESSING: u1 = 0,
    DISABLE_NEWLINE_AUTO_RETURN: u1 = 0,
    ENABLE_LVB_GRID_WORLDWIDE: u1 = 0,
    _: u27 = 0,
};

fn getConsoleMode(comptime T: type, handle: std.os.windows.HANDLE) !T {
    var mode: u32 = undefined;
    if (winconsole.GetConsoleMode(handle, @ptrCast(&mode)) == 0) return switch (windows.GetLastError()) {
        .INVALID_HANDLE => error.InvalidHandle,
        else => |e| windows.unexpectedError(e),
    };
    return @bitCast(mode);
}

fn setConsoleMode(handle: std.os.windows.HANDLE, mode: anytype) !void {
    if (winconsole.SetConsoleMode(handle, @bitCast(mode)) == 0) return switch (windows.GetLastError()) {
        .INVALID_HANDLE => error.InvalidHandle,
        else => |e| windows.unexpectedError(e),
    };
}

fn getReader(self_ptr: *anyopaque) *std.Io.Reader {
    const self: *WinAdapter = @ptrCast(@alignCast(self_ptr));

    return &self.stdin_reader.interface;
}

fn getWriter(self_ptr: *anyopaque) *std.Io.Writer {
    const self: *WinAdapter = @ptrCast(@alignCast(self_ptr));

    return &self.stdout_writer.interface;
}
