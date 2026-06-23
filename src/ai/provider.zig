// Layer: deterministic_core
//
// AI provider mode (docs/AI_PROVIDER_POLICY.md, docs/AI_CONTEXT_SCHEMA.md). This
// file owns only the provider `Mode` enum and its config-string conversions; the
// command engines (src/ai/command.zig, src/ai/doctest_command.zig) own provider
// resolution, the deterministic stub responses, and validation. AI is ADVISORY
// ONLY: a provider can never influence mutant classification, report statuses, or
// any deterministic-core decision. `disabled` yields no advisory; `stub`/`local`
// are deterministic so prompt/response snapshots are stable and default tests
// never call a live model; `remote` is gated and never invoked by default tests.
const std = @import("std");

pub const Mode = enum { disabled, stub, local, remote };

pub fn modeFromName(name: []const u8) ?Mode {
    if (std.mem.eql(u8, name, "disabled")) return .disabled;
    if (std.mem.eql(u8, name, "stub")) return .stub;
    if (std.mem.eql(u8, name, "local")) return .local;
    if (std.mem.eql(u8, name, "remote")) return .remote;
    return null;
}

pub fn modeName(mode: Mode) []const u8 {
    return @tagName(mode);
}
