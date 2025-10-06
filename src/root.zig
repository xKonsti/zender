const std = @import("std");
const assert = std.debug.assert;

const zlay = @import("zlayout");

const font_mod = @import("font.zig");
const FontCollection = font_mod.FontCollection;
const FontStyle = font_mod.FontStyle;
const glfw_mod = @import("glfw.zig");
const opengl_mod = @import("openGL.zig");

// Import existing modules
// =============================================================================
// CORE INITIALIZATION & CONFIGURATION
// =============================================================================

pub var window: glfw_mod.Window = undefined;
var procs: opengl_mod.c.ProcTable = undefined;
var program: opengl_mod.Program = undefined;
var renderer2D: opengl_mod.Renderer2D = undefined;

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

        // Set up key callback
        _ = glfw_mod.c.glfwSetKeyCallback(window.handle, keyCallback);

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

        zlay.configure(.{
            .allocator = alloc,
            .measure_text = measureText,
            .perf_info = false,
        });

        try font_mod.init(alloc);
    }

    /// Clean up zender resources
    /// Should be called when shutting down
    pub fn deinit() void {
        font_mod.deinit();
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

    pub fn startFrame() void {
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

    /// returns the draw commands
    ///
    /// usage:
    /// ```zig
    /// drawing.drawLayout(layout.endLayout());
    /// ```
    pub fn endLayout() []zlay.DrawCommand {
        return zlay.endLayout();
    }

    pub const open = zlay.open;
    pub const close = zlay.close;
    pub const text = zlay.text;
    pub const hovered = zlay.hovered;
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
                    renderer2D.flush();
                    const rect: [4]f32 = .{
                        clip.rect.x * scale[0],
                        clip.rect.y * scale[1],
                        clip.rect.width * scale[0],
                        clip.rect.height * scale[1],
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
                    renderer2D.drawRoundedBorderRect(
                        rect.x,
                        rect.y,
                        rect.width,
                        rect.height,
                        @floatFromInt(rect_cmd.corner_radius.top_left),
                        color,
                        border_widths,
                        border_color,
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
                        font_mod.font_collection_geist,
                        text,
                        rect.x,
                        rect.y,
                        @floatFromInt(text_config.font_size),
                        style,
                        text_color,
                    ) catch |err| {
                        std.log.err("Failed to draw text: {s}", .{@errorName(err)});
                    };
                },
                .drawImage => |_| {
                    @panic("TODO");
                },
            }
        }
    }

    const Color = [4]u8;

    pub fn drawRect(
        tl_x: f32,
        tl_y: f32,
        width: f32,
        height: f32,
        fill_color: Color,
    ) void {
        renderer2D.drawRect(tl_x, tl_y, width, height, fill_color);
    }

    pub fn drawRoundedRect(
        tl_x: f32,
        tl_y: f32,
        width: f32,
        height: f32,
        corner_radius: f32,
        fill_color: Color,
    ) void {
        renderer2D.drawRoundedRect(tl_x, tl_y, width, height, corner_radius, fill_color);
    }

    pub fn drawRoundedBorderRect(
        tl_x: f32,
        tl_y: f32,
        width: f32,
        height: f32,
        corner_radius: f32,
        fill_color: Color,
        border_width: f32,
        border_color: Color,
    ) void {
        renderer2D.drawRoundedBorderRect(tl_x, tl_y, width, height, corner_radius, border_width, border_color, fill_color);
    }

    pub fn drawText(
        font_collection: FontCollection,
        text: []const u8,
        tl_x: f32,
        tl_y: f32,
        pixel_height: f32,
        style: FontStyle,
        text_color: Color,
    ) void {
        renderer2D.drawText(font_collection, text, tl_x, tl_y, pixel_height, style, text_color) catch |err| {
            std.log.err("Failed to draw text: {}", .{err});
        };
    }
};

// =============================================================================
// IO (i.e. Keyboard, Mouse, ...)
// =============================================================================
// Key queue system for proper input handling
const MAX_KEY_QUEUE = 16;
var key_pressed_queue: [MAX_KEY_QUEUE]c_int = [_]c_int{0} ** MAX_KEY_QUEUE;
var key_pressed_queue_count: usize = 0;

