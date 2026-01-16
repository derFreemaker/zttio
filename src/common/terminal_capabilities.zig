const std = @import("std");
const builin = @import("builtin");
const uucode = @import("uucode");
const zigwin = @import("zigwin");
const winconsole = zigwin.system.console;

const ctlseqs = @import("ctlseqs.zig");
const KittyMultiCursorFlags = ctlseqs.Terminal.KittyMultiCursorFlags;
const KittyKeyboardFlags = ctlseqs.Terminal.KittyKeyboardFlags;
const gwidth = @import("gwidth.zig");
const Key = @import("key.zig");

const COLORTERM_ENV_VAR_NAME = "COLORTERM";
fn getColorTermW() [:0]const u16 {
    const static = struct {
        var buf: [COLORTERM_ENV_VAR_NAME.len + 1:0]u16 = blk: {
            var b: [COLORTERM_ENV_VAR_NAME.len + 1:0]u16 = undefined;
            const n = std.unicode.wtf8ToWtf16Le(&b, COLORTERM_ENV_VAR_NAME) catch unreachable;
            b[n] = 0;
            break :blk b;
        };
    };
    return &static.buf;
}

const TerminalCapabilities = @This();

focus: bool = false,
sgr_pixels: bool = false,
sync: bool = false,
unicode_width_method: gwidth.Method = .wcwidth,
color_scheme_updates: bool = false,
in_band_winsize: bool = false,
explicit_width: bool = false,
scaled_text: bool = false,
multi_cursor: ?KittyMultiCursorFlags = null,
kitty_keyboard: ?KittyKeyboardFlags = null,
kitty_graphics: bool = false,
rgb: bool = false,

/// Queries the terminal capabilities and blocks, until primary device attributes response is found.
pub fn query(stdin: std.fs.File, stdout: std.fs.File, timeout_ms: u32) error{ NoTty, ReadFailed, WriteFailed, EndOfStream }!TerminalCapabilities {
    if (!stdout.isTty()) return error.NoTty;

    var writer_buf: [32]u8 = undefined;
    var _writer = stdout.writer(&writer_buf);
    const writer = &_writer.interface;

    try writer.writeAll(ctlseqs.Screen.save ++
        ctlseqs.Cursor.save_position ++ "detecting terminal capabilities...");

    try writeQuery(writer);
    try writer.flush();

    const caps = try parseQueryResponses(stdin, timeout_ms);

    try writer.writeAll(ctlseqs.Cursor.restore_position ++
        ctlseqs.Erase.line ++ // erase: "detecting terminal capabilities..."
        ctlseqs.Screen.restore);
    try writer.flush();

    return caps;
}

pub fn writeQuery(writer: *std.Io.Writer) error{ NoTty, WriteFailed }!void {
    const queries = ctlseqs.Queries;

    try writer.writeAll(queries.decrqm_focus ++
        queries.decrqm_sync ++
        queries.decrqm_sgr_pixels ++
        queries.decrqm_unicode ++
        queries.decrqm_color_scheme ++

        // Explicit width query. We send the cursor home, then do an explicit width command, then
        // query the position. If the parsed value is an F3 with shift, we support explicit width.
        // The returned response will be something like \x1b[1;2R...which when parsed as a Key is a
        // shift + F3 (the row is ignored). We only care if the column has moved from 1->2, which is
        // why we see a Shift modifier
        ctlseqs.Cursor.home ++
        queries.explicit_width ++
        ctlseqs.Cursor.position_request ++

        // Scaled text query. We send the cursor home, then do an scaled text command, then
        // query the position. If the parsed value is an F3 with al, we support scaled text.
        // The returned response will be something like \x1b[1;3R...which when parsed as a Key is a
        // alt + F3 (the row is ignored). We only care if the column has moved from 1->3, which is
        // why we see a Alt modifier
        ctlseqs.Cursor.home ++
        queries.scaled_text ++
        ctlseqs.Cursor.position_request ++
        queries.kitty_multi_cursor ++
        queries.kitty_keyboard ++
        queries.kitty_graphics ++
        queries.primary_device_attrs);
}

