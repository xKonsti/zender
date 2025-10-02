const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const unicode = std.unicode;

const ft = @cImport({
    @cInclude("ft2build.h");
    @cInclude("freetype/freetype.h");
});

const hb = @cImport({
    @cInclude("hb.h");
    @cDefine("HAVE_FREETYPE", "1");
    @cInclude("hb-ft.h");
});

const c = @cImport({
    @cInclude("stdlib.h");
});

pub const Error = error{
    FreeTypeInitFailed,
    FreeTypeNewMemoryFaceFailed,
    FreeTypeSetPixelSizesFailed,
    HarfBuzzFontCreateFailed,
    HarfBuzzBufferCreateFailed,
    HarfBuzzBufferAddUtf8Failed,
    HarfBuzzShapeFailed,
    InvalidUtf8,
    OutOfMemory,
};

/// Represents a rendered glyph bitmap (8-bit grayscale).
pub const GlyphBitmap = struct {
    width: i32,
    height: i32,
    pitch: i32,
    pixels: []u8,
    left: i32,
    top: i32,

    pub fn deinit(self: *GlyphBitmap, allocator: Allocator) void {
        allocator.free(self.pixels);
    }
};

/// Represents a shaped glyph with position and index for rendering.
pub const ShapedGlyph = struct {
    glyph_index: u32,
    x_advance: f32,
    y_advance: f32,
    x_offset: f32,
    y_offset: f32,
};

/// A loaded font from TTF data in memory.
pub const Font = struct {
    allocator: Allocator,
    ft_library: ft.FT_Library,
    ft_face: ?ft.FT_Face,
    hb_font: ?*hb.hb_font_t,
    pixel_size: f32,

    /// Deinitializes the font, freeing all resources.
    pub fn deinit(self: *Font) void {
        if (self.hb_font) |hbf| {
            hb.hb_font_destroy(hbf);
        }
        if (self.ft_face) |ftf| {
            _ = ft.FT_Done_Face(ftf);
        }
        _ = ft.FT_Done_FreeType(self.ft_library);
        self.ft_face = null;
        self.hb_font = null;
    }

    /// Shapes a UTF-8 text string into a list of positioned glyphs.
    /// The returned slice must be freed with `deinitShapedText`.
    pub fn shapeText(self: Font, text: []const u8) Error![]ShapedGlyph {
        if (text.len == 0) return &.{};

        // Validate UTF-8 (optional but good practice).
        if (unicode.utf8ValidateSlice(text) == false) return Error.InvalidUtf8;

        const buffer = hb.hb_buffer_create() orelse return Error.HarfBuzzBufferCreateFailed;
        defer hb.hb_buffer_destroy(buffer);

        const len = @as(c_int, @intCast(text.len));
        hb.hb_buffer_add_utf8(buffer, text.ptr, len, 0, len);

        hb.hb_buffer_guess_segment_properties(buffer);

        hb.hb_shape(self.hb_font.?, buffer, null, 0);

        const glyph_count = hb.hb_buffer_get_length(buffer);
        const glyph_infos = hb.hb_buffer_get_glyph_infos(buffer, null);
        const glyph_positions = hb.hb_buffer_get_glyph_positions(buffer, null);

        if (glyph_infos == null or glyph_positions == null) {
            return Error.OutOfMemory;
        }

        const shaped_glyphs = try self.allocator.alloc(ShapedGlyph, @as(usize, @intCast(glyph_count)));
        errdefer self.allocator.free(shaped_glyphs);

        var i: usize = 0;
        while (i < glyph_count) : (i += 1) {
            const info = glyph_infos[i];
            const pos = glyph_positions[i];

            shaped_glyphs[i] = .{
                .glyph_index = info.codepoint,
                .x_advance = @as(f32, @floatFromInt(pos.x_advance)) / 64.0, // HarfBuzz uses 64x fixed-point.
                .y_advance = @as(f32, @floatFromInt(pos.y_advance)) / 64.0,
                .x_offset = @as(f32, @floatFromInt(pos.x_offset)) / 64.0,
                .y_offset = @as(f32, @floatFromInt(pos.y_offset)) / 64.0,
            };
        }

        return shaped_glyphs;
    }

    /// Frees a slice returned from `shapeText`.
    pub fn deinitShapedText(self: Font, shaped_glyphs: []ShapedGlyph) void {
        self.allocator.free(shaped_glyphs);
    }

    /// Rasterizes a glyph by index to an 8-bit grayscale bitmap.
    /// The caller owns the returned bitmap and must call `deinit` on it.
    pub fn rasterizeGlyph(self: Font, glyph_index: u32) Error!GlyphBitmap {
        const face = self.ft_face.?;

        const error_code = ft.FT_Load_Glyph(
            face,
            glyph_index,
            ft.FT_LOAD_DEFAULT | ft.FT_LOAD_RENDER,
        );
        if (error_code != ft.FT_Err_Ok) {
            return Error.FreeTypeNewMemoryFaceFailed;
        }

        const glyph = &face.glyph;
        const bitmap = &glyph.bitmap;

        const pixels_size = @as(usize, @intCast(bitmap.rows * bitmap.pitch));
        const pixels = try self.allocator.alloc(u8, pixels_size);
        errdefer self.allocator.free(pixels);

        @memcpy(pixels[0..pixels_size], bitmap.buffer.?[0..pixels_size]);

        return GlyphBitmap{
            .width = bitmap.width,
            .height = bitmap.rows,
            .pitch = bitmap.pitch,
            .pixels = pixels,
            .left = glyph.bitmap_left,
            .top = glyph.bitmap_top,
        };
    }
};

/// Creates a font from TTF data loaded into memory (e.g., via @embedFile).
/// `pixel_size` is the height in pixels for rendering.
pub fn createFontFromMemory(allocator: Allocator, font_data: []const u8, pixel_size: f32) Error!Font {
    if (font_data.len == 0) {
        return Error.FreeTypeNewMemoryFaceFailed;
    }

    var library: ft.FT_Library = undefined;
    const init_error = ft.FT_Init_FreeType(&library);
    if (init_error != ft.FT_Err_Ok) {
        return Error.FreeTypeInitFailed;
    }

    var face: ft.FT_Face = undefined;
    const face_error = ft.FT_New_Memory_Face(
        library,
        font_data.ptr,
        @as(ft.FT_Long, @intCast(font_data.len)),
        0,
        &face,
    );
    if (face_error != ft.FT_Err_Ok) {
        _ = ft.FT_Done_FreeType(library);
        return Error.FreeTypeNewMemoryFaceFailed;
    }

    const set_size_error = ft.FT_Set_Pixel_Sizes(face, 0, @as(ft.FT_UInt, @intFromFloat(pixel_size)));
    if (set_size_error != ft.FT_Err_Ok) {
        _ = ft.FT_Done_Face(face);
        _ = ft.FT_Done_FreeType(library);
        return Error.FreeTypeSetPixelSizesFailed;
    }

    const hb_font = hb.hb_ft_font_create(@ptrCast(face), null);
    if (hb_font == null) {
        _ = ft.FT_Done_Face(face);
        _ = ft.FT_Done_FreeType(library);
        return Error.HarfBuzzFontCreateFailed;
    }

    return Font{
        .allocator = allocator,
        .ft_library = library,
        .ft_face = face,
        .hb_font = hb_font,
        .pixel_size = pixel_size,
    };
}
