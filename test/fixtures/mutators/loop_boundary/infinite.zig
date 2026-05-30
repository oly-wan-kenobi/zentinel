// `while (true)` has no boundary comparison and no integer range end, so the
// loop_boundary mutator must skip it (infinite loop without a static integer
// guard is a forbidden context).
pub fn spin() void {
    while (true) {}
}
