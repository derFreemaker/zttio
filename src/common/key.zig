const std = @import("std");
const uucode = @import("uucode");

const Key = @This();

/// The unicode codepoint of the key event.
codepoint: KeyCP,

/// The text generated from the key event.
/// If set has to be freed with given `event_allocator`.
text: KeyText = .empty,

/// The shifted codepoint of this key event. This will only be present if the
/// Shift modifier was used to generate the event
shifted_codepoint: ?KeyCP = null,

/// The key that would have been pressed on a standard keyboard layout. This is
/// useful for shortcut matching
base_layout_codepoint: ?KeyCP = null,

mods: Modifiers = .{},

/// matches follows a loose matching algorithm for key matches
/// 1. If the codepoint and modifiers are exact matches
///
///    ignored modifiers: caps_lock, num_lock
///
/// 2. If the utf8 encoding of the codepoint matches the text
///
///    ignored modifiers: caps_lock, num_lock
///
/// 3. If there is a shifted codepoint and it matches
///
///    ignored modifiers: shift, caps_lock, num_lock
pub fn matches(self: Key, cp: KeyCP, mods: Modifiers) bool {
    // rule 1
    if (self.matchExact(cp, mods)) return true;

    // rule 2
    if (self.matchText(cp, mods)) return true;

    // rule 3
    if (self.matchShiftedCodepoint(cp, mods)) return true;

    return false;
}

/// matches against any of the provided codepoints.
pub fn matchesAny(self: Key, cps: []const KeyCP, mods: Modifiers) bool {
    for (cps) |cp| {
        if (self.matches(cp, mods)) return true;
    }
    return false;
}

/// matches base layout codes, useful for shortcut matching when an alternate key
/// layout is used
pub fn matchShortcut(self: Key, cp: KeyCP, mods: Modifiers) bool {
    if (self.base_layout_codepoint == null) return false;
    return cp == self.base_layout_codepoint.? and self.mods.eql(mods);
}

/// matches keys that aren't upper case versions when shifted.
/// For example, shift + semicolon produces a colon. The key can be matched against shift +
/// semicolon or just colon...or shift + ctrl + ; or just ctrl + :
///
/// ignored modifiers: shift, caps_lock, num_lock
pub fn matchShiftedCodepoint(self: Key, cp: KeyCP, mods: Modifiers) bool {
    if (self.shifted_codepoint == null) return false;
    if (!self.mods.shift) return false;

    var self_mods = self.mods;
    self_mods.shift = false;
    self_mods.caps_lock = false;
    self_mods.num_lock = false;

    var tgt_mods = mods;
    tgt_mods.shift = false;
    tgt_mods.caps_lock = false;
    tgt_mods.num_lock = false;

    return cp == self.shifted_codepoint.? and self_mods.eql(tgt_mods);
}

/// matches when the utf8 encoding of the codepoint and relevant mods matches the
/// text of the key.
///
/// ignored modifiers: caps_lock, num_lock
pub fn matchText(self: Key, cp: KeyCP, mods: Modifiers) bool {
    if (self.text == .empty) return false;

    var self_mods = self.mods;
    self_mods.caps_lock = false;
    self_mods.num_lock = false;

    var arg_mods = mods;
    arg_mods.caps_lock = false;
    arg_mods.num_lock = false;

    const _cp: u21 = if (mods.shift or mods.caps_lock) blk: {
        if (cp.value() < 128) {
            break :blk std.ascii.toUpper(@intCast(cp.value()));
        }

        var buf: [1]u21 = undefined;
        break :blk uucode.get(.uppercase_mapping, cp.value()).with(&buf, cp.value())[0];
    } else cp.value();

    var buf: [4]u8 = undefined;
    const n = std.unicode.utf8Encode(_cp, &buf) catch return false;
    return std.mem.eql(u8, self.text.get(), buf[0..n]) and self_mods.eql(arg_mods);
}

/// The key must exactly match the codepoint and modifiers.
///
/// ignored modifiers: caps_lock, num_lock
pub fn matchExact(self: Key, cp: KeyCP, mods: Modifiers) bool {
    var self_mods = self.mods;
    self_mods.caps_lock = false;
    self_mods.num_lock = false;

    var tgt_mods = mods;
    tgt_mods.caps_lock = false;
    tgt_mods.num_lock = false;

    return self.codepoint == cp and self_mods.eql(tgt_mods);
}

