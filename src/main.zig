const std = @import("std");
const rl = @import("raylib");
const Canvas = @import("canvas.zig").Canvas;
const Interaction = @import("interact.zig").Interaction;
const graph = @import("graph.zig");
const render = @import("render.zig");
const dot = @import("dot.zig");
const layout = @import("layout.zig");

/// Replace the contents of `g` with the graph in the DOT file at `path`.
fn loadGraph(gpa: std.mem.Allocator, path: [:0]const u8, g: *graph.Graph) void {
    g.clear(gpa);
    {
        const text = rl.loadFileText(path);
        defer rl.unloadFileText(text);
        dot.parse(gpa, text, g) catch |err| {
            std.debug.print("could not parse {s}: {s}\n", .{ path, @errorName(err) });
        };
        layout.circle(g);
        render.measureNodes(g);
    }
}

pub fn main() !void {
    // An allocator that reports leaks when deinit'd. Useful while learning.
    var debug_alloc: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_alloc.deinit();
    const gpa = debug_alloc.allocator();

    rl.setConfigFlags(.{ .window_resizable = true, .msaa_4x_hint = true });
    rl.initWindow(1280, 720, "graphs");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    var canvas = Canvas.init();
    var interaction = Interaction{};
    var force = layout.Force{};

    var g: graph.Graph = .{};
    defer g.deinit(gpa);
    loadGraph(gpa, "graph.dot", &g);

    while (!rl.windowShouldClose()) {
        // Files dropped onto the window: load the first one.
        if (rl.isFileDropped()) {
            const files = rl.loadDroppedFiles();
            defer rl.unloadDroppedFiles(files);
            if (files.count > 0) {
                loadGraph(gpa, std.mem.span(files.paths[0]), &g);
                interaction = .{}; // old node indices are meaningless now
                force = .{}; // full heat: lay the new graph out from scratch
            }
        }

        // R: scramble back to the circle and re-run the layout.
        if (rl.isKeyPressed(.r)) {
            layout.circle(&g);
            force = .{};
        }

        canvas.update();
        interaction.update(&g, canvas.camera);

        if (interaction.dragging) force.reheat(0.15);
        force.step(&g, if (interaction.dragging) interaction.selected else null);

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.init(250, 250, 252, 255));

        rl.beginMode2D(canvas.camera);
        canvas.drawGrid();
        render.drawGraph(&g, canvas.camera.zoom, interaction.selected);
        rl.endMode2D();

        // Screen-space UI (unaffected by camera).
        const mouseDelta = rl.getMouseDelta();
        rl.drawText(
            rl.textFormat("mid:%d  left:%d  space:%d  delta:(%.0f, %.0f)", .{
                @as(c_int, @intFromBool(rl.isMouseButtonDown(.middle))),
                @as(c_int, @intFromBool(rl.isMouseButtonDown(.left))),
                @as(c_int, @intFromBool(rl.isKeyDown(.space))),
                mouseDelta.x,
                mouseDelta.y,
            }),
            10,
            40,
            20,
            rl.Color.dark_gray,
        );
        rl.drawFPS(10, 10);
        rl.drawText("Drop a .dot file to load  |  R: re-layout", 10, 34, 16, rl.Color.gray);
    }
}
