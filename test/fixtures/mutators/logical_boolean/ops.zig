pub fn f(a: bool) bool {
    const x = a and true;
    const y = a or false;
    return x or y;
}
