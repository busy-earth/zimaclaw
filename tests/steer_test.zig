const std = @import("std");
const testing = std.testing;
const steer = @import("steer");

test "steer returns typed unavailable failure when emacsclient is missing" {
    var result = steer.execute(testing.allocator, .{
        .eval = "(+ 1 2)",
    }, .{
        .emacsclient_cmd = "/__zimaclaw__/missing/emacsclient",
    });
    defer result.deinit(testing.allocator);

    switch (result) {
        .err => |failure| {
            try testing.expect(failure.kind == .emacsclient_unavailable);
        },
        .ok => {
            try testing.expect(false);
        },
    }
}
