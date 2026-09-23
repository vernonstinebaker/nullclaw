//! Parallel read-only tool batch helpers for the agent loop.

const std = @import("std");
const dispatcher = @import("dispatcher.zig");

const ParsedToolCall = dispatcher.ParsedToolCall;

// Memory backend vtables do not promise thread-safe reads; keep them sequential.
const parallel_readonly_tools = [_][]const u8{
    "file_read",
    "file_read_hashed",
    "web_fetch",
    "web_search",
    "sqlite_query",
};

pub fn isParallelReadOnlyTool(name: []const u8) bool {
    const trimmed = std.mem.trim(u8, name, " \t\r\n");
    for (parallel_readonly_tools) |allowed| {
        if (std.mem.eql(u8, trimmed, allowed)) return true;
    }
    return false;
}

pub fn batchAllParallelReadOnly(calls: []const ParsedToolCall) bool {
    if (calls.len <= 1) return false;
    for (calls, 0..) |call, i| {
        // Resolve duplicate native IDs sequentially so the first result is in
        // the replay cache before another call with that ID can execute.
        if (call.tool_call_id) |id| {
            if (id.len > 0) for (calls[0..i]) |earlier| {
                if (earlier.tool_call_id) |previous| {
                    if (std.mem.eql(u8, id, previous)) return false;
                }
            };
        }
        if (!isParallelReadOnlyTool(call.name)) return false;
        if (std.mem.eql(u8, std.mem.trim(u8, call.name, " \t\r\n"), "file_read")) {
            // Bootstrap file reads may call a shared memory backend. Parse with
            // bounded scratch space; malformed/large arguments stay sequential.
            var scratch: [4096]u8 = undefined;
            var fixed = std.heap.FixedBufferAllocator.init(&scratch);
            const parsed = std.json.parseFromSlice(std.json.Value, fixed.allocator(), call.arguments_json, .{}) catch return false;
            defer parsed.deinit();
            if (parsed.value != .object) return false;
            const path = parsed.value.object.get("path") orelse return false;
            if (path != .string) return false;
            if (@import("../tools/file_common.zig").bootstrapRootFilename(path.string) != null) return false;
        }
    }
    return true;
}

pub fn shouldRunParallelReadOnlyBatch(parallel_tools_enabled: bool, calls: []const ParsedToolCall) bool {
    return parallel_tools_enabled and batchAllParallelReadOnly(calls);
}

test "batchAllParallelReadOnly accepts file_read batch" {
    const calls = [_]ParsedToolCall{
        .{ .name = "file_read", .arguments_json = "{\"path\":\"a\"}" },
        .{ .name = "file_read", .arguments_json = "{\"path\":\"b\"}" },
    };
    try std.testing.expect(batchAllParallelReadOnly(&calls));
}

test "batchAllParallelReadOnly rejects shell mixed with file_read" {
    const calls = [_]ParsedToolCall{
        .{ .name = "file_read", .arguments_json = "{\"path\":\"a\"}" },
        .{ .name = "shell", .arguments_json = "{\"command\":\"ls\"}" },
    };
    try std.testing.expect(!batchAllParallelReadOnly(&calls));
}

test "shouldRunParallelReadOnlyBatch requires parallel_tools flag" {
    const calls = [_]ParsedToolCall{
        .{ .name = "file_read", .arguments_json = "{\"path\":\"a\"}" },
        .{ .name = "file_read", .arguments_json = "{\"path\":\"b\"}" },
    };
    try std.testing.expect(!shouldRunParallelReadOnlyBatch(false, &calls));
    try std.testing.expect(shouldRunParallelReadOnlyBatch(true, &calls));
}

test "memory tools remain sequential without a backend concurrency contract" {
    // Regression: read-only memory calls may mutate backend caches/allocators.
    for ([_][]const u8{ "memory_recall", "memory_list", "memory_search" }) |name| {
        try std.testing.expect(!isParallelReadOnlyTool(name));
    }
}

test "bootstrap file reads remain sequential" {
    // Regression: file_read can delegate bootstrap files to shared memory.
    const calls = [_]ParsedToolCall{
        .{ .name = "file_read", .arguments_json = "{\"path\":\"AGENTS.md\"}" },
        .{ .name = "file_read", .arguments_json = "{\"path\":\"notes.txt\"}" },
    };
    try std.testing.expect(!batchAllParallelReadOnly(&calls));
}
