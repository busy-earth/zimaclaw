const std = @import("std");
const types = @import("types.zig");

pub const IssueState = types.IssueState;
pub const Issue = types.Issue;

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
        updated.state = new_state;
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
