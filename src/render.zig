const std = @import("std");
const rl = @import("raylib");
const graph = @import("graph.zig");

const corner_roundness: f32 = 0.35;

const font_size: i32 = 18;
const pad_x: f32 = 14;
const pad_y: f32 = 10;

const node_fill = rl.Color.init(255, 255, 255, 255);
const node_border = rl.Color.init(90, 100, 120, 255);
const text_color = rl.Color.init(40, 44, 52, 255);
const edge_color = rl.Color.init(120, 130, 150, 255);
const accent = rl.Color.init(37, 99, 235, 255);

/// Compute each node's size from its label. Call once after the window is
/// open (measuring text needs the font) and again whenever labels change.
pub fn measureNodes(g: *graph.Graph) void {
    for (g.nodes.items) |*n| {
        const text_w: f32 = @floatFromInt(rl.measureText(n.label, font_size));
        n.size = .{
            .x = text_w + 2 * pad_x,
            .y = @as(f32, @floatFromInt(font_size)) + 2 * pad_y,
        };
    }
}

/// Draw the whole graph. Call between beginMode2D and endMode2D.
pub fn drawGraph(g: *const graph.Graph, zoom: f32, selected: ?usize) void {
    // Edges first so nodes paint over their endpoints.
    for (g.edges.items) |e| drawEdge(g, e, zoom);
    for (g.nodes.items, 0..) |n, i| drawNode(n, selected == i);
}

fn drawNode(n: graph.Node, selected: bool) void {
    const border: f32 = 1.5;

    const outer = rl.Rectangle{
        .x = n.pos.x - n.size.x / 2,
        .y = n.pos.y - n.size.y / 2,
        .width = n.size.x,
        .height = n.size.y,
    };
    const inner = rl.Rectangle{
        .x = outer.x + border,
        .y = outer.y + border,
        .width = outer.width - 2 * border,
        .height = outer.height - 2 * border,
    };

    // `roundness` is relative to the shorter side, so we conver to an
    // actual corner radius and shrink it by the border width for the inner
    // rectangle. That keeps the border an even thickness around the corners.
    const outer_radius = corner_roundness * @min(outer.width, outer.height) / 2;
    const inner_radius = outer_radius - border;
    const inner_roundness = inner_radius * 2 / @min(inner.width, inner.height);

    if (selected) {
        const grow: f32 = 4;
        const halo = rl.Rectangle{
            .x = outer.x - grow,
            .y = outer.y - grow,
            .width = outer.width + 2 * grow,
            .height = outer.height + 2 * grow,
        };
        const halo_roundness = (outer_radius + grow) * 2 / @min(halo.width, halo.height);
        rl.drawRectangleRounded(halo, halo_roundness, 8, rl.Color.init(39, 99, 235, 70));
    }

    rl.drawRectangleRounded(outer, corner_roundness, 8, if (selected) accent else node_border);
    rl.drawRectangleRounded(inner, inner_roundness, 8, node_fill);

    rl.drawTextEx(
        rl.getFontDefault() catch unreachable,
        n.label,
        .{ .x = outer.x + pad_x, .y = outer.y + pad_y },
        @floatFromInt(font_size),
        1, // spacing: matches what drawText uses for this size (18 / 10 = 1)
        text_color,
    );
}

fn drawEdge(g: *const graph.Graph, e: graph.Edge, zoom: f32) void {
    if (e.from == e.to) return; // self-loops need a curve; later step
    const a = g.nodes.items[e.from];
    const b = g.nodes.items[e.to];

    const start = borderPoint(a, b.pos);
    const end = borderPoint(b, a.pos);

    // Line widths are in world units and get scaled by zoom. Dividing by
    // zoom gives edges a constant on-screen thickness, like the grid dots.
    const thick = 2.0 / zoom;
    rl.drawLineEx(start, end, thick, edge_color);
    if (g.directed) drawArrowhead(end, start, 12.0 / zoom, thick, edge_color);
}

