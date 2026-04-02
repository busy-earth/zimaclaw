const std = @import("std");
const testing = std.testing;
const fang = @import("fang");

test "fang creates and loads issue artifact" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(root);

    const store = fang.Store.init(root);
    try store.createIssueWithId(testing.allocator, "issue-1", "First issue", "do the thing");

    var loaded = try store.loadIssue(testing.allocator, "issue-1");
    defer loaded.deinit();

    try testing.expectEqualStrings("issue-1", loaded.value.id);
    try testing.expectEqualStrings("First issue", loaded.value.title);
    try testing.expectEqualStrings("do the thing", loaded.value.prompt);
    try testing.expect(loaded.value.state == .inbox);
}

test "fang transitions issue state and updates timestamp" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(root);

    const store = fang.Store.init(root);
    try store.createIssueWithId(testing.allocator, "issue-2", "Transition me", "go");

    var before = try store.loadIssue(testing.allocator, "issue-2");
    defer before.deinit();

    try store.transitionIssue(testing.allocator, "issue-2", .planned);
    try store.transitionIssue(testing.allocator, "issue-2", .executing);

    var after = try store.loadIssue(testing.allocator, "issue-2");
    defer after.deinit();

    try testing.expect(after.value.state == .executing);
    try testing.expect(after.value.updated_at_ms >= before.value.updated_at_ms);
}

test "fang enforces review reject resend-to-planned flow" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(root);

    const store = fang.Store.init(root);
    try store.createIssueWithId(testing.allocator, "issue-4", "Review me", "go");
    try store.transitionIssue(testing.allocator, "issue-4", .planned);
    try store.transitionIssue(testing.allocator, "issue-4", .executing);
    try store.transitionIssue(testing.allocator, "issue-4", .review);
    try store.rejectIssue(testing.allocator, "issue-4", "needs narrower scope");
    try store.transitionIssue(testing.allocator, "issue-4", .planned);

    var loaded = try store.loadIssue(testing.allocator, "issue-4");
    defer loaded.deinit();
    try testing.expect(loaded.value.state == .planned);

    const invalid = store.transitionIssue(testing.allocator, "issue-4", .done);
    try testing.expectError(fang.TransitionError.InvalidTransition, invalid);
}

test "fang stores simulation and execution artifacts with timestamps" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(root);

    const store = fang.Store.init(root);
    try store.createIssueWithId(testing.allocator, "issue-5", "Artifacts", "go");

    try store.setSimulationArtifactPath(
        testing.allocator,
        "issue-5",
        ".zimaclaw/issues/issue-5/simulation/trace.json",
    );
    try store.setExecutionArtifactPath(
        testing.allocator,
        "issue-5",
        ".zimaclaw/issues/issue-5/execution/events.jsonl",
    );

    var loaded = try store.loadIssue(testing.allocator, "issue-5");
    defer loaded.deinit();

    try testing.expect(loaded.value.simulation_artifact != null);
    try testing.expectEqualStrings(
        ".zimaclaw/issues/issue-5/simulation/trace.json",
        loaded.value.simulation_artifact.?.path,
    );
    try testing.expect(loaded.value.simulation_artifact.?.recorded_at_ms > 0);

    try testing.expect(loaded.value.execution_artifact != null);
    try testing.expectEqualStrings(
        ".zimaclaw/issues/issue-5/execution/events.jsonl",
        loaded.value.execution_artifact.?.path,
    );
    try testing.expect(loaded.value.execution_artifact.?.recorded_at_ms > 0);
}

test "fang uses deterministic issue file path" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(root);

    const store = fang.Store.init(root);
    const path = try store.issueFilePath(testing.allocator, "issue-3");
    defer testing.allocator.free(path);

    const expected = try std.fs.path.join(testing.allocator, &[_][]const u8{
        root,
        ".zimaclaw",
        "issues",
        "issue-3",
        "issue.json",
    });
    defer testing.allocator.free(expected);

    try testing.expectEqualStrings(expected, path);
}

