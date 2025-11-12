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

    addDependencies(b, exe.root_module, target, optimize);

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

    const lib = b.addModule("zender", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    addDependencies(b, lib, target, optimize);

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}

fn addDependencies(
    b: *std.Build,
    mod: *std.Build.Module,
    target: anytype,
    optimize: anytype,
) void {
    const freetype = b.dependency("freetype", .{
        .target = target,
        .optimize = optimize,
    });

    const freetype_upstream = b.dependency("freetype_upstream", .{
        .target = target,
        .optimize = optimize,
    });

    mod.linkLibrary(freetype.artifact("freetype"));
    mod.addIncludePath(freetype_upstream.path("include"));

    mod.addCSourceFile(.{
        .file = b.path("lib/stb/stb_image_impl.c"),
        .flags = &[_][]const u8{"-std=c99"},
    });

    const harfbuzz = b.dependency("harfbuzz", .{
        .target = target,
        .optimize = optimize,
    });

    const harfbuzz_upstream = b.dependency("harfbuzz_upstream", .{
        .target = target,
        .optimize = optimize,
    });

    mod.addIncludePath(harfbuzz_upstream.path("src"));
    mod.linkLibrary(harfbuzz.artifact("harfbuzz"));

    const glfw = b.dependency("glfw_zig", .{
        .target = target,
        .optimize = optimize,
    });
    mod.linkLibrary(glfw.artifact("glfw"));

    mod.addIncludePath(b.path("lib"));

    const gl_bindings = @import("zigglgen").generateBindingsModule(b, .{
        .api = .gl,
        .version = .@"4.1",
        .profile = .core,
        .extensions = &.{ .ARB_clip_control, .NV_scissor_exclusive },
    });

    mod.addImport("gl", gl_bindings);

    const zlayout = b.dependency("zlayout", .{
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("zlayout", zlayout.module("zlayout"));
}
