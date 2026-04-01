@testset "Formatter" begin
    @testset "format a literal number" begin
        node = LiteralNode(42)
        @test format_node(node) == "42"
    end

    @testset "format a string literal" begin
        node = LiteralNode("hello")
        formatted = format_node(node)
        @test formatted == "\"hello\""
    end

    @testset "format an expression" begin
        node = ExpressionNode("add", [LiteralNode(1), LiteralNode(2)])
        formatted = format_node(node)
        @test formatted == "add(1, 2)"
    end

    @testset "format nested expression" begin
        inner = ExpressionNode("mul", [LiteralNode(3), LiteralNode(4)])
        outer = ExpressionNode("add", [LiteralNode(1), inner])
        formatted = format_node(outer)
        @test formatted == "add(1, mul(3, 4))"
    end

    @testset "as-binding format does not crash (review issue #6)" begin
        # StatementNode with multiple names should format without error
        node = StatementNode(
            ExpressionNode("compute", [LiteralNode(1)]),
            ["x", "y"]
        )
        formatted = format_node(node)
        @test formatted isa String
        @test occursin("as", formatted)
        @test occursin("x", formatted)
        @test occursin("y", formatted)
    end

    @testset "format assignment" begin
        node = AssignmentNode(
            IdentifierNode("x"),
            LiteralNode(5)
        )
        formatted = format_node(node)
        @test formatted == "x = 5"
    end

    @testset "round-trip: parse then format produces valid code" begin
        source = "add(1, 2)"
        node = parse_eric(source)
        formatted = format_node(node)
        # Re-parse the formatted output — should not throw
        reparsed = parse_eric(formatted)
        @test reparsed isa ExpressionNode
        @test reparsed.name == "add"
    end
end
