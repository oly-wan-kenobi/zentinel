// Layer: deterministic_core
//
// AI provider plumbing (docs/AI_PROVIDER_POLICY.md, docs/AI_CONTEXT_SCHEMA.md).
// AI is ADVISORY ONLY: a provider produces text under `advisory.*` and can never
// influence mutant classification, report statuses, or any deterministic-core
// decision. The `disabled` mode yields no advisory; `stub` and `local` are
// deterministic (same context -> same advisory) so prompt/response snapshots are
// stable and default tests never call a live model; `remote` is gated and never
// invoked by default tests.
const std = @import("std");

pub const Mode = enum { disabled, stub, local, remote };

pub const Error = error{ ProviderDisabled, RemoteNotAllowed } || std.mem.Allocator.Error;

/// Advisory output. Carries only provider/flow labels and free text; it never
/// contains a mutant status or any field the deterministic core derives.
pub const Advisory = struct {
    provider_mode: []const u8,
    flow: []const u8,
    advice: []const u8,
};

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

/// Inputs a provider may see -- all already-redacted, advisory-safe summary
/// fields drawn from the AI context. No deterministic result field is passed in
/// a way that could be written back.
pub const Request = struct {
    flow: []const u8,
    mutant_id: []const u8,
    operator: []const u8,
};

/// Produce a deterministic advisory for the request, or signal that the provider
/// is disabled / not allowed. `remote` requires `remote_allowed` and, even then,
/// returns a deterministic stand-in here; live remote calls are out of scope for
/// this task and for default tests.
pub fn run(arena: std.mem.Allocator, mode: Mode, remote_allowed: bool, req: Request) Error!Advisory {
    switch (mode) {
        .disabled => return error.ProviderDisabled,
        .remote => {
            if (!remote_allowed) return error.RemoteNotAllowed;
            return deterministicAdvisory(arena, "remote", req);
        },
        .stub => return deterministicAdvisory(arena, "stub", req),
        .local => return deterministicAdvisory(arena, "local", req),
    }
}

fn deterministicAdvisory(arena: std.mem.Allocator, mode_name: []const u8, req: Request) std.mem.Allocator.Error!Advisory {
    const advice = try std.fmt.allocPrint(
        arena,
        "advisory[{s}/{s}]: review tests exercising the {s} operator for mutant {s}",
        .{ mode_name, req.flow, req.operator, req.mutant_id },
    );
    return .{ .provider_mode = mode_name, .flow = req.flow, .advice = advice };
}
