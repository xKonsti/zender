//! minimal example:
//! ```zig
//! const std = @import("std");
//! const zen = @import("zender");
//! const zlay = zen.layout;
//!
//! pub fn main() !void {
//!     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//!     defer _ = gpa.deinit();
//!     const allocator = gpa.allocator();
//!
//!     try zen.core.init(allocator, .{ 1200, 800 }, "App title", .{});
//!     defer zen.core.deinit();
//!
//!     while (!zen.core.shouldClose()) {
//!         zen.core.beginFrame();
//!
//!         zlay.beginLayout();
//!         if (zlay.open(.{
//!             .sizing = .{ .full, .full },
//!             .bg_color = .light_100,
//!             .padding = .all(8),
//!             .layout = .flex(.{
//!                 .gap = 8,
//!                 .alignment = .center,
//!             }),
//!         })) {
//!             defer zlay.close();
//!
//!             zlay.text("Hello, world!", .{
//!                 .font_size = 46,
//!                 .text_color = .dark_300,
//!                 .font_style = .bold,
//!             });
//!         }
//!
//!
//!         zen.drawing.start();
//!         zen.drawing.drawLayout(zlay.endLayout());
//!         zen.drawing.end();
//!
//!         zen.core.endFrame();
//!     }
//! }
//! ```
//!
const std = @import("std");
const assert = std.debug.assert;

const zlay = @import("zlayout");

const font_mod = @import("font.zig");
const FontFamily = font_mod.FontFamily;
const FontStyle = font_mod.FontStyle;
const glfw_mod = @import("glfw.zig");
const Renderer2D = opengl_mod.Renderer2D;
const opengl_mod = @import("openGL.zig");
pub const Image = opengl_mod.ImageTexture;

const rgfw = @cImport({
    @cDefine("RGFW_IMPLEMENTATION", {});
    @cDefine("RGFW_OPENGL", {});
    @cInclude("RGFW.h");
});

// Import existing modules
// =============================================================================
// CORE INITIALIZATION & CONFIGURATION
// =============================================================================

pub var window: glfw_mod.Window = undefined;
var procs: opengl_mod.c.ProcTable = undefined;
var program: opengl_mod.Program = undefined;
var renderer2D: opengl_mod.Renderer2D = undefined;

const Config = struct {
    print_perf: bool = false,
};

pub const core = struct {
    /// Initialize the zender library
    /// Must be called before any other zender functions
    pub fn init(alloc: std.mem.Allocator, screen_dimensions: [2]u32, title: [:0]const u8, cfg: Config) !void {
        try glfw_mod.init();
        errdefer glfw_mod.deinit();

        glfw_mod.defaultWindowHints();
        _ = glfw_mod.c.glfwSetErrorCallback(errorCallback);

        window = try glfw_mod.Window.init(screen_dimensions[0], screen_dimensions[1], title, null, null);
        errdefer window.deinit();

        // Set up input callbacks
        _ = glfw_mod.c.glfwSetKeyCallback(window.handle, keyCallback);
        _ = glfw_mod.c.glfwSetCharCallback(window.handle, charCallback);
        _ = glfw_mod.c.glfwSetMouseButtonCallback(window.handle, mouseButtonCallback);

        glfw_mod.makeContextCurrent(window.handle);
        glfw_mod.swapInterval(1); // enable vsync

        if (!procs.init(glfw_mod.getProcAddress)) {
            return error.OpenGLLoadFailed;
        }
        opengl_mod.c.makeProcTableCurrent(&procs);
        errdefer opengl_mod.c.makeProcTableCurrent(null);

        program = try opengl_mod.Program.init(@embedFile("vert.glsl"), @embedFile("frag.glsl"));
        errdefer program.deinit();

        renderer2D = try .init(alloc, program);
        errdefer renderer2D.deinit();

        zlay.init(.{
            .allocator = alloc,
            .measure_text = measureText,
            .print_perf = cfg.print_perf,
        });

        try font_mod.init(alloc);
        try font_mod.preloadCommon(alloc);
    }

    /// Clean up zender resources
    /// Should be called when shutting down
    pub fn deinit() void {
        font_mod.deinit();
        deinitStandardCursors();
        glfw_mod.deinit();
        window.deinit();
        opengl_mod.c.makeProcTableCurrent(null);
        program.deinit();
    }

    /// Check if the window should close
    /// usage:
    /// ```zig
    /// while (!zender.core.shouldClose()) {
    ///     ... frame rendering
    /// }
    /// ```
    pub inline fn shouldClose() bool {
        return glfw_mod.c.glfwWindowShouldClose(window.handle) == glfw_mod.c.GLFW_TRUE;
    }

    pub fn beginFrame() void {
        // Clear input queues from previous frame first
        char_input_queue_count = 0;
        key_pressed_queue_count = 0;
        mouse_button_pressed_queue_count = 0;

        // Then poll events to fill the queues for this frame
        glfw_mod.pollEvents();

        opengl_mod.c.ClearColor(0.2, 0.3, 0.3, 1);
        opengl_mod.c.Clear(opengl_mod.c.COLOR_BUFFER_BIT);
    }

    pub fn endFrame() void {
        window.swapBuffers();
    }

    fn errorCallback(errn: c_int, str: [*c]const u8) callconv(.c) void {
        std.log.err("GLFW Error: {d} - {s}\n", .{ errn, str });
    }
};

