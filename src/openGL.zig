const std = @import("std");
const assert = std.debug.assert;
pub const gl = @import("gl");

pub const Program = struct {
    id: c_uint,

    window_size_loc: c_int,

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

        gl.DeleteProgram(vs);
        gl.DeleteProgram(fs);

        return .{
            .id = program_id,
            .window_size_loc = gl.GetUniformLocation(program_id, "window_size"),
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
        gl.ShaderSource(shader, 1, &.{src.ptr}, null);
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

const Vertex = struct {
    pos: [2]f32,
    color: [4]f32,
    rect_center: [2]f32,
    rect_size: [2]f32,
    corner_radius: f32,
    border_width: f32,
    border_color: [4]f32,

    fn fromRect(x: f32, y: f32, w: f32, h: f32, r: f32, rect_center: [2]f32, color: [4]f32) Vertex {
        return Vertex{
            .pos = .{ x, y },
            .color = color,
            .rect_center = rect_center,
            .rect_size = .{ w, h },
            .corner_radius = r,
            .border_width = 0,
            .border_color = .{ 0, 0, 0, 0 },
        };
    }

    comptime {
        assert(@offsetOf(Vertex, "pos") == 0);
        assert(@offsetOf(Vertex, "color") == 2 * @sizeOf(f32));
        assert(@offsetOf(Vertex, "rect_center") == (2 + 4) * @sizeOf(f32));
        assert(@offsetOf(Vertex, "rect_size") == (2 + 4 + 2) * @sizeOf(f32));
        assert(@offsetOf(Vertex, "corner_radius") == (2 + 4 + 2 + 2) * @sizeOf(f32));
        assert(@offsetOf(Vertex, "border_width") == (2 + 4 + 2 + 2 + 1) * @sizeOf(f32));
        assert(@offsetOf(Vertex, "border_color") == (2 + 4 + 2 + 2 + 1 + 1) * @sizeOf(f32));
    }
};

pub const MAX_RECTANGLES = 10_000;
pub const MAX_VERTICES = MAX_RECTANGLES * 4;
pub const MAX_INDICES = MAX_RECTANGLES * 6;

pub const Renderer2D = struct {
    program: Program,

    vao: c_uint,
    vbo: c_uint,
    ebo: c_uint,

    window_scale_x: f32,
    window_scale_y: f32,

    vertexData: [MAX_VERTICES]Vertex,
    indexData: [MAX_INDICES]c_uint,
    vertexCount: usize,
    indexCount: usize,

    pub fn init(program: Program) !Renderer2D {
        var vao: c_uint = undefined;
        gl.GenVertexArrays(1, (&vao)[0..1]);
        gl.BindVertexArray(vao);

        var vbo: c_uint = undefined;
        gl.GenBuffers(1, (&vbo)[0..1]);
        gl.BindBuffer(gl.ARRAY_BUFFER, vbo);
        gl.BufferData(gl.ARRAY_BUFFER, MAX_VERTICES * @sizeOf(Vertex), null, gl.DYNAMIC_DRAW);

        var ibo: c_uint = undefined;
        gl.GenBuffers(1, (&ibo)[0..1]);
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ibo);
        gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, MAX_INDICES * @sizeOf(c_uint), null, gl.DYNAMIC_DRAW);

        const stride: c_uint = @sizeOf(Vertex);

        gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, stride, @offsetOf(Vertex, "pos"));
        gl.EnableVertexAttribArray(0);

        gl.VertexAttribPointer(1, 4, gl.FLOAT, gl.FALSE, stride, @offsetOf(Vertex, "color"));
        gl.EnableVertexAttribArray(1);

        gl.VertexAttribPointer(2, 2, gl.FLOAT, gl.FALSE, stride, @offsetOf(Vertex, "rect_center"));
        gl.EnableVertexAttribArray(2);

        gl.VertexAttribPointer(3, 2, gl.FLOAT, gl.FALSE, stride, @offsetOf(Vertex, "rect_size"));
        gl.EnableVertexAttribArray(3);

        gl.VertexAttribPointer(4, 1, gl.FLOAT, gl.FALSE, stride, @offsetOf(Vertex, "corner_radius"));
        gl.EnableVertexAttribArray(4);

        gl.VertexAttribPointer(5, 1, gl.FLOAT, gl.FALSE, stride, @offsetOf(Vertex, "border_width"));
        gl.EnableVertexAttribArray(5);

        gl.VertexAttribPointer(6, 4, gl.FLOAT, gl.FALSE, stride, @offsetOf(Vertex, "border_color"));
        gl.EnableVertexAttribArray(6);

        gl.Enable(gl.BLEND);
        gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

        return Renderer2D{
            .program = program,
            .vao = vao,
            .vbo = vbo,
            .ebo = ibo,
            .vertexData = undefined,
            .indexData = undefined,
            .vertexCount = 0,
            .indexCount = 0,
            .window_scale_x = 1,
            .window_scale_y = 1,
        };
    }

    pub fn begin(self: *Renderer2D, window_scale_x: f32, window_scale_y: f32) void {
        self.vertexCount = 0;
        self.indexCount = 0;
        self.window_scale_x = window_scale_x;
        self.window_scale_y = window_scale_y;
    }

    pub fn drawRect(self: *Renderer2D, x: f32, y: f32, w: f32, h: f32, color: [4]f32) void {
        if (self.vertexCount + 4 > MAX_VERTICES or self.indexCount + 6 > MAX_INDICES) {
            std.log.err("Vertex buffer or index buffer overflow", .{});
            std.debug.print("Vertex count: {d}, Index count: {d}\n", .{ self.vertexCount, self.indexCount });
            return;
        }

        drawRoundedRect(self, x, y, w, h, 0.0, color);
    }

    pub fn drawRoundedRect(self: *Renderer2D, x: f32, y: f32, w: f32, h: f32, r: f32, color: [4]f32) void {
        if (self.vertexCount + 4 > MAX_VERTICES or self.indexCount + 6 > MAX_INDICES) {
            std.log.err("Vertex buffer or index buffer overflow", .{});
            std.debug.print("Vertex count: {d}, Index count: {d}\n", .{ self.vertexCount, self.indexCount });
            return;
        }

        const scale_x: f32 = self.window_scale_x;
        const scale_y: f32 = self.window_scale_y;

        const tl_x = x * scale_x;
        const tl_y = y * scale_y;
        const br_x = (x + w) * scale_x;
        const br_y = (y + h) * scale_y;

        const width_scaled = w * scale_x;
        const height_scaled = h * scale_y;

        const base: c_uint = @intCast(self.vertexCount);

        const center_x = tl_x + width_scaled / 2;
        const center_y = tl_y + height_scaled / 2;
        const r_scaled = r * @max(scale_x, scale_y);

        // 4 vertices
        self.vertexData[self.vertexCount + 0] = .fromRect(tl_x, tl_y, width_scaled, height_scaled, r_scaled, .{ center_x, center_y }, color);
        self.vertexData[self.vertexCount + 1] = .fromRect(br_x, tl_y, width_scaled, height_scaled, r_scaled, .{ center_x, center_y }, color);
        self.vertexData[self.vertexCount + 2] = .fromRect(br_x, br_y, width_scaled, height_scaled, r_scaled, .{ center_x, center_y }, color);
        self.vertexData[self.vertexCount + 3] = .fromRect(tl_x, br_y, width_scaled, height_scaled, r_scaled, .{ center_x, center_y }, color);

        // 6 indices
        self.indexData[self.indexCount + 0] = base + 0; // tl
        self.indexData[self.indexCount + 1] = base + 2; // br
        self.indexData[self.indexCount + 2] = base + 1; // tr
        self.indexData[self.indexCount + 3] = base + 0; // tl
        self.indexData[self.indexCount + 4] = base + 3; // bl
        self.indexData[self.indexCount + 5] = base + 2; // br

        self.vertexCount += 4;
        self.indexCount += 6;
    }

    pub fn end(self: *Renderer2D) void {
        gl.BindVertexArray(self.vao);

        gl.BindBuffer(gl.ARRAY_BUFFER, self.vbo);
        gl.BufferSubData(gl.ARRAY_BUFFER, 0, @intCast(@sizeOf(Vertex) * self.vertexCount), &self.vertexData[0]);

        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.ebo);
        gl.BufferSubData(gl.ELEMENT_ARRAY_BUFFER, 0, @intCast(@sizeOf(c_uint) * self.indexCount), &self.indexData[0]);

        gl.DrawElements(gl.TRIANGLES, @intCast(self.indexCount), gl.UNSIGNED_INT, 0);
    }
};
