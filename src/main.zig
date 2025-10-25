const std = @import("std");

const zen = @import("root.zig");
const zlay = zen.layout;

var text: std.ArrayList(u8) = .empty;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        _ = gpa.detectLeaks();
        _ = gpa.deinit();
    }

    const now = std.time.milliTimestamp();

    const allocator = gpa.allocator();

    try zen.core.init(allocator, .{ 1200, 800 }, "Zender Test", .{});
    defer zen.core.deinit();

    calculator_icon = zen.Image.loadFromMemory(@embedFile("resources/calculator.png")) catch unreachable;

    while (!zen.core.shouldClose()) {
        zen.core.beginFrame();

        zen.layout.beginLayout();
        interface();
        const interface_cmds = zen.layout.endLayout();

        zen.drawing.start();
        zen.drawing.drawLayout(interface_cmds);
        zen.drawing.drawRect(100, 400, 100, 100, .{
            // .corner_radius = .{16} ** 4,
            .color = .{ 200, 200, 200, 255 },
            .rotation_deg = @floatFromInt(@mod(@divFloor(std.time.milliTimestamp() - now, 15), 360)),
        });
        // Simple line
        zen.drawing.drawLine(10, 10, 500, 400, .{
            .width = 40.0,
            .cap = .round,
            .color = .{ 0, 0, 0, 255 },
        });

        // Thick line with round caps
        zen.drawing.drawLine(100, 250, 300, 350, .{
            .width = 40.0,
            .color = .{ 0, 255, 0, 255 }, // Green
            .cap = .round,
        });

        // Square cap line
        zen.drawing.drawLine(100, 400, 300, 500, .{
            .width = 8.0,
            .color = .{ 0, 0, 255, 255 }, // Blue
            .cap = .square,
        });
        zen.drawing.end();

        zen.core.endFrame();
    }
}

var calculator_icon: zen.Image = undefined;
// zen.drawing.Image.loadFromMemory(@embedFile("resources/calculator.png"));

fn interface() void {
    if (zlay.open(.{
        .id = .from("root"),
        .sizing = .{ .full, .full },
        .bg_color = .red,
        .padding = .all(8),
        .layout = .flex(.{
            .gap = 8,
            .alignment = .center_left,
        }),
    })) {
        defer zlay.close();

        if (zlay.open(.{})) {
            defer zlay.close();

            zlay.image(@ptrCast(@alignCast(&calculator_icon)), .{
                .src_dimensions = .{ 200, 200 },
                .id = .from(@src()),
                .sizing = .{ .fixed(48), .fixed(48) },
            });
        }

        if (zlay.open(.{
            .id = .from("left_panel"),
            .sizing = .{ .fixed(200), .full },
            .bg_color = .withAlpha(.blue, 0.4),
            .border = .all(8, .dark_100),
            .padding = .all(8),
            .layout = .flex(.{
                .gap = 8,
                .direction = .y,
                .alignment = .top_center,
            }),
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

            zlay.text(text.items, .{
                .id = .from(@src()),
                .font_size = 18,
                .text_color = .dark_300,
                .font_style = .bold,
                .sizing = .{ .full, .default },
            });

            if (hov and zen.io.isMouseButtonDown(.RIGHT)) {
                zlay.text("Zender is a ui drawing library", .{
                    .id = .from(@src()),
                    .font_size = 18,
                    .text_color = .dark_300,
                    .font_style = .bold,
                    .sizing = .{ .full, .default },
                });

                // TODO: Why does this hover case the next panel to change background color from transparent to light_200?

                if (zlay.open(.{
                    .sizing = .{ .full, .fixed(50) },
                    .corner_radius = .all(4),
                    .bg_color = .dark_300,
                })) {
                    defer zlay.close();
                }
                // zlay.text(
                //     "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit",
                //     .{
                //         .id = .from(@src()),
                //         .font_size = 16,
                //         .font_style = .medium,
                //         .text_color = .dark_300,
                //         .sizing = .{ .full, .default },
                //     },
                // );
            }
        }

        if (zlay.open(.{
            .id = .from("next_panel"),
            .sizing = .{ .fixed(600), .percent(0.5) },
            .bg_color = .light_200,
            .scroll = .{ .y = true },
            .padding = .all(16),
            .corner_radius = .all(40),
            .border = .all(8, .withAlpha(.dark_100, 1.0)),
            .layout = .flex(.{
                .gap = 4,
                .direction = .x,
            }),
        })) {
            defer zlay.close();

            if (zlay.open(.{
                .layout = .flex(.{
                    .gap = 8,
                    .direction = .y,
                }),
            })) {
                defer zlay.close();

                for (0..20) |i| {
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
                        .sizing = .{ .fixed(32), .fixed(32) },
                        .bg_color = .orange,
                        .corner_radius = .all(4),
                    })) {
                        defer zlay.close();
                    }
                }
            }

            // zlay.text(
            //     "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit." ** 20,
            //     .{
            //         .font_size = 16,
            //         .font_style = .medium,
            //         .text_color = .dark_300,
            //         .sizing = .{ .grow, .default },
            //     },
            // );
        }
    }
}
