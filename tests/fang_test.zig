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

    try store.transitionIssue(testing.allocator, "issue-2", .executing);

    var after = try store.loadIssue(testing.allocator, "issue-2");
    defer after.deinit();

    try testing.expect(after.value.state == .executing);
    try testing.expect(after.value.updated_at_ms >= before.value.updated_at_ms);
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
