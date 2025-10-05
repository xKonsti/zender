const std = @import("std");
pub const c = @cImport({
    @cDefine("GLFW_INCLUDE_NONE", "1");
    @cInclude("GLFW/glfw3.h");
});

pub const setErrorCallback = c.glfwSetErrorCallback;
pub const swapInterval = c.glfwSwapInterval;
pub const makeContextCurrent = c.glfwMakeContextCurrent;
pub const pollEvents = c.glfwPollEvents;
pub const getProcAddress = c.glfwGetProcAddress;

pub fn init() !void {
    if (c.glfwInit() != c.GLFW_TRUE) {
        return error.InitFailed;
    }
}
pub const deinit = c.glfwTerminate;

fn scrollCallback(win: ?*c.GLFWwindow, xoffset: f64, yoffset: f64) callconv(.c) void {
    _ = win;
    // accumulate deltas until read in the frame
    scroll_accum[0] += xoffset;
    scroll_accum[1] += yoffset;
}

var scroll_accum: [2]f64 = .{ 0, 0 };

pub fn defaultWindowHints() void {
    c.glfwDefaultWindowHints();
    // Set hints if you want a specific OpenGL version (optional)
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 4);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 1);
    c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);
    // On macOS, also:
    c.glfwWindowHint(c.GLFW_OPENGL_FORWARD_COMPAT, c.GLFW_TRUE);
}

pub const Window = struct {
    handle: *c.GLFWwindow,

    pub fn init(width: u32, height: u32, title: [:0]const u8, monitor: ?*c.GLFWmonitor, share: ?*c.GLFWwindow) !Window {
        const handle = c.glfwCreateWindow(@intCast(width), @intCast(height), title, monitor, share) orelse return error.WindowCreationFailed;
        _ = c.glfwSetScrollCallback(handle, scrollCallback);
        return .{
            .handle = handle,
        };
    }

    pub inline fn deinit(self: Window) void {
        c.glfwDestroyWindow(self.handle);
    }

    pub inline fn shouldClose(self: Window) bool {
        return c.glfwWindowShouldClose(self.handle) == c.GLFW_TRUE;
    }

    /// this is basically the window size with respect to the content scale
    pub inline fn bufferSize(self: Window) [2]u32 {
        var w: c_int = 0;
        var h: c_int = 0;
        // c.glfwGetWindowSize(self.handle, &w, &h);
        c.glfwGetFramebufferSize(self.handle, &w, &h);
        return .{ @intCast(w), @intCast(h) };
    }

    pub inline fn windowSize(self: Window) [2]u32 {
        var w: c_int = 0;
        var h: c_int = 0;
        c.glfwGetWindowSize(self.handle, &w, &h);
        return .{ @intCast(w), @intCast(h) };
    }

    pub inline fn swapBuffers(self: Window) void {
        c.glfwSwapBuffers(self.handle);
    }

    /// only important on macOS
    pub inline fn getContentScale(self: Window) [2]f32 {
        if (@import("builtin").os.tag != .macos) return .{ 1, 1 };

        var x: f32 = 0;
        var y: f32 = 0;
        c.glfwGetWindowContentScale(self.handle, &x, &y);
        return .{ x, y };
    }

    pub fn mousePos(self: Window) [2]f64 {
        var x: f64 = 0;
        var y: f64 = 0;
        c.glfwGetCursorPos(self.handle, &x, &y);
        return .{ x, y };
    }

    pub fn mouseScroll(self: Window) [2]f64 {
        _ = self;
        return scroll_accum; // raw (non-resetting) access if needed
    }

    /// Returns the accumulated scroll delta since last call and resets it to zero.
    pub fn takeMouseScrollDelta(self: Window) [2]f64 {
        _ = self;
        var d = scroll_accum;
        // Apply small deadzone to avoid tiny residual scroll and stop sharper
        const deadzone: f64 = 1.0;
        if (@abs(d[0]) < deadzone) d[0] = 0;
        if (@abs(d[1]) < deadzone) d[1] = 0;
        scroll_accum = .{ 0, 0 };
        return d;
    }

    const CursorIcons = enum(c_int) {
        Arrow = c.GLFW_ARROW_CURSOR,
        IBeam = c.GLFW_IBEAM_CURSOR,
        Crosshair = c.GLFW_CROSSHAIR_CURSOR,
        HResize = c.GLFW_HRESIZE_CURSOR,
        VResize = c.GLFW_VRESIZE_CURSOR,
        ResizeAll = c.GLFW_RESIZE_ALL_CURSOR,
        NotAllowed = c.GLFW_NOT_ALLOWED_CURSOR,
        PointingHand = c.GLFW_POINTING_HAND_CURSOR,
    };
};
