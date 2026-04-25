const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const uucode_dep = b.dependency("uucode", .{
        .target = target,
        .optimize = optimize,
        .fields = @as([]const []const u8, &.{ "east_asian_width", "grapheme_break", "general_category", "is_emoji_presentation", "uppercase_mapping" }),
    });
    const uucode_mod = uucode_dep.module("uucode");

    // const zigimg_dep = b.dependency("zigimg", .{
    //     .target = target,
    //     .optimize = optimize,
    // });
    // const zigimg_mod = zigimg_dep.module("zigimg");

    const zttio_mod = b.addModule("zttio", .{
        .target = target,
        .optimize = optimize,

        .root_source_file = b.path("src/zttio.zig"),

        .imports = &.{
            .{ .name = "uucode", .module = uucode_mod },
            // .{ .name = "zigimg", .module = zigimg_mod },
        },
    });
    if (target.result.os.tag == .windows) {
        if (b.lazyDependency("win32", .{})) |win32| {
            const mod = win32.module("win32");

            zttio_mod.addImport("win32", mod);
        }
    }

    const zttio_tests = b.addTest(.{
        .root_module = zttio_mod,
    });
    const run_zttio_tests = b.addRunArtifact(zttio_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_zttio_tests.step);

    const basic_example_exe = b.addExecutable(.{
        .name = "basic_example",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,

            .root_source_file = b.path("examples/basic.zig"),

            .imports = &.{
                .{ .name = "zttio", .module = zttio_mod },
            },
        }),
    });
    const basic_example_run_step = b.step("run-basic-example", "run basic example");
    const basic_example_cmd = b.addRunArtifact(basic_example_exe);
    basic_example_run_step.dependOn(&basic_example_cmd.step);
    basic_example_cmd.step.dependOn(&basic_example_exe.step);
    if (b.args) |args| {
        basic_example_cmd.addArgs(args);
    }
}
