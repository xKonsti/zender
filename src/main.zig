const std = @import("std");

const glfw = @import("glfw.zig");
const glWrapper = @import("openGL.zig");
const gl = glWrapper.gl;

// Youâ€™ll import or declare OpenGL function pointers somewhere, e.g.:
var procs: gl.ProcTable = undefined;

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
    glfw.swapInterval(0);

    // Initialize OpenGL function table
    if (!procs.init(glfw.getProcAddress)) {
        return error.OpenGLLoadFailed;
    }
    gl.makeProcTableCurrent(&procs);
    defer gl.makeProcTableCurrent(null);

    const program = try glWrapper.Program.init(@embedFile("vert.glsl"), @embedFile("frag.glsl"));
    defer program.deinit();

    // const uProjectionLoc = program.uniformLocation("uProjection");
    var renderer = glWrapper.Renderer2D.init() catch |err| {
        std.debug.print("Error in init Renderer2D: {t}\n", .{err});
        return;
    };
    const u_window_size_loc = program.uniformLocation("uWindowSize");
    // Main loop
    while (!window.shouldClose()) {
        const now = std.time.milliTimestamp();
        defer std.debug.print("Frame took {d}ms\n", .{std.time.milliTimestamp() - now});

        // Clear screen
        gl.ClearColor(0.2, 0.3, 0.3, 1.0);
        gl.Clear(gl.COLOR_BUFFER_BIT);

        program.use();
        const dims = window.bufferSize();
        gl.Uniform2f(u_window_size_loc, @floatFromInt(dims.w), @floatFromInt(dims.h));

        renderer.begin();
        renderer.drawRect(0, 0, 200, 50, .{ 1.3, 0.5, 0.0, 1.0 });
        renderer.drawRect(0, 0, 100, 100, .{ 0.0, 0.0, 1.0, 1.0 });
        renderer.drawRect(100, 100, 200, 50, .{ 1.0, 0.5, 0.0, 1.0 });
        renderer.drawRect(350, 100, 100, 100, .{ 0.2, 0.8, 0.3, 1.0 });
        renderer.end();

        // Swap buffers & poll events
        window.swapBuffers();
        glfw.pollEvents();
    }
}

fn ortho(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) [16]f32 {
    return [_]f32{
        2 / (right - left),               0,                                0,                            0,
        0,                                2 / (top - bottom),               0,                            0,
        0,                                0,                                -2 / (far - near),            0,
        -(right + left) / (right - left), -(top + bottom) / (top - bottom), -(far + near) / (far - near), 1,
    };
}
