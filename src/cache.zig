// Layer: deterministic_core
//
// Cache key construction and cache metadata (docs/PERFORMANCE_STRATEGY.md). This
// module is pure: it computes deterministic result-cache keys and serializes
// cache metadata. It performs no storage — cache reads/writes are a side-effect
// adapter concern wired later, and Phase 1 keeps result reuse disabled (I-013).
const std = @import("std");
const report = @import("report.zig");

const key_namespace = "zentinel.cache.v1";

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
    config_hash: []const u8,
    test_command: []const u8,
    mode: []const u8,
    /// Normalized environment policy label (e.g. "minimal").
    environment: []const u8,
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

/// Deterministic hex result-cache key over the canonical, `\n`-separated input
/// fields. Stable across repeated runs and machines.
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
        inputs.config_hash,
        inputs.test_command,
        inputs.mode,
        inputs.environment,
    };
    for (fields) |f| {
        h.update(f);
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
/// caching (`--no-cache`) from metadata-only key computation (Phase 1 default,
/// no reuse) from full read/write reuse (a later task).
pub const Metadata = struct {
    schema_version: []const u8 = key_namespace,
    enabled: bool,
    mode: report.CacheMode,
    result_keys: []const ResultKey,
    build_cache: BuildCache,
};

/// Deterministic pretty-printed JSON for cache metadata.
pub fn toJson(arena: std.mem.Allocator, metadata: Metadata) std.mem.Allocator.Error![]u8 {
    return std.json.Stringify.valueAlloc(arena, metadata, .{ .whitespace = .indent_2 });
}

/// Wire run cache metadata into the report v1 `diagnostics.cache` field
/// (tasks/052). The reserved report field is the canonical observable location
/// for cache behavior. In Phase 1 result reuse is disabled, so every computed
/// result key is a deterministic miss and there are no hits; with `--no-cache`
/// the cache is disabled and no keys are computed. Cached and uncached runs
/// therefore differ only in this field (and durations).
pub fn toReportDiagnostics(metadata: Metadata) report.CacheDiagnostics {
    return .{
        .enabled = metadata.enabled,
        .mode = metadata.mode,
        .hits = 0,
        .misses = metadata.result_keys.len,
    };
}

// --- Doctest cache ---------------------------------------------------------

const doctest_key_namespace = "zentinel.doctest.cache.v1";

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

/// Deterministic hex SHA-256 doctest cache key over the canonical,
/// `\n`-separated documented input tuple. Stable across runs and machines; any
/// change to a documented input changes the key (conservative invalidation).
pub fn computeDoctestKey(arena: std.mem.Allocator, inputs: DoctestKeyInputs) std.mem.Allocator.Error![]const u8 {
    var h = std.crypto.hash.sha2.Sha256.init(.{});
    var numbuf: [20]u8 = undefined;
    h.update(doctest_key_namespace);
    h.update("\n");
    h.update(inputs.engine_version);
    h.update("\n");
    h.update(inputs.doc_file);
    h.update("\n");
    h.update(std.fmt.bufPrint(&numbuf, "{d}", .{inputs.line_start}) catch unreachable);
    h.update("\n");
    h.update(std.fmt.bufPrint(&numbuf, "{d}", .{inputs.line_end}) catch unreachable);
    h.update("\n");
    h.update(inputs.block_content_hash);
    h.update("\n");
    h.update(inputs.expectation_hash);
    h.update("\n");
    h.update(inputs.zig_version);
    h.update("\n");
    h.update(inputs.command_kind);
    h.update("\n");
    h.update(inputs.config_hash);
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