/// True if the key is a single modifier (ie: left_shift)
pub fn isModifier(self: Key) bool {
    return self.codepoint == left_shift or
        self.codepoint == left_alt or
        self.codepoint == left_super or
        self.codepoint == left_hyper or
        self.codepoint == left_control or
        self.codepoint == left_meta or
        self.codepoint == right_shift or
        self.codepoint == right_alt or
        self.codepoint == right_super or
        self.codepoint == right_hyper or
        self.codepoint == right_control or
        self.codepoint == right_meta;
}

pub const KeyText = union(enum) {
    pub const MaxShortLength = 23;

    empty: void,
    char: u8,
    short: [MaxShortLength]u8,
    long: []const u8,

    pub fn from(text: []const u8) KeyText {
        if (text.len == 1) {
            return KeyText{ .char = text[0] };
        } else if (text.len <= MaxShortLength) {
            var key_text = KeyText{ .short = std.mem.zeroes([MaxShortLength]u8) };
            @memcpy(key_text.short[0..text.len], text);
            return key_text;
        } else {
            return KeyText{ .long = text };
        }
    }

    pub fn deinit(self: *KeyText, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .empty, .char, .short => {},
            .long => allocator.free(self.long),
        }
    }

    pub fn clone(self: *const KeyText, allocator: std.mem.Allocator) std.mem.Allocator.Error!KeyText {
        return switch (self.*) {
            .empty, .char, .short => self.*,
            .long => KeyText{ .long = try allocator.dupe(u8, self.long) },
        };
    }

    pub fn get(self: *const KeyText) []const u8 {
        return switch (self.*) {
            .empty => &[_]u8{},
            .char => (&self.char)[0..1],
            .short => self.short[0 .. std.mem.indexOfScalar(u8, &self.short, 0) orelse MaxShortLength],
            .long => self.long,
        };
    }

    pub fn len(self: *const KeyText) usize {
        return switch (self.*) {
            .empty => 0,
            .char => 1,
            .short => std.mem.indexOfScalar(u8, &self.short, 0) orelse MaxShortLength,
            .long => self.long.len,
        };
    }
};

comptime {
    std.debug.assert(@sizeOf(KeyText) == 24);
}

pub const Modifiers = packed struct(u8) {
    shift: bool = false,
    alt: bool = false,
    ctrl: bool = false,
    super: bool = false,
    hyper: bool = false,
    meta: bool = false,
    caps_lock: bool = false,
    num_lock: bool = false,

    pub fn eql(self: Modifiers, other: Modifiers) bool {
        const a: u8 = @bitCast(self);
        const b: u8 = @bitCast(other);
        return a == b;
    }
};

