pub fn countTo(n: usize) usize {
    var i: usize = 0;
    while (i < n) {
        i += 1;
    }
    return i;
}

pub fn sumRange() usize {
    var total: usize = 0;
    for (0..10) |x| {
        total += x;
    }
    return total;
}
