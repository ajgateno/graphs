const std = @import("std");
const graph = @import("graph.zig");

const TokenKind = enum {
    ident, // bare word or number: foo, 42
    string, // "quoted text" (quotes stripped)
    arrow, // -> or --
    lbrace,
    rbrace, // { }
    lbracket,
    rbracket, // [ ]
    equals,
    semicolon,
    comma,
    colon,
    eof,
    invalid,
};

const Token = struct {
    kind: TokenKind,
    /// A slice into the source text. Tokens never copy anything.
    text: []const u8,
    line: u32,
};

const Lexer = struct {
    src: []const u8,
    pos: usize = 0,
    line: u32 = 1,

    fn make(self: *Lexer, kind: TokenKind, start: usize) Token {
        return .{ .kind = kind, .text = self.src[start..self.pos], .line = self.line };
    }

    fn peekAt(self: *Lexer, offset: usize) u8 {
        const i = self.pos + offset;
        return if (i < self.src.len) self.src[i] else 0;
    }

    /// Skip whitespace and comments (//, #, and /* ... */).
    fn skipTrivia(self: *Lexer) void {
        while (self.pos < self.src.len) {
            const c = self.src[self.pos];
            if (c == '\n') {
                self.line += 1;
                self.pos += 1;
            } else if (c == ' ' or c == '\t' or c == '\r') {
                self.pos += 1;
            } else if (c == '#' or (c == '/' and self.peekAt(1) == '/')) {
                while (self.pos < self.src.len and self.src[self.pos] != '\n') self.pos += 1;
            } else if (c == '/' and self.peekAt(1) == '*') {
                self.pos += 2;
                while (self.pos < self.src.len and
                    !(self.src[self.pos] == '*' and self.peekAt(1) == '/'))
                {
                    if (self.src[self.pos] == '\n') self.line += 1;
                    self.pos += 1;
                }
                self.pos = @min(self.pos + 2, self.src.len);
            } else break;
        }
    }

    fn isIdentChar(c: u8) bool {
        // Bytes >= 0x80 are parts of UTF-8 characters, so accented
        // and non-Latin names work.
        return std.ascii.isAlphanumeric(c) or c == '_' or c == '.' or c >= 0x80;
    }

    fn next(self: *Lexer) Token {
        self.skipTrivia();
        const start = self.pos;
        if (self.pos >= self.src.len) return self.make(.eof, start);

        const c = self.src[self.pos];
        const single: ?TokenKind = switch (c) {
            '{' => .lbrace,
            '}' => .rbrace,
            '[' => .lbracket,
            ']' => .rbracket,
            '=' => .equals,
            ';' => .semicolon,
            ',' => .comma,
            ':' => .colon,
            else => null,
        };
        if (single) |kind| {
            self.pos += 1;
            return self.make(kind, start);
        }

        if (c == '"') {
            self.pos += 1;
            const body_start = self.pos;
            const line = self.line;
            while (self.pos < self.src.len and self.src[self.pos] != '"') {
                if (self.src[self.pos] == '\\') self.pos += 1; // skip escaped char
                if (self.pos < self.src.len and self.src[self.pos] == '\n') self.line += 1;
                self.pos += 1;
            }
            if (self.pos >= self.src.len) {
                return .{ .kind = .invalid, .text = "unterminated string", .line = line };
            }
            const body = self.src[body_start..self.pos];
            self.pos += 1; // closing quote
            return .{ .kind = .string, .text = body, .line = line };
        }

        if (c == '-') {
            const n = self.peekAt(1);
            if (n == '>' or n == '-') {
                self.pos += 2;
                return self.make(.arrow, start);
            }
            // Otherwise a negative number such as -3.5: fall through.
            self.pos += 1;
        }

        if (isIdentChar(self.peekAt(0)) or self.pos > start) {
            while (self.pos < self.src.len and isIdentChar(self.src[self.pos])) self.pos += 1;
            return self.make(.ident, start);
        }

        self.pos += 1;
        return self.make(.invalid, start);
    }
};

pub const ParseError = error{ UnexpectedToken, UnsupportedSyntax, OutOfMemory };

/// Parse DOT text and add its nodes and edges ot `g`.
/// Nodes are placed at (0,0); run a layout afterwards.
pub fn parse(gpa: std.mem.Allocator, src: []const u8, g: *graph.Graph) ParseError!void {
    var p = Parser{ .gpa = gpa, .lex = .{ .src = src }, .tok = undefined, .g = g };
    defer p.ids.deinit(gpa);
    p.advance(); // load the first token
    try p.parseGraph();
}