pub const KeyCP = enum(u21) {
    // a few special keys that we encode as their actual ascii value
    tab = 0x09,
    enter = 0x0D,
    escape = 0x1B,
    space = 0x20,
    backspace = 0x7F,

    /// Multicodepoint is a key which generated text but cannot be expressed as a
    /// single codepoint. The value is the maximum unicode codepoint + 1
    multicodepoint = 0x110000 + 1,

    // kitty encodes these keys directly in the private use area. We reuse those
    // mappings
    insert = 57348,
    delete = 57349,
    left = 57350,
    right = 57351,
    up = 57352,
    down = 57353,
    page_up = 57354,
    page_down = 57355,
    home = 57356,
    end = 57357,
    caps_lock = 57358,
    scroll_lock = 57359,
    num_lock = 57360,
    print_screen = 57361,
    pause = 57362,
    menu = 57363,
    f1 = 57364,
    f2 = 57365,
    f3 = 57366,
    f4 = 57367,
    f5 = 57368,
    f6 = 57369,
    f7 = 57370,
    f8 = 57371,
    f9 = 57372,
    f10 = 57373,
    f11 = 57374,
    f12 = 57375,
    f13 = 57376,
    f14 = 57377,
    f15 = 57378,
    f16 = 57379,
    f17 = 57380,
    f18 = 57381,
    f19 = 57382,
    f20 = 57383,
    f21 = 57384,
    f22 = 57385,
    f23 = 57386,
    f24 = 57387,
    f25 = 57388,
    f26 = 57389,
    f27 = 57390,
    f28 = 57391,
    f29 = 57392,
    f30 = 57393,
    f31 = 57394,
    f32 = 57395,
    f33 = 57396,
    f34 = 57397,
    f35 = 57398,
    kp_0 = 57399,
    kp_1 = 57400,
    kp_2 = 57401,
    kp_3 = 57402,
    kp_4 = 57403,
    kp_5 = 57404,
    kp_6 = 57405,
    kp_7 = 57406,
    kp_8 = 57407,
    kp_9 = 57408,
    kp_decimal = 57409,
    kp_divide = 57410,
    kp_multiply = 57411,
    kp_subtract = 57412,
    kp_add = 57413,
    kp_enter = 57414,
    kp_equal = 57415,
    kp_separator = 57416,
    kp_left = 57417,
    kp_right = 57418,
    kp_up = 57419,
    kp_down = 57420,
    kp_page_up = 57421,
    kp_page_down = 57422,
    kp_home = 57423,
    kp_end = 57424,
    kp_insert = 57425,
    kp_delete = 57426,
    kp_begin = 57427,
    media_play = 57428,
    media_pause = 57429,
    media_play_pause = 57430,
    media_reverse = 57431,
    media_stop = 57432,
    media_fast_forward = 57433,
    media_rewind = 57434,
    media_track_next = 57435,
    media_track_previous = 57436,
    media_record = 57437,
    lower_volume = 57438,
    raise_volume = 57439,
    mute_volume = 57440,
    left_shift = 57441,
    left_control = 57442,
    left_alt = 57443,
    left_super = 57444,
    left_hyper = 57445,
    left_meta = 57446,
    right_shift = 57447,
    right_control = 57448,
    right_alt = 57449,
    right_super = 57450,
    right_hyper = 57451,
    right_meta = 57452,
    iso_level_3_shift = 57453,
    iso_level_5_shift = 57454,
    _,

    pub inline fn from(cp: u21) KeyCP {
        return @enumFromInt(cp);
    }

    pub inline fn value(self: KeyCP) u21 {
        return @intFromEnum(self);
    }
};

// a few special keys that we encode as their actual ascii value
pub const tab: u21 = @intFromEnum(KeyCP.tab);
pub const enter: u21 = @intFromEnum(KeyCP.enter);
pub const escape: u21 = @intFromEnum(KeyCP.escape);
pub const space: u21 = @intFromEnum(KeyCP.space);
pub const backspace: u21 = @intFromEnum(KeyCP.backspace);

/// Multicodepoint is a key which generated text but cannot be expressed as a
/// single codepoint. The value is the maximum unicode codepoint + 1
pub const multicodepoint: u21 = @intFromEnum(KeyCP.multicodepoint);

