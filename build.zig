const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library
    const lib = b.addStaticLibrary(.{
        .name = "si-runtime",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    // Main executable (demo)
    const exe = b.addExecutable(.{
        .name = "si-runtime-demo",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("si", &lib.root_module);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the demo");
    run_step.dependOn(&run_cmd.step);

    // Unit tests
    const test_files = &[_][]const u8{
        "tests/conservation_test.zig",
        "tests/spectral_test.zig",
        "tests/capability_test.zig",
        "tests/cell_test.zig",
        "tests/agent_test.zig",
    };

    const test_step = b.step("test", "Run all tests");

    for (test_files) |path| {
        const t = b.addTest(.{
            .root_source_file = b.path(path),
            .target = target,
            .optimize = optimize,
        });
        t.root_module.addImport("si", &lib.root_module);
        test_step.dependOn(&t.step);
    }

    // Check step
    const check = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const check_step = b.step("check", "Check compilation without running tests");
    check_step.dependOn(&check.step);
}
