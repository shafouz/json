const std = @import("std");
const lexer = @import("lexer.zig").lexer;
const print = std.debug.print;
const exit = std.os.exit;
const testing = std.testing;
const ArrayList = std.ArrayList;
const alloc = std.heap.page_allocator;

pub fn main() !void {
    const json: []const u8 =
        \\{"somenullthing":"here"}
    ;
    var tokens = lexer(json);
    var token_stream = TokenStream.init(tokens);
    parser(&token_stream);
}

pub fn parser(token_stream: *TokenStream) void {
    token_stream.json() catch {};
}

pub const Token = enum { R_CURLY, L_CURLY, R_SQUARE, L_SQUARE, LITERAL, COMMA, COLON, D_QUOTE, NULL, EOF };
const ParserError = error{ MISSING_COMMA, INVALID_OBJECT, INVALID_KEY_NO_D_QUOTE, INVALID_VALUE, NO_L_SQUARE, NO_R_SQUARE, NO_L_CURLY, NO_R_CURLY, NO_R_D_QUOTE, NO_L_D_QUOTE, INVALID_KEY, DEBUG, EOF_REACHED, INVALID_KV_PAIR };

const String = struct { start: usize, end: usize };
const KV_Pair = struct { key: String, value: *ValueT };
const Object = struct { kv_pairs: ArrayList(KV_Pair) };
const Value = enum { Array, String, Bool, Null, Number, KV_Pair, Object };
const ValueT = union(Value) { Array: String, String: String, Bool: String, Null: String, Number: String, KV_Pair: KV_Pair, Object: Object };

pub const TokenStream = struct {
    tokens: ArrayList(Token),
    index: usize,
    lookahead: usize,
    values: ArrayList(ValueT),

    pub fn init(tokens: ArrayList(Token)) TokenStream {
        var values = ArrayList(ValueT).init(std.heap.page_allocator);
        return TokenStream{ .index = 0, .lookahead = 0, .tokens = tokens, .values = values };
    }

    // checks if starts with {
    // calls objects
    // else calls value
    fn json(self: *TokenStream) !void {
        const token = self.current();
        switch (token) {
            .L_CURLY => {
                _ = try self.object();
            },
            else => {
                // try self.value();
            },
        }
    }

    fn object(self: *TokenStream) !ValueT {
        if (self.current() != .L_CURLY) {
            return ParserError.NO_L_CURLY;
        }

        if (self.next() == .R_CURLY) {
            _ = self.prev();
            return ValueT{ .Object = Object{ .kv_pairs = ArrayList(KV_Pair).init(alloc) } };
        }

        var kv_pairs = ArrayList(KV_Pair).init(alloc);

        // {} handled above so there is at least one kv_pair
        var kv = try self.kv_pair();
        try kv_pairs.append(kv);

        // should stop generating kv_pairs if has reached '}'
        // if reached .EOF is an error
        while (self.current() != .EOF) : (_ = self.next()) {
            switch (self.current()) {
                .R_CURLY => {
                    _ = self.next();
                    break;
                },
                .COMMA => {
                    _ = self.next();
                    var kv1 = try self.kv_pair();
                    try kv_pairs.append(kv1);
                },
                else => return ParserError.MISSING_COMMA,
            }
        } else {
            return ParserError.EOF_REACHED;
        }

        return ValueT{ .Object = Object{ .kv_pairs = kv_pairs } };
    }

    fn value(self: *TokenStream) !*ValueT {
        const res = switch (self.next()) {
            .D_QUOTE => ValueT{ .String = try self.string() },
            else => return ParserError.INVALID_VALUE,
        };

        try self.values.append(res);
        return self.get_last_value();
    }

    fn kv_pair(self: *TokenStream) !KV_Pair {
        switch (self.current()) {
            .D_QUOTE => {
                const key = try self.string();
                if (self.current() != .COLON) {
                    return ParserError.INVALID_KV_PAIR;
                }
                const val = try self.value();
                return KV_Pair{ .key = key, .value = val };
            },
            else => return ParserError.INVALID_KEY_NO_D_QUOTE,
        }
    }

    fn string(self: *TokenStream) !String {
        const start_index = self.index;

        if (self.current() != .D_QUOTE) {
            return ParserError.NO_L_D_QUOTE;
        }
        _ = self.next();

        while (self.current() != .EOF) : (_ = self.next()) {
            if (self.current() == .D_QUOTE) {
                _ = self.next();
                break;
            }
        } else {
            return ParserError.NO_R_D_QUOTE;
        }

        return String{ .start = start_index, .end = self.index };
    }

    // recursive
    fn array(self: *TokenStream) void {
        // const start_index = self.index;

        if (self.current() != .L_SQUARE) {
            return ParserError.NO_L_SQUARE;
        }
        _ = self.next();

        // while (self.current() != .EOF) : (_ = self.next()) {
        //     if (self.current() == .R_SQUARE) {
        //         _ = self.next();
        //         break;
        //     }
        // } else {
        //     return ParserError.NO_R_SQUARE;
        // }

        // return ValueT{ .Array = String{ .start = start_index, .end = self.index } };
        return {};
    }

    fn current(self: *TokenStream) Token {
        if (self.index < self.tokens.items.len) {
            return self.tokens.items[self.index];
        } else {
            return .EOF;
        }
    }

    fn get_last_value(self: TokenStream) *ValueT {
        return &self.values.items[self.values.items.len - 1];
    }

    fn next(self: *TokenStream) Token {
        self.index += 1;

        return self.current();
    }

    fn prev(self: *TokenStream) Token {
        self.index -= 1;

        return self.current();
    }
};

