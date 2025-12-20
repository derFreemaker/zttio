const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zigwin_mod = b.dependency("zigwin32", .{}).module("win32");

    const uucode_dep = b.dependency("uucode", .{
        .target = target,
        .optimize = optimize,
        .fields = @as([]const []const u8, &.{ "east_asian_width", "grapheme_break", "general_category", "is_emoji_presentation", "uppercase_mapping" }),
    });
    const uucode_mod = uucode_dep.module("uucode");

    const common_mod = b.addModule("common", .{
        .target = target,
        .optimize = optimize,

        .root_source_file = b.path("src/common/common.zig"),

        .imports = &.{
            .{ .name = "zigwin", .module = zigwin_mod },
            .{ .name = "uucode", .module = uucode_mod },
        },
    });

    const common_tests = b.addTest(.{
        .root_module = common_mod,
    });
    const run_common_tests = b.addRunArtifact(common_tests);

    const tty_mod = b.addModule("tty", .{
        .target = target,
        .optimize = optimize,

        .root_source_file = b.path("src/tty/tty.zig"),

        .imports = &.{
            .{ .name = "zigwin", .module = zigwin_mod },
            .{ .name = "uucode", .module = uucode_mod },

            .{ .name = "common", .module = common_mod },
        },
    });
    
    const zttio_mod = b.addModule("zttio", .{
        .target = target,
        .optimize = optimize,
        
        .root_source_file = b.path("src/zttio.zig"),
        
        .imports = &.{
            .{ .name = "tty", .module = tty_mod },
        },
    });
    
    const test_exe_mod = b.addModule("test_exe", .{
        .target = target,
        .optimize = optimize,
        
        .root_source_file = b.path("src/test_exe.zig"),
        
        .imports = &.{
            .{ .name = "zttio", .module = zttio_mod },     
        },
    });
    const test_exe = b.addExecutable(.{
        .name = "test_exe",
        .root_module = test_exe_mod,
    });
    b.installArtifact(test_exe);
    
    const tty_tests = b.addTest(.{
        .root_module = tty_mod,
    });
    const run_tty_tests = b.addRunArtifact(tty_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_common_tests.step);
    test_step.dependOn(&run_tty_tests.step);
}
