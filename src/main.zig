const std = @import("std");

const glfw = @import("glfw.zig");
const glWrapper = @import("openGL.zig");
const gl = glWrapper.gl;
const font = @import("font.zig");
const zlay = @import("zlayout");
const renderer = @import("rendering.zig");

// Youâ€™ll import or declare OpenGL function pointers somewhere, e.g.:
var procs: gl.ProcTable = undefined;

fn errorCallback(errn: c_int, str: [*c]const u8) callconv(std.builtin.CallingConvention.c) void {
    std.log.err("GLFW Error: {d} - {s}\n", .{ errn, str });
}

pub var pencil: glWrapper.Renderer2D = undefined;

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
    pencil = try glWrapper.Renderer2D.init(program);

    zlay.configure(.{
        .allocator = alloc,
        .measure_text = renderer.measureText,
    });

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

        pencil.begin(window.bufferSize(), window.getContentScale());

        const mouse_pos = window.mousePos();
        const buffer_size = window.windowSize();
        zlay.startLayout(.{
            .is_down = false,
            .x = @floatCast(mouse_pos[0]),
            .y = @floatCast(mouse_pos[1]),
        }, .{}, .{
            .w = @floatFromInt(buffer_size[0]),
            .h = @floatFromInt(buffer_size[1]),
        });

        interface();

        // draw_caller.drawRect(5, 5, 200, 50, .{ 1.0, 0.5, 0.0, 1.0 });
        // draw_caller.drawRect(0, 0, 100, 100, .{ 0.0, 0.0, 1.0, 0.2 });
        // draw_caller.drawRect(100, 100, 200, 50, .{ 1.0, 0.5, 0.0, 1.0 });
        // draw_caller.drawRoundedBorderRect(350, 100, 100, 100, 0, .{ 0.2, 0.8, 0.3, 1.0 }, .{8} ** 4, .{ 0.0, 0.0, 0.0, 1.0 });
        //
        // draw_caller.drawRoundedBorderRect(200, 300, 400, 300, 120, .{ 0.8, 0.2, 0.2, 1.0 }, .{ 4, 8, 2, 6 }, .{ 1, 1, 0, 1 });
        // draw_caller.drawRoundedRect(1000, 0, 100, 100, 12, .{ 1.0, 0.0, 0.0, 1.0 });
        // draw_caller.drawRoundedBorderRect(800, 400, 140, 100, 12, .{ 1.0, 1.0, 0.0, 0.8 }, .{2} ** 4, .{ 0.0, 0.0, 0.0, 1.0 });

        // renderer.drawRect(95, 55, 800, 800, .{ 0.0, 0.0, 0.0, 1.0 });
        // try renderer.drawText(font.font_collection_geist,
        //     \\Hällö, World!éáó
        //     \\Lorem ipsum dolor sit.
        //     \\Nullam euismod, nisl?
        //     \\NULLAM EUISMOD, NISL?
        // , 100, 60, 60, .regular, .{ 1.0, 1.0, 1.0, 1.0 });
        renderer.draw(zlay.endLayout());
        pencil.end();

        // Swap buffers & poll events
        window.swapBuffers();
        glfw.pollEvents();
    }
}

fn ortho(l: f32, r: f32, bottom: f32, top: f32, near: f32, far: f32) [16]f32 {
    return [_]f32{
        2 / (r - l),        0,                                0,                            0,
        0,                  2 / (top - bottom),               0,                            0,
        0,                  0,                                -2 / (far - near),            0,
        -(r + l) / (r - l), -(top + bottom) / (top - bottom), -(far + near) / (far - near), 1,
    };
}

fn interface() void {
    if (zlay.open(.{
        .id = .from("root"),
        .width = .full,
        .height = .full,
        .bg_color = .red,
        .padding = .all(8),
    })) {
        defer zlay.close();

        if (zlay.open(.{
            .id = .from("left_panel"),
            .width = .fixed(120),
            .height = .full,
            .bg_color = .light_300,
            .border = .all(4, .dark_100),
            .padding = .all(8),
            .gap = 8,
            .direction = .y,
            .alignment = .top_center,
            .corner_radius = .all(12),
        })) {
            defer zlay.close();

            zlay.text("Zender", .{
                .id = .from("zender"),
                .font_size = 24,
                .text_color = .dark_300,
                .font_style = .bold,
            });

            zlay.text("Zender is a ui drawing library", .{
                .font_size = 16,
                .text_color = .dark_300,
                .font_style = .bold,
                .width = .full,
            });
        }
    }
}

fn blueprintInterface() void {
    const GAPS_AND_ROUNDING = 8;
    const BORDER_COLOR: zlay.RGBA = .dark_100;

    if (zlay.open(.{
        .id = .from("root"),
        .width = .full,
        .height = .full,
        .padding = .all(8),
    })) {
        defer zlay.close();

        if (zlay.open(.{
            .id = .from("l_panel"),
            .width = .fixed(120),
            .height = .full,
            .bg_color = .light_300,
            .border = .{ .r = 1, .color = BORDER_COLOR },
            .padding = .all(GAPS_AND_ROUNDING),
            .gap = GAPS_AND_ROUNDING,
            .direction = .y,
            .corner_radius = .{ .bottom_left = 8, .top_left = 8 },
        })) {
            defer zlay.close();
        }
        if (zlay.open(.{
            .id = .from("main_panel"),
            .width = .grow,
            .height = .grow,
            .bg_color = .light_100,
            .gap = 40,
            .padding = .all(GAPS_AND_ROUNDING),
            .direction = .y,
        })) {
            defer zlay.close();

            if (zlay.open(.{
                .id = .from(@src()),
                .width = .fixed(120),
                .height = .fixed(400),
                .bg_color = .light_300,
                .direction = .y,
                .padding = .all(4),
                .scroll = .{ .y = true, .x = true },
                .gap = 4,
            })) {
                defer zlay.close();
                // inline for (0..200) |i| {
                //     if (zlay.open(.{
                //         .id = .from(i),
                //         .width = .full,
                //         .height = .fixed(60),
                //         .bg_color = .orange,
                //         .alignment = .center,
                //         .corner_radius = .all(4),
                //     })) {
                //         defer zlay.close();
                //
                //         zlay.text("Beispieltext", .{});
                //     }
                // }
            }

            zlay.text("Hallo", .{
                .id = .from("hallo"),
                .text_color = .dark_300,
            });
        }

        if (zlay.open(.{
            .id = .from("r_panel"),
            .width = .fixed(120),
            .height = .full,
            .bg_color = .light_300,
            .border = .{ .l = 1, .color = BORDER_COLOR },
        })) {
            defer zlay.close();
        }
    }
}
