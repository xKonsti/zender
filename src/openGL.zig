const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

pub const c = @import("gl");
const stb_image = @import("image.zig").c;

const font_mod = @import("font.zig");
const Font = @import("font.zig").Font;
const FontAtlas = @import("font.zig").FontAtlas;
const FontFamily = @import("font.zig").FontFamily;
const FontStyle = @import("font.zig").FontStyle;
const zlay = @import("zlayout");

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
    map: std.AutoHashMapUnmanaged(ShapeCacheKey, CachedShape) = .empty,
    frame_number: u128 = 0,

    const CachedShape = struct {
        glyphs: []const @import("font.zig").ShapedGlyph,
        last_used_frame: u128,
    };

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
            self.allocator.free(entry.value_ptr.glyphs);
        }
        self.map.deinit(self.allocator);
    }

    pub fn beginFrame(self: *ShapeCache) void {
        self.frame_number += 1;

        // Only clear entries not used in last 60 frames (~1 second at 60fps)
        if (self.frame_number % 60 == 0) {
            var it = self.map.iterator();
            while (it.next()) |entry| {
                if (self.frame_number - entry.value_ptr.last_used_frame > 60) {
                    self.allocator.free(entry.value_ptr.glyphs);
                    // Remove from map
                    _ = self.map.remove(entry.key_ptr.*);
                }
            }
        }
    }

    pub fn get(self: *ShapeCache, font_ref: Font, text: []const u8) ![]const @import("font.zig").ShapedGlyph {
        var h = std.hash.Wyhash.init(0);
        h.update(text);
        const key = ShapeCacheKey{ .font_id = font_ref.id, .text_hash = h.final(), .text_len = text.len };

        if (self.map.getPtr(key)) |cached| {
            cached.last_used_frame = self.frame_number;
            return cached.glyphs;
        }

        const shaped = try font_ref.shapeText(text);
        try self.map.put(self.allocator, key, .{
            .glyphs = shaped,
            .last_used_frame = self.frame_number,
        });
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
    border_width: [4]f32, // unscaled l,r,t,b
    border_color: [4]u8, // RGBA 0-255
    rotation: f32, // in radians
    use_texture: enum(c_int) { solid = 0, text = 1, image = 2, arc = 3 }, // 0 = solid, 1 = text (grayscale), 2 = image (RGBA), 3 = arc
    uv_data: [4]f32, // for text/images, UV data (x, y, width, height) OR for arc: (start_angle, end_angle, unused, unused)

    fn fromRect(
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        r: f32,
        color: [4]u8,
        border_width: [4]f32,
        border_color: [4]u8,
        rotation: f32,
    ) InstanceData {
        return InstanceData{
            .pos_tl = .{ x, y },
            .size = .{ w, h },
            .color = color,
            .corner_radius = r,
            .border_width = border_width,
            .border_color = border_color,
            .use_texture = .solid,
            .uv_data = .{ 0, 0, 0, 0 },
            .rotation = rotation,
        };
    }
};

pub const MAX_RECTANGLES = 8192;
pub const MAX_TRIANGLES = 2048;

pub const TriangleVertex = struct {
    pos: [2]f32,
    color: [4]u8,
};

