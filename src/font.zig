const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const ft = @cImport({
    @cInclude("ft2build.h");
    @cInclude("freetype/freetype.h");
});

const harfb = @cImport({
    @cInclude("hb.h");

    @cDefine("HAVE_FREETYPE", "1");
    @cInclude("hb-ft.h");
});

var freetype_lib: ft.FT_Library = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    const init_error = ft.FT_Init_FreeType(&freetype_lib);
    if (init_error != ft.FT_Err_Ok) {
        std.log.err("FreeType init failed: {d}", .{init_error});
    }

    // geist_light_16 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-Light.ttf"), 16);
    // geist_light_24 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-Light.ttf"), 24);
    // geist_light_32 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-Light.ttf"), 32);
    geist_light_48 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-Light.ttf"), 48);
    // geist_light_64 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-Light.ttf"), 64);
    // geist_light_72 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-Light.ttf"), 72);
    // geist_light_96 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-Light.ttf"), 96);

    // geist_regular_16 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-Regular.ttf"), 16);
    // geist_regular_24 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-Regular.ttf"), 24);
    // geist_regular_32 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-Regular.ttf"), 32);
    geist_regular_48 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-Regular.ttf"), 48);
    // geist_regular_64 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-Regular.ttf"), 64);
    // geist_regular_72 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-Regular.ttf"), 72);
    // geist_regular_96 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-Regular.ttf"), 96);

    // geist_medium_16 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-Medium.ttf"), 16);
    // geist_medium_24 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-Medium.ttf"), 24);
    // geist_medium_32 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-Medium.ttf"), 32);
    geist_medium_48 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-Medium.ttf"), 48);
    // geist_medium_64 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-Medium.ttf"), 64);
    // geist_medium_72 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-Medium.ttf"), 72);
    // geist_medium_96 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-Medium.ttf"), 96);

    // geist_semibold_16 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-SemiBold.ttf"), 16);
    // geist_semibold_24 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-SemiBold.ttf"), 24);
    // geist_semibold_32 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-SemiBold.ttf"), 32);
    geist_semibold_48 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-SemiBold.ttf"), 48);
    // geist_semibold_64 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-SemiBold.ttf"), 64);
    // geist_semibold_72 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-SemiBold.ttf"), 72);
    // geist_semibold_96 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-SemiBold.ttf"), 96);

    // geist_bold_16 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-Bold.ttf"), 16);
    // geist_bold_24 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-Bold.ttf"), 24);
    // geist_bold_32 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-Bold.ttf"), 32);
    geist_bold_48 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-Bold.ttf"), 48);
    // geist_bold_64 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-Bold.ttf"), 64);
    // geist_bold_72 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-Bold.ttf"), 72);
    // geist_bold_96 = try .fromMemory(allocator, @embedFile("resources/Font/Geist/Geist-Bold.ttf"), 96);
}

pub fn deinit() void {
    _ = ft.FT_Done_FreeType(freetype_lib);
}

pub var geist_light_16: Font = undefined;
pub var geist_light_24: Font = undefined;
pub var geist_light_32: Font = undefined;
pub var geist_light_48: Font = undefined;
pub var geist_light_64: Font = undefined;
pub var geist_light_72: Font = undefined;
pub var geist_light_96: Font = undefined;
pub var geist_regular_16: Font = undefined;
pub var geist_regular_24: Font = undefined;
pub var geist_regular_32: Font = undefined;
pub var geist_regular_48: Font = undefined;
pub var geist_regular_64: Font = undefined;
pub var geist_regular_72: Font = undefined;
pub var geist_regular_96: Font = undefined;
pub var geist_medium_16: Font = undefined;
pub var geist_medium_24: Font = undefined;
pub var geist_medium_32: Font = undefined;
pub var geist_medium_48: Font = undefined;
pub var geist_medium_64: Font = undefined;
pub var geist_medium_72: Font = undefined;
pub var geist_medium_96: Font = undefined;
pub var geist_semibold_16: Font = undefined;
pub var geist_semibold_24: Font = undefined;
pub var geist_semibold_32: Font = undefined;
pub var geist_semibold_48: Font = undefined;
pub var geist_semibold_64: Font = undefined;
pub var geist_semibold_72: Font = undefined;
pub var geist_semibold_96: Font = undefined;
pub var geist_bold_16: Font = undefined;
pub var geist_bold_24: Font = undefined;
pub var geist_bold_32: Font = undefined;
pub var geist_bold_48: Font = undefined;
pub var geist_bold_64: Font = undefined;
pub var geist_bold_72: Font = undefined;
pub var geist_bold_96: Font = undefined;