// =============================================================================
// Layout
// =============================================================================

var prev_frame_time: i64 = 0;
pub const layout = struct {
    pub fn beginLayout() void {
        const now = std.time.milliTimestamp();
        const delta_ms = now - prev_frame_time;
        prev_frame_time = now;
        const delta_time = @as(f32, @floatFromInt(delta_ms)) / 1000;

        const window_size = window.windowSize();
        const mouse_pos = window.mousePos();
        const left_mouse_state = glfw_mod.c.glfwGetMouseButton(window.handle, glfw_mod.c.GLFW_MOUSE_BUTTON_LEFT);
        const scroll = window.takeMouseScrollDelta();
        zlay.startLayout(.{
            .pos = .{ @floatCast(mouse_pos[0]), @floatCast(mouse_pos[1]) },
            .is_down = left_mouse_state == glfw_mod.c.GLFW_PRESS,
        }, .{
            .delta = .{ @floatCast(scroll[0]), @floatCast(scroll[1]) },
            .delta_time = @floatCast(delta_time),
        }, .{
            @floatFromInt(window_size[0]),
            @floatFromInt(window_size[1]),
        });
    }

    /// returns the draw commands
    ///
    /// usage:
    /// ```zig
    /// drawing.drawLayout(layout.endLayout());
    /// ```
    pub fn endLayout() []zlay.DrawCommand {
        return zlay.endLayout();
    }

    // FNs
    pub const open = zlay.open;
    pub const close = zlay.close;
    pub const text = zlay.text;
    pub const image = zlay.image;
    pub const hovered = zlay.hovered;

    // Types
    pub const Border = zlay.Border;
};

// =============================================================================
// Drawing
// =============================================================================

