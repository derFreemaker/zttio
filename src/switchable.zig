const std = @import("std");

pub fn Switchable(comptime T: type) type {
    if (@typeInfo(T) != .@"struct" or @typeInfo(T).@"struct".layout == .auto) {
        @compileError("expected T to be a packed/extern struct: " ++ @typeName(T));
    }

    return struct {
        pub const SwitchValue = std.meta.Int(.unsigned, @bitSizeOf(T));

        pub fn makeSwitchable(self: *const T) SwitchValue {
            return @as(SwitchValue, @bitCast(self.*));
        }
    };
}
