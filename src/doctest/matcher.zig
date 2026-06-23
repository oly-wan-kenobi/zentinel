// Layer: deterministic_core
//
// Deterministic doctest expectation matching (docs/DOCTEST_ARCHITECTURE.md
// "Snapshot match modes"). Text modes (exact/contains/regex/diagnostic) compare
// already-normalized strings; JSON modes (json/json_subset/json_unordered)
// compare parsed JSON semantically so object key order never matters. A small
// pure backtracking regex engine avoids any external dependency. Nothing here
// executes code or touches the filesystem.
const std = @import("std");

pub const Mode = enum {
    exact,
    contains,
    regex,
    json,
    json_subset,
    json_unordered,
    diagnostic,

    pub fn toString(self: Mode) []const u8 {
        return @tagName(self);
    }
};

/// Compare `expected` against `actual` under `mode`. Callers pass normalized
/// strings (except a regex `expected`, which is a pattern). Returns whether the
/// actual output satisfies the expectation.
pub fn match(arena: std.mem.Allocator, mode: Mode, expected: []const u8, actual: []const u8) std.mem.Allocator.Error!bool {
    return switch (mode) {
        .exact => exactText(expected, actual),
        .contains => containsText(expected, actual),
        .regex => regexText(arena, expected, actual),
        .diagnostic => diagnosticText(arena, expected, actual),
        .json => jsonText(arena, expected, actual, .exact),
        .json_subset => jsonText(arena, expected, actual, .subset),
        .json_unordered => jsonText(arena, expected, actual, .unordered),
    };
}

// ----- text modes -----

fn exactText(expected: []const u8, actual: []const u8) bool {
    const e = std.mem.trimEnd(u8, expected, " \t\r\n");
    const a = std.mem.trimEnd(u8, actual, " \t\r\n");
    return std.mem.eql(u8, e, a);
}

fn containsText(expected: []const u8, actual: []const u8) bool {
    var cursor: usize = 0;
    var checked = false;
    var it = std.mem.splitScalar(u8, expected, '\n');
    while (it.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;
        checked = true;
        const idx = std.mem.indexOfPos(u8, actual, cursor, line) orelse return false;
        cursor = idx + line.len;
    }
    // An expectation with no non-empty lines asserts nothing. Treating it as a
    // trivially-satisfied containment would let an empty `text output contains`
    // block silently pass against ANY command output, hiding a real regression.
    // Instead require empty (trimmed) actual, matching exact-mode's empty case.
    if (!checked) return std.mem.trim(u8, actual, " \t\r\n").len == 0;
    return true;
}

fn diagnosticText(arena: std.mem.Allocator, expected: []const u8, actual: []const u8) std.mem.Allocator.Error!bool {
    const e = try replaceLineCol(arena, expected);
    const a = try replaceLineCol(arena, actual);
    // A diagnostic expectation that reduces to only positional skeletons (`:N`)
    // and punctuation asserts nothing distinguishing: bare containment would then
    // match any output that merely carries a line:col reference. Require the
    // expectation to carry substantive (alphanumeric) content; otherwise it may
    // only match an equally insubstantial actual.
    if (!hasSubstance(e)) return !hasSubstance(a) and containsText(e, a);
    return containsText(e, a);
}

/// True if `s`, after dropping `:N` line/column placeholders (emitted by
/// `replaceLineCol`), still contains an alphanumeric byte -- i.e. it asserts more
/// than a bare source position.
fn hasSubstance(s: []const u8) bool {
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == ':' and i + 1 < s.len and s[i + 1] == 'N') {
            i += 2;
            continue;
        }
        if (std.ascii.isAlphanumeric(s[i])) return true;
        i += 1;
    }
    return false;
}

/// Collapse `:<digits>` runs (line/column references) to `:N` so diagnostic
/// matching ignores volatile line and column numbers.
fn replaceLineCol(arena: std.mem.Allocator, s: []const u8) std.mem.Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == ':' and i + 1 < s.len and isDigit(s[i + 1])) {
            try out.appendSlice(arena, ":N");
            i += 1;
            while (i < s.len and isDigit(s[i])) i += 1;
        } else {
            try out.append(arena, s[i]);
            i += 1;
        }
    }
    return out.toOwnedSlice(arena);
}

// ----- regex (pure backtracking subset) -----

fn regexText(arena: std.mem.Allocator, pattern: []const u8, actual: []const u8) std.mem.Allocator.Error!bool {
    const re = try compileRegex(arena, pattern);
    return regexSearch(re, actual);
}

const Atom = union(enum) {
    any,
    literal: u8,
    digit,
    word,
    space,
    class: Class,
};

const Class = struct {
    negate: bool,
    ranges: []const Range,
};

const Range = struct { lo: u8, hi: u8 };

const Quant = enum { one, star, plus, opt };

