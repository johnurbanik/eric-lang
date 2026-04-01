@testset "Parser" begin
    @testset "parse a literal" begin
        node = parse_eric("42")
        @test node isa LiteralNode
        @test node.value == 42
    end

    @testset "parse an expression" begin
        node = parse_eric("add(1, 2)")
        @test node isa ExpressionNode
        @test node.name == "add"
        @test length(node.args) == 2
        @test node.args[1] isa LiteralNode
        @test node.args[1].value == 1
        @test node.args[2] isa LiteralNode
        @test node.args[2].value == 2
    end

    @testset "parse assignment" begin
        node = parse_eric("x = 5")
        @test node isa AssignmentNode
        @test node.left isa IdentifierNode || node.left isa LiteralNode
        @test node.right isa LiteralNode
        @test node.right.value == 5
    end

    @testset "parse pattern-matched function" begin
        node = parse_eric("fib(0) = 1")
        @test node isa AssignmentNode
        @test node.left isa ExpressionNode
        @test node.left.name == "fib"
        @test node.left.args[1].value == 0
        @test node.right isa LiteralNode
        @test node.right.value == 1
    end

    @testset "parse as binding" begin
        node = parse_eric("expr as x, y")
        @test node isa StatementNode
        @test hasfield(typeof(node), :names) || hasproperty(node, :names)
        @test length(node.names) == 2
        @test "x" in node.names
        @test "y" in node.names
    end

    @testset "parse collection with spread" begin
        node = parse_eric("(...a, b)")
        @test node isa CollectionNode
        @test length(node.elements) == 2
        # First element should be marked as expanded/spread
        @test node.expand[1] == true
        @test node.expand[2] == false
    end

    @testset "parse error includes line number" begin
        try
            parse_eric("((( unclosed")
            @test false  # should not reach here
        catch e
            msg = string(e)
            # Error message should contain a line number reference
            @test occursin(r"line\s*\d+|:\d+|at \d+", msg)
        end
    end
end
