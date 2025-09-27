const std = @import("std");
const glfw = @import("glfw.zig");

// You’ll import or declare OpenGL function pointers somewhere, e.g.:
const gl = @import("gl"); // assume this is a module with OpenGL bindings (e.g. via zigglgen)
var procs: gl.ProcTable = undefined;

fn errorCallback(errn: c_int, str: [*c]const u8) callconv(std.builtin.CallingConvention.c) void {
    std.log.err("GLFW Error: {d} - {s}\n", .{ errn, str });
}

pub fn main() !void {
    _ = glfw.setErrorCallback(errorCallback);
    try glfw.init();
    defer glfw.deinit();

    glfw.defaultWindowHints();

    var window = try glfw.Window.init(640, 480, "Hello OpenGL", null, null);
    defer window.deinit();

    glfw.makeContextCurrent(window.handle);
    glfw.swapInterval(1);

    // Initialize OpenGL function table
    if (!procs.init(glfw.getProcAddress)) {
        return error.OpenGLLoadFailed;
    }
    gl.makeProcTableCurrent(&procs);
    defer gl.makeProcTableCurrent(null);

    const vertices = [3][3]f32{
        .{ -0.5, -0.5, 0.0 },
        .{ 0.5, -0.5, 0.0 },
        .{ 0.0, 0.5, 0.0 },
    };

    var vao: gl.uint = undefined;
    var vbo: gl.uint = undefined;

    gl.GenVertexArrays(1, (&vao)[0..1]);
    gl.GenBuffers(1, (&vbo)[0..1]);

    gl.BindVertexArray(vao);
    gl.BindBuffer(gl.ARRAY_BUFFER, vbo);
    gl.BufferData(gl.ARRAY_BUFFER, @sizeOf(f32) * vertices.len, &vertices, gl.STATIC_DRAW);

    gl.VertexAttribPointer(0, // index
        3, // size (x,y,z)
        gl.FLOAT, // type
        gl.FALSE, // normalized
        @intCast(3 * @sizeOf(f32)), // stride in bytes
        0 // offset (start)
    );
    gl.EnableVertexAttribArray(0);

    gl.BindBuffer(gl.ARRAY_BUFFER, 0);
    gl.BindVertexArray(0);

    const fragment_shader_src = @embedFile("frag.frag");
    const vertex_shader_src = @embedFile("vert.vert");
    std.debug.print("vertex_shader_src:\n{s}\n", .{vertex_shader_src});
    std.debug.print("fragment_shader_src:\n{s}\n", .{fragment_shader_src});

    const vs = try compileShader(gl.VERTEX_SHADER, vertex_shader_src);
    const fs = try compileShader(gl.FRAGMENT_SHADER, fragment_shader_src);
    const shader = try linkProgram(vs, fs);
    defer gl.DeleteShader(vs);
    defer gl.DeleteShader(fs);
    defer gl.DeleteProgram(shader);

    // Main loop
    while (!window.shouldClose()) {
        const dims = window.windowSize();
        gl.Viewport(0, 0, @intCast(dims.w), @intCast(dims.h));

        // Clear screen
        gl.ClearColor(0.2, 0.3, 0.3, 1.0);
        gl.Clear(gl.COLOR_BUFFER_BIT);

        gl.UseProgram(shader);
        gl.BindVertexArray(vao);
        gl.DrawArrays(gl.TRIANGLES, 0, 3);
        gl.BindVertexArray(0);
        gl.UseProgram(0);

        // Draw something: e.g. a triangle

        // Swap buffers & poll events
        window.swapBuffers();
        glfw.pollEvents();
    }
}

// Helper: compile a shader
fn compileShader(kind: u32, comptime src: []const u8) !u32 {
    const shader = gl.CreateShader(kind);
    if (shader == 0) return error.ShaderCreateFailed;

    const shader_version = switch (gl.info.api) {
        .gl => (
            \\#version 410 core
            \\
        ),
        .gles, .glsc => (
            \\#version 300 es
            \\
        ),
    };

    gl.ShaderSource(
        shader,
        2,
        &.{ (src)[0..],shader_version  },
        &.{
            @intCast(src.len + 1),
            @intCast(shader_version.len),
        },
    );
    gl.CompileShader(shader);

    var success: c_int = 0;
    gl.GetShaderiv(shader, gl.COMPILE_STATUS, (&success)[0..1]);
    if (success == 0) {
        var log_len: c_int = 0;
        gl.GetShaderiv(shader, gl.INFO_LOG_LENGTH, (&log_len)[0..1]);

        const buf = try std.heap.page_allocator.alloc(u8, @intCast(log_len + 1));
        defer std.heap.page_allocator.free(buf);

        gl.GetShaderInfoLog(shader, log_len, null, buf.ptr);
        std.debug.print("Shader compile error: {s}\n", .{buf});
        return error.ShaderCompileFailed;
    }

    return shader;
}

// Helper: link vertex + fragment into a program
fn linkProgram(vs: u32, fs: u32) !u32 {
    const prog = gl.CreateProgram();
    if (prog == 0) return error.ProgramCreateFailed;

    gl.AttachShader(prog, vs);
    gl.AttachShader(prog, fs);
    gl.LinkProgram(prog);

    var success: gl.int = undefined;
    gl.GetProgramiv(prog, gl.LINK_STATUS, (&success)[0..1]);
    if (success == 0) {
        var log_len: c_int = 0;
        gl.GetProgramiv(prog, gl.INFO_LOG_LENGTH, (&log_len)[0..1]);
        const buf = try std.heap.page_allocator.alloc(u8, @intCast(log_len + 1));
        defer std.heap.page_allocator.free(buf);
        gl.GetProgramInfoLog(prog, log_len, null, buf.ptr);
        std.debug.print("Program link error: {s}\n", .{buf});
        return error.ProgramLinkFailed;
    }

    return prog;
}
