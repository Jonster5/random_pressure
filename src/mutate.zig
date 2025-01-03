const std = @import("std");
const Allocator = std.mem.Allocator;
const mm = @import("mistamunsta.zig");
const Tree = @import("tree.zig");
const Func = @import("func.zig");
const testing = std.testing;

//  The odds of any Node in the function tree changing. They are left vague
//  on purpose because they will likely be changed a lot.
//  Same means the no change, and for example Constant -> Constant just means
//  changing the value of that constant. By what rules it can be changed by
//  idk right now.
//
//  Node                High Chance     Med Chance      Low Chance
//
//  Constant            Constant        Same            Variable
//  Variable            Same            HyperOp[1]      Constant
//  HyperOp[i]          Same            HyperOp[i+1]    HyperOp[i-1]

/// Rules for mutation
///
/// Random u8 is generated for each node to determine how it will change.
/// Set the chance properties to the maximum value the number can be.
pub const Options = struct {
    high_chance: u8,
    med_chance: u8,
    low_chance: u8,

    constant: ChangeRules,
    variable: ChangeRules,
    hyperop: ChangeRules,

    pub const ChangeRules = struct { ChangeType, ChangeType, ChangeType };
    pub const ChangeType = enum {
        NoChange,
        IntoVariable,
        IntoConstant,
        IntoHyperOp,
        ConstantValue,
        HyperOpLevelUp,
        HyperOpLevelDown,
    };
};

pub const default_options: Options = Options{
    .high_chance = 128,
    .med_chance = 224,
    .low_chance = 240,
    .constant = .{ .ConstantValue, .NoChange, .IntoVariable },
    .variable = .{ .NoChange, .IntoHyperOp, .IntoConstant },
    .hyperop = .{ .NoChange, .HyperOpLevelUp, .HyperOpLevelDown },
};

const MutationError = anyerror;