// kitty encodes these keys directly in the private use area. We reuse those
// mappings
pub const insert: u21 = @intFromEnum(KeyCP.insert);
pub const delete: u21 = @intFromEnum(KeyCP.delete);
pub const left: u21 = @intFromEnum(KeyCP.left);
pub const right: u21 = @intFromEnum(KeyCP.right);
pub const up: u21 = @intFromEnum(KeyCP.up);
pub const down: u21 = @intFromEnum(KeyCP.down);
pub const page_up: u21 = @intFromEnum(KeyCP.page_up);
pub const page_down: u21 = @intFromEnum(KeyCP.page_down);
pub const home: u21 = @intFromEnum(KeyCP.home);
pub const end: u21 = @intFromEnum(KeyCP.end);
pub const caps_lock: u21 = @intFromEnum(KeyCP.caps_lock);
pub const scroll_lock: u21 = @intFromEnum(KeyCP.scroll_lock);
pub const num_lock: u21 = @intFromEnum(KeyCP.num_lock);
pub const print_screen: u21 = @intFromEnum(KeyCP.print_screen);
pub const pause: u21 = @intFromEnum(KeyCP.pause);
pub const menu: u21 = @intFromEnum(KeyCP.menu);
pub const f1: u21 = @intFromEnum(KeyCP.f1);
pub const f2: u21 = @intFromEnum(KeyCP.f2);
pub const f3: u21 = @intFromEnum(KeyCP.f3);
pub const f4: u21 = @intFromEnum(KeyCP.f4);
pub const f5: u21 = @intFromEnum(KeyCP.f5);
pub const f6: u21 = @intFromEnum(KeyCP.f6);
pub const f7: u21 = @intFromEnum(KeyCP.f7);
pub const f8: u21 = @intFromEnum(KeyCP.f8);
pub const f9: u21 = @intFromEnum(KeyCP.f9);
pub const f10: u21 = @intFromEnum(KeyCP.f10);
pub const f11: u21 = @intFromEnum(KeyCP.f11);
pub const f12: u21 = @intFromEnum(KeyCP.f12);
pub const f13: u21 = @intFromEnum(KeyCP.f13);
pub const f14: u21 = @intFromEnum(KeyCP.f14);
pub const f15: u21 = @intFromEnum(KeyCP.f15);
pub const @"f16": u21 = @intFromEnum(KeyCP.f16);
pub const f17: u21 = @intFromEnum(KeyCP.f17);
pub const f18: u21 = @intFromEnum(KeyCP.f18);
pub const f19: u21 = @intFromEnum(KeyCP.f19);
pub const f20: u21 = @intFromEnum(KeyCP.f20);
pub const f21: u21 = @intFromEnum(KeyCP.f21);
pub const f22: u21 = @intFromEnum(KeyCP.f22);
pub const f23: u21 = @intFromEnum(KeyCP.f23);
pub const f24: u21 = @intFromEnum(KeyCP.f24);
pub const f25: u21 = @intFromEnum(KeyCP.f25);
pub const f26: u21 = @intFromEnum(KeyCP.f26);
pub const f27: u21 = @intFromEnum(KeyCP.f27);
pub const f28: u21 = @intFromEnum(KeyCP.f28);
pub const f29: u21 = @intFromEnum(KeyCP.f29);
pub const f30: u21 = @intFromEnum(KeyCP.f30);
pub const f31: u21 = @intFromEnum(KeyCP.f31);
pub const @"f32": u21 = @intFromEnum(KeyCP.f32);
pub const f33: u21 = @intFromEnum(KeyCP.f33);
pub const f34: u21 = @intFromEnum(KeyCP.f34);
pub const f35: u21 = @intFromEnum(KeyCP.f35);
pub const kp_0: u21 = @intFromEnum(KeyCP.kp_0);
pub const kp_1: u21 = @intFromEnum(KeyCP.kp_1);
pub const kp_2: u21 = @intFromEnum(KeyCP.kp_2);
pub const kp_3: u21 = @intFromEnum(KeyCP.kp_3);
pub const kp_4: u21 = @intFromEnum(KeyCP.kp_4);
pub const kp_5: u21 = @intFromEnum(KeyCP.kp_5);
pub const kp_6: u21 = @intFromEnum(KeyCP.kp_6);
pub const kp_7: u21 = @intFromEnum(KeyCP.kp_7);
pub const kp_8: u21 = @intFromEnum(KeyCP.kp_8);
pub const kp_9: u21 = @intFromEnum(KeyCP.kp_9);
pub const kp_decimal: u21 = @intFromEnum(KeyCP.kp_decimal);
pub const kp_divide: u21 = @intFromEnum(KeyCP.kp_divide);
pub const kp_multiply: u21 = @intFromEnum(KeyCP.kp_multiply);
pub const kp_subtract: u21 = @intFromEnum(KeyCP.kp_subtract);
pub const kp_add: u21 = @intFromEnum(KeyCP.kp_add);
pub const kp_enter: u21 = @intFromEnum(KeyCP.kp_enter);
pub const kp_equal: u21 = @intFromEnum(KeyCP.kp_equal);
pub const kp_separator: u21 = @intFromEnum(KeyCP.kp_separator);
pub const kp_left: u21 = @intFromEnum(KeyCP.kp_left);
pub const kp_right: u21 = @intFromEnum(KeyCP.kp_right);
pub const kp_up: u21 = @intFromEnum(KeyCP.kp_up);
pub const kp_down: u21 = @intFromEnum(KeyCP.kp_down);
pub const kp_page_up: u21 = @intFromEnum(KeyCP.kp_page_up);
pub const kp_page_down: u21 = @intFromEnum(KeyCP.kp_page_down);
pub const kp_home: u21 = @intFromEnum(KeyCP.kp_home);
pub const kp_end: u21 = @intFromEnum(KeyCP.kp_end);
pub const kp_insert: u21 = @intFromEnum(KeyCP.kp_insert);
pub const kp_delete: u21 = @intFromEnum(KeyCP.kp_delete);
pub const kp_begin: u21 = @intFromEnum(KeyCP.kp_begin);
pub const media_play: u21 = @intFromEnum(KeyCP.media_play);
pub const media_pause: u21 = @intFromEnum(KeyCP.media_pause);
pub const media_play_pause: u21 = @intFromEnum(KeyCP.media_play_pause);
pub const media_reverse: u21 = @intFromEnum(KeyCP.media_reverse);
pub const media_stop: u21 = @intFromEnum(KeyCP.media_stop);
pub const media_fast_forward: u21 = @intFromEnum(KeyCP.media_fast_forward);
pub const media_rewind: u21 = @intFromEnum(KeyCP.media_rewind);
pub const media_track_next: u21 = @intFromEnum(KeyCP.media_track_next);
pub const media_track_previous: u21 = @intFromEnum(KeyCP.media_track_previous);
pub const media_record: u21 = @intFromEnum(KeyCP.media_record);
pub const lower_volume: u21 = @intFromEnum(KeyCP.lower_volume);
pub const raise_volume: u21 = @intFromEnum(KeyCP.raise_volume);
pub const mute_volume: u21 = @intFromEnum(KeyCP.mute_volume);
pub const left_shift: u21 = @intFromEnum(KeyCP.left_shift);
pub const left_control: u21 = @intFromEnum(KeyCP.left_control);
pub const left_alt: u21 = @intFromEnum(KeyCP.left_alt);
pub const left_super: u21 = @intFromEnum(KeyCP.left_super);
pub const left_hyper: u21 = @intFromEnum(KeyCP.left_hyper);
pub const left_meta: u21 = @intFromEnum(KeyCP.left_meta);
pub const right_shift: u21 = @intFromEnum(KeyCP.right_shift);
pub const right_control: u21 = @intFromEnum(KeyCP.right_control);
pub const right_alt: u21 = @intFromEnum(KeyCP.right_alt);
pub const right_super: u21 = @intFromEnum(KeyCP.right_super);
pub const right_hyper: u21 = @intFromEnum(KeyCP.right_hyper);
pub const right_meta: u21 = @intFromEnum(KeyCP.right_meta);
pub const iso_level_3_shift: u21 = @intFromEnum(KeyCP.iso_level_3_shift);
pub const iso_level_5_shift: u21 = @intFromEnum(KeyCP.iso_level_5_shift);

