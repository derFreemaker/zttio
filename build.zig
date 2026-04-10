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

    const zigimg_dep = b.dependency("zigimg", .{
        .target = target,
        .optimize = optimize,
    });
    const zigimg_mod = zigimg_dep.module("zigimg");

    const zttio_mod = b.addModule("zttio", .{
        .target = target,
        .optimize = optimize,

        .root_source_file = b.path("src/zttio.zig"),

        .imports = &.{
            .{ .name = "uucode", .module = uucode_mod },
            .{ .name = "zigimg", .module = zigimg_mod },
        },
    });
    if (target.result.os.tag == .windows) {
        if (b.lazyDependency("zigwin32", .{})) |zigwin32| {
            const mod = zigwin32.module("win32");

            zttio_mod.addImport("zigwin", mod);
            zttio_mod.addImport("zigwin", mod);
        }
    }

    const zttio_tests = b.addTest(.{
        .root_module = zttio_mod,
    });
    const run_zttio_tests = b.addRunArtifact(zttio_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_zttio_tests.step);

    if (b.option(bool, "examples", "build examples") orelse false) {
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

        b.installArtifact(simple_example_exe);
    }
}
