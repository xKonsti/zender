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

fn loadFontFromMem(allocator: std.mem.Allocator, comptime font_data: []const u8, pixel_height: f32, dst: *Font) void {
    // the times two is because of highdpi rendering
    // TODO: on normal screens without highdpi this seems to also be fine but look at it in greater detail
    dst.* = Font.fromMemory(allocator, font_data, pixel_height * 2) catch |err| {
        std.log.err("Font load failed: {s}", .{@errorName(err)});
        unreachable;
    };
}

pub var font_collection_geist: FontCollection = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    const init_error = ft.FT_Init_FreeType(&freetype_lib);
    if (init_error != ft.FT_Err_Ok) {
        std.log.err("FreeType init failed: {d}", .{init_error});
    }

    font_collection_geist = try .loadGeist(allocator);
}

pub fn deinit() void {
    _ = ft.FT_Done_FreeType(freetype_lib);

    font_collection_geist.deinit();
}
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
    /// maps to byte index in the original text
    cluster: u32,
};

pub const Font = struct {
    id: u64,
    alloc: Allocator,
    ft_face: ft.FT_Face,
    harfb_font: *harfb.hb_font_t,
    pixel_height: f32,
    atlas: FontAtlas,
    units_per_em: u16,

    pub fn fromMemory(allocator: Allocator, comptime font_data: []const u8, pixel_height: f32) !Font {
        const now = std.time.milliTimestamp();
        defer std.debug.print("Font init took {d}ms\n", .{std.time.milliTimestamp() - now});

        var hasher = std.hash.Wyhash.init(0);
        hasher.update(std.mem.asBytes(&pixel_height));
        hasher.update(font_data);

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
                .cluster = info.cluster,
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
        // Only deinit the map on error (we return it on success).
        errdefer glyphs_map.deinit();

        try glyphs_map.ensureTotalCapacity(@intCast(num_glyphs));

        var pack = try std.ArrayList(packGlyph).initCapacity(alloc, num_glyphs);
        defer {
            // free bitmaps and the list on both success and error; bitmaps are no longer needed after copying
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
                std.debug.print("Skipping empty glyph {d}\n", .{gi});
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

            // store rect with bearings (left/top) so rendering code can place glyphs on baseline
            glyphs_map.putAssumeCapacityNoClobber(@intCast(gi), .{
                .x = rect_x,
                .y = rect_y,
                .w = gw,
                .h = gh,
                .left = glyph.left,
                .top = glyph.top,
            });

            // keep the actual bitmap around so we can copy it into the atlas
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
        // free on error
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

        try writeToBMP(alloc, atlas_w, atlas_h, pixel);

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
    }

    pub fn getGlyphDimensions(self: FontAtlas, glyph_index: u32) Rect {
        return self.glyphs_map.get(glyph_index).?;
    }

    fn writeToBMP(alloc: Allocator, width: u32, height: u32, pixels: []u8) !void {
        const row_stride: usize = ((@as(usize, width) * 3 + 3) / 4) * 4;
        const file_size = 14 + 40 + row_stride * @as(usize, height);

        const file = try std.fs.cwd().createFile("font_atlas.bmp", .{});
        defer file.close();

        // BMP file header (14 bytes)
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
            40,                               0,                                       0,                                        0,
            @as(u8, @intCast(width & 0xFF)),  @as(u8, @intCast((width >> 8) & 0xFF)),  @as(u8, @intCast((width >> 16) & 0xFF)),  @as(u8, @intCast((width >> 24) & 0xFF)),
            @as(u8, @intCast(height & 0xFF)), @as(u8, @intCast((height >> 8) & 0xFF)), @as(u8, @intCast((height >> 16) & 0xFF)), @as(u8, @intCast((height >> 24) & 0xFF)),
            1,                                0,                                       24,                                       0,
            0,                                0,                                       0,                                        0,
            0,                                0,                                       0,                                        0,
            0,                                0,                                       0,                                        0,
            0,                                0,                                       0,                                        0,
            0,                                0,                                       0,                                        0,
            0,                                0,                                       0,                                        0,
        };

        try file.writeAll(&file_header);
        try file.writeAll(&dib_header);

        // --- FIXED ROW-WRITE WITH PADDING ---
        var rgb_row = try alloc.alloc(u8, row_stride);
        defer alloc.free(rgb_row);

        for (0..height) |y| {
            const src_y = height - 1 - y; // BMP wants bottom-to-top
            var idx: usize = 0;
            for (0..width) |x| {
                const gray = pixels[src_y * width + x];
                rgb_row[idx + 0] = gray; // B
                rgb_row[idx + 1] = gray; // G
                rgb_row[idx + 2] = gray; // R
                idx += 3;
            }
            // pad to 4-byte boundary
            while (idx < row_stride) : (idx += 1) {
                rgb_row[idx] = 0;
            }
            try file.writeAll(rgb_row[0..row_stride]);
        }
    }

    fn writeToBMP2(alloc: Allocator, max_height: u32, glyphs: []GlyphBitmap) !void {
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

pub const FontStyle = enum {
    light,
    regular,
    medium,
    semibold,
    bold,
    extrabold,
    black,
};

pub const FontCollection = struct {
    font_light_16: Font,
    font_light_24: Font,
    font_light_32: Font,
    font_light_48: Font,
    font_light_64: Font,
    font_light_72: Font,
    font_light_96: Font,
    font_regular_16: Font,
    font_regular_24: Font,
    font_regular_32: Font,
    font_regular_48: Font,
    font_regular_64: Font,
    font_regular_72: Font,
    font_regular_96: Font,
    font_medium_16: Font,
    font_medium_24: Font,
    font_medium_32: Font,
    font_medium_48: Font,
    font_medium_64: Font,
    font_medium_72: Font,
    font_medium_96: Font,
    font_semibold_16: Font,
    font_semibold_24: Font,
    font_semibold_32: Font,
    font_semibold_48: Font,
    font_semibold_64: Font,
    font_semibold_72: Font,
    font_semibold_96: Font,
    font_bold_16: Font,
    font_bold_24: Font,
    font_bold_32: Font,
    font_bold_48: Font,
    font_bold_64: Font,
    font_bold_72: Font,
    font_bold_96: Font,
    font_extrabold_16: Font,
    font_extrabold_24: Font,
    font_extrabold_32: Font,
    font_extrabold_48: Font,
    font_extrabold_64: Font,
    font_extrabold_72: Font,
    font_extrabold_96: Font,
    font_black_16: Font,
    font_black_24: Font,
    font_black_32: Font,
    font_black_48: Font,
    font_black_64: Font,
    font_black_72: Font,
    font_black_96: Font,

    pub fn getFont(self: FontCollection, font_size: f32, style: FontStyle) Font {
        const nearest_font_size = nearestFontSize(@intFromFloat(font_size));
        return switch (style) {
            .light => return switch (nearest_font_size) {
                16 => self.font_light_16,
                24 => self.font_light_24,
                32 => self.font_light_32,
                48 => self.font_light_48,
                64 => self.font_light_64,
                72 => self.font_light_72,
                96 => self.font_light_96,
                else => unreachable,
            },
            .regular => switch (nearest_font_size) {
                16 => self.font_regular_16,
                24 => self.font_regular_24,
                32 => self.font_regular_32,
                48 => self.font_regular_48,
                64 => self.font_regular_64,
                72 => self.font_regular_72,
                96 => self.font_regular_96,
                else => unreachable,
            },
            .medium => switch (nearest_font_size) {
                16 => self.font_medium_16,
                24 => self.font_medium_24,
                32 => self.font_medium_32,
                48 => self.font_medium_48,
                64 => self.font_medium_64,
                72 => self.font_medium_72,
                96 => self.font_medium_96,
                else => unreachable,
            },
            .semibold => switch (nearest_font_size) {
                16 => self.font_semibold_16,
                24 => self.font_semibold_24,
                32 => self.font_semibold_32,
                48 => self.font_semibold_48,
                64 => self.font_semibold_64,
                72 => self.font_semibold_72,
                96 => self.font_semibold_96,
                else => unreachable,
            },
            .bold => switch (nearest_font_size) {
                16 => self.font_bold_16,
                24 => self.font_bold_24,
                32 => self.font_bold_32,
                48 => self.font_bold_48,
                64 => self.font_bold_64,
                72 => self.font_bold_72,
                96 => self.font_bold_96,
                else => unreachable,
            },
            .extrabold => switch (nearest_font_size) {
                16 => self.font_extrabold_16,
                24 => self.font_extrabold_24,
                32 => self.font_extrabold_32,
                48 => self.font_extrabold_48,
                64 => self.font_extrabold_64,
                72 => self.font_extrabold_72,
                96 => self.font_extrabold_96,
                else => unreachable,
            },
            .black => switch (nearest_font_size) {
                16 => self.font_black_16,
                24 => self.font_black_24,
                32 => self.font_black_32,
                48 => self.font_black_48,
                64 => self.font_black_64,
                72 => self.font_black_72,
                96 => self.font_black_96,
                else => unreachable,
            },
        };
    }

    fn nearestFontSize(font_size: u16) u16 {
        switch (font_size) {
            0...16 => return 16,
            17...24 => return 24,
            25...32 => return 32,
            33...48 => return 48,
            49...64 => return 64,
            65...72 => return 72,
            73...96 => return 96,
            else => return 96,
        }
    }

    pub fn deinit(self: *FontCollection) void {
        self.font_light_16.deinit();
        self.font_light_24.deinit();
        self.font_light_32.deinit();
        self.font_light_48.deinit();
        self.font_light_64.deinit();
        self.font_light_72.deinit();
        self.font_light_96.deinit();
        self.font_regular_16.deinit();
        self.font_regular_24.deinit();
        self.font_regular_32.deinit();
        self.font_regular_48.deinit();
        self.font_regular_64.deinit();
        self.font_regular_72.deinit();
        self.font_regular_96.deinit();
        self.font_medium_16.deinit();
        self.font_medium_24.deinit();
        self.font_medium_32.deinit();
        self.font_medium_48.deinit();
        self.font_medium_64.deinit();
        self.font_medium_72.deinit();
        self.font_medium_96.deinit();
        self.font_semibold_16.deinit();
        self.font_semibold_24.deinit();
        self.font_semibold_32.deinit();
        self.font_semibold_48.deinit();
        self.font_semibold_64.deinit();
        self.font_semibold_72.deinit();
        self.font_semibold_96.deinit();
        self.font_bold_16.deinit();
        self.font_bold_24.deinit();
        self.font_bold_32.deinit();
        self.font_bold_48.deinit();
        self.font_bold_64.deinit();
        self.font_bold_72.deinit();
        self.font_bold_96.deinit();
        self.font_extrabold_16.deinit();
        self.font_extrabold_24.deinit();
        self.font_extrabold_32.deinit();
        self.font_extrabold_48.deinit();
        self.font_extrabold_64.deinit();
        self.font_extrabold_72.deinit();
        self.font_extrabold_96.deinit();
        self.font_black_16.deinit();
        self.font_black_24.deinit();
        self.font_black_32.deinit();
        self.font_black_48.deinit();
        self.font_black_64.deinit();
        self.font_black_72.deinit();
        self.font_black_96.deinit();
    }

    fn loadGeist(allocator: std.mem.Allocator) !FontCollection {
        var thread_pool: std.Thread.Pool = undefined;
        try std.Thread.Pool.init(&thread_pool, .{
            .allocator = allocator,
        });

        var font_light_16: Font = undefined;
        var font_light_24: Font = undefined;
        var font_light_32: Font = undefined;
        var font_light_48: Font = undefined;
        var font_light_64: Font = undefined;
        var font_light_72: Font = undefined;
        var font_light_96: Font = undefined;
        var font_regular_16: Font = undefined;
        var font_regular_24: Font = undefined;
        var font_regular_32: Font = undefined;
        var font_regular_48: Font = undefined;
        var font_regular_64: Font = undefined;
        var font_regular_72: Font = undefined;
        var font_regular_96: Font = undefined;
        var font_medium_16: Font = undefined;
        var font_medium_24: Font = undefined;
        var font_medium_32: Font = undefined;
        var font_medium_48: Font = undefined;
        var font_medium_64: Font = undefined;
        var font_medium_72: Font = undefined;
        var font_medium_96: Font = undefined;
        var font_semibold_16: Font = undefined;
        var font_semibold_24: Font = undefined;
        var font_semibold_32: Font = undefined;
        var font_semibold_48: Font = undefined;
        var font_semibold_64: Font = undefined;
        var font_semibold_72: Font = undefined;
        var font_semibold_96: Font = undefined;
        var font_bold_16: Font = undefined;
        var font_bold_24: Font = undefined;
        var font_bold_32: Font = undefined;
        var font_bold_48: Font = undefined;
        var font_bold_64: Font = undefined;
        var font_bold_72: Font = undefined;
        var font_bold_96: Font = undefined;
        var font_extrabold_16: Font = undefined;
        var font_extrabold_24: Font = undefined;
        var font_extrabold_32: Font = undefined;
        var font_extrabold_48: Font = undefined;
        var font_extrabold_64: Font = undefined;
        var font_extrabold_72: Font = undefined;
        var font_extrabold_96: Font = undefined;
        var font_black_16: Font = undefined;
        var font_black_24: Font = undefined;
        var font_black_32: Font = undefined;
        var font_black_48: Font = undefined;
        var font_black_64: Font = undefined;
        var font_black_72: Font = undefined;
        var font_black_96: Font = undefined;

        const font_data_light = @embedFile("resources/Font/Geist/Geist-Light.ttf");
        const font_data_regular = @embedFile("resources/Font/Geist/Geist-Regular.ttf");
        const font_data_medium = @embedFile("resources/Font/Geist/Geist-Medium.ttf");
        const font_data_semibold = @embedFile("resources/Font/Geist/Geist-SemiBold.ttf");
        const font_data_bold = @embedFile("resources/Font/Geist/Geist-Bold.ttf");
        const font_data_extrabold = @embedFile("resources/Font/Geist/Geist-ExtraBold.ttf");
        const font_data_black = @embedFile("resources/Font/Geist/Geist-Black.ttf");

        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_light, 16, &font_light_16 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_light, 24, &font_light_24 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_light, 32, &font_light_32 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_light, 48, &font_light_48 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_light, 64, &font_light_64 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_light, 72, &font_light_72 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_light, 96, &font_light_96 });

        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_regular, 16, &font_regular_16 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_regular, 24, &font_regular_24 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_regular, 32, &font_regular_32 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_regular, 48, &font_regular_48 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_regular, 64, &font_regular_64 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_regular, 72, &font_regular_72 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_regular, 96, &font_regular_96 });

        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_medium, 16, &font_medium_16 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_medium, 24, &font_medium_24 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_medium, 32, &font_medium_32 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_medium, 48, &font_medium_48 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_medium, 64, &font_medium_64 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_medium, 72, &font_medium_72 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_medium, 96, &font_medium_96 });

        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_semibold, 16, &font_semibold_16 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_semibold, 24, &font_semibold_24 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_semibold, 32, &font_semibold_32 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_semibold, 48, &font_semibold_48 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_semibold, 64, &font_semibold_64 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_semibold, 72, &font_semibold_72 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_semibold, 96, &font_semibold_96 });

        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_bold, 16, &font_bold_16 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_bold, 24, &font_bold_24 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_bold, 32, &font_bold_32 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_bold, 48, &font_bold_48 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_bold, 64, &font_bold_64 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_bold, 72, &font_bold_72 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_bold, 96, &font_bold_96 });

        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_extrabold, 16, &font_extrabold_16 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_extrabold, 24, &font_extrabold_24 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_extrabold, 32, &font_extrabold_32 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_extrabold, 48, &font_extrabold_48 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_extrabold, 64, &font_extrabold_64 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_extrabold, 72, &font_extrabold_72 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_extrabold, 96, &font_extrabold_96 });

        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_black, 16, &font_black_16 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_black, 24, &font_black_24 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_black, 32, &font_black_32 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_black, 48, &font_black_48 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_black, 64, &font_black_64 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_black, 72, &font_black_72 });
        try thread_pool.spawn(loadFontFromMem, .{ allocator, font_data_black, 96, &font_black_96 });

        thread_pool.deinit();

        return FontCollection{
            .font_light_16 = font_light_16,
            .font_light_24 = font_light_24,
            .font_light_32 = font_light_32,
            .font_light_48 = font_light_48,
            .font_light_64 = font_light_64,
            .font_light_72 = font_light_72,
            .font_light_96 = font_light_96,
            .font_regular_16 = font_regular_16,
            .font_regular_24 = font_regular_24,
            .font_regular_32 = font_regular_32,
            .font_regular_48 = font_regular_48,
            .font_regular_64 = font_regular_64,
            .font_regular_72 = font_regular_72,
            .font_regular_96 = font_regular_96,
            .font_medium_16 = font_medium_16,
            .font_medium_24 = font_medium_24,
            .font_medium_32 = font_medium_32,
            .font_medium_48 = font_medium_48,
            .font_medium_64 = font_medium_64,
            .font_medium_72 = font_medium_72,
            .font_medium_96 = font_medium_96,
            .font_semibold_16 = font_semibold_16,
            .font_semibold_24 = font_semibold_24,
            .font_semibold_32 = font_semibold_32,
            .font_semibold_48 = font_semibold_48,
            .font_semibold_64 = font_semibold_64,
            .font_semibold_72 = font_semibold_72,
            .font_semibold_96 = font_semibold_96,
            .font_bold_16 = font_bold_16,
            .font_bold_24 = font_bold_24,
            .font_bold_32 = font_bold_32,
            .font_bold_48 = font_bold_48,
            .font_bold_64 = font_bold_64,
            .font_bold_72 = font_bold_72,
            .font_bold_96 = font_bold_96,
            .font_extrabold_16 = font_extrabold_16,
            .font_extrabold_24 = font_extrabold_24,
            .font_extrabold_32 = font_extrabold_32,
            .font_extrabold_48 = font_extrabold_48,
            .font_extrabold_64 = font_extrabold_64,
            .font_extrabold_72 = font_extrabold_72,
            .font_extrabold_96 = font_extrabold_96,
            .font_black_16 = font_black_16,
            .font_black_24 = font_black_24,
            .font_black_32 = font_black_32,
            .font_black_48 = font_black_48,
            .font_black_64 = font_black_64,
            .font_black_72 = font_black_72,
            .font_black_96 = font_black_96,
        };
    }
};
