// Small benchmark workload: a few arithmetic operators so a run
// produces multiple mutants to schedule, keeping the benchmark fixture tiny and
// deterministic for trend comparison.
pub fn compute(a: i32, b: i32) i32 {
    return a + b - a * b;
}
