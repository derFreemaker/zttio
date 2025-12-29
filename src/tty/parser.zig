const std = @import("std");
const uucode = @import("uucode");
const common = @import("common");

const Color = common.Color;
const Event = common.Event;
const Key = common.Key;
const Mouse = common.Mouse;
const Winsize = common.Winsize;
const ctlseqs = common.cltseqs;

const log = std.log.scoped(.zttio_tty_parser);

const Parser = @This();

/// The return type of our parse method. Contains an Event and the number of
/// bytes read from the buffer.
pub const Result = struct {
    parse: Parse,
    n: usize,

    pub const none = Result{
        .parse = .none,
        .n = 0,
    };

    pub fn skip(n: usize) Result {
        return Result{
            .parse = .skip,
            .n = n,
        };
    }

    pub const Parse = union(enum) {
        none,
        skip,
        event: Event,

        paste_start,
        paste_end,

        // cap_kitty_graphics,
        // cap_kitty_keyboard,
        // cap_da1,
        // cap_sgr_pixels,
        // cap_unicode_width,
        // cap_color_scheme_updates,
        // cap_multi_cursor,
    };
};

const mouse_bits = struct {
    const motion: u8 = 0b00100000;
    const buttons: u8 = 0b11000011;
    const shift: u8 = 0b00000100;
    const alt: u8 = 0b00001000;
    const ctrl: u8 = 0b00010000;
    const leave: u16 = 0b100000000;
};

allocator: std.mem.Allocator,
buf: []u8,

pub fn init(allocator: std.mem.Allocator) Parser {
    return Parser{
        .allocator = allocator,
        .buf = &.{},
    };
}

pub fn deinit(self: *Parser) void {
    self.allocator.free(self.buf);
}

fn ensureCapacity(self: *Parser, minimum: usize) error{OutOfMemory}!void {
    if (self.buf.len >= minimum) {
        return;
    }

    const init_capacity = @as(comptime_int, @max(1, std.atomic.cache_line / @sizeOf(u8)));
    const new = blk: {
        var new = self.buf.len;
        while (true) {
            new +|= new / 2 + init_capacity;
            if (new >= minimum)
                break :blk new;
        }
    };

    const old_memory = self.buf;
    if (self.allocator.remap(old_memory, new)) |new_memory| {
        self.buf = new_memory;
    } else {
        const new_memory = try self.allocator.alignedAlloc(u8, std.mem.Alignment.of(u8), new);
        @memcpy(new_memory[0..self.buf.len], self.buf);
        self.allocator.free(old_memory);
        self.buf = new_memory;
    }
}

/// Parse the first event from the input buffer. If a completion event is not
/// present, Result.event will be null and Result.n will be 0
///
/// If an unknown event is found, Result.event will be null and Result.n will be
/// greater than 0
pub fn parse(self: *Parser, input: []const u8) !Result {
    std.debug.assert(input.len > 0);

    // We gate this for len > 1 so we can detect singular escape key presses
    if (input[0] == 0x1b and input.len > 1) {
        switch (input[1]) {
            'N' => return parseSs2(input),
            'O' => return parseSs3(input),
            'P' => return skipUntilST(input), // DCS
            'X' => return skipUntilST(input), // SOS
            '[' => return self.parseCsi(input),
            ']' => return self.parseOsc(input),
            '^' => return skipUntilST(input), // PM
            '_' => return skipUntilST(input), // APC
            else => {
                // Anything else is an "alt + <char>" keypress
                const key: Key = .{
                    .codepoint = input[1],
                    .mods = .{ .alt = true },
                };
                return .{
                    .parse = .{ .event = .{ .key_press = key } },
                    .n = 2,
                };
            },
        }
    } else return parseGround(input);
}