pub const drawing = struct {
    /// fires up the openGL shaders and uploads uniforms
    pub fn start() void {
        program.use();
        renderer2D.begin(window.windowSize(), window.getContentScale());
    }

    /// flushes remaining draw calls for the frame
    pub fn end() void {
        renderer2D.end();
    }

    /// interop for drawing layout commands from the layout module
    pub fn drawLayout(cmds: []const zlay.DrawCommand) void {
        // const window_h = @as(f32, @floatFromInt(window.windowSize()[1]));
        const scale = window.getContentScale();
        for (cmds) |cmd| {
            switch (cmd) {
                .clipStart => |clip| {
                    if (renderer2D.rect_count > 0) {
                        renderer2D.flush();
                    }

                    const bottom_left_y = @as(f32, @floatFromInt(window.windowSize()[1])) - clip.rect[3] - clip.rect[1];
                    const rect: [4]f32 = .{
                        clip.rect[0] * scale[0],
                        bottom_left_y * scale[1],
                        clip.rect[2] * scale[0],
                        clip.rect[3] * scale[1],
                    };
                    // _ = rect;
                    opengl_mod.clipStart(rect);
                },
                .clipEnd => {
                    renderer2D.flush();
                    opengl_mod.clipEnd();
                },
                .drawRect => |rect_cmd| {
                    const rect = rect_cmd.rect_on_screen;
                    const color: [4]u8 = .{
                        rect_cmd.color.r,
                        rect_cmd.color.g,
                        rect_cmd.color.b,
                        rect_cmd.color.a,
                    };
                    const border_widths: [4]f32 =
                        if (rect_cmd.border) |border|
                            .{
                                @floatFromInt(border.l),
                                @floatFromInt(border.r),
                                @floatFromInt(border.t),
                                @floatFromInt(border.b),
                            }
                        else
                            .{0} ** 4;

                    const border_color: [4]u8 =
                        if (rect_cmd.border) |border|
                            .{
                                border.color.r,
                                border.color.g,
                                border.color.b,
                                border.color.a,
                            }
                        else
                            .{0} ** 4;
                    // if (border_widths[3] == 4) {
                    //     std.log.err("border_widths[3] == 4", .{});
                    //     std.log.err("The width is {d} {d} {d} {d}", .{ border_widths[0], border_widths[1], border_widths[2], border_widths[3] });
                    //     std.log.err("And the color is {d} {d} {d} {d}", .{ border_color[0], border_color[1], border_color[2], border_color[3] });
                    // }
                    renderer2D.drawRect(
                        rect[0],
                        rect[1],
                        rect[2],
                        rect[3],
                        .{
                            .corner_radius = .{
                                @floatFromInt(rect_cmd.corner_radius.tl),
                                @floatFromInt(rect_cmd.corner_radius.tr),
                                @floatFromInt(rect_cmd.corner_radius.br),
                                @floatFromInt(rect_cmd.corner_radius.bl),
                            },
                            .color = color,
                            .border_width = border_widths,
                            .border_color = border_color,
                        },
                    );
                },
                .drawText => |text_cmd| {
                    const text_config = text_cmd.text_config;
                    const rect = text_cmd.rect_on_screen;

                    const style: font_mod.FontStyle = switch (text_config.font_style) {
                        .light => .light,
                        .regular => .regular,
                        .medium => .medium,
                        .semibold => .semibold,
                        .bold => .bold,
                        .black => .black,
                    };
                    const text_color: [4]u8 = .{
                        text_config.text_color.r,
                        text_config.text_color.g,
                        text_config.text_color.b,
                        text_config.text_color.a,
                    };
                    const text = text_cmd.text;

                    renderer2D.drawText(
                        window.getContentScale(),
                        font_mod.FontFamily.geist,
                        text,
                        rect[0],
                        rect[1],
                        @as(f32, @floatFromInt(text_config.font_size)),
                        style,
                        text_color,
                    ) catch |err| {
                        std.log.err("Failed to draw text: {s}", .{@errorName(err)});
                    };
                },
                .drawImage => |img_cmd| {
                    const image: *const anyopaque = img_cmd.data;
                    // const dims: [2]f32 = img_cmd.dimensions;
                    const rect: [4]f32 = img_cmd.rect_on_screen;

                    // Cast the opaque pointer back to ImageTexture
                    const image_texture: *const opengl_mod.ImageTexture = @ptrCast(@alignCast(image));

                    // Call drawImage with the rect coordinates
                    renderer2D.drawImage(
                        image_texture.*,
                        rect[0], // x
                        rect[1], // y
                        rect[2], // width
                        rect[3], // height
                        .{ 255, 255, 255, 255 }, // white tint (no color change)
                    );
                },
            }
        }
    }

    const Color = [4]u8;

    pub fn drawRect(x: f32, y: f32, w: f32, h: f32, config: Renderer2D.RectConfig) void {
        renderer2D.drawRect(x, y, w, h, config);
    }

    pub fn drawLine(p1: [2]f32, p2: [2]f32, config: Renderer2D.LineConfig) void {
        renderer2D.drawLine(p1, p2, config);
    }

    pub fn drawLines(points: []const [2]f32, config: Renderer2D.LineConfig) void {
        for (points, 0..) |p, i| {
            if (i == 0) {
                drawLine(p, points[1], config);
            } else {
                drawLine(points[i - 1], p, config);
            }
        }
    }

    pub fn drawText(window_scale: [2]f32, font_collection: FontFamily, text: []const u8, x: f32, y: f32, size: f32, style: FontStyle, text_color: Color) void {
        renderer2D.drawText(window_scale, font_collection, text, x, y, size, style, text_color);
    }

    pub fn drawImage(image: *const anyopaque, x: f32, y: f32, w: f32, h: f32, tint: Color) void {
        renderer2D.drawImage(image, x, y, w, h, tint);
    }
};

