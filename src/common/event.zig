const std = @import("std");

const Key = @import("key.zig");
const Mouse = @import("mouse.zig");
const Color = @import("color.zig").Color;
const Winsize = @import("winsize.zig");
const MultiCursor = @import("multi_cursor.zig");

pub const Event = union(enum) {
    key_press: Key,
    key_release: Key,

    mouse: Mouse,
    mouse_leave,

    focus_in,
    focus_out,

    winsize: Winsize,

    paste: []const u8,

    color_report: Color.Report,
    color_scheme: Color.Scheme,

    multi_cursors: []const MultiCursor.Report,
    multi_cursor_color: MultiCursor.Color,

    pub fn deinit(event: *const Event, allocator: std.mem.Allocator) void {
        switch (event.*) {
            .key_press, .key_release => |key| {
                if (key.text) |text| {
                    allocator.free(text);
                }
            },
            .paste => |p| {
                allocator.free(p);
            },
            else => {},
        }
    }

    pub fn clone(event: *const Event, allocator: std.mem.Allocator) error{OutOfMemory}!Event {
        switch (event.*) {
            .key_press => |key| {
                if (key.text) |text| {
                    var new_key = key;
                    new_key.text = try allocator.dupe(u8, text);
                    return Event{ .key_press = new_key };
                }

                return event.*;
            },
            .key_release => |key| {
                if (key.text) |text| {
                    var new_key = key;
                    new_key.text = try allocator.dupe(u8, text);
                    return Event{ .key_release = new_key };
                }

                return event.*;
            },
            .paste => |p| {
                return Event{ .paste = try allocator.dupe(u8, p) };
            },
            else => return event.*,
        }
    }
};