/// Will block until the primary device attributes are found.
/// Recommended to use `query()`.
///
/// TODO: maybe add timeout
pub fn parseQueryResponses(stdin: std.fs.File, timeout_ms: u32) error{ ReadFailed, EndOfStream }!TerminalCapabilities {
    var reader_buf: [32]u8 = undefined;
    var _reader: std.fs.File.Reader = .initStreaming(stdin, &reader_buf);
    const reader = &_reader.interface;

    var caps: TerminalCapabilities = .{};

    {
        if (builin.os.tag == .windows) {
            const colorterm = std.process.getenvW(getColorTermW());
            if (colorterm) |term| {
                if (std.mem.eql(u16, term, &.{ 't', 'r', 'u', 'e', 'c', 'o', 'l', 'o', 'r' }) or
                    std.mem.eql(u16, term, &.{ '2', '4', 'b', 'i', 't' }))
                {
                    caps.rgb = true;
                }
            }
        } else {
            const colorterm = std.posix.getenv(COLORTERM_ENV_VAR_NAME);
            if (colorterm) |term| {
                if (std.mem.eql(u8, term, "truecolor") or
                    std.mem.eql(u8, term, "24bit"))
                {
                    caps.rgb = true;
                }
            }
        }
    }

    const end_ms = std.time.milliTimestamp() + timeout_ms;
    var buf: [256]u8 = undefined;
    var i: usize = 0;
    while (true) {
        if (end_ms < std.time.milliTimestamp()) {
            break;
        }

        switch (builin.os.tag) {
            .windows => {
                buf[i] = try reader.takeByte();
                i += 1;
            },
            else => {
                i += std.posix.read(stdin.handle, buf[i..]) catch |err| switch (err) {
                    error.WouldBlock => continue,
                    else => return error.ReadFailed,
                };
            },
        }

        if (i < 2) {
            continue;
        }

        const result = parse(buf[0..i], &caps);
        if (result.n > 0) {
            // if (buf[0] == ctlseqs.ESC[0]) {
            //     std.debug.print("seq: <ESC>{s}\n", .{buf[1..result.n]});
            // } else {
            //     std.debug.print("seq: {s}\n", .{buf[0..result.n]});
            // }

            @memmove(buf[0 .. i - result.n], buf[result.n..i]);
            i -= result.n;
        }

        if (result.done) {
            break;
        }
    }

    return caps;
}

pub const ParseResult = struct {
    done: bool = false,
    n: usize,

    pub const none = ParseResult{
        .n = 0,
    };

    pub fn consume(n: usize) ParseResult {
        return ParseResult{
            .n = n,
        };
    }
};

fn parse(input: []const u8, caps: *TerminalCapabilities) ParseResult {
    std.debug.assert(input.len > 0);

    // We gate this for len > 1 so we can detect singular escape key presses
    if (input[0] == 0x1b and input.len > 1) {
        switch (input[1]) {
            'N' => return parseSs2(input),
            'O' => return parseSs3(input),
            'P' => return skipUntilST(input), // DCS
            'X' => return skipUntilST(input), // SOS
            '[' => return parseCsi(input, caps),
            ']' => return parseOsc(input),
            '^' => return skipUntilST(input), // PM
            '_' => return parseApc(input, caps),
            else => {
                return .consume(2);
            },
        }
    } else return parseGround(input);
}

inline fn parseSs2(input: []const u8) ParseResult {
    if (input.len < 3) return .none;
    if (input[2] == ctlseqs.ESC[0]) return .consume(2);
    return .consume(3);
}

inline fn parseSs3(input: []const u8) ParseResult {
    if (input.len < 3) return .none;
    if (input[2] == ctlseqs.ESC[0]) return .consume(2);
    return .consume(3);
}