pub const name_map = blk: {
    @setEvalBranchQuota(2000);
    break :blk std.StaticStringMap(u21).initComptime(.{
        // common names
        .{ "plus", '+' },
        .{ "minus", '-' },
        .{ "colon", ':' },
        .{ "semicolon", ';' },
        .{ "comma", ',' },

        // special keys
        .{ "tab", tab },
        .{ "enter", enter },
        .{ "escape", escape },
        .{ "space", space },
        .{ "backspace", backspace },
        .{ "insert", insert },
        .{ "delete", delete },
        .{ "left", left },
        .{ "right", right },
        .{ "up", up },
        .{ "down", down },
        .{ "page_up", page_up },
        .{ "page_down", page_down },
        .{ "home", home },
        .{ "end", end },
        .{ "caps_lock", caps_lock },
        .{ "scroll_lock", scroll_lock },
        .{ "num_lock", num_lock },
        .{ "print_screen", print_screen },
        .{ "pause", pause },
        .{ "menu", menu },
        .{ "f1", f1 },
        .{ "f2", f2 },
        .{ "f3", f3 },
        .{ "f4", f4 },
        .{ "f5", f5 },
        .{ "f6", f6 },
        .{ "f7", f7 },
        .{ "f8", f8 },
        .{ "f9", f9 },
        .{ "f10", f10 },
        .{ "f11", f11 },
        .{ "f12", f12 },
        .{ "f13", f13 },
        .{ "f14", f14 },
        .{ "f15", f15 },
        .{ "f16", @"f16" },
        .{ "f17", f17 },
        .{ "f18", f18 },
        .{ "f19", f19 },
        .{ "f20", f20 },
        .{ "f21", f21 },
        .{ "f22", f22 },
        .{ "f23", f23 },
        .{ "f24", f24 },
        .{ "f25", f25 },
        .{ "f26", f26 },
        .{ "f27", f27 },
        .{ "f28", f28 },
        .{ "f29", f29 },
        .{ "f30", f30 },
        .{ "f31", f31 },
        .{ "f32", @"f32" },
        .{ "f33", f33 },
        .{ "f34", f34 },
        .{ "f35", f35 },
        .{ "kp_0", kp_0 },
        .{ "kp_1", kp_1 },
        .{ "kp_2", kp_2 },
        .{ "kp_3", kp_3 },
        .{ "kp_4", kp_4 },
        .{ "kp_5", kp_5 },
        .{ "kp_6", kp_6 },
        .{ "kp_7", kp_7 },
        .{ "kp_8", kp_8 },
        .{ "kp_9", kp_9 },
        .{ "kp_decimal", kp_decimal },
        .{ "kp_divide", kp_divide },
        .{ "kp_multiply", kp_multiply },
        .{ "kp_subtract", kp_subtract },
        .{ "kp_add", kp_add },
        .{ "kp_enter", kp_enter },
        .{ "kp_equal", kp_equal },
        .{ "kp_separator", kp_separator },
        .{ "kp_left", kp_left },
        .{ "kp_right", kp_right },
        .{ "kp_up", kp_up },
        .{ "kp_down", kp_down },
        .{ "kp_page_up", kp_page_up },
        .{ "kp_page_down", kp_page_down },
        .{ "kp_home", kp_home },
        .{ "kp_end", kp_end },
        .{ "kp_insert", kp_insert },
        .{ "kp_delete", kp_delete },
        .{ "kp_begin", kp_begin },
        .{ "media_play", media_play },
        .{ "media_pause", media_pause },
        .{ "media_play_pause", media_play_pause },
        .{ "media_reverse", media_reverse },
        .{ "media_stop", media_stop },
        .{ "media_fast_forward", media_fast_forward },
        .{ "media_rewind", media_rewind },
        .{ "media_track_next", media_track_next },
        .{ "media_track_previous", media_track_previous },
        .{ "media_record", media_record },
        .{ "lower_volume", lower_volume },
        .{ "raise_volume", raise_volume },
        .{ "mute_volume", mute_volume },
        .{ "left_shift", left_shift },
        .{ "left_control", left_control },
        .{ "left_alt", left_alt },
        .{ "left_super", left_super },
        .{ "left_hyper", left_hyper },
        .{ "left_meta", left_meta },
        .{ "right_shift", right_shift },
        .{ "right_control", right_control },
        .{ "right_alt", right_alt },
        .{ "right_super", right_super },
        .{ "right_hyper", right_hyper },
        .{ "right_meta", right_meta },
        .{ "iso_level_3_shift", iso_level_3_shift },
        .{ "iso_level_5_shift", iso_level_5_shift },
    });
};

