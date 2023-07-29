const Token = @import("main.zig").Token;
const TokenT = @import("main.zig").TokenT;
const std = @import("std");
const print = std.debug.print;
const testing = std.testing;
const ArrayList = std.ArrayList;

pub fn lexer(token_stream: []const u8) ArrayList(TokenT) {
    var tokens = ArrayList(TokenT).init(std.heap.page_allocator);

    const ts_len = token_stream.len;
    var local_index: usize = 0;
    while (local_index < ts_len) : (local_index += 1) {
        if (std.ascii.isWhitespace(token_stream[local_index])) {
            continue;
        }

        const char = token_stream[local_index];
        const token =
            switch (char) {
            '}' => Token.R_CURLY,
            '{' => Token.L_CURLY,
            ']' => Token.R_SQUARE,
            '[' => Token.L_SQUARE,
            ',' => Token.COMMA,
            ':' => Token.COLON,
            '"' => Token.D_QUOTE,
            else => TokenT{ .LITERAL = char },
        };

        tokens.append(token) catch @panic("oom");
    }

    return tokens;
}

test "skips whitespaces" {
    const json =
        \\asd asd
    ;

    const tokens = lexer(json);
    if (json.len == tokens.items.len) {
        return error.WHITESPACE_NOT_SKIPPED;
    }
}

test "skips whitespaces newline" {
    const json = "asd\nasd";

    const tokens = lexer(json);
    if (json.len == tokens.items.len) {
        return error.WHITESPACE_NOT_SKIPPED;
    }
}

test "skips whitespaces newline multiple" {
    const json = "\nas d\na sd\n";

    const tokens = lexer(json);
    if (tokens.items.len != 6) {
        return error.WHITESPACE_NOT_SKIPPED;
    }
}

test "skips whitespaces tabs" {
    const json = "[sd\t]";

    const tokens = lexer(json);
    if (tokens.items.len == json.len) {
        return error.WHITESPACE_NOT_SKIPPED;
    }
}
