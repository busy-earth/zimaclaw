pub const IssueState = enum {
    inbox,
    executing,
    review,
    done,
    failed,
};

pub const Issue = struct {
    id: []const u8,
    title: []const u8,
    prompt: []const u8,
    state: IssueState,
    created_at_ms: i64,
    updated_at_ms: i64,
    acceptance_criteria: ?[]const u8 = null,
    simulation_artifact: ?[]const u8 = null,
    execution_artifact: ?[]const u8 = null,
};
