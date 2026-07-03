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

    if (rep.run.status == .internal_error) {
        // Mirror the baseline_failed early return: a run-level failure with no
        // mutant listing. `validate` guarantees `run.error` is non-null here, so
        // surface its stable code and message.
        if (rep.run.@"error") |e| {
            try out.print(arena, "internal error[{s}]: {s}\n", .{ e.code, e.message });
        } else {
            try out.appendSlice(arena, "internal error\n");
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
                // Status-neutral label: in verbose mode this line is printed for
                // every mutant (killed/timeout/compile_error included), so it must
                // not claim the selected tests "passed".
                try out.appendSlice(arena, "  selected tests:");
                for (m.test_selection.commands) |cmd| try out.print(arena, " {s}", .{cmd});
                try out.append(arena, '\n');
            }
            if (m.advisory.equivalent_risks.len > 0) {
                // The field semantically describes mutation-equivalence risks for
                // this survivor, not a test-focus suggestion (the AI context keeps
                // those as separate fields). Label it to match the field meaning.
                try out.print(arena, "  equivalent risk: {s}\n", .{m.advisory.equivalent_risks[0]});
            }
        }
    }

    const s = rep.summary;
    const noun = if (s.total == 1) "mutant" else "mutants";
    try out.print(arena, "{d} {s}: {d} killed, {d} survived\n", .{ s.total, noun, s.killed, s.survived });
    return out.toOwnedSlice(arena);
}
