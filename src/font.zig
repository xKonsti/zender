const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const unicode = std.unicode;

pub const ft = @cImport({
    @cInclude("ft2build.h");
    @cInclude("freetype/freetype.h");
});

pub const hb = @cImport({
    @cInclude("hb.h");
});
