const std = @import("std");
const rl = @import("raylib");

pub const Node = struct {
    /// Null-terminated because raylib's text functions expect C strings.
    /// A Zig string literal already has this type.
    label: [:0]const u8,
    /// Center of the node, in WORLD coordinates.
    pos: rl.Vector2,
    /// Filled in by the render.measureNodes() once we know the text width.
    size: rl.Vector2 = .{ .x = 0, .y = 0 },
    /// Scratch space for layout: the net force on this node during a step.
    disp: rl.Vector2 = .{ .x = 0, .y = 0 },
};

pub const Edge = struct {
    from: usize, // index into Graph.nodes
    to: usize,
};

pub const Graph = struct {
    nodes: std.ArrayList(Node) = .empty,
    edges: std.ArrayList(Edge) = .empty,
    directed: bool = true,

    pub fn deinit(self: *Graph, gpa: std.mem.Allocator) void {
        for (self.nodes.items) |n| gpa.free(n.label);
        self.nodes.deinit(gpa);
        self.edges.deinit(gpa);
    }

    /// Remove everything but keep the allocated capacity, ready for a new graph.
    pub fn clear(self: *Graph, gpa: std.mem.Allocator) void {
        for (self.nodes.items) |n| gpa.free(n.label);
        self.nodes.clearRetainingCapacity();
        self.edges.clearRetainingCapacity();
    }

    /// Copies `label`; the graph owns the copy. Returns the new node's index.
    pub fn addNode(
        self: *Graph,
        gpa: std.mem.Allocator,
        label: []const u8,
        pos: rl.Vector2,
    ) !usize {
        const owned = try gpa.dupeZ(u8, label);
        errdefer gpa.free(owned);
        try self.nodes.append(gpa, .{ .label = owned, .pos = pos });
        return self.nodes.items.len - 1;
    }

    pub fn setLabel(self: *Graph, gpa: std.mem.Allocator, i: usize, label: []const u8) !void {
        const owned = try gpa.dupeZ(u8, label);
        gpa.free(self.nodes.items[i].label);
        self.nodes.items[i].label = owned;
    }

    pub fn addEdge(self: *Graph, gpa: std.mem.Allocator, from: usize, to: usize) !void {
        try self.edges.append(gpa, .{ .from = from, .to = to });
    }
};
