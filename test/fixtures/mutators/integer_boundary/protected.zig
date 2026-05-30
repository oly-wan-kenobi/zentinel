// Protected literals: none of these are in a branch/range/slice/length-check
// context, so the integer_literal_boundary mutator must leave them untouched.
pub const VERSION: u32 = 16; // version number
pub const MASK: u32 = 255; // ABI/bit-mask constant

pub const Code = enum(u8) {
    ok = 0, // error/enum code
    err = 1,
};

pub fn aligned() void {
    var buf: [8]u8 align(16) = undefined; // array length + alignment
    _ = &buf;
}