fn keyCallback(win: ?*glfw_mod.c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.c) void {
    _ = win;
    _ = scancode;
    _ = mods;

    if (action == glfw_mod.c.GLFW_PRESS and key_pressed_queue_count < MAX_KEY_QUEUE) {
        key_pressed_queue[key_pressed_queue_count] = key;
        key_pressed_queue_count += 1;
    }
}
pub const io = struct {
    pub const ASCIIKEY = enum(i32) {
        // Letters
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
        APOSTROPHE = glfw_mod.c.GLFW_KEY_APOSTROPHE,
        COMMA = glfw_mod.c.GLFW_KEY_COMMA,
        MINUS = glfw_mod.c.GLFW_KEY_MINUS,
        PERIOD = glfw_mod.c.GLFW_KEY_PERIOD,
        SLASH = glfw_mod.c.GLFW_KEY_SLASH,
        SEMICOLON = glfw_mod.c.GLFW_KEY_SEMICOLON,
        EQUAL = glfw_mod.c.GLFW_KEY_EQUAL,
        LEFT_BRACKET = glfw_mod.c.GLFW_KEY_LEFT_BRACKET,
        BACKSLASH = glfw_mod.c.GLFW_KEY_BACKSLASH,
        RIGHT_BRACKET = glfw_mod.c.GLFW_KEY_RIGHT_BRACKET,
        GRAVE_ACCENT = glfw_mod.c.GLFW_KEY_GRAVE_ACCENT,

        // Function keys
        ESCAPE = glfw_mod.c.GLFW_KEY_ESCAPE,
        ENTER = glfw_mod.c.GLFW_KEY_ENTER,
        TAB = glfw_mod.c.GLFW_KEY_TAB,
        BACKSPACE = glfw_mod.c.GLFW_KEY_BACKSPACE,
        INSERT = glfw_mod.c.GLFW_KEY_INSERT,
        DELETE = glfw_mod.c.GLFW_KEY_DELETE,

        // Arrow keys
        RIGHT = glfw_mod.c.GLFW_KEY_RIGHT,
        LEFT = glfw_mod.c.GLFW_KEY_LEFT,
        DOWN = glfw_mod.c.GLFW_KEY_DOWN,
        UP = glfw_mod.c.GLFW_KEY_UP,

        // Modifier keys
        LEFT_SHIFT = glfw_mod.c.GLFW_KEY_LEFT_SHIFT,
        LEFT_CONTROL = glfw_mod.c.GLFW_KEY_LEFT_CONTROL,
        LEFT_ALT = glfw_mod.c.GLFW_KEY_LEFT_ALT,
        LEFT_SUPER = glfw_mod.c.GLFW_KEY_LEFT_SUPER,
        RIGHT_SHIFT = glfw_mod.c.GLFW_KEY_RIGHT_SHIFT,
        RIGHT_CONTROL = glfw_mod.c.GLFW_KEY_RIGHT_CONTROL,
        RIGHT_ALT = glfw_mod.c.GLFW_KEY_RIGHT_ALT,
        RIGHT_SUPER = glfw_mod.c.GLFW_KEY_RIGHT_SUPER,

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

    pub fn isKeyDown(key: ASCIIKEY) bool {
        const state = glfw_mod.c.glfwGetKey(window.handle, @intFromEnum(key));
        return state == glfw_mod.c.GLFW_PRESS or state == glfw_mod.c.GLFW_REPEAT;
    }

    pub fn isKeyPressed(key: ASCIIKEY) bool {
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

    pub fn getKeyPressed() ?ASCIIKEY {
        if (key_pressed_queue_count == 0) return null;

        // Get first key from queue
        const glfw_key = key_pressed_queue[0];

        // Shift remaining keys down
        var i: usize = 0;
        while (i < key_pressed_queue_count - 1) : (i += 1) {
            key_pressed_queue[i] = key_pressed_queue[i + 1];
        }
        key_pressed_queue_count -= 1;

        // Convert GLFW key code to our ASCIIKEY enum
        return switch (glfw_key) {
            glfw_mod.c.GLFW_KEY_A => .A,
            glfw_mod.c.GLFW_KEY_B => .B,
            glfw_mod.c.GLFW_KEY_C => .C,
            glfw_mod.c.GLFW_KEY_D => .D,
            glfw_mod.c.GLFW_KEY_E => .E,
            glfw_mod.c.GLFW_KEY_F => .F,
            glfw_mod.c.GLFW_KEY_G => .G,
            glfw_mod.c.GLFW_KEY_H => .H,
            glfw_mod.c.GLFW_KEY_I => .I,
            glfw_mod.c.GLFW_KEY_J => .J,
            glfw_mod.c.GLFW_KEY_K => .K,
            glfw_mod.c.GLFW_KEY_L => .L,
            glfw_mod.c.GLFW_KEY_M => .M,
            glfw_mod.c.GLFW_KEY_N => .N,
            glfw_mod.c.GLFW_KEY_O => .O,
            glfw_mod.c.GLFW_KEY_P => .P,
            glfw_mod.c.GLFW_KEY_Q => .Q,
            glfw_mod.c.GLFW_KEY_R => .R,
            glfw_mod.c.GLFW_KEY_S => .S,
            glfw_mod.c.GLFW_KEY_T => .T,
            glfw_mod.c.GLFW_KEY_U => .U,
            glfw_mod.c.GLFW_KEY_V => .V,
            glfw_mod.c.GLFW_KEY_W => .W,
            glfw_mod.c.GLFW_KEY_X => .X,
            glfw_mod.c.GLFW_KEY_Y => .Y,
            glfw_mod.c.GLFW_KEY_Z => .Z,
            glfw_mod.c.GLFW_KEY_0 => .KEY_0,
            glfw_mod.c.GLFW_KEY_1 => .KEY_1,
            glfw_mod.c.GLFW_KEY_2 => .KEY_2,
            glfw_mod.c.GLFW_KEY_3 => .KEY_3,
            glfw_mod.c.GLFW_KEY_4 => .KEY_4,
            glfw_mod.c.GLFW_KEY_5 => .KEY_5,
            glfw_mod.c.GLFW_KEY_6 => .KEY_6,
            glfw_mod.c.GLFW_KEY_7 => .KEY_7,
            glfw_mod.c.GLFW_KEY_8 => .KEY_8,
            glfw_mod.c.GLFW_KEY_9 => .KEY_9,
            glfw_mod.c.GLFW_KEY_SPACE => .SPACE,
            glfw_mod.c.GLFW_KEY_ESCAPE => .ESCAPE,
            glfw_mod.c.GLFW_KEY_ENTER => .ENTER,
            glfw_mod.c.GLFW_KEY_TAB => .TAB,
            glfw_mod.c.GLFW_KEY_BACKSPACE => .BACKSPACE,
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
            // Add other keys as needed, return null for unmapped keys
            else => null,
        };
    }
};

// =============================================================================
// MISC & NO PROPER PLACE FOUND YET
// =============================================================================
fn measureText(text: []const u8, config: zlay.TextProps) zlay.Dimensions {
    // Pick font by size and style
    const style: font_mod.FontStyle = switch (config.font_style) {
        .light => .light,
        .regular => .regular,
        .medium => .medium,
        .semibold => .semibold,
        .bold => .bold,
        .black => .black,
    };
    const size: f32 = @floatFromInt(config.font_size);
    if (config.font_id != 0) {
        std.log.warn("font_id != 0 not supported", .{});
        return zlay.Dimensions{ .w = 0, .h = 0 };
    }
    const font_obj = font_mod.font_collection_geist.getFont(size, style);

    // Scale factor between atlas rasterization and requested size
    const scale = size / font_obj.pixel_height;

    // Get line metrics from FreeType (in 26.6 fixed-point)
    // const ascender_px = @as(f32, @floatFromInt(font_obj.ft_face.*.size.*.metrics.ascender)) / 64.0;
    const line_advance_px = @as(f32, @floatFromInt(font_obj.ft_face.*.size.*.metrics.height)) / 64.0;

    // Shape text using HarfBuzz
    const glyphs = renderer2D.shape_cache.get(font_obj, text) catch |err| {
        std.log.err("Shape text failed: {s}", .{@errorName(err)});
        return zlay.Dimensions{ .w = 0, .h = 0 };
    };
    // owned by per-frame cache; no defer free here

    var cursor_x: f32 = 0.0;
    var cursor_y: f32 = 0.0;
    var max_line_width: f32 = 0.0;
    var line_count: usize = 1;

    for (glyphs) |g| {
        // Newline handling
        if (g.cluster < text.len and text[g.cluster] == '\n') {
            if (cursor_x > max_line_width) max_line_width = cursor_x;
            cursor_x = 0.0;
            cursor_y += line_advance_px * scale;
            line_count += 1;
            continue;
        }

        // Advance pen (HarfBuzz advances are already in pixels)
        cursor_x += g.x_advance * scale;
        cursor_y += g.y_advance * scale;
    }

    // Last line width
    if (cursor_x > max_line_width)
        max_line_width = cursor_x;

    // Height: line_count * line_advance_px
    const total_height = @as(f32, @floatFromInt(line_count)) * line_advance_px * scale;

    // Optional letter spacing
    const final_width = max_line_width + @as(f32, @floatFromInt((text.len - 1 * @as(usize, @intCast(config.letter_spacing)))));

    return zlay.Dimensions{
        .w = final_width,
        .h = total_height,
    };
}
