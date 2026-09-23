//! Detect repeated identical tool calls within a turn and veto runaway loops.

const std = @import("std");

pub const LoopGuardConfig = struct {
    warn_at: u32 = 3,
    veto_at: u32 = 5,
    force_reply_after_vetoes: u32 = 3,
};

pub const LoopGuardAction = enum {
    ok,
    warn,
    veto,
    force_reply,
};

const MAX_ARGUMENT_BYTES = 64 * 1024;
const MAX_GUARD_BYTES = 1024 * 1024;
const MAX_GUARD_ENTRIES = 1024;
const MAX_ARGUMENT_DEPTH = 32;

pub const LoopGuard = struct {
    config: LoopGuardConfig,
    // Store exact canonical keys so hash collisions cannot merge unrelated calls.
    counts: std.StringHashMapUnmanaged(u32) = .empty,
    key_bytes: usize = 0,
    consecutive_vetoes: u32 = 0,

    pub fn init(config: LoopGuardConfig) LoopGuard {
        return .{ .config = config };
    }

    pub fn deinit(self: *LoopGuard, allocator: std.mem.Allocator) void {
        self.reset(allocator);
        self.counts.deinit(allocator);
    }

    pub fn reset(self: *LoopGuard, allocator: std.mem.Allocator) void {
        var keys = self.counts.keyIterator();
        while (keys.next()) |key| allocator.free(key.*);
        self.counts.clearRetainingCapacity();
        self.key_bytes = 0;
        self.consecutive_vetoes = 0;
    }

    pub fn record(self: *LoopGuard, allocator: std.mem.Allocator, name: []const u8, args_json: []const u8) !LoopGuardAction {
        const key = try canonicalToolCall(allocator, name, args_json);
        var retained = false;
        defer if (!retained) allocator.free(key);
        const count = if (self.counts.getPtr(key)) |value| blk: {
            value.* +|= 1;
            break :blk value.*;
        } else blk: {
            if (self.counts.count() >= MAX_GUARD_ENTRIES or key.len > MAX_GUARD_BYTES - self.key_bytes)
                return error.LoopGuardCapacityExceeded;
            try self.counts.put(allocator, key, 1);
            retained = true;
            self.key_bytes += key.len;
            break :blk @as(u32, 1);
        };

        if (count >= self.config.veto_at) {
            self.consecutive_vetoes +|= 1;
            if (self.consecutive_vetoes >= self.config.force_reply_after_vetoes) return .force_reply;
            return .veto;
        }
        // Actual progress (a non-vetoed call), not a different fingerprint,
        // resets the budget. Alternating already-vetoed calls still terminate.
        self.consecutive_vetoes = 0;
        if (count >= self.config.warn_at) return .warn;
        return .ok;
    }
};

fn canonicalToolCall(allocator: std.mem.Allocator, name: []const u8, args: []const u8) ![]const u8 {
    const trimmed = std.mem.trim(u8, name, " \t\r\n");
    if (trimmed.len == 0 or trimmed.len > 256 or args.len > MAX_ARGUMENT_BYTES) return error.InvalidToolArguments;
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, args, .{ .parse_numbers = false }) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => return error.InvalidToolArguments,
    };
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidToolArguments;
    try normalizeValue(parsed.arena.allocator(), &parsed.value, 0);
    const json = try std.json.Stringify.valueAlloc(allocator, parsed.value, .{});
    defer allocator.free(json);
    const normalized_name = try std.ascii.allocLowerString(allocator, trimmed);
    defer allocator.free(normalized_name);
    return std.fmt.allocPrint(allocator, "{d}:{s}{s}", .{ normalized_name.len, normalized_name, json });
}

fn normalizeValue(allocator: std.mem.Allocator, value: *std.json.Value, depth: usize) !void {
    if (depth > MAX_ARGUMENT_DEPTH) return error.InvalidToolArguments;
    switch (value.*) {
        .object => |*object| {
            const Order = struct {
                keys: []const []const u8,
                pub fn lessThan(ctx: @This(), a: usize, b: usize) bool {
                    return std.mem.lessThan(u8, ctx.keys[a], ctx.keys[b]);
                }
            };
            object.sort(Order{ .keys = object.keys() });
            for (object.values()) |*child| try normalizeValue(allocator, child, depth + 1);
        },
        .array => |*array| for (array.items) |*child| try normalizeValue(allocator, child, depth + 1),
        .number_string => |number| value.* = .{ .number_string = try normalizeNumber(allocator, number) },
        else => {},
    }
}