pub fn mutate_tree(allocator: Allocator, random: std.Random, options: Options, parent_tree: Tree) MutationError!Tree {
    const init_constant = Tree.Node.init_constant;
    const init_variable = Tree.Node.init_variable;
    const init_hyperop = Tree.Node.init_hyperop;

    var opt_nodes_list = try std.ArrayList(?Tree.Node).initCapacity(allocator, parent_tree.nodes.len);
    try opt_nodes_list.appendNTimes(null, parent_tree.nodes.len);
    for (0..parent_tree.nodes.len) |i| opt_nodes_list.items[i] = parent_tree.nodes[i];
    defer opt_nodes_list.deinit();

    // Potential problem where a branch node converts into a leaf node which may decrease leaf node mutations.
    for (0..parent_tree.nodes.len) |i| {
        if (opt_nodes_list.items[i] == null) continue;
        const parent_node = parent_tree.nodes[i];

        const change_rules = switch (parent_node) {
            .Constant => options.constant,
            .Variable => options.variable,
            .HyperOp => options.hyperop,
        };
        const chance = random.int(u8);
        const change_type: Options.ChangeType = if (chance < options.high_chance) change_rules[0] else if (chance < options.med_chance) change_rules[1] else if (chance < options.low_chance) change_rules[2] else .NoChange;

        // Branch nodes need to have their leafs cut when before being changed.
        // Also conveniently the parent node type can be jotted down here.
        const parent_node_type: Tree.Node.Type = switch (parent_node) {
            .HyperOp => |h_node| blk: {
                opt_nodes_list.items[h_node.subject_index] = null;
                opt_nodes_list.items[h_node.positive_factor_index] = null;
                opt_nodes_list.items[h_node.negative_factor_index] = null;

                break :blk .HyperOp;
            },
            .Constant => .Constant,
            .Variable => .Variable,
        };
        // each switch branch should use the parent node to alter the matching child node,
        // and append any new nodes to the end of the list.
        switch (change_type) {
            .NoChange => continue,
            .IntoConstant => {
                if (parent_node_type == .Constant) return error.InvalidChangeType;

                opt_nodes_list.items[i] = init_constant(1.0);
            },
            .IntoVariable => {
                if (parent_node_type == .Variable) return error.InvalidChangeType;

                opt_nodes_list.items[i] = init_variable('x');
            },
            .IntoHyperOp => {
                if (parent_node_type == .HyperOp) return error.InvalidChangeType;

                const index = opt_nodes_list.items.len;

                try opt_nodes_list.append(parent_node);
                try opt_nodes_list.append(init_constant(1));
                try opt_nodes_list.append(init_constant(0));

                opt_nodes_list.items[i] = init_hyperop(index, index + 1, index + 2, .Sum);
            },
            .ConstantValue => {
                if (parent_node_type != .Constant) return error.InvalidChangeType;

                const random_value: f64 = random.floatExp(f64);
                const random_sign: f64 = if (random.boolean()) 1 else -1;
                const previous_value: f64 = parent_node.Constant.value;

                opt_nodes_list.items[i] = init_constant(previous_value + random_value * random_sign);
            },
            .HyperOpLevelUp => {
                if (parent_node_type != .HyperOp) return error.InvalidChangeType;

                opt_nodes_list.items[i].?.HyperOp.op_level = switch (opt_nodes_list.items[i].?.HyperOp.op_level) {
                    .Sum => .Product,
                    .Product => .Power,
                    .Power => .Power,
                };
            },
            .HyperOpLevelDown => {
                if (parent_node_type != .HyperOp) return error.InvalidChangeType;

                opt_nodes_list.items[i].?.HyperOp.op_level = switch (opt_nodes_list.items[i].?.HyperOp.op_level) {
                    .Sum => .Sum,
                    .Product => .Sum,
                    .Power => .Product,
                };
            },
        }
    }

    const opt_nodes = try allocator.dupe(?Tree.Node, opt_nodes_list.items);
    defer allocator.free(opt_nodes);

    // The list needs to be culled of any nulls in the event that a node with subnodes is changed into a leaf node.
    // Cull it by starting from the tree root and rebuilding the list from the ground up.

    // The length of the final result is equal to the length of
    // the post-mutation list - the amount of nulls in that list.
    const child_slice_len = opt_nodes.len - blk: {
        var null_count: usize = 0;
        for (opt_nodes) |opt_node| {
            if (opt_node == null) null_count += 1;
        }
        break :blk null_count;
    };

    // This will be the final result
    const child_slice = try allocator.alloc(Tree.Node, child_slice_len);
    defer allocator.free(child_slice);

    // The queue won't ever need more memory than the size of the child_opt_nodes - the amount of nulls,
    // so it can use this buffer instead of managing its own memory.
    const node_queue_buffer = try allocator.alloc(Tree.Node, child_slice_len);
    defer allocator.free(node_queue_buffer);

    const Queue = std.fifo.LinearFifo(Tree.Node, .Slice);
    var node_queue: Queue = Queue.init(node_queue_buffer);
    defer node_queue.deinit();
    try node_queue.writeItem(opt_nodes[0].?);

    var index: usize = 0;
    while (node_queue.readItem()) |head_node| {
        const current_node_ptr = &child_slice[index];
        current_node_ptr.* = head_node;
        index += 1;

        // deal with index changes and add sub nodes to the queue
        switch (head_node) {
            .Constant, .Variable => continue,
            .HyperOp => |hyperop_node| {
                const sb_node = opt_nodes[hyperop_node.subject_index].?;
                const pf_node = opt_nodes[hyperop_node.positive_factor_index].?;
                const nf_node = opt_nodes[hyperop_node.negative_factor_index].?;

                // The correct index for each node off the branch will be the current
                // index + how many items are ahead of node in the queue + 1
                const offset: usize = index + node_queue.count - 1;
                try node_queue.writeItem(sb_node);
                current_node_ptr.HyperOp.subject_index = offset + 1;
                try node_queue.writeItem(pf_node);
                current_node_ptr.HyperOp.positive_factor_index = offset + 2;
                try node_queue.writeItem(nf_node);
                current_node_ptr.HyperOp.negative_factor_index = offset + 3;
            },
        }
    }

    return Tree.init(allocator, child_slice);
}

test "mutate_tree" {
    const allocator = std.testing.allocator;
    var rng = std.Random.DefaultPrng.init(0);
    const random = rng.random();

    const tree_1 = try Tree.init_default(allocator);
    defer tree_1.deinit();

    const func_1 = try Func.init(allocator, tree_1);
    defer func_1.deinit();
    const output_1 = try func_1.eval(25);
    std.debug.print("Test Result: {d}\n", .{output_1});

    const tree_2 = try mutate_tree(allocator, random, default_options, func_1.tree);
    defer tree_2.deinit();

    const func_2 = try Func.init(allocator, tree_2);
    defer func_2.deinit();
    const output_2 = try func_1.eval(25);
    std.debug.print("Test Result: {d}\n", .{output_2});

    const tree_3 = try mutate_tree(allocator, random, default_options, func_2.tree);
    defer tree_3.deinit();

    const func_3 = try Func.init(allocator, tree_3);
    defer func_3.deinit();
    const output_3 = try func_2.eval(25);
    std.debug.print("Test Result: {d}\n", .{output_3});
}
