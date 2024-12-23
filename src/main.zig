const std = @import("std");
const node = @import("./tree.zig");

pub fn main() !void {}

test {
    std.testing.refAllDeclsRecursive();
}
