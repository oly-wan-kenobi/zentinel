// Layer: deterministic_core
//
// Isolated doctest workspace planning (docs/DOCTEST_ARCHITECTURE.md "Temporary
// Workspace Generation"). The workspace directory name is a pure function of the
// durable case id, grouped content, Zig version, and doctest engine version, so
// the same case always maps to the same path and different content never
// collides. Materialization (writing files) is an injected side effect through
// the `Provider` abstraction: the CLI wires the real filesystem provider (a
// side_effect_adapter, like src/runner.zig's Executor), while unit tests inject
// a mock so classification stays hermetic. Every planned file path is confined
// under the workspace directory, so running a doctest can never touch repository
// sources.
const std = @import("std");

/// Doctest engine version; participates in the workspace path so a future engine
/// change cannot reuse a stale workspace.
pub const engine_version = "0.1.0";

const ws_namespace = "zentinel.doctest_workspace.v1";

/// Root under which all doctest workspaces are generated (project-relative).
pub const root = ".zig-cache/zentinel/doctest";

/// Lowercase Crockford base32 alphabet (excludes i, l, o, u). Matches src/mutant.zig.
const crockford_lower = "0123456789abcdefghjkmnpqrstvwxyz";

/// Deterministic 26-char workspace name from case identity. Same inputs produce
/// the same name; any change to id, content, Zig version, or engine version
/// changes it.
pub fn workspaceName(case_id: []const u8, content: []const u8, zig_version: []const u8) [26]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(ws_namespace);
    hasher.update("\n");
    hasher.update(case_id);
    hasher.update("\n");
    hasher.update(content);
    hasher.update("\n");
    hasher.update(zig_version);
    hasher.update("\n");
    hasher.update(engine_version);

    var digest: [32]u8 = undefined;
    hasher.final(&digest);

    var out: [26]u8 = undefined;
    var bits: u32 = 0;
    var nbits: u8 = 0;
    var di: usize = 0;
    var oi: usize = 0;
    while (oi < 26) : (oi += 1) {
        if (nbits < 5) {
            bits = (bits << 8) | digest[di];
            di += 1;
            nbits += 8;
        }
        nbits -= 5;
        out[oi] = crockford_lower[(bits >> @intCast(nbits)) & 0x1f];
    }
    return out;
}

/// Project-relative workspace directory for a case: `<root>/<name>`.
pub fn workspaceDir(arena: std.mem.Allocator, case_id: []const u8, content: []const u8, zig_version: []const u8) std.mem.Allocator.Error![]const u8 {
    const name = workspaceName(case_id, content, zig_version);
    return std.fmt.allocPrint(arena, "{s}/{s}", .{ root, name });
}

pub const GeneratedFile = struct {
    /// Project-relative path; always under the workspace directory.
    rel_path: []const u8,
    contents: []const u8,
};

pub const Plan = struct {
    /// Project-relative workspace directory.
    dir: []const u8,
    files: []const GeneratedFile,
};

/// Plan the files for a Zig doctest case: the snippet goes to
/// `<dir>/src/doctest.zig`. The returned path is confined under `dir`.
pub fn zigPlan(arena: std.mem.Allocator, case_id: []const u8, snippet: []const u8, zig_version: []const u8) std.mem.Allocator.Error!Plan {
    const dir = try workspaceDir(arena, case_id, snippet, zig_version);
    const src_path = try std.fmt.allocPrint(arena, "{s}/src/doctest.zig", .{dir});
    const files = try arena.alloc(GeneratedFile, 1);
    files[0] = .{ .rel_path = src_path, .contents = snippet };
    return .{ .dir = dir, .files = files };
}

/// True only if every planned file path is confined under `plan.dir` (and so can
/// never be a repository source file).
pub fn isConfined(plan: Plan) bool {
    for (plan.files) |f| {
        if (!std.mem.startsWith(u8, f.rel_path, plan.dir)) return false;
        if (f.rel_path.len <= plan.dir.len or f.rel_path[plan.dir.len] != '/') return false;
    }
    return true;
}

pub const MaterializeError = error{WorkspaceCreateFailed} || std.mem.Allocator.Error;

/// Workspace materialization abstraction. The runner never writes files
/// directly; the production provider (filesystem) is injected by the CLI, and
/// tests inject a mock that records the plan without touching disk.
pub const Provider = struct {
    ctx: *anyopaque,
    materializeFn: *const fn (ctx: *anyopaque, plan: Plan) MaterializeError!void,

    pub fn materialize(self: Provider, plan: Plan) MaterializeError!void {
        return self.materializeFn(self.ctx, plan);
    }
};