const Token = struct { atom: Atom, quant: Quant };

const Regex = struct {
    anchored_start: bool,
    anchored_end: bool,
    tokens: []const Token,
};

fn compileRegex(arena: std.mem.Allocator, pattern: []const u8) std.mem.Allocator.Error!Regex {
    var tokens: std.ArrayList(Token) = .empty;
    var i: usize = 0;
    var anchored_start = false;
    var anchored_end = false;
    if (pattern.len > 0 and pattern[0] == '^') {
        anchored_start = true;
        i = 1;
    }
    while (i < pattern.len) {
        if (pattern[i] == '$' and i == pattern.len - 1) {
            anchored_end = true;
            break;
        }
        var atom: Atom = undefined;
        if (pattern[i] == '\\' and i + 1 < pattern.len) {
            atom = switch (pattern[i + 1]) {
                'd' => .digit,
                'w' => .word,
                's' => .space,
                else => .{ .literal = pattern[i + 1] },
            };
            i += 2;
        } else if (pattern[i] == '.') {
            atom = .any;
            i += 1;
        } else if (pattern[i] == '[') {
            i += 1;
            var negate = false;
            if (i < pattern.len and pattern[i] == '^') {
                negate = true;
                i += 1;
            }
            var ranges: std.ArrayList(Range) = .empty;
            while (i < pattern.len and pattern[i] != ']') {
                const lo = pattern[i];
                if (i + 2 < pattern.len and pattern[i + 1] == '-' and pattern[i + 2] != ']') {
                    try ranges.append(arena, .{ .lo = lo, .hi = pattern[i + 2] });
                    i += 3;
                } else {
                    try ranges.append(arena, .{ .lo = lo, .hi = lo });
                    i += 1;
                }
            }
            if (i < pattern.len and pattern[i] == ']') i += 1;
            atom = .{ .class = .{ .negate = negate, .ranges = try ranges.toOwnedSlice(arena) } };
        } else {
            atom = .{ .literal = pattern[i] };
            i += 1;
        }
        var quant: Quant = .one;
        if (i < pattern.len) {
            switch (pattern[i]) {
                '*' => {
                    quant = .star;
                    i += 1;
                },
                '+' => {
                    quant = .plus;
                    i += 1;
                },
                '?' => {
                    quant = .opt;
                    i += 1;
                },
                else => {},
            }
        }
        try tokens.append(arena, .{ .atom = atom, .quant = quant });
    }
    return .{ .anchored_start = anchored_start, .anchored_end = anchored_end, .tokens = try tokens.toOwnedSlice(arena) };
}

fn atomMatches(atom: Atom, c: u8) bool {
    return switch (atom) {
        .any => c != '\n',
        .literal => |l| c == l,
        .digit => isDigit(c),
        .word => isWord(c),
        .space => c == ' ' or c == '\t' or c == '\n' or c == '\r',
        .class => |cl| blk: {
            var in = false;
            for (cl.ranges) |r| {
                if (c >= r.lo and c <= r.hi) {
                    in = true;
                    break;
                }
            }
            break :blk in != cl.negate;
        },
    };
}

/// Bounded backtracking budget. This subset engine has no grouped quantifiers,
/// but multiple adjacent `*`/`+`/`?` tokens against a long non-matching input
/// (e.g. `a*a*a*a*a*x` over thousands of `a`s) still drive super-linear
/// backtracking. `step` is charged once per `matchHere` entry; when it is
/// exhausted the engine fails CLOSED -- it reports NO MATCH rather than spinning.
/// A snapshot expectation is never an adversary, so a sane bound never trips on a
/// real pattern; it only caps the cost of a pathological or malformed one.
const Budget = struct {
    /// Remaining `matchHere` invocations before the search aborts as no-match.
    step: usize,

    /// Charge one step. Returns false (no budget left) when the cap is reached, so
    /// callers can short-circuit to a fail-closed no-match.
    fn spend(self: *Budget) bool {
        if (self.step == 0) return false;
        self.step -= 1;
        return true;
    }
};

/// Step ceiling for one `regexSearch`. Generous relative to any real snapshot
/// pattern/output yet small enough that exponential backtracking on adversarial
/// input terminates promptly instead of hanging the run.
const regex_step_budget: usize = 1_000_000;

