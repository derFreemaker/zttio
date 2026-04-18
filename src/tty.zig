const std = @import("std");
const builtin = @import("builtin");

const Adapter = @import("adapter.zig");
const ctlseqs = @import("ctlseqs.zig");
const KittyGraphics = ctlseqs.KittyGraphics;
const GraphicsSource = @import("graphics/source.zig").Source;
const Event = @import("event.zig").Event;
const Winsize = @import("winsize.zig").Winsize;
const TerminalCapabilities = @import("terminal_capabilities.zig");
const gwidth = @import("gwidth.zig");

const Parser = @import("parser.zig");

const log = std.log.scoped(.zttio_tty);

pub const HelperError = std.Io.Writer.Error || error{CapabilityNotSupported};

const Tty = @This();

allocator: std.mem.Allocator,

parser: Parser,
writer: *std.Io.Writer,

opts: Options,
caps: TerminalCapabilities,

winsize: Winsize,

pub fn init(allocator: std.mem.Allocator, event_allocator: std.mem.Allocator, adapter: Adapter, opts: CreateOptions) error{ UnableToEnableReader, UnableToGetWinsize, WriteFailed }!Tty {
    // switch (builtin.os.tag) {
    //     .windows => {},
    //     else => {
    //         if (!builtin.is_test and !ptr.caps.in_band_winsize) {
    //             try SigwinchHandling.notifyWinsize(.{
    //                 .context = ptr,
    //                 .callback = struct {
    //                     pub fn call(context: *anyopaque) void {
    //                         const self: *Tty = @ptrCast(@alignCast(context));
    //                         const winsize = InternalReader.getWinsize(self.stdin_handle) catch return;
    //                         self.reader.postEvent(.{ .winsize = winsize });
    //                     }
    //                 }.call,
    //             });
    //         }
    //     },
    // }

    _ = adapter.enable() catch return error.UnableToEnableReader;

    const winsize = adapter.getWinsize() catch return error.UnableToGetWinsize;

    const writer = adapter.getWriter();

    try writer.writeAll(ctlseqs.Terminal.braketed_paste_set);

    if (opts.caps.in_band_winsize) {
        try writer.writeAll(ctlseqs.Terminal.in_band_resize_set);
    }

    if (opts.caps.sgr_pixels) {
        try writer.writeAll(ctlseqs.Terminal.mouse_set_pixels);
    } else {
        try writer.writeAll(ctlseqs.Terminal.mouse_set);
    }

    if (opts.caps.kitty_keyboard != null) {
        try ctlseqs.Terminal.setKittyKeyboardHandling(writer, opts.kitty_keyboard_flags);
    }

    try writer.flush();

    return Tty{
        .allocator = allocator,

        .writer = writer,
        .parser = .init(
            allocator,
            event_allocator,
            adapter,
        ),

        .opts = Options{
            .kitty_keyboard_flags = opts.kitty_keyboard_flags,
        },
        .caps = opts.caps,

        .winsize = winsize,
    };
}

pub fn deinit(self: *Tty) void {
    self.parser.deinit();

    if (self.caps.kitty_keyboard) |detail| {
        ctlseqs.Terminal.setKittyKeyboardHandling(self.writer, detail) catch {};
    }

    if (self.caps.in_band_winsize) {
        self.writer.writeAll(ctlseqs.Terminal.in_band_resize_reset) catch {};
    }

    self.writer.writeAll(ctlseqs.Terminal.braketed_paste_reset) catch {};

    self.writer.writeAll(ctlseqs.Terminal.mouse_reset) catch {};

    self.writer.flush() catch {};
}

pub inline fn strWidth(self: *Tty, str: []const u8) usize {
    return gwidth.gwidth(str, self.caps.unicode_width_method);
}

pub inline fn getWinsize(self: *const Tty) Winsize {
    return self.winsize;
}

pub inline fn updateWinsize(self: *const Tty) Parser.GetWinsizeError!Winsize {
    const winsize = try self.parser.getWinsize();
    self.winsize = winsize;
    return winsize;
}

/// Returns `null` if currently there are no more events that could be given.
pub inline fn nextEvent(self: *Tty) Parser.ParseError!Event {
    while (true) {
        const event = try self.parser.nextEvent(null) orelse continue;
        if (event == .winsize) {
            self.winsize = event.winsize;
        }

        return event;
    }
}

pub inline fn flush(self: *Tty) std.Io.Writer.Error!void {
    return self.writer.flush();
}