inline fn skipUntilST(input: []const u8) ParseResult {
    if (input.len < 3) return .none;

    var chunker = std.mem.window(u8, input[2..], 2, 1);
    while (chunker.next()) |chunk| {
        if (chunk.len < 2) return .none;

        if (std.mem.eql(u8, chunk, ctlseqs.ST)) {
            const end = if (chunker.index) |index| index - 2 else input.len;
            return .consume(end);
        }
    }

    return .none;
}

inline fn parseCsi(input: []const u8, caps: *TerminalCapabilities) ParseResult {
    if (input.len < 3) {
        return .none;
    }
    // We start iterating at index 2 to get past the '['
    const sequence = for (input[2..], 2..) |b, i| {
        switch (b) {
            0x40...0xFF => break input[0 .. i + 1],
            else => continue,
        }
    } else return .none;
    const consume: ParseResult = .consume(sequence.len);

    const final = sequence[sequence.len - 1];
    return switch (final) {
        'R' => {
            // Split first into fields delimited by ';'
            var field_iter = std.mem.splitScalar(u8, sequence[2 .. sequence.len - 1], ';');

            // skip the first field
            _ = field_iter.next(); //

            var mods: Key.Modifiers = .{};
            field2: {
                // modifier_mask:event_type
                const field_buf = field_iter.next() orelse break :field2;
                var param_iter = std.mem.splitScalar(u8, field_buf, ':');
                const modifier_buf = param_iter.next() orelse unreachable;
                const modifier_mask = parseParam(u8, modifier_buf, 1) orelse return consume;
                mods = @bitCast(modifier_mask -| 1);
            }

            if (mods.shift) {
                caps.explicit_width = true;
            } else if (mods.alt) {
                caps.scaled_text = true;
            }

            return consume;
        },
        'c' => {
            // Primary DA (CSI ? Pm c)
            std.debug.assert(sequence.len >= 4); // ESC [ ? c == 4 bytes
            switch (input[2]) {
                '?' => {
                    // we issue the primary attrs as last one and expect an FIFO sequence handling of the terminal
                    return ParseResult{
                        .done = true,
                        .n = sequence.len,
                    };
                },
                else => return consume,
            }
        },
        'u' => {
            // we ignore the flags
            if (sequence.len < 3 or sequence[2] != '?') return consume;

            const flags_num = parseParam(u5, sequence[3 .. sequence.len - 1], null) orelse return consume;
            caps.kitty_keyboard = @as(KittyKeyboardFlags, @bitCast(flags_num));

            return consume;
        },
        'y' => {
            // DECRPM (CSI ? Pd ; Ps $ y)
            const delim_idx = std.mem.indexOfScalarPos(u8, input, 3, ';') orelse return consume;
            const pd = std.fmt.parseUnsigned(u16, input[3..delim_idx], 10) catch return consume;
            const ps = std.fmt.parseUnsigned(u8, input[delim_idx + 1 .. sequence.len - 2], 10) catch return consume;
            switch (pd) {
                // Focus Events
                1004 => switch (ps) {
                    0, 4 => return consume,
                    else => {
                        caps.focus = true;
                        return consume;
                    },
                },
                // Mouse Pixel reporting (SGR)
                1016 => switch (ps) {
                    0, 4 => return consume,
                    else => {
                        caps.sgr_pixels = true;
                        return consume;
                    },
                },
                // Synchronized Output
                2026 => switch (ps) {
                    0, 4 => return consume,
                    else => {
                        caps.sync = true;
                        return consume;
                    },
                },
                // Unicode Core, see https://github.com/contour-terminal/terminal-unicode-core
                2027 => switch (ps) {
                    0, 4 => return consume,
                    else => {
                        caps.unicode_width_method = .unicode;
                        return consume;
                    },
                },
                // Color scheme reportnig, see https://github.com/contour-terminal/contour/blob/master/docs/vt-extensions/color-palette-update-notifications.md
                2031 => switch (ps) {
                    0, 4 => return consume,
                    else => {
                        caps.color_scheme_updates = true;
                        return consume;
                    },
                },
                // In-Band Window Resize Notifications, see https://gist.github.com/rockorager/e695fb2924d36b2bcf1fff4a3704bd83
                2048 => switch (ps) {
                    0, 4 => return consume,
                    else => {
                        caps.in_band_winsize = true;
                        return consume;
                    },
                },
                else => return consume,
            }
        },
        'q' => {
            // kitty multi cursor cap (CSI > 1;2;3;29;30;40;100;101 TRAILER) (TRAILER is " q")
            // see https://sw.kovidgoyal.net/kitty/multiple-cursors-protocol/
            const second_final = sequence[sequence.len - 2];
            if (second_final != ' ') return consume;

            var supported_multi_cursor: KittyMultiCursorFlags = .{};
            var field_iter = std.mem.splitScalar(u8, sequence[3 .. sequence.len - 2], ';');
            while (field_iter.next()) |field| {
                const cursor_shape = std.fmt.parseInt(u8, field, 10) catch continue;
                switch (cursor_shape) {
                    1 => supported_multi_cursor.block = true,
                    2 => supported_multi_cursor.beam = true,
                    3 => supported_multi_cursor.underline = true,
                    29 => supported_multi_cursor.follow_main_cursor = true,
                    30 => supported_multi_cursor.change_color_of_text_under_extra_cursors = true,
                    40 => supported_multi_cursor.change_color_of_extra_cursors = true,
                    100 => supported_multi_cursor.query_currently_set_cursors = true,
                    101 => supported_multi_cursor.query_currently_set_cursor_colors = true,
                    else => {},
                }
            }

            caps.multi_cursor = supported_multi_cursor;
            return consume;
        },
        else => return consume,
    };
}

