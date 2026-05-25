const Switchable = @import("switchable.zig").Switchable;

const Mouse = @This();

col: u16,
row: u16,
xoffset: u16 = 0,
yoffset: u16 = 0,
button: Button,
action: Action,
mods: Modifiers,

const MouseMatching = Switchable(packed struct {
    button: Button,
    action: Action,
    mods: Modifiers,
});

pub fn switchable(self: *const Mouse) MouseMatching.SwitchValue {
    return MouseMatching.makeSwitchable(.{
        .button = self.button,
        .action = self.action,
        .mods = self.mods,
    });
}

pub fn matches(button: Button, action: Action, mods: Modifiers) MouseMatching.SwitchValue {
    return MouseMatching.makeSwitchable(.{
        .button = button,
        .action = action,
        .mods = mods,
    });
}

pub const Button = enum(u8) {
    left,
    middle,
    right,
    none,
    wheel_up = 64,
    wheel_down = 65,
    wheel_right = 66,
    wheel_left = 67,
    button_8 = 128,
    button_9 = 129,
    button_10 = 130,
    button_11 = 131,
};

pub const Modifiers = packed struct(u3) {
    shift: bool = false,
    alt: bool = false,
    ctrl: bool = false,

    pub fn eql(self: Modifiers, other: Modifiers) bool {
        const a: u3 = @bitCast(self);
        const b: u3 = @bitCast(other);
        return a == b;
    }
};

pub const Action = enum {
    press,
    release,
    motion,
    drag,
};

pub const Shape = enum {
    default,
    text,
    pointer,
    help,
    progress,
    wait,
    @"ew-resize",
    @"ns-resize",
    cell,
};
