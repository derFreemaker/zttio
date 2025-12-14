const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zigwin_mod = b.dependency("zigwin32", .{}).module("win32");
    
    const uucode_dep = b.dependency("uucode", .{
        .target = target,
        .optimize = optimize,
        .fields = @as([]const []const u8, &.{
            "east_asian_width",
            "grapheme_break",
            "general_category",
            "is_emoji_presentation",
            "uppercase_mapping"
        }),
    });
    const uucode_mod = uucode_dep.module("uucode");

    const mod = b.addModule("ztty", .{
        .target = target,
        .optimize = optimize,

        .root_source_file = b.path("src/tty.zig"),

        .imports = &.{
            .{ .name = "zigwin", .module = zigwin_mod },
            .{ .name = "uucode", .module = uucode_mod },
        },
    });

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
