const c = @cImport({
    @cDefine("GLFW_INCLUDE_NONE", "1");
    @cInclude("GLFW/glfw3.h");
});

pub const setErrorCallback = c.glfwSetErrorCallback;
pub const swapInterval = c.glfwSwapInterval;
pub const makeContextCurrent = c.glfwMakeContextCurrent;
pub const pollEvents = c.glfwPollEvents;
pub const getProcAddress = c.glfwGetProcAddress;

const Dimensions = struct {
    w: u32,
    h: u32,
};

pub fn init() !void {
    if (c.glfwInit() != c.GLFW_TRUE) {
        return error.InitFailed;
    }
}
pub const deinit = c.glfwTerminate;

pub fn defaultWindowHints() void {
    c.glfwDefaultWindowHints();
    // Set hints if you want a specific OpenGL version (optional)
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 3);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 3);
    c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);
    // On macOS, also:
    c.glfwWindowHint(c.GLFW_OPENGL_FORWARD_COMPAT, c.GLFW_TRUE);
}

pub const Window = struct {
    handle: *c.GLFWwindow,

    pub fn init(width: u32, height: u32, title: [:0]const u8, monitor: ?*c.GLFWmonitor, share: ?*c.GLFWwindow) !Window {
        const handle = c.glfwCreateWindow(@intCast(width), @intCast(height), title, monitor, share) orelse return error.WindowCreationFailed;
        return Window{ .handle = handle };
    }

    pub fn deinit(self: *Window) void {
        c.glfwDestroyWindow(self.handle);
    }

    pub fn shouldClose(self: *Window) bool {
        return c.glfwWindowShouldClose(self.handle) == c.GLFW_TRUE;
    }

    pub fn windowSize(self: *Window) Dimensions {
        var w: c_int = 0;
        var h: c_int = 0;
        c.glfwGetWindowSize(self.handle, &w, &h);
        return Dimensions{ .w = @intCast(w), .h = @intCast(h) };
    }

    pub fn swapBuffers(self: *Window) void {
        c.glfwSwapBuffers(self.handle);
    }
};
