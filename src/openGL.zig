const std = @import("std");
const assert = std.debug.assert;

pub const c = @import("gl");

const Font = @import("font.zig").Font;
const FontAtlas = @import("font.zig").FontAtlas;
const FontCollection = @import("font.zig").FontCollection;
const FontStyle = @import("font.zig").FontStyle;

// --- Per-frame shaping cache (shared by measureText and drawText) ---
const ShapeCacheKey = struct {
    font_id: u64,
    text_hash: u64,
    text_len: usize,

    pub fn hash(self: @This()) u64 {
        var h = std.hash.Wyhash.init(0);
        h.update(std.mem.asBytes(&self.font_id));
        h.update(std.mem.asBytes(&self.text_hash));
        h.update(std.mem.asBytes(&self.text_len));
        return h.final();
    }

    pub fn eql(a: @This(), b: @This()) bool {
        return a.font_id == b.font_id and a.text_len == b.text_len and a.text_hash == b.text_hash;
    }
};

const ShapeCache = struct {
    allocator: std.mem.Allocator,
    map: std.AutoHashMapUnmanaged(ShapeCacheKey, []const @import("font.zig").ShapedGlyph) = .{},

    pub fn init(allocator: std.mem.Allocator) ShapeCache {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *ShapeCache) void {
        // free cached shaped glyph arrays
        var it = self.map.iterator();
        while (it.next()) |entry| {
            // glyph arrays were allocated using the font alloc; free through any font API
            // We don't store per-entry font pointer, but all fonts share same API to free
            // Choose any representative font to call deinitShapedText; slices were allocated
            // with that font's allocator, but Zig's allocators are compatible for free
            // as they store allocator pointer in slice metadata. Use self.allocator to free directly.
            self.allocator.free(entry.value_ptr.*);
        }
        self.map.deinit(self.allocator);
    }

    pub fn beginFrame(self: *ShapeCache) void {
        // Free all entries and clear
        var it = self.map.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.map.clearRetainingCapacity();
    }

    pub fn get(self: *ShapeCache, font_ref: Font, text: []const u8) ![]const @import("font.zig").ShapedGlyph {
        var h = std.hash.Wyhash.init(0);
        h.update(text);
        const key = ShapeCacheKey{ .font_id = font_ref.id, .text_hash = h.final(), .text_len = text.len };

        if (self.map.get(key)) |cached| return cached;

        const shaped = try font_ref.shapeText(text);
        // store a copy owned by this cache (shapeText already allocs a fresh slice)
        try self.map.put(self.allocator, key, shaped);
        return shaped;
    }
};

pub const Program = struct {
    id: c_uint,

    window_params_loc: c_int,
    tex_loc: c_int,

    pub fn init(comptime vertex_shader_src: []const u8, comptime fragment_shader_src: []const u8) !Program {
        const program_id = c.CreateProgram();

        const vs = try compileShader(c.VERTEX_SHADER, vertex_shader_src);
        const fs = try compileShader(c.FRAGMENT_SHADER, fragment_shader_src);

        c.AttachShader(program_id, vs);
        c.AttachShader(program_id, fs);
        c.LinkProgram(program_id);

        var success: c_int = undefined;
        var info_log: [512]u8 = undefined;
        c.GetProgramiv(program_id, c.LINK_STATUS, (&success)[0..1]);
        if (success == 0) {
            c.GetProgramInfoLog(program_id, info_log.len, null, info_log[0..]);
            std.log.err("Program link error: {s}", .{info_log});
            return error.ProgramLinkFailed;
        }

        c.DeleteShader(vs);
        c.DeleteShader(fs);

        return .{
            .id = program_id,
            .window_params_loc = c.GetUniformLocation(program_id, "window_params"),
            .tex_loc = c.GetUniformLocation(program_id, "tex"),
        };
    }

    pub inline fn deinit(self: Program) void {
        c.DeleteProgram(self.id);
    }

    pub inline fn use(self: Program) void {
        c.UseProgram(self.id);
    }

    pub inline fn uniformLocation(self: Program, name: [:0]const u8) c_int {
        return c.GetUniformLocation(self.id, name);
    }

    fn compileShader(kind: c_uint, comptime src: []const u8) !c_uint {
        const shader = c.CreateShader(kind);
        c.ShaderSource(shader, 1, &.{src.ptr}, &.{src.len});
        c.CompileShader(shader);

        var success: c_int = undefined;
        var info_log: [512]u8 = undefined;
        c.GetShaderiv(shader, c.COMPILE_STATUS, (&success)[0..1]);
        if (success == 0) {
            c.GetShaderInfoLog(shader, info_log.len, null, info_log[0..]);
            std.log.err("Shader compile error: {s}", .{info_log});
            return error.ShaderCompileFailed;
        }
        return shader;
    }
};

