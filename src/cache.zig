// Layer: deterministic_core
//
// Cache key construction and cache metadata (docs/PERFORMANCE_STRATEGY.md). This
// module is pure: it computes deterministic result-cache keys and serializes
// cache metadata. It performs no storage — cache reads/writes are a side-effect
// adapter concern wired later, and Phase 1 keeps result reuse disabled (I-013).
const std = @import("std");
const report = @import("report.zig");

const key_namespace = "zentinel.cache.v2";

/// Every deterministic input that can affect a mutant's observable result
/// (docs/PERFORMANCE_STRATEGY.md "Caching Strategy"). `backend_version` is kept
/// separate from the loose `backend` display name so a backend-mapping change
/// invalidates reuse even when the display name is unchanged.
pub const KeyInputs = struct {
    mutant_id: []const u8,
    zentinel_version: []const u8,
    zig_version: []const u8,
    /// Zig compiler cache namespace metadata when local/global Zig cache
    /// configuration can affect observable command behavior.
    zig_cache_namespace: []const u8,
    backend: []const u8,
    backend_version: []const u8,
    operator: []const u8,
    /// Hex SHA-256 of the mutated file's content (never a bare file path).
    source_hash: []const u8,
    /// Hex SHA-256 over every discovered source path and content hash. This is
    /// required before result reuse because tests may depend on helper files
    /// outside the mutated source.
    project_hash: []const u8,
    config_hash: []const u8,
    /// Canonical injective encoding of the commands actually EXECUTED for this
    /// mutant (may be a narrowed test selection).
    test_command: []const u8,
    /// Canonical injective encoding of the CONFIGURED test suite
    /// (`cfg.test_commands`), kept distinct from `test_command`. A narrowed
    /// survivor's verdict is reverified against the configured suite, so a cached
    /// result is only sound for reuse when BOTH the executed-narrowed commands and
    /// the authoritative configured suite match -- otherwise a key built from a
    /// narrowed command could be served for a configured-suite verdict.
    configured_command: []const u8,
    mode: []const u8,
    /// Normalized environment policy label (e.g. "minimal").
    environment: []const u8,
    /// Hex SHA-256 of the minimal environment key/value set actually passed to
    /// commands. Environment policy alone is too coarse for safe reuse.
    environment_hash: []const u8,
};

fn toHex(arena: std.mem.Allocator, digest: [32]u8) std.mem.Allocator.Error![]const u8 {
    return arena.dupe(u8, &std.fmt.bytesToHex(digest, .lower));
}

/// Hex SHA-256 of arbitrary content (source files, etc.).
pub fn sourceHash(arena: std.mem.Allocator, content: []const u8) std.mem.Allocator.Error![]const u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(content, &digest, .{});
    return toHex(arena, digest);
}

/// Deterministic hex result-cache key over the canonical input fields. Each
/// field is LENGTH-PREFIXED (decimal byte-length + `\n` + bytes) rather than
/// plain newline-joined, so the top-level encoding is injective regardless of a
/// field's contents: a field that itself contains a newline can no longer shift
/// a record boundary and collide two distinct input tuples. Stable across
/// repeated runs and machines.
pub fn computeKey(arena: std.mem.Allocator, inputs: KeyInputs) std.mem.Allocator.Error![]const u8 {
    var h = std.crypto.hash.sha2.Sha256.init(.{});
    const fields = [_][]const u8{
        key_namespace,
        inputs.mutant_id,
        inputs.zentinel_version,
        inputs.zig_version,
        inputs.zig_cache_namespace,
        inputs.backend,
        inputs.backend_version,
        inputs.operator,
        inputs.source_hash,
        inputs.project_hash,
        inputs.config_hash,
        inputs.test_command,
        inputs.configured_command,
        inputs.mode,
        inputs.environment,
        inputs.environment_hash,
    };
    var numbuf: [20]u8 = undefined;
    for (fields) |f| {
        h.update(std.fmt.bufPrint(&numbuf, "{d}", .{f.len}) catch unreachable);
        h.update("\n");
        h.update(f);
    }
    var digest: [32]u8 = undefined;
    h.final(&digest);
    return toHex(arena, digest);
}

