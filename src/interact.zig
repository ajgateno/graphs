const rl = @import("raylib");
const graph = @import("graph.zig");
const render = @import("render.zig");

pub const Interaction = struct {
    selected: ?usize = null,
    dragging: bool = false,
    /// mouse(world) - node.pos, captured when the drag starts.
    grab_offset: rl.Vector2 = .{ .x = 0, .y = 0 },

    /// Call once per frame, aftetr canvas.update() so we see the latest camera.
    pub fn update(self: *Interaction, g: *graph.Graph, camera: rl.Camera2D) void {
        const world = rl.getScreenToWorld2D(rl.getMousePosition(), camera);
        const hovered = render.nodeAt(g, world);

        // Space + left-drag is the canvas pan gesture, so don't treat
        // those clicks as selection.
        const pan_gesture = rl.isKeyDown(.space);

        // Press: select whatever is under the cursor (or nothing), and
        // start a drag if it was a node.
        if (!pan_gesture and rl.isMouseButtonPressed(.left)) {
            self.selected = hovered;
            if (hovered) |i| {
                const n = g.nodes.items[i];
                self.dragging = true;
                self.grab_offset = .{ .x = world.x - n.pos.x, .y = world.y - n.pos.y };
            }
        }

        // Hold: move the node. Release: stop.
        if (self.dragging) {
            if (rl.isMouseButtonDown(.left)) {
                if (self.selected) |i| {
                    g.nodes.items[i].pos = .{
                        .x = world.x - self.grab_offset.x,
                        .y = world.y - self.grab_offset.y,
                    };
                } else {
                    self.dragging = false;
                }
            }
        }

        // Feedback: tell the user what's clickable.
        if (self.dragging) {
            rl.setMouseCursor(.resize_all);
        } else if (hovered != null) {
            rl.setMouseCursor(.pointing_hand);
        } else {
            rl.setMouseCursor(.default);
        }
    }
};
