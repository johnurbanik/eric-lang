@testset "Tokenizer" begin
    @testset "basic tokenization of add(1, 2)" begin
        tokens = tokenize("add(1, 2)")
        kinds = [t.kind for t in tokens]
        @test kinds == [IDENT, LPAREN, LITERAL, COMMA, LITERAL, RPAREN]
        @test tokens[1].value == "add"
        @test tokens[3].value == "1"
        @test tokens[5].value == "2"
    end

    @testset "indentation tracking" begin
        src = """
        if true
            x = 1
        """
        tokens = tokenize(src)
        kinds = [t.kind for t in tokens]
        @test INDENT in kinds
        @test DEDENT in kinds
        # INDENT should appear before the indented content
        indent_idx = findfirst(==(INDENT), kinds)
        x_idx = findfirst(t -> t.kind == IDENT && t.value == "x", tokens)
        @test indent_idx < x_idx
    end

    @testset "pipe maps to NEWLINE" begin
        tokens = tokenize("a | b")
        pipe_tokens = filter(t -> t.kind == NEWLINE, tokens)
        @test length(pipe_tokens) >= 1
    end

    @testset "empty lines produce EMPTY" begin
        tokens = tokenize("a\n\nb")
        kinds = [t.kind for t in tokens]
        @test EMPTY in kinds
    end

    @testset "comments are stripped" begin
        tokens = tokenize("x = 1 # this is a comment")
        values = [t.value for t in tokens]
        @test !any(v -> occursin("comment", v), values)
        # Should still have the assignment
        kinds = [t.kind for t in tokens]
        @test IDENT in kinds
        @test LITERAL in kinds
    end

    @testset "escaped quotes in strings (review issue #2)" begin
        tokens = tokenize(raw"""
        "hello \"world\""
        """)
        str_tokens = filter(t -> t.kind == LITERAL && t.value isa AbstractString, tokens)
        @test length(str_tokens) == 1
        @test str_tokens[1].value == "hello \"world\""
    end

    @testset "source locations are correct" begin
        tokens = tokenize("ab\ncd")
        first_tok = tokens[1]
        @test first_tok.line == 1
        @test first_tok.col == 1
        # Second line token
        second_line = filter(t -> t.line == 2 && t.kind == IDENT, tokens)
        @test length(second_line) >= 1
        @test second_line[1].col == 1
    end

    @testset "negative numbers tokenize as single LITERAL" begin
        tokens = tokenize("-42")
        literals = filter(t -> t.kind == LITERAL, tokens)
        @test length(literals) == 1
        @test literals[1].value == "-42" || literals[1].value == -42
    end
end
