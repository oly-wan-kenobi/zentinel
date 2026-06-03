// Layer: deterministic_core
//
// JUnit XML report renderer (docs/REPORT_FORMAT.md "JUnit Output"). A CI
// integration format derived from the canonical report; it is NOT the canonical
// mutation report. Diagnostic mode never represents survivors as failures; only
// strict survivor-failing mode (the run command's --fail-on-survivors) emits
// <failure type="zentinel.survived">. Suite counts are derived from the emitted
// testcases. Pure: returns bytes, normalizes time to 0 for deterministic
// snapshots.
const std = @import("std");
const report = @import("report.zig");

/// Render the report as a JUnit testsuite. `strict` enables survivor-failing
/// mode (survived mutants additionally emit a <failure>).
pub fn render(arena: std.mem.Allocator, rep: report.Report, strict: bool) std.mem.Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;

    // Derive suite counts from what will be emitted.
    var tests: u32 = 0;
    var failures: u32 = 0;
    var errors: u32 = 0;
    var skipped: u32 = 0;
    if (rep.run.status == .baseline_failed) {
        tests = 1;
        errors = 1;
    } else {
        for (rep.mutants) |m| {
            tests += 1;
            switch (m.result.status) {
                .survived => if (strict) {
                    failures += 1;
                },
                .timeout, .compiler_crash, .invalid => errors += 1,
                .skipped => skipped += 1,
                .killed, .compile_error => {},
            }
        }
    }

    try out.appendSlice(arena, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    try out.print(arena, "<testsuite name=\"zentinel.mutation\" tests=\"{d}\" failures=\"{d}\" errors=\"{d}\" skipped=\"{d}\" time=\"0\">\n", .{ tests, failures, errors, skipped });

    if (rep.run.status == .baseline_failed) {
        try out.appendSlice(arena, "  <testcase classname=\"zentinel.run\" name=\"baseline\">\n");
        try out.appendSlice(arena, "    <error type=\"zentinel.baseline_failed\" message=\"baseline failed; no mutants run\"></error>\n");
        try emitBaselineEvidence(arena, &out, rep);
        try out.appendSlice(arena, "  </testcase>\n");
    } else {
        for (rep.mutants) |m| try emitMutant(arena, &out, m, strict);
    }

    try out.appendSlice(arena, "</testsuite>\n");
    return out.toOwnedSlice(arena);
}

fn emitMutant(arena: std.mem.Allocator, out: *std.ArrayList(u8), m: report.Mutant, strict: bool) std.mem.Allocator.Error!void {
    const name = try std.fmt.allocPrint(arena, "{d} {s} {s}:{d}", .{ m.display_id, m.operator, m.file, m.span.line_start });
    try out.print(arena, "  <testcase classname=\"zentinel.mutant\" name=\"{s}\">\n", .{try escape(arena, name)});

    // Properties: mutant + per-command structured evidence.
    try out.appendSlice(arena, "    <properties>\n");
    try prop(arena, out, "mutant_id", m.id);
    try prop(arena, out, "backend", @tagName(m.backend));
    try prop(arena, out, "backend_stability", @tagName(m.backend_stability));
    try prop(arena, out, "operator", m.operator);
    try prop(arena, out, "operator_stability", @tagName(m.operator_stability));
    try prop(arena, out, "status", @tagName(m.result.status));
    // SEM-1c: the compiler's actual verdict for this mutant (empirical once it has
    // run; the per-operator heuristic for the list-mutants preview). Metadata bag,
    // so it sits alongside backend/operator rather than in the status element.
    try prop(arena, out, "expected_compile", @tagName(m.expected_compile));
    try prop(arena, out, "phase", @tagName(m.result.phase));
    try prop(arena, out, "command_count", try std.fmt.allocPrint(arena, "{d}", .{m.result.commands.len}));
    for (m.result.commands, 0..) |c, i| {
        try prop(arena, out, try std.fmt.allocPrint(arena, "command_{d}_original", .{i}), c.command.original);
        try prop(arena, out, try std.fmt.allocPrint(arena, "command_{d}_argv", .{i}), try joinArgv(arena, c.command.argv));
        try prop(arena, out, try std.fmt.allocPrint(arena, "command_{d}_cwd", .{i}), c.command.cwd);
        try prop(arena, out, try std.fmt.allocPrint(arena, "command_{d}_environment_policy", .{i}), @tagName(c.command.environment_policy));
        try prop(arena, out, try std.fmt.allocPrint(arena, "command_{d}_shell", .{i}), if (c.command.shell) "true" else "false");
        try prop(arena, out, try std.fmt.allocPrint(arena, "command_{d}_status", .{i}), @tagName(c.status));
        try prop(arena, out, try std.fmt.allocPrint(arena, "command_{d}_phase", .{i}), @tagName(c.phase));
        try prop(arena, out, try std.fmt.allocPrint(arena, "command_{d}_skip_reason", .{i}), c.skip_reason orelse "");
    }
    try out.appendSlice(arena, "    </properties>\n");

    // Status element per docs/REPORT_FORMAT.md mapping.
    switch (m.result.status) {
        .killed, .compile_error => {},
        .survived => if (strict) {
            try out.appendSlice(arena, "    <failure type=\"zentinel.survived\" message=\"mutant survived\"></failure>\n");
        },
        .compiler_crash => try out.appendSlice(arena, "    <error type=\"zentinel.compiler_crash\" message=\"compiler crash\"></error>\n"),
        .timeout => try out.appendSlice(arena, "    <error type=\"zentinel.timeout\" message=\"timed out\"></error>\n"),
        .invalid => try out.appendSlice(arena, "    <error type=\"zentinel.invalid\" message=\"invalid candidate\"></error>\n"),
        .skipped => try out.appendSlice(arena, "    <skipped message=\"deterministically skipped\"></skipped>\n"),
    }

    try emitEvidence(arena, out, m.result.evidence);
    try out.appendSlice(arena, "  </testcase>\n");
}

