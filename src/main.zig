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

    const allocator = gpa.allocator();

    try zen.core.init(allocator, .{ 1200, 800 }, "Zender Test", .{ .print_perf = true });
    defer zen.core.deinit();

    calculator_icon = zen.Image.loadFromMemory(@embedFile("resources/calculator.png")) catch unreachable;

    while (!zen.core.shouldClose()) {
        zen.core.beginFrame();

        zen.layout.beginLayout();
        interface();
        const interface_cmds = zen.layout.endLayout();

        zen.drawing.start();
        zen.drawing.drawLayout(interface_cmds);
        // zen.drawing.drawRect(100, 400, 100, 100, .{
        //     // .corner_radius = .{16} ** 4,
        //     .color = .{ 200, 200, 200, 255 },
        //     .rotation_deg = @floatFromInt(@mod(@divFloor(std.time.milliTimestamp() - now, 10), 360)),
        // });
        // // Simple line
        // const mouse_pos = zen.io.getMousePosition();
        // zen.drawing.drawLine(
        //     .{ 50, 50 },
        //     .{ @floatCast(mouse_pos[0]), @floatCast(mouse_pos[1]) },
        //     .{
        //         .width = 4.0,
        //         .cap = .round,
        //         .color = .{ 0, 0, 0, 255 },
        //     },
        // );
        //
        // zen.drawing.drawLines(&.{
        //     .{ 100, 100 },
        //     .{ 200, 200 },
        //     .{ 800, 300 },
        //     .{ 300, 600 },
        //     .{ 100, 100 },
        // }, .{
        //     .width = 2.0,
        //     .cap = .round,
        //     .color = .{ 0, 0, 0, 255 },
        // });

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
        .padding = .all(8),
        .bg_color = .light_300,
        .layout = .flex(.{
            .gap = 8,
        }),
    })) {
        defer zlay.close();

        if (zlay.open(.{
            .layout = .flex(.{
                .gap = 8,
                .direction = .y,
                .alignment = .top_center,
            }),
            .sizing = .{ .fixed(120), .full },
            .bg_color = .light_200,
            .border = .all(1, .withAlpha(.black, 0.2)),
            .corner_radius = .all(8),
            .padding = .all(8),
        })) {
            defer zlay.close();

            const hvrd = zlay.hovered();

            if (zlay.open(.{
                .sizing = .{ .full, .fit },
                .layout = .flex(.{
                    .gap = 4,
                    .direction = .y,
                    .alignment = .center,
                }),
            })) {
                defer zlay.close();

                if (zlay.open(.{
                    .sizing = .{ .fixed(16), .fixed(16) },
                    .corner_radius = .all(400),
                    .bg_color = .red,
                })) {
                    defer zlay.close();
                }
                zlay.text("Demo", .{
                    .text_color = .dark_300,
                    .font_size = 24,
                });
            }
            zlay.text("das ist ein test das ist ein test das ist ein test", .{});

            if (hvrd) {
                zlay.text("hidden text", .{
                    .font_size = 18,
                    .text_color = .dark_300,
                });
            }
        }

        if (zlay.open(.{
            .layout = .flex(.{
                .gap = 8,
                .direction = .y,
                .alignment = .top_center,
            }),
            .sizing = .{ .grow, .full },
            .bg_color = .light_200,
            .border = .all(1, .withAlpha(.black, 0.2)),
            .corner_radius = .all(8),
            .padding = .all(8),
        })) {
            defer zlay.close();
        }

        if (zlay.open(.{
            .layout = .flex(.{
                .gap = 8,
                .direction = .y,
                .alignment = .top_center,
            }),
            .sizing = .{ .fixed(120), .full },
            .bg_color = .light_200,
            .border = .all(1, .withAlpha(.black, 0.2)),
            .corner_radius = .all(8),
            .padding = .all(8),
        })) {
            defer zlay.close();

            inline for (0..24) |i| {
                if (zlay.open(.{
                    .id = .from(i),
                    .sizing = .{ .full, .fit },
                    .bg_color = .orange,
                    .corner_radius = .all(8),
                    .layout = .flex(.{
                        .alignment = .center,
                    }),
                })) {
                    defer zlay.close();

                    zlay.text(std.fmt.comptimePrint("Item {d}", .{i}), .{
                        .text_color = .dark_300,
                    });
                }
            }
        }
    }
}

fn interface2() void {
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
                if (zlay.open(.{
                    .bg_color = .red,
                    .sizing = .{ .full, .default },
                })) {
                    defer zlay.close();
                    zlay.text("Zender is a ui drawing library", .{
                        .id = .from(@src()),
                        .font_size = 18,
                        .text_color = .dark_300,
                        .font_style = .bold,
                    });
                }

                // TODO: Why does this hover case the next panel to change background color from transparent to light_200?

                if (zlay.open(.{
                    .sizing = .{ .full, .fixed(50) },
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
                    },
                );
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

            zlay.text(
                "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit." ** 20,
                .{
                    .font_size = 16,
                    .font_style = .medium,
                    .text_color = .dark_300,
                    .sizing = .{ .grow, .default },
                },
            );
        }
    }
}
