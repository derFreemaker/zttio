const std = @import("std");
const windows = std.os.windows;

const ntdll = @import("ntdll");

const Adapter = @import("../adapter.zig");
const ReadResult = Adapter.ReadResult;
const Key = @import("../../key.zig");
const Mouse = @import("../../mouse.zig");
const Winsize = @import("../../winsize.zig").Winsize;

const log = std.log.scoped(.zttio_win_adapter);

const INPUT_RECORD_BUF_LEN = 16;

const WinAdapter = @This();

stdin: windows.HANDLE,
stdin_buf: []u8,
stdin_reader: std.Io.File.Reader,

stdout: windows.HANDLE,
stdout_buf: []u8,
stdout_writer: std.Io.File.Writer,

events: [INPUT_RECORD_BUF_LEN]ntdll.CONSOLE.INPUT_RECORD = undefined,
events_count: usize = 0,
events_pos: usize = 0,

utf16_buf: [2]u16 = undefined,
utf16_half: bool = false,

last_mouse_button_press: ntdll.CONSOLE.INPUT_RECORD.MOUSE_EVENT.BUTTON_STATE = .{},

org_state: ?ConsoleMode = null,

pub fn init(io: std.Io, stdin: std.Io.File, stdin_buf: []u8, stdout: std.Io.File, stdout_buf: []u8) error{NoTty}!WinAdapter {
    if (!(stdin.isTty(io) catch false)) return error.NoTty;

    return WinAdapter{
        .stdin = stdin.handle,
        .stdin_buf = stdin_buf,
        .stdin_reader = stdin.readerStreaming(io, stdin_buf),

        .stdout = stdout.handle,
        .stdout_buf = stdout_buf,
        .stdout_writer = stdout.writer(io, stdout_buf),
    };
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

fn getReader(self_ptr: *anyopaque) *std.Io.Reader {
    const self: *WinAdapter = @ptrCast(@alignCast(self_ptr));

    return &self.stdin_reader.interface;
}

fn getWriter(self_ptr: *anyopaque) *std.Io.Writer {
    const self: *WinAdapter = @ptrCast(@alignCast(self_ptr));

    return &self.stdout_writer.interface;
}

fn getWinsize(self_ptr: *anyopaque) Adapter.GetWinsizeError!Winsize {
    const self: *WinAdapter = @ptrCast(@alignCast(self_ptr));

    var screen_buffer_info_msg: ntdll.CONSOLE.GetScreenBufferInfoMsg = .{};
    const screen_buffer_info = &screen_buffer_info_msg.Body;
    {
        var user_io: ntdll.CON_DRV.USER_DEFINED_IO(1, 1) = .{};
        user_io.Buffers[0].is(&screen_buffer_info_msg);
        user_io.Buffers[1].is(screen_buffer_info);

        var iosb: ntdll.IO_STATUS_BLOCK = undefined;
        switch (ntdll.NtDeviceIoControlFile(
            self.stdout,
            null,
            null,
            null,
            &iosb,
            .CONDRV_ISSUE_USER_IO,
            &user_io,
            @sizeOf(@TypeOf(user_io)),
            null,
            0,
        )) {
            .SUCCESS => {},
            else => |status| ntdll.unexpectedStatus(status) catch
                return Adapter.GetWinsizeError.Failed,
        }
    }

    return Winsize{
        .cols = @intCast(screen_buffer_info.Size.X),
        .rows = @intCast(screen_buffer_info.Size.Y),
        .x_pixel = 0,
        .y_pixel = 0,
    };
}

fn read(self_ptr: *anyopaque) Adapter.ReadError!?ReadResult {
    const self: *WinAdapter = @ptrCast(@alignCast(self_ptr));

    while (true) {
        const record = try self.peekEvent() orelse return null;
        self.tossEvent();

        switch (record.EventType) {
            .KEY => {
                const event = record.Event.Key;

                if (self.utf16_half and std.unicode.utf16IsLowSurrogate(event.uChar.Unicode)) {
                    self.utf16_half = false;
                    self.utf16_buf[1] = event.uChar.Unicode;
                    const cp: u21 = std.unicode.utf16DecodeSurrogatePair(&self.utf16_buf) catch unreachable;

                    return ReadResult{ .codepoint = cp };
                }

                const base_layout: u16 = switch (event.wVirtualKeyCode) {
                    0x00 => { // delivered when we get an escape sequence or a unicode codepoint
                        if (std.unicode.utf16IsHighSurrogate(event.uChar.Unicode)) {
                            self.utf16_buf[0] = event.uChar.Unicode;
                            self.utf16_half = true;
                            continue;
                        }

                        if (std.unicode.utf16IsLowSurrogate(event.uChar.Unicode)) {
                            continue;
                        }

                        return ReadResult{ .codepoint = event.uChar.Unicode };
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
                    0x76 => Key.f7,
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
                    self.utf16_buf[0] = base_layout;
                    self.utf16_half = true;
                    continue;
                }

                if (std.unicode.utf16IsLowSurrogate(base_layout)) {
                    continue;
                }

                comptime std.debug.assert(4 <= Key.KeyText.MaxShortLength);
                var text: [4]u8 = std.mem.zeroes([4]u8);

                var codepoint: u21 = base_layout;
                var len: u3 = 0;
                switch (event.uChar.Unicode) {
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

                if (event.bKeyDown.toBool()) {
                    return ReadResult{ .event = .{ .key_press = key } };
                } else {
                    return ReadResult{ .event = .{ .key_release = key } };
                }
            },
            .MOUSE => {
                const event = record.Event.Mouse;

                // save the current state when we are done
                defer self.last_mouse_button_press = event.dwButtonState;

                // see https://learn.microsoft.com/en-us/windows/console/mouse-event-record-str
                const button_xor: ntdll.CONSOLE.INPUT_RECORD.MOUSE_EVENT.BUTTON_STATE =
                    @bitCast(@as(ntdll.DWORD, @bitCast(self.last_mouse_button_press)) ^
                        @as(ntdll.DWORD, @bitCast(event.dwButtonState)));
                var event_type: Mouse.Action = .press;

                const btn: Mouse.Button = switch (@as(u16, @truncate(@as(ntdll.DWORD, @bitCast(button_xor))))) {
                    0x0000 => blk: {
                        if (event.dwEventFlags.WHEELED) {
                            switch (event.dwButtonState.getWheelDirection()) {
                                .FORWARD => break :blk .wheel_up,
                                .BACKWARD => break :blk .wheel_down,
                            }
                        }

                        // If we have no change but one of the buttons is still pressed we have a
                        // drag event. Find out which button is held down
                        if (@as(ntdll.DWORD, @bitCast(event.dwButtonState)) > 0 and event.dwEventFlags.MOVED) {
                            event_type = .drag;
                            if (event.dwButtonState.FROM_LEFT_1ST_BUTTON_PRESSED) {
                                break :blk .left;
                            }
                            if (event.dwButtonState.RIGHTMOST_BUTTON_PRESSED) {
                                break :blk .right;
                            }
                            if (event.dwButtonState.FROM_LEFT_2ND_BUTTON_PRESSED) {
                                break :blk .middle;
                            }
                            if (event.dwButtonState.FROM_LEFT_3RD_BUTTON_PRESSED) {
                                break :blk .button_8;
                            }
                            if (event.dwButtonState.FROM_LEFT_4TH_BUTTON_PRESSED) {
                                break :blk .button_9;
                            }
                        }

                        if (event.dwEventFlags.MOVED) {
                            event_type = .motion;
                        }

                        break :blk .none;
                    },
                    0x0001 => blk: {
                        if (event.dwButtonState.FROM_LEFT_1ST_BUTTON_PRESSED) {
                            event_type = .release;
                        }

                        break :blk .left;
                    },
                    0x0002 => blk: {
                        if (event.dwButtonState.RIGHTMOST_BUTTON_PRESSED) {
                            event_type = .release;
                        }

                        break :blk .right;
                    },
                    0x0004 => blk: {
                        if (event.dwButtonState.FROM_LEFT_2ND_BUTTON_PRESSED) {
                            event_type = .release;
                        }

                        break :blk .middle;
                    },
                    0x0008 => blk: {
                        if (event.dwButtonState.FROM_LEFT_3RD_BUTTON_PRESSED) {
                            event_type = .release;
                        }

                        break :blk .button_8;
                    },
                    0x0010 => blk: {
                        if (event.dwButtonState.FROM_LEFT_4TH_BUTTON_PRESSED) {
                            event_type = .release;
                        }

                        break :blk .button_9;
                    },
                    else => {
                        log.warn("unknown mouse event: {}", .{event});
                        continue;
                    },
                };

                const mods: Mouse.Modifiers = .{
                    .shift = event.dwControlKeyState.SHIFT_PRESSED,
                    .alt = event.dwControlKeyState.LEFT_ALT_PRESSED or event.dwControlKeyState.RIGHT_ALT_PRESSED,
                    .ctrl = event.dwControlKeyState.LEFT_CTRL_PRESSED or event.dwControlKeyState.RIGHT_CTRL_PRESSED,
                };

                const mouse: Mouse = .{
                    .col = @intCast(event.dwMousePosition.X), // Windows reports with 0 index
                    .row = @intCast(event.dwMousePosition.Y), // Windows reports with 0 index
                    .mods = mods,
                    .action = event_type,
                    .button = btn,
                };
                return ReadResult{ .event = .{ .mouse = mouse } };
            },
            .WINDOW_BUFFER_SIZE => {
                // NOTE: Even though the event comes with a size, it may not be accurate.
                // We ask for the size directly when we get this event
                const winsize = getWinsize(self) catch return error.ReadFailed;
                return ReadResult{ .event = .{ .winsize = winsize } };
            },
            .FOCUS => {
                return ReadResult{
                    .event = if (record.Event.Focus.bSetFocus.toBool())
                        .focus_in
                    else
                        .focus_out,
                };
            },
            .MENU => continue,
            else => {
                log.warn("unknown input EventType: {}", .{record.EventType});
                continue;
            },
        }
    }
}

inline fn translateMods(mods: ntdll.CONSOLE.CONTROL_KEY_STATE) Key.Modifiers {
    return .{
        .shift = mods.SHIFT_PRESSED,
        .alt = mods.LEFT_ALT_PRESSED or mods.RIGHT_ALT_PRESSED,
        .ctrl = mods.LEFT_CTRL_PRESSED or mods.RIGHT_CTRL_PRESSED,
        .caps_lock = mods.CAPSLOCK_ON,
        .num_lock = mods.NUMLOCK_ON,
    };
}

fn peekEvent(self: *WinAdapter) error{ReadFailed}!?ntdll.CONSOLE.INPUT_RECORD {
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

fn readNextEvents(self: *WinAdapter) ntdll.UnexpectedError!bool {
    self.events_count = 0;
    self.events_pos = 0;

    var read_console_input_msg: ntdll.CONSOLE.GetConsoleInputMsg = .{ .Body = .{
        .NumRecords = 0,
        .Flags = .{
            .READ_NOWAIT = true,
        },
        .Unicode = .FALSE,
    } };
    {
        var user_io: ntdll.CON_DRV.USER_DEFINED_IO(1, 2) = .{};
        user_io.Buffers[0].is(&read_console_input_msg);
        user_io.Buffers[1].is(&read_console_input_msg.Body);
        user_io.Buffers[2].is(&self.events);

        var iosb: ntdll.IO_STATUS_BLOCK = undefined;
        switch (ntdll.NtDeviceIoControlFile(
            self.stdin,
            null,
            null,
            null,
            &iosb,
            .CONDRV_ISSUE_USER_IO,
            &user_io,
            @sizeOf(@TypeOf(user_io)),
            null,
            0,
        )) {
            .SUCCESS => {},
            else => |status| {
                const foo = status;
                return ntdll.unexpectedStatus(foo);
            },
        }
    }
    self.events_count = read_console_input_msg.Body.NumRecords;

    return self.events_count != 0;
}

fn waitForStdinData(self_ptr: *anyopaque, milliseconds: u16) void {
    if (milliseconds == 0) {
        return;
    }

    const self: *WinAdapter = @ptrCast(@alignCast(self_ptr));

    const timeout: i64 = -@as(i64, milliseconds) * 10_000;
    _ = ntdll.NtWaitForSingleObject(self.stdin, .FALSE, &timeout);
}

const ConsoleMode = struct {
    codepage: ntdll.CONSOLE.CODEPAGE,
    input_mode: ntdll.CONSOLE.MODE.INPUT,
    output_mode: ntdll.CONSOLE.MODE.OUTPUT,
};

fn enable(self_ptr: *anyopaque) Adapter.EnableError!bool {
    const self: *WinAdapter = @ptrCast(@alignCast(self_ptr));
    if (self.org_state != null) return false;

    const org_codepage = getConsoleCP(self.stdin) catch
        return Adapter.EnableError.Failed;
    const org_input_mode = (getConsoleMode(self.stdin) catch
        return Adapter.EnableError.Failed).Input;
    const org_output_mode = (getConsoleMode(self.stdout) catch
        return Adapter.EnableError.Failed).Output;

    const org_state = ConsoleMode{
        .codepage = org_codepage,
        .input_mode = org_input_mode,
        .output_mode = org_output_mode,
    };

    const input_raw_mode: ntdll.CONSOLE.MODE.INPUT = .{
        .ENABLE_WINDOW_INPUT = true, // resize events
        .ENABLE_MOUSE_INPUT = true,
        .ENABLE_EXTENDED_FLAGS = true, // allow mouse events
        .ENABLE_PROCESSED_INPUT = false,
        .ENABLE_LINE_INPUT = false,
        .ENABLE_ECHO_INPUT = false,
        .ENABLE_VIRTUAL_TERMINAL_INPUT = true,
    };

    const output_raw_mode: ntdll.CONSOLE.MODE.OUTPUT = .{
        .ENABLE_PROCESSED_OUTPUT = true,
        .ENABLE_VIRTUAL_TERMINAL_PROCESSING = true,
    };

    setConsoleMode(self.stdin, .{ .Input = input_raw_mode }) catch
        return Adapter.EnableError.Failed;
    setConsoleMode(self.stdout, .{ .Output = output_raw_mode }) catch
        return Adapter.EnableError.Failed;
    setConsoleCP(self.stdin, .@"utf-8") catch
        return Adapter.EnableError.Failed;

    self.org_state = org_state;
    return true;
}

fn disable(self_ptr: *anyopaque) void {
    const self: *WinAdapter = @ptrCast(@alignCast(self_ptr));
    const org_state = self.org_state orelse return;
    defer self.org_state = null;

    setConsoleCP(self.stdin, org_state.codepage) catch {};
    setConsoleMode(self.stdin, .{ .Input = org_state.input_mode }) catch {};
    setConsoleMode(self.stdout, .{ .Output = org_state.output_mode }) catch {};
}

fn isEnabled(self_ptr: *anyopaque) bool {
    const self: *WinAdapter = @ptrCast(@alignCast(self_ptr));
    return self.org_state != null;
}

fn getConsoleCP(handle: ntdll.HANDLE) error{Unexpected}!ntdll.CONSOLE.CODEPAGE {
    var get_console_cp: ntdll.CONSOLE.GetCPMsg = .{ .Body = .{
        .CodePage = undefined,
        .Output = .FALSE,
    } };

    {
        var user_io: ntdll.CON_DRV.USER_DEFINED_IO(1, 1) = .{};
        user_io.Buffers[0].is(&get_console_cp);
        user_io.Buffers[1].is(&get_console_cp.Body);

        var iosb: ntdll.IO_STATUS_BLOCK = undefined;
        switch (ntdll.NtDeviceIoControlFile(
            handle,
            null,
            null,
            null,
            &iosb,
            .CONDRV_ISSUE_USER_IO,
            &user_io,
            @sizeOf(@TypeOf(user_io)),
            null,
            0,
        )) {
            .SUCCESS => {},
            else => |status| {
                return ntdll.unexpectedStatus(status);
            },
        }
    }

    return get_console_cp.Body.CodePage;
}

fn setConsoleCP(handle: ntdll.HANDLE, codepage: ntdll.CONSOLE.CODEPAGE) error{Unexpected}!void {
    var set_console_output_cp: ntdll.CONSOLE.SetCPMsg = .{ .Body = .{
        .CodePage = codepage,
        .Output = .FALSE,
    } };

    {
        var user_io: ntdll.CON_DRV.USER_DEFINED_IO(1, 0) = .{};
        user_io.Buffers[0].is(&set_console_output_cp);

        var iosb: ntdll.IO_STATUS_BLOCK = undefined;
        switch (ntdll.NtDeviceIoControlFile(
            handle,
            null,
            null,
            null,
            &iosb,
            .CONDRV_ISSUE_USER_IO,
            &user_io,
            @sizeOf(@TypeOf(user_io)),
            null,
            0,
        )) {
            .SUCCESS => {},
            else => |status| {
                return ntdll.unexpectedStatus(status);
            },
        }
    }
}

fn getConsoleMode(handle: ntdll.HANDLE) error{ InvalidHandle, Unexpected }!ntdll.CONSOLE.MODE {
    var get_console_mode_msg: ntdll.CONSOLE.GetModeMsg = .{};
    {
        var user_io: ntdll.CON_DRV.USER_DEFINED_IO(1, 1) = .{};
        user_io.Buffers[0].is(&get_console_mode_msg);
        user_io.Buffers[1].is(&get_console_mode_msg.Body);

        var iosb: ntdll.IO_STATUS_BLOCK = undefined;
        switch (ntdll.NtDeviceIoControlFile(
            handle,
            null,
            null,
            null,
            &iosb,
            .CONDRV_ISSUE_USER_IO,
            &user_io,
            @sizeOf(@TypeOf(user_io)),
            null,
            0,
        )) {
            .SUCCESS => {},
            .INVALID_HANDLE => return error.InvalidHandle,
            else => |status| {
                return ntdll.unexpectedStatus(status);
            },
        }
    }

    return get_console_mode_msg.Body.Mode;
}

fn setConsoleMode(handle: ntdll.HANDLE, mode: ntdll.CONSOLE.MODE) error{ InvalidHandle, Unexpected }!void {
    var set_console_mode_msg: ntdll.CONSOLE.SetModeMsg = .{ .Body = .{
        .Mode = mode,
    } };
    {
        var user_io: ntdll.CON_DRV.USER_DEFINED_IO(1, 1) = .{};
        user_io.Buffers[0].is(&set_console_mode_msg);
        user_io.Buffers[1].is(&set_console_mode_msg.Body);

        var iosb: ntdll.IO_STATUS_BLOCK = undefined;
        switch (ntdll.NtDeviceIoControlFile(
            handle,
            null,
            null,
            null,
            &iosb,
            .CONDRV_ISSUE_USER_IO,
            &user_io,
            @sizeOf(@TypeOf(user_io)),
            null,
            0,
        )) {
            .SUCCESS => {},
            .INVALID_HANDLE => return error.InvalidHandle,
            else => |status| {
                return ntdll.unexpectedStatus(status);
            },
        }
    }
}