// =============================================================================
// Image
// =============================================================================
// =============================================================================
// IO (i.e. Keyboard, Mouse, ...)
// =============================================================================
// Unicode character input queue (reject when full)
const MAX_CHAR_QUEUE = 32;
var char_input_queue: [MAX_CHAR_QUEUE]u21 = [_]u21{0} ** MAX_CHAR_QUEUE;
var char_input_queue_count: usize = 0;

// Key press queue for non-character keys (arrows, function keys, etc.)
const MAX_KEY_QUEUE = 16;
var key_pressed_queue: [MAX_KEY_QUEUE]c_int = [_]c_int{0} ** MAX_KEY_QUEUE;
var key_pressed_queue_count: usize = 0;

// Mouse button press queue for single-frame press events
const MAX_MOUSE_QUEUE = 8;
var mouse_button_pressed_queue: [MAX_MOUSE_QUEUE]c_int = [_]c_int{0} ** MAX_MOUSE_QUEUE;
var mouse_button_pressed_queue_count: usize = 0;

fn charCallback(win: ?*glfw_mod.c.GLFWwindow, codepoint: c_uint) callconv(.c) void {
    _ = win;

    // Early return if queue is full
    if (char_input_queue_count >= MAX_CHAR_QUEUE) return;

    // Add character to queue
    char_input_queue[char_input_queue_count] = @intCast(codepoint);
    char_input_queue_count += 1;
}

fn keyCallback(win: ?*glfw_mod.c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.c) void {
    _ = win;
    _ = scancode;
    _ = mods;

    // Only queue non-printable/special keys
    if (action == glfw_mod.c.GLFW_PRESS and key_pressed_queue_count < MAX_KEY_QUEUE) {
        switch (key) {
            glfw_mod.c.GLFW_KEY_ESCAPE, glfw_mod.c.GLFW_KEY_ENTER, glfw_mod.c.GLFW_KEY_TAB, glfw_mod.c.GLFW_KEY_BACKSPACE, glfw_mod.c.GLFW_KEY_DELETE, glfw_mod.c.GLFW_KEY_LEFT, glfw_mod.c.GLFW_KEY_RIGHT, glfw_mod.c.GLFW_KEY_UP, glfw_mod.c.GLFW_KEY_DOWN, glfw_mod.c.GLFW_KEY_F1...glfw_mod.c.GLFW_KEY_F12 => {
                key_pressed_queue[key_pressed_queue_count] = key;
                key_pressed_queue_count += 1;
            },
            else => {}, // Printable characters handled by charCallback
        }
    }
}

fn mouseButtonCallback(win: ?*glfw_mod.c.GLFWwindow, button: c_int, action: c_int, mods: c_int) callconv(.c) void {
    _ = win;
    _ = mods;

    // Only queue on press event
    if (action == glfw_mod.c.GLFW_PRESS and mouse_button_pressed_queue_count < MAX_MOUSE_QUEUE) {
        mouse_button_pressed_queue[mouse_button_pressed_queue_count] = button;
        mouse_button_pressed_queue_count += 1;
    }
}

var standard_cursors: [8]?*glfw_mod.c.GLFWcursor = [_]?*glfw_mod.c.GLFWcursor{null} ** 8;
var cursors_initialized: bool = false;

