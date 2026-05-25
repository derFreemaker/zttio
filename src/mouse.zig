const Mouse = @This();

col: u16,
row: u16,
xoffset: u16 = 0,
yoffset: u16 = 0,
button: Button,
mods: Modifiers,
action: Action,

pub fn matches(self: *const Mouse, button: Button, action: Action, mods: Modifiers) bool {
    return self.button == button and
        self.action == action and
        self.mods.eql(mods);
}

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
