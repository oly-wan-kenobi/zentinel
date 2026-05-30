// Layer: deterministic_core
//
// Human text report renderer (docs/REPORT_FORMAT.md "Text Output Style"). Default
// output prioritizes actionable survivors over a percentage headline. Pure: takes
// the canonical report and returns bytes; verbosity affects only what is shown,
// never the deterministic report data.
const std = @import("std");
const report = @import("report.zig");

pub const Verbosity = enum { quiet, normal, verbose };

/// Render the report as survivor-focused text. `quiet` prints only the compact
/// summary (and run-level failures); `verbose` lists every mutant; `normal`
/// lists survivors.
pub fn render(arena: std.mem.Allocator, rep: report.Report, verbosity: Verbosity) std.mem.Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;

    if (rep.run.status == .baseline_failed) {
        try out.appendSlice(arena, "baseline failed; no mutants run\n");
        for (rep.baseline.commands) |c| {
            if (c.status != .passed) {
                try out.print(arena, "  baseline {s}: {s}\n", .{ @tagName(c.status), c.command.original });
            }
        }
        return out.toOwnedSlice(arena);
    }

    if (verbosity != .quiet) {
        for (rep.mutants) |m| {
            const show = verbosity == .verbose or m.result.status == .survived;
            if (!show) continue;
            try out.print(arena, "{s} {d} {s} {s}:{d}\n", .{
                @tagName(m.result.status), m.display_id, m.operator, m.file, m.span.line_start,
            });
            for (m.diff) |line| try out.print(arena, "  {s}\n", .{line});
            if (m.test_selection.commands.len > 0) {
                try out.appendSlice(arena, "  selected tests passed:");
                for (m.test_selection.commands) |cmd| try out.print(arena, " {s}", .{cmd});
                try out.append(arena, '\n');
            }
            if (m.advisory.equivalent_risks.len > 0) {
                try out.print(arena, "  likely focus: {s}\n", .{m.advisory.equivalent_risks[0]});
            }
        }
    }

    const s = rep.summary;
    const noun = if (s.total == 1) "mutant" else "mutants";
    try out.print(arena, "{d} {s}: {d} killed, {d} survived\n", .{ s.total, noun, s.killed, s.survived });
    return out.toOwnedSlice(arena);
}