fn initStandardCursors() void {
    if (cursors_initialized) return;

    const cursor_types = [_]c_int{
        glfw_mod.c.GLFW_ARROW_CURSOR,
        glfw_mod.c.GLFW_IBEAM_CURSOR,
        glfw_mod.c.GLFW_CROSSHAIR_CURSOR,
        glfw_mod.c.GLFW_HRESIZE_CURSOR,
        glfw_mod.c.GLFW_VRESIZE_CURSOR,
        glfw_mod.c.GLFW_RESIZE_ALL_CURSOR,
        glfw_mod.c.GLFW_NOT_ALLOWED_CURSOR,
        glfw_mod.c.GLFW_POINTING_HAND_CURSOR,
    };

    for (cursor_types, 0..) |cursor_type, i| {
        standard_cursors[i] = glfw_mod.c.glfwCreateStandardCursor(cursor_type);
    }

    cursors_initialized = true;
}

fn deinitStandardCursors() void {
    if (!cursors_initialized) return;

    for (standard_cursors) |cursor| {
        if (cursor) |c_cursor| {
            glfw_mod.c.glfwDestroyCursor(c_cursor);
        }
    }

    standard_cursors = [_]?*glfw_mod.c.GLFWcursor{null} ** 8;
    cursors_initialized = false;
}

