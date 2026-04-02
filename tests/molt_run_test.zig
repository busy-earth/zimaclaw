const std = @import("std");
const testing = std.testing;
const claw = @import("claw");

test "molt run drives issue to review with event trail" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(root);

    const pi_script = "read line; echo '{\"kind\":\"pi_event\",\"payload\":\"ok\"}'";
    const pi_argv = &[_][]const u8{ "sh", "-c", pi_script };

    var run_result = try claw.runMoltWithOptions(testing.allocator, "ship it", .{
        .root_path = root,
        .drive_options = .{ .command_argv = pi_argv },
        .steer_options = .{ .emacsclient_cmd = "true" },
    });
    defer run_result.deinit(testing.allocator);

    try testing.expect(run_result.final_state == .review);

    const store = claw.fang.Store.init(root);
    var loaded = try store.loadIssue(testing.allocator, run_result.issue_id);
    defer loaded.deinit();

    try testing.expect(loaded.value.state == .review);
    try testing.expect(loaded.value.execution_artifact != null);
    try testing.expect(loaded.value.execution_artifact.?.recorded_at_ms > 0);

    const event_payload = try std.fs.cwd().readFileAlloc(
        testing.allocator,
        loaded.value.execution_artifact.?.path,
        1024 * 1024,
    );
    defer testing.allocator.free(event_payload);

    const run_started_at = std.mem.indexOf(u8, event_payload, "\"kind\":\"run_started\"") orelse return error.TestExpectedRunStarted;
    const issue_created_at = std.mem.indexOf(u8, event_payload, "\"kind\":\"issue_created\"") orelse return error.TestExpectedIssueCreated;
    const drive_spawned_at = std.mem.indexOf(u8, event_payload, "\"kind\":\"drive_spawned\"") orelse return error.TestExpectedDriveSpawned;
    const pi_event_received_at = std.mem.indexOf(u8, event_payload, "\"kind\":\"pi_event_received\"") orelse return error.TestExpectedPiEventReceived;
    const steer_call_attempted_at = std.mem.indexOf(u8, event_payload, "\"kind\":\"steer_call_attempted\"") orelse return error.TestExpectedSteerCallAttempted;
    const run_finished_at = std.mem.indexOf(u8, event_payload, "\"kind\":\"run_finished\"") orelse return error.TestExpectedRunFinished;

    try testing.expect(run_started_at < issue_created_at);
    try testing.expect(issue_created_at < drive_spawned_at);
    try testing.expect(drive_spawned_at < pi_event_received_at);
    try testing.expect(pi_event_received_at < steer_call_attempted_at);
    try testing.expect(steer_call_attempted_at < run_finished_at);
}

test "molt run marks issue failed when steer is unavailable" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(root);

    const pi_script = "read line; echo '{\"kind\":\"pi_event\",\"payload\":\"ok\"}'";
    const pi_argv = &[_][]const u8{ "sh", "-c", pi_script };

    var run_result = try claw.runMoltWithOptions(testing.allocator, "ship it", .{
        .root_path = root,
        .drive_options = .{ .command_argv = pi_argv },
        .steer_options = .{ .emacsclient_cmd = "/__zimaclaw__/missing/emacsclient" },
    });
    defer run_result.deinit(testing.allocator);

    try testing.expect(run_result.final_state == .failed);

    const store = claw.fang.Store.init(root);
    var loaded = try store.loadIssue(testing.allocator, run_result.issue_id);
    defer loaded.deinit();

    try testing.expect(loaded.value.state == .failed);
    try testing.expect(loaded.value.execution_artifact != null);
    try testing.expect(loaded.value.execution_artifact.?.recorded_at_ms > 0);

    const event_payload = try std.fs.cwd().readFileAlloc(
        testing.allocator,
        loaded.value.execution_artifact.?.path,
        1024 * 1024,
    );
    defer testing.allocator.free(event_payload);

    _ = std.mem.indexOf(u8, event_payload, "\"kind\":\"run_failed\"") orelse return error.TestExpectedRunFailed;
}
