//! A small, self-contained JSON-Schema-subset validator over `std.json.Value`.
//!
//! This is deliberately NOT a general JSON-Schema implementation. It supports
//! exactly the keyword subset used by the two schemas shipped in this repo:
//!   - schemas/report.v1.schema.json
//!   - schemas/doctest.report.v1.schema.json
//!
//! Supported keywords (everything those two files actually use):
//!   type (string form and array-of-strings form, e.g. ["integer","null"]),
//!   properties, required, additionalProperties:false (closed objects),
//!   enum, const, items, prefixItems, minItems, maxItems, minLength,
//!   maxLength, minimum, pattern (anchored subset), $ref ("#/$defs/<name>"),
//!   allOf, anyOf, oneOf, if/then/else, not.
//!
//! Intentionally ignored (no-op) annotation keywords: $schema, $id, title,
//! comment, and the schema-document "$defs" container itself.
//!
//! The validator is dependency-free (std only) and deterministic: it walks
//! object members through `std.json.ObjectMap` and reports the first failure.

const std = @import("std");

const Value = std.json.Value;
const ObjectMap = std.json.ObjectMap;

/// Validates `instance` against `schema`. `root` is the schema document used to
/// resolve `$ref` pointers of the form "#/$defs/<name>"; pass the same value as
/// `schema` at the top level.
pub fn validate(schema: Value, instance: Value, root: Value) bool {
    if (schema != .object) {
        // A boolean schema is not used by our documents; treat a non-object as
        // "accept" only when it is the JSON literal `true`.
        return schema == .bool and schema.bool;
    }
    const s = schema.object;

    // $ref short-circuits to the referenced subschema (the referenced schema is
    // applied in addition to any sibling keywords, which our documents never
    // combine, so resolving and continuing is sufficient).
    if (s.get("$ref")) |ref| {
        const target = resolveRef(ref, root) orelse return false;
        if (!validate(target, instance, root)) return false;
    }

    if (s.get("type")) |t| {
        if (!typeMatches(t, instance)) return false;
    }

    if (s.get("const")) |c| {
        if (!valueEql(c, instance)) return false;
    }

    if (s.get("enum")) |e| {
        if (e != .array) return false;
        var found = false;
        for (e.array.items) |candidate| {
            if (valueEql(candidate, instance)) {
                found = true;
                break;
            }
        }
        if (!found) return false;
    }

    if (s.get("minimum")) |m| {
        if (instance == .integer and m == .integer) {
            if (instance.integer < m.integer) return false;
        }
    }

    if (instance == .string) {
        if (s.get("minLength")) |ml| {
            if (ml == .integer and @as(i64, @intCast(instance.string.len)) < ml.integer) return false;
        }
        if (s.get("maxLength")) |ml| {
            if (ml == .integer and @as(i64, @intCast(instance.string.len)) > ml.integer) return false;
        }
        if (s.get("pattern")) |p| {
            if (p == .string and !patternMatch(p.string, instance.string)) return false;
        }
    }

    if (instance == .array) {
        const items = instance.array.items;
        if (s.get("minItems")) |mi| {
            if (mi == .integer and @as(i64, @intCast(items.len)) < mi.integer) return false;
        }
        if (s.get("maxItems")) |mi| {
            if (mi == .integer and @as(i64, @intCast(items.len)) > mi.integer) return false;
        }
        if (s.get("prefixItems")) |pi| {
            if (pi == .array) {
                for (pi.array.items, 0..) |sub, i| {
                    if (i >= items.len) break;
                    if (!validate(sub, items[i], root)) return false;
                }
            }
        }
        if (s.get("items")) |item_schema| {
            var start: usize = 0;
            if (s.get("prefixItems")) |pi| {
                if (pi == .array) start = pi.array.items.len;
            }
            var i: usize = start;
            while (i < items.len) : (i += 1) {
                if (!validate(item_schema, items[i], root)) return false;
            }
        }
    }

    if (instance == .object) {
        const obj = instance.object;

        if (s.get("required")) |req| {
            if (req == .array) {
                for (req.array.items) |name| {
                    if (name != .string) return false;
                    if (obj.get(name.string) == null) return false;
                }
            }
        }

        if (s.get("properties")) |props| {
            if (props == .object) {
                var it = props.object.iterator();
                while (it.next()) |entry| {
                    if (obj.get(entry.key_ptr.*)) |child| {
                        if (!validate(entry.value_ptr.*, child, root)) return false;
                    }
                }
            }
        }

        // additionalProperties:false => closed object. The only form our
        // documents use is the boolean `false`; an object subschema form is not
        // present so we do not implement it.
        if (s.get("additionalProperties")) |ap| {
            if (ap == .bool and ap.bool == false) {
                var it = obj.iterator();
                while (it.next()) |entry| {
                    if (!propertyDeclared(s, entry.key_ptr.*)) return false;
                }
            }
        }
    }

    if (s.get("allOf")) |all| {
        if (all != .array) return false;
        for (all.array.items) |sub| {
            if (!validate(sub, instance, root)) return false;
        }
    }

    if (s.get("anyOf")) |any| {
        if (any != .array) return false;
        var ok = false;
        for (any.array.items) |sub| {
            if (validate(sub, instance, root)) {
                ok = true;
                break;
            }
        }
        if (!ok) return false;
    }

    if (s.get("oneOf")) |one| {
        if (one != .array) return false;
        var count: usize = 0;
        for (one.array.items) |sub| {
            if (validate(sub, instance, root)) count += 1;
        }
        if (count != 1) return false;
    }

    if (s.get("not")) |n| {
        if (validate(n, instance, root)) return false;
    }

    if (s.get("if")) |cond| {
        if (validate(cond, instance, root)) {
            if (s.get("then")) |t| {
                if (!validate(t, instance, root)) return false;
            }
        } else {
            if (s.get("else")) |e| {
                if (!validate(e, instance, root)) return false;
            }
        }
    }

    return true;
}