inline fn parseOsc(input: []const u8) ParseResult {
    if (input.len < 3) {
        return .none;
    }
    var bel_terminated: bool = false;
    // end is the index of the terminating byte(s) (either the last byte of an
    // ST or BEL)
    const end: usize = blk: {
        const esc_result = skipUntilST(input);
        if (esc_result.n > 0) break :blk esc_result.n;

        // No escape, could be BEL terminated
        const bel = std.mem.indexOfScalarPos(u8, input, 2, 0x07) orelse return .none;
        bel_terminated = true;
        break :blk bel + 1;
    };

    // The complete OSC sequence
    // const sequence = input[0..end];

    return .consume(end);
}

inline fn parseApc(input: []const u8, caps: *TerminalCapabilities) ParseResult {
    if (input.len < 3) {
        return .none;
    }

    const end: usize = blk: {
        const esc_result = skipUntilST(input);
        if (esc_result.n > 0) break :blk esc_result.n;

        return .none;
    };
    const sequence = input[0..end];
    const consume: ParseResult = .consume(sequence.len);

    switch (input[2]) {
        'G' => {
            const semicolon_idx = std.mem.indexOfScalarPos(u8, sequence, 3, ';') orelse return consume;

            const content_buf = sequence[semicolon_idx + 1 .. sequence.len - 2];
            if (content_buf.len == 0) return consume;

            const colon_idx = std.mem.indexOfScalar(u8, content_buf, ':') orelse content_buf.len;
            const response_type_buf = content_buf[0..colon_idx];

            if (!std.mem.eql(u8, response_type_buf, "ENOTSUPPORTED")) {
                caps.kitty_graphics = true;
            }

            return consume;
        },
        else => return consume,
    }
}

