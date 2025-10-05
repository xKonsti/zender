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

    // // Initialize OpenGL function table
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
    pencil = try glWrapper.Renderer2D.init(alloc, program);

    zlay.configure(.{
        .allocator = alloc,
        .measure_text = renderer.measureText,
        .perf_info = false,
    });

    // Main loop
    var prev_frame_time: i64 = std.time.milliTimestamp();
    while (!window.shouldClose()) {
        const now = std.time.milliTimestamp();
        const delta_ms = now - prev_frame_time;
        prev_frame_time = now;
        const delta_time = @as(f32, @floatFromInt(delta_ms)) / 1000;
        defer std.debug.print("Frame took {d}ms\n", .{std.time.milliTimestamp() - now});

        // const mouse_pos = window.mousePos();
        // std.debug.print("Mouse pos: {d}, {d}\n", .{ mouse_pos[0], mouse_pos[1] });

        // Clear screen
        gl.ClearColor(0.2, 0.3, 0.3, 1.0);
        gl.Clear(gl.COLOR_BUFFER_BIT);

        program.use();

        pencil.begin(window.windowSize(), window.getContentScale());

        const mouse_pos = window.mousePos();
        const window_size = window.windowSize();
        // Important: poll events BEFORE reading accumulated scroll
        glfw.pollEvents();
        const scroll = window.takeMouseScrollDelta();

        // std.debug.print("delta time: {d}\twith scroll: {d} {d}\n", .{ last_frame_time, scroll[0], scroll[1] });

        zlay.startLayout(.{
            .is_down = false,
            .x = @floatCast(mouse_pos[0]),
            .y = @floatCast(mouse_pos[1]),
        }, .{
            .delta = .{ .x = @floatCast(scroll[0]), .y = @floatCast(scroll[1]) },
            .delta_time = @floatCast(delta_time),
        }, .{
            .w = @floatFromInt(window_size[0]),
            .h = @floatFromInt(window_size[1]),
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
        renderer.draw(zlay.endLayout(), &window);
        pencil.end();

        // Swap buffers
        window.swapBuffers();
    }
}

fn interface() void {
    if (zlay.open(.{
        .id = .from("root"),
        .width = .full,
        .height = .full,
        .bg_color = .red,
        .padding = .all(8),
        .gap = 8,
        .alignment = .center_left,
    })) {
        defer zlay.close();

        if (zlay.open(.{
            .id = .from("left_panel"),
            .width = .fixed(200),
            .height = .full,
            .bg_color = .light_300,
            .border = .all(8, .dark_100),
            .padding = .all(8),
            .gap = 8,
            .direction = .y,
            .alignment = .top_center,
            .corner_radius = .all(12),
        })) {
            defer zlay.close();
            const hov = zlay.hovered();

            zlay.text("Zender", .{
                .id = .from(@src()),
                .font_size = 24,
                .text_color = .dark_300,
                .font_style = .bold,
            });

            if (hov) {
                zlay.text("Zender is a ui drawing library", .{
                    .id = .from(@src()),
                    .font_size = 18,
                    .text_color = .dark_300,
                    .font_style = .bold,
                    .width = .full,
                });

                // TODO: Why does this hover case the next panel to change background color from transparent to light_200?

                if (zlay.open(.{
                    .width = .full,
                    .height = .fixed(50),
                    .corner_radius = .all(4),
                    .bg_color = .dark_300,
                })) {
                    defer zlay.close();
                }
                zlay.text(
                    "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit",
                    .{
                        .id = .from(@src()),
                        .font_size = 16,
                        .font_style = .medium,
                        .text_color = .dark_300,
                        .width = .full,
                    },
                );
            }
        }

        if (zlay.open(.{
            .id = .from("next_panel"),
            .width = .fixed(400),
            .height = .percent(0.5),
            .bg_color = .light_200,
            .scroll = .{ .y = true, .x = true },
            .padding = .all(16),
            .corner_radius = .all(40),
            .border = .all(8, .withAlpha(.dark_100, 1.0)),
            .gap = 4,
            .direction = .x,
        })) {
            defer zlay.close();

            if (zlay.open(.{
                .gap = 8,
                .direction = .y,
            })) {
                defer zlay.close();

                for (0..2000) |i| {
                    // if (zlay.open(.{
                    //     .id = .from(i),
                    //     .bg_color = .orange,
                    //     .corner_radius = .all(4),
                    // })) {
                    //     defer zlay.close();
                    //     zlay.text("Hello world", .{
                    //         .font_size = 16,
                    //         .font_style = .medium,
                    //         .text_color = .dark_300,
                    //     });
                    // }
                    if (zlay.open(.{
                        .id = .from(i),
                        .width = .fixed(32),
                        .height = .fixed(32),
                        .bg_color = .orange,
                        .corner_radius = .all(4),
                    })) {
                        defer zlay.close();
                    }
                }
            }

            zlay.text(
                "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit" ** 20,
                .{
                    .font_size = 16,
                    .font_style = .medium,
                    .text_color = .dark_300,
                    .width = .grow,
                },
            );
        }
    }
}
