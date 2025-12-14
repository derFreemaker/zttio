const std = @import("std");
const zigwin = @import("zigwin");
const windows = std.os.windows;
const winconsole = zigwin.system.console;

const Key = @import("../key.zig");
const Mouse = @import("../mouse.zig");
const Winsize = @import("../winsize.zig");
const ReadResult = @import("../reader.zig").ReadResult;

const log = std.log.scoped(.ztty);

const WinReader = @This();

stdin: windows.HANDLE,
stdout: windows.HANDLE,

events: [32]winconsole.INPUT_RECORD = undefined,
events_count: usize = 0,
events_pos: usize = 0,

last_mouse_button_press: u16 = 0,

pub fn init(stdin: std.fs.File.Handle, stdout: std.fs.File.Handle) WinReader {
    return WinReader{
        .stdin = stdin,
        .stdout = stdout,
    };
}

pub fn getWindowSize(stdout_handle: std.fs.File.Handle) error{Unexpected}!Winsize {
    // NOTE: Even though the event comes with a size, it may not be accurate. We ask for
    // the size directly when we get this event
    var console_info: winconsole.CONSOLE_SCREEN_BUFFER_INFO = undefined;
    if (winconsole.GetConsoleScreenBufferInfo(stdout_handle, &console_info) == 0) {
        return windows.unexpectedError(windows.kernel32.GetLastError());
    }
    const window_rect = console_info.srWindow;
    const width = window_rect.Right - window_rect.Left;
    const height = window_rect.Bottom - window_rect.Top;

    return Winsize{
        .cols = @intCast(width),
        .rows = @intCast(height),
        .x_pixel = 0,
        .y_pixel = 0,
    };
}

pub fn next(self: *WinReader, event_allocator: std.mem.Allocator) error{ OutOfMemory, ReadFailed }!?ReadResult {
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

                    return ReadResult{ .cp = cp };
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

                        return ReadResult{ .cp = event.uChar.UnicodeChar };
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

                var codepoint: u21 = base_layout;
                var text: ?[]const u8 = null;
                switch (event.uChar.UnicodeChar) {
                    0x00...0x1F => {},
                    else => |cp| {
                        codepoint = cp;
                        const buf = try event_allocator.alloc(u8, std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable);
                        _ = std.unicode.utf8Encode(codepoint, buf) catch unreachable;
                        text = buf;
                    },
                }

                const key = Key{
                    .codepoint = codepoint,
                    .base_layout_codepoint = base_layout,
                    .mods = translateMods(event.dwControlKeyState),
                    .text = text,
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
                    .col = @as(i16, @bitCast(event.dwMousePosition.X)), // Windows reports with 0 index
                    .row = @as(i16, @bitCast(event.dwMousePosition.Y)), // Windows reports with 0 index
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
                    .event = .{ .winsize = getWindowSize(self.stdout) catch return error.ReadFailed },
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

fn peekEvent(self: *WinReader) error{ReadFailed}!?winconsole.INPUT_RECORD {
    if (self.events_pos >= self.events_count) {
        self.readNextEvents() catch |err| switch (err) {
            error.Unexpected => return error.ReadFailed,
        };
        if (self.events_count == 0) {
            return null;
        }
    }

    return self.events[self.events_pos];
}

inline fn tossEvent(self: *WinReader) void {
    if (self.events_pos >= self.events_count) return;
    self.events_pos += 1;
}

inline fn remainingEvents(self: *const WinReader) usize {
    return self.events_count - self.events_pos;
}

fn readNextEvents(self: *WinReader) error{Unexpected}!void {
    self.events_count = 0;
    self.events_pos = 0;

    var numEvents: u32 = 0;
    if (winconsole.GetNumberOfConsoleInputEvents(self.stdin, &numEvents) == 0) {
        return windows.unexpectedError(windows.kernel32.GetLastError());
    }
    if (numEvents == 0) {
        return;
    }
    const events_to_read = @min(numEvents, 32);

    if (winconsole.ReadConsoleInputW(self.stdin, &self.events, events_to_read, &numEvents) == 0) {
        return windows.unexpectedError(windows.kernel32.GetLastError());
    }
    self.events_count = numEvents;
}
