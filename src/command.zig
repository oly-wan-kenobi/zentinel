// Layer: deterministic_core
//
// Shared, shell-free command-string parser (docs/CONFIG_SPEC.md, docs/INTERNAL_API_CONTRACTS.md).
// Turns a configured command string into a deterministic argv array without
// invoking a shell. `zentinel check` validates with it; the runner (task 014)
// must execute exactly the argv this returns and must not fork a second parser.
// Pure: allocates only into the caller-provided arena.
const std = @import("std");

/// Why a command string is not valid argv. Used for diagnostics; `zentinel check`
/// maps any invalid result to ZNTL_CONFIG_INVALID_COMMAND.
pub const Reason = enum {
    empty,
    empty_argv0,
    unmatched_quote,
    trailing_escape,
    unsupported_escape,
    backslash_outside_quote,
    metacharacter,
    env_assignment,
};

pub const Result = union(enum) {
    ok: []const []const u8,
    invalid: Reason,
};

fn isSpace(c: u8) bool {
    return c == ' ' or c == '\t';
}

/// Shell metacharacters rejected even inside quotes or escapes. Rejecting these
/// keeps argv construction deterministic instead of approximating a shell.
fn isMeta(c: u8) bool {
    return switch (c) {
        '|', '<', '>', '$', '`', '*', '?', '[', ']', '{', '}', '(', ')', '&', ';' => true,
        else => false,
    };
}

pub fn parse(arena: std.mem.Allocator, source: []const u8) std.mem.Allocator.Error!Result {
    var fields: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    while (i < source.len and isSpace(source[i])) i += 1;
    if (i >= source.len) return .{ .invalid = .empty };

    while (i < source.len) {
        var buf: std.ArrayList(u8) = .empty;
        while (i < source.len and !isSpace(source[i])) {
            const c = source[i];
            if (c == '"' or c == '\'') {
                const quote = c;
                i += 1;
                var closed = false;
                while (i < source.len) {
                    const q = source[i];
                    if (q == quote) {
                        i += 1;
                        closed = true;
                        break;
                    }
                    if (q == '\\') {
                        i += 1;
                        if (i >= source.len) return .{ .invalid = .trailing_escape };
                        switch (source[i]) {
                            '\\', '\'', '"', ' ' => {
                                try buf.append(arena, source[i]);
                                i += 1;
                            },
                            else => return .{ .invalid = .unsupported_escape },
                        }
                        continue;
                    }
                    if (isMeta(q)) return .{ .invalid = .metacharacter };
                    try buf.append(arena, q);
                    i += 1;
                }
                if (!closed) return .{ .invalid = .unmatched_quote };
            } else if (c == '\\') {
                return .{ .invalid = .backslash_outside_quote };
            } else if (isMeta(c)) {
                return .{ .invalid = .metacharacter };
            } else {
                try buf.append(arena, c);
                i += 1;
            }
        }

        const field = try buf.toOwnedSlice(arena);
        if (fields.items.len == 0) {
            // argv[0] must be a non-empty program name and may not be an
            // environment-variable assignment prefix such as `FOO=bar`.
            if (field.len == 0) return .{ .invalid = .empty_argv0 };
            if (std.mem.indexOfScalar(u8, field, '=') != null) return .{ .invalid = .env_assignment };
        }
        try fields.append(arena, field);
        while (i < source.len and isSpace(source[i])) i += 1;
    }

    if (fields.items.len == 0) return .{ .invalid = .empty };
    return .{ .ok = try fields.toOwnedSlice(arena) };
}
