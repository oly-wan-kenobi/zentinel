const std = @import("std");
const zentinel = @import("zentinel");

const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;

test "the runtime version and doctest engine version derive from one source" {
    // Regression: the version string used to be declared independently in three
    // places (build.zig.zon, root.version, doctest.workspace.engine_version). A
    // bump in any one without the others desynced cache keys, workspace paths,
    // and the reported version. build.zig.zon is now the single source (injected
    // via build options into src/version.zig); this test guards that wiring
    // stays intact and that both public surfaces keep referencing it.
    try expectEqualStrings(zentinel.version, zentinel.doctest.workspace.engine_version);
    try expect(zentinel.version.len > 0);
}
