const std = @import("std");
const uucode = @import("uucode");
const common = @import("common");

const Color = common.Color;
const Event = common.Event;
const Key = common.Key;
const Mouse = common.Mouse;
const Winsize = common.Winsize;
const ctlseqs = common.ctlseqs;
const MultiCursor = ctlseqs.MultiCursor;
const KittyGraphics = ctlseqs.KittyGraphics;

const log = std.log.scoped(.zttio_tty_parser);

const Parser = @This();

arena: std.heap.ArenaAllocator,

pub fn init(allocator: std.mem.Allocator) Parser {
    return Parser{
        .arena = .init(allocator),
    };
}

pub fn deinit(self: *Parser) void {
    self.arena.deinit();
}

/// Parse the first event from the input buffer. If a completion event is not
/// present, Result.event will be null and Result.n will be 0
///
/// If an unknown event is found, Result.event will be null and Result.n will be
/// greater than 0
pub fn parse(self: *Parser, input: []const u8) !ParseResult {
    std.debug.assert(input.len > 0);

    // clear any used memory from previous ParseResult
    _ = self.arena.reset(.retain_capacity);

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
            '_' => return parseApc(input), // APC
            else => {
                // Anything else is an "alt + <char>" keypress
                const key: Key = .{
                    .codepoint = input[1],
                    .mods = .{ .alt = true },
                };
                return .event(2, Event{ .key_press = key });
            },
        }
    } else return parseNormal(input);
}

/// Parse ground state
fn parseNormal(input: []const u8) !ParseResult {
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

    return .event(n, Event{ .key_press = key });
}

fn parseSs2(input: []const u8) ParseResult {
    if (input.len < 3) return .none;

    if (input[2] == 0x1B) return .skip(2);
    return .skip(3);
}

fn parseSs3(input: []const u8) ParseResult {
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
    return .event(3, Event{ .key_press = key });
}