inline fn parseGround(input: []const u8) ParseResult {
    std.debug.assert(input.len > 0);

    const b = input[0];
    var n: usize = 1;

    switch (b) {
        0x00 => {},
        0x08 => {},
        0x09 => {},
        0x0A => {},
        0x0D => {},
        0x01...0x07,
        0x0B...0x0C,
        0x0E...0x1A,
        => {},
        0x1B => {},
        0x7F => {},
        else => {
            var iter = uucode.utf8.Iterator.init(input);
            // return null if we don't have a valid codepoint
            const first_cp = iter.next() orelse return .consume(n);

            n = std.unicode.utf8CodepointSequenceLength(first_cp) catch return .consume(n);

            // Check if we have a multi-codepoint grapheme
            var grapheme_iter = uucode.grapheme.Iterator(uucode.utf8.Iterator).init(.init(input));
            var grapheme_len: usize = 0;
            var cp_count: usize = 0;

            while (grapheme_iter.next()) |result| {
                cp_count += 1;
                if (result.is_break) {
                    // Found the first grapheme boundary
                    grapheme_len = grapheme_iter.i;
                    break;
                }
            }

            if (grapheme_len > 0) {
                n = grapheme_len;
            }
        },
    }

    return .consume(n);
}

/// Parse a param buffer, returning a default value if the param was empty
inline fn parseParam(comptime T: type, buf: []const u8, default: ?T) ?T {
    if (buf.len == 0) return default;
    return std.fmt.parseInt(T, buf, 10) catch return null;
}

const testing = std.testing;

test "parse(csi): primary da" {
    var caps = TerminalCapabilities{};
    const input = "\x1b[?c";
    const result = parse(input, &caps);
    const expected: ParseResult = .{
        .n = input.len,
        .done = true,
    };

    try testing.expectEqual(expected, result);
    try testing.expectEqual(TerminalCapabilities{}, caps);
}

fn testDECRPM(pd: usize, supported_caps: TerminalCapabilities) !void {
    {
        var caps = TerminalCapabilities{};
        const input = try std.fmt.allocPrint(testing.allocator, ctlseqs.CSI ++ "?{d};0$y", .{pd});
        defer testing.allocator.free(input);

        const result = parse(input, &caps);
        const expected: ParseResult = .consume(input.len);

        try testing.expectEqual(expected, result);
        try testing.expectEqual(TerminalCapabilities{}, caps);
    }
    {
        var caps = TerminalCapabilities{};
        const input = try std.fmt.allocPrint(testing.allocator, ctlseqs.CSI ++ "?{d};1$y", .{pd});
        defer testing.allocator.free(input);

        const result = parse(input, &caps);
        const expected: ParseResult = .consume(input.len);

        try testing.expectEqual(expected, result);
        try testing.expectEqual(supported_caps, caps);
    }
    {
        var caps = TerminalCapabilities{};
        const input = try std.fmt.allocPrint(testing.allocator, ctlseqs.CSI ++ "?{d};2$y", .{pd});
        defer testing.allocator.free(input);

        const result = parse(input, &caps);
        const expected: ParseResult = .consume(input.len);

        try testing.expectEqual(expected, result);
        try testing.expectEqual(supported_caps, caps);
    }
    {
        var caps = TerminalCapabilities{};
        const input = try std.fmt.allocPrint(testing.allocator, ctlseqs.CSI ++ "?{d};3$y", .{pd});
        defer testing.allocator.free(input);

        const result = parse(input, &caps);
        const expected: ParseResult = .consume(input.len);

        try testing.expectEqual(expected, result);
        try testing.expectEqual(supported_caps, caps);
    }
    {
        var caps = TerminalCapabilities{};
        const input = try std.fmt.allocPrint(testing.allocator, ctlseqs.CSI ++ "?{d};4$y", .{pd});
        defer testing.allocator.free(input);

        const result = parse(input, &caps);
        const expected: ParseResult = .consume(input.len);

        try testing.expectEqual(expected, result);
        try testing.expectEqual(TerminalCapabilities{}, caps);
    }
}

test "parse(DECRQM): Focus Events" {
    try testDECRPM(1004, .{ .focus = true });
}

test "parse(DECRQM): SGR Pixels" {
    try testDECRPM(1016, .{ .sgr_pixels = true });
}