pub const io = struct {
    pub const CursorIcon = enum(c_int) {
        Arrow = glfw_mod.c.GLFW_ARROW_CURSOR,
        IBeam = glfw_mod.c.GLFW_IBEAM_CURSOR,
        Crosshair = glfw_mod.c.GLFW_CROSSHAIR_CURSOR,
        HResize = glfw_mod.c.GLFW_HRESIZE_CURSOR,
        VResize = glfw_mod.c.GLFW_VRESIZE_CURSOR,
        ResizeAll = glfw_mod.c.GLFW_RESIZE_ALL_CURSOR,
        NotAllowed = glfw_mod.c.GLFW_NOT_ALLOWED_CURSOR,
        PointingHand = glfw_mod.c.GLFW_POINTING_HAND_CURSOR,
    };
    pub const Key = enum(c_int) {
        // Letters (for key state polling)
        A = glfw_mod.c.GLFW_KEY_A,
        B = glfw_mod.c.GLFW_KEY_B,
        C = glfw_mod.c.GLFW_KEY_C,
        D = glfw_mod.c.GLFW_KEY_D,
        E = glfw_mod.c.GLFW_KEY_E,
        F = glfw_mod.c.GLFW_KEY_F,
        G = glfw_mod.c.GLFW_KEY_G,
        H = glfw_mod.c.GLFW_KEY_H,
        I = glfw_mod.c.GLFW_KEY_I,
        J = glfw_mod.c.GLFW_KEY_J,
        K = glfw_mod.c.GLFW_KEY_K,
        L = glfw_mod.c.GLFW_KEY_L,
        M = glfw_mod.c.GLFW_KEY_M,
        N = glfw_mod.c.GLFW_KEY_N,
        O = glfw_mod.c.GLFW_KEY_O,
        P = glfw_mod.c.GLFW_KEY_P,
        Q = glfw_mod.c.GLFW_KEY_Q,
        R = glfw_mod.c.GLFW_KEY_R,
        S = glfw_mod.c.GLFW_KEY_S,
        T = glfw_mod.c.GLFW_KEY_T,
        U = glfw_mod.c.GLFW_KEY_U,
        V = glfw_mod.c.GLFW_KEY_V,
        W = glfw_mod.c.GLFW_KEY_W,
        X = glfw_mod.c.GLFW_KEY_X,
        Y = glfw_mod.c.GLFW_KEY_Y,
        Z = glfw_mod.c.GLFW_KEY_Z,

        // Numbers
        KEY_0 = glfw_mod.c.GLFW_KEY_0,
        KEY_1 = glfw_mod.c.GLFW_KEY_1,
        KEY_2 = glfw_mod.c.GLFW_KEY_2,
        KEY_3 = glfw_mod.c.GLFW_KEY_3,
        KEY_4 = glfw_mod.c.GLFW_KEY_4,
        KEY_5 = glfw_mod.c.GLFW_KEY_5,
        KEY_6 = glfw_mod.c.GLFW_KEY_6,
        KEY_7 = glfw_mod.c.GLFW_KEY_7,
        KEY_8 = glfw_mod.c.GLFW_KEY_8,
        KEY_9 = glfw_mod.c.GLFW_KEY_9,

        // Special keys
        SPACE = glfw_mod.c.GLFW_KEY_SPACE,

        // Control keys
        ESCAPE = glfw_mod.c.GLFW_KEY_ESCAPE,
        ENTER = glfw_mod.c.GLFW_KEY_ENTER,
        TAB = glfw_mod.c.GLFW_KEY_TAB,
        BACKSPACE = glfw_mod.c.GLFW_KEY_BACKSPACE,
        DELETE = glfw_mod.c.GLFW_KEY_DELETE,

        // Arrow keys
        RIGHT = glfw_mod.c.GLFW_KEY_RIGHT,
        LEFT = glfw_mod.c.GLFW_KEY_LEFT,
        DOWN = glfw_mod.c.GLFW_KEY_DOWN,
        UP = glfw_mod.c.GLFW_KEY_UP,

        // Modifier keys
        LEFT_SHIFT = glfw_mod.c.GLFW_KEY_LEFT_SHIFT,
        RIGHT_SHIFT = glfw_mod.c.GLFW_KEY_RIGHT_SHIFT,
        LEFT_CONTROL = glfw_mod.c.GLFW_KEY_LEFT_CONTROL,
        RIGHT_CONTROL = glfw_mod.c.GLFW_KEY_RIGHT_CONTROL,

        // Function keys
        F1 = glfw_mod.c.GLFW_KEY_F1,
        F2 = glfw_mod.c.GLFW_KEY_F2,
        F3 = glfw_mod.c.GLFW_KEY_F3,
        F4 = glfw_mod.c.GLFW_KEY_F4,
        F5 = glfw_mod.c.GLFW_KEY_F5,
        F6 = glfw_mod.c.GLFW_KEY_F6,
        F7 = glfw_mod.c.GLFW_KEY_F7,
        F8 = glfw_mod.c.GLFW_KEY_F8,
        F9 = glfw_mod.c.GLFW_KEY_F9,
        F10 = glfw_mod.c.GLFW_KEY_F10,
        F11 = glfw_mod.c.GLFW_KEY_F11,
        F12 = glfw_mod.c.GLFW_KEY_F12,
    };

    pub const SpecialKey = enum(c_int) {
        ESCAPE = glfw_mod.c.GLFW_KEY_ESCAPE,
        ENTER = glfw_mod.c.GLFW_KEY_ENTER,
        TAB = glfw_mod.c.GLFW_KEY_TAB,
        BACKSPACE = glfw_mod.c.GLFW_KEY_BACKSPACE,
        DELETE = glfw_mod.c.GLFW_KEY_DELETE,
        LEFT = glfw_mod.c.GLFW_KEY_LEFT,
        RIGHT = glfw_mod.c.GLFW_KEY_RIGHT,
        UP = glfw_mod.c.GLFW_KEY_UP,
        DOWN = glfw_mod.c.GLFW_KEY_DOWN,
        F1 = glfw_mod.c.GLFW_KEY_F1,
        F2 = glfw_mod.c.GLFW_KEY_F2,
        F3 = glfw_mod.c.GLFW_KEY_F3,
        F4 = glfw_mod.c.GLFW_KEY_F4,
        F5 = glfw_mod.c.GLFW_KEY_F5,
        F6 = glfw_mod.c.GLFW_KEY_F6,
        F7 = glfw_mod.c.GLFW_KEY_F7,
        F8 = glfw_mod.c.GLFW_KEY_F8,
        F9 = glfw_mod.c.GLFW_KEY_F9,
        F10 = glfw_mod.c.GLFW_KEY_F10,
        F11 = glfw_mod.c.GLFW_KEY_F11,
        F12 = glfw_mod.c.GLFW_KEY_F12,
    };

    pub fn isKeyDown(key: Key) bool {
        const state = glfw_mod.c.glfwGetKey(window.handle, @intFromEnum(key));
        return state == glfw_mod.c.GLFW_PRESS or state == glfw_mod.c.GLFW_REPEAT;
    }

    pub fn isKeyPressed(key: Key) bool {
        const state = glfw_mod.c.glfwGetKey(window.handle, @intFromEnum(key));
        return state == glfw_mod.c.GLFW_PRESS;
    }

    pub fn getMousePosition() [2]f64 {
        return window.mousePos();
    }

    pub fn getMouseScrollDelta() [2]f64 {
        return window.takeMouseScrollDelta();
    }

    pub const MouseButton = enum(c_int) {
        LEFT = glfw_mod.c.GLFW_MOUSE_BUTTON_LEFT,
        RIGHT = glfw_mod.c.GLFW_MOUSE_BUTTON_RIGHT,
        MIDDLE = glfw_mod.c.GLFW_MOUSE_BUTTON_MIDDLE,
    };

    pub fn isMouseButtonDown(button: MouseButton) bool {
        const state = glfw_mod.c.glfwGetMouseButton(window.handle, @intFromEnum(button));
        return state == glfw_mod.c.GLFW_PRESS;
    }

    /// Check if a mouse button was pressed this frame (single-frame event)
    pub fn isMouseButtonPressed(button: MouseButton) bool {
        const button_code = @intFromEnum(button);

        for (mouse_button_pressed_queue[0..mouse_button_pressed_queue_count]) |pressed_button| {
            if (pressed_button == button_code)
                return true;
        }
        return false;
    }

    /// Get the next Unicode character from input queue, returns null if empty
    pub fn getCharPressed() ?u21 {
        if (char_input_queue_count == 0) return null;

        // Get first character
        const char = char_input_queue[0];

        // Shift remaining characters left
        var i: usize = 0;
        while (i < char_input_queue_count - 1) : (i += 1) {
            char_input_queue[i] = char_input_queue[i + 1];
        }
        char_input_queue_count -= 1;

        return char;
    }

    /// Get next special key press (non-printable keys like arrows, function keys, etc.)
    pub fn getSpecialKeyPressed() ?SpecialKey {
        if (key_pressed_queue_count == 0) return null;

        // Get first key from queue
        const glfw_key = key_pressed_queue[0];

        // Shift remaining keys down
        var i: usize = 0;
        while (i < key_pressed_queue_count - 1) : (i += 1) {
            key_pressed_queue[i] = key_pressed_queue[i + 1];
        }
        key_pressed_queue_count -= 1;

        // Convert GLFW key code to SpecialKey enum
        return switch (glfw_key) {
            glfw_mod.c.GLFW_KEY_ESCAPE => .ESCAPE,
            glfw_mod.c.GLFW_KEY_ENTER => .ENTER,
            glfw_mod.c.GLFW_KEY_TAB => .TAB,
            glfw_mod.c.GLFW_KEY_BACKSPACE => .BACKSPACE,
            glfw_mod.c.GLFW_KEY_DELETE => .DELETE,
            glfw_mod.c.GLFW_KEY_LEFT => .LEFT,
            glfw_mod.c.GLFW_KEY_RIGHT => .RIGHT,
            glfw_mod.c.GLFW_KEY_UP => .UP,
            glfw_mod.c.GLFW_KEY_DOWN => .DOWN,
            glfw_mod.c.GLFW_KEY_F1 => .F1,
            glfw_mod.c.GLFW_KEY_F2 => .F2,
            glfw_mod.c.GLFW_KEY_F3 => .F3,
            glfw_mod.c.GLFW_KEY_F4 => .F4,
            glfw_mod.c.GLFW_KEY_F5 => .F5,
            glfw_mod.c.GLFW_KEY_F6 => .F6,
            glfw_mod.c.GLFW_KEY_F7 => .F7,
            glfw_mod.c.GLFW_KEY_F8 => .F8,
            glfw_mod.c.GLFW_KEY_F9 => .F9,
            glfw_mod.c.GLFW_KEY_F10 => .F10,
            glfw_mod.c.GLFW_KEY_F11 => .F11,
            glfw_mod.c.GLFW_KEY_F12 => .F12,
            else => null,
        };
    }

    // Static buffer to return UTF-8 bytes as slice
    var utf8_buffer: [4]u8 = undefined;

    /// Get next Unicode character as UTF-8 bytes
    /// Returns null if no character, or []u8 slice with the UTF-8 bytes
    pub fn getCharPressedAsUtf8() ?[]u8 {
        const unicode_char = getCharPressed() orelse return null;

        const len = std.unicode.utf8Encode(unicode_char, &utf8_buffer) catch {
            // Invalid codepoint, return replacement character (�)
            utf8_buffer[0] = 0xEF;
            utf8_buffer[1] = 0xBF;
            utf8_buffer[2] = 0xBD;
            return utf8_buffer[0..3];
        };

        return utf8_buffer[0..len];
    }

    /// Set the mouse cursor to a specific icon
    pub fn setCursor(cursor_icon: CursorIcon) void {
        initStandardCursors();

        const cursor_index: usize = switch (cursor_icon) {
            .Arrow => 0,
            .IBeam => 1,
            .Crosshair => 2,
            .HResize => 3,
            .VResize => 4,
            .ResizeAll => 5,
            .NotAllowed => 6,
            .PointingHand => 7,
        };

        if (standard_cursors[cursor_index]) |cursor| {
            glfw_mod.c.glfwSetCursor(window.handle, cursor);
        }
    }

    /// Reset the mouse cursor to the default arrow cursor
    pub fn setDefaultCursor() void {
        glfw_mod.c.glfwSetCursor(window.handle, null);
    }
};