fn stringLess(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

/// Deterministic hash of a process environment map: sorted key/value pairs,
/// independent of map iteration order. Used as a result-cache input.
pub fn environmentHash(arena: std.mem.Allocator, env: *const std.process.Environ.Map) std.mem.Allocator.Error![]const u8 {
    const sorted = try arena.dupe([]const u8, env.keys());
    std.mem.sort([]const u8, sorted, {}, stringLess);

    var h = std.crypto.hash.sha2.Sha256.init(.{});
    h.update("zentinel.environment.v1\n");
    for (sorted) |key| {
        h.update(key);
        h.update("\n");
        h.update(env.get(key) orelse "");
        h.update("\n");
    }
    var digest: [32]u8 = undefined;
    h.final(&digest);
    return toHex(arena, digest);
}

/// One mutant's result-cache key.
pub const ResultKey = struct {
    mutant_id: []const u8,
    key: []const u8,
};

/// Zig build-cache reuse metadata, kept distinct from the zentinel result cache.
/// A warm Zig build cache may reduce compile time but must not change report
/// statuses; isolation metadata ensures workspaces do not corrupt each other.
pub const BuildCache = struct {
    namespace: []const u8,
    isolated: bool,
};

/// Serializable cache metadata for a run. `mode` distinguishes disabled result
/// caching (`--no-cache`) from metadata-only key computation (no reuse: keys are
/// computed but never consulted) from full read/write reuse (`read_write`, when a
/// result store is wired and a terminal verdict is served/persisted).
pub const Metadata = struct {
    schema_version: []const u8 = key_namespace,
    enabled: bool,
    mode: report.CacheMode,
    result_keys: []const ResultKey,
    build_cache: BuildCache,
    /// How many of the cacheable mutants this run served from a prior run's store
    /// (the rest of `result_keys` were computed fresh). Carried so the report's
    /// `diagnostics.cache.hits` reflects reality, but DELIBERATELY excluded from
    /// the serialized cache artifact (see `jsonStringify`) so the on-disk
    /// `cache.json` shape -- and every committed snapshot of it -- is unchanged.
    hits: u64 = 0,

    /// Custom serialization that emits exactly the original five artifact fields
    /// and omits the run-local `hits` counter, so the cache metadata JSON is
    /// byte-identical to the prior reflection-based encoding.
    pub fn jsonStringify(self: Metadata, jws: *std.json.Stringify) std.json.Stringify.Error!void {
        try jws.beginObject();
        try jws.objectField("schema_version");
        try jws.write(self.schema_version);
        try jws.objectField("enabled");
        try jws.write(self.enabled);
        try jws.objectField("mode");
        try jws.write(self.mode);
        try jws.objectField("result_keys");
        try jws.write(self.result_keys);
        try jws.objectField("build_cache");
        try jws.write(self.build_cache);
        try jws.endObject();
    }
};

/// Deterministic pretty-printed JSON for cache metadata.
pub fn toJson(arena: std.mem.Allocator, metadata: Metadata) std.mem.Allocator.Error![]u8 {
    return std.json.Stringify.valueAlloc(arena, metadata, .{ .whitespace = .indent_2 });
}

/// Wire run cache metadata into the report v1 `diagnostics.cache` field. The
/// reserved report field is the canonical observable location for cache behavior.
/// `result_keys` covers every cacheable mutant (terminal verdicts only); `hits`
/// is how many were served from a prior run's store, so `misses` -- the mutants
/// computed fresh -- is the remainder. With `--no-cache` the cache is disabled, no
/// keys are computed, and both counts are zero. When no result store is wired,
/// reuse stays off, so `hits` is zero and every cacheable mutant is a miss
/// (metadata-only): cached and uncached runs then differ only in this field (and
/// durations).
pub fn toReportDiagnostics(metadata: Metadata) report.CacheDiagnostics {
    return .{
        .enabled = metadata.enabled,
        .mode = metadata.mode,
        .hits = metadata.hits,
        .misses = metadata.result_keys.len - metadata.hits,
    };
}

// --- Doctest cache ---------------------------------------------------------

const doctest_key_namespace = "zentinel.doctest.cache.v2";

/// Every deterministic input that can affect a doctest case's observable result
/// (docs/DOCTEST_ARCHITECTURE.md "Caching Opportunities"). Line numbers are
/// cache inputs (a moved block is a different cache entry); content hashes are
/// used instead of timestamps, and the doc path is project-relative.
pub const DoctestKeyInputs = struct {
    /// Doctest engine version: bumping it invalidates every cached entry.
    engine_version: []const u8,
    /// Project-relative documentation path.
    doc_file: []const u8,
    line_start: u32,
    line_end: u32,
    /// Hex SHA-256 of the grouped producer block content.
    block_content_hash: []const u8,
    /// Hex SHA-256 of the grouped expectation block content ("" when none).
    expectation_hash: []const u8,
    zig_version: []const u8,
    /// Case command kind (cli/zig_test/config/...): selects the execution path.
    command_kind: []const u8,
    config_hash: []const u8,
};

/// Deterministic hex SHA-256 doctest cache key over the canonical documented
/// input tuple. Each field is LENGTH-PREFIXED (decimal byte-length + `\n` +
/// bytes) rather than plain newline-joined, so the top-level encoding is
/// injective regardless of a field's contents (a doc path or block hash that
/// itself contains a newline can no longer shift a record boundary). The two
/// numeric line fields are decimal-formatted, then length-prefixed like the rest.
/// Stable across runs and machines; any change to a documented input changes the
/// key (conservative invalidation).
pub fn computeDoctestKey(arena: std.mem.Allocator, inputs: DoctestKeyInputs) std.mem.Allocator.Error![]const u8 {
    var h = std.crypto.hash.sha2.Sha256.init(.{});
    var linebuf: [20]u8 = undefined;
    const line_start = std.fmt.bufPrint(&linebuf, "{d}", .{inputs.line_start}) catch unreachable;
    var linebuf2: [20]u8 = undefined;
    const line_end = std.fmt.bufPrint(&linebuf2, "{d}", .{inputs.line_end}) catch unreachable;
    const fields = [_][]const u8{
        doctest_key_namespace,
        inputs.engine_version,
        inputs.doc_file,
        line_start,
        line_end,
        inputs.block_content_hash,
        inputs.expectation_hash,
        inputs.zig_version,
        inputs.command_kind,
        inputs.config_hash,
    };
    var numbuf: [20]u8 = undefined;
    for (fields) |f| {
        h.update(std.fmt.bufPrint(&numbuf, "{d}", .{f.len}) catch unreachable);
        h.update("\n");
        h.update(f);
    }
    var digest: [32]u8 = undefined;
    h.final(&digest);
    return toHex(arena, digest);
}

/// One doctest case's cache key.
pub const DoctestCaseKey = struct {
    case_id: []const u8,
    kind: []const u8,
    key: []const u8,
};

/// Serializable doctest cache metadata. `mode` is `metadata_only` in this phase:
/// keys are computed but never used to skip execution, so a doctest report is
/// identical whether or not the cache is enabled.
pub const DoctestMetadata = struct {
    schema_version: []const u8 = doctest_key_namespace,
    engine_version: []const u8,
    enabled: bool,
    mode: report.CacheMode,
    case_keys: []const DoctestCaseKey,
};

pub fn doctestMetadataToJson(arena: std.mem.Allocator, metadata: DoctestMetadata) std.mem.Allocator.Error![]u8 {
    return std.json.Stringify.valueAlloc(arena, metadata, .{ .whitespace = .indent_2 });
}
