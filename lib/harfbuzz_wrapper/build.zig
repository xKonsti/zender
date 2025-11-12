const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const harfbuzz_upstream = b.dependency("harfbuzz_upstream", .{
        .target = target,
        .optimize = optimize,
    });

    const freetype = b.dependency("freetype", .{
        .target = target,
        .optimize = optimize,
    });

    // Also get freetype_upstream to access headers
    const freetype_upstream = freetype.builder.dependency("freetype_upstream", .{
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "harfbuzz",
        .linkage = .static,
        .root_module = b.createModule(.{
            .link_libcpp = true,
            .target = target,
            .optimize = optimize,
        }),
    });

    lib.root_module.addCMacro("HAVE_FREETYPE", "1");
    lib.root_module.addIncludePath(harfbuzz_upstream.path("src"));
    lib.root_module.addCSourceFile(.{ .file = harfbuzz_upstream.path("src/harfbuzz.cc") });
    lib.root_module.addCSourceFile(.{ .file = harfbuzz_upstream.path("src/hb-ft.cc") });

    lib.root_module.addIncludePath(freetype_upstream.path("include"));
    lib.root_module.linkLibrary(freetype.artifact("freetype"));

    b.installArtifact(lib);
}
