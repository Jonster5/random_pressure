const std = @import("std");
const Allocator = std.mem.Allocator;

const Tree = @This();
allocator: Allocator,
nodes: []Node,
root_index: usize,

pub fn init(allocator: Allocator, nodes_to_copy: []const Node, root_index: usize) !Tree {
    const nodes = try allocator.alloc(Node, nodes_to_copy.len);
    @memcpy(nodes, nodes_to_copy);

    if (root_index >= nodes.len) {
        return error.RootIndexOutOfBounds;
    }

    return Tree{
        .allocator = allocator,
        .nodes = nodes,
        .root_index = root_index,
    };
}

pub fn init_default(allocator: Allocator) !Tree {
    const nodes = comptime [_]Node{.{ .Variable = .{ .name = 'x' } }};
    return Tree.init(allocator, &nodes, 0);
}

pub fn deinit(self: Tree) void {
    self.allocator.free(self.nodes);
}

pub fn clone(self: Tree, allocator: Allocator) !Tree {
    return Tree.init(allocator, self.nodes, self.root_index);
}

test "init, deinit, init_default, clone" {
    const allocator = std.testing.allocator;

    const tests = .{
        [_]Tree.Node{Node.init_variable('x')},
        [_]Tree.Node{
            Node.init_variable('x'),
            Node.init_hyperop(0, 2, 3, .Addition),
            Node.init_constant(0),
            Node.init_constant(0),
        },
    };

    inline for (tests) |nodes| {
        var test_tree = try Tree.init(allocator, &nodes, 0);
        defer test_tree.deinit();
    }

    const test_default = try Tree.init_default(allocator);
    defer test_default.deinit();
    try std.testing.expect(test_default.nodes.len == 1);
    try std.testing.expect(test_default.nodes[0].Variable.name == 'x');
}

pub const Node = union(Type) {
    const Type = enum(u8) {
        Constant,
        Variable,
        HyperOp,
    };

    Constant: Constant,
    Variable: Variable,
    HyperOp: HyperOp,

    pub const Constant = struct {
        value: f64,

        pub fn eval(self: Constant, nodes: []const Node) f64 {
            _ = nodes;
            return self.value;
        }
    };
    pub const Variable = struct {
        name: u8,

        pub fn eval(self: Variable, nodes: []const Node) f64 {
            _ = self;
            _ = nodes;
            @compileError("This shouldn't ever be called");
        }
    };
    pub const HyperOp = struct {
        subject: usize,
        positive_factor: usize,
        negative_factor: usize,
        op_level: Level,

        pub const Level = enum(u8) {
            Addition,
            Multiplication,
            Exponentiation,
        };

        pub fn eval(self: HyperOp, nodes: []const Node) f64 {
            const sb: f64 = nodes[self.subject].eval(nodes);
            const pf: f64 = nodes[self.positive_factor].eval(nodes);
            const nf: f64 = nodes[self.negative_factor].eval(nodes);

            return switch (self.op_level) {
                .Addition => sb + (pf - nf),
                .Multiplication => sb * (pf / nf),
                .Exponentiation => std.math.pow(f64, sb, try std.math.divTrunc(pf, nf)),
            };
        }
    };

    pub fn init_constant(value: f64) Node {
        return Node{ .Constant = Node.Constant{ .value = value } };
    }

    pub fn init_variable(name: u8) Node {
        return Node{ .Variable = Node.Variable{ .name = name } };
    }

    pub fn init_hyperop(subject: usize, positive_factor: usize, negative_factor: usize, op_level: HyperOp.Level) Node {
        return Node{
            .HyperOp = Node.HyperOp{
                .subject = subject,
                .positive_factor = positive_factor,
                .negative_factor = negative_factor,
                .op_level = op_level,
            },
        };
    }

    pub fn eval(self: Node, nodes: []const Node) f64 {
        return switch (self) {
            .Constant => |node| node.eval(nodes),
            .Variable => |node| node.eval(nodes),
            .HyperOp => |node| node.eval(nodes),
        };
    }
};
