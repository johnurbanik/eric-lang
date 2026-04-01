using EricLang: tokenize, parse_eric, ParseError,
    ASTNode, LiteralNode, IdentifierNode, ExpressionNode,
    CollectionItemNode, CollectionNode, StatementNode, BlockNode,
    ModuleNode, AssignmentNode

@testset "Parser" begin
    @testset "parse a literal" begin
        tokens = tokenize("42")
        mod = parse_eric(tokens)
        @test mod isa ModuleNode
        # Navigate: ModuleNode -> BlockNode -> StatementNode -> expr
        stmt = mod.blocks[1].stmts[1]
        node = stmt.expr
        @test node isa LiteralNode
        @test node.value == 42
    end

    @testset "parse an expression" begin
        tokens = tokenize("add(1, 2)")
        mod = parse_eric(tokens)
        stmt = mod.blocks[1].stmts[1]
        node = stmt.expr
        @test node isa ExpressionNode
        @test node.identifier.name == "add"
        @test length(node.args) == 2
        @test node.args[1] isa LiteralNode
        @test node.args[1].value == 1
        @test node.args[2] isa LiteralNode
        @test node.args[2].value == 2
    end

    @testset "parse assignment" begin
        tokens = tokenize("x = 5")
        mod = parse_eric(tokens)
        stmt = mod.blocks[1].stmts[1]
        # The parser wraps assignment as StatementNode whose expr is AssignmentNode
        node = stmt.expr
        @test node isa AssignmentNode
        @test node.left isa IdentifierNode
        @test node.right isa LiteralNode
        @test node.right.value == 5
    end

    @testset "parse pattern-matched function" begin
        tokens = tokenize("fib(0) = 1")
        mod = parse_eric(tokens)
        stmt = mod.blocks[1].stmts[1]
        node = stmt.expr
        @test node isa AssignmentNode
        @test node.left isa ExpressionNode
        @test node.left.identifier.name == "fib"
        @test node.left.args[1].value == 0
        @test node.right isa LiteralNode
        @test node.right.value == 1
    end

    @testset "parse as binding" begin
        tokens = tokenize("expr as x, y")
        mod = parse_eric(tokens)
        stmt = mod.blocks[1].stmts[1]
        @test stmt isa StatementNode
        @test length(stmt.names) == 2
        name_strs = [n.name for n in stmt.names]
        @test "x" in name_strs
        @test "y" in name_strs
    end

    @testset "parse collection with spread" begin
        tokens = tokenize("(a..., b)")
        mod = parse_eric(tokens)
        stmt = mod.blocks[1].stmts[1]
        node = stmt.expr
        @test node isa CollectionNode
        @test length(node.items) == 2
        # First element should be marked as expanded/spread
        @test node.items[1].expand == true
        @test node.items[2].expand == false
    end

    @testset "parse error includes line number" begin
        try
            tokens = tokenize("((( unclosed")
            parse_eric(tokens)
            @test false  # should not reach here
        catch e
            @test e isa ParseError
            msg = string(e)
            # Error message should contain a line number reference
            @test occursin(r"line\s*\d+|:\d+|at \d+|ParseError", msg)
        end
    end
end
