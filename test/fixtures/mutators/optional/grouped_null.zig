// Parenthesized null operands: `x == (null)` and `(null) == x`. The shared
// node-based null recognizer unwraps `.grouped_expression` so optional_null_check
// OWNS these (and the comparison mutator skips them), exactly as it does the bare
// `x == null` form. A positional token check saw the `(` and missed them.
pub fn rightGrouped(x: ?i32) bool {
    return x == (null);
}

pub fn leftGrouped(x: ?i32) bool {
    return (null) == x;
}