/// Skips sequences until we see an ST (String Terminator, ESC \)
fn skipUntilST(input: []const u8) ParseResult {
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
fn parseOsc(self: *Parser, input: []const u8) !ParseResult {
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

    const skip: ParseResult = .skip(sequence.len);

    const semicolon_idx = std.mem.indexOfScalarPos(u8, input, 2, ';') orelse return skip;
    const ps = std.fmt.parseUnsigned(u8, input[2..semicolon_idx], 10) catch return skip;

    switch (ps) {
        4 => {
            const color_idx_delim = std.mem.indexOfScalarPos(u8, input, semicolon_idx + 1, ';') orelse return skip;
            const ps_idx = std.fmt.parseUnsigned(u8, input[semicolon_idx + 1 .. color_idx_delim], 10) catch return skip;
            const color_spec = if (bel_terminated)
                input[color_idx_delim + 1 .. sequence.len - 1]
            else
                input[color_idx_delim + 1 .. sequence.len - 2];

            const color = try Color.rgbFromSpec(color_spec);
            const event: Color.Report = .{
                .kind = .{ .index = ps_idx },
                .color = color,
            };
            return .event(sequence.len, Event{ .color_report = event });
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
            return .event(sequence.len, Event{ .color_report = event });
        },
        52 => {
            if (input[semicolon_idx + 1] != 'c') return skip;
            const payload = if (bel_terminated)
                input[semicolon_idx + 3 .. sequence.len - 1]
            else
                input[semicolon_idx + 3 .. sequence.len - 2];
            const decoder = std.base64.standard.Decoder;
            const payload_size = try decoder.calcSizeForSlice(payload);

            const text = try self.arena.allocator().alloc(u8, payload_size);
            try decoder.decode(text, payload);
            log.debug("decoded paste: {s}", .{text});

            return .event(sequence.len, Event{ .paste = text });
        },
        else => return skip,
    }
}

fn parseCsi(self: *Parser, input: []const u8) error{OutOfMemory}!ParseResult {
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
                    else => return skip,
                },
            };

            field2: {
                // modifier_mask:event_type
                const field_buf = field_iter.next() orelse break :field2;
                var param_iter = std.mem.splitScalar(u8, field_buf, ':');
                const modifier_buf = param_iter.next() orelse unreachable;
                const modifier_mask = parseParam(u8, modifier_buf, 1) orelse return skip;
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
                var text_buf: std.ArrayList(u8) = .empty;
                while (param_iter.next()) |cp_buf| {
                    const cp = parseParam(u21, cp_buf, null) orelse return skip;
                    const cp_utf8_len = std.unicode.utf8CodepointSequenceLength(cp) catch unreachable;

                    const cp_text_buf = try text_buf.addManyAsSlice(self.arena.allocator(), cp_utf8_len);
                    total += std.unicode.utf8Encode(cp, cp_text_buf) catch return skip;
                }
                key.text = text_buf.items;
            }

            const event: Event = if (is_release) .{ .key_release = key } else .{ .key_press = key };
            return .event(sequence.len, event);
        },
        '~' => {
            // Legacy keys
            // CSI number ~
            // CSI number ; modifier ~
            // CSI number ; modifier:event_type ; text_as_codepoint ~
            var field_iter = std.mem.splitScalar(u8, sequence[2 .. sequence.len - 1], ';');
            const number_buf = field_iter.next() orelse unreachable; // always will have one field
            const number = parseParam(u16, number_buf, null) orelse return skip;

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
                    else => return skip,
                },
            };

            var is_release: bool = false;
            field2: {
                // modifier_mask:event_type
                const field_buf = field_iter.next() orelse break :field2;
                var param_iter = std.mem.splitScalar(u8, field_buf, ':');
                const modifier_buf = param_iter.next() orelse unreachable;
                const modifier_mask = parseParam(u8, modifier_buf, 1) orelse return skip;
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
                var text_buf: std.ArrayList(u8) = .empty;
                while (param_iter.next()) |cp_buf| {
                    const cp = parseParam(u21, cp_buf, null) orelse return skip;
                    const cp_utf8_len = std.unicode.utf8CodepointSequenceLength(cp) catch unreachable;

                    const cp_text_buf = try text_buf.addManyAsSlice(self.arena.allocator(), cp_utf8_len);
                    total += std.unicode.utf8Encode(cp, cp_text_buf) catch return skip;
                }
                key.text = text_buf.items;
            }

            const event: Event = if (is_release) .{ .key_release = key } else .{ .key_press = key };
            return .event(sequence.len, event);
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
                    const delim_idx = std.mem.indexOfScalarPos(u8, input, 3, ';') orelse return skip;
                    const ps = std.fmt.parseUnsigned(u16, input[3..delim_idx], 10) catch return skip;
                    switch (ps) {
                        997 => {
                            // Color scheme update (CSI 997 ; Ps n)
                            // See https://github.com/contour-terminal/contour/blob/master/docs/vt-extensions/color-palette-update-notifications.md
                            switch (sequence[delim_idx + 1]) {
                                '1' => return .event(sequence.len, Event{
                                    .color_scheme = .dark,
                                }),
                                '2' => return .event(sequence.len, Event{
                                    .color_scheme = .light,
                                }),
                                else => return skip,
                            }
                        },
                        else => return skip,
                    }
                },
                else => return skip,
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
                const height_char = iter.next() orelse return skip;
                const width_char = iter.next() orelse return skip;
                const height_pix = iter.next() orelse "0";
                const width_pix = iter.next() orelse "0";

                const winsize: Winsize = .{
                    .rows = std.fmt.parseUnsigned(u16, height_char, 10) catch return skip,
                    .cols = std.fmt.parseUnsigned(u16, width_char, 10) catch return skip,
                    .x_pixel = std.fmt.parseUnsigned(u16, width_pix, 10) catch return skip,
                    .y_pixel = std.fmt.parseUnsigned(u16, height_pix, 10) catch return skip,
                };

                return .event(sequence.len, Event{ .winsize = winsize });
            }
            return skip;
        },
        'u' => {
            // Kitty keyboard
            // CSI unicode-key-code:alternate-key-codes ; modifiers:event-type ; text-as-codepoints u
            // Not all fields will be present. Only unicode-key-code is
            // mandatory

            // ignore the capability response
            if (sequence.len > 2 and sequence[2] == '?') return skip;

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
                key.codepoint = parseParam(u21, codepoint_buf, null) orelse return skip;

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
                const modifier_mask = parseParam(u8, modifier_buf, 1) orelse return skip;
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
                var text_buf: std.ArrayList(u8) = .empty;
                while (param_iter.next()) |cp_buf| {
                    const cp = parseParam(u21, cp_buf, null) orelse return skip;
                    const cp_utf8_len = std.unicode.utf8CodepointSequenceLength(cp) catch unreachable;

                    const cp_text_buf = try text_buf.addManyAsSlice(self.arena.allocator(), cp_utf8_len);
                    total += std.unicode.utf8Encode(cp, cp_text_buf) catch return skip;
                }
                key.text = text_buf.items;
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
                    const text_buf = try self.arena.allocator().alloc(u8, std.unicode.utf8CodepointSequenceLength(upper) catch unreachable);
                    _ = std.unicode.utf8Encode(upper, text_buf) catch unreachable;

                    key.text = text_buf;
                    key.shifted_codepoint = upper;
                }
            }

            const event: Event = if (is_release)
                .{ .key_release = key }
            else
                .{ .key_press = key };

            return .event(sequence.len, event);
        },
        'q' => {
            // kitty multi cursor "CSI > ... TRAILER" (TRAILER is " q")
            // see https://sw.kovidgoyal.net/kitty/multiple-cursors-protocol/
            if (sequence[2] != '>' or sequence[sequence.len - 2] != ' ') return skip;

            var field_iter = std.mem.splitScalar(u8, sequence[3 .. sequence.len - 2], ';');
            const report_num_buf = field_iter.next() orelse unreachable; // always will have one field
            const report_num = parseParam(u8, report_num_buf, null) orelse return skip;

            switch (report_num) {
                100 => {
                    const allocator = self.arena.allocator();
                    var cursor_reports: std.ArrayList(MultiCursor.Report) = .empty;

                    while (field_iter.next()) |cursor_report_buf| {
                        var param_iter = std.mem.splitScalar(u8, cursor_report_buf, ':');
                        const shape_buf = param_iter.next() orelse break;
                        const shape_num = parseParam(u8, shape_buf, null) orelse break;
                        const shape: MultiCursor.Shape = switch (shape_num) {
                            @intFromEnum(MultiCursor.Shape.block) => .block,
                            @intFromEnum(MultiCursor.Shape.beam) => .beam,
                            @intFromEnum(MultiCursor.Shape.underline) => .underline,
                            @intFromEnum(MultiCursor.Shape.follow_main) => .follow_main,
                            else => break,
                        };

                        const pos = MultiCursor.Position.parse(param_iter.rest()) catch break;

                        try cursor_reports.append(allocator, .{
                            .shape = shape,
                            .pos = pos,
                        });
                    }

                    const cursor_reports_items = cursor_reports.items;
                    return .event(sequence.len, Event{ .multi_cursors = cursor_reports_items });
                },
                101 => {
                    const text_under_cursor_color_buf = field_iter.next() orelse return skip;
                    var text_under_cursor_color_param_iter = std.mem.splitScalar(u8, text_under_cursor_color_buf, ':');

                    const text_under_cursor_color_num_buf = text_under_cursor_color_param_iter.next() orelse return skip;
                    const text_under_cursor_color_num = parseParam(u8, text_under_cursor_color_num_buf, null) orelse return skip;
                    if (text_under_cursor_color_num != 30) return skip;

                    const text_under_cursor_color_space = MultiCursor.ColorSpace.parse(text_under_cursor_color_param_iter.rest()) catch return skip;

                    const cursor_color_buf = field_iter.next() orelse return skip;
                    var cursor_color_param_iter = std.mem.splitScalar(u8, cursor_color_buf, ':');

                    const cursor_color_num_buf = cursor_color_param_iter.next() orelse return skip;
                    const cursor_color_num = parseParam(u8, cursor_color_num_buf, null) orelse return skip;
                    if (cursor_color_num != 40) return skip;

                    const cursor_color_space = MultiCursor.ColorSpace.parse(cursor_color_param_iter.rest()) catch return skip;

                    return .event(sequence.len, Event{ .multi_cursor_color = MultiCursor.Color{
                        .text_under_cursor = text_under_cursor_color_space,
                        .cursor = cursor_color_space,
                    } });
                },
                else => return skip,
            }
        },
        else => return skip,
    }
}