pub fn requestClipboard(self: *Tty) std.Io.Writer.Error!void {
    return self.writer.writeAll(ctlseqs.Terminal.clipboard_request);
}

pub fn notify(self: *Tty, title: ?[]const u8, msg: []const u8) std.Io.Writer.Error!void {
    return ctlseqs.Terminal.notify(self.writer, title, msg);
}

pub fn setProgressIndicator(self: *Tty, state: ctlseqs.Terminal.Progress) std.Io.Writer.Error!void {
    return ctlseqs.Terminal.progress(self.writer, state);
}

pub fn setTitle(self: *Tty, title: []const u8) std.Io.Writer.Error!void {
    return ctlseqs.Terminal.setTitle(self.writer, title);
}

pub fn changeCurrentWorkingDirectory(self: *Tty, path: []const u8) std.Io.Writer.Error!void {
    std.debug.assert(std.fs.path.isAbsolute(path));
    return ctlseqs.Terminal.cd(self.writer, path);
}

pub fn saveScreen(self: *Tty) std.Io.Writer.Error!void {
    return self.writer.writeAll(ctlseqs.Screen.save);
}

pub fn restoreScreen(self: *Tty) std.Io.Writer.Error!void {
    return self.writer.writeAll(ctlseqs.Screen.restore);
}

pub fn resetScreen(self: *Tty) std.Io.Writer.Error!void {
    try self.clearScreen(.entire);
    try self.moveCursor(.home);
}

pub const ClearScreenMode = enum {
    entire,
    visible,
    before_cursor,
    after_cursor,
};

pub fn clearScreen(self: *Tty, mode: ClearScreenMode) std.Io.Writer.Error!void {
    switch (mode) {
        .entire => {
            try self.clearScrollback();
            return self.writer.writeAll(ctlseqs.Erase.visible_screen);
        },
        .visible => {
            return self.writer.writeAll(ctlseqs.Erase.visible_screen);
        },
        .before_cursor => {
            return self.writer.writeAll(ctlseqs.Erase.screen_begin_to_cursor);
        },
        .after_cursor => {
            return self.writer.writeAll(ctlseqs.Erase.cursor_to_screen_end);
        },
    }
}

pub fn clearScrollback(self: *Tty) std.Io.Writer.Error!void {
    return self.writer.writeAll(ctlseqs.Erase.scroll_back);
}

pub fn enableAlternativeScreen(self: *Tty) std.Io.Writer.Error!void {
    return self.writer.writeAll(ctlseqs.Screen.alternative_enable);
}

pub fn disableAlternativeScreen(self: *Tty) std.Io.Writer.Error!void {
    return self.writer.writeAll(ctlseqs.Screen.alternative_disable);
}

pub fn enableAndResetAlternativeScreen(self: *Tty) std.Io.Writer.Error!void {
    try self.enableAlternativeScreen();
    try self.resetScreen();
}

pub fn setMouseEvents(self: *Tty, enable: bool) std.Io.Writer.Error!void {
    if (!enable) {
        return self.writer.writeAll(ctlseqs.Terminal.mouse_reset);
    }

    if (self.caps.sgr_pixels) {
        return self.writer.writeAll(ctlseqs.Terminal.mouse_set_pixels);
    } else {
        return self.writer.writeAll(ctlseqs.Terminal.mouse_set);
    }
}

pub fn hideCursor(self: *Tty) std.Io.Writer.Error!void {
    return self.writer.writeAll(ctlseqs.Cursor.hide);
}

pub fn showCursor(self: *Tty) std.Io.Writer.Error!void {
    return self.writer.writeAll(ctlseqs.Cursor.show);
}

pub fn saveCursorPos(self: *Tty) std.Io.Writer.Error!void {
    return self.writer.writeAll(ctlseqs.Cursor.save_position);
}

pub fn restoreCursorPos(self: *Tty) std.Io.Writer.Error!void {
    return self.writer.writeAll(ctlseqs.Cursor.restore_position);
}

pub fn setCursorShape(self: *Tty, shape: ctlseqs.Cursor.Shape) std.Io.Writer.Error!void {
    return ctlseqs.Cursor.setCursorShape(self.writer, shape);
}

