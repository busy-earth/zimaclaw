const std = @import("std");
const claw = @import("claw.zig");

test "imports compile" {
    _ = claw;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    try claw.run(allocator, args);
}
