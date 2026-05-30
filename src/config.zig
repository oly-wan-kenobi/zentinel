// Layer: deterministic_core
//
// Typed zentinel config: parses the in-tree TOML subset (src/config_toml.zig),
// applies documented defaults, validates against docs/CONFIG_SPEC.md, normalizes
// paths, and expands mutator special values deterministically. Pure: no side
// effects beyond the caller-provided arena.
const std = @import("std");
const toml = @import("config_toml.zig");

pub const Code = enum {
    parse_error,
    unknown_key,
    invalid_value,
    invalid_command,
    experimental_backend,
    not_found,

    pub fn token(self: Code) []const u8 {
        return switch (self) {
            .parse_error => "ZNTL_CONFIG_PARSE_ERROR",
            .unknown_key => "ZNTL_CONFIG_UNKNOWN_KEY",
            .invalid_value => "ZNTL_CONFIG_INVALID_VALUE",
            .invalid_command => "ZNTL_CONFIG_INVALID_COMMAND",
            .experimental_backend => "ZNTL_CONFIG_EXPERIMENTAL_BACKEND",
            .not_found => "ZNTL_CONFIG_NOT_FOUND",
        };
    }
};

pub const Diagnostic = struct {
    code: Code = .parse_error,
    section: []const u8 = "",
    key: []const u8 = "",
    message: []const u8 = "",
    line: usize = 0,
};

pub const Error = error{Invalid} || std.mem.Allocator.Error;

pub const Config = struct {
    project_name: []const u8,
    project_root: []const u8,
    include: []const []const u8,
    exclude: []const []const u8,
    zig_version: []const u8,
    zig_modes: []const []const u8,
    backend_default: []const u8,
    backend_experimental: []const []const u8,
    mutators_enabled: []const []const u8,
    test_commands: []const []const u8,
    test_selection: []const u8,
    test_timeout_ms: i64,
    baseline_required: bool,
    run_jobs: i64,
    cache_enabled: bool,
    cache_directory: []const u8,
    report_formats: []const []const u8,
    report_output_dir: []const u8,
    ai_enabled: bool,
    ai_provider: []const u8,
    ai_remote_allowed: bool,
    ai_source_context_lines: i64,
    ai_redact_patterns: []const []const u8,
};

const Stability = enum { stable, preview };
const OperatorInfo = struct { name: []const u8, phase: u8, stability: Stability };

// Operator registry mirrors docs/MUTATOR_SPEC.md (and tests/coverage-gaps/mutators.v1.json).
const operators = [_]OperatorInfo{
    .{ .name = "arithmetic_add_sub", .phase = 1, .stability = .stable },
    .{ .name = "arithmetic_mul_div", .phase = 1, .stability = .stable },
    .{ .name = "equality_swap", .phase = 1, .stability = .stable },
    .{ .name = "comparison_boundary", .phase = 1, .stability = .stable },
    .{ .name = "logical_and_or", .phase = 1, .stability = .stable },
    .{ .name = "boolean_literal", .phase = 1, .stability = .stable },
    .{ .name = "optional_orelse_unreachable", .phase = 2, .stability = .stable },
    .{ .name = "optional_orelse_default", .phase = 2, .stability = .preview },
    .{ .name = "optional_null_check", .phase = 2, .stability = .stable },
    .{ .name = "error_catch_unreachable", .phase = 2, .stability = .stable },
    .{ .name = "error_catch_return", .phase = 2, .stability = .preview },
    .{ .name = "try_to_catch_unreachable", .phase = 2, .stability = .preview },
    .{ .name = "defer_remove", .phase = 2, .stability = .preview },
    .{ .name = "errdefer_remove", .phase = 2, .stability = .stable },
    .{ .name = "allocator_failure_path", .phase = 2, .stability = .preview },
    .{ .name = "comptime_branch_flip", .phase = 2, .stability = .preview },
    .{ .name = "comptime_value_boundary", .phase = 2, .stability = .preview },
    .{ .name = "safety_unreachable_to_return", .phase = 2, .stability = .preview },
    .{ .name = "integer_literal_boundary", .phase = 2, .stability = .stable },
    .{ .name = "loop_boundary", .phase = 2, .stability = .stable },
};

