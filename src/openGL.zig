const std = @import("std");
const assert = std.debug.assert;
pub const gl = @import("gl");

pub const Program = struct {
    id: c_uint,

    pub fn init(comptime vertex_shader_src: []const u8, comptime fragment_shader_src: []const u8) !Program {
        const program = gl.CreateProgram();

        const vs = try compileShader(gl.VERTEX_SHADER, vertex_shader_src);
        const fs = try compileShader(gl.FRAGMENT_SHADER, fragment_shader_src);

        gl.AttachShader(program, vs);
        gl.AttachShader(program, fs);
        gl.LinkProgram(program);

        var success: c_int = undefined;
        var info_log: [512]u8 = undefined;
        gl.GetProgramiv(program, gl.LINK_STATUS, (&success)[0..1]);
        if (success == 0) {
            gl.GetProgramInfoLog(program, info_log.len, null, info_log[0..]);
            std.log.err("Program link error: {s}", .{info_log});
            return error.ProgramLinkFailed;
        }

        gl.DeleteProgram(vs);
        gl.DeleteProgram(fs);

        return Program{ .id = program };
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
    pos: [3]f32,
    color: [4]f32,
};

comptime {
    assert(@offsetOf(Vertex, "pos") == 0);
    assert(@offsetOf(Vertex, "color") == 3 * @sizeOf(f32));
}

pub const MAX_RECTANGLES = 1_000;
pub const MAX_VERTICES = MAX_RECTANGLES * 4;
pub const MAX_INDICES = MAX_RECTANGLES * 6;

pub const Renderer2D = struct {
    vao: c_uint,
    vbo: c_uint,
    ibo: c_uint,

    vertexData: [MAX_VERTICES]Vertex,
    indexData: [MAX_INDICES]c_uint,
    vertexCount: usize,
    indexCount: usize,

    pub fn init() !Renderer2D {
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

        // vertex attribs: pos (3 floats), color (4 floats)
        gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, stride, 0);
        gl.EnableVertexAttribArray(0);

        gl.VertexAttribPointer(1, 4, gl.FLOAT, gl.FALSE, stride, @offsetOf(Vertex, "color"));
        gl.EnableVertexAttribArray(1);

        return Renderer2D{
            .vao = vao,
            .vbo = vbo,
            .ibo = ibo,
            .vertexData = std.mem.zeroes([MAX_VERTICES]Vertex),
            .indexData = std.mem.zeroes([MAX_INDICES]c_uint),
            .vertexCount = 0,
            .indexCount = 0,
        };
    }

    pub fn begin(self: *Renderer2D) void {
        self.vertexCount = 0;
        self.indexCount = 0;
    }

    pub fn drawRect(self: *Renderer2D, x: f32, y: f32, w: f32, h: f32, color: [4]f32) void {
        if (self.vertexCount + 4 > MAX_VERTICES or self.indexCount + 6 > MAX_INDICES) {
            std.log.err("Vertex buffer or index buffer overflow", .{});
            std.debug.print("Vertex count: {d}, Index count: {d}\n", .{ self.vertexCount, self.indexCount });
            return;
        }

        const x0 = x;
        const y0 = y;
        const x1 = x + w;
        const y1 = y + h;
        const z = 0.0;

        const base: c_uint = @intCast(self.vertexCount);

        self.vertexData[self.vertexCount + 0] = Vertex{ .pos = .{ x0, y0, z }, .color = color };
        // 4 vertices
        self.vertexData[self.vertexCount + 1] = Vertex{ .pos = .{ x1, y0, z }, .color = color };
        self.vertexData[self.vertexCount + 2] = Vertex{ .pos = .{ x1, y1, z }, .color = color };
        self.vertexData[self.vertexCount + 3] = Vertex{ .pos = .{ x0, y1, z }, .color = color };

        // 6 indices
        self.indexData[self.indexCount + 0] = base + 0;
        self.indexData[self.indexCount + 1] = base + 1;
        self.indexData[self.indexCount + 2] = base + 2;
        self.indexData[self.indexCount + 3] = base + 0;
        self.indexData[self.indexCount + 4] = base + 2;
        self.indexData[self.indexCount + 5] = base + 3;

        self.vertexCount += 4;
        self.indexCount += 6;
    }

    pub fn end(self: *Renderer2D) void {
        gl.BindVertexArray(self.vao);

        gl.BindBuffer(gl.ARRAY_BUFFER, self.vbo);
        gl.BufferSubData(gl.ARRAY_BUFFER, 0, @intCast(@sizeOf(Vertex) * self.vertexCount), &self.vertexData[0]);

        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.ibo);
        gl.BufferSubData(gl.ELEMENT_ARRAY_BUFFER, 0, @intCast(@sizeOf(c_uint) * self.indexCount), &self.indexData[0]);

        gl.DrawElements(gl.TRIANGLES, @intCast(self.indexCount), gl.UNSIGNED_INT, 0);
    }
};
