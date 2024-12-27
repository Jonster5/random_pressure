const std = @import("std");
const Allocator = std.mem.Allocator;
const Tree = @import("tree.zig");

const Func = @This();
allocator: Allocator,
tree: Tree,

pub fn init(allocator: Allocator, tree_to_copy: Tree) !Func {
    const tree = try tree_to_copy.clone(allocator);
    return Func{
        .allocator = allocator,
        .tree = tree,
    };
}

pub fn deinit(self: Func) void {
    self.tree.deinit();
}

pub fn init_default(allocator: Allocator) !Func {
    const tree_to_copy = try Tree.init_default(allocator);
    return Func.init(allocator, tree_to_copy);
}

pub fn clone(self: Func, allocator: Allocator) !Func {
    return Func.init(allocator, self.tree);
}

test "init, deinit, init_default, clone" {}

pub fn eval(self: Func, input_value: f64) !f64 {
    const eval_tree_nodes = try self.allocator.alloc(Tree.Node, self.tree.nodes.len);
    @memcpy(eval_tree_nodes, self.tree.nodes);

    for (self.tree.nodes, 0..) |node, i| {
        eval_tree_nodes[i] = switch (node) {
            .Variable => Tree.Node.init_constant(input_value),
            else => eval_tree_nodes[i],
        };
    }

    return eval_tree_nodes[self.tree.root_index].eval(eval_tree_nodes);
}

test "eval" {
    const allocator = std.testing.allocator;
    const testing = std.testing;

    const test_func_1 = try Func.init_default(allocator);
    defer test_func_1.deinit();
    try testing.expect(try test_func_1.eval(10) == 10);

    const init_constant = Tree.Node.init_constant;
    const init_variable = Tree.Node.init_variable;
    const init_hyperop = Tree.Node.init_hyperop;

    const test_tree_2: []const Tree.Node = &[_]Tree.Node{
        init_variable('x'),
        init_hyperop(0, 2, 3, .Addition),
        init_constant(10.0),
        init_constant(2.0),
    };
    const test_func_2 = try Func.init(allocator, try Tree.init(allocator, test_tree_2, 1));
    defer test_func_2.deinit();
    const test_result_2: f64 = try test_func_2.eval(5.0);
    try testing.expect(test_result_2 == 13.5);
}
