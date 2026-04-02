const std = @import("std");
const types = @import("types.zig");

pub const IssueState = types.IssueState;
pub const Issue = types.Issue;
pub const ArtifactRef = types.ArtifactRef;

pub const TransitionError = error{
    InvalidTransition,
};

pub fn canTransition(from: IssueState, to: IssueState) bool {
    if (from == to) return true;

    return switch (from) {
        .inbox => to == .planned or to == .executing,
        .planned => to == .simulating or to == .executing,
        .simulating => to == .planned or to == .executing,
        .executing => to == .review or to == .failed,
        .review => to == .done or to == .rejected,
        .rejected => to == .planned,
        .failed => to == .planned,
        .done => false,
    };
}

pub const Store = struct {
    root_path: []const u8,

    pub fn init(root_path: []const u8) Store {
        return .{ .root_path = root_path };
    }

    pub fn generateIssueId(allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "issue-{d}", .{std.time.milliTimestamp()});
    }

    pub fn createIssueWithId(
        self: *const Store,
        allocator: std.mem.Allocator,
        id: []const u8,
        title: []const u8,
        prompt: []const u8,
    ) !void {
        const now = std.time.milliTimestamp();
        const issue = Issue{
            .id = id,
            .title = title,
            .prompt = prompt,
            .state = .inbox,
            .created_at_ms = now,
            .updated_at_ms = now,
            .acceptance_criteria = null,
            .simulation_artifact = null,
            .execution_artifact = null,
        };
        try self.saveIssue(allocator, issue);
    }

    pub fn loadIssue(
        self: *const Store,
        allocator: std.mem.Allocator,
        id: []const u8,
    ) !std.json.Parsed(Issue) {
        const file_path = try self.issueFilePath(allocator, id);
        defer allocator.free(file_path);

        const payload = try std.fs.cwd().readFileAlloc(allocator, file_path, 1024 * 1024);
        defer allocator.free(payload);

        return std.json.parseFromSlice(Issue, allocator, payload, .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        });
    }

    pub fn transitionIssue(
        self: *const Store,
        allocator: std.mem.Allocator,
        id: []const u8,
        new_state: IssueState,
    ) !void {
        var loaded = try self.loadIssue(allocator, id);
        defer loaded.deinit();

        var updated = loaded.value;
        if (!canTransition(updated.state, new_state)) {
            return TransitionError.InvalidTransition;
        }
        updated.state = new_state;
        if (new_state != .rejected) {
            updated.rejection_reason = null;
        }
        updated.updated_at_ms = std.time.milliTimestamp();

        try self.saveIssue(allocator, updated);
    }

    pub fn rejectIssue(
        self: *const Store,
        allocator: std.mem.Allocator,
        id: []const u8,
        reason: []const u8,
    ) !void {
        var loaded = try self.loadIssue(allocator, id);
        defer loaded.deinit();

        var updated = loaded.value;
        if (!canTransition(updated.state, .rejected)) {
            return TransitionError.InvalidTransition;
        }
        updated.state = .rejected;
        updated.rejection_reason = reason;
        updated.updated_at_ms = std.time.milliTimestamp();
        try self.saveIssue(allocator, updated);
    }

    pub fn setSimulationArtifactPath(
        self: *const Store,
        allocator: std.mem.Allocator,
        id: []const u8,
        artifact_path: []const u8,
    ) !void {
        try self.setArtifactPath(allocator, id, .simulation, artifact_path);
    }

    pub fn setExecutionArtifactPath(
        self: *const Store,
        allocator: std.mem.Allocator,
        id: []const u8,
        artifact_path: []const u8,
    ) !void {
        try self.setArtifactPath(allocator, id, .execution, artifact_path);
    }

    fn setArtifactPath(
        self: *const Store,
        allocator: std.mem.Allocator,
        id: []const u8,
        which: enum { simulation, execution },
        artifact_path: []const u8,
    ) !void {
        var loaded = try self.loadIssue(allocator, id);
        defer loaded.deinit();

        var updated = loaded.value;
        const artifact: ArtifactRef = .{
            .path = artifact_path,
            .recorded_at_ms = std.time.milliTimestamp(),
        };
        switch (which) {
            .simulation => updated.simulation_artifact = artifact,
            .execution => updated.execution_artifact = artifact,
        }
        updated.updated_at_ms = std.time.milliTimestamp();
        try self.saveIssue(allocator, updated);
    }

    pub fn saveIssue(
        self: *const Store,
        allocator: std.mem.Allocator,
        issue: Issue,
    ) !void {
        const issue_dir_path = try self.issueDirPath(allocator, issue.id);
        defer allocator.free(issue_dir_path);
        try std.fs.cwd().makePath(issue_dir_path);

        const file_path = try self.issueFilePath(allocator, issue.id);
        defer allocator.free(file_path);

        const payload = try std.json.stringifyAlloc(allocator, issue, .{
            .whitespace = .indent_2,
        });
        defer allocator.free(payload);

        var file = try std.fs.cwd().createFile(file_path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(payload);
    }

    pub fn issueFilePath(
        self: *const Store,
        allocator: std.mem.Allocator,
        id: []const u8,
    ) ![]u8 {
        return std.fs.path.join(allocator, &[_][]const u8{
            self.root_path,
            ".zimaclaw",
            "issues",
            id,
            "issue.json",
        });
    }

    fn issueDirPath(
        self: *const Store,
        allocator: std.mem.Allocator,
        id: []const u8,
    ) ![]u8 {
        return std.fs.path.join(allocator, &[_][]const u8{
            self.root_path,
            ".zimaclaw",
            "issues",
            id,
        });
    }
};
