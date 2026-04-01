using EricLang: tokenize, parse_eric, format_ast,
    ASTNode, ModuleNode, AssignmentNode, ExpressionNode

@testset "Integration" begin
    @testset "end-to-end: tokenize and parse add(1, 2)" begin
        tokens = tokenize("add(1, 2)")
        mod = parse_eric(tokens)
        @test mod isa ModuleNode
        stmt = mod.blocks[1].stmts[1]
        node = stmt.expr
        @test node isa ExpressionNode
        @test node.identifier.name == "add"
    end

    @testset "end-to-end: tokenize, parse, and format round-trip" begin
        source = "add(1, 2)"
        tokens = tokenize(source)
        mod = parse_eric(tokens)
        formatted = format_ast(mod)
        @test formatted isa String
        @test occursin("add", formatted)
        @test occursin("1", formatted)
        @test occursin("2", formatted)
    end

    @testset "fib example can be parsed" begin
        fib_src = """
        fib(0) = 0
        fib(1) = 1
        fib(n) = add(fib(sub(n, 1)), fib(sub(n, 2)))
        """
        tokens = tokenize(fib_src)
        mod = parse_eric(tokens)
        @test mod isa ModuleNode
        # Should have at least 3 statements across blocks
        all_stmts = reduce(vcat, [b.stmts for b in mod.blocks])
        @test length(all_stmts) >= 3
    end

    @testset "fib example can be formatted" begin
        fib_src = """
        fib(0) = 0
        fib(1) = 1
        fib(n) = add(fib(sub(n, 1)), fib(sub(n, 2)))
        """
        tokens = tokenize(fib_src)
        mod = parse_eric(tokens)
        formatted = format_ast(mod)
        @test formatted isa String
        @test occursin("fib", formatted)
    end

    @testset "pipe chaining parses correctly" begin
        tokens = tokenize("range(1, 3) | len")
        mod = parse_eric(tokens)
        @test mod isa ModuleNode
        # After pipe, there should be multiple statements in the block
        block = mod.blocks[1]
        @test length(block.stmts) >= 2
    end
end
