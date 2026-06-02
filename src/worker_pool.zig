// Layer: deterministic_core
//
// Bounded worker pool for parallel mutant execution (docs/PERFORMANCE_STRATEGY.md,
// tasks/050-parallel-worker-pool.md). The pool maps work-item indices [0, count)
// to results by INDEX, never by completion order, so the worker count changes
// only concurrency and never which result belongs to which item. The run command
// sorts the report into canonical order afterward, so serial and parallel runs
// produce equivalent reports except for normalized durations. jobs == 1 runs
// inline with no threads -- the conservative default. Per-unit workspace paths
// are content-addressed so concurrent workers never share a writable workspace,
// local .zig-cache, or zig-out directory. Pure scheduling: process execution and
// filesystem I/O are performed by the injected task, not by this module.
const std = @import("std");
const config = @import("config.zig");

/// Hard upper bound on concurrent workers, independent of any configured value,
/// so an over-large `--jobs` / `run.jobs` can never spawn unbounded threads.
pub const max_jobs: usize = 64;

/// A unit of work: process item `index`, optionally using worker lane `slot`
/// (in [0, jobs)) for per-worker scratch. The task writes its own result through
/// the shared `ctx`; the pool never interprets the result.
pub const Task = *const fn (ctx: *anyopaque, index: usize, slot: usize) void;

/// Clamp a requested worker count to `[1, min(count, max_jobs)]`. A zero-work or
/// non-positive request collapses to a single inline worker (conservative).
pub fn effectiveJobs(requested: usize, count: usize) usize {
    if (count == 0) return 1;
    const capped = @min(requested, max_jobs);
    return @max(@as(usize, 1), @min(capped, count));
}

const Shared = struct {
    next: std.atomic.Value(usize),
    count: usize,
    ctx: *anyopaque,
    task: Task,
};

/// Pull item indices off the shared counter until exhausted. Each index is
/// claimed by exactly one worker via an atomic fetch-add, so no item is run
/// twice or skipped regardless of how many workers participate.
fn drain(shared: *Shared, slot: usize) void {
    while (true) {
        const index = shared.next.fetchAdd(1, .seq_cst);
        if (index >= shared.count) return;
        shared.task(shared.ctx, index, slot);
    }
}

/// Run `count` tasks across at most `jobs` workers (after clamping). Each index
/// is processed exactly once and `run` returns only after every task completes,
/// so the caller's result buffer is fully populated. Deterministic in output:
/// the index->result mapping is independent of worker count and scheduling.
pub fn run(jobs: usize, count: usize, ctx: *anyopaque, task: Task) void {
    const workers = effectiveJobs(jobs, count);
    if (workers <= 1 or count <= 1) {
        var i: usize = 0;
        while (i < count) : (i += 1) task(ctx, i, 0);
        return;
    }

    var shared = Shared{
        .next = std.atomic.Value(usize).init(0),
        .count = count,
        .ctx = ctx,
        .task = task,
    };

    var threads: [max_jobs]std.Thread = undefined;
    var spawned: usize = 0;
    var slot: usize = 1;
    while (slot < workers) : (slot += 1) {
        // A spawn failure degrades to fewer workers; correctness is preserved
        // because the calling thread (lane 0) still drains every remaining item.
        threads[spawned] = std.Thread.spawn(.{}, drain, .{ &shared, slot }) catch break;
        spawned += 1;
    }

    drain(&shared, 0);

    var j: usize = 0;
    while (j < spawned) : (j += 1) threads[j].join();
}

/// Dedicated, content-addressed writable workspace root for one mutant run,
/// isolated by run id and mutant id so two concurrent workers never share a
/// directory. The developer working tree is never mutated in place.
pub fn workspaceRoot(arena: std.mem.Allocator, run_id: []const u8, mutant_id: []const u8) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(arena, ".zig-cache/zentinel/workspaces/{s}/{s}", .{ run_id, mutant_id });
}

/// The local Zig build cache for a workspace root, nested inside the root so a
/// worker's `zig build` / `zig test` cache cannot collide with another worker's.
pub fn cacheDirIn(arena: std.mem.Allocator, root: []const u8) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(arena, "{s}/.zig-cache", .{root});
}

/// The local Zig output directory for a workspace root, nested inside the root
/// so a worker's `zig-out` cannot collide with another worker's.
pub fn outDirIn(arena: std.mem.Allocator, root: []const u8) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(arena, "{s}/zig-out", .{root});
}

/// Directories whose entire subtree is excluded from a per-mutant workspace copy:
/// the zentinel-controlled build cache, the build-output dir, and the VCS dir.
/// Matched by exact path SEGMENT (a sibling like `zig-outputs/` is NOT excluded).
const excluded_descent_dirs = [_][]const u8{ ".zig-cache", "zig-out", ".git" };

fn isExcludedDescentDir(basename: []const u8) bool {
    for (excluded_descent_dirs) |name| {
        if (std.mem.eql(u8, basename, name)) return true;
    }
    return false;
}

/// Copy the project tree from `src` into `dst`, descending into every directory
/// EXCEPT `excluded_descent_dirs`. The walker never enters those dirs, which is
/// what keeps a parallel run's per-mutant workspace builders from racing sibling
/// workers tearing down their workspaces under `.zig-cache/zentinel/workspaces`
/// (a transient openDir/copyFile failure there was collapsed into a spurious
/// `invalid` mutant, hiding survivors) and avoids the O(N^2) re-walk of every
/// other worker's copied tree (H3, L7).
///
/// A file whose path matches `copyExcluded` (a raw-prefix legacy filter owned by
/// the caller) is still skipped, so the copied set is byte-identical to the prior
/// full-walk behavior; an entry that escapes `src` by symlink is rejected. `src`
/// must be opened with `iterate = true`.
pub fn copyProjectTree(
    io: std.Io,
    gpa: std.mem.Allocator,
    src: std.Io.Dir,
    dst: std.Io.Dir,
    copyExcluded: *const fn (path: []const u8) bool,
) !void {
    var walker = try src.walkSelectively(gpa);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind == .directory) {
            // Descend only into non-excluded dirs: never enter the cache / build
            // output / VCS trees. This removes the sibling-teardown race and the
            // O(N^2) re-walk that the prior full `walk()` suffered (H3, L7).
            if (!isExcludedDescentDir(entry.basename)) try walker.enter(io, entry);
            continue;
        }
        if (entry.kind != .file) continue;
        if (copyExcluded(entry.path)) continue;
        if (config.pathEscapesRoot(io, src, entry.path)) return error.WorkspaceCreateFailed;
        try src.copyFile(entry.path, dst, entry.path, io, .{ .make_path = true });
    }
}
