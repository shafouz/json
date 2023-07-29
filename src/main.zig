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
    var token_stream = TokenStream.init(json, tokens);
    parser(&token_stream);
}

pub fn parser(token_stream: *TokenStream) void {
    token_stream.json() catch {};
}

pub const Token = enum { R_CURLY, L_CURLY, R_SQUARE, L_SQUARE, LITERAL, COMMA, COLON, D_QUOTE, NULL, EOF };
pub const TokenT = union(Token) { R_CURLY, L_CURLY, R_SQUARE, L_SQUARE, LITERAL: u8, COMMA, COLON, D_QUOTE, NULL, EOF };
const ParserError = error{ MISSING_COMMA, INVALID_OBJECT, INVALID_KEY_NO_D_QUOTE, INVALID_VALUE, NO_L_SQUARE, NO_R_SQUARE, NO_L_CURLY, NO_R_CURLY, NO_R_D_QUOTE, NO_L_D_QUOTE, INVALID_KEY, DEBUG, EOF_REACHED, INVALID_KV_PAIR, OutOfMemory, MISSING_COLON, INVALID_ARRAY, TRYING_TO_UNDERREAD, TRYING_TO_OVERREAD };
const Array = struct { items: ?ArrayList(*ValueT) };
const Bool = struct { start: usize, end: usize };
const String = struct { start: usize, end: usize };
const Number = struct { start: usize, end: usize };
const Null = struct { start: usize, end: usize };
const KV_Pair = struct { key: String, value: *ValueT };
const Object = struct { kv_pairs: ?ArrayList(KV_Pair) };
const Value = enum { Array, String, Bool, Null, Number, KV_Pair, Object };
const ValueT = union(Value) { Array: Array, String: String, Bool: Bool, Null: Null, Number: Number, KV_Pair: KV_Pair, Object: Object };

