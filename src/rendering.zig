const std = @import("std");
const zlay = @import("zlayout");
const font = @import("font.zig");
const openGL = @import("openGL.zig");
const glfw = @import("glfw.zig");
const pencil = &@import("main.zig").pencil;

pub fn draw(cmds: []const zlay.DrawCommand, window: *glfw.Window) void {
    // const window_h = @as(f32, @floatFromInt(window.windowSize()[1]));
    const scale = window.getContentScale();
    for (cmds) |cmd| {
        switch (cmd) {
            .clipStart => |clip| {
                pencil.flush();
                const rect: [4]f32 = .{
                    clip.rect.x * scale[0],
                    clip.rect.y * scale[1],
                    clip.rect.width * scale[0],
                    clip.rect.height * scale[1],
                };
                // _ = rect;
                openGL.clipStart(rect);
            },
            .clipEnd => {
                pencil.flush();
                openGL.clipEnd();
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
                pencil.drawRoundedBorderRect(
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

                const style: font.FontStyle = switch (text_config.font_style) {
                    .light => .light,
                    .regular => .regular,
                    .medium => .medium,
                    .semibold => .semibold,
                    .bold => .bold,
                };
                const text_color: [4]u8 = .{
                    text_config.text_color.r,
                    text_config.text_color.g,
                    text_config.text_color.b,
                    text_config.text_color.a,
                };
                const text = text_cmd.text;

                pencil.drawText(
                    font.font_collection_geist,
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

pub fn measureText(text: []const u8, config: zlay.TextProps) zlay.Dimensions {
    // Pick font by size and style
    const style: font.FontStyle = switch (config.font_style) {
        .light => .light,
        .regular => .regular,
        .medium => .medium,
        .semibold => .semibold,
        .bold => .bold,
    };
    const size: f32 = @floatFromInt(config.font_size);
    if (config.font_id != 0) {
        std.log.warn("font_id != 0 not supported", .{});
        return zlay.Dimensions{ .w = 0, .h = 0 };
    }
    const font_obj = font.font_collection_geist.getFont(size, style);

    // Scale factor between atlas rasterization and requested size
    const scale = size / font_obj.pixel_height;

    // Get line metrics from FreeType (in 26.6 fixed-point)
    // const ascender_px = @as(f32, @floatFromInt(font_obj.ft_face.*.size.*.metrics.ascender)) / 64.0;
    const line_advance_px = @as(f32, @floatFromInt(font_obj.ft_face.*.size.*.metrics.height)) / 64.0;

    // Shape text using HarfBuzz
    const glyphs = font_obj.shapeText(text) catch |err| {
        std.log.err("Shape text failed: {s}", .{@errorName(err)});
        return zlay.Dimensions{ .w = 0, .h = 0 };
    };
    defer font_obj.deinitShapedText(glyphs);

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
