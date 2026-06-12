// Layer: deterministic_core
//
// Deterministic in-tree TOML subset parser for zentinel.toml.
// Supports exactly: `[section]` tables, bare keys, double-quoted strings (with
// the TOML basic escapes `\\ \" \n \t \r`; any other escape is a parse error),
// `true`/`false` booleans, base-10 integers, arrays of strings (single- or
// multi-line), and `#` comments. Anything outside this subset is a parse error.
// No external TOML dependency (docs/DEPENDENCY_POLICY.md).
const std = @import("std");

pub const Value = union(enum) {
    string: []const u8,
    boolean: bool,
    integer: i64,
    string_array: []const []const u8,
};

pub const Entry = struct {
    section: []const u8,
    key: []const u8,
    value: Value,
    line: usize,
};

pub const Document = struct {
    entries: []const Entry,
};

pub const Diagnostic = struct {
    line: usize = 0,
    message: []const u8 = "",
};

pub const ParseError = error{ParseError} || std.mem.Allocator.Error;

const Parser = struct {
    src: []const u8,
    i: usize = 0,
    line: usize = 1,
    arena: std.mem.Allocator,
    diag: *Diagnostic,

    fn fail(self: *Parser, message: []const u8) ParseError {
        self.diag.* = .{ .line = self.line, .message = message };
        return error.ParseError;
    }

    fn atEnd(self: *Parser) bool {
        return self.i >= self.src.len;
    }

    fn peek(self: *Parser) u8 {
        return self.src[self.i];
    }

    fn advance(self: *Parser) void {
        if (self.src[self.i] == '\n') self.line += 1;
        self.i += 1;
    }

    fn isBareChar(c: u8) bool {
        return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or
            (c >= '0' and c <= '9') or c == '_' or c == '-';
    }

    // Skip spaces, tabs, newlines, and comments.
    fn skipTrivia(self: *Parser) void {
        while (!self.atEnd()) {
            const c = self.peek();
            if (c == ' ' or c == '\t' or c == '\r' or c == '\n') {
                self.advance();
            } else if (c == '#') {
                while (!self.atEnd() and self.peek() != '\n') self.advance();
            } else break;
        }
    }

    // Skip only inline spaces and tabs (not newlines).
    fn skipInline(self: *Parser) void {
        while (!self.atEnd()) {
            const c = self.peek();
            if (c == ' ' or c == '\t' or c == '\r') self.advance() else break;
        }
    }

    fn readBare(self: *Parser) []const u8 {
        const start = self.i;
        while (!self.atEnd() and isBareChar(self.peek())) self.advance();
        return self.src[start..self.i];
    }

    fn readString(self: *Parser) ParseError![]const u8 {
        // Assumes current char is the opening quote.
        self.advance();
        const start = self.i;
        // Fast path: a basic string with no escape sequences is returned as a
        // zero-copy slice of the source. As soon as a backslash appears, switch to a
        // decoded arena copy so the TOML basic escapes (\\ \" \n \t \r) are honored
        // rather than passed through verbatim -- the prior loop kept "a\\b" as two
        // backslashes and terminated early on \".
        while (!self.atEnd()) {
            const c = self.peek();
            if (c == '"') {
                const text = self.src[start..self.i];
                self.advance();
                return text;
            }
            if (c == '\\') return try self.readStringEscaped(start);
            if (c == '\n') return self.fail("unterminated string");
            self.advance();
        }
        return self.fail("unterminated string");
    }

    /// Decode a basic string containing at least one escape. `start` is the first
    /// content byte; `self.i` points at the first backslash. Only the TOML 1.0 basic
    /// escapes are recognized; an unknown escape is a parse error, never silently
    /// kept.
    fn readStringEscaped(self: *Parser, start: usize) ParseError![]const u8 {
        var buf: std.ArrayList(u8) = .empty;
        try buf.appendSlice(self.arena, self.src[start..self.i]); // bytes before the first escape
        while (!self.atEnd()) {
            const c = self.peek();
            if (c == '"') {
                self.advance();
                return try buf.toOwnedSlice(self.arena);
            }
            if (c == '\n') return self.fail("unterminated string");
            if (c == '\\') {
                self.advance();
                if (self.atEnd()) return self.fail("unterminated string");
                const decoded: u8 = switch (self.peek()) {
                    '\\' => '\\',
                    '"' => '"',
                    'n' => '\n',
                    't' => '\t',
                    'r' => '\r',
                    else => return self.fail("invalid escape sequence in string"),
                };
                try buf.append(self.arena, decoded);
                self.advance();
                continue;
            }
            try buf.append(self.arena, c);
            self.advance();
        }
        return self.fail("unterminated string");
    }

    fn readValue(self: *Parser) ParseError!Value {
        const c = self.peek();
        if (c == '"') {
            return .{ .string = try self.readString() };
        }
        if (c == '[') {
            return try self.readArray();
        }
        if (c == 't' or c == 'f') {
            const word = self.readBare();
            if (std.mem.eql(u8, word, "true")) return .{ .boolean = true };
            if (std.mem.eql(u8, word, "false")) return .{ .boolean = false };
            return self.fail("invalid value");
        }
        if (c == '-' or (c >= '0' and c <= '9')) {
            const start = self.i;
            if (c == '-') self.advance();
            while (!self.atEnd() and self.peek() >= '0' and self.peek() <= '9') self.advance();
            const text = self.src[start..self.i];
            const n = std.fmt.parseInt(i64, text, 10) catch return self.fail("invalid integer");
            return .{ .integer = n };
        }
        return self.fail("unsupported value syntax");
    }

    fn readArray(self: *Parser) ParseError!Value {
        self.advance(); // consume '['
        var items: std.ArrayList([]const u8) = .empty;
        while (true) {
            self.skipTrivia();
            if (self.atEnd()) return self.fail("unterminated array");
            if (self.peek() == ']') {
                self.advance();
                break;
            }
            if (self.peek() != '"') return self.fail("array elements must be strings");
            const s = try self.readString();
            try items.append(self.arena, s);
            self.skipTrivia();
            if (self.atEnd()) return self.fail("unterminated array");
            const c = self.peek();
            if (c == ',') {
                self.advance();
            } else if (c == ']') {
                self.advance();
                break;
            } else {
                return self.fail("expected ',' or ']' in array");
            }
        }
        return .{ .string_array = try items.toOwnedSlice(self.arena) };
    }
};