pub const Renderer2D = struct {
    program: Program,
    triangle_program: Program,
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

    image_textures: std.StringHashMap(ImageTexture), // path -> texture
    current_image_id: ?c_uint,

    // Triangle rendering
    triangle_vao: c_uint,
    triangle_vbo: c_uint,
    triangle_vertices: [MAX_TRIANGLES * 3]TriangleVertex,
    triangle_count: usize,

    pub fn init(allocator: std.mem.Allocator, program: Program, triangle_program: Program) !Renderer2D {
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

        c.VertexAttribPointer(9, 1, c.FLOAT, c.FALSE, stride, @offsetOf(InstanceData, "rotation"));
        c.VertexAttribDivisor(9, 1);
        c.EnableVertexAttribArray(9);

        // Unbind VAO
        c.BindVertexArray(0);

        c.Enable(c.BLEND);
        c.BlendFunc(c.SRC_ALPHA, c.ONE_MINUS_SRC_ALPHA);

        // Placeholder atlas texture
        var atlas_texture: c_uint = undefined;
        c.GenTextures(1, (&atlas_texture)[0..1]);

        // Setup triangle rendering (VAO and VBO)
        var triangle_vao: c_uint = undefined;
        c.GenVertexArrays(1, (&triangle_vao)[0..1]);
        c.BindVertexArray(triangle_vao);

        var triangle_vbo: c_uint = undefined;
        c.GenBuffers(1, (&triangle_vbo)[0..1]);
        c.BindBuffer(c.ARRAY_BUFFER, triangle_vbo);
        c.BufferData(c.ARRAY_BUFFER, MAX_TRIANGLES * 3 * @sizeOf(TriangleVertex), null, c.DYNAMIC_DRAW);

        // Triangle vertex attributes
        const triangle_stride: c_uint = @sizeOf(TriangleVertex);
        c.VertexAttribPointer(0, 2, c.FLOAT, c.FALSE, triangle_stride, @offsetOf(TriangleVertex, "pos"));
        c.EnableVertexAttribArray(0);

        c.VertexAttribPointer(1, 4, c.UNSIGNED_BYTE, c.TRUE, triangle_stride, @offsetOf(TriangleVertex, "color"));
        c.EnableVertexAttribArray(1);

        c.BindVertexArray(0);

        // Check for OpenGL errors
        if (c.GetError() != c.NO_ERROR) {
            std.log.err("OpenGL error during Renderer2D.init: {d}", .{c.GetError()});
            return error.OpenGLError;
        }

        return .{
            .program = program,
            .triangle_program = triangle_program,
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

            .image_textures = .init(allocator),
            .current_image_id = null,

            .triangle_vao = triangle_vao,
            .triangle_vbo = triangle_vbo,
            .triangle_vertices = undefined,
            .triangle_count = 0,
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

        // Delete triangle resources
        c.DeleteVertexArrays(1, (&self.triangle_vao)[0..1]);
        c.DeleteBuffers(1, (&self.triangle_vbo)[0..1]);

        var img_it = self.image_textures.iterator();
        while (img_it.next()) |entry| {
            entry.value_ptr.*.deinit();
        }
        self.image_textures.deinit();
    }

    pub fn begin(self: *Renderer2D, window_size: [2]u32, window_scale: [2]f32) void {
        self.rect_count = 0;
        self.triangle_count = 0;
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

    pub const RectConfig = struct {
        color: [4]u8 = .{0} ** 4,
        corner_radius: [4]f32 = .{0} ** 4,
        border_width: [4]f32 = .{0} ** 4,
        border_color: [4]u8 = .{0} ** 4,
        rotation_deg: f32 = 0,
    };

    pub fn drawRect(self: *Renderer2D, tl_x: f32, tl_y: f32, w: f32, h: f32, config: RectConfig) void {
        if (self.rect_count >= MAX_RECTANGLES) self.flush();
        self.instance_data[self.rect_count] = .fromRect(
            tl_x,
            tl_y,
            w,
            h,
            config.corner_radius[0],
            config.color,
            config.border_width,
            config.border_color,
            std.math.degreesToRadians(config.rotation_deg),
        );
        self.rect_count += 1;
    }

    pub const LineConfig = struct {
        width: f32 = 1.0,
        color: [4]u8 = .{ 255, 255, 255, 255 },
        cap: LineCap = .butt,
    };

    pub const LineCap = enum {
        butt,
        square,
        round,
    };

    pub fn drawLine(self: *Renderer2D, p1: [2]f32, p2: [2]f32, config: LineConfig) void {
        if (self.rect_count >= MAX_RECTANGLES) self.flush();

        const x1 = p1[0];
        const y1 = p1[1];
        const x2 = p2[0];
        const y2 = p2[1];

        const dx = x2 - x1;
        const dy = y2 - y1;
        const length = @sqrt(dx * dx + dy * dy);
        const angle_rad = std.math.atan2(dy, dx);

        // Extend the visual line length depending on cap type
        var extra_len: f32 = 0.0;
        switch (config.cap) {
            .square, .round => extra_len = config.width,
            .butt => {},
        }

        const total_length = length + extra_len;

        // Center is still midpoint between p1 and p2
        const center_x = (x1 + x2) / 2;
        const center_y = (y1 + y2) / 2;

        const width = total_length;
        const height = config.width;

        // The rectangle should be centered at the midpoint of the line.
        // When rotating, top-left is computed as offset from center.
        const tl_x = center_x - width / 2;
        const tl_y = center_y - height / 2;

        self.instance_data[self.rect_count] = .fromRect(
            tl_x,
            tl_y,
            width,
            height,
            switch (config.cap) {
                .butt, .square => 0,
                .round => config.width * 0.5, // radius for caps
            },
            config.color,
            .{ 0, 0, 0, 0 },
            .{ 0, 0, 0, 0 },
            -angle_rad,
        );

        self.rect_count += 1;
    }

    pub const CircleConfig = struct {
        color: [4]u8 = .{ 255, 255, 255, 255 },
        border_width: f32 = 0,
        border_color: [4]u8 = .{ 0, 0, 0, 255 },
    };

    pub fn drawCircle(self: *Renderer2D, center_x: f32, center_y: f32, radius: f32, config: CircleConfig) void {
        if (self.rect_count >= MAX_RECTANGLES) self.flush();

        // A circle is just a square with corner_radius = radius
        const diameter = radius * 2;
        const tl_x = center_x - radius;
        const tl_y = center_y - radius;

        const border_widths: [4]f32 = if (config.border_width > 0)
            .{ config.border_width, config.border_width, config.border_width, config.border_width }
        else
            .{ 0, 0, 0, 0 };

        self.instance_data[self.rect_count] = .fromRect(
            tl_x,
            tl_y,
            diameter,
            diameter,
            radius, // corner_radius = radius makes it a perfect circle
            config.color,
            border_widths,
            config.border_color,
            0, // no rotation
        );

        self.rect_count += 1;
    }

    pub const RectOutlineConfig = struct {
        corner_radius: [4]f32 = .{0} ** 4,
        stroke_width: f32 = 1.0,
        color: [4]u8 = .{ 255, 255, 255, 255 },
    };

    pub fn drawRectOutline(self: *Renderer2D, tl_x: f32, tl_y: f32, w: f32, h: f32, config: RectOutlineConfig) void {
        if (self.rect_count >= MAX_RECTANGLES) self.flush();

        // Use border to create outline effect - fill is transparent, border is the stroke
        const border_widths: [4]f32 = .{
            config.stroke_width,
            config.stroke_width,
            config.stroke_width,
            config.stroke_width,
        };

        self.instance_data[self.rect_count] = .fromRect(
            tl_x,
            tl_y,
            w,
            h,
            config.corner_radius[0], // Using first corner radius (uniform for now)
            .{ 0, 0, 0, 0 }, // transparent fill
            border_widths,
            config.color, // stroke color
            0, // no rotation
        );

        self.rect_count += 1;
    }

    pub const CircleOutlineConfig = struct {
        stroke_width: f32 = 1.0,
        color: [4]u8 = .{ 255, 255, 255, 255 },
    };

    pub fn drawCircleOutline(self: *Renderer2D, center_x: f32, center_y: f32, radius: f32, config: CircleOutlineConfig) void {
        if (self.rect_count >= MAX_RECTANGLES) self.flush();

        // A circle outline is a square with corner_radius = radius, transparent fill, and border
        const diameter = radius * 2;
        const tl_x = center_x - radius;
        const tl_y = center_y - radius;

        const border_widths: [4]f32 = .{
            config.stroke_width,
            config.stroke_width,
            config.stroke_width,
            config.stroke_width,
        };

        self.instance_data[self.rect_count] = .fromRect(
            tl_x,
            tl_y,
            diameter,
            diameter,
            radius, // corner_radius = radius makes it a perfect circle
            .{ 0, 0, 0, 0 }, // transparent fill
            border_widths,
            config.color, // stroke color
            0, // no rotation
        );

        self.rect_count += 1;
    }

    pub const ArcConfig = struct {
        start_angle_deg: f32 = 0.0, // Start angle in degrees (0 = right, 90 = down, 180 = left, 270 = up)
        end_angle_deg: f32 = 90.0, // End angle in degrees
        thickness: f32 = 10.0, // Thickness of the arc stroke
        color: [4]u8 = .{ 255, 255, 255, 255 },
    };

    pub fn drawArc(self: *Renderer2D, center_x: f32, center_y: f32, radius: f32, config: ArcConfig) void {
        if (self.rect_count >= MAX_RECTANGLES) self.flush();

        // Convert degrees to radians for shader
        const start_angle_rad = std.math.degreesToRadians(config.start_angle_deg);
        const end_angle_rad = std.math.degreesToRadians(config.end_angle_deg);

        // Bounding box is a square containing the circle
        const diameter = radius * 2;
        const tl_x = center_x - radius;
        const tl_y = center_y - radius;

        self.instance_data[self.rect_count] = .{
            .pos_tl = .{ tl_x, tl_y },
            .size = .{ diameter, diameter },
            .color = config.color,
            .corner_radius = radius, // Store radius in corner_radius field
            .border_width = .{ config.thickness, config.thickness, config.thickness, config.thickness },
            .border_color = .{ 0, 0, 0, 0 }, // unused for arcs
            .use_texture = .arc,
            .uv_data = .{ start_angle_rad, end_angle_rad, 0, 0 }, // Pack angles in uv_data
            .rotation = 0,
        };

        self.rect_count += 1;
    }

    pub const TriangleConfig = struct {
        color: [4]u8 = .{ 255, 255, 255, 255 },
    };

    pub fn drawTriangle(self: *Renderer2D, p1: [2]f32, p2: [2]f32, p3: [2]f32, config: TriangleConfig) void {
        if (self.triangle_count >= MAX_TRIANGLES) {
            std.log.warn("Triangle buffer full, skipping triangle", .{});
            return;
        }

        const base_idx = self.triangle_count * 3;
        self.triangle_vertices[base_idx] = .{
            .pos = p1,
            .color = config.color,
        };
        self.triangle_vertices[base_idx + 1] = .{
            .pos = p2,
            .color = config.color,
        };
        self.triangle_vertices[base_idx + 2] = .{
            .pos = p3,
            .color = config.color,
        };

        self.triangle_count += 1;
    }

    pub fn drawText(self: *Renderer2D, window_scale: [2]f32, font_family: FontFamily, text: []const u8, x: f32, y: f32, size: f32, style: FontStyle, text_color: [4]u8) !void {
        // const now = std.time.milliTimestamp();
        // defer std.debug.print("drawText took {d}ms\n", .{std.time.milliTimestamp() - now});

        const font = font_mod.getFont(font_family, style, size * window_scale[1]) catch |err| {
            std.log.err("Failed to get font: {s}", .{@errorName(err)});
            return;
        };
        if (self.current_texture_id == null or self.current_font_id == null or self.current_font_id.? != font.id) {
            self.flush();
            const tex = self.getOrCreateAtlasTexture(font.atlas, font.id);
            c.ActiveTexture(c.TEXTURE0);
            c.BindTexture(c.TEXTURE_2D, tex);
            self.current_texture_id = tex;
            self.current_font_id = font.id;
            self.current_image_id = null;
        }

        const glyphs = try self.shape_cache.get(font.*, text);

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
                .use_texture = .text,
                .uv_data = .{
                    @as(f32, @floatFromInt(rect.x)) / @as(f32, @floatFromInt(font.atlas.width)),
                    @as(f32, @floatFromInt(rect.y)) / @as(f32, @floatFromInt(font.atlas.height)),
                    @as(f32, @floatFromInt(rect.w)) / @as(f32, @floatFromInt(font.atlas.width)),
                    @as(f32, @floatFromInt(rect.h)) / @as(f32, @floatFromInt(font.atlas.height)),
                },
                .rotation = 0,
            };
            self.rect_count += 1;

            // advance pen by HarfBuzz advance (already in pixels), scaled
            cursor_x += g.x_advance * scale;
            cursor_y += g.y_advance * scale;
        }
    }

    //TODO: based on window scale the image should be in higher or lower resolution
    pub fn drawImage(
        self: *Renderer2D,
        image: ImageTexture,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        tint: [4]u8, // white = no tint: .{255, 255, 255, 255}
    ) void {
        // Flush if we're switching textures
        if (self.current_image_id == null or self.current_image_id.? != image.id) {
            self.flush();
            c.ActiveTexture(c.TEXTURE0);
            c.BindTexture(c.TEXTURE_2D, image.id);
            self.current_image_id = image.id;
            self.current_font_id = null; // invalidate font cache
            self.current_texture_id = null;
        }

        if (self.rect_count >= MAX_RECTANGLES) self.flush();

        self.instance_data[self.rect_count] = .{
            .pos_tl = .{ x, y },
            .size = .{ w, h },
            .color = tint,
            .corner_radius = 0,
            .border_width = .{0} ** 4,
            .border_color = .{0} ** 4,
            .use_texture = .image,
            .uv_data = .{ 0.0, 0.0, 1.0, 1.0 }, // full texture
            .rotation = 0,
        };
        self.rect_count += 1;
    }

    pub fn flushTriangles(self: *Renderer2D, window_size: [2]u32, window_scale: [2]f32) void {
        if (self.triangle_count == 0) return;

        c.BindVertexArray(self.triangle_vao);
        c.UseProgram(self.triangle_program.id);
        c.Uniform4f(
            self.triangle_program.uniformLocation("window_params"),
            @floatFromInt(window_size[0]),
            @floatFromInt(window_size[1]),
            window_scale[0],
            window_scale[1],
        );

        c.BindBuffer(c.ARRAY_BUFFER, self.triangle_vbo);
        c.BufferSubData(
            c.ARRAY_BUFFER,
            0,
            @intCast(self.triangle_count * 3 * @sizeOf(TriangleVertex)),
            &self.triangle_vertices[0],
        );

        c.DrawArrays(c.TRIANGLES, 0, @intCast(self.triangle_count * 3));
        self.triangle_count = 0;

        if (c.GetError() != c.NO_ERROR) {
            std.log.err("OpenGL error during flushTriangles: {d}", .{c.GetError()});
        }
    }

    pub fn end(self: *Renderer2D, window_size: [2]u32, window_scale: [2]f32) void {
        self.flush();
        self.flushTriangles(window_size, window_scale);
    }

    pub fn loadImage(self: *Renderer2D, path: []const u8) !ImageTexture {
        if (self.image_textures.get(path)) |cached| {
            return cached;
        }

        const image = try ImageTexture.loadFromPath(self.allocator, path);
        const path_owned = try self.allocator.dupe(u8, path);
        try self.image_textures.put(path_owned, image);

        return image;
    }

    // For embedded data, add this too:
    pub fn loadImageFromMemory(self: *Renderer2D, id: []const u8, data: []const u8) !ImageTexture {
        if (self.image_textures.get(id)) |cached| {
            return cached;
        }

        const image = try ImageTexture.loadFromMemory(data);
        const id_owned = try self.allocator.dupe(u8, id);
        try self.image_textures.put(id_owned, image);

        return image;
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

// IMAGE
pub const ImageTexture = struct {
    id: c_uint,
    width: u32,
    height: u32,

    pub fn loadFromPath(allocator: Allocator, path: []const u8) !ImageTexture {
        const path_z = try allocator.dupeZ(u8, path);
        errdefer allocator.free(path_z);

        var width: c_int = undefined;
        var height: c_int = undefined;
        var channels: c_int = undefined;

        const data = stb_image.stbi_load(
            path_z.ptr,
            &width,
            &height,
            &channels,
            4, // force RGBA
        ) orelse {
            std.log.err("Failed to load image from path: {s}", .{path});
            return error.ImageLoadFailed;
        };
        defer stb_image.stbi_image_free(data);

        return uploadToGPU(data, @intCast(width), @intCast(height));
    }

    pub fn loadFromMemory(comptime image_data: []const u8) !ImageTexture {
        var width: c_int = undefined;
        var height: c_int = undefined;
        var channels: c_int = undefined;

        const data = stb_image.stbi_load_from_memory(
            image_data.ptr,
            @intCast(image_data.len),
            &width,
            &height,
            &channels,
            4, // force RGBA
        ) orelse {
            std.log.err("Failed to load image from memory", .{});
            return error.ImageLoadFailed;
        };
        defer stb_image.stbi_image_free(data);

        return uploadToGPU(data, @intCast(width), @intCast(height));
    }

    fn uploadToGPU(data: [*c]u8, width: u32, height: u32) !ImageTexture {
        var tex_id: c_uint = undefined;
        c.GenTextures(1, (&tex_id)[0..1]);
        c.ActiveTexture(c.TEXTURE0);
        c.BindTexture(c.TEXTURE_2D, tex_id);

        c.TexImage2D(
            c.TEXTURE_2D,
            0,
            c.RGBA,
            @intCast(width),
            @intCast(height),
            0,
            c.RGBA,
            c.UNSIGNED_BYTE,
            data,
        );

        // Set texture parameters
        c.TexParameteri(c.TEXTURE_2D, c.TEXTURE_MIN_FILTER, c.NEAREST);
        c.TexParameteri(c.TEXTURE_2D, c.TEXTURE_MAG_FILTER, c.NEAREST);

        c.TexParameteri(c.TEXTURE_2D, c.TEXTURE_WRAP_S, c.CLAMP_TO_EDGE);
        c.TexParameteri(c.TEXTURE_2D, c.TEXTURE_WRAP_T, c.CLAMP_TO_EDGE);

        const err = c.GetError();
        if (err != c.NO_ERROR) {
            std.log.err("OpenGL error during texture upload: {d}", .{err});
            c.DeleteTextures(1, (&tex_id)[0..1]);
            return error.OpenGLTextureUploadFailed;
        }

        return ImageTexture{
            .id = tex_id,
            .width = width,
            .height = height,
        };
    }

    pub fn deinit(self: *ImageTexture) void {
        c.DeleteTextures(1, (&self.id)[0..1]);
    }
};