/// Represents a rendered glyph bitmap (8-bit grayscale).
/// must be freed with `deinit`.
pub const GlyphBitmap = struct {
    alloc: Allocator,
    pixels: []u8,
    width: i32,
    height: i32,
    pitch: i32,
    top: i32,
    left: i32,

    pub fn deinit(self: *GlyphBitmap) void {
        self.alloc.free(self.pixels);
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

pub const Font = struct {
    alloc: Allocator,
    ft_face: ft.FT_Face,
    harfb_font: *harfb.hb_font_t,
    pixel_height: f32,
    atlas: FontAtlas,

    pub fn fromMemory(allocator: Allocator, comptime font_data: []const u8, pixel_height: f32) !Font {
        const now = std.time.milliTimestamp();
        defer std.debug.print("Font init took {d}ms\n", .{std.time.milliTimestamp() - now});

        var font: Font = undefined;
        var face: ft.FT_Face = undefined;
        const face_error = ft.FT_New_Memory_Face(
            freetype_lib,
            font_data.ptr,
            @as(ft.FT_Long, @intCast(font_data.len)),
            0,
            &face,
        );
        if (face_error != ft.FT_Err_Ok) {
            std.log.err("FreeType new memory face failed: {s}", .{ft.FT_Error_String(face_error)});
            return error.FreeTypeNewMemoryFaceFailed;
        }
        errdefer assert(ft.FT_Done_Face(face) == ft.FT_Err_Ok);

        const set_size_error = ft.FT_Set_Pixel_Sizes(face, 0, @as(ft.FT_UInt, @intFromFloat(pixel_height)));
        if (set_size_error != ft.FT_Err_Ok) {
            std.log.err("FreeType set pixel sizes failed: {s}", .{ft.FT_Error_String(set_size_error)});
            return error.FreeTypeSetPixelSizesFailed;
        }

        const harfb_font = harfb.hb_ft_font_create(@ptrCast(face), null) orelse
            return error.HarfBuzzFontCreateFailed;

        // TODO: this block below is really cringe
        font = .{
            .alloc = allocator,
            .ft_face = face,
            .harfb_font = harfb_font,
            .pixel_height = pixel_height,
            .atlas = undefined,
        };
        const atlas = try FontAtlas.init(allocator, font);
        font.atlas = atlas;
        return font;
    }

    pub fn deinit(self: *Font) void {
        assert(ft.FT_Done_Face(self.ft_face) == ft.FT_Err_Ok);
        harfb.hb_font_destroy(self.harfb_font);
        self.atlas.deinit();
    }

    pub fn shapeText(self: Font, text: []const u8) ![]ShapedGlyph {
        if (text.len == 0) return &.{};
        if (std.unicode.utf8ValidateSlice(text) == false) return error.InvalidUtf8;

        const buffer = harfb.hb_buffer_create() orelse return error.HarfBuzzBufferCreateFailed;
        defer harfb.hb_buffer_destroy(buffer);

        const len: c_int = @intCast(text.len);
        harfb.hb_buffer_add_utf8(buffer, text.ptr, len, 0, len);

        harfb.hb_buffer_guess_segment_properties(buffer);

        harfb.hb_shape(self.harfb_font, buffer, null, 0);

        const glyph_count = harfb.hb_buffer_get_length(buffer);
        const glyph_infos = harfb.hb_buffer_get_glyph_infos(buffer, null) orelse return error.HarfBuzzBufferGetGlyphInfosFailed;
        const glyph_positions = harfb.hb_buffer_get_glyph_positions(buffer, null) orelse return error.HarfBuzzBufferGetGlyphPositionsFailed;

        const shaped_glyphs = try self.alloc.alloc(ShapedGlyph, @as(usize, @intCast(glyph_count)));

        for (0..glyph_count) |i| {
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

    pub fn deinitShapedText(self: Font, shaped_glyphs: []ShapedGlyph) void {
        self.alloc.free(shaped_glyphs);
    }

    /// Rasterizes a glyph by index to an 8-bit grayscale bitmap.
    /// The caller owns the returned bitmap and must call `deinit` on it.
    pub fn rasterizeGlyph(self: Font, glyph_index: usize) !GlyphBitmap {
        const face = self.ft_face.?;

        const error_code = ft.FT_Load_Glyph(
            face,
            @intCast(glyph_index),
            ft.FT_LOAD_DEFAULT | ft.FT_LOAD_RENDER,
        );
        if (error_code != ft.FT_Err_Ok) {
            return error.FreeTypeNewMemoryFaceFailed;
        }

        const bitmap = &face.*.glyph.*.bitmap;

        const pixels_size = @as(usize, @intCast(@as(c_int, @intCast(bitmap.rows)) * bitmap.pitch));
        const pixels = try self.alloc.alloc(u8, pixels_size);
        errdefer self.allocator.free(pixels);

        @memcpy(pixels, bitmap.buffer);

        return GlyphBitmap{
            .alloc = self.alloc,
            .width = @intCast(bitmap.width),
            .height = @intCast(bitmap.rows),
            .pitch = bitmap.pitch,
            .pixels = pixels,
            .top = face.*.glyph.*.bitmap_top,
            .left = face.*.glyph.*.bitmap_left,
        };
    }
};

const Rect = struct {
    x: u32,
    y: u32,
    w: u32,
    h: u32,
};

const FontAtlas = struct {
    alloc: Allocator,
    pixel: []u8,
    width: u32,
    height: u32,
    glyphs_map: std.AutoHashMap(u32, Rect), // maps to uv texture coordinates (x, y, width, height)

    pub fn init(alloc: Allocator, font: Font) !FontAtlas {
        const num_glyphs: usize = @intCast(font.ft_face.*.num_glyphs);

        var glyphs_map = std.AutoHashMap(u32, Rect).init(alloc);
        errdefer glyphs_map.deinit();

        try glyphs_map.ensureTotalCapacity(@intCast(num_glyphs));

        var glyphs = try std.ArrayList(GlyphBitmap).initCapacity(alloc, num_glyphs);
        defer {
            for (glyphs.items) |*g| g.deinit();
            glyphs.deinit(alloc);
        }

        // Step 1: Collect glyphs and estimate size
        var total_width: u32 = 0;
        var max_height: u32 = 0;
        for (0..num_glyphs) |i| {
            // const now = std.time.microTimestamp();
            var glyph = try font.rasterizeGlyph(i);
            // std.debug.print("rasterizing glyph took {d}µs\n", .{std.time.microTimestamp() - now});
            if (glyph.width > 0 and glyph.height > 0) {
                glyphs_map.putAssumeCapacityNoClobber(@intCast(i), .{
                    .x = total_width,
                    .y = 0,
                    .w = @intCast(glyph.width),
                    .h = @intCast(glyph.height),
                });
                glyphs.appendAssumeCapacity(glyph);

                total_width += @intCast(glyph.width);
                max_height = @max(max_height, @as(u32, @intCast(glyph.height)));
            } else {
                glyph.deinit();
            }
        }
        std.debug.print("total width: {d}, max height: {d}\n", .{ total_width, max_height });

        var pixel = try alloc.alloc(u8, total_width * max_height);
        errdefer alloc.free(pixel);

        var x_offset: u32 = 0;
        for (glyphs.items) |g| {
            const gw: usize = @intCast(g.width);
            const gh: usize = @intCast(g.height);
            const pitch: usize = @intCast(g.pitch);

            // Copy row by row into atlas
            for (0..gh) |row| {
                const src_start = row * pitch;
                const src = g.pixels[src_start .. src_start + gw];

                const dst_start = row * total_width + x_offset;
                const dst = pixel[dst_start .. dst_start + gw];

                @memcpy(dst, src);
            }

            x_offset += @intCast(g.width);
        }

        // try writeToBMP(alloc, max_height, glyphs.items);

        return .{
            .alloc = alloc,
            .width = total_width,
            .height = max_height,
            .pixel = pixel,
            .glyphs_map = glyphs_map,
        };
    }

    pub fn deinit(self: *FontAtlas) void {
        self.alloc.free(self.pixel);
    }

    pub fn getGlyphDimensions(self: FontAtlas, glyph_index: u32) Rect {
        return self.glyphs_map.get(glyph_index).?;
    }

    fn writeToBMP(alloc: Allocator, max_height: u32, glyphs: []GlyphBitmap) !void {
        // Step 2: Use a square atlas with row-based packing
        const atlas_width: u32 = 1024 * 2; // Adjust as needed (power of 2 recommended)
        var atlas_height: u32 = max_height;
        var current_x: u32 = 0;
        var current_y: u32 = 0;
        var row_height: u32 = 0;

        for (glyphs) |g| {
            const w: u32 = @intCast(g.width);
            const h: u32 = @intCast(g.height);
            if (current_x + w > atlas_width) {
                current_x = 0;
                current_y += row_height;
                row_height = 0;
            }
            current_x += w;
            row_height = @max(row_height, h);
        }
        atlas_height = current_y + row_height; // Final height
        if (atlas_height > atlas_width) {
            return error.AtlasTooSmall; // Increase atlas_width and retry
        }
        std.debug.print("Final atlas size: {d}x{d}\n", .{ atlas_width, atlas_height });

        // Step 3: Create atlas pixels
        var atlas_pixels = try alloc.alloc(u8, atlas_width * atlas_height);
        defer alloc.free(atlas_pixels);
        @memset(atlas_pixels, 0);

        current_x = 0;
        current_y = 0;
        row_height = 0;
        for (glyphs) |g| {
            const w: u32 = @intCast(g.width);
            const h: u32 = @intCast(g.height);
            if (current_x + w > atlas_width) {
                current_x = 0;
                current_y += row_height;
                row_height = 0;
            }
            for (0..@as(usize, @intCast(g.height))) |row| {
                const src_start = row * @as(usize, @intCast(g.pitch));
                const src = g.pixels[src_start .. src_start + @as(usize, @intCast(g.width))];
                const dst_offset = (current_y + @as(u32, @intCast(row))) * @as(usize, atlas_width) + @as(usize, current_x);
                @memcpy(atlas_pixels[dst_offset .. dst_offset + src.len], src);
            }
            current_x += w;
            row_height = @max(row_height, h);
        }

        // Step 4: Write BMP file
        const file = try std.fs.cwd().createFile("font_atlas.bmp", .{});
        defer file.close();

        // BMP file header (14 bytes)
        const file_size = 14 + 40 + (atlas_width * atlas_height * 3);
        const file_header = [_]u8{
            'B',                                         'M',
            @as(u8, @intCast(file_size & 0xFF)),         @as(u8, @intCast((file_size >> 8) & 0xFF)),
            @as(u8, @intCast((file_size >> 16) & 0xFF)), @as(u8, @intCast((file_size >> 24) & 0xFF)),
            0,                                           0,
            0,                                           0,
            54,                                          0,
            0,                                           0,
        };

        // DIB header (40 bytes, BITMAPINFOHEADER)
        const dib_header = [_]u8{
            40,                                     0,                                             0,                                              0,
            @as(u8, @intCast(atlas_width & 0xFF)),  @as(u8, @intCast((atlas_width >> 8) & 0xFF)),  @as(u8, @intCast((atlas_width >> 16) & 0xFF)),  @as(u8, @intCast((atlas_width >> 24) & 0xFF)),
            @as(u8, @intCast(atlas_height & 0xFF)), @as(u8, @intCast((atlas_height >> 8) & 0xFF)), @as(u8, @intCast((atlas_height >> 16) & 0xFF)), @as(u8, @intCast((atlas_height >> 24) & 0xFF)),
            1,                                      0,                                             24,                                             0,
            0,                                      0,                                             0,                                              0,
            0,                                      0,                                             0,                                              0,
            0,                                      0,                                             0,                                              0,
            0,                                      0,                                             0,                                              0,
            0,                                      0,                                             0,                                              0,
            0,                                      0,                                             0,                                              0,
        };

        try file.writeAll(&file_header);
        try file.writeAll(&dib_header);

        // Convert grayscale to RGB, flip Y for BMP
        var rgb_pixels = try alloc.alloc(u8, atlas_width * atlas_height * 3);
        defer alloc.free(rgb_pixels);
        for (0..atlas_height) |y| {
            for (0..atlas_width) |x| {
                const gray = atlas_pixels[(atlas_height - 1 - y) * atlas_width + x];
                const idx = (y * atlas_width + x) * 3;
                rgb_pixels[idx + 0] = gray; // B
                rgb_pixels[idx + 1] = gray; // G
                rgb_pixels[idx + 2] = gray; // R
            }
        }
        try file.writeAll(rgb_pixels);
    }
};