pub fn parse(arena: std.mem.Allocator, source: []const u8, diag: *Diagnostic) ParseError!Document {
    var p = Parser{ .src = source, .arena = arena, .diag = diag };
    var entries: std.ArrayList(Entry) = .empty;
    var section: []const u8 = "";

    while (true) {
        p.skipTrivia();
        if (p.atEnd()) break;

        const c = p.peek();
        if (c == '[') {
            p.advance();
            const name = p.readBare();
            if (name.len == 0) return p.fail("empty section name");
            p.skipInline();
            if (p.atEnd() or p.peek() != ']') return p.fail("unterminated section header");
            p.advance();
            section = name;
            continue;
        }

        if (!Parser.isBareChar(c)) return p.fail("expected section header or key");
        const key_line = p.line;
        const key = p.readBare();
        p.skipInline();
        if (p.atEnd() or p.peek() != '=') return p.fail("expected '=' after key");
        // TOML forbids defining a key twice in the same table, and resolution is
        // first-wins, so a duplicate would silently drop the later value the author
        // wrote. Reject it with a parse error at the redefinition line.
        for (entries.items) |e| {
            if (std.mem.eql(u8, e.section, section) and std.mem.eql(u8, e.key, key)) {
                return p.fail("duplicate key");
            }
        }
        p.advance();
        p.skipInline();
        if (p.atEnd()) return p.fail("missing value");
        const value = try p.readValue();
        try entries.append(arena, .{ .section = section, .key = key, .value = value, .line = key_line });
    }

    return .{ .entries = try entries.toOwnedSlice(arena) };
}
