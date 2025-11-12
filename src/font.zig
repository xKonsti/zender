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
var font_cache: FontCache = undefined;

pub fn init(allocator: Allocator) !void {
    const init_error = ft.FT_Init_FreeType(&freetype_lib);
    if (init_error != ft.FT_Err_Ok) {
        std.log.err("FreeType init failed: {d}", .{init_error});
        return error.FreeTypeInitFailed;
    }

    font_cache = FontCache.init(allocator);
}

pub fn deinit() void {
    font_cache.deinit();
    _ = ft.FT_Done_FreeType(freetype_lib);
}

// =============================================================================
// Public API
// =============================================================================

/// Font family enum - add more font families here
pub const FontFamily = enum {
    geist,
    geist_mono,
    // Add more fonts as needed:
    // roboto,
    // inter,
    // etc.

    fn getFontData(self: FontFamily, style: FontStyle) []const u8 {
        return switch (self) {
            .geist => switch (style) {
                .light => @embedFile("resources/Font/Geist/Geist-Light.ttf"),
                .regular => @embedFile("resources/Font/Geist/Geist-Regular.ttf"),
                .medium => @embedFile("resources/Font/Geist/Geist-Medium.ttf"),
                .semibold => @embedFile("resources/Font/Geist/Geist-SemiBold.ttf"),
                .bold => @embedFile("resources/Font/Geist/Geist-Bold.ttf"),
                .extrabold => @embedFile("resources/Font/Geist/Geist-ExtraBold.ttf"),
                .black => @embedFile("resources/Font/Geist/Geist-Black.ttf"),
            },
            .geist_mono => switch (style) {
                .light => @embedFile("resources/Font/GeistMono/GeistMono-Light.ttf"),
                .regular => @embedFile("resources/Font/GeistMono/GeistMono-Regular.ttf"),
                .medium => @embedFile("resources/Font/GeistMono/GeistMono-Medium.ttf"),
                .semibold => @embedFile("resources/Font/GeistMono/GeistMono-SemiBold.ttf"),
                .bold => @embedFile("resources/Font/GeistMono/GeistMono-Bold.ttf"),
                .extrabold => @embedFile("resources/Font/GeistMono/GeistMono-ExtraBold.ttf"),
                .black => @embedFile("resources/Font/GeistMono/GeistMono-Black.ttf"),
            },
            // Add more font families:
            // .roboto => switch (style) { ... },
        };
    }
};

pub const FontStyle = enum {
    light,
    regular,
    medium,
    semibold,
    bold,
    extrabold,
    black,
};

/// Get a font with the specified family, style and size
/// Fonts are cached, so repeated calls are fast
pub fn getFont(family: FontFamily, style: FontStyle, size: f32) !*Font {
    return font_cache.getOrLoad(family, style, size);
}

/// Preload commonly used fonts during startup (optional but recommended)
pub fn preloadCommon(allocator: Allocator) !void {
    _ = allocator;

    const common_sizes = [_]f32{ 16, 24, 32, 48 };
    const common_styles = [_]FontStyle{ .regular, .medium, .bold };

    for (common_styles) |style| {
        for (common_sizes) |size| {
            _ = try getFont(.geist, style, size);
        }
    }
}

// =============================================================================
// Font Cache - Internal
// =============================================================================

/// Cache key combining family, style and size
const FontKey = struct {
    family: FontFamily,
    style: FontStyle,
    size: u16,

    pub fn hash(self: FontKey, hasher_seed: u64) u64 {
        var hasher = std.hash.Wyhash.init(hasher_seed);
        hasher.update(std.mem.asBytes(&self.family));
        hasher.update(std.mem.asBytes(&self.style));
        hasher.update(std.mem.asBytes(&self.size));
        return hasher.final();
    }

    pub fn eql(self: FontKey, other: FontKey) bool {
        return self.family == other.family and
            self.style == other.style and
            self.size == other.size;
    }
};