test "string happy path" {
    const json =
        \\"something"
    ;

    var tokens = lexer(json);
    var token_stream = TokenStream.init(tokens);
    const str = try token_stream.string();
    const value = json[str.start..str.end];
    try testing.expectEqualStrings(value, "\"something\"");
}

test "throws NO_R_D_QUOTE" {
    const json =
        \\"something
    ;

    var tokens = lexer(json);
    var token_stream = TokenStream.init(tokens);
    try testing.expectError(ParserError.NO_R_D_QUOTE, token_stream.string());
}

test "throws NO_L_D_QUOTE" {
    const json =
        \\something"
    ;

    var tokens = lexer(json);
    var token_stream = TokenStream.init(tokens);
    try testing.expectError(ParserError.NO_L_D_QUOTE, token_stream.string());
}

test "value returns string" {
    const json =
        \\{"something":123}
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(tokens);
    const val = try token_stream.value();

    if (val.* != .String) {
        return error.WRONG_VALUE_TYPE;
    }

    const str = json[val.String.start..val.String.end];
    if (!(std.mem.eql(u8, str, "\"something\""))) {
        return error.WRONG_STRING_POSITION;
    }
}

test "kv_pair works for string" {
    const json =
        \\"something":"123"}
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(tokens);
    _ = try token_stream.kv_pair();
}

test "kv_pair takes only what belongs to it" {
    const json =
        \\"something":"123"}
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(tokens);
    _ = try token_stream.kv_pair();

    if (token_stream.current() != .R_CURLY) {
        return error.KV_PAIR_INDEXED_WRONG;
    }
}

test "strings takes only what belongs to it" {
    const json =
        \\"something":"123"
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(tokens);
    _ = try token_stream.string();
    if (token_stream.current() != .COLON) {
        return error.STRING_INDEXED_WRONG;
    }
}

test "empty object works" {
    const json =
        \\{}
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(tokens);
    var obj = try token_stream.object();

    if (obj.Object.kv_pairs.items.len != 0) {
        return error.OBJECT_SHOULD_BE_EMPTY;
    }
}

test "single object works" {
    const json =
        \\{"asd":"asd"}
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(tokens);
    const obj = try token_stream.object();
    const kvp = obj.Object.kv_pairs.items[0];
    print("DEBUGPRINT[43]: main.zig:297: kvp.key={any}\n", .{kvp.key});
    print("DEBUGPRINT[43]: main.zig:297: kvp.key={any}\n", .{kvp.value});
}
