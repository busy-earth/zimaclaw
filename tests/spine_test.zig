const std = @import("std");
const testing = std.testing;
const spine_mod = @import("spine");

test "spine emits ordered events and persists JSONL" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(root);

    const events_path = try std.fs.path.join(testing.allocator, &[_][]const u8{
        root,
        "events.jsonl",
    });
    defer testing.allocator.free(events_path);

    var spine = try spine_mod.Spine.init(testing.allocator, events_path);
    defer spine.deinit();

    _ = try spine.emit(.run_started, .{ .issue_id = "issue-1" });
    _ = try spine.emit(.issue_created, .{
        .issue_id = "issue-1",
        .detail = "created",
    });
    _ = try spine.emit(.run_finished, .{ .issue_id = "issue-1" });

    const events = spine.items();
    try testing.expectEqual(@as(usize, 3), events.len);
    try testing.expectEqual(@as(u64, 1), events[0].sequence);
    try testing.expectEqual(@as(u64, 2), events[1].sequence);
    try testing.expectEqual(@as(u64, 3), events[2].sequence);
    try testing.expect(events[0].kind == .run_started);
    try testing.expect(events[1].kind == .issue_created);
    try testing.expect(events[2].kind == .run_finished);

    const payload = try std.fs.cwd().readFileAlloc(testing.allocator, events_path, 1024 * 1024);
    defer testing.allocator.free(payload);

    var lines = std.mem.splitScalar(u8, payload, '\n');
    var non_empty_lines: usize = 0;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        non_empty_lines += 1;
    }

    try testing.expectEqual(@as(usize, 3), non_empty_lines);
}
