# Token types and source location tracking
# "Errors now report which paradigm they occurred in" -- Review Issue #3

struct SourceLocation
    file::String
    line::Int
    col::Int
end

SourceLocation() = SourceLocation("<unknown>", 0, 0)

Base.show(io::IO, loc::SourceLocation) = print(io, "$(loc.file):$(loc.line):$(loc.col)")

@enum TokenType begin
    T_LITERAL
    T_IDENT
    T_STRING
    T_LPAREN
    T_RPAREN
    T_ASSIGN
    T_PIPE
    T_COMMA
    T_SPREAD
    T_AS
    T_INDENT
    T_DEDENT
    T_NEWLINE
    T_EMPTY
    T_EOF
    T_TRUE
    T_FALSE
end

struct Token
    type::TokenType
    value::String
    location::SourceLocation
end

Base.show(io::IO, t::Token) = print(io, "Token($(t.type), $(repr(t.value)), $(t.location))")