/// Parse ground state
fn parseGround(input: []const u8) !Result {
    std.debug.assert(input.len > 0);

    const b = input[0];
    var n: usize = 1;
    // ground state generates keypresses when parsing input. We
    // generally get ascii characters, but anything less than
    // 0x20 is a Ctrl+<c> keypress. We map these to lowercase
    // ascii characters when we can
    const key: Key = switch (b) {
        0x00 => .{ .codepoint = '@', .mods = .{ .ctrl = true } },
        0x08 => .{ .codepoint = Key.backspace },
        0x09 => .{ .codepoint = Key.tab },
        0x0A => .{ .codepoint = 'j', .mods = .{ .ctrl = true } },
        0x0D => .{ .codepoint = Key.enter },
        0x01...0x07,
        0x0B...0x0C,
        0x0E...0x1A,
        => .{ .codepoint = b + 0x60, .mods = .{ .ctrl = true } },
        0x1B => escape: {
            std.debug.assert(input.len == 1); // parseGround expects len == 1 with 0x1b
            break :escape .{
                .codepoint = Key.escape,
            };
        },
        0x7F => .{ .codepoint = Key.backspace },
        else => blk: {
            var iter = uucode.utf8.Iterator.init(input);
            // return null if we don't have a valid codepoint
            const first_cp = iter.next() orelse return error.InvalidUTF8;

            n = std.unicode.utf8CodepointSequenceLength(first_cp) catch return error.InvalidUTF8;

            // Check if we have a multi-codepoint grapheme
            var code = first_cp;
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
                if (cp_count > 1) {
                    code = Key.multicodepoint;
                }
            }

            break :blk .{ .codepoint = code, .text = input[0..n] };
        },
    };

    return .{
        .parse = .{ .event = .{ .key_press = key } },
        .n = n,
    };
}

fn parseSs2(input: []const u8) Result {
    if (input.len < 3) return .none;

    if (input[2] == 0x1B) return .skip(2);
    return .skip(3);
}

fn parseSs3(input: []const u8) Result {
    if (input.len < 3) return .none;

    const key: Key = switch (input[2]) {
        0x1B => return .skip(2),
        'A' => .{ .codepoint = Key.up },
        'B' => .{ .codepoint = Key.down },
        'C' => .{ .codepoint = Key.right },
        'D' => .{ .codepoint = Key.left },
        'E' => .{ .codepoint = Key.kp_begin },
        'F' => .{ .codepoint = Key.end },
        'H' => .{ .codepoint = Key.home },
        'P' => .{ .codepoint = Key.f1 },
        'Q' => .{ .codepoint = Key.f2 },
        'R' => .{ .codepoint = Key.f3 },
        'S' => .{ .codepoint = Key.f4 },
        else => {
            return .skip(3);
        },
    };
    return .{
        .parse = .{ .event = .{ .key_press = key } },
        .n = 3,
    };
}

