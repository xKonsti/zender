const std = @import("std");
const glfw = @import("glfw.zig");

// Youâ€™ll import or declare OpenGL function pointers somewhere, e.g.:
const gl = @import("gl"); // assume this is a module with OpenGL bindings (e.g. via zigglgen)
var procs: gl.ProcTable = undefined;
const glWrapper = @import("openGL.zig");

fn errorCallback(errn: c_int, str: [*c]const u8) callconv(std.builtin.CallingConvention.c) void {
    std.log.err("GLFW Error: {d} - {s}\n", .{ errn, str });
}

pub fn main() !void {
    _ = glfw.setErrorCallback(errorCallback);
    try glfw.init();
    defer glfw.deinit();

    glfw.defaultWindowHints();

    var window = try glfw.Window.init(640, 480, "2D UI Renderer", null, null);
    defer window.deinit();

    glfw.makeContextCurrent(window.handle);
    glfw.swapInterval(1);

    // Initialize OpenGL function table
    if (!procs.init(glfw.getProcAddress)) {
        return error.OpenGLLoadFailed;
    }
    gl.makeProcTableCurrent(&procs);
    defer gl.makeProcTableCurrent(null);

    // 2D UI vertices with position, UV, and color
    // Triangle positioned in screen coordinates (will be converted in shader)
    const vertices = [_]f32{
        0.5, 0.5, 0.0,
        0.5, -0.5, 0.0,
        -0.5, -0.5, 0.0,
        -0.5, 0.5, 0.0
    };
    const indices = [_]c_uint{
        0, 1, 3,
        1, 2, 3
    };

    const program = try glWrapper.Program.init(@embedFile("vert.glsl"), @embedFile("frag.glsl"));
    defer program.deinit();

    var vao: c_uint = undefined;
    gl.GenVertexArrays(1, (&vao)[0..1]);
    gl.BindVertexArray(vao);

    var vbo: c_uint = undefined;
    gl.GenBuffers(1, (&vbo)[0..1]);
    gl.BindBuffer(gl.ARRAY_BUFFER, vbo);
    gl.BufferData(gl.ARRAY_BUFFER, @sizeOf(f32) * vertices.len, &vertices, gl.STATIC_DRAW);

    var ebo: c_uint = undefined;
    gl.GenBuffers(1, (&ebo)[0..1]);
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo);
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, @sizeOf(c_uint) * indices.len, &indices, gl.STATIC_DRAW);

    gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 3 * @sizeOf(f32), 0);
    gl.EnableVertexAttribArray(0);

    // Main loop
    while (!window.shouldClose()) {
        const dims = window.windowSize();
        gl.Viewport(0, 0, @intCast(dims.w), @intCast(dims.h));

        // Clear screen
        gl.ClearColor(0.2, 0.3, 0.3, 1.0);
        gl.Clear(gl.COLOR_BUFFER_BIT);

        program.use();
        gl.BindVertexArray(vao);
        gl.PolygonMode(gl.FRONT_AND_BACK, gl.FILL);
        gl.DrawArrays(gl.TRIANGLES, 0, 3);
        gl.DrawArrays(gl.TRIANGLES, 2, 3);
        // gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_INT, 0);
        gl.BindVertexArray(0);

        // Swap buffers & poll events
        window.swapBuffers();
        glfw.pollEvents();
    }
}
