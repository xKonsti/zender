const std = @import("std");
const assert = std.debug.assert;
pub const gl = @import("gl");
const Font = @import("font.zig").Font;
const FontAtlas = @import("font.zig").FontAtlas;

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
    color: [4]f32,
    corner_radius: f32, // unscaled
    border_width: f32, // unscaled
    border_color: [4]f32,
    use_texture: c_int, // 0 = solid, 1 = textured
    uv_data: [4]f32, // for text/images, UV data (x, y, width, height)

    fn fromRect(x: f32, y: f32, w: f32, h: f32, r: f32, color: [4]f32, border_width: f32, border_color: [4]f32) InstanceData {
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

    comptime {
        assert(@offsetOf(InstanceData, "pos_tl") == 0);
        assert(@offsetOf(InstanceData, "size") == 2 * @sizeOf(f32));
        assert(@offsetOf(InstanceData, "color") == (2 + 2) * @sizeOf(f32));
        assert(@offsetOf(InstanceData, "corner_radius") == (2 + 2 + 4) * @sizeOf(f32));
        assert(@offsetOf(InstanceData, "border_width") == (2 + 2 + 4 + 1) * @sizeOf(f32));
        assert(@offsetOf(InstanceData, "border_color") == (2 + 2 + 4 + 1 + 1) * @sizeOf(f32));
        assert(@offsetOf(InstanceData, "use_texture") == (2 + 2 + 4 + 1 + 1 + 4) * @sizeOf(f32));
        assert(@offsetOf(InstanceData, "uv_data") == (2 + 2 + 4 + 1 + 1 + 4 + 1) * @sizeOf(f32));
    }
};

pub const MAX_RECTANGLES = 10_000;

