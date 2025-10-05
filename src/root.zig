const std = @import("std");
const assert = std.debug.assert;

// Import existing modules
const glfw_mod = @import("glfw.zig");
const opengl_mod = @import("openGL.zig");
const font_mod = @import("font.zig");
const rendering_mod = @import("rendering.zig");
const zlay = @import("zlayout");

// =============================================================================
// CORE INITIALIZATION & CONFIGURATION
// =============================================================================

pub var window: glfw_mod.Window = undefined;
var procs: opengl_mod.ProcTable = undefined;
var program: opengl_mod.Program = undefined;
var opengl_drawer: opengl_mod.Renderer2D = undefined;

pub const core = struct {
    /// Initialize the zender library
    /// Must be called before any other zender functions
    pub fn init(alloc: std.mem.Allocator, screen_dimensions: [2]u32, title: [:0]const u8) !void {
        try glfw_mod.init();
        errdefer glfw_mod.deinit();

        glfw_mod.defaultWindowHints();
        _ = glfw_mod.c.glfwSetErrorCallback(errorCallback);

        window = try glfw_mod.Window.init(screen_dimensions[0], screen_dimensions[1], title, null, null);
        errdefer window.deinit();

        glfw_mod.makeContextCurrent(window.handle);
        glfw_mod.swapInterval(1); // enable vsync

        if (!procs.init(glfw_mod.getProcAddress)) {
            return error.OpenGLLoadFailed;
        }
        opengl_mod.makeProcTableCurrent(&procs);
        errdefer opengl_mod.makeProcTableCurrent(null);

        program = try opengl_mod.Program.init(@embedFile("vert.glsl"), @embedFile("frag.glsl"));
        errdefer program.deinit();

        opengl_drawer = try .init(alloc, program);
        errdefer opengl_drawer.deinit();

        zlay.configure(.{
            .allocator = alloc,
            .measure_text = rendering_mod.measureText,
            .perf_info = false,
        });

        try font_mod.init(alloc);

        assert(window != undefined);
        assert(procs != undefined);
        assert(program != undefined);
        assert(opengl_drawer != undefined);
    }

    /// Clean up zender resources
    /// Should be called when shutting down
    pub fn deinit() void {
        font_mod.deinit();
        glfw_mod.deinit();
        window.?.deinit();
        opengl_mod.makeProcTableCurrent(null);
        program.deinit();
    }

    fn errorCallback(errn: c_int, str: [*c]const u8) callconv(.c) void {
        std.log.err("GLFW Error: {d} - {s}\n", .{ errn, str });
    }
};

// =============================================================================
// LAYOUTING
// =============================================================================

var prev_frame_time: i64 = std.time.milliTimestamp();
pub const layout = struct {
    pub fn startLayout() void {
        const now = std.time.milliTimestamp();
        const delta_ms = now - prev_frame_time;
        prev_frame_time = now;
        const delta_time = @as(f32, @floatFromInt(delta_ms)) / 1000;

        const window_size = window.windowSize();
        const mouse_pos = window.mousePos();
        const left_mouse_state = glfw_mod.c.glfwGetMouseButton(window.handle, glfw_mod.c.GLFW_MOUSE_BUTTON_LEFT);
        const scroll = window.takeMouseScrollDelta();
        zlay.startLayout(.{
            .is_down = left_mouse_state == glfw_mod.c.GLFW_PRESS,
            .x = @floatCast(mouse_pos[0]),
            .y = @floatCast(mouse_pos[1]),
        }, .{
            .delta = .{ .x = @floatCast(scroll[0]), .y = @floatCast(scroll[1]) },
            .delta_time = @floatCast(delta_time),
        }, .{
            .w = @floatFromInt(window_size[0]),
            .h = @floatFromInt(window_size[1]),
        });
    }

    pub fn endLayout() void {
        rendering_mod.draw(zlay.endLayout(), window);
    }
};
