const std = @import("std");
const builin = @import("builtin");
const uucode = @import("uucode");
const zigwin = @import("zigwin");
const winconsole = zigwin.system.console;

const ctlseqs = @import("ctlseqs.zig");
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

sync: bool = false,
focus: bool = false,
kitty_keyboard: bool = false,
kitty_graphics: bool = false,
rgb: bool = false,
smulx: bool = false,
unicode_width_method: gwidth.Method = .wcwidth,
sgr_pixels: bool = false,
color_scheme_updates: bool = false,
explicit_width: bool = false,
scaled_text: bool = false,
multi_cursor: bool = false,

/// Queries the terminal capabilities and blocks, until primary device attributes response is found.
pub fn query(stdin: std.fs.File, stdout: std.fs.File) error{ NoTty, ReadFailed, WriteFailed, EndOfStream }!TerminalCapabilities {
    try sendQuery(stdout);
    return parseQueryResponses(stdin);
}

pub fn sendQuery(stdout: std.fs.File) error{ NoTty, WriteFailed }!void {
    if (!stdout.isTty()) return error.NoTty;

    var writer_buf: [32]u8 = undefined;
    var _writer = stdout.writer(&writer_buf);
    const writer = &_writer.interface;

    const queries = ctlseqs.Queries;

    try writer.writeAll(ctlseqs.Screen.save ++
        ctlseqs.Cursor.save_position);

    try writer.writeAll(queries.decrqm_focus ++
        queries.decrqm_sync ++
        queries.decrqm_sgr_pixels ++
        queries.decrqm_unicode ++
        queries.decrqm_color_scheme ++
        ctlseqs.Terminal.in_band_resize_set ++
        ctlseqs.Terminal.braketed_paste_set ++

        // Explicit width query. We send the cursor home, then do an explicit width command, then
        // query the position. If the parsed value is an F3 with shift, we support explicit width.
        // The returned response will be something like \x1b[1;2R...which when parsed as a Key is a
        // shift + F3 (the row is ignored). We only care if the column has moved from 1->2, which is
        // why we see a Shift modifier
        ctlseqs.Cursor.home ++
        queries.explicit_width_query ++
        queries.cursor_position_request ++

        // Explicit width query. We send the cursor home, then do an scaled text command, then
        // query the position. If the parsed value is an F3 with al, we support scaled text.
        // The returned response will be something like \x1b[1;3R...which when parsed as a Key is a
        // alt + F3 (the row is ignored). We only care if the column has moved from 1->3, which is
        // why we see a Shift modifier
        ctlseqs.Cursor.home ++
        queries.scaled_text_query ++
        queries.cursor_position_request ++
        queries.multi_cursor_query ++
        // queries.xtversion ++
        queries.kitty_keyboard_query ++
        queries.kitty_graphics_query ++
        queries.primary_device_attrs);

    try writer.writeAll(ctlseqs.Screen.restore ++
        ctlseqs.Cursor.restore_position);

    try writer.flush();
}

//TODO: maybe add timeout
/// Will block until the primary device attributes are found.
/// Recommended to use `query()`.
pub fn parseQueryResponses(stdin: std.fs.File) error{ ReadFailed, EndOfStream }!TerminalCapabilities {
    var reader_buf: [32]u8 = undefined;
    var _reader = stdin.reader(&reader_buf);
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

    var buf: [128]u8 = undefined;
    var i: usize = 0;
    while (true) {
        const byte = try reader.takeByte();
        buf[i] = byte;
        i += 1;
        // if (byte == ctlseqs.ESC[0]) {
        //     std.debug.print("b: <ESC>\n", .{});
        // } else {
        //     std.debug.print("b: {d} - '{c}'\n", .{ byte, byte });
        // }

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

    pub fn skip(n: usize) ParseResult {
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
            'O' => return parseSs3(input),
            'P' => return skipUntilST(input), // DCS
            'X' => return skipUntilST(input), // SOS
            '[' => return parseCsi(input, caps),
            ']' => return parseOsc(input),
            '^' => return skipUntilST(input), // PM
            '_' => return parseApc(input, caps),
            else => {
                return .skip(2);
            },
        }
    } else return parseGround(input);
}

