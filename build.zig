const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zimaclaw",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the zimaclaw binary");
    run_step.dependOn(&run_cmd.step);

    const main_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_main_tests = b.addRunArtifact(main_tests);

    const fang_tests = b.addTest(.{
        .root_source_file = b.path("tests/fang_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const fang_module = b.createModule(.{
        .root_source_file = b.path("src/fang.zig"),
        .target = target,
        .optimize = optimize,
    });
    fang_tests.root_module.addImport("fang", fang_module);
    const run_fang_tests = b.addRunArtifact(fang_tests);

    const drive_jsonl_tests = b.addTest(.{
        .root_source_file = b.path("tests/drive_jsonl_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const drive_jsonl_module = b.createModule(.{
        .root_source_file = b.path("src/drive_jsonl.zig"),
        .target = target,
        .optimize = optimize,
    });
    drive_jsonl_tests.root_module.addImport("drive_jsonl", drive_jsonl_module);
    const run_drive_jsonl_tests = b.addRunArtifact(drive_jsonl_tests);

    const drive_tests = b.addTest(.{
        .root_source_file = b.path("tests/drive_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const drive_module = b.createModule(.{
        .root_source_file = b.path("src/drive.zig"),
        .target = target,
        .optimize = optimize,
    });
    drive_tests.root_module.addImport("drive", drive_module);
    const run_drive_tests = b.addRunArtifact(drive_tests);

    const steer_tests = b.addTest(.{
        .root_source_file = b.path("tests/steer_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const steer_module = b.createModule(.{
        .root_source_file = b.path("src/steer.zig"),
        .target = target,
        .optimize = optimize,
    });
    steer_tests.root_module.addImport("steer", steer_module);
    const run_steer_tests = b.addRunArtifact(steer_tests);

    const spine_tests = b.addTest(.{
        .root_source_file = b.path("tests/spine_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const spine_module = b.createModule(.{
        .root_source_file = b.path("src/spine.zig"),
        .target = target,
        .optimize = optimize,
    });
    spine_tests.root_module.addImport("spine", spine_module);
    const run_spine_tests = b.addRunArtifact(spine_tests);

    const molt_run_tests = b.addTest(.{
        .root_source_file = b.path("tests/molt_run_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const claw_module = b.createModule(.{
        .root_source_file = b.path("src/claw.zig"),
        .target = target,
        .optimize = optimize,
    });
    molt_run_tests.root_module.addImport("claw", claw_module);
    const run_molt_run_tests = b.addRunArtifact(molt_run_tests);

    const test_step = b.step("test", "Run project tests");
    test_step.dependOn(&run_main_tests.step);
    test_step.dependOn(&run_fang_tests.step);
    test_step.dependOn(&run_drive_jsonl_tests.step);
    test_step.dependOn(&run_drive_tests.step);
    test_step.dependOn(&run_steer_tests.step);
    test_step.dependOn(&run_spine_tests.step);
    test_step.dependOn(&run_molt_run_tests.step);
}