const FontCache = struct {
    allocator: Allocator,
    fonts: std.HashMap(FontKey, Font, FontKeyContext, std.hash_map.default_max_load_percentage),
    mutex: std.Thread.Mutex,

    const FontKeyContext = struct {
        pub fn hash(_: @This(), key: FontKey) u64 {
            return key.hash(0);
        }
        pub fn eql(_: @This(), a: FontKey, b: FontKey) bool {
            return a.eql(b);
        }
    };

    fn init(allocator: Allocator) FontCache {
        return .{
            .allocator = allocator,
            .fonts = std.HashMap(FontKey, Font, FontKeyContext, std.hash_map.default_max_load_percentage).init(allocator),
            .mutex = .{},
        };
    }

    fn deinit(self: *FontCache) void {
        var it = self.fonts.valueIterator();
        while (it.next()) |font| {
            var f = font.*;
            f.deinit();
        }
        self.fonts.deinit();
    }

    /// Get or load a font. Thread-safe.
    fn getOrLoad(self: *FontCache, family: FontFamily, style: FontStyle, size: f32) !*Font {
        // Quantize size to reduce cache entries
        const quantized_size = quantizeSize(size);
        const key = FontKey{ .family = family, .style = style, .size = quantized_size };

        self.mutex.lock();
        defer self.mutex.unlock();

        // Check if already loaded
        if (self.fonts.getPtr(key)) |font| {
            return font;
        }

        // Load new font
        const font_data = family.getFontData(style);
        const font = try Font.fromMemory(self.allocator, font_data, @floatFromInt(quantized_size));

        try self.fonts.put(key, font);
        return self.fonts.getPtr(key).?;
    }

    /// Quantize font size to standard sizes to reduce cache entries
    fn quantizeSize(size: f32) u16 {
        const size_int: u16 = @intFromFloat(@round(size));
        return switch (size_int) {
            0...16 => 16,
            17...20 => 20,
            21...24 => 24,
            25...28 => 28,
            29...32 => 32,
            33...40 => 40,
            41...48 => 48,
            49...56 => 56,
            57...64 => 64,
            65...72 => 72,
            73...96 => 96,
            else => 96,
        };
    }
};

// =============================================================================
// Font & Related Types
// =============================================================================

/// Represents a rendered glyph bitmap (8-bit grayscale).
/// Must be freed with `deinit`.
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
    /// maps to byte index in the original text
    cluster: u32,
    bearing_x: f32, // horizontal left-bearing in pixel units
    glyph_width: f32, // glyph bounding width in pixel units
};