const known_modes = [_][]const u8{ "Debug", "ReleaseSafe", "ReleaseFast", "ReleaseSmall" };
const known_backends = [_][]const u8{ "ast", "zir", "air" };
const known_selections = [_][]const u8{ "same_file_then_package", "same_file", "package", "all" };
const known_providers = [_][]const u8{ "disabled", "stub", "local", "remote" };
const default_exclude = [_][]const u8{ ".zig-cache/**", "zig-out/**", "test/**" };
const default_redact = [_][]const u8{ "(?i)api[_-]?key", "(?i)token" };

// (section, key) pairs accepted by the v1 schema.
const KnownKey = struct { section: []const u8, key: []const u8 };
const known_keys = [_]KnownKey{
    .{ .section = "project", .key = "name" },
    .{ .section = "project", .key = "root" },
    .{ .section = "project", .key = "include" },
    .{ .section = "project", .key = "exclude" },
    .{ .section = "zig", .key = "version" },
    .{ .section = "zig", .key = "modes" },
    .{ .section = "backend", .key = "default" },
    .{ .section = "backend", .key = "experimental" },
    .{ .section = "mutators", .key = "enabled" },
    .{ .section = "test", .key = "commands" },
    .{ .section = "test", .key = "selection" },
    .{ .section = "test", .key = "timeout_ms" },
    .{ .section = "test", .key = "baseline_required" },
    .{ .section = "run", .key = "jobs" },
    .{ .section = "cache", .key = "enabled" },
    .{ .section = "cache", .key = "directory" },
    .{ .section = "report", .key = "formats" },
    .{ .section = "report", .key = "output_dir" },
    .{ .section = "ai", .key = "enabled" },
    .{ .section = "ai", .key = "provider" },
    .{ .section = "ai", .key = "remote_allowed" },
    .{ .section = "ai", .key = "source_context_lines" },
    .{ .section = "ai", .key = "redact_patterns" },
};

fn inList(list: []const []const u8, value: []const u8) bool {
    for (list) |item| {
        if (std.mem.eql(u8, item, value)) return true;
    }
    return false;
}

fn knownKey(section: []const u8, key: []const u8) bool {
    for (known_keys) |kk| {
        if (std.mem.eql(u8, kk.section, section) and std.mem.eql(u8, kk.key, key)) return true;
    }
    return false;
}

fn findOperator(name: []const u8) ?OperatorInfo {
    for (operators) |op| {
        if (std.mem.eql(u8, op.name, name)) return op;
    }
    return null;
}

fn fail(diag: *Diagnostic, code: Code, section: []const u8, key: []const u8, message: []const u8) Error {
    diag.* = .{ .code = code, .section = section, .key = key, .message = message };
    return error.Invalid;
}

const Lookup = struct {
    doc: toml.Document,

    fn find(self: Lookup, section: []const u8, key: []const u8) ?toml.Value {
        for (self.doc.entries) |e| {
            if (std.mem.eql(u8, e.section, section) and std.mem.eql(u8, e.key, key)) return e.value;
        }
        return null;
    }

    fn getString(self: Lookup, section: []const u8, key: []const u8, default: []const u8, diag: *Diagnostic) Error![]const u8 {
        const v = self.find(section, key) orelse return default;
        return switch (v) {
            .string => |s| s,
            else => fail(diag, .invalid_value, section, key, "expected a string"),
        };
    }

    fn getBool(self: Lookup, section: []const u8, key: []const u8, default: bool, diag: *Diagnostic) Error!bool {
        const v = self.find(section, key) orelse return default;
        return switch (v) {
            .boolean => |b| b,
            else => fail(diag, .invalid_value, section, key, "expected a boolean"),
        };
    }

    fn getInt(self: Lookup, section: []const u8, key: []const u8, default: i64, diag: *Diagnostic) Error!i64 {
        const v = self.find(section, key) orelse return default;
        return switch (v) {
            .integer => |n| n,
            else => fail(diag, .invalid_value, section, key, "expected an integer"),
        };
    }

    fn getArray(self: Lookup, section: []const u8, key: []const u8, default: []const []const u8, diag: *Diagnostic) Error![]const []const u8 {
        const v = self.find(section, key) orelse return default;
        return switch (v) {
            .string_array => |a| a,
            else => fail(diag, .invalid_value, section, key, "expected an array of strings"),
        };
    }
};

fn outsideRoot(path: []const u8) bool {
    if (std.fs.path.isAbsolute(path)) return true;
    var it = std.mem.splitScalar(u8, path, '/');
    while (it.next()) |seg| {
        if (std.mem.eql(u8, seg, "..")) return true;
    }
    return false;
}

