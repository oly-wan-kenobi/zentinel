// Parenthesized null operands the comparison mutator must SKIP (they belong to
// optional_null_check): `x == (null)` and `(null) == x`. Before the shared
// node-based recognizer, the positional token check saw the `(` and let
// equality_swap emit these -- a disagreement with optional's emit side.
pub fn rightGrouped(x: ?i32) bool {
    return x == (null);
}

pub fn leftGrouped(x: ?i32) bool {
    return (null) == x;
}