// Normalize decimals exactly, without rounding distinct large integers to f64.
fn normalizeNumber(allocator: std.mem.Allocator, number: []const u8) ![]const u8 {
    const exponent_at = std.mem.indexOfAny(u8, number, "eE") orelse number.len;
    const mantissa = number[0..exponent_at];
    var exponent: i64 = if (exponent_at < number.len)
        std.fmt.parseInt(i64, number[exponent_at + 1 ..], 10) catch return error.InvalidToolArguments
    else
        0;
    if (std.mem.indexOfScalar(u8, mantissa, '.')) |dot| {
        exponent = std.math.sub(i64, exponent, @intCast(mantissa.len - dot - 1)) catch return error.InvalidToolArguments;
    }
    var digits: std.ArrayListUnmanaged(u8) = .empty;
    defer digits.deinit(allocator);
    for (mantissa) |char| if (char != '-' and char != '.') try digits.append(allocator, char);
    var begin: usize = 0;
    while (begin < digits.items.len and digits.items[begin] == '0') : (begin += 1) {}
    if (begin == digits.items.len) return allocator.dupe(u8, "0");
    var end = digits.items.len;
    while (end > begin and digits.items[end - 1] == '0') : (end -= 1) {
        exponent = std.math.add(i64, exponent, 1) catch return error.InvalidToolArguments;
    }
    return std.fmt.allocPrint(allocator, "{s}{s}e{d}", .{
        if (number[0] == '-') "-" else "", digits.items[begin..end], exponent,
    });
}

test "loop guard warns on third identical call" {
    var guard = LoopGuard.init(.{});
    defer guard.deinit(std.testing.allocator);

    try std.testing.expectEqual(LoopGuardAction.ok, try guard.record(std.testing.allocator, "file_read", "{\"path\":\"a\"}"));
    try std.testing.expectEqual(LoopGuardAction.ok, try guard.record(std.testing.allocator, "file_read", "{\"path\":\"a\"}"));
    try std.testing.expectEqual(LoopGuardAction.warn, try guard.record(std.testing.allocator, "file_read", "{\"path\":\"a\"}"));
}

test "loop guard vetoes on fifth identical call" {
    var guard = LoopGuard.init(.{});
    defer guard.deinit(std.testing.allocator);

    _ = try guard.record(std.testing.allocator, "web_search", "{\"query\":\"x\"}");
    _ = try guard.record(std.testing.allocator, "web_search", "{\"query\":\"x\"}");
    _ = try guard.record(std.testing.allocator, "web_search", "{\"query\":\"x\"}");
    _ = try guard.record(std.testing.allocator, "web_search", "{\"query\":\"x\"}");
    try std.testing.expectEqual(LoopGuardAction.veto, try guard.record(std.testing.allocator, "web_search", "{\"query\":\"x\"}"));
}

test "loop guard force reply after three consecutive vetoes" {
    var guard = LoopGuard.init(.{ .warn_at = 1, .veto_at = 2, .force_reply_after_vetoes = 3 });
    defer guard.deinit(std.testing.allocator);

    _ = try guard.record(std.testing.allocator, "shell", "{\"command\":\"ls\"}");
    _ = try guard.record(std.testing.allocator, "shell", "{\"command\":\"ls\"}"); // veto #1
    _ = try guard.record(std.testing.allocator, "shell", "{\"command\":\"ls\"}"); // veto #2
    const action = try guard.record(std.testing.allocator, "shell", "{\"command\":\"ls\"}"); // veto #3 -> force_reply
    try std.testing.expectEqual(LoopGuardAction.force_reply, action);
}

test "loop guard resets consecutive vetoes when fingerprint changes before veto threshold" {
    var guard = LoopGuard.init(.{ .warn_at = 2, .veto_at = 5 });
    defer guard.deinit(std.testing.allocator);

    _ = try guard.record(std.testing.allocator, "file_read", "{\"path\":\"a\"}");
    _ = try guard.record(std.testing.allocator, "file_read", "{\"path\":\"b\"}");
    try std.testing.expectEqual(@as(u32, 0), guard.consecutive_vetoes);
}

