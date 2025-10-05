const std = @import("std");
const assert = std.debug.assert;

pub const gl = @import("gl");

const Font = @import("font.zig").Font;
const FontAtlas = @import("font.zig").FontAtlas;
const FontCollection = @import("font.zig").FontCollection;
const FontStyle = @import("font.zig").FontStyle;

var once = false;

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
        const program_id = gl.CreateProgram();

        const vs = try compileShader(gl.VERTEX_SHADER, vertex_shader_src);
        const fs = try compileShader(gl.FRAGMENT_SHADER, fragment_shader_src);

        gl.AttachShader(program_id, vs);
        gl.AttachShader(program_id, fs);
        gl.LinkProgram(program_id);

        var success: c_int = undefined;
        var info_log: [512]u8 = undefined;
        gl.GetProgramiv(program_id, gl.LINK_STATUS, (&success)[0..1]);
        if (success == 0) {
            gl.GetProgramInfoLog(program_id, info_log.len, null, info_log[0..]);
            std.log.err("Program link error: {s}", .{info_log});
            return error.ProgramLinkFailed;
        }

        gl.DeleteShader(vs);
        gl.DeleteShader(fs);

        return .{
            .id = program_id,
            .window_params_loc = gl.GetUniformLocation(program_id, "window_params"),
            .tex_loc = gl.GetUniformLocation(program_id, "tex"),
        };
    }

    pub inline fn deinit(self: Program) void {
        gl.DeleteProgram(self.id);
    }

    pub inline fn use(self: Program) void {
        gl.UseProgram(self.id);
    }

    pub inline fn uniformLocation(self: Program, name: [:0]const u8) c_int {
        return gl.GetUniformLocation(self.id, name);
    }

    fn compileShader(kind: c_uint, comptime src: []const u8) !c_uint {
        const shader = gl.CreateShader(kind);
        gl.ShaderSource(shader, 1, &.{src.ptr}, &.{src.len});
        gl.CompileShader(shader);

        var success: c_int = undefined;
        var info_log: [512]u8 = undefined;
        gl.GetShaderiv(shader, gl.COMPILE_STATUS, (&success)[0..1]);
        if (success == 0) {
            gl.GetShaderInfoLog(shader, info_log.len, null, info_log[0..]);
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
        gl.GenVertexArrays(1, (&vao)[0..1]);
        gl.BindVertexArray(vao); // Bind VAO first

        // Base quad vertices (normalized)
        const base_verts = [_][2]f32{ .{ -0.5, -0.5 }, .{ 0.5, -0.5 }, .{ 0.5, 0.5 }, .{ -0.5, 0.5 } };
        var base_vbo: c_uint = undefined;
        gl.GenBuffers(1, (&base_vbo)[0..1]);
        gl.BindBuffer(gl.ARRAY_BUFFER, base_vbo);
        gl.BufferData(gl.ARRAY_BUFFER, base_verts.len * @sizeOf([2]f32), &base_verts[0], gl.STATIC_DRAW);

        // Indices: Counter-clockwise
        const base_indices = [_]c_uint{ 0, 1, 2, 0, 2, 3 };
        var base_ebo: c_uint = undefined;
        gl.GenBuffers(1, (&base_ebo)[0..1]);
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, base_ebo);
        gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, base_indices.len * @sizeOf(c_uint), &base_indices[0], gl.STATIC_DRAW);

        // Base vertex attribute
        gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, 2 * @sizeOf(f32), 0);
        gl.EnableVertexAttribArray(0);

        // Instance VBO (dynamic)
        var vbo: c_uint = undefined;
        gl.GenBuffers(1, (&vbo)[0..1]);
        gl.BindBuffer(gl.ARRAY_BUFFER, vbo);
        gl.BufferData(gl.ARRAY_BUFFER, MAX_RECTANGLES * @sizeOf(InstanceData), null, gl.DYNAMIC_DRAW);

        // Instance attributes
        const stride: c_uint = @sizeOf(InstanceData);
        gl.VertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, stride, @offsetOf(InstanceData, "pos_tl"));
        gl.VertexAttribDivisor(1, 1);
        gl.EnableVertexAttribArray(1);

        gl.VertexAttribPointer(2, 2, gl.FLOAT, gl.FALSE, stride, @offsetOf(InstanceData, "size"));
        gl.VertexAttribDivisor(2, 1);
        gl.EnableVertexAttribArray(2);

        gl.VertexAttribPointer(3, 4, gl.UNSIGNED_BYTE, gl.TRUE, stride, @offsetOf(InstanceData, "color"));
        gl.VertexAttribDivisor(3, 1);
        gl.EnableVertexAttribArray(3);

        gl.VertexAttribPointer(4, 1, gl.FLOAT, gl.FALSE, stride, @offsetOf(InstanceData, "corner_radius"));
        gl.VertexAttribDivisor(4, 1);
        gl.EnableVertexAttribArray(4);

        gl.VertexAttribPointer(5, 4, gl.FLOAT, gl.FALSE, stride, @offsetOf(InstanceData, "border_width"));
        gl.VertexAttribDivisor(5, 1);
        gl.EnableVertexAttribArray(5);

        gl.VertexAttribPointer(6, 4, gl.UNSIGNED_BYTE, gl.TRUE, stride, @offsetOf(InstanceData, "border_color"));
        gl.VertexAttribDivisor(6, 1);
        gl.EnableVertexAttribArray(6);

        gl.VertexAttribIPointer(7, 1, gl.INT, stride, @offsetOf(InstanceData, "use_texture"));
        gl.VertexAttribDivisor(7, 1);
        gl.EnableVertexAttribArray(7);

        gl.VertexAttribPointer(8, 4, gl.FLOAT, gl.FALSE, stride, @offsetOf(InstanceData, "uv_data"));
        gl.VertexAttribDivisor(8, 1);
        gl.EnableVertexAttribArray(8);

        // Unbind VAO
        gl.BindVertexArray(0);

        gl.Enable(gl.BLEND);
        gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

        // Placeholder atlas texture
        var atlas_texture: c_uint = undefined;
        gl.GenTextures(1, (&atlas_texture)[0..1]);

        // Check for OpenGL errors
        if (gl.GetError() != gl.NO_ERROR) {
            std.log.err("OpenGL error during Renderer2D.init: {d}", .{gl.GetError()});
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
            .font_textures = std.AutoHashMap(u64, c_uint).init(allocator),
            .shape_cache = ShapeCache.init(allocator),
        };
    }

    pub fn deinit(self: *Renderer2D) void {
        // delete cached textures
        var it = self.font_textures.iterator();
        while (it.next()) |entry| {
            gl.DeleteTextures(1, (&entry.value_ptr.*)[0..1]);
        }
        self.font_textures.deinit();
        self.shape_cache.deinit(&@import("font.zig").font_collection_geist);
        gl.DeleteVertexArrays(1, (&self.vao)[0..1]);
        gl.DeleteBuffers(1, (&self.vbo)[0..1]);
        gl.DeleteBuffers(1, (&self.base_vbo)[0..1]);
        gl.DeleteBuffers(1, (&self.base_ebo)[0..1]);
        gl.DeleteTextures(1, (&self.atlas_texture)[0..1]);
    }

    pub fn begin(self: *Renderer2D, window_size: [2]u32, window_scale: [2]f32) void {
        self.rect_count = 0;
        // reset per-frame caches
        self.shape_cache.beginFrame();
        gl.BindVertexArray(self.vao);
        gl.UseProgram(self.program.id);
        gl.Uniform4f(self.program.window_params_loc, @floatFromInt(window_size[0]), @floatFromInt(window_size[1]), window_scale[0], window_scale[1]);
        gl.Uniform1i(self.program.tex_loc, 0);
        gl.ActiveTexture(gl.TEXTURE0);

        if (gl.GetError() != gl.NO_ERROR) {
            std.log.err("OpenGL error during Renderer2D.begin: {d}", .{gl.GetError()});
        }
    }

    pub fn flush(self: *Renderer2D) void {
        if (self.rect_count == 0) return;
        // std.log.debug("Flushing {d} rectangles", .{self.rect_count});
        gl.BindVertexArray(self.vao);
        gl.BindBuffer(gl.ARRAY_BUFFER, self.vbo);
        gl.BufferSubData(gl.ARRAY_BUFFER, 0, @intCast(self.rect_count * @sizeOf(InstanceData)), &self.instance_data[0]);
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.base_ebo);
        gl.DrawElementsInstanced(gl.TRIANGLES, 6, gl.UNSIGNED_INT, 0, @intCast(self.rect_count));
        self.rect_count = 0;

        if (gl.GetError() != gl.NO_ERROR) {
            std.log.err("OpenGL error during Renderer2D.flush: {d}", .{gl.GetError()});
        }
    }

    fn uploadAtlasToTexture(texture: c_uint, font_atlas: FontAtlas) void {
        const now = std.time.microTimestamp();
        defer std.debug.print("uploadAtlas took {d}us\n", .{std.time.microTimestamp() - now});
        // Make sure we target texture unit 0 because that's what the shader expects via Uniform1i(...)
        gl.ActiveTexture(gl.TEXTURE0);
        gl.BindTexture(gl.TEXTURE_2D, texture);

        // Pixel alignment for single-channel data
        gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1);

        // Upload: internal format RED, data format RED
        gl.TexImage2D(
            gl.TEXTURE_2D,
            0,
            gl.RED, // internal format
            @intCast(font_atlas.width),
            @intCast(font_atlas.height),
            0,
            gl.RED, // source/pixel format
            gl.UNSIGNED_BYTE,
            font_atlas.pixel.ptr,
        );

        // Set sampling / wrapping
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);

        // --- important: swizzle RED -> RGB, ALPHA -> 1
        // This makes sampling texture(tex, uv) return (r,r,r,1) for compatibility
        // on backends that do not auto-swizzle RED to vec4.
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_SWIZZLE_R, gl.RED);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_SWIZZLE_G, gl.RED);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_SWIZZLE_B, gl.RED);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_SWIZZLE_A, gl.ONE);

        const e = gl.GetError();
        if (e != gl.NO_ERROR) {
            std.log.err("OpenGL error after uploadAtlas: {d}", .{e});
        }
    }

    fn getOrCreateAtlasTexture(self: *Renderer2D, font_atlas: FontAtlas, font_id: u64) c_uint {
        if (self.font_textures.get(font_id)) |tex| return tex;
        var tex: c_uint = undefined;
        gl.GenTextures(1, (&tex)[0..1]);
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
            gl.ActiveTexture(gl.TEXTURE0);
            gl.BindTexture(gl.TEXTURE_2D, tex);
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
    gl.Enable(gl.SCISSOR_TEST);
    gl.Scissor(
        @intFromFloat(rect[0]),
        @intFromFloat(rect[1]),
        @intFromFloat(rect[2]),
        @intFromFloat(rect[3]),
    );
}

pub inline fn clipEnd() void {
    gl.Disable(gl.SCISSOR_TEST);
}