/// Public form of the project-root containment check. A path is outside the
/// project root when it is absolute or contains a `..` segment. Used by
/// `zentinel check` to validate include/exclude paths (docs/CONFIG_SPEC.md).
pub fn isOutsideRoot(path: []const u8) bool {
    return outsideRoot(path);
}

// Paths are normalized to forward slashes per docs/CONFIG_SPEC.md.
fn normalizePath(arena: std.mem.Allocator, s: []const u8) Error![]const u8 {
    if (std.mem.indexOfScalar(u8, s, '\\') == null) return s;
    const out = try arena.dupe(u8, s);
    for (out) |*c| {
        if (c.* == '\\') c.* = '/';
    }
    return out;
}

fn normalizePaths(arena: std.mem.Allocator, list: []const []const u8) Error![]const []const u8 {
    const out = try arena.alloc([]const u8, list.len);
    for (list, 0..) |p, idx| out[idx] = try normalizePath(arena, p);
    return out;
}

fn expandMutators(arena: std.mem.Allocator, enabled: []const []const u8, diag: *Diagnostic) Error![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (enabled) |item| {
        if (std.mem.eql(u8, item, "phase1")) {
            for (operators) |op| {
                if (op.phase == 1 and op.stability == .stable) try appendUnique(arena, &out, op.name);
            }
        } else if (std.mem.eql(u8, item, "phase2")) {
            for (operators) |op| {
                if (op.phase == 2 and op.stability == .stable) try appendUnique(arena, &out, op.name);
            }
        } else if (std.mem.eql(u8, item, "all_stable")) {
            for (operators) |op| {
                if (op.stability == .stable) try appendUnique(arena, &out, op.name);
            }
        } else if (findOperator(item) != null) {
            try appendUnique(arena, &out, item);
        } else {
            return fail(diag, .invalid_value, "mutators", "enabled", "unknown mutator name");
        }
    }
    return out.toOwnedSlice(arena);
}

fn appendUnique(arena: std.mem.Allocator, list: *std.ArrayList([]const u8), name: []const u8) Error!void {
    for (list.items) |existing| {
        if (std.mem.eql(u8, existing, name)) return;
    }
    try list.append(arena, name);
}