// =============================================================================
// MISC & NO PROPER PLACE FOUND YET
// =============================================================================
pub fn measureText(text: []const u8, config: zlay.TextProps) zlay.Pair {
    if (text.len == 0) return .{ 0, 0 };

    // Convert external FontStyle to internal FontStyle
    const style: FontStyle = switch (config.font_style) {
        .light => .light,
        .regular => .regular,
        .medium => .medium,
        .semibold => .semibold,
        .bold => .bold,
        .black => .black,
    };

    const size: f32 = @floatFromInt(config.font_size);

    // font_id currently only supports default (geist)
    if (config.font_id != 0) {
        std.log.warn("font_id != 0 not supported yet, defaulting to geist", .{});
    }

    const font_obj = font_mod.getFont(.geist, style, size) catch |err| {
        std.log.err("Failed to get font: {s}", .{@errorName(err)});
        return .{ 0, 0 };
    };

    // Scale factor between atlas rasterization and requested size
    const scale = size / font_obj.pixel_height;

    // Get line metrics from FreeType (in 26.6 fixed-point)
    const line_advance_px = @as(f32, @floatFromInt(font_obj.ft_face.*.size.*.metrics.height)) / 64.0;

    // Shape text using HarfBuzz
    const glyphs = font_obj.shapeText(text) catch |err| {
        std.log.err("Shape text failed: {s}", .{@errorName(err)});
        return .{ 0, 0 };
    };
    defer font_obj.deinitShapedText(glyphs);

    var cursor_x: f32 = 0.0;
    var max_line_width: f32 = 0.0;
    var line_count: usize = 1;
    var glyph_count_in_line: usize = 0;

    const letter_spacing_px: f32 = @as(f32, @floatFromInt(config.letter_spacing)) * scale;

    // Process each shaped glyph
    for (glyphs) |g| {
        // Check for newline
        if (g.cluster < text.len and text[g.cluster] == '\n') {
            // Record this line's width before resetting
            if (cursor_x > max_line_width) {
                max_line_width = cursor_x;
            }
            cursor_x = 0.0;
            line_count += 1;
            glyph_count_in_line = 0;
            continue;
        }

        // Add letter spacing before this glyph (except for first glyph in line)
        if (glyph_count_in_line > 0) {
            cursor_x += letter_spacing_px;
        }

        // Advance cursor by this glyph's advance
        cursor_x += g.x_advance * scale;
        glyph_count_in_line += 1;
    }

    // Don't forget the last line
    if (cursor_x > max_line_width) {
        max_line_width = cursor_x;
    }

    // Calculate total height
    const total_height: f32 = @as(f32, @floatFromInt(line_count)) * line_advance_px * scale;

    return .{ @ceil(max_line_width), @ceil(total_height) };
}
