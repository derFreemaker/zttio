const std = @import("std");

// TODO: revert function to normal build signature
pub fn build(b: *std.Build, test_step: *std.Build.Step, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) [2]*std.Build.Module {
    // const target = b.standardTargetOptions(.{});
    // const optimize = b.standardOptimizeOption(.{});

    std.debug.assert(target.result.os.tag == .windows);

    const ntdll_raw_mod = b.addModule("ntdll_raw", .{
        .target = target,
        .optimize = optimize,

        .root_source_file = b.path("src_ntdll/ntdll_raw/root.zig"),
    });
    const ntdll_raw_tests = b.addTest(.{
        .root_module = ntdll_raw_mod,
    });
    const run_ntdll_raw_tests = b.addRunArtifact(ntdll_raw_tests);

    const ntdll_mod = b.addModule("ntdll", .{
        .target = target,
        .optimize = optimize,

        .root_source_file = b.path("src_ntdll/ntdll/root.zig"),

        .imports = &.{
            .{ .name = "ntdll_raw", .module = ntdll_raw_mod },
        },
    });
    const ntdll_tests = b.addTest(.{
        .root_module = ntdll_mod,
    });
    const run_ntdll_tests = b.addRunArtifact(ntdll_tests);

    // TODO: add test step when extracting into own library
    test_step.dependOn(&run_ntdll_raw_tests.step);
    test_step.dependOn(&run_ntdll_tests.step);

    return .{ ntdll_raw_mod, ntdll_mod };
}