const testing = std.testing;

test "matches 'a'" {
    const key: Key = .{
        .codepoint = .from('a'),
        .mods = .{ .num_lock = true },
        .text = .from("a"),
    };
    try testing.expect(key.matches(.from('a'), .{}));
    try testing.expect(!key.matches(.from('a'), .{ .shift = true }));
}

test "matches 'shift+a'" {
    const key: Key = .{
        .codepoint = .from('a'),
        .shifted_codepoint = .from('A'),
        .mods = .{ .shift = true },
        .text = .from("A"),
    };
    try testing.expect(key.matches(.from('a'), .{ .shift = true }));
    try testing.expect(!key.matches(.from('a'), .{}));
    try testing.expect(key.matches(.from('A'), .{}));
    try testing.expect(!key.matches(.from('A'), .{ .ctrl = true }));
}

test "matches 'shift+tab'" {
    const key: Key = .{
        .codepoint = .tab,
        .mods = .{ .shift = true, .num_lock = true },
    };
    try testing.expect(key.matches(.tab, .{ .shift = true }));
    try testing.expect(!key.matches(.tab, .{}));
}

test "matches 'shift+;'" {
    const key: Key = .{
        .codepoint = .from(';'),
        .shifted_codepoint = .from(':'),
        .mods = .{ .shift = true },
        .text = .from(":"),
    };
    try testing.expect(key.matches(.from(';'), .{ .shift = true }));
    try testing.expect(key.matches(.from(':'), .{}));

    const colon: Key = .{
        .codepoint = .from(':'),
        .mods = .{},
    };
    try testing.expect(colon.matches(.from(':'), .{}));
}

test "name_map" {
    try testing.expectEqual(insert, name_map.get("insert"));
}

test "upper mapping" {
    const small_greek_letter = KeyCP.from(0x03C2);
    const capital_greek_letter = KeyCP.from(0x03A3);

    const key = Key{
        .codepoint = small_greek_letter,
        .shifted_codepoint = capital_greek_letter,
        .mods = .{ .shift = true },
        .text = .from("\u{03A3}"),
    };
    try testing.expect(key.matchText(small_greek_letter, .{ .shift = true }));
}
