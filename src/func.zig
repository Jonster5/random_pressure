const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const Tree = @import("tree.zig");
const mm = @import("mistamunsta.zig");

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
    defer tree_to_copy.deinit();
    return Func.init(allocator, tree_to_copy);
}

pub fn clone(self: Func, allocator: Allocator) !Func {
    return Func.init(allocator, self.tree);
}

test "Func init, deinit, init_default, clone" {
    const allocator = std.testing.allocator;
    const init_constant = Tree.Node.init_constant;
    const init_variable = Tree.Node.init_variable;
    const init_hyperop = Tree.Node.init_hyperop;

    const test_tree_1 = try Tree.init(
        allocator,
        &[_]Tree.Node{
            init_hyperop(0, 2, 3, .Sum),
            init_variable('x'),
            init_constant(2.0),
            init_constant(5.0),
        },
    );
    defer test_tree_1.deinit();
    const test_1 = try Func.init(allocator, test_tree_1);
    defer test_1.deinit();
    try testing.expect(test_1.tree.nodes.len == test_tree_1.nodes.len);
    try testing.expect(test_1.tree.nodes.ptr != test_tree_1.nodes.ptr);

    const test_tree_2 = try Tree.init_default(allocator);
    defer test_tree_2.deinit();
    const test_2 = try Func.init_default(allocator);
    defer test_2.deinit();
    try testing.expect(test_2.tree.nodes.len == test_tree_2.nodes.len);
    try testing.expect(test_2.tree.nodes.ptr != test_tree_2.nodes.ptr);
}

pub const EvalError = error{OutOfMemory} || Tree.Node.EvalError;

pub fn eval(self: Func, input_value: f64) EvalError!f64 {
    const eval_tree_nodes = try self.allocator.alloc(Tree.Node, self.tree.nodes.len);
    defer self.allocator.free(eval_tree_nodes);
    @memcpy(eval_tree_nodes, self.tree.nodes);

    for (self.tree.nodes, 0..) |node, i| {
        eval_tree_nodes[i] = switch (node) {
            .Variable => Tree.Node.init_constant(input_value),
            else => eval_tree_nodes[i],
        };
    }

    const eval_tree_root = eval_tree_nodes[0];

    return eval_tree_root.eval(eval_tree_nodes);
}

test "eval" {
    const allocator = std.testing.allocator;
    const init_constant = Tree.Node.init_constant;
    const init_variable = Tree.Node.init_variable;
    const init_hyperop = Tree.Node.init_hyperop;

    const test_func_1 = try Func.init_default(allocator);
    defer test_func_1.deinit();
    const test_result_1 = try test_func_1.eval(10);
    try testing.expect(test_result_1 == 10);

    const test_tree_2: Tree = try Tree.init(
        allocator,
        &[_]Tree.Node{
            init_hyperop(1, 2, 3, .Sum),
            init_variable('x'),
            init_constant(10.0),
            init_constant(2.0),
        },
    );
    defer test_tree_2.deinit();
    const test_func_2 = try Func.init(allocator, test_tree_2);
    defer test_func_2.deinit();
    const test_result_2 = try test_func_2.eval(5.0);
    try testing.expect(test_result_2 == 13.0);
}