test "loop guard counts equivalent object arguments and normalized names" {
    // Regression: key order, whitespace, and provider spelling bypassed counts.
    var guard = LoopGuard.init(.{ .warn_at = 2 });
    defer guard.deinit(std.testing.allocator);
    _ = try guard.record(std.testing.allocator, "file_read", "{\"path\":\"a\",\"offset\":0}");
    try std.testing.expectEqual(LoopGuardAction.warn, try guard.record(std.testing.allocator, " FILE_READ ", "{ \"offset\": 0, \"path\": \"a\" }"));
}

test "loop guard alternating vetoed calls still terminate" {
    // Regression: alternating fingerprints reset the consecutive-veto budget.
    var guard = LoopGuard.init(.{ .veto_at = 1, .force_reply_after_vetoes = 3 });
    defer guard.deinit(std.testing.allocator);
    _ = try guard.record(std.testing.allocator, "file_read", "{\"path\":\"a\"}");
    _ = try guard.record(std.testing.allocator, "file_read", "{\"path\":\"b\"}");
    try std.testing.expectEqual(LoopGuardAction.force_reply, try guard.record(std.testing.allocator, "file_read", "{\"path\":\"a\"}"));
}

test "loop guard legitimate progress resets the veto budget" {
    var guard = LoopGuard.init(.{ .veto_at = 2, .force_reply_after_vetoes = 2 });
    defer guard.deinit(std.testing.allocator);
    _ = try guard.record(std.testing.allocator, "file_read", "{\"path\":\"a\"}");
    try std.testing.expectEqual(LoopGuardAction.veto, try guard.record(std.testing.allocator, "file_read", "{\"path\":\"a\"}"));
    try std.testing.expectEqual(LoopGuardAction.ok, try guard.record(std.testing.allocator, "file_read", "{\"path\":\"b\"}"));
    try std.testing.expectEqual(LoopGuardAction.veto, try guard.record(std.testing.allocator, "file_read", "{\"path\":\"a\"}"));
    try std.testing.expectEqual(@as(u32, 1), guard.consecutive_vetoes);
}

test "loop guard distinguishes scalar values and array order" {
    var guard = LoopGuard.init(.{ .warn_at = 2 });
    defer guard.deinit(std.testing.allocator);
    _ = try guard.record(std.testing.allocator, "file_read", "{\"paths\":[1,2]}");
    try std.testing.expectEqual(LoopGuardAction.ok, try guard.record(std.testing.allocator, "file_read", "{\"paths\":[2,1]}"));
    _ = try guard.record(std.testing.allocator, "file_read", "{\"n\":1}");
    try std.testing.expectEqual(LoopGuardAction.ok, try guard.record(std.testing.allocator, "file_read", "{\"n\":2}"));
}

test "loop guard rejects malformed and oversized arguments" {
    // Regression: unbounded or unparsed arguments must stop classification
    // without retaining a key.
    var guard = LoopGuard.init(.{});
    defer guard.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidToolArguments, guard.record(std.testing.allocator, "file_read", "not-json"));
    try std.testing.expectError(error.InvalidToolArguments, guard.record(std.testing.allocator, "file_read", "[1,2]"));
    try std.testing.expectError(error.InvalidToolArguments, guard.record(std.testing.allocator, "  ", "{\"path\":\"a\"}"));
    const oversized = try std.testing.allocator.alloc(u8, 64 * 1024 + 1);
    defer std.testing.allocator.free(oversized);
    @memset(oversized, 'x');
    try std.testing.expectError(error.InvalidToolArguments, guard.record(std.testing.allocator, "file_read", oversized));
    try std.testing.expectEqual(@as(usize, 0), guard.counts.count());
}

fn loopGuardAllocation(allocator: std.mem.Allocator) !void {
    var guard = LoopGuard.init(.{ .warn_at = 2 });
    defer guard.deinit(allocator);
    _ = try guard.record(allocator, "file_read", "{\"path\":\"a\",\"offset\":0}");
    _ = try guard.record(allocator, " FILE_READ ", "{ \"offset\": 0, \"path\": \"a\" }");
}

test "loop guard allocation failures release canonical keys" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, loopGuardAllocation, .{});
}