/// Corner radius in world units for a node of the given size. Matches how
/// drawNode converts raylib's relative `roundness` into an actual radius.
fn cornerRadius(size: rl.Vector2) f32 {
    return corner_roundness * @min(size.x, size.y) / 2;
}

/// Signed distance from point (px, py), relative to the box center, to a
/// rounded rectangle with the given half-extents and corner radius.
/// Negative = inside, positive = outside, zero = exactly on the edge.
fn roundedBoxSdf(px: f32, py: f32, half: rl.Vector2, r: f32) f32 {
    // Fold into one quadrant, then measure against the "inner" rectangle
    // (the box shrunk by r). Rounding is just "distance to that inner box,
    // minus r".
    const qx = @abs(px) - (half.x - r);
    const qy = @abs(py) - (half.y - r);
    const ox = @max(qx, 0);
    const oy = @max(qy, 0);
    return @sqrt(ox * ox + oy * oy) + @min(@max(qx, qy), 0) - r;
}

/// Index of the topmost node containing world-space point `p`, if any.
pub fn nodeAt(g: *const graph.Graph, p: rl.Vector2) ?usize {
    var i = g.nodes.items.len;
    while (i > 0) {
        i -= 1; // walk backwards: last drawn = on top
        const n = g.nodes.items[i];
        const half = rl.Vector2{ .x = n.size.x / 2, .y = n.size.y / 2 };
        const d = roundedBoxSdf(p.x - n.pos.x, p.y - n.pos.y, half, cornerRadius(n.size));
        if (d <= 0) return i;
    }
    return null;
}

/// Where a ray from n's center toward `toward` leaves n's rectangle.
fn borderPoint(n: graph.Node, toward: rl.Vector2) rl.Vector2 {
    const dx = toward.x - n.pos.x;
    const dy = toward.y - n.pos.y;
    if (dx == 0 and dy == 0) return n.pos;

    // Step 1: exit point of the bounding box (same math as before). The
    // rounded shape is enitrely inside the box, so this is an upper bound.
    const inf = std.math.inf(f32);
    const tx = if (dx != 0) (n.size.x / 2) / @abs(dx) else inf;
    const ty = if (dy != 0) (n.size.y / 2) / @abs(dy) else inf;

    // Step 2: bisect between t=0 (center, inside) and t=box exit (outside
    // or on the edge) until we converge on the rounded edge.
    const half = rl.Vector2{ .x = n.size.x / 2, .y = n.size.y / 2 };
    const r = cornerRadius(n.size);
    var lo: f32 = 0;
    var hi: f32 = @min(tx, ty);
    for (0..24) |_| {
        const mid = (lo + hi) / 2;
        if (roundedBoxSdf(dx * mid, dy * mid, half, r) < 0) {
            lo = mid; // still inside the shape, move outward
        } else {
            hi = mid; // outside, move back in
        }
    }

    return .{ .x = n.pos.x + dx * hi, .y = n.pos.y + dy * hi };
}

/// Two short lines forming a "V" at `tip`, pointing along tip - from.
fn drawArrowhead(tip: rl.Vector2, from: rl.Vector2, len: f32, thick: f32, color: rl.Color) void {
    const dx = tip.x - from.x;
    const dy = tip.y - from.y;
    const d = @sqrt(dx * dx + dy * dy);
    if (d == 0) return;

    // Unit vector pointing BACK from the tip along the edge.
    const bx = -dx / d;
    const by = -dy / d;

    // Rotate it by +/- 0.45 rad (~26 degrees) to get the two barbs.
    const angle: f32 = 0.45;
    const c = @cos(angle);
    const s = @sin(angle);
    const left = rl.Vector2{
        .x = tip.x + len * (bx * c - by * s),
        .y = tip.y + len * (bx * s + by * c),
    };
    const right = rl.Vector2{
        .x = tip.x + len * (bx * c + by * s),
        .y = tip.y + len * (-bx * s + by * c),
    };
    rl.drawLineEx(tip, left, thick, color);
    rl.drawLineEx(tip, right, thick, color);
}
