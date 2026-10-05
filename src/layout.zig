const std = @import("std");
const rl = @import("raylib");
const graph = @import("graph.zig");

/// Place all nodes evenly on a circle around the origin.
pub fn circle(g: *graph.Graph) void {
    const n: f32 = @floatFromInt(g.nodes.items.len);
    if (n == 0) return;

    // Grow the radius with the node count so neighbors keep ~110 units of
    // arc between them, but never shrink below a readable minimum.
    const radius = @max(150.0, n * 110.0 / (2.0 * std.math.pi));

    for (g.nodes.items, 0..) |*node, i| {
        const angle = 2.0 * std.math.pi * @as(f32, @floatFromInt(i)) / n;
        node.pos = .{ .x = radius * @cos(angle), .y = radius * @sin(angle) };
    }
}

/// Fruchterman-Reingold force-directed layout, run one step per frame.
pub const Force = struct {
    /// Ideal edge length, in world units.
    k: f32 = 160,
    /// "Heat" from 1 (hot, big moves) down to 0. Decays every step.
    alpha: f32 = 1.0,

    const gravity: f32 = 0.05;
    const step_scale: f32 = 0.1;

    pub fn asleep(self: Force) bool {
        return self.alpha < 0.01;
    }

    /// Raise the heat to at least `to`. Never cools it down.
    pub fn reheat(self: *Force, to: f32) void {
        self.alpha = @max(self.alpha, to);
    }

    /// Advance the simulation one step. `pinned` is a node the simulation
    /// must not move (the one being dragged).
    pub fn step(self: *Force, g: *graph.Graph, pinned: ?usize) void {
        if (self.asleep()) return;
        const nodes = g.nodes.items;
        const k2 = self.k * self.k;

        for (nodes) |*n| n.disp = .{ .x = 0, .y = 0 };

        // Repulsion: every pair pushes apart. Visiting each pair once
        // (j > i) and applying equal and opposite forces halves the work.
        for (nodes, 0..) |*a, i| {
            for (nodes[i + 1 ..]) |*b| {
                var dx = a.pos.x - b.pos.x;
                var dy = a.pos.y - b.pos.y;
                var d2 = dx * dx + dy * dy;
                if (d2 < 0.01) { // exactly overlapping: pick any direction
                    dx = 0.1;
                    dy = 0.1;
                    d2 = 0.02;
                }
                const d = @sqrt(d2);
                const f = k2 / d; // magnitude
                const fx = dx / d * f; // (dx/d, dy/d) is the unit direction
                const fy = dy / d * f;
                a.disp.x += fx;
                a.disp.y += fy;
                b.disp.x -= fx;
                b.disp.y -= fy;
            }
        }

        // Attraction: every edge is a spring pulling its ends together.
        for (g.edges.items) |e| {
            if (e.from == e.to) continue;
            const a = &nodes[e.from];
            const b = &nodes[e.to];
            const dx = b.pos.x - a.pos.x;
            const dy = b.pos.y - a.pos.y;
            const d = @max(@sqrt(dx * dx + dy * dy), 0.01);
            const f = d * d / self.k;
            const fx = dx / d * f;
            const fy = dy / d * f;
            a.disp.x += fx;
            a.disp.y += fy;
            b.disp.x -= fx;
            b.disp.y -= fy;
        }

        // Move each node along its net force, capped by the temperature.
        const temp = self.alpha * self.k * 0.25;
        for (nodes, 0..) |*n, i| {
            // A weak pull toward the origin keeps disconnected pieces of
            // the graph from drifting off to infinity.
            n.disp.x -= n.pos.x * gravity;
            n.disp.y -= n.pos.y * gravity;

            if (pinned == i) continue;
            const len = @sqrt(n.disp.x * n.disp.x + n.disp.y * n.disp.y);
            if (len < 1e-6) continue;
            const move = @min(len * step_scale, temp);
            n.pos.x += n.disp.x / len * move;
            n.pos.y += n.disp.y / len * move;
        }

        self.alpha *= 0.98; // cool down
    }
};
