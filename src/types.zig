pub const IssueState = enum {
    inbox,
    planned,
    simulating,
    executing,
    review,
    rejected,
    done,
    failed,
};

pub const ArtifactRef = struct {
    path: []const u8,
    recorded_at_ms: i64,
};

pub const Issue = struct {
    id: []const u8,
    title: []const u8,
    prompt: []const u8,
    state: IssueState,
    created_at_ms: i64,
    updated_at_ms: i64,
    acceptance_criteria: ?[]const u8 = null,
    simulation_artifact: ?ArtifactRef = null,
    execution_artifact: ?ArtifactRef = null,
    rejection_reason: ?[]const u8 = null,
};