pub const Font = struct {
    id: u64,
    alloc: Allocator,
    ft_face: ft.FT_Face,
    harfb_font: *harfb.hb_font_t,
    pixel_height: f32,
    atlas: FontAtlas,
    units_per_em: u16,

    pub fn fromMemory(allocator: Allocator, font_data: []const u8, pixel_height: f32) !Font {
        const now = std.time.milliTimestamp();
        defer std.debug.print("Font init took {d}ms for size {d}\n", .{ std.time.milliTimestamp() - now, pixel_height });

        var hasher = std.hash.Wyhash.init(0);
        hasher.update(std.mem.asBytes(&pixel_height));
        hasher.update(font_data);

        var face: ft.FT_Face = undefined;
        const face_error = ft.FT_New_Memory_Face(
            freetype_lib,
            font_data.ptr,
            @as(ft.FT_Long, @intCast(font_data.len)),
            0,
            &face,
        );
        if (face_error != ft.FT_Err_Ok) {
            std.log.err("FreeType new memory face failed: {d}", .{face_error});
            return error.FreeTypeNewMemoryFaceFailed;
        }
        errdefer _ = ft.FT_Done_Face(face);

        if (face == null) {
            return error.FreeTypeFaceNull;
        }

        const set_size_error = ft.FT_Set_Pixel_Sizes(face, 0, @as(ft.FT_UInt, @intFromFloat(pixel_height)));
        if (set_size_error != ft.FT_Err_Ok) {
            std.log.err("FreeType set pixel sizes failed: {d}", .{set_size_error});
            return error.FreeTypeSetPixelSizesFailed;
        }

        const harfb_font = harfb.hb_ft_font_create(@ptrCast(face), null) orelse
            return error.HarfBuzzFontCreateFailed;
        errdefer harfb.hb_font_destroy(harfb_font);

        var font: Font = .{
            .id = hasher.final(),
            .alloc = allocator,
            .ft_face = face,
            .harfb_font = harfb_font,
            .pixel_height = pixel_height,
            .atlas = undefined,
            .units_per_em = face.*.units_per_EM,
        };

        const atlas = try FontAtlas.init(allocator, font);
        font.atlas = atlas;
        return font;
    }

    pub fn deinit(self: *Font) void {
        // 1. Destroy HarfBuzz font FIRST (it references ft_face internally)
        harfb.hb_font_destroy(self.harfb_font);

        // 2. Deinit atlas (doesn't depend on ft_face anymore)
        self.atlas.deinit();

        // 3. Finally destroy FreeType face
        const result = ft.FT_Done_Face(self.ft_face);
        if (result != ft.FT_Err_Ok) {
            std.log.err("Failed to deinitialize font face: error code {d}", .{result});
        }
    }

    pub fn shapeText(self: Font, text: []const u8) ![]ShapedGlyph {
        if (text.len == 0) return &.{};
        if (std.unicode.utf8ValidateSlice(text) == false) return error.InvalidUtf8;

        const allocator = self.alloc;

        const buffer = harfb.hb_buffer_create() orelse return error.HarfBuzzBufferCreateFailed;
        defer harfb.hb_buffer_destroy(buffer);

        const len: c_int = @intCast(text.len);
        harfb.hb_buffer_add_utf8(buffer, text.ptr, len, 0, len);

        harfb.hb_buffer_guess_segment_properties(buffer);

        harfb.hb_shape(self.harfb_font, buffer, null, 0);

        const glyph_count = harfb.hb_buffer_get_length(buffer);
        const glyph_infos = harfb.hb_buffer_get_glyph_infos(buffer, null) orelse return error.HarfBuzzBufferGetGlyphInfosFailed;
        const glyph_positions = harfb.hb_buffer_get_glyph_positions(buffer, null) orelse return error.HarfBuzzBufferGetGlyphPositionsFailed;

        const shaped_glyphs = try allocator.alloc(ShapedGlyph, @as(usize, @intCast(glyph_count)));

        for (0..glyph_count) |i| {
            const info = glyph_infos[i];
            const pos = glyph_positions[i];
            _ = ft.FT_Load_Glyph(self.ft_face, @intCast(info.codepoint), ft.FT_LOAD_DEFAULT);

            const m = self.ft_face.*.glyph.*.metrics;
            const bearing_x_raw = @as(f32, @floatFromInt(m.horiBearingX)) / 64.0;
            const glyph_width_raw = @as(f32, @floatFromInt(m.width)) / 64.0;

            shaped_glyphs[i] = .{
                .glyph_index = info.codepoint,
                .x_advance = @as(f32, @floatFromInt(pos.x_advance)) / 64.0, // HarfBuzz uses 64x fixed-point.
                .y_advance = @as(f32, @floatFromInt(pos.y_advance)) / 64.0,
                .x_offset = @as(f32, @floatFromInt(pos.x_offset)) / 64.0,
                .y_offset = @as(f32, @floatFromInt(pos.y_offset)) / 64.0,
                .cluster = info.cluster,
                .bearing_x = bearing_x_raw,
                .glyph_width = glyph_width_raw,
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
        const face = self.ft_face;

        const error_code = ft.FT_Load_Glyph(
            face,
            @intCast(glyph_index),
            ft.FT_LOAD_DEFAULT | ft.FT_LOAD_RENDER,
        );
        if (error_code != ft.FT_Err_Ok) {
            return error.FreeTypeLoadGlyphFailed;
        }

        const bitmap = &face.*.glyph.*.bitmap;

        const pixels_size = @as(usize, @intCast(@as(c_int, @intCast(bitmap.rows)) * bitmap.pitch));
        const pixels = try self.alloc.alloc(u8, pixels_size);
        errdefer self.alloc.free(pixels);

        if (pixels_size > 0) {
            @memcpy(pixels, bitmap.buffer[0..pixels_size]);
        }

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

// =============================================================================
// Font Atlas
// =============================================================================

const Rect = struct {
    x: u32, // position in atlas (padded rect.x where bitmap starts)
    y: u32, // position in atlas
    w: u32, // bitmap width (not counting padding)
    h: u32, // bitmap height
    left: i32, // bitmap_left (FT bitmap_left) — horizontal bearing
    top: i32, // bitmap_top  (FT bitmap_top)  — vertical bearing (distance from baseline to top)
};

const packGlyph = struct {
    index: u32,
    bmp: GlyphBitmap,
};

pub const FontAtlas = struct {
    alloc: Allocator,
    pixel: []u8,
    width: u32,
    height: u32,
    glyphs_map: std.AutoHashMap(u32, Rect),

    pub fn init(alloc: Allocator, font: Font) !FontAtlas {
        assert(font.pixel_height <= 512);

        const MAX_ROW_WIDTH: u32 = 2048;
        const PADDING: u32 = 2; // pixels of transparent padding around each glyph
        const num_glyphs: usize = @intCast(font.ft_face.*.num_glyphs);

        var glyphs_map = std.AutoHashMap(u32, Rect).init(alloc);
        errdefer glyphs_map.deinit();

        try glyphs_map.ensureTotalCapacity(@intCast(num_glyphs));

        var pack = try std.ArrayList(packGlyph).initCapacity(alloc, num_glyphs);
        defer {
            for (pack.items) |*pg| pg.bmp.deinit();
            pack.deinit(alloc);
        }

        // Layout state
        var atlas_w: u32 = 0;
        var atlas_h: u32 = 0;
        var cursor_x: u32 = 0;
        var row_h: u32 = 0;

        // Collect glyph bitmaps and assign slots (row packing)
        for (0..num_glyphs) |gi| {
            var glyph = try font.rasterizeGlyph(gi);
            if (glyph.width == 0 or glyph.height == 0) {
                // Keep an entry so we know its bearings and advance, but no pixels
                glyphs_map.putAssumeCapacityNoClobber(@intCast(gi), .{
                    .x = 0,
                    .y = 0,
                    .w = 0,
                    .h = 0,
                    .left = glyph.left,
                    .top = glyph.top,
                });
                glyph.deinit();
                continue;
            }

            const gw: u32 = @as(u32, @intCast(glyph.width));
            const gh: u32 = @as(u32, @intCast(glyph.height));
            const gw_padded: u32 = gw + (PADDING * 2);
            const gh_padded: u32 = gh + (PADDING * 2);

            // wrap to next row if needed
            if (cursor_x + gw_padded > MAX_ROW_WIDTH) {
                atlas_w = @max(atlas_w, cursor_x);
                cursor_x = 0;
                atlas_h += row_h;
                row_h = 0;
            }

            const rect_x = cursor_x + PADDING;
            const rect_y = atlas_h + PADDING;

            glyphs_map.putAssumeCapacityNoClobber(@intCast(gi), .{
                .x = rect_x,
                .y = rect_y,
                .w = gw,
                .h = gh,
                .left = glyph.left,
                .top = glyph.top,
            });

            pack.appendAssumeCapacity(.{
                .index = @intCast(gi),
                .bmp = glyph,
            });

            cursor_x += gw_padded;
            row_h = @max(row_h, gh_padded);
        }

        atlas_w = @max(atlas_w, cursor_x);
        atlas_h += row_h;

        if (atlas_w == 0 or atlas_h == 0) {
            return error.AtlasTooSmall;
        }

        std.debug.print("Atlas size = {d}x{d}\n", .{ atlas_w, atlas_h });

        // Allocate and clear pixel buffer
        var pixel = try alloc.alloc(u8, @as(usize, atlas_w) * @as(usize, atlas_h));
        errdefer alloc.free(pixel);
        @memset(pixel, 0);

        // Copy each glyph bitmap into its reserved rect
        for (pack.items) |pg| {
            const gw: usize = @intCast(pg.bmp.width);
            const gh: usize = @intCast(pg.bmp.height);
            const pitch: usize = @intCast(pg.bmp.pitch);

            const rect = glyphs_map.get(pg.index) orelse continue;
            for (0..gh) |r| {
                const src_row = pg.bmp.pixels[(r * pitch)..(r * pitch + gw)];
                const dst_row = @as(usize, rect.y) + r;
                const dst_start = dst_row * @as(usize, atlas_w) + @as(usize, rect.x);
                const dst = pixel[dst_start .. dst_start + gw];
                @memcpy(dst, src_row);
            }
        }

        return .{
            .alloc = alloc,
            .width = atlas_w,
            .height = atlas_h,
            .pixel = pixel,
            .glyphs_map = glyphs_map,
        };
    }

    pub fn deinit(self: *FontAtlas) void {
        self.alloc.free(self.pixel);
        self.glyphs_map.deinit();
    }

    pub fn getGlyphDimensions(self: FontAtlas, glyph_index: u32) Rect {
        return self.glyphs_map.get(glyph_index).?;
    }
};
