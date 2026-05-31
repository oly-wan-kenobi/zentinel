// Impact-analysis fixture (tasks/051): a mutable function plus same-file tests
// in non-alphabetical declaration order, so impact selection ordering is by the
// deterministic (file, line, name) key rather than source or alphabetical order.
pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "zeta covers add of positives" {
    _ = add(1, 2);
}

test "alpha covers add of zero" {
    _ = add(0, 0);
}