fn emitEvidence(arena: std.mem.Allocator, out: *std.ArrayList(u8), evidence: report.Evidence) std.mem.Allocator.Error!void {
    if (evidence.stdout_excerpt.len > 0) {
        try out.print(arena, "    <system-out>{s}</system-out>\n", .{try escape(arena, evidence.stdout_excerpt)});
    }
    if (evidence.stderr_excerpt.len > 0) {
        try out.print(arena, "    <system-err>{s}</system-err>\n", .{try escape(arena, evidence.stderr_excerpt)});
    }
}

fn emitBaselineEvidence(arena: std.mem.Allocator, out: *std.ArrayList(u8), rep: report.Report) std.mem.Allocator.Error!void {
    var buf: std.ArrayList(u8) = .empty;
    for (rep.baseline.commands) |c| {
        try buf.print(arena, "{s} {s}\n", .{ @tagName(c.status), c.command.original });
    }
    if (buf.items.len > 0) {
        try out.print(arena, "    <system-err>{s}</system-err>\n", .{try escape(arena, buf.items)});
    }
}

fn joinArgv(arena: std.mem.Allocator, argv: []const []const u8) std.mem.Allocator.Error![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    for (argv, 0..) |a, i| {
        if (i > 0) try buf.append(arena, ' ');
        try buf.appendSlice(arena, a);
    }
    return buf.toOwnedSlice(arena);
}

fn prop(arena: std.mem.Allocator, out: *std.ArrayList(u8), name: []const u8, value: []const u8) std.mem.Allocator.Error!void {
    try out.print(arena, "      <property name=\"{s}\" value=\"{s}\"/>\n", .{ name, try escape(arena, value) });
}

/// Escape XML special characters in attribute values and text content.
fn escape(arena: std.mem.Allocator, s: []const u8) std.mem.Allocator.Error![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    for (s) |c| switch (c) {
        '&' => try buf.appendSlice(arena, "&amp;"),
        '<' => try buf.appendSlice(arena, "&lt;"),
        '>' => try buf.appendSlice(arena, "&gt;"),
        '"' => try buf.appendSlice(arena, "&quot;"),
        '\'' => try buf.appendSlice(arena, "&apos;"),
        // Tab, LF, and CR are the only control characters XML 1.0 permits.
        '\t', '\n', '\r' => try buf.append(arena, c),
        // Every other C0 control byte (ANSI ESC \x1b, BEL \x07, ...) and DEL are
        // illegal in XML 1.0; captured Zig output is routinely ANSI-colored, so
        // emitting them verbatim would make a strict CI parser reject the whole
        // testsuite. Replace each with `?` so the JUnit XML is always well-formed
        // (M11).
        0x00...0x08, 0x0b, 0x0c, 0x0e...0x1f, 0x7f => try buf.append(arena, '?'),
        else => try buf.append(arena, c),
    };
    return buf.toOwnedSlice(arena);
}
