using EricLang: format_ast, tokenize, parse_eric,
    ASTNode, LiteralNode, IdentifierNode, ExpressionNode,
    CollectionItemNode, CollectionNode, StatementNode, BlockNode,
    ModuleNode, AssignmentNode, SourceLocation

@testset "Formatter" begin
    @testset "format a literal number" begin
        node = LiteralNode(42)
        @test format_ast(node) == "42"
    end

    @testset "format a string literal" begin
        node = LiteralNode("hello")
        formatted = format_ast(node)
        @test formatted == "\"hello\""
    end

    @testset "format an expression" begin
        ident = IdentifierNode("add")
        node = ExpressionNode(ident, ASTNode[LiteralNode(1), LiteralNode(2)], SourceLocation())
        formatted = format_ast(node)
        @test formatted == "add(1, 2)"
    end

    @testset "format nested expression" begin
        mul_ident = IdentifierNode("mul")
        inner = ExpressionNode(mul_ident, ASTNode[LiteralNode(3), LiteralNode(4)], SourceLocation())
        add_ident = IdentifierNode("add")
        outer = ExpressionNode(add_ident, ASTNode[LiteralNode(1), inner], SourceLocation())
        formatted = format_ast(outer)
        @test formatted == "add(1, mul(3, 4))"
    end

    @testset "as-binding format does not crash (review issue #6)" begin
        # StatementNode with multiple names should format without error
        ident = IdentifierNode("compute")
        expr = ExpressionNode(ident, ASTNode[LiteralNode(1)], SourceLocation())
        names = [IdentifierNode("x"), IdentifierNode("y")]
        node = StatementNode(expr, names, nothing, SourceLocation())
        formatted = format_ast(node)
        @test formatted isa String
        @test occursin("as", formatted)
        @test occursin("x", formatted)
        @test occursin("y", formatted)
    end

    @testset "format assignment" begin
        node = AssignmentNode(
            IdentifierNode("x"),
            LiteralNode(5),
            SourceLocation()
        )
        formatted = format_ast(node)
        @test formatted == "x = 5"
    end

    @testset "round-trip: parse then format produces valid code" begin
        source = "add(1, 2)"
        tokens = tokenize(source)
        mod = parse_eric(tokens)
        formatted = format_ast(mod)
        # Re-parse the formatted output — should not throw
        tokens2 = tokenize(formatted)
        reparsed = parse_eric(tokens2)
        @test reparsed isa ModuleNode
    end
end
