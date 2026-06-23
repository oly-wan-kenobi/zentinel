// Layer: deterministic_core
//
// Config-driven project model (docs/ARCHITECTURE.md lists "discovering source
// files" in the deterministic core). Provides pure glob matching and
// include/exclude eligibility, plus deterministic discovery of eligible source
// files over a directory. `zentinel run` derives the set of mutated files from
// these config rules rather than a hardcoded list.
const std = @import("std");

/// Match a project-relative `path` against a glob `pattern`. `*` matches any run
/// of characters within a single path segment; `**` matches zero or more whole
/// path segments. Matches segment-by-segment over the raw strings without
/// materializing segments into a fixed buffer, so a legitimately-includable file
/// nested arbitrarily deep is never silently dropped from discovery.
pub fn matchGlob(pattern: []const u8, path: []const u8) bool {
    return matchSegments(pattern, path);
}

/// First `/`-delimited segment of `s` (the whole string when there is no `/`).
fn firstSegment(s: []const u8) []const u8 {
    const i = std.mem.indexOfScalar(u8, s, '/') orelse return s;
    return s[0..i];
}

/// The remaining segments after the first, or `null` when none remain. This
/// mirrors `std.mem.splitScalar`: `""` is a single empty segment, `"a/"` is
/// `["a", ""]`, and `restSegments` of a slash-free string is `null` (exhausted).
fn restSegments(s: []const u8) ?[]const u8 {
    const i = std.mem.indexOfScalar(u8, s, '/') orelse return null;
    return s[i + 1 ..];
}

/// Match the `/`-segmented pattern `pat` against the `/`-segmented `path`, where
/// `null` means "no segments remain". Equivalent to the prior segment-array
/// recursion (`pat[1..]` / `path[i..]`) but with the path encoded as the remaining
/// substring, so there is no 64-segment ceiling.
fn matchSegments(pat: ?[]const u8, path: ?[]const u8) bool {
    const p = pat orelse return path == null; // no pattern left -> match iff no path left
    const head = firstSegment(p);
    const rest = restSegments(p);
    if (std.mem.eql(u8, head, "**")) {
        // `**` matches zero or more whole segments: try `rest` against every
        // suffix of `path`, including the empty (null) one.
        var cur: ?[]const u8 = path;
        while (true) {
            if (matchSegments(rest, cur)) return true;
            const c = cur orelse break; // also tried the zero-segments case
            cur = restSegments(c);
        }
        return false;
    }
    const ph = path orelse return false; // pattern needs a segment, path has none
    if (!matchSegment(head, firstSegment(ph))) return false;
    return matchSegments(rest, restSegments(ph));
}

fn matchSegment(pat: []const u8, str: []const u8) bool {
    var pi: usize = 0;
    var si: usize = 0;
    var star_pi: ?usize = null;
    var star_si: usize = 0;
    while (si < str.len) {
        if (pi < pat.len and pat[pi] == str[si]) {
            pi += 1;
            si += 1;
        } else if (pi < pat.len and pat[pi] == '*') {
            star_pi = pi;
            star_si = si;
            pi += 1;
        } else if (star_pi) |sp| {
            pi = sp + 1;
            star_si += 1;
            si = star_si;
        } else {
            return false;
        }
    }
    while (pi < pat.len and pat[pi] == '*') pi += 1;
    return pi == pat.len;
}

/// A path is eligible when it matches at least one include pattern and no exclude
/// pattern.
pub fn isEligible(path: []const u8, include: []const []const u8, exclude: []const []const u8) bool {
    var included = false;
    for (include) |pattern| {
        if (matchGlob(pattern, path)) {
            included = true;
            break;
        }
    }
    if (!included) return false;
    for (exclude) |pattern| {
        if (matchGlob(pattern, path)) return false;
    }
    return true;
}

fn lessThanPath(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

/// Directory basenames whose entire subtree discovery never descends into: the
/// build cache, the build-output dir, and the VCS dir. Pruned by exact basename
/// BEFORE entering, so a parallel run's transient per-mutant workspaces under
/// `.zig-cache` are never walked and the VCS/output trees are never scanned. A
/// sibling like `zig-outputs/` (basename `zig-outputs`, not `zig-out`) is NOT
/// pruned, matching `worker_pool.excluded_descent_dirs`.
const excluded_descent_dirs = [_][]const u8{ ".zig-cache", "zig-out", ".git" };

fn isExcludedDescentDir(basename: []const u8) bool {
    for (excluded_descent_dirs) |name| {
        if (std.mem.eql(u8, basename, name)) return true;
    }
    return false;
}

/// Discover eligible `.zig` source files under `dir`, returned as forward-slashed
/// project-relative paths sorted lexicographically (deterministic).
///
/// Uses `walkSelectively` so excluded directories (`.zig-cache`/`zig-out`/`.git`)
/// are pruned by basename BEFORE descent rather than walked-then-filtered: the
/// cache tree holds a parallel run's transient per-mutant workspaces, so
/// descending it both wastes work and races sibling teardown. The configured
/// `exclude` patterns (which include `cfg.cache.directory`) are still applied as
/// a file-level backstop via `isEligible`, so a cache dir reachable only through
/// the patterns is still dropped.
pub fn discover(
    arena: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    include: []const []const u8,
    exclude: []const []const u8,
) ![][]const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    var walker = try dir.walkSelectively(arena);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind == .directory) {
            // Descend only into non-excluded dirs: never enter the cache / build
            // output / VCS trees (a sibling that merely prefix-collides, like
            // `zig-outputs`, still descends because the basename differs).
            if (!isExcludedDescentDir(entry.basename)) try walker.enter(io, entry);
            continue;
        }
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.path, ".zig")) continue;
        const path = try normalizeSlashes(arena, entry.path);
        if (!isEligible(path, include, exclude)) continue;
        try list.append(arena, path);
    }
    std.mem.sort([]const u8, list.items, {}, lessThanPath);
    return list.toOwnedSlice(arena);
}

fn normalizeSlashes(arena: std.mem.Allocator, s: []const u8) ![]const u8 {
    const out = try arena.dupe(u8, s);
    for (out) |*c| {
        if (c.* == '\\') c.* = '/';
    }
    return out;
}
