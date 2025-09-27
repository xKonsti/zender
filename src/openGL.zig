const std = @import("std");
const gl = @import("gl");

pub const Program = struct {
    handle: c_uint,

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

        return Program{ .handle = program };
    }

    pub fn deinit(self: Program) void {
        gl.DeleteProgram(self.handle);
    }

    pub fn use(self: Program) void {
        gl.UseProgram(self.handle);
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

// const Renderer2D = struct {
//     vao: c_uint,
//     vbo: c_uint,
//     ibo: c_uint,
//
//     const MAX_Rectangles = 1_000_000;  // cap of how many elements can be displayed at once assuming rectangles 
//
//     pub fn init() Renderer2D {
//         var vao: c_uint = 0;
//         gl.GenVertexArrays(1, (&vao)[0..1]);
//         gl.BindVertexArray(vao);
//
//         var vbo: c_uint = 0;
//         gl.GenBuffers(1, (&vbo)[0..1]);
//         gl.BindBuffer(gl.ARRAY_BUFFER, vbo);
//         gl.BufferData(gl.ARRAY_BUFFER, MAX_Rectangles * 4 * @sizeOf(Vertex), null, gl.DYNAMIC_DRAW);
//
//         var ibo: c_uint = 0;
//         gl.GenBuffers(1, (&ibo)[0..1]);
//         gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ibo);
//         gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, MAX_Rectangles * 6 * @sizeOf(c_uint), null, gl.DYNAMIC_DRAW);
//
//         gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), 0);
//         gl.EnableVertexAttribArray(0);
//
//         return Renderer2D{ .vao = vao, .vbo = vbo, .ibo = ibo };
//     }
//
//     pub fn begin(self: *Renderer2D) void {
//         // map buffer or reset write cursor
//     }
//
//     pub fn drawRect(self: *Renderer2D, x: f32, y: f32, w: f32, h: f32, color: [4]f32) void {
//         // push 4 vertices + 6 indices into your buffer
//     }
//
//     pub fn end(self: *Renderer2D) void {
//         _ = self;
//     }
// };