inline fn parseSs3(input: []const u8) ParseResult {
    if (input.len < 3) return .none;
    if (input[2] == ctlseqs.ESC[0]) return .skip(2);
    return .skip(3);
}

inline fn skipUntilST(input: []const u8) ParseResult {
    if (input.len < 3) return .none;

    var chunker = std.mem.window(u8, input[2..], 2, 1);
    while (chunker.next()) |chunk| {
        if (chunk.len < 2) return .none;

        if (std.mem.eql(u8, chunk, ctlseqs.ST)) {
            const end = if (chunker.index) |index| index - 2 else input.len;
            return .skip(end);
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
    const skip: ParseResult = .skip(sequence.len);

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
                const modifier_mask = parseParam(u8, modifier_buf, 1) orelse return skip;
                mods = @bitCast(modifier_mask -| 1);
            }

            if (mods.shift) {
                caps.explicit_width = true;
                caps.unicode_width_method = .unicode;
            } else if (mods.alt) {
                caps.scaled_text = true;
            }

            return skip;
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
                else => return skip,
            }
        },
        'u' => {
            if (sequence.len > 2 and sequence[2] == '?') {
                caps.kitty_keyboard = true;
            }

            return skip;
        },
        'y' => {
            // DECRPM (CSI ? Ps ; Pm $ y)
            const delim_idx = std.mem.indexOfScalarPos(u8, input, 3, ';') orelse return skip;
            const ps = std.fmt.parseUnsigned(u16, input[3..delim_idx], 10) catch return skip;
            const pm = std.fmt.parseUnsigned(u8, input[delim_idx + 1 .. sequence.len - 2], 10) catch return skip;
            switch (ps) {
                // Focus
                1004 => switch (pm) {
                    0, 4 => return skip,
                    else => {
                        caps.focus = true;
                        return skip;
                    },
                },
                // Mouse Pixel reporting
                1016 => switch (pm) {
                    0, 4 => return skip,
                    else => {
                        caps.sgr_pixels = true;
                        return skip;
                    },
                },
                // Sync
                2026 => switch (pm) {
                    0, 4 => return skip,
                    else => {
                        caps.sync = true;
                        return skip;
                    },
                },
                // Unicode Core, see https://github.com/contour-terminal/terminal-unicode-core
                2027 => switch (pm) {
                    0, 4 => return skip,
                    else => {
                        caps.unicode_width_method = .unicode;
                        return skip;
                    },
                },
                // Color scheme reportnig, see https://github.com/contour-terminal/contour/blob/master/docs/vt-extensions/color-palette-update-notifications.md
                2031 => switch (pm) {
                    0, 4 => return skip,
                    else => {
                        caps.color_scheme_updates = true;
                        return skip;
                    },
                },
                else => return skip,
            }
        },
        'q' => {
            // kitty multi cursor cap (CSI > 1;2;3;29;30;40;100;101 TRAILER) (TRAILER is " q")
            const second_final = sequence[sequence.len - 2];
            if (second_final != ' ') return skip;
            // check for any digits. we're not too picky about checking the supported cursor types here
            for (sequence[0 .. sequence.len - 2]) |c| switch (c) {
                '0'...'9' => {
                    caps.multi_cursor = true;
                    return skip;
                },
                else => continue,
            };
            return skip;
        },
        else => return skip,
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

    return .skip(end);
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
    const skip: ParseResult = .skip(sequence.len);

    switch (input[2]) {
        'G' => {
            caps.kitty_graphics = true;
            return skip;
        },
        else => return skip,
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
            const first_cp = iter.next() orelse return .skip(n);

            n = std.unicode.utf8CodepointSequenceLength(first_cp) catch return .skip(n);

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

    return .skip(n);
}

/// Parse a param buffer, returning a default value if the param was empty
inline fn parseParam(comptime T: type, buf: []const u8, default: ?T) ?T {
    if (buf.len == 0) return default;
    return std.fmt.parseInt(T, buf, 10) catch return null;
}
