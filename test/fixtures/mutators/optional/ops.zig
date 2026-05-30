pub fn unwrap(x: ?i32) i32 {
    return x orelse 0;
}

pub fn isNull(x: ?i32) bool {
    return x == null;
}

pub fn isSet(x: ?i32) bool {
    return x != null;
}

pub fn nullFirst(x: ?i32) bool {
    return null == x;
}