pub fn load(arena: std.mem.Allocator, source: []const u8, diag: *Diagnostic) Error!Config {
    var pdiag: toml.Diagnostic = .{};
    const doc = toml.parse(arena, source, &pdiag) catch {
        diag.* = .{ .code = .parse_error, .message = pdiag.message, .line = pdiag.line };
        return error.Invalid;
    };
    const look = Lookup{ .doc = doc };

    // Reject unknown sections/keys.
    for (doc.entries) |e| {
        if (!knownKey(e.section, e.key)) {
            return fail(diag, .unknown_key, e.section, e.key, "unknown config section or key");
        }
    }

    // [zig]
    const zig_version = try look.getString("zig", "version", "0.16.0", diag);
    if (!std.mem.eql(u8, zig_version, "0.16.0")) {
        return fail(diag, .invalid_value, "zig", "version", "only Zig 0.16.0 is supported");
    }
    const zig_modes = try look.getArray("zig", "modes", &.{"Debug"}, diag);
    if (zig_modes.len > 1) {
        return fail(diag, .invalid_value, "zig", "modes", "multiple modes require task 058 safety-mode matrix");
    }
    for (zig_modes) |m| {
        if (!inList(&known_modes, m)) return fail(diag, .invalid_value, "zig", "modes", "unknown Zig mode");
    }

    // [backend]
    const backend_default = try look.getString("backend", "default", "ast", diag);
    if (!inList(&known_backends, backend_default)) {
        return fail(diag, .invalid_value, "backend", "default", "unknown backend");
    }
    const backend_experimental = try look.getArray("backend", "experimental", &.{}, diag);
    for (backend_experimental) |b| {
        if (!inList(&known_backends, b)) return fail(diag, .invalid_value, "backend", "experimental", "unknown backend");
    }
    if ((std.mem.eql(u8, backend_default, "zir") or std.mem.eql(u8, backend_default, "air")) and
        !inList(backend_experimental, backend_default))
    {
        return fail(diag, .experimental_backend, "backend", "default", "experimental backend requires explicit opt-in");
    }

    // [mutators]
    const enabled_raw = try look.getArray("mutators", "enabled", &.{"phase1"}, diag);
    const mutators_enabled = try expandMutators(arena, enabled_raw, diag);

    // [test]
    const test_commands = try look.getArray("test", "commands", &.{"zig build test"}, diag);
    if (test_commands.len == 0) return fail(diag, .invalid_value, "test", "commands", "test commands must not be empty");
    for (test_commands) |c| {
        if (c.len == 0) return fail(diag, .invalid_value, "test", "commands", "test command must not be empty");
    }
    const test_selection = try look.getString("test", "selection", "same_file_then_package", diag);
    // `impact_graph` is a documented future strategy (task 051). It must be
    // rejected outright, never silently downgraded to same_file_then_package or
    // all (docs/TEST_SELECTION.md).
    if (std.mem.eql(u8, test_selection, "impact_graph")) {
        return fail(diag, .invalid_value, "test", "selection", "impact_graph selection is not available before task 051");
    }
    if (!inList(&known_selections, test_selection)) {
        return fail(diag, .invalid_value, "test", "selection", "unknown or not-yet-supported selection strategy");
    }
    const test_timeout_ms = try look.getInt("test", "timeout_ms", 30000, diag);
    if (test_timeout_ms < 0) return fail(diag, .invalid_value, "test", "timeout_ms", "timeout must not be negative");
    const baseline_required = try look.getBool("test", "baseline_required", true, diag);
    if (!baseline_required) return fail(diag, .invalid_value, "test", "baseline_required", "baseline skipping is reserved for a future policy");

    // [run]
    const run_jobs = try look.getInt("run", "jobs", 1, diag);
    if (run_jobs < 1) return fail(diag, .invalid_value, "run", "jobs", "worker count must be a positive integer");

    // [report]
    const report_output_dir = try normalizePath(arena, try look.getString("report", "output_dir", "zig-out/zentinel", diag));
    if (outsideRoot(report_output_dir)) {
        return fail(diag, .invalid_value, "report", "output_dir", "output directory must stay within the project root");
    }
    const report_formats = try look.getArray("report", "formats", &.{ "text", "json" }, diag);

    // [ai]
    const ai_provider = try look.getString("ai", "provider", "disabled", diag);
    if (!inList(&known_providers, ai_provider)) {
        return fail(diag, .invalid_value, "ai", "provider", "unknown AI provider");
    }
    const ai_remote_allowed = try look.getBool("ai", "remote_allowed", false, diag);
    if (std.mem.eql(u8, ai_provider, "remote") and !ai_remote_allowed) {
        return fail(diag, .invalid_value, "ai", "provider", "remote provider requires remote_allowed = true");
    }
    const ai_context_lines = try look.getInt("ai", "source_context_lines", 4, diag);
    if (ai_context_lines < 0) return fail(diag, .invalid_value, "ai", "source_context_lines", "context lines must not be negative");

    return Config{
        .project_name = try look.getString("project", "name", "example", diag),
        .project_root = try normalizePath(arena, try look.getString("project", "root", ".", diag)),
        .include = try normalizePaths(arena, try look.getArray("project", "include", &.{"src/**/*.zig"}, diag)),
        .exclude = try normalizePaths(arena, try look.getArray("project", "exclude", &default_exclude, diag)),
        .zig_version = zig_version,
        .zig_modes = zig_modes,
        .backend_default = backend_default,
        .backend_experimental = backend_experimental,
        .mutators_enabled = mutators_enabled,
        .test_commands = test_commands,
        .test_selection = test_selection,
        .test_timeout_ms = test_timeout_ms,
        .baseline_required = baseline_required,
        .run_jobs = run_jobs,
        .cache_enabled = try look.getBool("cache", "enabled", true, diag),
        .cache_directory = try normalizePath(arena, try look.getString("cache", "directory", ".zig-cache/zentinel", diag)),
        .report_formats = report_formats,
        .report_output_dir = report_output_dir,
        .ai_enabled = try look.getBool("ai", "enabled", false, diag),
        .ai_provider = ai_provider,
        .ai_remote_allowed = ai_remote_allowed,
        .ai_source_context_lines = ai_context_lines,
        .ai_redact_patterns = try look.getArray("ai", "redact_patterns", &default_redact, diag),
    };
}
