const std = @import("std");

const glfw = @import("glfw.zig");
const glWrapper = @import("openGL.zig");
const gl = glWrapper.gl;
const font = @import("font.zig");

// Youâ€™ll import or declare OpenGL function pointers somewhere, e.g.:
var procs: gl.ProcTable = undefined;

fn errorCallback(errn: c_int, str: [*c]const u8) callconv(std.builtin.CallingConvention.c) void {
    std.log.err("GLFW Error: {d} - {s}\n", .{ errn, str });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) std.log.err("Failed to deinit gpa", .{});
    const alloc = gpa.allocator();

    _ = glfw.setErrorCallback(errorCallback);
    try glfw.init();
    defer glfw.deinit();

    glfw.defaultWindowHints();

    var window = try glfw.Window.init(1200, 1000, "2D UI Renderer", null, null);
    defer window.deinit();

    glfw.makeContextCurrent(window.handle);
    glfw.swapInterval(1);

    // Initialize OpenGL function table
    if (!procs.init(glfw.getProcAddress)) {
        return error.OpenGLLoadFailed;
    }
    gl.makeProcTableCurrent(&procs);
    defer gl.makeProcTableCurrent(null);

    try font.init(alloc);
    defer font.deinit();

    const program = try glWrapper.Program.init(@embedFile("vert.glsl"), @embedFile("frag.glsl"));
    defer program.deinit();

    // const uProjectionLoc = program.uniformLocation("uProjection");
    var renderer = try glWrapper.Renderer2D.init(program);

    // Main loop
    while (!window.shouldClose()) {
        const now = std.time.milliTimestamp();
        defer std.debug.print("Frame took {d}ms\n", .{std.time.milliTimestamp() - now});

        // const mouse_pos = window.mousePos();
        // std.debug.print("Mouse pos: {d}, {d}\n", .{ mouse_pos[0], mouse_pos[1] });

        // Clear screen
        gl.ClearColor(0.2, 0.3, 0.3, 1.0);
        gl.Clear(gl.COLOR_BUFFER_BIT);

        program.use();

        renderer.begin(window.bufferSize(), window.getContentScale());
        renderer.drawRect(5, 5, 200, 50, .{ 1.0, 0.5, 0.0, 1.0 });
        renderer.drawRect(0, 0, 100, 100, .{ 0.0, 0.0, 1.0, 0.2 });
        renderer.drawRect(100, 100, 200, 50, .{ 1.0, 0.5, 0.0, 1.0 });
        renderer.drawRoundedBorderRect(350, 100, 100, 100, 0, .{ 0.2, 0.8, 0.3, 1.0 }, 8, .{ 0.0, 0.0, 0.0, 1.0 });

        renderer.drawRoundedBorderRect(200, 300, 400, 300, 120, .{ 0.8, 0.2, 0.2, 1.0 }, 4, .{ 0, 0, 0, 1 });
        renderer.drawRoundedRect(1000, 0, 100, 100, 12, .{ 1.0, 0.0, 0.0, 1.0 });
        renderer.drawRoundedBorderRect(800, 400, 140, 100, 12, .{ 1.0, 1.0, 0.0, 0.8 }, 2, .{ 0.0, 0.0, 0.0, 1.0 });

        renderer.drawRect(95, 55, 800, 200, .{ 0.0, 0.0, 0.0, 1.0 });
        try renderer.drawText(font.geist_regular_48,
            \\Hällö, World!éáó
            \\Lorem ipsum dolor sit.
            \\Nullam euismod, nisl?
            \\NULLAM EUISMOD, NISL?
        , 100, 100, 32, .{ 1.0, 1.0, 1.0, 1.0 });
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