fn propertyDeclared(schema: ObjectMap, name: []const u8) bool {
    if (schema.get("properties")) |props| {
        if (props == .object and props.object.get(name) != null) return true;
    }
    return false;
}

fn typeMatches(t: Value, instance: Value) bool {
    return switch (t) {
        .string => |name| typeNameMatches(name, instance),
        .array => |arr| blk: {
            for (arr.items) |entry| {
                if (entry == .string and typeNameMatches(entry.string, instance)) break :blk true;
            }
            break :blk false;
        },
        else => false,
    };
}

fn typeNameMatches(name: []const u8, instance: Value) bool {
    if (std.mem.eql(u8, name, "object")) return instance == .object;
    if (std.mem.eql(u8, name, "array")) return instance == .array;
    if (std.mem.eql(u8, name, "string")) return instance == .string;
    if (std.mem.eql(u8, name, "boolean")) return instance == .bool;
    if (std.mem.eql(u8, name, "null")) return instance == .null;
    if (std.mem.eql(u8, name, "integer")) {
        return instance == .integer or (instance == .float and @floor(instance.float) == instance.float);
    }
    if (std.mem.eql(u8, name, "number")) {
        return instance == .integer or instance == .float or instance == .number_string;
    }
    return false;
}

fn valueEql(a: Value, b: Value) bool {
    return switch (a) {
        .null => b == .null,
        .bool => |x| b == .bool and b.bool == x,
        .integer => |x| switch (b) {
            .integer => |y| x == y,
            .float => |y| @as(f64, @floatFromInt(x)) == y,
            else => false,
        },
        .float => |x| switch (b) {
            .float => |y| x == y,
            .integer => |y| x == @as(f64, @floatFromInt(y)),
            else => false,
        },
        .number_string => |x| b == .number_string and std.mem.eql(u8, x, b.number_string),
        .string => |x| b == .string and std.mem.eql(u8, x, b.string),
        .array => false, // not needed by const/enum in our schemas
        .object => false,
    };
}

/// Resolves a "#/$defs/<name>" reference against the schema document `root`.
fn resolveRef(ref: Value, root: Value) ?Value {
    if (ref != .string) return null;
    const prefix = "#/$defs/";
    if (!std.mem.startsWith(u8, ref.string, prefix)) return null;
    const name = ref.string[prefix.len..];
    if (root != .object) return null;
    const defs = root.object.get("$defs") orelse return null;
    if (defs != .object) return null;
    return defs.object.get(name);
}

// --- Anchored regex subset -------------------------------------------------
//
// Supports exactly the constructs used by the schema `pattern` keywords:
//   anchors ^ and $, literal characters, character classes `[...]` with
//   inclusive ranges (e.g. [A-Za-z0-9], [0-9a-hjkmnp-tv-z]), and the
//   quantifiers `+` (one or more) and `{N}` (exactly N) applied to the
//   preceding class. All schema patterns are fully anchored (`^...$`).

/// Returns true when `text` matches the anchored pattern `pat`.
fn patternMatch(pat: []const u8, text: []const u8) bool {
    var pi: usize = 0;
    if (pi < pat.len and pat[pi] == '^') pi += 1 else return false;

    var ti: usize = 0;
    while (pi < pat.len and pat[pi] != '$') {
        if (pat[pi] == '[') {
            const class_end = std.mem.indexOfScalarPos(u8, pat, pi + 1, ']') orelse return false;
            const class = pat[pi + 1 .. class_end];
            pi = class_end + 1;
            // Optional quantifier.
            if (pi < pat.len and pat[pi] == '+') {
                pi += 1;
                var matched: usize = 0;
                while (ti < text.len and charInClass(class, text[ti])) : (ti += 1) matched += 1;
                if (matched == 0) return false;
            } else if (pi < pat.len and pat[pi] == '{') {
                const brace_end = std.mem.indexOfScalarPos(u8, pat, pi + 1, '}') orelse return false;
                const n = std.fmt.parseInt(usize, pat[pi + 1 .. brace_end], 10) catch return false;
                pi = brace_end + 1;
                var k: usize = 0;
                while (k < n) : (k += 1) {
                    if (ti >= text.len or !charInClass(class, text[ti])) return false;
                    ti += 1;
                }
            } else {
                if (ti >= text.len or !charInClass(class, text[ti])) return false;
                ti += 1;
            }
        } else {
            // Literal character.
            if (ti >= text.len or text[ti] != pat[pi]) return false;
            ti += 1;
            pi += 1;
        }
    }

    // A trailing `$` requires the text to be fully consumed.
    if (pi < pat.len and pat[pi] == '$') return ti == text.len;
    // Patterns without a trailing anchor are not used; require full consumption.
    return ti == text.len;
}

fn charInClass(class: []const u8, c: u8) bool {
    var i: usize = 0;
    while (i < class.len) {
        if (i + 2 < class.len and class[i + 1] == '-') {
            if (c >= class[i] and c <= class[i + 2]) return true;
            i += 3;
        } else {
            if (c == class[i]) return true;
            i += 1;
        }
    }
    return false;
}
