const std = @import("std");
pub const fang = @import("fang.zig");
const drive = @import("drive.zig");
const steer = @import("steer.zig");
const spine_mod = @import("spine.zig");

pub const MoltRunOptions = struct {
    root_path: []const u8 = ".",
    drive_options: drive.Options = .{},
    steer_options: steer.Options = .{},
    steer_eval: []const u8 = "(+ 1 1)",
};

pub const MoltRunResult = struct {
    issue_id: []u8,
    final_state: fang.IssueState,

    pub fn deinit(self: *MoltRunResult, allocator: std.mem.Allocator) void {
        allocator.free(self.issue_id);
    }
};

pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 2) {
        try printUsage();
        return;
    }

    if (std.mem.eql(u8, args[1], "issue")) {
        try runIssue(allocator, args);
        return;
    }

    if (std.mem.eql(u8, args[1], "molt")) {
        try runMolt(allocator, args);
        return;
    }

    try printUsage();
}

fn printUsage() !void {
    const out = std.io.getStdOut().writer();
    try out.print(
        \\Usage:
        \\  zimaclaw issue create --title "<title>" --prompt "<prompt>"
        \\  zimaclaw issue show <issue-id>
        \\  zimaclaw molt run --prompt "<prompt>"
        \\
    , .{});
}

fn runIssue(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 3) {
        try printUsage();
        return;
    }

    if (std.mem.eql(u8, args[2], "create")) {
        const title = getFlagValue(args, "--title") orelse "Untitled issue";
        const prompt = getFlagValue(args, "--prompt") orelse "";

        const issue_id = try fang.Store.generateIssueId(allocator);
        defer allocator.free(issue_id);

        const store = fang.Store.init(".");
        try store.createIssueWithId(allocator, issue_id, title, prompt);

        const out = std.io.getStdOut().writer();
        try out.print("created issue {s}\n", .{issue_id});
        return;
    }

    if (std.mem.eql(u8, args[2], "show")) {
        if (args.len < 4) {
            try printUsage();
            return;
        }

        const store = fang.Store.init(".");
        var loaded = try store.loadIssue(allocator, args[3]);
        defer loaded.deinit();

        const out = std.io.getStdOut().writer();
        try std.json.stringify(loaded.value, .{ .whitespace = .indent_2 }, out);
        try out.print("\n", .{});
        return;
    }

    try printUsage();
}

fn runMolt(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 3 or !std.mem.eql(u8, args[2], "run")) {
        try printUsage();
        return;
    }

    const prompt = getFlagValue(args, "--prompt") orelse {
        try printUsage();
        return;
    };

    var result = try runMoltWithOptions(allocator, prompt, .{});
    defer result.deinit(allocator);

    const out = std.io.getStdOut().writer();
    try out.print(
        "molt run completed issue {s} with state {s}\n",
        .{ result.issue_id, @tagName(result.final_state) },
    );

    if (result.final_state == .failed) {
        return error.MoltRunFailed;
    }
}

pub fn runMoltWithOptions(
    allocator: std.mem.Allocator,
    prompt: []const u8,
    options: MoltRunOptions,
) !MoltRunResult {
    const store = fang.Store.init(options.root_path);
    const issue_id = try fang.Store.generateIssueId(allocator);
    errdefer allocator.free(issue_id);

    const title = try std.fmt.allocPrint(allocator, "Molt run: {s}", .{prompt});
    defer allocator.free(title);
    try store.createIssueWithId(allocator, issue_id, title, prompt);

    const events_path = try std.fs.path.join(allocator, &[_][]const u8{
        options.root_path,
        ".zimaclaw",
        "issues",
        issue_id,
        "events.jsonl",
    });
    defer allocator.free(events_path);

    var spine = try spine_mod.Spine.init(allocator, events_path);
    defer spine.deinit();

    _ = try spine.emit(.run_started, .{ .issue_id = issue_id });
    _ = try spine.emit(.issue_created, .{ .issue_id = issue_id });
    try store.transitionIssue(allocator, issue_id, .planned);
    try store.transitionIssue(allocator, issue_id, .executing);
    _ = try spine.emit(.drive_spawned, .{ .issue_id = issue_id });

    var drive_result = drive.runWithOptions(allocator, .{
        .prompt = prompt,
    }, options.drive_options) catch |err| {
        try failRun(
            allocator,
            &store,
            &spine,
            issue_id,
            events_path,
            @errorName(err),
        );
        return .{
            .issue_id = issue_id,
            .final_state = .failed,
        };
    };
    defer drive_result.deinit(allocator);

    _ = try spine.emit(.pi_event_received, .{
        .issue_id = issue_id,
        .detail = drive_result.response.kind,
    });
    _ = try spine.emit(.steer_call_attempted, .{ .issue_id = issue_id });

    var steer_result = steer.execute(allocator, .{
        .eval = options.steer_eval,
    }, options.steer_options);
    defer steer_result.deinit(allocator);
    switch (steer_result) {
        .ok => {},
        .err => |failure| {
            try failRun(
                allocator,
                &store,
                &spine,
                issue_id,
                events_path,
                @tagName(failure.kind),
            );
            return .{
                .issue_id = issue_id,
                .final_state = .failed,
            };
        },
    }

    try store.transitionIssue(allocator, issue_id, .review);
    try setExecutionArtifact(allocator, &store, issue_id, events_path);
    _ = try spine.emit(.run_finished, .{ .issue_id = issue_id });

    return .{
        .issue_id = issue_id,
        .final_state = .review,
    };
}

fn failRun(
    allocator: std.mem.Allocator,
    store: *const fang.Store,
    spine: *spine_mod.Spine,
    issue_id: []const u8,
    events_path: []const u8,
    detail: []const u8,
) !void {
    try store.transitionIssue(allocator, issue_id, .failed);
    try setExecutionArtifact(allocator, store, issue_id, events_path);
    _ = try spine.emit(.run_failed, .{
        .issue_id = issue_id,
        .detail = detail,
    });
}

fn setExecutionArtifact(
    allocator: std.mem.Allocator,
    store: *const fang.Store,
    issue_id: []const u8,
    events_path: []const u8,
) !void {
    try store.setExecutionArtifactPath(allocator, issue_id, events_path);
}

fn getFlagValue(args: []const []const u8, flag: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i + 1 < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], flag)) {
            return args[i + 1];
        }
    }
    return null;
}
