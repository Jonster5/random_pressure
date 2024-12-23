const std = @import("std");
const Allocator = std.mem.Allocator;

pub const NodeType = enum(u8) {
    Constant,
    Variable,
    HyperOp,
};

pub const HyperOpLevel = enum(u8) {
    Increment,
    Addition,
    Multiplication,
    Exponentiation,
};

pub const Node = union(NodeType) {
    Constant: f64,
    Variable: struct { name: u8 },
    HyperOp: struct { subject: *Node, positive_factor: *Node, negative_factor: *Node, op_level: HyperOpLevel },
};

pub const NodeTree = struct {
    arena: std.heap.ArenaAllocator,
    variable_ptrs: []*Node,

    root: *Node,

    pub fn init(child_allocator: Allocator) !NodeTree {
        var arena = std.heap.ArenaAllocator.init(child_allocator);
        const ally = arena.allocator();

        const root = try ally.create(Node);
        root.* = .{ .Variable = .{ .name = 'x' } };

        const variable_ptrs = try ally.alloc(*Node, 1);
        variable_ptrs[0] = root;

        return NodeTree{
            .arena = arena,
            .variable_ptrs = variable_ptrs,

            .root = root,
        };
    }

    pub fn deinit() void {}
};

test "init NodeTree" {}
