const std = @import("std");

pub const JsonlError = error{
    EmptyLine,
    EmbeddedNewline,
    InvalidJson,
} || std.mem.Allocator.Error;

pub fn writeJsonLine(writer: anytype, value: anytype) !void {
    try std.json.stringify(value, .{}, writer);
    try writer.writeByte('\n');
}

pub fn readLineAlloc(
    reader: anytype,
    allocator: std.mem.Allocator,
    max_bytes: usize,
) !?[]u8 {
    return reader.readUntilDelimiterOrEofAlloc(allocator, '\n', max_bytes);
}

pub fn parseEventLine(
    allocator: std.mem.Allocator,
    line: []const u8,
) JsonlError!std.json.Parsed(std.json.Value) {
    if (line.len == 0) return error.EmptyLine;
    if (std.mem.indexOfScalar(u8, line, '\n') != null) return error.EmbeddedNewline;

    return std.json.parseFromSlice(std.json.Value, allocator, line, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidJson,
    };
}
