const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const freetype_upstream = b.dependency("freetype_upstream", .{
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "freetype",
        .linkage = .static,
        .root_module = b.createModule(.{
            .link_libc = true,
            .target = target,
            .optimize = optimize,
        }),
    });

    lib.root_module.addIncludePath(freetype_upstream.path("include"));
    lib.root_module.addIncludePath(freetype_upstream.path("include/freetype"));
    lib.root_module.addCMacro("FT2_BUILD_LIBRARY", "1");
    lib.root_module.addCMacro("HAVE_UNISTD_H", "1");

    const sources = [_][]const u8{
        "src/autofit/autofit.c",
        "src/base/ftbase.c",
        "src/base/ftsystem.c",
        "src/base/ftdebug.c",
        "src/base/ftbbox.c",
        "src/base/ftbdf.c",
        "src/base/ftbitmap.c",
        "src/base/ftcid.c",
        "src/base/ftfstype.c",
        "src/base/ftgasp.c",
        "src/base/ftglyph.c",
        "src/base/ftgxval.c",
        "src/base/ftinit.c",
        "src/base/ftmm.c",
        "src/base/ftotval.c",
        "src/base/ftpatent.c",
        "src/base/ftpfr.c",
        "src/base/ftstroke.c",
        "src/base/ftsynth.c",
        "src/base/fttype1.c",
        "src/base/ftwinfnt.c",
        "src/bdf/bdf.c",
        "src/bzip2/ftbzip2.c",
        "src/cache/ftcache.c",
        "src/cff/cff.c",
        "src/cid/type1cid.c",
        "src/gzip/ftgzip.c",
        "src/lzw/ftlzw.c",
        "src/pcf/pcf.c",
        "src/pfr/pfr.c",
        "src/psaux/psaux.c",
        "src/pshinter/pshinter.c",
        "src/psnames/psnames.c",
        "src/raster/raster.c",
        "src/sdf/sdf.c",
        "src/sfnt/sfnt.c",
        "src/smooth/smooth.c",
        "src/svg/svg.c",
        "src/truetype/truetype.c",
        "src/type1/type1.c",
        "src/type42/type42.c",
        "src/winfonts/winfnt.c",
    };

    inline for (sources) |src| {
        lib.root_module.addCSourceFile(.{
            .file = freetype_upstream.path(src),
        });
    }

    b.installArtifact(lib);
}
