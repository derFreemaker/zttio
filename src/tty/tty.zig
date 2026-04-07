const std = @import("std");
const builtin = @import("builtin");
const common = @import("common");

const ctlseqs = common.ctlseqs;
const KittyGraphics = ctlseqs.KittyGraphics;
const RawMode = common.RawMode;
const Event = common.Event;
const Winsize = common.Winsize;
const TerminalCapabilities = common.TerminalCapabilities;
const SigwinchHandling = @import("sigwinch_handling.zig");

const log = std.log.scoped(.zttio);

pub const HelperError = std.Io.Writer.Error || error{CapabilityNotSupported};

pub fn Tty(comptime config: TtyConfig) type {
    const Reader = @import("reader.zig")
        .Reader(.{ .run_own_thread = config.run_own_thread });
    const InternalReader = @import("reader.zig").InternalReader;

    return struct {
        const Self = @This();

        stdin_handle: std.fs.File.Handle,
        stdout_handle: std.fs.File.Handle,
        raw_mode: RawMode,

        allocator: std.mem.Allocator,
        event_allocator: std.mem.Allocator,

        stdout_writer_buf: []const u8,
        stdout_writer: std.fs.File.Writer,
        stdout: *std.Io.Writer,

        reader: Reader,
        winsize: std.atomic.Value(Winsize),

        opts: Options,
        caps: TerminalCapabilities,

        pub fn init(allocator: std.mem.Allocator, event_allocator: std.mem.Allocator, stdin: std.fs.File, stdout: std.fs.File, opts: CreateOptions) error{ OutOfMemory, WriteFailed, NoTty, UnableToEnterRawMode, UnableToQueryTerminalCapabilities, UnableToGetWinsize, UnableToStartReader }!*Self {
            if (!stdin.isTty()) return error.NoTty;
            const raw_mode = RawMode.enable(stdin.handle, stdout.handle) catch return error.UnableToEnterRawMode;

            const ptr = try allocator.create(Self);
            errdefer allocator.destroy(ptr);

            ptr.stdin_handle = stdin.handle;
            ptr.stdout_handle = stdout.handle;
            ptr.raw_mode = raw_mode;

            ptr.allocator = allocator;
            ptr.event_allocator = event_allocator;

            ptr.stdout_writer_buf = try ptr.allocator.alloc(u8, 32 * 1024);
            errdefer ptr.allocator.free(ptr.stdout_writer_buf);
            ptr.stdout_writer = stdout.writer(@constCast(ptr.stdout_writer_buf));
            ptr.stdout = &ptr.stdout_writer.interface;

            ptr.reader = try .init(ptr.allocator, event_allocator, stdin.handle, stdout.handle, &ptr.winsize);
            errdefer ptr.reader.deinit(ptr.allocator);

            ptr.opts = .{
                .kitty_keyboard_flags = opts.kitty_keyboard_flags,
            };
            ptr.caps = opts.caps orelse common.TerminalCapabilities.query(stdin, stdout, 5 * std.time.ms_per_s) catch return error.UnableToQueryTerminalCapabilities;

            if (comptime config.run_own_thread) {
                ptr.reader.start() catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    else => return error.UnableToStartReader,
                };
            }

            try ptr.stdout.writeAll(ctlseqs.Terminal.braketed_paste_set);
            if (ptr.caps.in_band_winsize) {
                try ptr.stdout.writeAll(ctlseqs.Terminal.in_band_resize_set);
            }
            if (ptr.caps.sgr_pixels) {
                try ptr.stdout.writeAll(ctlseqs.Terminal.mouse_set_pixels);
            } else {
                try ptr.stdout.writeAll(ctlseqs.Terminal.mouse_set);
            }
            if (ptr.caps.kitty_keyboard != null) {
                try ctlseqs.Terminal.setKittyKeyboardHandling(ptr.stdout, opts.kitty_keyboard_flags);
            }
            try ptr.stdout.flush();

            switch (builtin.os.tag) {
                .windows => {},
                else => {
                    if (!builtin.is_test and !ptr.caps.in_band_winsize) {
                        try SigwinchHandling.notifyWinsize(.{
                            .context = ptr,
                            .callback = struct {
                                pub fn call(context: *anyopaque) void {
                                    const self: *Self = @ptrCast(@alignCast(context));
                                    const winsize = InternalReader.getWinsize(self.stdin_handle) catch return;
                                    self.reader.postEvent(.{ .winsize = winsize });
                                }
                            }.call,
                        });
                    }
                },
            }

            _ = try ptr.updateWinsize();

            return ptr;
        }

        pub fn deinit(self: *Self) void {
            switch (builtin.os.tag) {
                .windows => {},
                else => {
                    if (!builtin.is_test) {
                        SigwinchHandling.removeNotifyWinsize(self);
                    }
                },
            }

            self.reader.deinit(self.allocator);

            self.revertTerminal();
            self.allocator.free(self.stdout_writer_buf);

            self.allocator.destroy(self);
        }

        /// Makes tty basically useless and probably crashes reader thread.
        pub fn revertTerminal(self: *Self) void {
            if (comptime config.run_own_thread) {
                self.reader.stop();
            }
            self.raw_mode.disable();

            if (self.caps.kitty_keyboard) |detail| {
                ctlseqs.Terminal.setKittyKeyboardHandling(self.stdout, detail) catch {};
            }
            if (self.caps.in_band_winsize) {
                self.stdout.writeAll(ctlseqs.Terminal.in_band_resize_reset) catch {};
            }
            self.stdout.writeAll(ctlseqs.Terminal.braketed_paste_reset) catch {};
            self.stdout.writeAll(ctlseqs.Terminal.mouse_reset) catch {};
            self.stdout.flush() catch {};
        }

        pub inline fn strWidth(self: *Self, str: []const u8) usize {
            return common.gwidth.gwidth(str, self.caps.unicode_width_method);
        }

        pub inline fn getWinsize(self: *const Self) Winsize {
            return self.winsize.load(.acquire);
        }

        pub fn updateWinsize(self: *Self) error{UnableToGetWinsize}!Winsize {
            const winsize = InternalReader.getWinsize(self.stdout_handle) catch return error.UnableToGetWinsize;
            self.winsize.store(winsize, .release);
            return winsize;
        }

        pub inline fn nextEvent(self: *Self) Reader.ParseError!Event {
            return self.reader.nextEvent();
        }

        pub inline fn flush(self: *Self) std.Io.Writer.Error!void {
            return self.stdout.flush();
        }

        pub fn requestClipboard(self: *Self) std.Io.Writer.Error!void {
            return self.stdout.writeAll(ctlseqs.Terminal.clipboard_request);
        }

        pub fn notify(self: *Self, title: ?[]const u8, msg: []const u8) std.Io.Writer.Error!void {
            return ctlseqs.Terminal.notify(self.stdout, title, msg);
        }

        pub fn setProgressIndicator(self: *Self, state: ctlseqs.Terminal.Progress) std.Io.Writer.Error!void {
            return ctlseqs.Terminal.progress(self.stdout, state);
        }

        pub fn setTitle(self: *Self, title: []const u8) std.Io.Writer.Error!void {
            return ctlseqs.Terminal.setTitle(self.stdout, title);
        }

        pub fn changeCurrentWorkingDirectory(self: *Self, path: []const u8) std.Io.Writer.Error!void {
            std.debug.assert(std.fs.path.isAbsolute(path));
            return ctlseqs.Terminal.cd(self.stdout, path);
        }

        pub fn saveScreen(self: *Self) std.Io.Writer.Error!void {
            return self.stdout.writeAll(ctlseqs.Screen.save);
        }

        pub fn restoreScreen(self: *Self) std.Io.Writer.Error!void {
            return self.stdout.writeAll(ctlseqs.Screen.restore);
        }

        pub fn resetScreen(self: *Self) std.Io.Writer.Error!void {
            try self.clearScreen(.entire);
            try self.moveCursor(.home);
        }

        pub fn clearScreen(self: *Self, mode: ClearScreenMode) std.Io.Writer.Error!void {
            switch (mode) {
                .entire => {
                    try self.clearScrollback();
                    return self.stdout.writeAll(ctlseqs.Erase.visible_screen);
                },
                .visible => {
                    return self.stdout.writeAll(ctlseqs.Erase.visible_screen);
                },
                .before_cursor => {
                    return self.stdout.writeAll(ctlseqs.Erase.screen_begin_to_cursor);
                },
                .after_cursor => {
                    return self.stdout.writeAll(ctlseqs.Erase.cursor_to_screen_end);
                },
            }
        }

        pub fn clearScrollback(self: *Self) std.Io.Writer.Error!void {
            return self.stdout.writeAll(ctlseqs.Erase.scroll_back);
        }

        pub fn enableAlternativeScreen(self: *Self) std.Io.Writer.Error!void {
            return self.stdout.writeAll(ctlseqs.Screen.alternative_enable);
        }

        pub fn disableAlternativeScreen(self: *Self) std.Io.Writer.Error!void {
            return self.stdout.writeAll(ctlseqs.Screen.alternative_disable);
        }

        pub fn enableAndResetAlternativeScreen(self: *Self) std.Io.Writer.Error!void {
            try self.enableAlternativeScreen();
            try self.resetScreen();
        }

        pub fn setMouseEvents(self: *Self, enable: bool) std.Io.Writer.Error!void {
            if (!enable) {
                return self.stdout.writeAll(ctlseqs.Terminal.mouse_reset);
            }

            if (self.caps.sgr_pixels) {
                return self.stdout.writeAll(ctlseqs.Terminal.mouse_set_pixels);
            } else {
                return self.stdout.writeAll(ctlseqs.Terminal.mouse_set);
            }
        }

        pub fn hideCursor(self: *Self) std.Io.Writer.Error!void {
            return self.stdout.writeAll(ctlseqs.Cursor.hide);
        }

        pub fn showCursor(self: *Self) std.Io.Writer.Error!void {
            return self.stdout.writeAll(ctlseqs.Cursor.show);
        }

        pub fn saveCursorPos(self: *Self) std.Io.Writer.Error!void {
            return self.stdout.writeAll(ctlseqs.Cursor.save_position);
        }

        pub fn restoreCursorPos(self: *Self) std.Io.Writer.Error!void {
            return self.stdout.writeAll(ctlseqs.Cursor.restore_position);
        }

        pub fn setCursorShape(self: *Self, shape: ctlseqs.Cursor.Shape) std.Io.Writer.Error!void {
            return ctlseqs.Cursor.setCursorShape(self.stdout, shape);
        }

        pub fn moveCursor(self: *Self, move_cursor: MoveCursor) std.Io.Writer.Error!void {
            const cursor = ctlseqs.Cursor;

            move: switch (move_cursor) {
                .home => {
                    return self.stdout.writeAll(cursor.home);
                },
                .pos => |pos| {
                    return cursor.moveTo(self.stdout, pos.row, pos.column);
                },
                .up => |x| {
                    if (x == 0) return;
                    return cursor.moveUp(self.stdout, x);
                },
                .down => |x| {
                    if (x == 0) return;
                    return cursor.moveDown(self.stdout, x);
                },
                .left => |x| {
                    if (x == 0) return;
                    return cursor.moveLeft(self.stdout, x);
                },
                .right => |x| {
                    if (x == 0) return;
                    return cursor.moveRight(self.stdout, x);
                },
                .front_up => |x| {
                    if (x == 0) continue :move .front;
                    return cursor.moveFrontUp(self.stdout, x);
                },
                .front_down => |x| {
                    if (x == 0) continue :move .front;
                    return cursor.moveFrontDown(self.stdout, x);
                },
                .column => |x| {
                    return cursor.moveToColumn(self.stdout, x);
                },
                .up_scroll_if_needed => {
                    return self.stdout.writeAll(cursor.move_up_scroll_if_needed);
                },

                .front => {
                    continue :move .{ .column = 0 };
                },
                .end => {
                    continue :move .{ .column = self.getWinsize().cols };
                },
            }
        }

        pub fn setStyling(self: *Self, style: *const ctlseqs.Styling) std.Io.Writer.Error!void {
            return style.print(self.stdout);
        }

        pub fn clearLine(self: *Self, mode: ClearLineMode) std.Io.Writer.Error!void {
            switch (mode) {
                .entire => {
                    return self.stdout.writeAll(ctlseqs.Erase.line);
                },
                .before_cursor => {
                    return self.stdout.writeAll(ctlseqs.Erase.line_begin_to_cursor);
                },
                .after_cursor => {
                    return self.stdout.writeAll(ctlseqs.Erase.cursor_to_line_end);
                },
            }
        }

        pub fn resetLine(self: *Self) std.Io.Writer.Error!void {
            try self.clearLine(.entire);
            try self.moveCursor(.front);
        }

        pub fn writeHyperlink(self: *Self, hyperlink: ctlseqs.Hyperlink, text: []const u8) std.Io.Writer.Error!void {
            try hyperlink.introduce(self.stdout);
            try self.stdout.writeAll(text);
            try self.stdout.writeAll(ctlseqs.Hyperlink.close);
        }

        pub fn startSync(self: *Self) HelperError!void {
            if (!self.caps.sync) return error.CapabilityNotSupported;

            return self.stdout.writeAll(ctlseqs.Terminal.sync_begin);
        }

        pub fn endSync(self: *Self) HelperError!void {
            if (!self.caps.sync) return error.CapabilityNotSupported;

            return self.stdout.writeAll(ctlseqs.Terminal.sync_end);
        }

        pub fn beginScaledText(self: *Self, scaled: ctlseqs.Text.Scaled) HelperError!void {
            if (!self.caps.explicit_width) return error.CapabilityNotSupported;

            return ctlseqs.Text.introduceScaled(self.stdout, scaled);
        }

        pub fn endScaledText(self: *Self) HelperError!void {
            if (!self.caps.explicit_width) return error.CapabilityNotSupported;

            return self.stdout.writeAll(ctlseqs.Text.end_scaled_or_explicit_width);
        }

        pub fn beginExplicitWidthText(self: *Self, width: u3) HelperError!void {
            if (!self.caps.explicit_width) return error.CapabilityNotSupported;

            return ctlseqs.Text.introduceExplicitWidth(self.stdout, width);
        }

        pub fn endExplicitWidthText(self: *Self) HelperError!void {
            if (!self.caps.explicit_width) return error.CapabilityNotSupported;

            return self.stdout.writeAll(ctlseqs.Text.end_scaled_or_explicit_width);
        }

        pub fn addCursor(self: *Self, shape: ctlseqs.MultiCursor.Shape, positions: []const ctlseqs.MultiCursor.Position) HelperError!void {
            const multi_caps = self.caps.multi_cursor orelse return error.CapabilityNotSupported;
            switch (shape) {
                .block => if (!multi_caps.block) return error.CapabilityNotSupported,
                .beam => if (!multi_caps.beam) return error.CapabilityNotSupported,
                .underline => if (!multi_caps.underline) return error.CapabilityNotSupported,
                .follow_main => if (!multi_caps.follow_main_cursor) return error.CapabilityNotSupported,
            }

            return ctlseqs.MultiCursor.add(self.stdout, shape, positions);
        }

        pub fn removeCursor(self: *Self, positions: []const ctlseqs.MultiCursor.Position) HelperError!void {
            if (self.caps.multi_cursor == null) return error.CapabilityNotSupported;
            return ctlseqs.MultiCursor.remove(self.stdout, positions);
        }

        pub fn clearCursor(self: *Self) HelperError!void {
            if (self.caps.multi_cursor == null) return error.CapabilityNotSupported;
            return self.stdout.writeAll(ctlseqs.MultiCursor.RESET);
        }

        pub fn setMultiCursorsColor(self: *Self, color: ctlseqs.MultiCursor.ColorSpace) HelperError!void {
            const multi_caps = self.caps.multi_cursor orelse return error.CapabilityNotSupported;
            if (!multi_caps.change_color_of_extra_cursors) return error.CapabilityNotSupported;

            return ctlseqs.MultiCursor.setCursorColor(self.stdout, color);
        }

        pub fn setTextUnderMultiCursorsColor(self: *Self, color: ctlseqs.MultiCursor.ColorSpace) HelperError!void {
            const multi_caps = self.caps.multi_cursor orelse return error.CapabilityNotSupported;
            if (!multi_caps.change_color_of_text_under_extra_cursors) return error.CapabilityNotSupported;

            return ctlseqs.MultiCursor.setTextUnderCursorColor(self.stdout, color);
        }

        pub fn requestMultiCursors(self: *Self) HelperError!void {
            const multi_caps = self.caps.multi_cursor orelse return error.CapabilityNotSupported;
            if (!multi_caps.query_currently_set_cursors) return error.CapabilityNotSupported;

            return self.stdout.writeAll(ctlseqs.MultiCursor.QUERY_CURRENT_CURSORS);
        }

        pub fn requestMultiCursorsColor(self: *Self) HelperError!void {
            const multi_caps = self.caps.multi_cursor orelse return error.CapabilityNotSupported;
            if (!multi_caps.query_currently_set_cursor_colors) return error.CapabilityNotSupported;

            return self.stdout.writeAll(ctlseqs.MultiCursor.QUERY_CURRENT_CURSORS_COLOR);
        }

        const KittyHelperTransmitError = KittyGraphics.Error || HelperError;

        pub fn transmitImageKitty(self: *Self, source: common.Graphics.Source, opts: KittyGraphics.TransmitOnlyOptions) KittyHelperTransmitError!void {
            if (!self.caps.kitty_graphics) return error.CapabilityNotSupported;
            return KittyGraphics.transmitOnly(self.stdout, self.allocator, source, opts);
        }

        pub fn transmitAndDisplayImageKitty(self: *Self, source: common.Graphics.Source, opts: KittyGraphics.TransmitAndDisplayOptions) KittyHelperTransmitError!void {
            if (!self.caps.kitty_graphics) return error.CapabilityNotSupported;
            return KittyGraphics.transmitAndDisplay(self.stdout, self.allocator, source, opts);
        }

        pub fn displayImageKitty(self: *Self, opts: KittyGraphics.DisplayOnlyOptions) HelperError!void {
            if (!self.caps.kitty_graphics) return error.CapabilityNotSupported;
            return KittyGraphics.display(self.stdout, opts);
        }

        pub fn eraseImageKitty(self: *Self, opts: KittyGraphics.EraseOptions) HelperError!void {
            if (!self.caps.kitty_graphics) return error.CapabilityNotSupported;
            return KittyGraphics.erase(self.stdout, opts);
        }

        pub fn transmitAnimationFrameKitty(self: *Self, opts: KittyGraphics.TransmitAnimationFrameOptions) KittyHelperTransmitError!void {
            if (!self.caps.kitty_graphics) return error.CapabilityNotSupported;
            return KittyGraphics.transmitAnimationFrame(self.stdout, self.allocator, opts);
        }

        pub fn controlAnimationKitty(self: *Self, opts: KittyGraphics.ControlAnimationOptions) HelperError!void {
            if (!self.caps.kitty_graphics) return error.CapabilityNotSupported;
            return KittyGraphics.controlAnimation(self.stdout, opts);
        }

        pub fn composeAnimationKitty(self: *Self, opts: KittyGraphics.ComposeAnimationOptions) HelperError!void {
            if (!self.caps.kitty_graphics) return error.CapabilityNotSupported;
            return KittyGraphics.composeAnimation(self.stdout, opts);
        }
    };
}

pub const ClearScreenMode = enum {
    entire,
    visible,
    before_cursor,
    after_cursor,
};

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

    front,
    end,

    pub const Pos = struct {
        row: u16 = 0,
        column: u16 = 0,
    };
};

pub const ClearLineMode = enum {
    entire,
    before_cursor,
    after_cursor,
};

pub const Options = struct {
    kitty_keyboard_flags: ctlseqs.Terminal.KittyKeyboardFlags = .default,
};

pub const CreateOptions = struct {
    caps: ?TerminalCapabilities = null,
    kitty_keyboard_flags: ctlseqs.Terminal.KittyKeyboardFlags = .default,
};

pub const TtyConfig = struct {
    /// If `true` runs the parser for incoming data in its own thread.
    run_own_thread: bool = false,
};

test {
    @setEvalBranchQuota(1_000_000);
    _ = std.testing.refAllDeclsRecursive(@This());
}