const InstanceData = struct {
    pos_tl: [2]f32, // unscaled x,y
    size: [2]f32, // unscaled width,height
    color: [4]u8, // RGBA 0-255
    corner_radius: f32, // unscaled
    border_width: [4]f32, // unscaled t,r,b,l
    border_color: [4]u8, // RGBA 0-255
    use_texture: c_int, // 0 = solid, 1 = textured
    uv_data: [4]f32, // for text/images, UV data (x, y, width, height)

    fn fromRect(x: f32, y: f32, w: f32, h: f32, r: f32, color: [4]u8, border_width: [4]f32, border_color: [4]u8) InstanceData {
        return InstanceData{
            .pos_tl = .{ x, y },
            .size = .{ w, h },
            .color = color,
            .corner_radius = r,
            .border_width = border_width,
            .border_color = border_color,
            .use_texture = 0,
            .uv_data = .{ 0, 0, 0, 0 },
        };
    }
};

pub const MAX_RECTANGLES = 8192;

pub const Renderer2D = struct {
    program: Program,
    base_vbo: c_uint,
    base_ebo: c_uint,
    vao: c_uint,
    vbo: c_uint,
    instance_data: [MAX_RECTANGLES]InstanceData,
    rect_count: usize,
    current_font_id: ?u64,
    current_texture_id: ?u32,
    atlas_texture: c_uint,
    allocator: std.mem.Allocator,
    font_textures: std.AutoHashMap(u64, c_uint), // font.id -> texture id
    shape_cache: ShapeCache,

    pub fn init(allocator: std.mem.Allocator, program: Program) !Renderer2D {
        var vao: c_uint = undefined;
        c.GenVertexArrays(1, (&vao)[0..1]);
        c.BindVertexArray(vao); // Bind VAO first

        // Base quad vertices (normalized)
        const base_verts = [_][2]f32{ .{ -0.5, -0.5 }, .{ 0.5, -0.5 }, .{ 0.5, 0.5 }, .{ -0.5, 0.5 } };
        var base_vbo: c_uint = undefined;
        c.GenBuffers(1, (&base_vbo)[0..1]);
        c.BindBuffer(c.ARRAY_BUFFER, base_vbo);
        c.BufferData(c.ARRAY_BUFFER, base_verts.len * @sizeOf([2]f32), &base_verts[0], c.STATIC_DRAW);

        // Indices: Counter-clockwise
        const base_indices = [_]c_uint{ 0, 1, 2, 0, 2, 3 };
        var base_ebo: c_uint = undefined;
        c.GenBuffers(1, (&base_ebo)[0..1]);
        c.BindBuffer(c.ELEMENT_ARRAY_BUFFER, base_ebo);
        c.BufferData(c.ELEMENT_ARRAY_BUFFER, base_indices.len * @sizeOf(c_uint), &base_indices[0], c.STATIC_DRAW);

        // Base vertex attribute
        c.VertexAttribPointer(0, 2, c.FLOAT, c.FALSE, 2 * @sizeOf(f32), 0);
        c.EnableVertexAttribArray(0);

        // Instance VBO (dynamic)
        var vbo: c_uint = undefined;
        c.GenBuffers(1, (&vbo)[0..1]);
        c.BindBuffer(c.ARRAY_BUFFER, vbo);
        c.BufferData(c.ARRAY_BUFFER, MAX_RECTANGLES * @sizeOf(InstanceData), null, c.DYNAMIC_DRAW);

        // Instance attributes
        const stride: c_uint = @sizeOf(InstanceData);
        c.VertexAttribPointer(1, 2, c.FLOAT, c.FALSE, stride, @offsetOf(InstanceData, "pos_tl"));
        c.VertexAttribDivisor(1, 1);
        c.EnableVertexAttribArray(1);

        c.VertexAttribPointer(2, 2, c.FLOAT, c.FALSE, stride, @offsetOf(InstanceData, "size"));
        c.VertexAttribDivisor(2, 1);
        c.EnableVertexAttribArray(2);

        c.VertexAttribPointer(3, 4, c.UNSIGNED_BYTE, c.TRUE, stride, @offsetOf(InstanceData, "color"));
        c.VertexAttribDivisor(3, 1);
        c.EnableVertexAttribArray(3);

        c.VertexAttribPointer(4, 1, c.FLOAT, c.FALSE, stride, @offsetOf(InstanceData, "corner_radius"));
        c.VertexAttribDivisor(4, 1);
        c.EnableVertexAttribArray(4);

        c.VertexAttribPointer(5, 4, c.FLOAT, c.FALSE, stride, @offsetOf(InstanceData, "border_width"));
        c.VertexAttribDivisor(5, 1);
        c.EnableVertexAttribArray(5);

        c.VertexAttribPointer(6, 4, c.UNSIGNED_BYTE, c.TRUE, stride, @offsetOf(InstanceData, "border_color"));
        c.VertexAttribDivisor(6, 1);
        c.EnableVertexAttribArray(6);

        c.VertexAttribIPointer(7, 1, c.INT, stride, @offsetOf(InstanceData, "use_texture"));
        c.VertexAttribDivisor(7, 1);
        c.EnableVertexAttribArray(7);

        c.VertexAttribPointer(8, 4, c.FLOAT, c.FALSE, stride, @offsetOf(InstanceData, "uv_data"));
        c.VertexAttribDivisor(8, 1);
        c.EnableVertexAttribArray(8);

        // Unbind VAO
        c.BindVertexArray(0);

        c.Enable(c.BLEND);
        c.BlendFunc(c.SRC_ALPHA, c.ONE_MINUS_SRC_ALPHA);

        // Placeholder atlas texture
        var atlas_texture: c_uint = undefined;
        c.GenTextures(1, (&atlas_texture)[0..1]);

        // Check for OpenGL errors
        if (c.GetError() != c.NO_ERROR) {
            std.log.err("OpenGL error during Renderer2D.init: {d}", .{c.GetError()});
            return error.OpenGLError;
        }

        return .{
            .program = program,
            .base_vbo = base_vbo,
            .base_ebo = base_ebo,
            .vao = vao,
            .vbo = vbo,
            .instance_data = undefined,
            .rect_count = 0,
            .current_font_id = null,
            .current_texture_id = null,
            .atlas_texture = atlas_texture,
            .allocator = allocator,
            .font_textures = .init(allocator),
            .shape_cache = .init(allocator),
        };
    }

    pub fn deinit(self: *Renderer2D) void {
        // delete cached textures
        var it = self.font_textures.iterator();
        while (it.next()) |entry| {
            c.DeleteTextures(1, (&entry.value_ptr.*)[0..1]);
        }
        self.font_textures.deinit();
        self.shape_cache.deinit();
        c.DeleteVertexArrays(1, (&self.vao)[0..1]);
        c.DeleteBuffers(1, (&self.vbo)[0..1]);
        c.DeleteBuffers(1, (&self.base_vbo)[0..1]);
        c.DeleteBuffers(1, (&self.base_ebo)[0..1]);
        c.DeleteTextures(1, (&self.atlas_texture)[0..1]);
    }

    pub fn begin(self: *Renderer2D, window_size: [2]u32, window_scale: [2]f32) void {
        self.rect_count = 0;
        // reset per-frame caches
        self.shape_cache.beginFrame();
        c.BindVertexArray(self.vao);
        c.UseProgram(self.program.id);
        c.Uniform4f(self.program.window_params_loc, @floatFromInt(window_size[0]), @floatFromInt(window_size[1]), window_scale[0], window_scale[1]);
        c.Uniform1i(self.program.tex_loc, 0);
        c.ActiveTexture(c.TEXTURE0);

        if (c.GetError() != c.NO_ERROR) {
            std.log.err("OpenGL error during Renderer2D.begin: {d}", .{c.GetError()});
        }
    }

    pub fn flush(self: *Renderer2D) void {
        if (self.rect_count == 0) return;
        // std.log.debug("Flushing {d} rectangles", .{self.rect_count});
        c.BindVertexArray(self.vao);
        c.BindBuffer(c.ARRAY_BUFFER, self.vbo);
        c.BufferSubData(c.ARRAY_BUFFER, 0, @intCast(self.rect_count * @sizeOf(InstanceData)), &self.instance_data[0]);
        c.BindBuffer(c.ELEMENT_ARRAY_BUFFER, self.base_ebo);
        c.DrawElementsInstanced(c.TRIANGLES, 6, c.UNSIGNED_INT, 0, @intCast(self.rect_count));
        self.rect_count = 0;

        if (c.GetError() != c.NO_ERROR) {
            std.log.err("OpenGL error during Renderer2D.flush: {d}", .{c.GetError()});
        }
    }

    fn uploadAtlasToTexture(texture: c_uint, font_atlas: FontAtlas) void {
        const now = std.time.microTimestamp();
        defer std.debug.print("uploadAtlas took {d}us\n", .{std.time.microTimestamp() - now});
        // Make sure we target texture unit 0 because that's what the shader expects via Uniform1i(...)
        c.ActiveTexture(c.TEXTURE0);
        c.BindTexture(c.TEXTURE_2D, texture);

        // Pixel alignment for single-channel data
        c.PixelStorei(c.UNPACK_ALIGNMENT, 1);

        // Upload: internal format RED, data format RED
        c.TexImage2D(
            c.TEXTURE_2D,
            0,
            c.RED, // internal format
            @intCast(font_atlas.width),
            @intCast(font_atlas.height),
            0,
            c.RED, // source/pixel format
            c.UNSIGNED_BYTE,
            font_atlas.pixel.ptr,
        );

        // Set sampling / wrapping
        c.TexParameteri(c.TEXTURE_2D, c.TEXTURE_MIN_FILTER, c.LINEAR);
        c.TexParameteri(c.TEXTURE_2D, c.TEXTURE_MAG_FILTER, c.LINEAR);
        c.TexParameteri(c.TEXTURE_2D, c.TEXTURE_WRAP_S, c.CLAMP_TO_EDGE);
        c.TexParameteri(c.TEXTURE_2D, c.TEXTURE_WRAP_T, c.CLAMP_TO_EDGE);

        // --- important: swizzle RED -> RGB, ALPHA -> 1
        // This makes sampling texture(tex, uv) return (r,r,r,1) for compatibility
        // on backends that do not auto-swizzle RED to vec4.
        c.TexParameteri(c.TEXTURE_2D, c.TEXTURE_SWIZZLE_R, c.RED);
        c.TexParameteri(c.TEXTURE_2D, c.TEXTURE_SWIZZLE_G, c.RED);
        c.TexParameteri(c.TEXTURE_2D, c.TEXTURE_SWIZZLE_B, c.RED);
        c.TexParameteri(c.TEXTURE_2D, c.TEXTURE_SWIZZLE_A, c.ONE);

        const e = c.GetError();
        if (e != c.NO_ERROR) {
            std.log.err("OpenGL error after uploadAtlas: {d}", .{e});
        }
    }

    fn getOrCreateAtlasTexture(self: *Renderer2D, font_atlas: FontAtlas, font_id: u64) c_uint {
        if (self.font_textures.get(font_id)) |tex| return tex;
        var tex: c_uint = undefined;
        c.GenTextures(1, (&tex)[0..1]);
        uploadAtlasToTexture(tex, font_atlas);
        self.font_textures.put(font_id, tex) catch |err| {
            std.log.err("Failed to cache font texture: {s}", .{@errorName(err)});
        };
        return tex;
    }

    pub inline fn drawRect(self: *Renderer2D, x: f32, y: f32, w: f32, h: f32, color: [4]u8) void {
        drawRoundedBorderRect(self, x, y, w, h, 0.0, color, .{ 0, 0, 0, 0 }, color);
    }

    pub fn drawRoundedRect(self: *Renderer2D, x: f32, y: f32, w: f32, h: f32, r: f32, color: [4]u8) void {
        drawRoundedBorderRect(self, x, y, w, h, r, color, .{0} ** 4, color);
    }

    pub fn drawRoundedBorderRect(self: *Renderer2D, x: f32, y: f32, w: f32, h: f32, r: f32, color: [4]u8, border_width: [4]f32, border_color: [4]u8) void {
        if (self.rect_count >= MAX_RECTANGLES) self.flush();
        self.instance_data[self.rect_count] = .fromRect(x, y, w, h, r, color, border_width, border_color);
        self.rect_count += 1;
    }

    pub fn drawText(self: *Renderer2D, font_collection: FontCollection, text: []const u8, x: f32, y: f32, size: f32, style: FontStyle, text_color: [4]u8) !void {
        // const now = std.time.milliTimestamp();
        // defer std.debug.print("drawText took {d}ms\n", .{std.time.milliTimestamp() - now});

        const font = font_collection.getFont(size, style);
        if (self.current_texture_id == null or self.current_font_id == null or self.current_font_id.? != font.id) {
            self.flush();
            const tex = self.getOrCreateAtlasTexture(font.atlas, font.id);
            c.ActiveTexture(c.TEXTURE0);
            c.BindTexture(c.TEXTURE_2D, tex);
            self.current_texture_id = tex;
            self.current_font_id = font.id;
        }

        const glyphs = try self.shape_cache.get(font, text);

        // scale between the atlas rasterization size (font.pixel_height) and requested size
        const scale = size / font.pixel_height;

        // Get ascender/height from FreeType for proper baseline and line advances
        // FreeType metrics are 26.6 fixed-point integers, so divide by 64.0 to get pixels
        const ascender_px = @as(f32, @floatFromInt(font.ft_face.*.size.*.metrics.ascender)) / 64.0;
        const line_advance_px = @as(f32, @floatFromInt(font.ft_face.*.size.*.metrics.height)) / 64.0;

        // We want `x,y` to be top-left of the text block -> convert to baseline
        var cursor_x: f32 = x;
        var cursor_y: f32 = y + ascender_px * scale; // baseline = top + ascender (scaled)

        for (glyphs) |g| {
            // Map back to input bytes using HarfBuzz cluster (you have cluster field)
            if (g.cluster < text.len and text[g.cluster] == '\n') {
                cursor_x = x;
                cursor_y += line_advance_px * scale;
                continue;
            }

            // If the glyph is missing (.notdef) many fonts use index 0
            if (g.glyph_index == 0) {
                // Just advance the pen — don't draw a tofu box
                cursor_x += g.x_advance * scale;
                cursor_y += g.y_advance * scale;
                continue;
            }

            const rect_opt = font.atlas.glyphs_map.get(g.glyph_index);
            if (rect_opt == null) {
                // No atlas entry (shouldn't happen for most printable glyphs) -> advance
                cursor_x += g.x_advance * scale;
                cursor_y += g.y_advance * scale;
                continue;
            }
            const rect = rect_opt.?;

            // If glyph has no bitmap (e.g. space), just advance
            if (rect.w == 0 or rect.h == 0) {
                cursor_x += g.x_advance * scale;
                cursor_y += g.y_advance * scale;
                continue;
            }

            // Compute size in screen pixels
            const w = @as(f32, @floatFromInt(rect.w)) * scale;
            const h = @as(f32, @floatFromInt(rect.h)) * scale;

            // Baseline-correct placement with HarfBuzz offsets:
            //  - rect.left is bitmap_left (px from pen to left of bitmap)
            //  - rect.top  is bitmap_top  (px from baseline up to top of bitmap)
            // HarfBuzz x_offset/y_offset are applied on top of the pen position (scale them)
            const hb_xoff = g.x_offset * scale;
            const hb_yoff = g.y_offset * scale;

            const xpos = cursor_x + hb_xoff + @as(f32, @floatFromInt(rect.left)) * scale;
            const ypos = cursor_y - @as(f32, @floatFromInt(rect.top)) * scale - hb_yoff;

            // Queue instance
            if (self.rect_count >= MAX_RECTANGLES) self.flush();
            self.instance_data[self.rect_count] = .{
                .pos_tl = .{ xpos, ypos },
                .size = .{ w, h },
                .color = text_color,
                .corner_radius = 0,
                .border_width = .{0} ** 4,
                .border_color = .{0} ** 4,
                .use_texture = 1,
                .uv_data = .{
                    @as(f32, @floatFromInt(rect.x)) / @as(f32, @floatFromInt(font.atlas.width)),
                    @as(f32, @floatFromInt(rect.y)) / @as(f32, @floatFromInt(font.atlas.height)),
                    @as(f32, @floatFromInt(rect.w)) / @as(f32, @floatFromInt(font.atlas.width)),
                    @as(f32, @floatFromInt(rect.h)) / @as(f32, @floatFromInt(font.atlas.height)),
                },
            };
            self.rect_count += 1;

            // advance pen by HarfBuzz advance (already in pixels), scaled
            cursor_x += g.x_advance * scale;
            cursor_y += g.y_advance * scale;
        }
    }

    pub fn end(self: *Renderer2D) void {
        self.flush();
    }
};

pub inline fn clipStart(rect: [4]f32) void {
    c.Enable(c.SCISSOR_TEST);
    c.Scissor(
        @intFromFloat(rect[0]),
        @intFromFloat(rect[1]),
        @intFromFloat(rect[2]),
        @intFromFloat(rect[3]),
    );
}

pub inline fn clipEnd() void {
    c.Disable(c.SCISSOR_TEST);
}