pub fn moveCursor(self: *Tty, move_cursor: MoveCursor) std.Io.Writer.Error!void {
    const cursor = ctlseqs.Cursor;

    move: switch (move_cursor) {
        .home => {
            return self.writer.writeAll(cursor.home);
        },
        .pos => |pos| {
            return cursor.moveTo(self.writer, pos.row, pos.column);
        },
        .up => |x| {
            if (x == 0) return;
            return cursor.moveUp(self.writer, x);
        },
        .down => |x| {
            if (x == 0) return;
            return cursor.moveDown(self.writer, x);
        },
        .left => |x| {
            if (x == 0) return;
            return cursor.moveLeft(self.writer, x);
        },
        .right => |x| {
            if (x == 0) return;
            return cursor.moveRight(self.writer, x);
        },
        .front_up => |x| {
            if (x == 0) continue :move .front;
            return cursor.moveFrontUp(self.writer, x);
        },
        .front_down => |x| {
            if (x == 0) continue :move .front;
            return cursor.moveFrontDown(self.writer, x);
        },
        .column => |x| {
            return cursor.moveToColumn(self.writer, x);
        },
        .up_scroll_if_needed => {
            return self.writer.writeAll(cursor.move_up_scroll_if_needed);
        },

        .front => {
            continue :move .{ .column = 0 };
        },
        .end => {
            continue :move .{ .column = self.getWinsize().cols };
        },
    }
}

pub fn setStyling(self: *Tty, style: *const ctlseqs.Styling) std.Io.Writer.Error!void {
    return style.print(self.writer);
}

pub fn clearLine(self: *Tty, mode: ClearLineMode) std.Io.Writer.Error!void {
    switch (mode) {
        .entire => {
            return self.writer.writeAll(ctlseqs.Erase.line);
        },
        .before_cursor => {
            return self.writer.writeAll(ctlseqs.Erase.line_begin_to_cursor);
        },
        .after_cursor => {
            return self.writer.writeAll(ctlseqs.Erase.cursor_to_line_end);
        },
    }
}

pub fn resetLine(self: *Tty) std.Io.Writer.Error!void {
    try self.clearLine(.entire);
    try self.moveCursor(.front);
}

pub fn writeHyperlink(self: *Tty, hyperlink: ctlseqs.Hyperlink, text: []const u8) std.Io.Writer.Error!void {
    try hyperlink.introduce(self.writer);
    try self.writer.writeAll(text);
    try self.writer.writeAll(ctlseqs.Hyperlink.close);
}

pub fn startSync(self: *Tty) HelperError!void {
    if (!self.caps.sync) return error.CapabilityNotSupported;

    return self.writer.writeAll(ctlseqs.Terminal.sync_begin);
}

pub fn endSync(self: *Tty) HelperError!void {
    if (!self.caps.sync) return error.CapabilityNotSupported;

    return self.writer.writeAll(ctlseqs.Terminal.sync_end);
}

pub fn beginScaledText(self: *Tty, scaled: ctlseqs.Text.Scaled) HelperError!void {
    if (!self.caps.explicit_width) return error.CapabilityNotSupported;

    return ctlseqs.Text.introduceScaled(self.writer, scaled);
}

pub fn endScaledText(self: *Tty) HelperError!void {
    if (!self.caps.explicit_width) return error.CapabilityNotSupported;

    return self.writer.writeAll(ctlseqs.Text.end_scaled_or_explicit_width);
}

pub fn beginExplicitWidthText(self: *Tty, width: u3) HelperError!void {
    if (!self.caps.explicit_width) return error.CapabilityNotSupported;

    return ctlseqs.Text.introduceExplicitWidth(self.writer, width);
}

pub fn endExplicitWidthText(self: *Tty) HelperError!void {
    if (!self.caps.explicit_width) return error.CapabilityNotSupported;

    return self.writer.writeAll(ctlseqs.Text.end_scaled_or_explicit_width);
}

pub fn addCursor(self: *Tty, shape: ctlseqs.MultiCursor.Shape, positions: []const ctlseqs.MultiCursor.Position) HelperError!void {
    const multi_caps = self.caps.multi_cursor orelse return error.CapabilityNotSupported;
    switch (shape) {
        .block => if (!multi_caps.block) return error.CapabilityNotSupported,
        .beam => if (!multi_caps.beam) return error.CapabilityNotSupported,
        .underline => if (!multi_caps.underline) return error.CapabilityNotSupported,
        .follow_main => if (!multi_caps.follow_main_cursor) return error.CapabilityNotSupported,
    }

    return ctlseqs.MultiCursor.add(self.writer, shape, positions);
}

pub fn removeCursor(self: *Tty, positions: []const ctlseqs.MultiCursor.Position) HelperError!void {
    if (self.caps.multi_cursor == null) return error.CapabilityNotSupported;
    return ctlseqs.MultiCursor.remove(self.writer, positions);
}