/// Skips sequences until we see an ST (String Terminator, ESC \)
fn skipUntilST(input: []const u8) Result {
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

/// Parses an OSC sequence
fn parseOsc(self: *Parser, input: []const u8) !Result {
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
    const sequence = input[0..end];

    const null_event: Result = .skip(sequence.len);

    const semicolon_idx = std.mem.indexOfScalarPos(u8, input, 2, ';') orelse return null_event;
    const ps = std.fmt.parseUnsigned(u8, input[2..semicolon_idx], 10) catch return null_event;

    switch (ps) {
        4 => {
            const color_idx_delim = std.mem.indexOfScalarPos(u8, input, semicolon_idx + 1, ';') orelse return null_event;
            const ps_idx = std.fmt.parseUnsigned(u8, input[semicolon_idx + 1 .. color_idx_delim], 10) catch return null_event;
            const color_spec = if (bel_terminated)
                input[color_idx_delim + 1 .. sequence.len - 1]
            else
                input[color_idx_delim + 1 .. sequence.len - 2];

            const color = try Color.rgbFromSpec(color_spec);
            const event: Color.Report = .{
                .kind = .{ .index = ps_idx },
                .color = color,
            };
            return .{
                .parse = .{ .event = .{ .color_report = event } },
                .n = sequence.len,
            };
        },
        10,
        11,
        12,
        => {
            const color_spec = if (bel_terminated)
                input[semicolon_idx + 1 .. sequence.len - 1]
            else
                input[semicolon_idx + 1 .. sequence.len - 2];

            const color = try Color.rgbFromSpec(color_spec);
            const event: Color.Report = .{
                .kind = switch (ps) {
                    10 => .fg,
                    11 => .bg,
                    12 => .cursor,
                    else => unreachable,
                },
                .color = color,
            };
            return .{
                .parse = .{ .event = .{ .color_report = event } },
                .n = sequence.len,
            };
        },
        52 => {
            if (input[semicolon_idx + 1] != 'c') return null_event;
            const payload = if (bel_terminated)
                input[semicolon_idx + 3 .. sequence.len - 1]
            else
                input[semicolon_idx + 3 .. sequence.len - 2];
            const decoder = std.base64.standard.Decoder;
            const payload_size = try decoder.calcSizeForSlice(payload);
            try self.ensureCapacity(payload_size);
            const text = self.buf[0..payload_size];

            try decoder.decode(text, payload);
            log.debug("decoded paste: {s}", .{text});

            return .{
                .parse = .{ .event = .{ .paste = text } },
                .n = sequence.len,
            };
        },
        else => return null_event,
    }
}

fn parseCsi(self: *Parser, input: []const u8) error{OutOfMemory}!Result {
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
    const null_event: Result = .skip(sequence.len);

    const final = sequence[sequence.len - 1];
    switch (final) {
        'A', 'B', 'C', 'D', 'E', 'F', 'H', 'P', 'Q', 'R', 'S' => {
            // Legacy keys
            // CSI {ABCDEFHPQS}
            // CSI 1 ; modifier:event_type {ABCDEFHPQS}

            // Split first into fields delimited by ';'
            var field_iter = std.mem.splitScalar(u8, sequence[2 .. sequence.len - 1], ';');

            // skip the first field
            _ = field_iter.next(); //

            var is_release: bool = false;
            var key: Key = .{
                .codepoint = switch (final) {
                    'A' => Key.up,
                    'B' => Key.down,
                    'C' => Key.right,
                    'D' => Key.left,
                    'E' => Key.kp_begin,
                    'F' => Key.end,
                    'H' => Key.home,
                    'P' => Key.f1,
                    'Q' => Key.f2,
                    'R' => Key.f3,
                    'S' => Key.f4,
                    else => return null_event,
                },
            };

            field2: {
                // modifier_mask:event_type
                const field_buf = field_iter.next() orelse break :field2;
                var param_iter = std.mem.splitScalar(u8, field_buf, ':');
                const modifier_buf = param_iter.next() orelse unreachable;
                const modifier_mask = parseParam(u8, modifier_buf, 1) orelse return null_event;
                key.mods = @bitCast(modifier_mask -| 1);

                if (param_iter.next()) |event_type_buf| {
                    is_release = std.mem.eql(u8, event_type_buf, "3");
                }
            }

            field3: {
                // text_as_codepoint[:text_as_codepoint]
                const field_buf = field_iter.next() orelse break :field3;
                var param_iter = std.mem.splitScalar(u8, field_buf, ':');
                var total: usize = 0;
                while (param_iter.next()) |cp_buf| {
                    const cp = parseParam(u21, cp_buf, null) orelse return null_event;
                    try self.ensureCapacity(total + 4);
                    total += std.unicode.utf8Encode(cp, self.buf[total..]) catch return null_event;
                }
                key.text = self.buf[0..total];
            }

            const event: Event = if (is_release) .{ .key_release = key } else .{ .key_press = key };
            return .{
                .parse = .{ .event = event },
                .n = sequence.len,
            };
        },
        '~' => {
            // Legacy keys
            // CSI number ~
            // CSI number ; modifier ~
            // CSI number ; modifier:event_type ; text_as_codepoint ~
            var field_iter = std.mem.splitScalar(u8, sequence[2 .. sequence.len - 1], ';');
            const number_buf = field_iter.next() orelse unreachable; // always will have one field
            const number = parseParam(u16, number_buf, null) orelse return null_event;

            var key: Key = .{
                .codepoint = switch (number) {
                    2 => Key.insert,
                    3 => Key.delete,
                    5 => Key.page_up,
                    6 => Key.page_down,
                    7 => Key.home,
                    8 => Key.end,
                    11 => Key.f1,
                    12 => Key.f2,
                    13 => Key.f3,
                    14 => Key.f4,
                    15 => Key.f5,
                    17 => Key.f6,
                    18 => Key.f7,
                    19 => Key.f8,
                    20 => Key.f9,
                    21 => Key.f10,
                    23 => Key.f11,
                    24 => Key.f12,
                    200 => return .{ .parse = .paste_start, .n = sequence.len },
                    201 => return .{ .parse = .paste_end, .n = sequence.len },
                    57427 => Key.kp_begin,
                    else => return null_event,
                },
            };

            var is_release: bool = false;
            field2: {
                // modifier_mask:event_type
                const field_buf = field_iter.next() orelse break :field2;
                var param_iter = std.mem.splitScalar(u8, field_buf, ':');
                const modifier_buf = param_iter.next() orelse unreachable;
                const modifier_mask = parseParam(u8, modifier_buf, 1) orelse return null_event;
                key.mods = @bitCast(modifier_mask -| 1);

                if (param_iter.next()) |event_type_buf| {
                    is_release = std.mem.eql(u8, event_type_buf, "3");
                }
            }

            field3: {
                // text_as_codepoint[:text_as_codepoint]
                const field_buf = field_iter.next() orelse break :field3;
                var param_iter = std.mem.splitScalar(u8, field_buf, ':');
                var total: usize = 0;
                while (param_iter.next()) |cp_buf| {
                    const cp = parseParam(u21, cp_buf, null) orelse return null_event;
                    try self.ensureCapacity(total + 4);
                    total += std.unicode.utf8Encode(cp, self.buf[total..]) catch return null_event;
                }
                key.text = self.buf[0..total];
            }

            const event: Event = if (is_release) .{ .key_release = key } else .{ .key_press = key };
            return .{
                .parse = .{ .event = event },
                .n = sequence.len,
            };
        },

        'I' => return .{ .parse = .{ .event = .focus_in }, .n = sequence.len },
        'O' => return .{ .parse = .{ .event = .focus_out }, .n = sequence.len },
        'M', 'm' => return parseMouse(sequence, input),
        'n' => {
            // Device Status Report
            // CSI Ps n
            // CSI ? Ps n
            std.debug.assert(sequence.len >= 3);
            switch (sequence[2]) {
                '?' => {
                    const delim_idx = std.mem.indexOfScalarPos(u8, input, 3, ';') orelse return null_event;
                    const ps = std.fmt.parseUnsigned(u16, input[3..delim_idx], 10) catch return null_event;
                    switch (ps) {
                        997 => {
                            // Color scheme update (CSI 997 ; Ps n)
                            // See https://github.com/contour-terminal/contour/blob/master/docs/vt-extensions/color-palette-update-notifications.md
                            switch (sequence[delim_idx + 1]) {
                                '1' => return .{
                                    .parse = .{ .event = .{ .color_scheme = .dark } },
                                    .n = sequence.len,
                                },
                                '2' => return .{
                                    .parse = .{ .event = .{ .color_scheme = .light } },
                                    .n = sequence.len,
                                },
                                else => return null_event,
                            }
                        },
                        else => return null_event,
                    }
                },
                else => return null_event,
            }
        },
        't' => {
            // XTWINOPS (https://gist.github.com/rockorager/e695fb2924d36b2bcf1fff4a3704bd83)
            // Split first into fields delimited by ';'
            var iter = std.mem.splitScalar(u8, sequence[2 .. sequence.len - 1], ';');
            const ps = iter.first();
            if (std.mem.eql(u8, "48", ps)) {
                // in band window resize
                // CSI 48 ; height ; width ; height_pix ; width_pix t
                const height_char = iter.next() orelse return null_event;
                const width_char = iter.next() orelse return null_event;
                const height_pix = iter.next() orelse "0";
                const width_pix = iter.next() orelse "0";

                const winsize: Winsize = .{
                    .rows = std.fmt.parseUnsigned(u16, height_char, 10) catch return null_event,
                    .cols = std.fmt.parseUnsigned(u16, width_char, 10) catch return null_event,
                    .x_pixel = std.fmt.parseUnsigned(u16, width_pix, 10) catch return null_event,
                    .y_pixel = std.fmt.parseUnsigned(u16, height_pix, 10) catch return null_event,
                };
                return .{
                    .parse = .{ .event = .{ .winsize = winsize } },
                    .n = sequence.len,
                };
            }
            return null_event;
        },
        'u' => {
            // Kitty keyboard
            // CSI unicode-key-code:alternate-key-codes ; modifiers:event-type ; text-as-codepoints u
            // Not all fields will be present. Only unicode-key-code is
            // mandatory

            // ignore the capability response
            if (sequence.len > 2 and sequence[2] == '?') return null_event;

            var key: Key = .{
                .codepoint = undefined,
            };
            // Split first into fields delimited by ';'
            var field_iter = std.mem.splitScalar(u8, sequence[2 .. sequence.len - 1], ';');

            { // field 1
                // unicode-key-code:shifted_codepoint:base_layout_codepoint
                const field_buf = field_iter.next() orelse unreachable; // There will always be at least one field
                var param_iter = std.mem.splitScalar(u8, field_buf, ':');
                const codepoint_buf = param_iter.next() orelse unreachable;
                key.codepoint = parseParam(u21, codepoint_buf, null) orelse return null_event;

                if (param_iter.next()) |shifted_cp_buf| {
                    key.shifted_codepoint = parseParam(u21, shifted_cp_buf, null);
                }
                if (param_iter.next()) |base_layout_buf| {
                    key.base_layout_codepoint = parseParam(u21, base_layout_buf, null);
                }
            }

            var is_release: bool = false;

            field2: {
                // modifier_mask:event_type
                const field_buf = field_iter.next() orelse break :field2;
                var param_iter = std.mem.splitScalar(u8, field_buf, ':');
                const modifier_buf = param_iter.next() orelse unreachable;
                const modifier_mask = parseParam(u8, modifier_buf, 1) orelse return null_event;
                key.mods = @bitCast(modifier_mask -| 1);

                if (param_iter.next()) |event_type_buf| {
                    is_release = std.mem.eql(u8, event_type_buf, "3");
                }
            }

            field3: {
                // text_as_codepoint[:text_as_codepoint]
                const field_buf = field_iter.next() orelse break :field3;
                var param_iter = std.mem.splitScalar(u8, field_buf, ':');
                var total: usize = 0;
                while (param_iter.next()) |cp_buf| {
                    const cp = parseParam(u21, cp_buf, null) orelse return null_event;
                    try self.ensureCapacity(total + 4);
                    total += std.unicode.utf8Encode(cp, self.buf[total..]) catch return null_event;
                }
                key.text = self.buf[0..total];
            }

            {
                // We check if we have *only* shift, no text, and a printable character. This can
                // happen when we have disambiguate on and a key is pressed and encoded as CSI u,
                // for example shift + space can produce CSI 32 ; 2 u
                const mod_test: Key.Modifiers = .{
                    .shift = true,
                    .caps_lock = key.mods.caps_lock,
                    .num_lock = key.mods.num_lock,
                };
                if (key.text == null and
                    key.mods.eql(mod_test) and
                    key.codepoint <= std.math.maxInt(u8) and
                    std.ascii.isPrint(@intCast(key.codepoint)))
                {
                    // Encode the codepoint as upper
                    const upper = std.ascii.toUpper(@intCast(key.codepoint));
                    try self.ensureCapacity(4);
                    const n = std.unicode.utf8Encode(upper, self.buf) catch unreachable;
                    key.text = self.buf[0..n];
                    key.shifted_codepoint = upper;
                }
            }

            const event: Event = if (is_release)
                .{ .key_release = key }
            else
                .{ .key_press = key };

            return .{ .parse = .{ .event = event }, .n = sequence.len };
        },
        else => return null_event,
    }
}

/// Parse a param buffer, returning a default value if the param was empty
inline fn parseParam(comptime T: type, buf: []const u8, default: ?T) ?T {
    if (buf.len == 0) return default;
    return std.fmt.parseInt(T, buf, 10) catch return null;
}

/// Parse a mouse event
inline fn parseMouse(input: []const u8, full_input: []const u8) Result {
    const null_event: Result = .skip(input.len);

    var button_mask: u16 = undefined;
    var px: i16 = undefined;
    var py: i16 = undefined;
    var xterm: bool = undefined;
    if (input.len == 3 and input[2] == 'M' and full_input.len >= 6) {
        xterm = true;
        button_mask = full_input[3] - 32;
        px = full_input[4] - 32;
        py = full_input[5] - 32;
    } else if (input.len >= 4 and input[2] == '<') {
        xterm = false;
        const delim1 = std.mem.indexOfScalarPos(u8, input, 3, ';') orelse return null_event;
        button_mask = parseParam(u16, input[3..delim1], null) orelse return null_event;
        const delim2 = std.mem.indexOfScalarPos(u8, input, delim1 + 1, ';') orelse return null_event;
        px = parseParam(i16, input[delim1 + 1 .. delim2], 1) orelse return null_event;
        py = parseParam(i16, input[delim2 + 1 .. input.len - 1], 1) orelse return null_event;
    } else {
        return null_event;
    }

    if (button_mask & mouse_bits.leave > 0)
        return .{ .parse = .{ .event = .mouse_leave }, .n = if (xterm) 6 else input.len };

    const button: Mouse.Button = @enumFromInt(button_mask & mouse_bits.buttons);
    const motion = button_mask & mouse_bits.motion > 0;
    const shift = button_mask & mouse_bits.shift > 0;
    const alt = button_mask & mouse_bits.alt > 0;
    const ctrl = button_mask & mouse_bits.ctrl > 0;

    const mouse = Mouse{
        .button = button,
        .mods = .{
            .shift = shift,
            .alt = alt,
            .ctrl = ctrl,
        },
        .col = px -| 1,
        .row = py -| 1,
        .type = blk: {
            if (motion and button != Mouse.Button.none) {
                break :blk .drag;
            }
            if (motion and button == Mouse.Button.none) {
                break :blk .motion;
            }
            if (xterm) {
                if (button == Mouse.Button.none) {
                    break :blk .release;
                }
                break :blk .press;
            }
            if (input[input.len - 1] == 'm') break :blk .release;
            break :blk .press;
        },
    };
    return .{ .parse = .{ .event = .{ .mouse = mouse } }, .n = if (xterm) 6 else input.len };
}

const testing = std.testing;

test "parse: single xterm keypress" {
    const alloc = testing.allocator_instance.allocator();
    const input = "a";
    var parser: Parser = .init(alloc);
    defer parser.deinit();
    const result = try parser.parse(input);
    const expected_key: Key = .{
        .codepoint = 'a',
        .text = "a",
    };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(1, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse: single xterm keypress backspace" {
    const alloc = testing.allocator_instance.allocator();
    const input = "\x08";
    var parser: Parser = .init(alloc);
    defer parser.deinit();
    const result = try parser.parse(input);
    const expected_key: Key = .{
        .codepoint = Key.backspace,
    };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(1, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse: single xterm keypress with more buffer" {
    const alloc = testing.allocator_instance.allocator();
    const input = "ab";
    var parser: Parser = .init(alloc);
    defer parser.deinit();
    const result = try parser.parse(input);
    const expected_key: Key = .{
        .codepoint = 'a',
        .text = "a",
    };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(1, result.n);
    try testing.expectEqualStrings(expected_key.text.?, result.parse.event.key_press.text.?);
    try testing.expectEqualDeep(expected_event, result.parse.event);
}

test "parse: xterm escape keypress" {
    const alloc = testing.allocator_instance.allocator();
    const input = "\x1b";
    var parser: Parser = .init(alloc);
    defer parser.deinit();
    const result = try parser.parse(input);
    const expected_key: Key = .{ .codepoint = Key.escape };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(1, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse: xterm ctrl+a" {
    const alloc = testing.allocator_instance.allocator();
    const input = "\x01";
    var parser: Parser = .init(alloc);
    defer parser.deinit();
    const result = try parser.parse(input);
    const expected_key: Key = .{ .codepoint = 'a', .mods = .{ .ctrl = true } };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(1, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse: xterm alt+a" {
    const alloc = testing.allocator_instance.allocator();
    const input = "\x1ba";
    var parser: Parser = .init(alloc);
    defer parser.deinit();
    const result = try parser.parse(input);
    const expected_key: Key = .{ .codepoint = 'a', .mods = .{ .alt = true } };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(2, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse: xterm key up" {
    const alloc = testing.allocator_instance.allocator();
    {
        // normal version
        const input = "\x1b[A";
        var parser: Parser = .init(alloc);
        defer parser.deinit();
        const result = try parser.parse(input);
        const expected_key: Key = .{ .codepoint = Key.up };
        const expected_event: Event = .{ .key_press = expected_key };

        try testing.expectEqual(3, result.n);
        try testing.expectEqual(expected_event, result.parse.event);
    }

    {
        // application keys version
        const input = "\x1bOA";
        var parser: Parser = .init(alloc);
        defer parser.deinit();
        const result = try parser.parse(input);
        const expected_key: Key = .{ .codepoint = Key.up };
        const expected_event: Event = .{ .key_press = expected_key };

        try testing.expectEqual(3, result.n);
        try testing.expectEqual(expected_event, result.parse.event);
    }
}

test "parse: xterm shift+up" {
    const alloc = testing.allocator_instance.allocator();
    const input = "\x1b[1;2A";
    var parser: Parser = .init(alloc);
    defer parser.deinit();
    const result = try parser.parse(input);
    const expected_key: Key = .{ .codepoint = Key.up, .mods = .{ .shift = true } };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(6, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse: xterm insert" {
    const alloc = testing.allocator_instance.allocator();
    const input = "\x1b[2~";
    var parser: Parser = .init(alloc);
    defer parser.deinit();
    const result = try parser.parse(input);
    const expected_key: Key = .{ .codepoint = Key.insert, .mods = .{} };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(input.len, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse: paste_start" {
    const alloc = testing.allocator_instance.allocator();
    const input = "\x1b[200~";
    var parser: Parser = .init(alloc);
    defer parser.deinit();
    const result = try parser.parse(input);
    const expected: Result.Parse = .paste_start;

    try testing.expectEqual(6, result.n);
    try testing.expectEqual(expected, result.parse);
}

test "parse: paste_end" {
    const alloc = testing.allocator_instance.allocator();
    const input = "\x1b[201~";
    var parser: Parser = .init(alloc);
    defer parser.deinit();
    const result = try parser.parse(input);
    const expected: Result.Parse = .paste_end;

    try testing.expectEqual(6, result.n);
    try testing.expectEqual(expected, result.parse);
}

test "parse: osc52 paste" {
    const alloc = testing.allocator_instance.allocator();
    const input = "\x1b]52;c;b3NjNTIgcGFzdGU=\x1b\\";
    const expected_text = "osc52 paste";
    var parser: Parser = .init(alloc);
    defer parser.deinit();
    const result = try parser.parse(input);

    try testing.expectEqual(25, result.n);
    switch (result.parse.event) {
        .paste => |text| {
            try testing.expectEqualStrings(expected_text, text);
        },
        else => try testing.expect(false),
    }
}

test "parse: focus_in" {
    const alloc = testing.allocator_instance.allocator();
    const input = "\x1b[I";
    var parser: Parser = .init(alloc);
    defer parser.deinit();
    const result = try parser.parse(input);
    const expected_event: Event = .focus_in;

    try testing.expectEqual(3, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse: focus_out" {
    const alloc = testing.allocator_instance.allocator();
    const input = "\x1b[O";
    var parser: Parser = .init(alloc);
    defer parser.deinit();
    const result = try parser.parse(input);
    const expected_event: Event = .focus_out;

    try testing.expectEqual(3, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse: kitty: shift+a without text reporting" {
    const alloc = testing.allocator_instance.allocator();
    const input = "\x1b[97:65;2u";
    var parser: Parser = .init(alloc);
    defer parser.deinit();
    const result = try parser.parse(input);
    const expected_key: Key = .{
        .codepoint = 'a',
        .shifted_codepoint = 'A',
        .mods = .{ .shift = true },
        .text = "A",
    };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(10, result.n);
    try testing.expectEqualDeep(expected_event, result.parse.event);
}

test "parse: kitty: alt+shift+a without text reporting" {
    const alloc = testing.allocator_instance.allocator();
    const input = "\x1b[97:65;4u";
    var parser: Parser = .init(alloc);
    defer parser.deinit();
    const result = try parser.parse(input);
    const expected_key: Key = .{
        .codepoint = 'a',
        .shifted_codepoint = 'A',
        .mods = .{ .shift = true, .alt = true },
    };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(10, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse: kitty: a without text reporting" {
    const alloc = testing.allocator_instance.allocator();
    const input = "\x1b[97u";
    var parser: Parser = .init(alloc);
    defer parser.deinit();
    const result = try parser.parse(input);
    const expected_key: Key = .{
        .codepoint = 'a',
    };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(5, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse: kitty: release event" {
    const alloc = testing.allocator_instance.allocator();
    const input = "\x1b[97;1:3u";
    var parser: Parser = .init(alloc);
    defer parser.deinit();
    const result = try parser.parse(input);
    const expected_key: Key = .{
        .codepoint = 'a',
    };
    const expected_event: Event = .{ .key_release = expected_key };

    try testing.expectEqual(9, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse: single codepoint" {
    const alloc = testing.allocator_instance.allocator();
    const input = "🙂";
    var parser: Parser = .init(alloc);
    defer parser.deinit();
    const result = try parser.parse(input);
    const expected_key: Key = .{
        .codepoint = 0x1F642,
        .text = input,
    };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(4, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse: single codepoint with more in buffer" {
    const alloc = testing.allocator_instance.allocator();
    const input = "🙂a";
    var parser: Parser = .init(alloc);
    defer parser.deinit();
    const result = try parser.parse(input);
    const expected_key: Key = .{
        .codepoint = 0x1F642,
        .text = "🙂",
    };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(4, result.n);
    try testing.expectEqualDeep(expected_event, result.parse.event);
}

test "parse: multiple codepoint grapheme" {
    const alloc = testing.allocator_instance.allocator();
    const input = "👩‍🚀";
    var parser: Parser = .init(alloc);
    defer parser.deinit();
    const result = try parser.parse(input);
    const expected_key: Key = .{
        .codepoint = Key.multicodepoint,
        .text = input,
    };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(input.len, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse: multiple codepoint grapheme with more after" {
    const alloc = testing.allocator_instance.allocator();
    const input = "👩‍🚀abc";
    var parser: Parser = .init(alloc);
    defer parser.deinit();
    const result = try parser.parse(input);
    const expected_key: Key = .{
        .codepoint = Key.multicodepoint,
        .text = "👩‍🚀",
    };

    try testing.expectEqual(expected_key.text.?.len, result.n);
    const actual = result.parse.event.key_press;
    try testing.expectEqualStrings(expected_key.text.?, actual.text.?);
    try testing.expectEqual(expected_key.codepoint, actual.codepoint);
}

test "parse: flag emoji" {
    const alloc = testing.allocator_instance.allocator();
    const input = "🇺🇸";
    var parser: Parser = .init(alloc);
    defer parser.deinit();
    const result = try parser.parse(input);
    const expected_key: Key = .{
        .codepoint = Key.multicodepoint,
        .text = input,
    };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(input.len, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse: combining mark" {
    const alloc = testing.allocator_instance.allocator();
    var parser: Parser = .init(alloc);
    defer parser.deinit();
    // a with combining acute accent (NFD form)
    const input = "a\u{0301}";
    const result = try parser.parse(input);
    const expected_key: Key = .{
        .codepoint = Key.multicodepoint,
        .text = input,
    };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(input.len, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse: skin tone emoji" {
    const alloc = testing.allocator_instance.allocator();
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = "👋🏿";
    const result = try parser.parse(input);
    const expected_key: Key = .{
        .codepoint = Key.multicodepoint,
        .text = input,
    };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(input.len, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse: text variation selector" {
    const alloc = testing.allocator_instance.allocator();
    // Heavy black heart with text variation selector
    const input = "❤︎";
    var parser: Parser = .init(alloc);
    defer parser.deinit();
    const result = try parser.parse(input);
    const expected_key: Key = .{
        .codepoint = Key.multicodepoint,
        .text = input,
    };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(input.len, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse: keycap sequence" {
    const alloc = testing.allocator_instance.allocator();
    const input = "1️⃣";
    var parser: Parser = .init(alloc);
    defer parser.deinit();
    const result = try parser.parse(input);
    const expected_key: Key = .{
        .codepoint = Key.multicodepoint,
        .text = input,
    };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(input.len, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse(csi): dsr" {
    const alloc = testing.allocator_instance.allocator();
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    {
        const input = "\x1b[?997;1n";
        const result = try parser.parseCsi(input);
        const expected: Result = .{
            .parse = .{ .event = .{ .color_scheme = .dark } },
            .n = input.len,
        };

        try testing.expectEqual(expected.n, result.n);
        try testing.expectEqual(expected.parse, result.parse);
    }
    {
        const input = "\x1b[?997;2n";
        const result = try parser.parseCsi(input);
        const expected: Result = .{
            .parse = .{ .event = .{ .color_scheme = .light } },
            .n = input.len,
        };

        try testing.expectEqual(expected.n, result.n);
        try testing.expectEqual(expected.parse, result.parse);
    }
    {
        const input = "\x1b[0n";
        const result = try parser.parseCsi(input);
        const expected: Result = .skip(input.len);

        try testing.expectEqual(expected.n, result.n);
        try testing.expectEqual(expected.parse, result.parse);
    }
}

test "parse(csi): mouse" {
    const alloc = testing.allocator_instance.allocator();
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = "\x1b[<35;1;1m";
    const result = try parser.parseCsi(input);
    const expected: Result = .{
        .parse = .{ .event = .{ .mouse = .{
            .col = 0,
            .row = 0,
            .button = .none,
            .type = .motion,
            .mods = .{},
        } } },
        .n = input.len,
    };

    try testing.expectEqual(expected.n, result.n);
    try testing.expectEqual(expected.parse, result.parse);
}

test "parse(csi): mouse (negative)" {
    const alloc = testing.allocator_instance.allocator();
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = "\x1b[<35;-50;-100m";
    const result = try parser.parseCsi(input);
    const expected: Result = .{
        .parse = .{ .event = .{ .mouse = .{
            .col = -51,
            .row = -101,
            .button = .none,
            .type = .motion,
            .mods = .{},
        } } },
        .n = input.len,
    };

    try testing.expectEqual(expected.n, result.n);
    try testing.expectEqual(expected.parse, result.parse);
}

test "parse(csi): xterm mouse (X10)" {
    const alloc = testing.allocator_instance.allocator();
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = "\x1b[M\x20\x21\x21";
    const result = try parser.parseCsi(input);
    const expected: Result = .{
        .parse = .{ .event = .{ .mouse = .{
            .col = 0,
            .row = 0,
            .button = .left,
            .type = .press,
            .mods = .{},
        } } },
        .n = input.len,
    };

    try testing.expectEqual(expected.n, result.n);
    try testing.expectEqual(expected.parse, result.parse);
}

test "parse(csi): mouse (URXVT)" {
    const alloc = testing.allocator_instance.allocator();
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = "\x1b[35;-50;100m";
    const result = try parser.parseCsi(input);
    const expected: Result = .skip(input.len);
    
    try testing.expectEqual(expected.n, result.n);
    try testing.expectEqual(expected.parse, result.parse);
}

test "parse: disambiguate shift + space" {
    const alloc = testing.allocator_instance.allocator();
    const input = "\x1b[32;2u";
    var parser: Parser = .init(alloc);
    defer parser.deinit();
    const result = try parser.parse(input);
    const expected_key: Key = .{
        .codepoint = ' ',
        .shifted_codepoint = ' ',
        .mods = .{ .shift = true },
        .text = " ",
    };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(7, result.n);
    try testing.expectEqualDeep(expected_event, result.parse.event);
}
