using EricLang: tokenize, Token, TokenType, SourceLocation,
    T_LITERAL, T_IDENT, T_STRING, T_LPAREN, T_RPAREN, T_ASSIGN,
    T_PIPE, T_COMMA, T_SPREAD, T_AS, T_INDENT, T_DEDENT, T_NEWLINE,
    T_EMPTY, T_EOF, T_TRUE, T_FALSE

@testset "Tokenizer" begin
    @testset "basic tokenization of add(1, 2)" begin
        tokens = tokenize("add(1, 2)")
        types = [t.type for t in tokens]
        @test T_IDENT in types
        @test T_LPAREN in types
        @test T_LITERAL in types
        @test T_COMMA in types
        @test T_RPAREN in types
        # Check values
        ident_tokens = filter(t -> t.type == T_IDENT, tokens)
        @test !isempty(ident_tokens)
        @test ident_tokens[1].value == "add"
        lit_tokens = filter(t -> t.type == T_LITERAL, tokens)
        @test length(lit_tokens) == 2
        @test lit_tokens[1].value == "1"
        @test lit_tokens[2].value == "2"
    end

    @testset "indentation tracking" begin
        src = """
        if true
            x = 1
        """
        tokens = tokenize(src)
        types = [t.type for t in tokens]
        @test T_INDENT in types
        @test T_DEDENT in types
        # INDENT should appear before the indented content
        indent_idx = findfirst(==(T_INDENT), types)
        x_idx = findfirst(t -> t.type == T_IDENT && t.value == "x", tokens)
        @test indent_idx < x_idx
    end

    @testset "pipe maps to NEWLINE" begin
        tokens = tokenize("a | b")
        pipe_tokens = filter(t -> t.type == T_NEWLINE, tokens)
        @test length(pipe_tokens) >= 1
    end

    @testset "empty lines produce EMPTY" begin
        tokens = tokenize("a\n\nb")
        types = [t.type for t in tokens]
        @test T_EMPTY in types
    end

    @testset "comments are stripped" begin
        tokens = tokenize("x = 1 # this is a comment")
        values = [t.value for t in tokens]
        @test !any(v -> occursin("comment", v), values)
        # Should still have the assignment
        types = [t.type for t in tokens]
        @test T_IDENT in types
        @test T_LITERAL in types
    end

    @testset "escaped quotes in strings (review issue #2)" begin
        tokens = tokenize("\"hello \\\"world\\\"\"")
        str_tokens = filter(t -> t.type == T_STRING, tokens)
        @test length(str_tokens) == 1
        @test str_tokens[1].value == "hello \"world\""
    end

    @testset "source locations are correct" begin
        tokens = tokenize("ab\ncd")
        first_tok = filter(t -> t.type == T_IDENT, tokens)[1]
        @test first_tok.location.line == 1
        # Second line token
        second_line = filter(t -> t.location.line == 2 && t.type == T_IDENT, tokens)
        @test length(second_line) >= 1
    end

    @testset "negative numbers tokenize as single LITERAL" begin
        tokens = tokenize("-42")
        literals = filter(t -> t.type == T_LITERAL, tokens)
        @test length(literals) == 1
        @test literals[1].value == "-42" || literals[1].value == -42
    end
end
