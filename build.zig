const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "zender",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    addDependencies(b, exe, target, optimize);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}

fn addDependencies(
    b: *std.Build,
    exe: *std.Build.Step.Compile,
    target: anytype,
    optimize: anytype,
) void {
    const freetype = b.dependency("freetype", .{
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.linkLibrary(freetype.artifact("freetype"));
    exe.root_module.addIncludePath(freetype.path("include"));
    // exe.root_module.addImport("freetype_c", freetype.module("freetype_mod"));

    const harfbuzz = b.dependency("harfbuzz", .{
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addIncludePath(harfbuzz.path("src"));
    exe.root_module.linkLibrary(harfbuzz.artifact("harfbuzz"));

    const glfw = b.dependency("glfw_zig", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.linkLibrary(glfw.artifact("glfw"));

    const gl_bindings = @import("zigglgen").generateBindingsModule(b, .{
        .api = .gl,
        .version = .@"4.1",
        .profile = .core,
        .extensions = &.{ .ARB_clip_control, .NV_scissor_exclusive },
    });

    exe.root_module.addImport("gl", gl_bindings);
}