test "parse(DECRQM): Synchronized Output" {
    try testDECRPM(2026, .{ .sync = true });
}

test "parse(DECRQM): Unicode Core" {
    try testDECRPM(2027, .{ .unicode_width_method = .unicode });
}

test "parse(DECRQM): Color scheme Updates" {
    try testDECRPM(2031, .{ .color_scheme_updates = true });
}

test "parse(DECRQM): In-Band Window Resize Notifications" {
    try testDECRPM(2048, .{ .in_band_winsize = true });
}

test "parse(CSI): Explicit Width" {
    var caps = TerminalCapabilities{};
    const input = ctlseqs.CSI ++ "1;2R";
    const result = parse(input, &caps);
    const expected: ParseResult = .consume(input.len);

    try testing.expectEqual(expected, result);
    try testing.expect(caps.explicit_width);
}

test "parse(CSI): Scaled Text" {
    var caps = TerminalCapabilities{};
    const input = ctlseqs.CSI ++ "1;3R";
    const result = parse(input, &caps);
    const expected: ParseResult = .consume(input.len);

    try testing.expectEqual(expected, result);
    try testing.expect(caps.scaled_text);
}

test "parse(CSI): kitty multi cursor" {
    {
        var caps = TerminalCapabilities{};
        const input = ctlseqs.CSI ++ ">1;2;3;29;30;40;100;101 q";
        const result = parse(input, &caps);
        const expected: ParseResult = .consume(input.len);

        try testing.expectEqual(expected, result);
        try testing.expectEqual(KittyMultiCursorFlags{
            .block = true,
            .beam = true,
            .underline = true,
            .follow_main_cursor = true,
            .change_color_of_text_under_extra_cursors = true,
            .change_color_of_extra_cursors = true,
            .query_currently_set_cursors = true,
            .query_currently_set_cursor_colors = true,
        }, caps.multi_cursor.?);
    }
    {
        var caps = TerminalCapabilities{};
        const input = ctlseqs.CSI ++ "> q";
        const result = parse(input, &caps);
        const expected: ParseResult = .consume(input.len);

        try testing.expectEqual(expected, result);
        try testing.expectEqual(KittyMultiCursorFlags{}, caps.multi_cursor);
    }
}

test "parse(CSI): Kitty Keyboard Protocol" {
    {
        var caps = TerminalCapabilities{};
        const input = ctlseqs.CSI ++ "?31u";
        const result = parse(input, &caps);
        const expected: ParseResult = .consume(input.len);

        try testing.expectEqual(expected, result);
        try testing.expectEqual(KittyKeyboardFlags{
            .disambiguate = true,
            .report_events = true,
            .report_alternate_keys = true,
            .report_all_as_ctl_seqs = true,
            .report_text = true,
        }, caps.kitty_keyboard.?);
    }
    {
        var caps = TerminalCapabilities{};
        const input = ctlseqs.CSI ++ "?0u";
        const result = parse(input, &caps);
        const expected: ParseResult = .consume(input.len);

        try testing.expectEqual(expected, result);
        try testing.expectEqual(KittyKeyboardFlags{}, caps.kitty_keyboard.?);
    }
}

test "parse(APC): Kitty Graphics Protocol" {
    {
        var caps = TerminalCapabilities{};
        const input = ctlseqs.APC ++ "Gi=1;OK" ++ ctlseqs.ST;
        const result = parse(input, &caps);
        const expected: ParseResult = .consume(input.len);

        try testing.expectEqual(expected, result);
        try testing.expect(caps.kitty_graphics);
    }

    {
        var caps = TerminalCapabilities{};
        const input = ctlseqs.APC ++ "Gi=1;ENOTSUPPORTED:Kitty Graphics Protocol is not support in version ..." ++ ctlseqs.ST;
        const result = parse(input, &caps);
        const expected: ParseResult = .consume(input.len);

        try testing.expectEqual(expected, result);
        try testing.expect(!caps.kitty_graphics);
    }
}
