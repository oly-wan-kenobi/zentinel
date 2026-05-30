// Layer: deterministic_core
//
// JSON Lines report renderer (docs/REPORT_FORMAT.md "Report Types": jsonl is for
// streaming or large-run processing). Emits one stable, independently-parseable
// JSON object per line: a header line carrying the run envelope (everything
// except the mutants array), then one line per mutant in canonical order. The
// per-object bytes reuse the canonical report fields, so a streaming consumer
// sees the same data as the canonical JSON report.
const std = @import("std");
const report = @import("report.zig");

const minified = std.json.Stringify.Options{ .whitespace = .minified };

pub fn render(arena: std.mem.Allocator, rep: report.Report) std.mem.Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;

    // Header line: the report envelope without the (streamed) mutants array.
    const header = .{
        .schema_version = rep.schema_version,
        .run = rep.run,
        .baseline = rep.baseline,
        .diagnostics = rep.diagnostics,
        .summary = rep.summary,
    };
    try out.appendSlice(arena, try std.json.Stringify.valueAlloc(arena, header, minified));
    try out.append(arena, '\n');

    for (rep.mutants) |m| {
        try out.appendSlice(arena, try std.json.Stringify.valueAlloc(arena, m, minified));
        try out.append(arena, '\n');
    }

    return out.toOwnedSlice(arena);
}