pub const Renderer2D = struct {
    program: Program,
    base_vbo: c_uint,
    base_ebo: c_uint,
    vao: c_uint,
    vbo: c_uint,
    instance_data: [MAX_RECTANGLES]InstanceData,
    rect_count: usize,
    current_texture: c_uint,
    white_texture: c_uint,
    atlas_texture: c_uint,

    pub fn init(program: Program) !Renderer2D {
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

        gl.VertexAttribPointer(3, 4, gl.FLOAT, gl.FALSE, stride, @offsetOf(InstanceData, "color"));
        gl.VertexAttribDivisor(3, 1);
        gl.EnableVertexAttribArray(3);

        gl.VertexAttribPointer(4, 1, gl.FLOAT, gl.FALSE, stride, @offsetOf(InstanceData, "corner_radius"));
        gl.VertexAttribDivisor(4, 1);
        gl.EnableVertexAttribArray(4);

        gl.VertexAttribPointer(5, 1, gl.FLOAT, gl.FALSE, stride, @offsetOf(InstanceData, "border_width"));
        gl.VertexAttribDivisor(5, 1);
        gl.EnableVertexAttribArray(5);

        gl.VertexAttribPointer(6, 4, gl.FLOAT, gl.FALSE, stride, @offsetOf(InstanceData, "border_color"));
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

        // Create white texture
        var white_texture: c_uint = undefined;
        gl.GenTextures(1, (&white_texture)[0..1]);
        gl.BindTexture(gl.TEXTURE_2D, white_texture);
        const white_pixel = [4]u8{ 255, 255, 255, 255 };
        gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, &white_pixel);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);

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
            .current_texture = white_texture,
            .white_texture = white_texture,
            .atlas_texture = atlas_texture,
        };
    }

    pub fn deinit(self: *Renderer2D) void {
        gl.DeleteVertexArrays(1, (&self.vao)[0..1]);
        gl.DeleteBuffers(1, (&self.vbo)[0..1]);
        gl.DeleteBuffers(1, (&self.base_vbo)[0..1]);
        gl.DeleteBuffers(1, (&self.base_ebo)[0..1]);
        gl.DeleteTextures(1, (&self.white_texture)[0..1]);
        gl.DeleteTextures(1, (&self.atlas_texture)[0..1]);
    }

    pub fn begin(self: *Renderer2D, window_size: [2]u32, window_scale: [2]f32) void {
        self.rect_count = 0;
        gl.BindVertexArray(self.vao);
        gl.UseProgram(self.program.id);
        gl.Uniform4f(self.program.window_params_loc, @floatFromInt(window_size[0]), @floatFromInt(window_size[1]), window_scale[0], window_scale[1]);
        gl.Uniform1i(self.program.tex_loc, 0);
        gl.ActiveTexture(gl.TEXTURE0);
        gl.BindTexture(gl.TEXTURE_2D, self.white_texture);
        self.current_texture = self.white_texture;

        if (gl.GetError() != gl.NO_ERROR) {
            std.log.err("OpenGL error during Renderer2D.begin: {d}", .{gl.GetError()});
        }
    }

    fn flush(self: *Renderer2D) void {
        if (self.rect_count == 0) return;
        std.log.debug("Flushing {d} rectangles", .{self.rect_count});
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

    pub fn uploadAtlas(self: *Renderer2D, font_atlas: FontAtlas) void {
        // Make sure we target texture unit 0 because that's what the shader expects via Uniform1i(...)
        gl.ActiveTexture(gl.TEXTURE0);
        gl.BindTexture(gl.TEXTURE_2D, self.atlas_texture);

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

    pub inline fn drawRect(self: *Renderer2D, x: f32, y: f32, w: f32, h: f32, color: [4]f32) void {
        drawRoundedBorderRect(self, x, y, w, h, 0.0, color, 0, color);
    }

    pub fn drawRoundedRect(self: *Renderer2D, x: f32, y: f32, w: f32, h: f32, r: f32, color: [4]f32) void {
        drawRoundedBorderRect(self, x, y, w, h, r, color, 0, color);
    }

    pub fn drawRoundedBorderRect(self: *Renderer2D, x: f32, y: f32, w: f32, h: f32, r: f32, color: [4]f32, border_width: f32, border_color: [4]f32) void {
        if (self.rect_count >= MAX_RECTANGLES) self.flush();
        self.instance_data[self.rect_count] = .fromRect(x, y, w, h, r, color, border_width, border_color);
        self.rect_count += 1;
    }

    pub fn drawText(self: *Renderer2D, font: Font, text: []const u8, x: f32, y: f32, size: f32, text_color: [4]f32) !void {
        // Switch texture if needed
        if (self.current_texture != self.atlas_texture) {
            self.flush();
            // gl.BindTexture(gl.TEXTURE_2D, self.atlas_texture);
            std.debug.print("uploading atlas with width = {}\n", .{font.atlas.width});
            self.uploadAtlas(font.atlas);
            self.current_texture = self.atlas_texture;
        }

        // Shape text (using your font.zig HarfBuzz wrapper)
        const glyphs = try font.shapeText(text);
        defer font.deinitShapedText(glyphs);

        var cursor_x: f32 = x;
        var cursor_y: f32 = y;

        // Scale glyph to requested text size
        const scale = size / font.pixel_height;

        for (glyphs) |g| {
            if (g.cluster < text.len and text[g.cluster] == '\n') {
                cursor_x = x;
                cursor_y += size;
                continue;
            }

            const rect = font.atlas.glyphs_map.get(g.glyph_index) orelse continue;

            if (rect.w == 0 or rect.h == 0) {
                cursor_x += g.x_advance * scale;
                cursor_y += g.y_advance * scale;
                continue;
            }

            const w = @as(f32, @floatFromInt(rect.w)) * scale;
            const h = @as(f32, @floatFromInt(rect.h)) * scale;

            // Baseline-correct placement
            const xpos = cursor_x + @as(f32, @floatFromInt(rect.left)) * scale;
            const ypos = cursor_y - @as(f32, @floatFromInt(rect.top)) * scale;

            // Instance setup
            if (self.rect_count >= MAX_RECTANGLES) self.flush();
            self.instance_data[self.rect_count] = .{
                .pos_tl = .{ xpos, ypos },
                .size = .{ w, h },
                .color = text_color,
                .corner_radius = 0,
                .border_width = 0,
                .border_color = .{ 0, 0, 0, 0 },
                .use_texture = 1,
                .uv_data = .{
                    @as(f32, @floatFromInt(rect.x)) / @as(f32, @floatFromInt(font.atlas.width)),
                    @as(f32, @floatFromInt(rect.y)) / @as(f32, @floatFromInt(font.atlas.height)),
                    @as(f32, @floatFromInt(rect.w)) / @as(f32, @floatFromInt(font.atlas.width)),
                    @as(f32, @floatFromInt(rect.h)) / @as(f32, @floatFromInt(font.atlas.height)),
                },
            };
            self.rect_count += 1;

            // Advance cursor
            cursor_x += g.x_advance * scale;
            cursor_y += g.y_advance * scale;
        }
    }

    pub fn end(self: *Renderer2D) void {
        self.flush();
    }
};
