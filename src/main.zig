const std = @import("std");
const lexer = @import("lexer.zig").lexer;
const print = std.debug.print;
const exit = std.os.exit;
const testing = std.testing;
const ArrayList = std.ArrayList;
const alloc = std.heap.page_allocator;
const assert = std.debug.assert;

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
const ParserError = error{ MISSING_COMMA, INVALID_OBJECT, INVALID_KEY_NO_D_QUOTE, INVALID_VALUE, NO_L_SQUARE, NO_R_SQUARE, NO_L_CURLY, NO_R_CURLY, NO_R_D_QUOTE, NO_L_D_QUOTE, INVALID_KEY, DEBUG, EOF_REACHED, INVALID_KV_PAIR, OutOfMemory, MISSING_COLON, INVALID_ARRAY, TRYING_TO_OVERREAD };
const Array = struct { items: ?ArrayList(*ValueT) };
const String = struct { start: usize, end: usize };
const KV_Pair = struct { key: String, value: *ValueT };
const Object = struct { kv_pairs: ?ArrayList(KV_Pair) };
const Value = enum { Array, String, Bool, Null, Number, KV_Pair, Object };
const ValueT = union(Value) { Array: Array, String: String, Bool: String, Null: String, Number: String, KV_Pair: KV_Pair, Object: Object };

