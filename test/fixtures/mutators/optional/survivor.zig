// The null path of `configOr` is never exercised: no caller/test passes null, so
// the orelse fallback (42) never runs. The optional_orelse_unreachable mutant
// (fallback -> unreachable) therefore SURVIVES, exposing a missing null-path test.
pub fn configOr(x: ?i32) i32 {
    return x orelse 42;
}