fn matchHere(re: Regex, ti: usize, text: []const u8, si: usize, budget: *Budget) bool {
    // Fail closed when the backtracking budget is exhausted: a pathological
    // pattern/input pair reports no-match instead of running unbounded.
    if (!budget.spend()) return false;
    if (ti == re.tokens.len) return (!re.anchored_end) or si == text.len;
    const t = re.tokens[ti];
    switch (t.quant) {
        .one => {
            if (si < text.len and atomMatches(t.atom, text[si])) return matchHere(re, ti + 1, text, si + 1, budget);
            return false;
        },
        .opt => {
            if (matchHere(re, ti + 1, text, si, budget)) return true;
            if (si < text.len and atomMatches(t.atom, text[si])) return matchHere(re, ti + 1, text, si + 1, budget);
            return false;
        },
        .star, .plus => {
            var count: usize = 0;
            while (si + count < text.len and atomMatches(t.atom, text[si + count])) count += 1;
            const min: usize = if (t.quant == .plus) 1 else 0;
            if (count < min) return false;
            var k: usize = count;
            while (true) {
                if (matchHere(re, ti + 1, text, si + k, budget)) return true;
                if (k == min) break;
                k -= 1;
            }
            return false;
        },
    }
}

fn regexSearch(re: Regex, text: []const u8) bool {
    // One shared budget across the whole search: the outer start-position loop
    // below multiplies `matchHere` work, so charging per call against a single
    // counter bounds the total, not just any one anchored attempt.
    var budget: Budget = .{ .step = regex_step_budget };
    if (re.anchored_start) return matchHere(re, 0, text, 0, &budget);
    var start: usize = 0;
    while (start <= text.len) : (start += 1) {
        if (matchHere(re, 0, text, start, &budget)) return true;
        // The budget is consumed across all start positions; once gone, no later
        // start can match either, so stop scanning.
        if (budget.step == 0) return false;
    }
    return false;
}

// ----- JSON semantic modes -----

const JMode = enum { exact, subset, unordered };

fn jsonText(arena: std.mem.Allocator, expected: []const u8, actual: []const u8, jmode: JMode) std.mem.Allocator.Error!bool {
    const e = std.json.parseFromSliceLeaky(std.json.Value, arena, expected, .{}) catch return false;
    const a = std.json.parseFromSliceLeaky(std.json.Value, arena, actual, .{}) catch return false;
    return valueMatch(arena, e, a, jmode);
}

const ValueTag = std.meta.Tag(std.json.Value);

fn valueMatch(arena: std.mem.Allocator, e: std.json.Value, a: std.json.Value, jmode: JMode) std.mem.Allocator.Error!bool {
    switch (e) {
        .null => return std.meta.activeTag(a) == .null,
        .bool => |eb| return std.meta.activeTag(a) == .bool and a.bool == eb,
        .integer => |ei| return switch (a) {
            .integer => |ai| ai == ei,
            .float => |af| @as(f64, @floatFromInt(ei)) == af,
            else => false,
        },
        .float => |ef| return switch (a) {
            .float => |af| af == ef,
            .integer => |ai| @as(f64, @floatFromInt(ai)) == ef,
            else => false,
        },
        .number_string => |es| return std.meta.activeTag(a) == .number_string and std.mem.eql(u8, es, a.number_string),
        .string => |es| return std.meta.activeTag(a) == .string and std.mem.eql(u8, es, a.string),
        .array => |ea| {
            if (std.meta.activeTag(a) != .array) return false;
            return arrayMatch(arena, ea, a.array, jmode);
        },
        .object => |eo| {
            if (std.meta.activeTag(a) != .object) return false;
            return objectMatch(arena, eo, a.object, jmode);
        },
    }
}

fn objectMatch(arena: std.mem.Allocator, eo: std.json.ObjectMap, ao: std.json.ObjectMap, jmode: JMode) std.mem.Allocator.Error!bool {
    if (jmode != .subset and eo.count() != ao.count()) return false;
    var it = eo.iterator();
    while (it.next()) |entry| {
        const av = ao.get(entry.key_ptr.*) orelse return false;
        if (!try valueMatch(arena, entry.value_ptr.*, av, jmode)) return false;
    }
    return true;
}

fn arrayMatch(arena: std.mem.Allocator, ea: std.json.Array, aa: std.json.Array, jmode: JMode) std.mem.Allocator.Error!bool {
    switch (jmode) {
        .exact => {
            if (ea.items.len != aa.items.len) return false;
            for (ea.items, aa.items) |ev, av| {
                if (!try valueMatch(arena, ev, av, .exact)) return false;
            }
            return true;
        },
        .subset => {
            if (ea.items.len > aa.items.len) return false;
            for (ea.items, 0..) |ev, idx| {
                if (!try valueMatch(arena, ev, aa.items[idx], .subset)) return false;
            }
            return true;
        },
        .unordered => {
            if (ea.items.len != aa.items.len) return false;
            const used = try arena.alloc(bool, aa.items.len);
            @memset(used, false);
            for (ea.items) |ev| {
                var found = false;
                for (aa.items, 0..) |av, idx| {
                    if (!used[idx] and try valueMatch(arena, ev, av, .unordered)) {
                        used[idx] = true;
                        found = true;
                        break;
                    }
                }
                if (!found) return false;
            }
            return true;
        },
    }
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isWord(c: u8) bool {
    return isDigit(c) or (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
}