pub const TokenStream = struct {
    tokens: ArrayList(Token),
    index: usize,
    lookahead: usize,
    values: ArrayList(ValueT),
    eof: bool,

    pub fn init(tokens: ArrayList(Token)) TokenStream {
        var values = ArrayList(ValueT).init(std.heap.page_allocator);
        return TokenStream{ .index = 0, .lookahead = 0, .tokens = tokens, .values = values, .eof = false };
    }

    // checks if starts with {
    // calls objects
    // else calls value
    fn json(self: *TokenStream) !void {
        const token = try self.current();
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
        if (try self.current() != .L_CURLY) {
            return ParserError.NO_L_CURLY;
        }

        if (try self.next() == .R_CURLY) {
            return ValueT{ .Object = Object{ .kv_pairs = null } };
        }
        _ = try self.prev();

        var kv_pairs = ArrayList(KV_Pair).init(alloc);

        // {} handled above so there is at least one kv_pair
        var kv = try self.kv_pair();
        try kv_pairs.append(kv);

        // should stop generating kv_pairs if has reached '}'
        // if reached .EOF is an error
        while (try self.current() != .EOF) : (_ = try self.next()) {
            switch (try self.current()) {
                .R_CURLY => r_curly: {
                    // hack to start on .COMMA on the next loop
                    if (try self.next() == .COMMA) {
                        _ = try self.prev();
                        break :r_curly;
                    } else if (try self.next() == .R_CURLY) {
                        _ = try self.next();
                        break;
                    } else if (try self.next() == .EOF) {
                        break;
                    } else {
                        return ParserError.INVALID_OBJECT;
                    }
                },
                .COMMA => {
                    var kv1 = try self.kv_pair();
                    try kv_pairs.append(kv1);
                    _ = try self.prev();
                },
                else => return ParserError.MISSING_COMMA,
            }
        } else {
            return ParserError.EOF_REACHED;
        }

        return ValueT{ .Object = Object{ .kv_pairs = kv_pairs } };
    }

    fn value(self: *TokenStream) !*ValueT {
        const res = switch (try self.next()) {
            .L_CURLY => try self.object(),
            .L_SQUARE => try self.array(),
            .D_QUOTE => ValueT{ .String = try self.string() },
            else => return ParserError.INVALID_VALUE,
        };

        try self.values.append(res);
        return self.get_last_value();
    }

    fn kv_pair(self: *TokenStream) ParserError!KV_Pair {
        switch (try self.next()) {
            .D_QUOTE => {
                const key = try self.string();
                if (try self.current() != .COLON) {
                    return ParserError.MISSING_COLON;
                }
                const val = try self.value();
                return KV_Pair{ .key = key, .value = val };
            },
            else => return ParserError.INVALID_KEY,
        }
    }

    fn string(self: *TokenStream) !String {
        const start_index = self.index;

        if (try self.current() != .D_QUOTE) {
            return ParserError.NO_L_D_QUOTE;
        }
        _ = try self.next();

        while (try self.current() != .EOF) : (_ = try self.next()) {
            if (try self.current() == .D_QUOTE) {
                _ = try self.next();
                break;
            }
        } else {
            return ParserError.NO_R_D_QUOTE;
        }

        return String{ .start = start_index, .end = self.index };
    }

    // recursive
    fn array(self: *TokenStream) ParserError!ValueT {
        if (try self.current() != .L_SQUARE) {
            return ParserError.NO_L_SQUARE;
        }

        if (try self.next() == .R_SQUARE) {
            return ValueT{ .Array = Array{ .items = null } };
        }
        _ = try self.prev();

        var items = ArrayList(*ValueT).init(alloc);

        var val = try self.value();
        try items.append(val);

        while (try self.current() != .EOF) : (_ = try self.next()) {
            switch (try self.current()) {
                .R_SQUARE => r_curly: {
                    // hack to start on .COMMA on the next loop
                    if (try self.next() == .COMMA) {
                        _ = try self.prev();
                        break :r_curly;
                    } else if (try self.next() == .R_SQUARE) {
                        _ = try self.next();
                        break;
                    } else if (try self.next() == .EOF) {
                        break;
                    } else {
                        return ParserError.INVALID_ARRAY;
                    }
                },
                .COMMA => {
                    var val1 = try self.value();
                    try items.append(val1);
                    _ = try self.prev();
                },
                else => return ParserError.MISSING_COMMA,
            }
        } else {
            return ParserError.EOF_REACHED;
        }

        return ValueT{ .Array = Array{ .items = items } };
    }

    fn current(self: *TokenStream) ParserError!Token {
        if (self.index == self.tokens.items.len) {
            self.eof = true;
            return .EOF;
        } else {
            return self.tokens.items[self.index];
        }
    }

    fn get_last_value(self: TokenStream) *ValueT {
        return &self.values.items[self.values.items.len - 1];
    }

    fn next(self: *TokenStream) ParserError!Token {
        if (self.eof) {
            return ParserError.TRYING_TO_OVERREAD;
        }

        self.index += 1;

        return try self.current();
    }

    fn prev(self: *TokenStream) ParserError!Token {
        self.index -= 1;

        return try self.current();
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
        \\{"something":"123"}
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(tokens);
    _ = try token_stream.kv_pair();
}

test "kv_pair takes only what belongs to it" {
    const json =
        \\{"something":"123"}
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(tokens);
    _ = try token_stream.kv_pair();

    if (try token_stream.current() != .R_CURLY) {
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
    if (try token_stream.current() != .COLON) {
        return error.STRING_INDEXED_WRONG;
    }
}

test "object empty" {
    const json =
        \\{}
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(tokens);
    var obj = try token_stream.object();

    if (obj.Object.kv_pairs != null) {
        return error.OBJECT_SHOULD_BE_EMPTY;
    }
}

test "object single string value happy path" {
    const json =
        \\{"asd":"asd"}
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(tokens);
    const obj = try token_stream.object();

    assert(obj == .Object);
    assert(obj.Object.kv_pairs.?.items.len == 1);
    assert(obj.Object.kv_pairs.?.items[0].value.* == .String);
}

test "object multiple string value happy path" {
    const json =
        \\{"asd":"asd","123":"!@312312"}
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(tokens);
    const obj = try token_stream.object();

    assert(obj == .Object);
    assert(obj.Object.kv_pairs.?.items.len == 2);
    assert(obj.Object.kv_pairs.?.items[0].value.* == .String);
    assert(obj.Object.kv_pairs.?.items[1].value.* == .String);
}

test "object nested once" {
    const json =
        \\{"asd":{}}
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(tokens);
    const obj = try token_stream.object();
    assert(obj == .Object);
    const obj1 = obj.Object.kv_pairs.?;
    assert(obj1.items.len == 1);
    assert(@TypeOf(obj1.items[0].key) == String);
    assert(obj1.items[0].value.* == .Object);
    assert(obj1.items[0].value.Object.kv_pairs == null);
}

test "object nested n times" {
    const json =
        \\{"asd":{},"1":{}, "asd":{}, "123123123":{}}
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(tokens);
    const obj = try token_stream.object();
    assert(obj.Object.kv_pairs.?.items.len == 4);
}

test "object invalid" {
    const json =
        \\{"asd":{},"1":{}, "asd":{} "123123123":{}}
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(tokens);
    const obj = token_stream.object();
    try testing.expectError(ParserError.INVALID_OBJECT, obj);
}

test "object leading comma" {
    const json =
        \\{"asd":{},}
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(tokens);
    const obj = token_stream.object();
    try testing.expectError(ParserError.INVALID_KEY, obj);
}

test "object takes only what belongs to it" {
    const json =
        \\{"asd":{}},
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(tokens);
    _ = try token_stream.object();
    if (try token_stream.current() != .EOF) {
        return error.OBJECT_INDEXED_WRONG;
    }
}

test "array empty" {
    const json =
        \\[]
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(tokens);
    var arr = try token_stream.array();

    if (arr.Array.items != null) {
        return error.ARRAY_SHOULD_BE_EMPTY;
    }
}

test "array single string value happy path" {
    const json =
        \\["asd"]
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(tokens);
    const arr = try token_stream.array();

    assert(arr == .Array);
    assert(arr.Array.items.?.items.len == 1);
    assert(arr.Array.items.?.items[0].* == .String);
}

test "array multiple string value happy path" {
    const json =
        \\["asd","asd"]
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(tokens);
    const arr = try token_stream.array();

    assert(arr == .Array);
    assert(arr.Array.items.?.items.len == 2);
    assert(arr.Array.items.?.items[0].* == .String);
    assert(arr.Array.items.?.items[1].* == .String);
}

test "array nested once" {
    const json =
        \\[[]]
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(tokens);
    const arr = try token_stream.array();

    assert(arr == .Array);
    const arr1 = arr.Array.items.?;

    assert(arr1.items.len == 1);
    assert(arr1.items[0].* == .Array);
    assert(arr1.items[0].* == .Array);
    assert(arr1.items[0].Array.items == null);
}

test "array nested n times" {
    const json =
        \\[[],[]]
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(tokens);
    const arr = try token_stream.array();
    assert(arr.Array.items.?.items.len == 4);
}

test "array invalid" {
    const json =
        \\["asdas",[]asd]
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(tokens);
    const arr = token_stream.array();
    try testing.expectError(ParserError.INVALID_ARRAY, arr);
}

test "array leading comma" {
    const json =
        \\[ "asd", ]
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(tokens);
    const arr = token_stream.array();
    try testing.expectError(ParserError.INVALID_VALUE, arr);
}

// test "array takes only what belongs to it" {
//     const json =
//         \\["asd"],"asd"]
//     ;
//
//     const tokens = lexer(json);
//     var token_stream = TokenStream.init(tokens);
//     _ = try token_stream.array();
//     if (try token_stream.current() != .EOF) {
//         return error.OBJECT_INDEXED_WRONG;
//     }
// }
