//! Audit-cluster regression tests for the CLI surface (cluster prefix
//! `cli_audit_`). Covers run-id collision avoidance (L1) and the route()
//! global-option value guard (L8). Imports only the public `zentinel` core, the
//! sole test-visible surface for the otherwise-private `src/cli.zig` adapter.
const std = @import("std");
const zentinel = @import("zentinel");

// --- L1: run_id collision avoidance ----------------------------------------

test "allocRunId yields a distinct id on each call (run_id collision avoidance)" {
    // Two runs that start in the same millisecond previously produced identical
    // run ids, so each run's end-of-run deleteTree(run_base) wiped the other's
    // live per-mutant sandboxes. The random nonce makes consecutive ids differ
    // even at the same timestamp.
    const a = try zentinel.allocRunId(std.testing.allocator, std.testing.io, "run", 0);
    defer std.testing.allocator.free(a);
    const b = try zentinel.allocRunId(std.testing.allocator, std.testing.io, "run", 0);
    defer std.testing.allocator.free(b);
    try std.testing.expect(!std.mem.eql(u8, a, b));
}

test "allocRunId id shape is prefix_{ts}_{16 hex nonce}" {
    const id = try zentinel.allocRunId(std.testing.allocator, std.testing.io, "run", 0);
    defer std.testing.allocator.free(id);
    // `run_` prefix, then the hex timestamp, then `_`, then exactly 16 lowercase
    // hex nonce chars (8 random bytes).
    try std.testing.expect(std.mem.startsWith(u8, id, "run_0_"));
    const nonce_hex = id["run_0_".len..];
    try std.testing.expectEqual(@as(usize, 16), nonce_hex.len);
    for (nonce_hex) |c| {
        const is_hex = (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f');
        try std.testing.expect(is_hex);
    }
}

test "the doctest run id prefix is also collision-resistant" {
    // The doctest run id (doctest_run_...) uses the same builder, so it gets the
    // same nonce guard as the mutation run id.
    const a = try zentinel.allocRunId(std.testing.allocator, std.testing.io, "doctest_run", 0);
    defer std.testing.allocator.free(a);
    const b = try zentinel.allocRunId(std.testing.allocator, std.testing.io, "doctest_run", 0);
    defer std.testing.allocator.free(b);
    try std.testing.expect(std.mem.startsWith(u8, a, "doctest_run_0_"));
    try std.testing.expect(!std.mem.eql(u8, a, b));
}

test "runIdWithNonce is pure: same inputs match, different nonces differ" {
    const nonce_a = [_]u8{ 0xde, 0xad, 0xbe, 0xef, 0x00, 0x11, 0x22, 0x33 };
    const nonce_b = [_]u8{ 0xde, 0xad, 0xbe, 0xef, 0x00, 0x11, 0x22, 0x34 };

    const id1 = try zentinel.runIdWithNonce(std.testing.allocator, "run", 5, nonce_a);
    defer std.testing.allocator.free(id1);
    const id2 = try zentinel.runIdWithNonce(std.testing.allocator, "run", 5, nonce_a);
    defer std.testing.allocator.free(id2);
    const id3 = try zentinel.runIdWithNonce(std.testing.allocator, "run", 5, nonce_b);
    defer std.testing.allocator.free(id3);

    // Deterministic: identical inputs reproduce the exact id (timestamp 5 -> `5`).
    try std.testing.expectEqualStrings("run_5_deadbeef00112233", id1);
    try std.testing.expectEqualStrings(id1, id2);
    // A distinct nonce yields a distinct id.
    try std.testing.expect(!std.mem.eql(u8, id1, id3));
}

test "runIdWithNonce clamps a negative timestamp to zero" {
    const nonce = [_]u8{0} ** 8;
    const id = try zentinel.runIdWithNonce(std.testing.allocator, "run", -1, nonce);
    defer std.testing.allocator.free(id);
    try std.testing.expectEqualStrings("run_0_0000000000000000", id);
}

// --- L8: route() must not absorb a following option as a global value -------

test "route does not capture --help as the --config value" {
    // `--config --help check`: route must NOT set config_path = "--help" and route
    // to check; it falls through to the frozen dispatch so its clear
    // cli_invalid_option usage error wins.
    const r = zentinel.route(&[_][]const u8{ "--config", "--help", "check" });
    try std.testing.expect(std.meta.activeTag(r) == .passthrough);

    // And the frozen dispatch produces the documented usage error for the option.
    const out = zentinel.dispatch(&[_][]const u8{ "--config", "--help", "check" }, false);
    try std.testing.expectEqual(@as(u8, 2), out.exit_code);
    try std.testing.expectEqual(zentinel.ErrorCode.cli_invalid_option, out.error_code);
}

test "route does not capture an option as the --root value" {
    const r = zentinel.route(&[_][]const u8{ "--root", "--no-color", "check" });
    try std.testing.expect(std.meta.activeTag(r) == .passthrough);
}

test "route still accepts a real --config value followed by a command" {
    // The guard must reject only a following OPTION, not a normal value: a real
    // path is still consumed and the command still routes.
    const r = zentinel.route(&[_][]const u8{ "--config", "custom.toml", "check" });
    switch (r) {
        .check => |globals| {
            try std.testing.expectEqualStrings("custom.toml", globals.config_path);
            try std.testing.expect(globals.config_explicit);
        },
        else => return error.TestUnexpectedRoute,
    }
}

test "route still accepts a real --root value followed by a command" {
    const r = zentinel.route(&[_][]const u8{ "--root", "sub", "run" });
    switch (r) {
        .run => |inv| try std.testing.expectEqualStrings("sub", inv.globals.root),
        else => return error.TestUnexpectedRoute,
    }
}
