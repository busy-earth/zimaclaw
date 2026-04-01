const std = @import("std");

pub const FailureKind = enum {
    emacsclient_unavailable,
    spawn_failed,
    missing_stdout_pipe,
    io_failure,
    non_zero_exit,
    out_of_memory,
};

pub const Failure = struct {
    kind: FailureKind,
};

pub const Request = union(enum) {
    eval: []const u8,
    read_file: []const u8,
};

pub const Response = union(enum) {
    eval_output: []u8,
    file_contents: []u8,
};

pub const Result = union(enum) {
    ok: Response,
    err: Failure,

    pub fn deinit(self: *Result, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .ok => |*ok| switch (ok.*) {
                .eval_output => |output| allocator.free(output),
                .file_contents => |contents| allocator.free(contents),
            },
            .err => {},
        }
    }
};

pub const Options = struct {
    emacsclient_cmd: []const u8 = "emacsclient",
    max_output_bytes: usize = 1024 * 1024,
};

pub fn execute(
    allocator: std.mem.Allocator,
    request: Request,
    options: Options,
) Result {
    return switch (request) {
        .eval => |expression| runEval(allocator, expression, .eval, options),
        .read_file => |path| {
            const encoded_path = std.json.stringifyAlloc(allocator, path, .{}) catch {
                return .{ .err = .{ .kind = .out_of_memory } };
            };
            defer allocator.free(encoded_path);

            const expression = std.fmt.allocPrint(
                allocator,
                "(with-temp-buffer (insert-file-contents {s}) (buffer-string))",
                .{encoded_path},
            ) catch {
                return .{ .err = .{ .kind = .out_of_memory } };
            };
            defer allocator.free(expression);

            return runEval(allocator, expression, .read_file, options);
        },
    };
}

const Mode = enum {
    eval,
    read_file,
};

fn runEval(
    allocator: std.mem.Allocator,
    expression: []const u8,
    mode: Mode,
    options: Options,
) Result {
    if (std.mem.indexOfScalar(u8, options.emacsclient_cmd, '/') != null) {
        std.fs.cwd().access(options.emacsclient_cmd, .{}) catch |err| switch (err) {
            error.FileNotFound => return .{ .err = .{ .kind = .emacsclient_unavailable } },
            else => {},
        };
    }

    var child = std.process.Child.init(
        &.{ options.emacsclient_cmd, "--eval", expression },
        allocator,
    );
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    child.spawn() catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return .{ .err = .{ .kind = .emacsclient_unavailable } },
        else => return .{ .err = .{ .kind = .spawn_failed } },
    };

    const stdout_file = child.stdout orelse {
        waitQuiet(&child);
        return .{ .err = .{ .kind = .missing_stdout_pipe } };
    };

    const output = stdout_file.readToEndAlloc(allocator, options.max_output_bytes) catch |err| switch (err) {
        error.OutOfMemory => return .{ .err = .{ .kind = .out_of_memory } },
        else => {
            waitQuiet(&child);
            return .{ .err = .{ .kind = .io_failure } };
        },
    };

    const term = child.wait() catch {
        allocator.free(output);
        return .{ .err = .{ .kind = .io_failure } };
    };
    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                allocator.free(output);
                if (code == 127) {
                    return .{ .err = .{ .kind = .emacsclient_unavailable } };
                }
                return .{ .err = .{ .kind = .non_zero_exit } };
            }
        },
        else => {
            allocator.free(output);
            return .{ .err = .{ .kind = .non_zero_exit } };
        },
    }

    return switch (mode) {
        .eval => .{ .ok = .{ .eval_output = output } },
        .read_file => .{ .ok = .{ .file_contents = output } },
    };
}

fn waitQuiet(child: *std.process.Child) void {
    _ = child.wait() catch {};
}
