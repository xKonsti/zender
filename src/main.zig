const std = @import("std");
const c = @cImport({
    @cDefine("GLFW_INCLUDE_NONE", "1");
    @cInclude("GLFW/glfw3.h");
    // We won’t `@cInclude <GL/gl.h>` because we’ll load those functions via loader
});

// You’ll import or declare OpenGL function pointers somewhere, e.g.:
const gl = @import("gl"); // assume this is a module with OpenGL bindings (e.g. via zigglgen)
var procs: gl.ProcTable = undefined;

fn errorCallback(errn: c_int, str: [*c]const u8) callconv(std.builtin.CallingConvention.c) void {
    std.log.err("GLFW Error: {d} - {s}\n", .{ errn, str });
}

pub fn main() !void {
    _ = c.glfwSetErrorCallback(errorCallback);

    if (c.glfwInit() != c.GLFW_TRUE) {
        return error.InitFailed;
    }
    defer c.glfwTerminate();

    // Set hints if you want a specific OpenGL version (optional)
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 3);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 3);
    c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);
    // On macOS, also:
    // c.glfwWindowHint(c.GLFW_OPENGL_FORWARD_COMPAT, c.GLFW_TRUE);

    const window = c.glfwCreateWindow(640, 480, "Hello OpenGL", null, null) orelse return error.WindowCreationFailed;
    defer c.glfwDestroyWindow(window);

    c.glfwMakeContextCurrent(window);
    c.glfwSwapInterval(1);

    // Initialize OpenGL function table
    if (!procs.init(c.glfwGetProcAddress)) {
        return error.OpenGLLoadFailed;
    }
    gl.makeProcTableCurrent(&procs);

    // Main loop
    while (c.glfwWindowShouldClose(window) == c.GLFW_FALSE) {
        // Optionally: get framebuffer size, set viewport
        var fb_w: c_int = 0;
        var fb_h: c_int = 0;
        c.glfwGetFramebufferSize(window, &fb_w, &fb_h);
        gl.Viewport(0, 0, fb_w, fb_h);

        // Clear screen
        gl.ClearColor(0.2, 0.3, 0.3, 1.0);
        gl.Clear(gl.COLOR_BUFFER_BIT);

        // Draw something: e.g. a triangle
        // (you need to set up VAO, VBO, shaders etc. — I'll show minimal below)

        // Swap buffers & poll events
        c.glfwSwapBuffers(window);
        c.glfwPollEvents();
    }
}

const vertex_shader_src = 
            \\#version 330 core
            \\layout (location = 0) in vec3 aPos;
            \\void main() {
                \\gl_Position = vec4(aPos, 1.0);
            \\}
            \\
        ;

const fragment_shader_src = 
\\#version 330 core
\\out vec4 FragColor;
\\void main() {
    \\FragColor = vec4(1.0, 0.5, 0.2, 1.0);
\\}
;

fn compileShader(t: gl.Enum, source: []const u8) !u32 {
    const shader = gl.CreateShader(t);
    gl.ShaderSource(shader, 1, &source, null);
    gl.CompileShader(shader);
    var success: i32 = 0;
    gl.GetShaderiv(shader, gl.COMPILE_STATUS, &success);
    if (success == 0) {
        // get error log
        var len: i32 = 0;
        gl.GetShaderiv(shader, gl.INFO_LOG_LENGTH, &len);
        const buf = std.heap.c_allocator.alloc(u8, len + 1) catch return error.MemAlloc;
        defer std.heap.c_allocator.free(buf);
        gl.GetShaderInfoLog(shader, len, null, buf);
        std.debug.print("Shader compile error: {s}\n", .{ buf });
        return error.ShaderCompileFailed;
    }
    return shader;
}

fn linkProgram(vertex: u32, fragment: u32) !u32 {
    const program = gl.CreateProgram();
    gl.AttachShader(program, vertex);
    gl.AttachShader(program, fragment);
    gl.LinkProgram(program);
    var success: i32 = 0;
    gl.GetProgramiv(program, gl.LINK_STATUS, &success);
    if (success == 0) {
        var len: i32 = 0;
        gl.GetProgramiv(program, gl.INFO_LOG_LENGTH, &len);
        const buf = std.heap.c_allocator.alloc(u8, len + 1) catch return error.MemAlloc;
        defer std.heap.c_allocator.free(buf);
        gl.GetProgramInfoLog(program, len, null, buf);
        std.debug.print("Program link error: {s}\n", .{ buf });
        return error.ProgramLinkFailed;
    }
    return program;
}
