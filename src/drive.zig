const std = @import("std");
const drive_jsonl = @import("drive_jsonl.zig");

pub const DriveError = error{
    MissingCommand,
    PiUnavailable,
    SpawnFailed,
    MissingStdinPipe,
    MissingStdoutPipe,
    TransportFailure,
    NoResponse,
    InvalidResponse,
    ProcessExitFailure,
    OutOfMemory,
};

pub const Request = struct {
    prompt: []const u8,
};

pub const Response = struct {
    kind: []const u8,
    payload: ?[]const u8 = null,
};

pub const Options = struct {
    command_argv: []const []const u8 = &.{ "pi" },
    max_line_bytes: usize = 64 * 1024,
};

pub const RunResult = struct {
    response: Response,
    term: std.process.Child.Term,

    pub fn deinit(self: *RunResult, allocator: std.mem.Allocator) void {
        allocator.free(self.response.kind);
        if (self.response.payload) |payload| {
            allocator.free(payload);
        }
    }
};

pub fn run(
    allocator: std.mem.Allocator,
    request: Request,
) DriveError!RunResult {
    return runWithOptions(allocator, request, .{});
}

pub fn runWithOptions(
    allocator: std.mem.Allocator,
    request: Request,
    options: Options,
) DriveError!RunResult {
    if (options.command_argv.len == 0) return error.MissingCommand;
    const command = options.command_argv[0];
    if (std.mem.indexOfScalar(u8, command, '/') != null) {
        std.fs.cwd().access(command, .{}) catch |err| switch (err) {
            error.FileNotFound => return error.PiUnavailable,
            else => {},
        };
    }

    var child = std.process.Child.init(options.command_argv, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    child.spawn() catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return error.PiUnavailable,
        else => return error.SpawnFailed,
    };

    const stdin_file = child.stdin orelse {
        waitQuiet(&child);
        return error.MissingStdinPipe;
    };
    const stdout_file = child.stdout orelse {
        waitQuiet(&child);
        return error.MissingStdoutPipe;
    };

    const outbound = .{
        .kind = "run",
        .prompt = request.prompt,
    };
    drive_jsonl.writeJsonLine(stdin_file.writer(), outbound) catch {
        stdin_file.close();
        child.stdin = null;
        waitQuiet(&child);
        return error.TransportFailure;
    };
    stdin_file.close();
    child.stdin = null;

    const maybe_line = drive_jsonl.readLineAlloc(stdout_file.reader(), allocator, options.max_line_bytes) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            waitQuiet(&child);
            return error.TransportFailure;
        },
    };
    const line = maybe_line orelse {
        const term = child.wait() catch return error.TransportFailure;
        switch (term) {
            .Exited => |code| {
                if (code == 127) return error.PiUnavailable;
                if (code != 0) return error.ProcessExitFailure;
            },
            else => return error.ProcessExitFailure,
        }
        return error.NoResponse;
    };
    defer allocator.free(line);

    var parsed_value = drive_jsonl.parseEventLine(allocator, line) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.EmptyLine => {
            waitQuiet(&child);
            return error.NoResponse;
        },
        else => {
            waitQuiet(&child);
            return error.InvalidResponse;
        },
    };
    defer parsed_value.deinit();

    var parsed_response = std.json.parseFromValue(Response, allocator, parsed_value.value, .{
        .ignore_unknown_fields = true,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            waitQuiet(&child);
            return error.InvalidResponse;
        },
    };
    defer parsed_response.deinit();

    const term = child.wait() catch return error.TransportFailure;
    switch (term) {
        .Exited => |code| {
            if (code != 0) return error.ProcessExitFailure;
        },
        else => return error.ProcessExitFailure,
    }

    return .{
        .response = .{
            .kind = try allocator.dupe(u8, parsed_response.value.kind),
            .payload = if (parsed_response.value.payload) |payload|
                try allocator.dupe(u8, payload)
            else
                null,
        },
        .term = term,
    };
}

fn waitQuiet(child: *std.process.Child) void {
    _ = child.wait() catch {};
}
