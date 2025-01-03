const std = @import("std");
const Allocator = std.mem.Allocator;
const math = std.math;

const Tree = @This();
allocator: Allocator,
nodes: []Node,

pub fn init(allocator: Allocator, nodes_to_copy: []const Node) !Tree {
    const nodes = try allocator.alloc(Node, nodes_to_copy.len);
    @memcpy(nodes, nodes_to_copy);

    return Tree{
        .allocator = allocator,
        .nodes = nodes,
    };
}

pub fn init_default(allocator: Allocator) !Tree {
    const default_nodes = comptime [_]Node{.{ .Variable = .{ .name = 'x' } }};

    return Tree.init(allocator, &default_nodes);
}

pub fn deinit(self: Tree) void {
    self.allocator.free(self.nodes);
}

pub fn clone(self: Tree, allocator: Allocator) !Tree {
    return Tree.init(allocator, self.nodes);
}

test "init, deinit, init_default, clone" {
    const allocator = std.testing.allocator;

    const tests = .{
        [_]Tree.Node{Node.init_variable('x')},
        [_]Tree.Node{
            Node.init_hyperop(0, 2, 3, .Sum),
            Node.init_variable('x'),
            Node.init_constant(5),
            Node.init_constant(1),
        },
    };

    inline for (tests) |nodes| {
        var test_tree = try Tree.init(allocator, &nodes);
        defer test_tree.deinit();
    }

    const test_default = try Tree.init_default(allocator);
    defer test_default.deinit();
    try std.testing.expect(test_default.nodes.len == 1);
    try std.testing.expect(test_default.nodes[0].Variable.name == 'x');
}

pub const Node = union(Type) {
    pub const Type = enum(u8) {
        Constant,
        Variable,
        HyperOp,
    };

    Constant: Constant,
    Variable: Variable,
    HyperOp: HyperOp,

    pub const Constant = struct {
        value: f64,

        const EvalError = error{IsNaN};

        pub fn eval(self: Constant, nodes: []const Node) Constant.EvalError!f64 {
            _ = nodes;

            if (math.isNan(self.value)) return error.IsNaN;

            return self.value;
        }
    };
    pub const Variable = struct {
        name: u8,

        const EvalError = error{DirectVariableEval};

        pub fn eval(self: Variable, nodes: []const Node) Variable.EvalError!f64 {
            _ = self;
            _ = nodes;
            return error.DirectVariableEval;
        }
    };
    pub const HyperOp = struct {
        subject_index: usize,
        positive_factor_index: usize,
        negative_factor_index: usize,
        op_level: Level,

        pub const Level = enum(u8) {
            Sum,
            Product,
            Power,
        };

        const EvalError: type = error{ DivisionByZero, IsNaN };

        pub fn eval(self: HyperOp, nodes: []const Node) Node.EvalError!f64 {
            const sb: f64 = try nodes[self.subject_index].eval(nodes);
            const pf: f64 = try nodes[self.positive_factor_index].eval(nodes);
            const nf: f64 = try nodes[self.negative_factor_index].eval(nodes);

            const result: f64 = switch (self.op_level) {
                .Sum => sb + pf - nf,
                .Product => blk: {
                    const factor_combination = if (nf == 0) return error.DivisionByZero else pf / nf;
                    break :blk sb * factor_combination;
                },
                .Power => blk: {
                    const factor_combination = if (nf == 0) return error.DivisionByZero else pf / nf;
                    break :blk math.pow(f64, sb, factor_combination);
                },
            };

            if (math.isNan(result)) return error.IsNaN;

            return result;
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
                .subject_index = subject,
                .positive_factor_index = positive_factor,
                .negative_factor_index = negative_factor,
                .op_level = op_level,
            },
        };
    }

    pub const EvalError = HyperOp.EvalError || Constant.EvalError || Variable.EvalError;

    pub fn eval(self: Node, nodes: []const Node) Node.EvalError!f64 {
        return switch (self) {
            inline else => |node| node.eval(nodes),
        };
    }
};
