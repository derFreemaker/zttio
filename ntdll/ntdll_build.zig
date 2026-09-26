const std = @import("std");

// TODO: revert function to normal build signature
pub fn build(b: *std.Build, test_step: *std.Build.Step, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    // const target = b.standardTargetOptions(.{});
    // const optimize = b.standardOptimizeOption(.{});

    std.debug.assert(target.result.os.tag == .windows);

    const ntdll_mod = b.addModule("ntdll", .{
        .target = target,
        .optimize = optimize,

        .root_source_file = b.path("ntdll/src/root.zig"),
    });
    const ntdll_tests = b.addTest(.{
        .root_module = ntdll_mod,
    });
    const run_ntdll_tests = b.addRunArtifact(ntdll_tests);

    // TODO: add test step when extracting into own library
    test_step.dependOn(&run_ntdll_tests.step);

    return ntdll_mod;
}