pub const TokenStream = struct {
    src: []const u8,
    tokens: ArrayList(TokenT),
    index: usize,
    lookahead: usize,
    values: ArrayList(ValueT),
    eof: bool,

    pub fn init(src: []const u8, tokens: ArrayList(TokenT)) TokenStream {
        var values = ArrayList(ValueT).init(std.heap.page_allocator);
        return TokenStream{ .src = src, .index = 0, .lookahead = 0, .tokens = tokens, .values = values, .eof = false };
    }

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

    fn object(self: *TokenStream) ParserError!ValueT {
        if (self.current() != .L_CURLY) {
            return ParserError.NO_L_CURLY;
        }
        // takes {
        _ = try self.next();

        if (self.current() == .R_CURLY) {
            // takes } if its done
            _ = try self.next();
            return ValueT{ .Object = Object{ .kv_pairs = null } };
        }

        var kv_pairs = ArrayList(KV_Pair).init(alloc);

        // {X
        //  ^
        var kv = try self.kv_pair();
        try kv_pairs.append(kv);

        // should stop generating kv_pairs if has reached '}'
        // if reached .EOF is an error
        while (self.current() != .EOF) : (_ = try self.next()) {
            switch (self.current()) {
                .R_CURLY => {
                    _ = try self.next();
                    break;
                },
                .COMMA => {
                    _ = try self.next();
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

    // fn _null(self: *TokenStream) !Null {}
    //
    // fn _bool(self: *TokenStream) !Bool {}
    //
    // fn _number(self: *TokenStream) !Number {}

    fn value(self: *TokenStream) !*ValueT {
        const res = switch (self.current()) {
            .L_CURLY => try self.object(),
            .L_SQUARE => try self.array(),
            .D_QUOTE => ValueT{ .String = try self.string() },
            // .LITERAL => |char| literal: {
            //     switch (char) {
            //         'n' => break :literal ValueT{ .Null = try self._null() },
            //         // 'f' | 't' => ValueT{ .Bool = try self._bool() },
            //         // 0...9 => self.number(),
            //         else => return ParserError.INVALID_VALUE,
            //     }
            // },
            //     // bool
            //     // number
            //     // null
            // },
            else => return ParserError.INVALID_VALUE,
        };

        try self.values.append(res);
        return self.get_last_value();
    }

    fn kv_pair(self: *TokenStream) ParserError!KV_Pair {
        switch (self.current()) {
            .D_QUOTE => {
                const key = try self.string();
                if (self.current() != .COLON) {
                    return ParserError.MISSING_COLON;
                }
                _ = try self.next();

                const val = try self.value();
                return KV_Pair{ .key = key, .value = val };
            },
            else => return ParserError.INVALID_KEY,
        }
    }

    fn string(self: *TokenStream) !String {
        const start_index = self.index;

        if (self.current() != .D_QUOTE) {
            return ParserError.NO_L_D_QUOTE;
        }
        _ = try self.next();

        while (self.current() != .EOF) : (_ = try self.next()) {
            if (self.current() == .D_QUOTE) {
                _ = try self.next();
                break;
            }
        } else {
            return ParserError.NO_R_D_QUOTE;
        }

        return String{ .start = start_index, .end = self.index };
    }

    fn array(self: *TokenStream) ParserError!ValueT {
        if (self.current() != .L_SQUARE) {
            return ParserError.NO_L_SQUARE;
        }
        // takes [
        _ = try self.next();

        if (self.current() == .R_SQUARE) {
            // takes ] if its done
            _ = try self.next();
            return ValueT{ .Array = Array{ .items = null } };
        }

        var items = ArrayList(*ValueT).init(alloc);

        // [X
        //  ^
        var val = try self.value();
        try items.append(val);

        while (self.current() != .EOF) : (_ = try self.next()) {
            switch (self.current()) {
                .R_SQUARE => {
                    _ = try self.next();
                    break;
                },
                .COMMA => {
                    _ = try self.next();
                    var val1 = try self.value();
                    try items.append(val1);

                    // ]]
                    //  ^
                    // at the end of the loop
                    // ]]
                    //   ^
                    // so we roll back one
                    // ]]
                    //  ^
                    _ = try self.prev();
                },
                else => return ParserError.MISSING_COMMA,
            }
        } else {
            return ParserError.EOF_REACHED;
        }

        return ValueT{ .Array = Array{ .items = items } };
    }

    fn get_string(self: *TokenStream, str: String) []const u8 {
        return self.src[str.start..str.end];
    }

    fn get_keys(obj: ValueT) ![]String {
        if (obj != .Object) {
            return error.EXPECTED_OBJECT;
        }

        const kv_pairs = obj.Object.kv_pairs.?.items;
        var keys = try alloc.alloc(String, kv_pairs.len);

        for (kv_pairs, 0..) |kv, i| {
            keys[i] = kv.key;
        }
        return keys;
    }

    fn assert_src(self: *TokenStream, expected: []const u8) !void {
        const assertion = std.mem.eql(u8, expected, self.current_src());
        if (!assertion) {
            print("\n{s}\n", .{expected});
            print("{s}\n", .{self.current_src()});
            return error.ASSERTION_FAILED;
        } else {
            print("\n{s}\n", .{expected});
            print("{s}\n", .{self.current_src()});
            print("OK\n", .{});
        }
    }

    fn current_src(self: *TokenStream) []const u8 {
        return self.src[0..self.index];
    }

    fn get_last_value(self: *TokenStream) *ValueT {
        return &self.values.items[self.values.items.len - 1];
    }

    fn current(self: *TokenStream) TokenT {
        if (self.index >= self.tokens.items.len) {
            self.eof = true;
            return .EOF;
        } else {
            return self.tokens.items[self.index];
        }
    }

    fn peek(self: *TokenStream) TokenT {
        self.index += 1;
        defer self.index -= 1;
        return self.current();
    }

    fn next(self: *TokenStream) ParserError!TokenT {
        if (self.eof) {
            // TODO: rename
            return ParserError.TRYING_TO_OVERREAD;
        }

        self.index += 1;

        return self.current();
    }

    fn prev(self: *TokenStream) ParserError!TokenT {
        if (self.index <= 0) {
            // TODO: rename
            return ParserError.TRYING_TO_UNDERREAD;
        }

        self.index -= 1;

        return self.current();
    }
};

test "string happy path" {
    const json =
        \\"something"
    ;

    var tokens = lexer(json);
    var token_stream = TokenStream.init(json, tokens);
    const str = try token_stream.string();
    const value = json[str.start..str.end];
    try testing.expectEqualStrings(value, "\"something\"");
}

test "throws NO_R_D_QUOTE" {
    const json =
        \\"something
    ;

    var tokens = lexer(json);
    var token_stream = TokenStream.init(json, tokens);
    try testing.expectError(ParserError.NO_R_D_QUOTE, token_stream.string());
}

test "throws NO_L_D_QUOTE" {
    const json =
        \\something"
    ;

    var tokens = lexer(json);
    var token_stream = TokenStream.init(json, tokens);
    try testing.expectError(ParserError.NO_L_D_QUOTE, token_stream.string());
}

test "kv_pair correct index empty object" {
    const json =
        \\"something":{}}
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(json, tokens);
    _ = try token_stream.kv_pair();

    const expected =
        \\"something":{}
    ;
    try token_stream.assert_src(expected);
}

test "value takes empty object" {
    const json =
        \\{}
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(json, tokens);
    _ = try token_stream.value();

    const expected =
        \\{}
    ;
    try token_stream.assert_src(expected);
}

test "value takes empty array" {
    const json =
        \\[]
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(json, tokens);
    _ = try token_stream.value();

    const expected =
        \\[]
    ;
    try token_stream.assert_src(expected);
}

test "string takes only what belongs to it" {
    const json =
        \\"something":"123"
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(json, tokens);
    _ = try token_stream.string();

    const expected =
        \\"something"
    ;

    try token_stream.assert_src(expected);
}

test "object empty" {
    const json =
        \\{}
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(json, tokens);
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
    var token_stream = TokenStream.init(json, tokens);
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
    var token_stream = TokenStream.init(json, tokens);
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
    var token_stream = TokenStream.init(json, tokens);
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
    var token_stream = TokenStream.init(json, tokens);
    const obj = try token_stream.object();
    assert(obj.Object.kv_pairs.?.items.len == 4);
}

test "object invalid" {
    const json =
        \\{"asd":{},"1":{}, "asd":{} "123123123":{}}
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(json, tokens);
    const obj = token_stream.object();
    try testing.expectError(ParserError.MISSING_COMMA, obj);
}

test "object leading comma" {
    const json =
        \\{"asd":{},}
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(json, tokens);
    const obj = token_stream.object();
    try testing.expectError(ParserError.INVALID_KEY, obj);
}

test "object correct index" {
    const json =
        \\{"asd":{}}
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(json, tokens);
    _ = try token_stream.object();

    const expected =
        \\{"asd":{}}
    ;

    try token_stream.assert_src(expected);
}

test "array empty" {
    const json =
        \\[]
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(json, tokens);
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
    var token_stream = TokenStream.init(json, tokens);
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
    var token_stream = TokenStream.init(json, tokens);
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
    var token_stream = TokenStream.init(json, tokens);
    const arr = try token_stream.array();

    assert(arr == .Array);
    const arr1 = arr.Array.items.?;

    assert(arr1.items.len == 1);
    assert(arr1.items[0].* == .Array);
    assert(arr1.items[0].* == .Array);
    assert(arr1.items[0].Array.items == null);
}

test "array leading comma" {
    const json =
        \\[ "asd", ]
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(json, tokens);
    const arr = token_stream.array();
    try testing.expectError(ParserError.INVALID_VALUE, arr);
}

test "peek works correctly" {
    const json =
        \\["asd"]
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(json, tokens);
    const token = token_stream.peek();
    assert(token_stream.index == 0);
    assert(token == .D_QUOTE);
}

test "value returns string" {
    const json =
        \\"something":123}
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(json, tokens);
    const val = try token_stream.value();
    assert(val.* == .String);
}

test "array nested n times" {
    const json =
        \\[[],[]]
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(json, tokens);
    const arr = try token_stream.array();
    assert(arr.Array.items.?.items.len == 2);
    for (arr.Array.items.?.items) |item| {
        assert(item.* == .Array);
    }
}

test "kv_pair correct index" {
    const json =
        \\"something":"123"}
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(json, tokens);
    _ = try token_stream.kv_pair();

    const expected =
        \\"something":"123"
    ;
    try token_stream.assert_src(expected);
}

test "kv_pair works for string" {
    const json =
        \\"something":"123"}
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(json, tokens);
    _ = try token_stream.kv_pair();
}

test "null works" {
    const json =
        \\null
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(json, tokens);
    const nil = try token_stream._null();
    print("DEBUGPRINT[3]: main.zig:659: nil={any}\n", .{nil});
    assert(nil.start == 0);
    assert(nil.end == 4);
}

test "null correct index" {
    const json =
        \\null
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(json, tokens);
    _ = try token_stream._null();

    const expected =
        \\null
    ;

    try token_stream.assert_src(expected);
}

test "true works" {
    const json =
        \\true
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(json, tokens);
    const b = try token_stream._bool();
    assert(b.start == 0);
    assert(b.end == 4);
}

test "true correct index" {
    const json =
        \\true
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(json, tokens);
    _ = try token_stream._bool();

    const expected =
        \\true
    ;

    try token_stream.assert_src(expected);
}

test "false works" {
    const json =
        \\false
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(json, tokens);
    const nil = try token_stream._bool();
    assert(nil.start == 0);
    assert(nil.end == 4);
}

test "false correct index" {
    const json =
        \\false
    ;

    const tokens = lexer(json);
    var token_stream = TokenStream.init(json, tokens);
    _ = try token_stream._bool();

    const expected =
        \\false
    ;

    try token_stream.assert_src(expected);
}