const Parser = struct {
    gpa: std.mem.Allocator,
    lex: Lexer,
    tok: Token, // the current token (our one token of lookahead)
    g: *graph.Graph,
    /// Node name -> index. Keys are slices of the source text, which
    /// outlives the parser.
    ids: std.StringHashMapUnmanaged(usize) = .empty,

    fn advance(self: *Parser) void {
        self.tok = self.lex.next();
    }

    fn failWith(self: *Parser, err: ParseError, msg: []const u8) ParseError {
        std.debug.print(
            "DOT error on line {d}: {s} (near '{s}')\n",
            .{ self.tok.line, msg, self.tok.text },
        );
        return err;
    }

    fn expect(self: *Parser, kind: TokenKind, comptime msg: []const u8) ParseError!void {
        if (self.tok.kind != kind) return self.failWith(error.UnexpectedToken, msg);
        self.advance();
    }

    fn isKeyword(self: *Parser, word: []const u8) bool {
        // Keywords are case-insensitive in DOT, and a quoted "node" is a
        // plain name, which is why we check for .ident specifically.
        return self.tok.kind == .ident and std.ascii.eqlIgnoreCase(self.tok.text, word);
    }

    /// Consume a name or quoted string and return its text.
    fn parseId(self: *Parser) ParseError![]const u8 {
        if (self.tok.kind != .ident and self.tok.kind != .string) {
            return self.failWith(error.UnexpectedToken, "expected a name");
        }
        const text = self.tok.text;
        self.advance();
        return text;
    }

    /// Find a node by name, creating it on first mention.
    fn nodeFor(self: *Parser, name: []const u8) ParseError!usize {
        if (self.ids.get(name)) |i| return i;
        const i = try self.g.addNode(self.gpa, name, .{ .x = 0, .y = 0 });
        try self.ids.put(self.gpa, name, i);
        return i;
    }

    // graph : [strict] (graph | digraph) [name] '{' stmt* '}'
    fn parseGraph(self: *Parser) ParseError!void {
        if (self.isKeyword("strict")) self.advance();

        if (self.isKeyword("digraph")) {
            self.g.directed = true;
        } else if (self.isKeyword("graph")) {
            self.g.directed = false;
        } else {
            return self.failWith(error.UnexpectedToken, "expected 'graph' or 'digraph'");
        }
        self.advance();

        if (self.tok.kind == .ident or self.tok.kind == .string) self.advance(); // optional name
        try self.expect(.lbrace, "expected '{'");

        while (self.tok.kind != .rbrace) {
            if (self.tok.kind == .eof) {
                return self.failWith(error.UnexpectedToken, "unexpected end of file, missing '}'");
            }
            try self.parseStmt();
        }
    }

    // [ key = value (;|,)? ... ] -- possibly several lists in a row.
    // Returns the last `label` value seen, if any.
    fn parseAttrs(self: *Parser) ParseError!?[]const u8 {
        var label: ?[]const u8 = null;
        while (self.tok.kind == .lbracket) {
            self.advance();
            while (self.tok.kind != .rbracket) {
                const key = try self.parseId();
                var value: []const u8 = "true";
                if (self.tok.kind == .equals) {
                    self.advance();
                    value = try self.parseId();
                }
                if (std.mem.eql(u8, key, "label")) label = value;
                if (self.tok.kind == .semicolon or self.tok.kind == .comma) self.advance();
            }
            self.advance(); // ']'
        }
        return label;
    }

    fn parseStmt(self: *Parser) ParseError!void {
        if (self.tok.kind == .semicolon) {
            self.advance();
            return;
        }

        // `node [..]`, `edge [..]`, `graph [..]`: defaults. Parsed and ignored.
        if (self.isKeyword("node") or self.isKeyword("edge") or self.isKeyword("graph")) {
            self.advance();
            _ = try self.parseAttrs();
            return;
        }

        if (self.isKeyword("subgraph") or self.tok.kind == .lbrace) {
            return self.failWith(error.UnsupportedSyntax, "subgraphs are not supported yet");
        }

        const first_name = try self.parseId();

        // `rankdir=LR`: a graph-level setting. Read and ignore.
        if (self.tok.kind == .equals) {
            self.advance();
            _ = try self.parseId();
            return;
        }

        if (self.tok.kind == .colon) {
            return self.failWith(error.UnsupportedSyntax, "ports are not supported yet");
        }

        // Node statement or edge chain: a [-> b -> c ...] [attrs]
        var prev = try self.nodeFor(first_name);
        var is_chain = false;
        while (self.tok.kind == .arrow) {
            self.advance();
            const name = try self.parseId();
            const next = try self.nodeFor(name);
            try self.g.addEdge(self.gpa, prev, next);
            prev = next;
            is_chain = true;
        }

        const label = try self.parseAttrs();
        // A label on a plain node statement renames that node's display text.
        // (On an edge chain it would be an edge label, which we don't draw yet.)
        if (!is_chain) {
            if (label) |text| try self.g.setLabel(self.gpa, prev, text);
        }

        if (self.tok.kind == .semicolon) self.advance();
    }
};
