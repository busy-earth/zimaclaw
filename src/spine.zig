const std = @import("std");

pub const EventKind = enum {
    run_started,
    issue_created,
    drive_spawned,
    pi_event_received,
    steer_call_attempted,
    run_finished,
    run_failed,
};

pub const Event = struct {
    sequence: u64,
    timestamp_ms: i64,
    kind: EventKind,
    issue_id: ?[]const u8 = null,
    detail: ?[]const u8 = null,
};

pub const EmitOptions = struct {
    issue_id: ?[]const u8 = null,
    detail: ?[]const u8 = null,
};

pub const Spine = struct {
    allocator: std.mem.Allocator,
    events: std.ArrayList(Event),
    next_sequence: u64,
    jsonl_path: ?[]u8,

    pub fn init(allocator: std.mem.Allocator, jsonl_path: ?[]const u8) !Spine {
        return .{
            .allocator = allocator,
            .events = std.ArrayList(Event).init(allocator),
            .next_sequence = 1,
            .jsonl_path = if (jsonl_path) |path| try allocator.dupe(u8, path) else null,
        };
    }

    pub fn deinit(self: *Spine) void {
        for (self.events.items) |event| {
            if (event.issue_id) |issue_id| self.allocator.free(issue_id);
            if (event.detail) |detail| self.allocator.free(detail);
        }
        self.events.deinit();
        if (self.jsonl_path) |path| self.allocator.free(path);
    }

    pub fn emit(self: *Spine, kind: EventKind, options: EmitOptions) !Event {
        const event = Event{
            .sequence = self.next_sequence,
            .timestamp_ms = std.time.milliTimestamp(),
            .kind = kind,
            .issue_id = if (options.issue_id) |issue_id| try self.allocator.dupe(u8, issue_id) else null,
            .detail = if (options.detail) |detail| try self.allocator.dupe(u8, detail) else null,
        };
        self.next_sequence += 1;

        try self.events.append(event);
        try self.appendToDisk(event);
        return event;
    }

    pub fn items(self: *const Spine) []const Event {
        return self.events.items;
    }

    pub fn writeJsonl(self: *const Spine, writer: anytype) !void {
        for (self.events.items) |event| {
            try std.json.stringify(event, .{}, writer);
            try writer.writeByte('\n');
        }
    }

    fn appendToDisk(self: *const Spine, event: Event) !void {
        const path = self.jsonl_path orelse return;

        var file = std.fs.cwd().openFile(path, .{ .mode = .write_only }) catch |err| switch (err) {
            error.FileNotFound => try std.fs.cwd().createFile(path, .{ .truncate = false }),
            else => return err,
        };
        defer file.close();

        try file.seekFromEnd(0);
        try std.json.stringify(event, .{}, file.writer());
        try file.writer().writeByte('\n');
    }
};
