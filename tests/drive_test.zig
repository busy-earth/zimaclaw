const std = @import("std");
const testing = std.testing;
const drive = @import("drive");

test "drive exchanges one request and one response over JSONL" {
    const script =
        "read line; echo '{\"kind\":\"pi_event\",\"payload\":\"ok\"}'";
    const argv = &[_][]const u8{ "sh", "-c", script };

    var result = try drive.runWithOptions(testing.allocator, .{
        .prompt = "hello",
    }, .{
        .command_argv = argv,
    });
    defer result.deinit(testing.allocator);

    try testing.expectEqualStrings("pi_event", result.response.kind);
    try testing.expectEqualStrings("ok", result.response.payload.?);
}

test "drive maps missing command binary to PiUnavailable" {
    const argv = &[_][]const u8{ "/__zimaclaw__/missing/pi" };

    try testing.expectError(
        error.PiUnavailable,
        drive.runWithOptions(testing.allocator, .{
            .prompt = "hello",
        }, .{
            .command_argv = argv,
        }),
    );
}

test "drive returns InvalidResponse for malformed JSONL output" {
    const script = "read line; echo 'not-json'";
    const argv = &[_][]const u8{ "sh", "-c", script };

    try testing.expectError(
        error.InvalidResponse,
        drive.runWithOptions(testing.allocator, .{
            .prompt = "hello",
        }, .{
            .command_argv = argv,
        }),
    );
}

test "drive returns NoResponse when child emits nothing" {
    const script = "read line > /dev/null";
    const argv = &[_][]const u8{ "sh", "-c", script };

    try testing.expectError(
        error.NoResponse,
        drive.runWithOptions(testing.allocator, .{
            .prompt = "hello",
        }, .{
            .command_argv = argv,
        }),
    );
}

test "drive returns ProcessExitFailure when child exits non-zero" {
    const script = "read line; echo '{\"kind\":\"pi_event\"}'; exit 7";
    const argv = &[_][]const u8{ "sh", "-c", script };

    try testing.expectError(
        error.ProcessExitFailure,
        drive.runWithOptions(testing.allocator, .{
            .prompt = "hello",
        }, .{
            .command_argv = argv,
        }),
    );
}

test "drive can surface OutOfMemory under constrained allocator" {
    const script =
        "read line; echo '{\"kind\":\"pi_event\",\"payload\":\"0123456789012345678901234567890123456789\"}'";
    const argv = &[_][]const u8{ "sh", "-c", script };

    var saw_oom = false;
    var fail_index: usize = 0;
    while (fail_index < 512) : (fail_index += 1) {
        var failing = std.testing.FailingAllocator.init(testing.allocator, .{
            .fail_index = fail_index,
        });
        const allocator = failing.allocator();

        var result = drive.runWithOptions(allocator, .{
            .prompt = "hello",
        }, .{
            .command_argv = argv,
        }) catch |err| switch (err) {
            error.OutOfMemory => {
                saw_oom = true;
                break;
            },
            error.SpawnFailed => continue,
            else => continue,
        };
        result.deinit(allocator);
    }

    try testing.expect(saw_oom);
}