fn parseApc(input: []const u8) ParseResult {
    if (input.len < 3) return .none;

    const end = blk: {
        const skip = skipUntilST(input).n;
        if (skip == 0) return .none;

        break :blk skip;
    };
    const sequence = input[0..end];
    const skip: ParseResult = .skip(sequence.len);

    switch (sequence[2]) {
        'G' => {
            const semicolon_idx = std.mem.indexOfScalarPos(u8, sequence, 3, ';') orelse return skip;

            var maybe_image_id: ?u32 = null;
            var maybe_image_num: ?u32 = null;

            const param_buf = sequence[3..semicolon_idx];
            var param_iter = std.mem.splitScalar(u8, param_buf, ',');
            while (param_iter.next()) |param| {
                switch (param[0]) {
                    'i' => {
                        maybe_image_id = parseParam(u32, param[2..], null) orelse return skip;
                    },
                    'I' => {
                        maybe_image_num = parseParam(u32, param[2..], null);
                    },
                    else => {},
                }
            }

            // it says no were what flags are always provided,
            // we are assuming the id flag 'i' is always provided
            const image_id = maybe_image_id orelse return skip;

            const content_buf = sequence[semicolon_idx + 1 .. sequence.len - 2];
            if (content_buf.len == 0) return skip;

            const colon_idx = std.mem.indexOfScalar(u8, content_buf, ':') orelse content_buf.len;
            const response_type_buf = content_buf[0..colon_idx];
            if (std.mem.eql(u8, response_type_buf, "OK")) {
                return .event(sequence.len, Event{ .kitty_graphics_response = .{
                    .id = image_id,
                    .num = maybe_image_num,
                    .msg = .ok,
                } });
            }

            var response: KittyGraphics.Response = .{
                .id = image_id,
                .num = maybe_image_num,
                .msg = .{ .err = .{
                    .type = response_type_buf,
                } },
            };

            if (content_buf.len > response_type_buf.len) {
                response.msg.err.msg = content_buf[colon_idx + 1 ..];
            }

            return .event(sequence.len, Event{ .kitty_graphics_response = response });
        },
        else => return skip,
    }
}

