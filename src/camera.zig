const std = @import("std");

/// 2D Camera with pan, zoom, rotation, and target tracking capabilities
pub const Camera2D = struct {
    /// Camera offset (screen space position)
    offset: [2]f32,
    /// Target position to look at (world space)
    target: [2]f32,
    /// Rotation in radians
    rotation: f32,
    /// Zoom factor (1.0 = no zoom, >1.0 = zoom in, <1.0 = zoom out)
    zoom: f32,

    /// Initialize a default camera at origin with no rotation and 1.0 zoom
    pub fn init() Camera2D {
        return .{
            .offset = .{ 0.0, 0.0 },
            .target = .{ 0.0, 0.0 },
            .rotation = 0.0,
            .zoom = 1.0,
        };
    }

    /// Calculate the 3x3 transformation matrix for this camera
    /// Matrix is in column-major order for OpenGL
    /// Transform order: translate(offset) * rotate(rotation) * scale(zoom) * translate(-target)
    pub fn getMatrix(self: Camera2D) [9]f32 {
        const cos_rot = @cos(self.rotation);
        const sin_rot = @sin(self.rotation);

        // Build matrix components
        // First: translate by -target (move target to origin)
        // Then: scale by zoom
        // Then: rotate
        // Finally: translate by offset

        const zoom_cos = self.zoom * cos_rot;
        const zoom_sin = self.zoom * sin_rot;

        // Combined matrix in column-major order:
        // Column 0: [zoom*cos,  -zoom*sin, 0]
        // Column 1: [zoom*sin,   zoom*cos, 0]
        // Column 2: [tx,         ty,       1]
        // Formula: screen = offset + zoom * rotate(-target)

        const tx = self.offset[0] + zoom_cos * (-self.target[0]) - zoom_sin * (-self.target[1]);
        const ty = self.offset[1] + zoom_sin * (-self.target[0]) + zoom_cos * (-self.target[1]);

        return [9]f32{
            zoom_cos,  -zoom_sin, 0.0, // Column 0
            zoom_sin,  zoom_cos,  0.0, // Column 1
            tx,        ty,        1.0, // Column 2
        };
    }

    /// Convert screen coordinates to world coordinates
    pub fn screenToWorld(self: Camera2D, screen_x: f32, screen_y: f32) [2]f32 {
        // Inverse transform: apply in reverse order
        // 1. Subtract offset
        // 2. Apply inverse rotation
        // 3. Apply inverse zoom
        // 4. Add target

        const cos_rot = @cos(-self.rotation);
        const sin_rot = @sin(-self.rotation);
        const inv_zoom = 1.0 / self.zoom;

        // Subtract offset
        const rel_x = screen_x - self.offset[0];
        const rel_y = screen_y - self.offset[1];

        // Apply inverse rotation and zoom
        const world_x = (cos_rot * rel_x - sin_rot * rel_y) * inv_zoom + self.target[0];
        const world_y = (sin_rot * rel_x + cos_rot * rel_y) * inv_zoom + self.target[1];

        return .{ world_x, world_y };
    }

    /// Convert world coordinates to screen coordinates
    pub fn worldToScreen(self: Camera2D, world_x: f32, world_y: f32) [2]f32 {
        // Forward transform
        // 1. Subtract target
        // 2. Apply zoom
        // 3. Apply rotation
        // 4. Add offset

        const cos_rot = @cos(self.rotation);
        const sin_rot = @sin(self.rotation);

        // Subtract target and apply zoom
        const rel_x = (world_x - self.target[0]) * self.zoom;
        const rel_y = (world_y - self.target[1]) * self.zoom;

        // Apply rotation and add offset
        const screen_x = cos_rot * rel_x - sin_rot * rel_y + self.offset[0];
        const screen_y = sin_rot * rel_x + cos_rot * rel_y + self.offset[1];

        return .{ screen_x, screen_y };
    }

    /// Set the camera target position (what the camera looks at)
    pub fn setTarget(self: *Camera2D, x: f32, y: f32) void {
        self.target[0] = x;
        self.target[1] = y;
    }

    /// Set the camera offset (screen position)
    pub fn setOffset(self: *Camera2D, x: f32, y: f32) void {
        self.offset[0] = x;
        self.offset[1] = y;
    }

    /// Set the zoom level (1.0 = normal, >1.0 = zoom in, <1.0 = zoom out)
    pub fn setZoom(self: *Camera2D, zoom: f32) void {
        self.zoom = zoom;
    }

    /// Zoom towards a specific screen position (e.g., mouse cursor)
    /// This adjusts the target so the world point under screen_pos stays fixed
    pub fn zoomTowards(self: *Camera2D, new_zoom: f32, screen_x: f32, screen_y: f32) void {
        if (self.zoom == new_zoom) return;

        // Update zoom
        const old_zoom = self.zoom;
        self.zoom = new_zoom;

        // Adjust target to keep the same world position under the cursor
        // Formula: target_new = target_old + (screen - offset) * (1/zoom_old - 1/zoom_new)
        const cos_rot = @cos(self.rotation);
        const sin_rot = @sin(self.rotation);

        const rel_x = screen_x - self.offset[0];
        const rel_y = screen_y - self.offset[1];

        // Apply inverse rotation
        const rot_x = cos_rot * rel_x - sin_rot * rel_y;
        const rot_y = sin_rot * rel_x + cos_rot * rel_y;

        const zoom_diff = 1.0 / old_zoom - 1.0 / new_zoom;
        self.target[0] += rot_x * zoom_diff;
        self.target[1] += rot_y * zoom_diff;
    }

    /// Set the rotation in radians
    pub fn setRotation(self: *Camera2D, rotation: f32) void {
        self.rotation = rotation;
    }

    /// Smoothly move camera target towards a position
    pub fn trackTarget(self: *Camera2D, target_x: f32, target_y: f32, smooth_factor: f32) void {
        const factor = std.math.clamp(smooth_factor, 0.0, 1.0);
        self.target[0] += (target_x - self.target[0]) * factor;
        self.target[1] += (target_y - self.target[1]) * factor;
    }
};

test "Camera2D initialization" {
    const camera = Camera2D.init();
    try std.testing.expectEqual(@as(f32, 0.0), camera.offset[0]);
    try std.testing.expectEqual(@as(f32, 0.0), camera.offset[1]);
    try std.testing.expectEqual(@as(f32, 0.0), camera.target[0]);
    try std.testing.expectEqual(@as(f32, 0.0), camera.target[1]);
    try std.testing.expectEqual(@as(f32, 0.0), camera.rotation);
    try std.testing.expectEqual(@as(f32, 1.0), camera.zoom);
}

test "Camera2D screen to world and back" {
    var camera = Camera2D.init();
    camera.setTarget(100.0, 100.0);
    camera.setZoom(2.0);

    const world = camera.screenToWorld(200.0, 200.0);
    const screen = camera.worldToScreen(world[0], world[1]);

    try std.testing.expectApproxEqAbs(@as(f32, 200.0), screen[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 200.0), screen[1], 0.001);
}
