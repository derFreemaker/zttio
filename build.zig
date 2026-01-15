const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zigwin_mod: ?*std.Build.Module = blk: {
        if (target.result.os.tag != .windows) {
            break :blk null;
        }

        if (b.lazyDependency("zigwin32", .{})) |zigwin32| {
            break :blk zigwin32.module("win32");
        }

        break :blk null;
    };

    const uucode_dep = b.dependency("uucode", .{
        .target = target,
        .optimize = optimize,
        .fields = @as([]const []const u8, &.{ "east_asian_width", "grapheme_break", "general_category", "is_emoji_presentation", "uppercase_mapping" }),
    });
    const uucode_mod = uucode_dep.module("uucode");

    const zigimg_dep = b.dependency("zigimg", .{
        .target = target,
        .optimize = optimize,
    });
    const zigimg_mod = zigimg_dep.module("zigimg");

    const common_mod = b.addModule("common", .{
        .target = target,
        .optimize = optimize,

        .root_source_file = b.path("src/common/common.zig"),

        .imports = &.{
            .{ .name = "uucode", .module = uucode_mod },
            .{ .name = "zigimg", .module = zigimg_mod },
        },
    });
    if (zigwin_mod) |mod| {
        common_mod.addImport("zigwin", mod);
    }

    const tty_mod = b.addModule("tty", .{
        .target = target,
        .optimize = optimize,

        .root_source_file = b.path("src/tty/tty.zig"),

        .imports = &.{
            .{ .name = "uucode", .module = uucode_mod },

            .{ .name = "common", .module = common_mod },
        },
    });
    if (zigwin_mod) |mod| {
        common_mod.addImport("zigwin", mod);
    }

    if (target.result.os.tag == .windows) {
        if (b.lazyDependency("zigwin32", .{})) |zigwin32| {
            const mod = zigwin32.module("win32");

            common_mod.addImport("zigwin", mod);
            tty_mod.addImport("zigwin", mod);
        }
    }

    const zttio_mod = b.addModule("zttio", .{
        .target = target,
        .optimize = optimize,

        .root_source_file = b.path("src/zttio.zig"),

        .imports = &.{
            .{ .name = "common", .module = common_mod },

            .{ .name = "tty", .module = tty_mod },
        },
    });

    const common_tests = b.addTest(.{
        .root_module = common_mod,
    });
    const run_common_tests = b.addRunArtifact(common_tests);

    const tty_tests = b.addTest(.{
        .root_module = tty_mod,
    });
    const run_tty_tests = b.addRunArtifact(tty_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_common_tests.step);
    test_step.dependOn(&run_tty_tests.step);
    
    const simple_example_exe = b.addExecutable(.{
        .name = "simple_example",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,

            .root_source_file = b.path("examples/simple.zig"),

            .imports = &.{
                .{ .name = "zttio", .module = zttio_mod },
            },
        }),
    });
    
    const examples_step = b.step("examples", "build examples");
    examples_step.dependOn(&simple_example_exe.step);
}