pub fn clearCursor(self: *Tty) HelperError!void {
    if (self.caps.multi_cursor == null) return error.CapabilityNotSupported;
    return self.writer.writeAll(ctlseqs.MultiCursor.RESET);
}

pub fn setMultiCursorsColor(self: *Tty, color: ctlseqs.MultiCursor.ColorSpace) HelperError!void {
    const multi_caps = self.caps.multi_cursor orelse return error.CapabilityNotSupported;
    if (!multi_caps.change_color_of_extra_cursors) return error.CapabilityNotSupported;

    return ctlseqs.MultiCursor.setCursorColor(self.writer, color);
}

pub fn setTextUnderMultiCursorsColor(self: *Tty, color: ctlseqs.MultiCursor.ColorSpace) HelperError!void {
    const multi_caps = self.caps.multi_cursor orelse return error.CapabilityNotSupported;
    if (!multi_caps.change_color_of_text_under_extra_cursors) return error.CapabilityNotSupported;

    return ctlseqs.MultiCursor.setTextUnderCursorColor(self.writer, color);
}

pub fn requestMultiCursors(self: *Tty) HelperError!void {
    const multi_caps = self.caps.multi_cursor orelse return error.CapabilityNotSupported;
    if (!multi_caps.query_currently_set_cursors) return error.CapabilityNotSupported;

    return self.writer.writeAll(ctlseqs.MultiCursor.QUERY_CURRENT_CURSORS);
}

pub fn requestMultiCursorsColor(self: *Tty) HelperError!void {
    const multi_caps = self.caps.multi_cursor orelse return error.CapabilityNotSupported;
    if (!multi_caps.query_currently_set_cursor_colors) return error.CapabilityNotSupported;

    return self.writer.writeAll(ctlseqs.MultiCursor.QUERY_CURRENT_CURSORS_COLOR);
}

// const KittyHelperTransmitError = KittyGraphics.Error || HelperError;

// pub fn transmitImageKitty(self: *Tty, source: GraphicsSource, opts: KittyGraphics.TransmitOnlyOptions) KittyHelperTransmitError!void {
//     if (!self.caps.kitty_graphics) return error.CapabilityNotSupported;
//     return KittyGraphics.transmitOnly(self.writer, self.allocator, source, opts);
// }

// pub fn transmitAndDisplayImageKitty(self: *Tty, source: GraphicsSource, opts: KittyGraphics.TransmitAndDisplayOptions) KittyHelperTransmitError!void {
//     if (!self.caps.kitty_graphics) return error.CapabilityNotSupported;
//     return KittyGraphics.transmitAndDisplay(self.writer, self.allocator, source, opts);
// }

// pub fn displayImageKitty(self: *Tty, opts: KittyGraphics.DisplayOnlyOptions) HelperError!void {
//     if (!self.caps.kitty_graphics) return error.CapabilityNotSupported;
//     return KittyGraphics.display(self.writer, opts);
// }

// pub fn eraseImageKitty(self: *Tty, opts: KittyGraphics.EraseOptions) HelperError!void {
//     if (!self.caps.kitty_graphics) return error.CapabilityNotSupported;
//     return KittyGraphics.erase(self.writer, opts);
// }

// pub fn transmitAnimationFrameKitty(self: *Tty, opts: KittyGraphics.TransmitAnimationFrameOptions) KittyHelperTransmitError!void {
//     if (!self.caps.kitty_graphics) return error.CapabilityNotSupported;
//     return KittyGraphics.transmitAnimationFrame(self.writer, self.allocator, opts);
// }

// pub fn controlAnimationKitty(self: *Tty, opts: KittyGraphics.ControlAnimationOptions) HelperError!void {
//     if (!self.caps.kitty_graphics) return error.CapabilityNotSupported;
//     return KittyGraphics.controlAnimation(self.writer, opts);
// }

// pub fn composeAnimationKitty(self: *Tty, opts: KittyGraphics.ComposeAnimationOptions) HelperError!void {
//     if (!self.caps.kitty_graphics) return error.CapabilityNotSupported;
//     return KittyGraphics.composeAnimation(self.writer, opts);
// }

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
    caps: TerminalCapabilities,
    kitty_keyboard_flags: ctlseqs.Terminal.KittyKeyboardFlags = .default,
};

pub const TtyConfig = struct {
    /// If `true` runs the parser for incoming data in its own thread.
    run_own_thread: bool = false,
};
