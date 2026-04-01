const std = @import("std");
const testing = std.testing;
const drive_jsonl = @import("drive_jsonl");

test "drive_jsonl writes one JSON object per line" {
    var buffer = std.ArrayList(u8).init(testing.allocator);
    defer buffer.deinit();

    try drive_jsonl.writeJsonLine(buffer.writer(), .{
        .kind = "pi_event",
        .payload = "ok",
    });

    try testing.expect(buffer.items.len > 0);
    try testing.expect(buffer.items[buffer.items.len - 1] == '\n');
}

test "drive_jsonl parses a valid event line" {
    var parsed = try drive_jsonl.parseEventLine(testing.allocator, "{\"kind\":\"pi_event\",\"payload\":\"ok\"}");
    defer parsed.deinit();

    const Event = struct {
        kind: []const u8,
        payload: ?[]const u8 = null,
    };

    var typed = try std.json.parseFromValue(Event, testing.allocator, parsed.value, .{
        .ignore_unknown_fields = true,
    });
    defer typed.deinit();

    try testing.expectEqualStrings("pi_event", typed.value.kind);
    try testing.expectEqualStrings("ok", typed.value.payload.?);
}

test "drive_jsonl rejects embedded newline input" {
    try testing.expectError(
        error.EmbeddedNewline,
        drive_jsonl.parseEventLine(testing.allocator, "{\"kind\":\"x\"}\n{\"kind\":\"y\"}"),
    );
}