/// Parse a param buffer, returning a default value if the param was empty
inline fn parseParam(comptime T: type, buf: []const u8, default: ?T) ?T {
    if (buf.len == 0) return default;
    return std.fmt.parseInt(T, buf, 10) catch return null;
}

/// Parse a mouse event
inline fn parseMouse(input: []const u8, full_input: []const u8) ParseResult {
    const skip: ParseResult = .skip(input.len);

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
        const delim1 = std.mem.indexOfScalarPos(u8, input, 3, ';') orelse return skip;
        button_mask = parseParam(u16, input[3..delim1], null) orelse return skip;
        const delim2 = std.mem.indexOfScalarPos(u8, input, delim1 + 1, ';') orelse return skip;
        px = parseParam(i16, input[delim1 + 1 .. delim2], 1) orelse return skip;
        py = parseParam(i16, input[delim2 + 1 .. input.len - 1], 1) orelse return skip;
    } else {
        return skip;
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

    const n = if (xterm) 6 else input.len;
    return .event(n, Event{ .mouse = mouse });
}

/// The return type of our parse method. Contains an Event and the number of
/// bytes read from the buffer.
pub const ParseResult = struct {
    parse: Parse,
    n: usize,

    pub const none = ParseResult{
        .parse = .none,
        .n = 0,
    };

    pub fn skip(n: usize) ParseResult {
        return ParseResult{
            .parse = .skip,
            .n = n,
        };
    }

    pub fn event(n: usize, e: Event) ParseResult {
        return ParseResult{
            .parse = .{ .event = e },
            .n = n,
        };
    }

    pub const Parse = union(enum) {
        none,
        skip,
        event: Event,

        paste_start,
        paste_end,
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

const testing = std.testing;

test "parse(NORMAL): single keypress" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = "a";
    const result = try parser.parse(input);
    const expected_key: Key = .{
        .codepoint = 'a',
        .text = "a",
    };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(1, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse(NORMAL): single keypress backspace" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = "\x08";
    const result = try parser.parse(input);
    const expected_key: Key = .{
        .codepoint = Key.backspace,
    };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(1, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse(NORMAL): single keypress with more buffer" {
    const alloc = testing.allocator;
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

test "parse(NORMAL): escape keypress" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = ctlseqs.ESC;
    const result = try parser.parse(input);
    const expected_key: Key = .{ .codepoint = Key.escape };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(1, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse(NORMAL): ctrl+a" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = "\x01";
    const result = try parser.parse(input);
    const expected_key: Key = .{ .codepoint = 'a', .mods = .{ .ctrl = true } };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(1, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse(NORMAL): alt+a" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = ctlseqs.ESC ++ "a";
    const result = try parser.parse(input);
    const expected_key: Key = .{ .codepoint = 'a', .mods = .{ .alt = true } };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(2, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse(NORMAL): single codepoint" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = "🙂";
    const result = try parser.parse(input);
    const expected_key: Key = .{
        .codepoint = 0x1F642,
        .text = input,
    };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(4, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse(NORMAL): single codepoint with more in buffer" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = "🙂a";
    const result = try parser.parse(input);
    const expected_key: Key = .{
        .codepoint = 0x1F642,
        .text = "🙂",
    };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(4, result.n);
    try testing.expectEqualDeep(expected_event, result.parse.event);
}

test "parse(NORMAL): multiple codepoint grapheme" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = "👩‍🚀";
    const result = try parser.parse(input);
    const expected_key: Key = .{
        .codepoint = Key.multicodepoint,
        .text = input,
    };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(input.len, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse(NORMAL): multiple codepoint grapheme with more after" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = "👩‍🚀abc";
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

test "parse(NORMAL): flag emoji" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = "🇺🇸";
    const result = try parser.parse(input);
    const expected_key: Key = .{
        .codepoint = Key.multicodepoint,
        .text = input,
    };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(input.len, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse(NORMAL): combining mark" {
    const alloc = testing.allocator;
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

test "parse(NORMAL): skin tone emoji" {
    const alloc = testing.allocator;
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

test "parse(NORMAL): text variation selector" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    // Heavy black heart with text variation selector
    const input = "❤︎";
    const result = try parser.parse(input);
    const expected_key: Key = .{
        .codepoint = Key.multicodepoint,
        .text = input,
    };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(input.len, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse(NORMAL): keycap sequence" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = "1️⃣";
    const result = try parser.parse(input);
    const expected_key: Key = .{
        .codepoint = Key.multicodepoint,
        .text = input,
    };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(input.len, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse(SS3): key up" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = ctlseqs.SS3 ++ "A";
    const result = try parser.parse(input);
    const expected_key: Key = .{ .codepoint = Key.up };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(3, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse(CSI): key up" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = ctlseqs.CSI ++ "A";
    const result = try parser.parse(input);
    const expected_key: Key = .{ .codepoint = Key.up };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(3, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse(CSI): shift+up" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = ctlseqs.CSI ++ "1;2A";
    const result = try parser.parse(input);
    const expected_key: Key = .{ .codepoint = Key.up, .mods = .{ .shift = true } };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(6, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse(CSI): insert" {
    const alloc = testing.allocator;
    const input = ctlseqs.CSI ++ "2~";
    var parser: Parser = .init(alloc);
    defer parser.deinit();
    const result = try parser.parse(input);
    const expected_key: Key = .{ .codepoint = Key.insert, .mods = .{} };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(input.len, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse(CSI): disambiguate shift + space" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = ctlseqs.CSI ++ "32;2u";
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

test "parse(CSI): paste_start" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = ctlseqs.CSI ++ "200~";
    const result = try parser.parse(input);
    const expected: ParseResult.Parse = .paste_start;

    try testing.expectEqual(6, result.n);
    try testing.expectEqual(expected, result.parse);
}

test "parse(CSI): paste_end" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = ctlseqs.CSI ++ "201~";
    const result = try parser.parse(input);
    const expected: ParseResult.Parse = .paste_end;

    try testing.expectEqual(6, result.n);
    try testing.expectEqual(expected, result.parse);
}

test "parse(CSI): focus_in" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = ctlseqs.CSI ++ "I";
    const result = try parser.parse(input);
    const expected_event: Event = .focus_in;

    try testing.expectEqual(3, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse(CSI): focus_out" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = ctlseqs.CSI ++ "O";
    const result = try parser.parse(input);
    const expected_event: Event = .focus_out;

    try testing.expectEqual(3, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse(CSI): mouse" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = ctlseqs.CSI ++ "<35;1;1m";
    const result = try parser.parse(input);
    const expected: ParseResult = .{
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

test "parse(CSI): mouse (negative)" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = ctlseqs.CSI ++ "<35;-50;-100m";
    const result = try parser.parse(input);
    const expected: ParseResult = .{
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

test "parse(CSI): xterm mouse (X10)" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = ctlseqs.CSI ++ "M\x20\x21\x21";
    const result = try parser.parse(input);
    const expected: ParseResult = .{
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

test "parse(CSI): mouse (URXVT)" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = ctlseqs.CSI ++ "35;-50;100m";
    const result = try parser.parse(input);
    const expected: ParseResult = .skip(input.len);

    try testing.expectEqual(expected.n, result.n);
    try testing.expectEqual(expected.parse, result.parse);
}

test "parse(CSI): Color sheme" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    {
        const input = ctlseqs.CSI ++ "?997;1n";
        const result = try parser.parse(input);
        const expected: ParseResult = .{
            .parse = .{ .event = .{ .color_scheme = .dark } },
            .n = input.len,
        };

        try testing.expectEqual(expected.n, result.n);
        try testing.expectEqual(expected.parse, result.parse);
    }

    {
        const input = ctlseqs.CSI ++ "?997;2n";
        const result = try parser.parse(input);
        const expected: ParseResult = .{
            .parse = .{ .event = .{ .color_scheme = .light } },
            .n = input.len,
        };

        try testing.expectEqual(expected.n, result.n);
        try testing.expectEqual(expected.parse, result.parse);
    }

    {
        const input = ctlseqs.CSI ++ "0n";
        const result = try parser.parse(input);
        const expected: ParseResult = .skip(input.len);

        try testing.expectEqual(expected.n, result.n);
        try testing.expectEqual(expected.parse, result.parse);
    }
}

test "parse(CSI): In-Band Window Resize" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = ctlseqs.CSI ++ "48;80;120;800;1200t";
    const result = try parser.parse(input);
    const expected: ParseResult = .{
        .parse = .{ .event = .{ .winsize = .{ .rows = 80, .cols = 120, .y_pixel = 800, .x_pixel = 1200 } } },
        .n = input.len,
    };

    try testing.expectEqual(expected.n, result.n);
    try testing.expectEqual(expected.parse, result.parse);
}

test "parse(CSI): kitty: shift+a with text reporting" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = ctlseqs.CSI ++ "97:65;2;229u";
    const result = try parser.parse(input);
    const expected_key: Key = .{
        .codepoint = 'a',
        .shifted_codepoint = 'A',
        .mods = .{ .shift = true },
        .text = "å",
    };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(input.len, result.n);
    try testing.expectEqualDeep(expected_event, result.parse.event);
}

test "parse(CSI): kitty: shift+a without text reporting" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = ctlseqs.CSI ++ "97:65;2u";
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

test "parse(CSI): kitty: alt+shift+a without text reporting" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = ctlseqs.CSI ++ "97:65;4u";
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

test "parse(CSI): kitty: a without text reporting" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = ctlseqs.CSI ++ "97u";
    const result = try parser.parse(input);
    const expected_key: Key = .{
        .codepoint = 'a',
    };
    const expected_event: Event = .{ .key_press = expected_key };

    try testing.expectEqual(5, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse(CSI): kitty: release event" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = ctlseqs.CSI ++ "97;1:3u";
    const result = try parser.parse(input);
    const expected_key: Key = .{
        .codepoint = 'a',
    };
    const expected_event: Event = .{ .key_release = expected_key };

    try testing.expectEqual(9, result.n);
    try testing.expectEqual(expected_event, result.parse.event);
}

test "parse(CSI): kitty multi cursors report" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = ctlseqs.CSI ++ ">100;1:2:4:5;2:4:1:4:2:8;3:2:6:5;29:0" ++ MultiCursor.TRAILER;
    const result = try parser.parse(input);
    const expected_color_reports: []const MultiCursor.Report = &.{
        MultiCursor.Report{
            .shape = .block,
            .pos = .{ .xy = .{
                .x = 4,
                .y = 5,
            } },
        },
        MultiCursor.Report{
            .shape = .beam,
            .pos = .{ .area = .{
                .top_left = .{
                    .x = 1,
                    .y = 4,
                },
                .bottom_right = .{
                    .x = 2,
                    .y = 8,
                },
            } },
        },
        MultiCursor.Report{
            .shape = .underline,
            .pos = .{ .xy = .{
                .x = 6,
                .y = 5,
            } },
        },
        MultiCursor.Report{
            .shape = .follow_main,
            .pos = .follow_main,
        },
    };

    try testing.expectEqual(input.len, result.n);
    try testing.expect(result.parse.event == .multi_cursors);

    const actual_color_reports = result.parse.event.multi_cursors;
    try testing.expectEqual(expected_color_reports.len, actual_color_reports.len);
    for (expected_color_reports, 0..) |expected_color_report, i| {
        try testing.expectEqual(expected_color_report, actual_color_reports[i]);
    }
}

test "parse(CSI): kitty multi cursor color report" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    {
        const input = MultiCursor.INTRODUCER ++ "101;30:0;40:1" ++ MultiCursor.TRAILER;
        const result = try parser.parse(input);
        const expected = MultiCursor.Color{
            .text_under_cursor = .follow_main,
            .cursor = .special,
        };

        try testing.expectEqual(input.len, result.n);
        try testing.expectEqual(expected, result.parse.event.multi_cursor_color);
    }
    {
        const input = MultiCursor.INTRODUCER ++ "101;30:2:255:255:255;40:5:255" ++ MultiCursor.TRAILER;
        const result = try parser.parse(input);
        const expected = MultiCursor.Color{
            .text_under_cursor = .{ .rgb = .{ 255, 255, 255 } },
            .cursor = .{ .index = 255 },
        };

        try testing.expectEqual(input.len, result.n);
        try testing.expectEqual(expected, result.parse.event.multi_cursor_color);
    }
}

test "parse(OSC 4): Color reports" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    {
        const input = ctlseqs.OSC ++ "4;19;rgb:AAAA/BBBB/CCCC" ++ ctlseqs.ST;
        const result = try parser.parse(input);

        try testing.expectEqual(input.len, result.n);
        try testing.expect(result.parse.event == .color_report);
        try testing.expect(result.parse.event.color_report.kind.index == 19);
    }
    {
        const input = ctlseqs.OSC ++ "4;19;rgb:AAAA/BBBB/CCCC" ++ ctlseqs.BEL;
        const result = try parser.parse(input);

        try testing.expectEqual(input.len, result.n);
        try testing.expect(result.parse.event == .color_report);
        try testing.expect(result.parse.event.color_report.kind.index == 19);
    }
}

test "parse(OSC 10): Color reports" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    {
        const input = ctlseqs.OSC ++ "10;rgb:AAAA/BBBB/CCCC" ++ ctlseqs.ST;
        const result = try parser.parse(input);

        try testing.expectEqual(input.len, result.n);
        try testing.expect(result.parse.event == .color_report);
        try testing.expect(result.parse.event.color_report.kind == .fg);
    }
    {
        const input = ctlseqs.OSC ++ "10;rgb:AAAA/BBBB/CCCC" ++ ctlseqs.BEL;
        const result = try parser.parse(input);

        try testing.expectEqual(input.len, result.n);
        try testing.expect(result.parse.event == .color_report);
        try testing.expect(result.parse.event.color_report.kind == .fg);
    }
}

test "parse(OSC 11): Color reports" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    {
        const input = ctlseqs.OSC ++ "11;rgb:AAAA/BBBB/CCCC" ++ ctlseqs.ST;
        const result = try parser.parse(input);

        try testing.expectEqual(input.len, result.n);
        try testing.expect(result.parse.event == .color_report);
        try testing.expect(result.parse.event.color_report.kind == .bg);
    }
    {
        const input = ctlseqs.OSC ++ "11;rgb:AAAA/BBBB/CCCC" ++ ctlseqs.BEL;
        const result = try parser.parse(input);

        try testing.expectEqual(input.len, result.n);
        try testing.expect(result.parse.event == .color_report);
        try testing.expect(result.parse.event.color_report.kind == .bg);
    }
}

test "parse(OSC 12): Color reports" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    {
        const input = ctlseqs.OSC ++ "12;rgb:AAAA/BBBB/CCCC" ++ ctlseqs.ST;
        const result = try parser.parse(input);

        try testing.expectEqual(input.len, result.n);
        try testing.expect(result.parse.event == .color_report);
        try testing.expect(result.parse.event.color_report.kind == .cursor);
    }
    {
        const input = ctlseqs.OSC ++ "12;rgb:AAAA/BBBB/CCCC" ++ ctlseqs.BEL;
        const result = try parser.parse(input);

        try testing.expectEqual(input.len, result.n);
        try testing.expect(result.parse.event == .color_report);
        try testing.expect(result.parse.event.color_report.kind == .cursor);
    }
}

test "parse(OSC 52): paste" {
    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    const input = ctlseqs.OSC ++ "52;c;b3NjNTIgcGFzdGU=" ++ ctlseqs.ST;
    const result = try parser.parse(input);
    const expected_text = "osc52 paste";

    try testing.expectEqual(input.len, result.n);
    try testing.expectEqualStrings(expected_text, result.parse.event.paste);
}

test "parse(APC): Kitty Graphics Protocol Reponse" {
    const KG = KittyGraphics;

    const alloc = testing.allocator;
    var parser: Parser = .init(alloc);
    defer parser.deinit();

    {
        const input = KG.INTRODUCER ++ "i=99,I=13;OK" ++ KG.CLOSE;
        const result = try parser.parse(input);
        const expected_response = KG.Response{
            .id = 99,
            .num = 13,
            .msg = .ok,
        };

        try testing.expectEqual(input.len, result.n);
        try testing.expectEqual(expected_response, result.parse.event.kitty_graphics_response);
    }
    {
        const input = KG.INTRODUCER ++ "i=123;EBADPNG:some extra error msg" ++ KG.CLOSE;
        const result = try parser.parse(input);
        const expected_response = KG.Response{
            .id = 123,
            .msg = .{ .err = .{
                .type = "EBADPNG",
                .msg = "some extra error msg",
            } },
        };

        try testing.expectEqual(input.len, result.n);

        const kgr = result.parse.event.kitty_graphics_response;
        try testing.expectEqual(expected_response.id, kgr.id);
        try testing.expectEqual(expected_response.num, kgr.num);
        try testing.expectEqualStrings(expected_response.msg.err.type, kgr.msg.err.type);
        try testing.expectEqualStrings(expected_response.msg.err.msg.?, kgr.msg.err.msg.?);
    }
    {
        const input = KG.INTRODUCER ++ "I=123;ENOID;should be skipped since no id was returned" ++ KG.CLOSE;
        const result = try parser.parse(input);
        try testing.expectEqual(ParseResult.skip(input.len), result);
    }
}
