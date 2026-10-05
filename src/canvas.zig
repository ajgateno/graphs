const std = @import("std");
const rl = @import("raylib");

pub const Canvas = struct {
    camera: rl.Camera2D,

    const min_zoom: f32 = 0.02;
    const max_zoom: f32 = 64.0;

    pub fn init() Canvas {
        const w: f32 = @floatFromInt(rl.getScreenWidth());
        const h: f32 = @floatFromInt(rl.getScreenHeight());
        return .{
            .camera = .{
                .offset = .{ .x = w / 2, .y = h / 2 }, // world origin starts at screen center
                .target = .{ .x = 0, .y = 0 },
                .rotation = 0,
                .zoom = 1,
            },
        };
    }

    /// Handle input: pan and zoom. Call once per frame, before drawing.
    pub fn update(self: *Canvas) void {
        const mouse = rl.getMousePosition();

        // Pan with the middle mouse button, or space + left button
        // (handy on laptops without a middle button).
        const panning = rl.isMouseButtonDown(.middle) or
            (rl.isKeyDown(.space) and rl.isMouseButtonDown(.left));
        if (panning) {
            const delta = rl.getMouseDelta();
            // Draggging right by 10 screen pixels should move the camera left by
            // 10 / zoom world units, so the content follows the cursor.
            self.camera.target.x -= delta.x / self.camera.zoom;
            self.camera.target.y -= delta.y / self.camera.zoom;
        }

        // Zoom toward the cursor.
        const wheel = rl.getMouseWheelMove();
        if (wheel != 0) {
            const world_under_mouse = rl.getScreenToWorld2D(mouse, self.camera);
            self.camera.offset = mouse;
            self.camera.target = world_under_mouse;

            // Multiplicative zoom feels uniform at every scale: each wheel
            // notch changes the zoom by 10%, not by a fixed amount.
            const factor = std.math.pow(f32, 1.1, wheel);
            self.camera.zoom = std.math.clamp(self.camera.zoom * factor, min_zoom, max_zoom);
        }
    }

    /// Draw the dot grid. Must be called between beginMode2D and endMode2D.
    pub fn drawGrid(self: Canvas) void {
        const cam = self.camera;
        const w: f32 = @floatFromInt(rl.getScreenWidth());
        const h: f32 = @floatFromInt(rl.getScreenHeight());

        // Which part of the world is visible? Convert two opposite screen
        // corner to world coordinates.
        const top_left = rl.getScreenToWorld2D(.{ .x = 0, .y = 0 }, cam);
        const bottom_right = rl.getScreenToWorld2D(.{ .x = w, .y = h }, cam);

        // Pick a spacing (a power of two, in world units) so dots are at least
        // ~24 screen pixels apart. Zoom out and the spacing doubles; zoom in
        // and it halves. On screen the grid always looks about as dense.
        const min_screen_px: f32 = 24;
        const exponent = @ceil(@log2(min_screen_px / cam.zoom));
        const spacing = std.math.pow(f32, 2, exponent);

        // Index range of dots inside the visible rectangle. Using integer
        // indices instead of repeatedly adding `spacing` avoids float drift.
        const ix0: i32 = @intFromFloat(@floor(top_left.x / spacing));
        const ix1: i32 = @intFromFloat(@ceil(bottom_right.x / spacing));
        const iy0: i32 = @intFromFloat(@floor(top_left.y / spacing));
        const iy1: i32 = @intFromFloat(@ceil(bottom_right.y / spacing));

        // We're drawing in world units, which get scaled by zoom. Dividing by
        // zoom cancels that out, so dots stay ~1.2 screen pixels in radius.
        const radius = 1.2 / cam.zoom;
        const color = rl.Color.init(190, 190, 195, 255);

        var iy = iy0;
        while (iy <= iy1) : (iy += 1) {
            var ix = ix0;
            while (ix <= ix1) : (ix += 1) {
                const x = @as(f32, @floatFromInt(ix)) * spacing;
                const y = @as(f32, @floatFromInt(iy)) * spacing;
                rl.drawCircleV(.{ .x = x, .y = y }, radius, color);
            }
        }
    }
};
