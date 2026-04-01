@testset "Integration" begin
    @testset "end-to-end: add(1, 2) | print produces output" begin
        buf = IOBuffer()
        run_program("add(1, 2) | print"; output=buf)
        result = String(take!(buf))
        @test occursin("3", result)
    end

    @testset "end-to-end: simple assignment and reference" begin
        buf = IOBuffer()
        run_program("""
        x = 5
        add(x, 1) | print
        """; output=buf)
        result = String(take!(buf))
        @test occursin("6", result)
    end

    @testset "fib example can be parsed" begin
        fib_src = """
        fib(0) = 0
        fib(1) = 1
        fib(n) = add(fib(sub(n, 1)), fib(sub(n, 2)))
        """
        # Should parse without error
        nodes = parse_eric_program(fib_src)
        @test length(nodes) == 3
        # Each should be an AssignmentNode
        @test all(n -> n isa AssignmentNode, nodes)
    end

    @testset "fib example can be formatted" begin
        fib_src = """
        fib(0) = 0
        fib(1) = 1
        fib(n) = add(fib(sub(n, 1)), fib(sub(n, 2)))
        """
        nodes = parse_eric_program(fib_src)
        for node in nodes
            formatted = format_node(node)
            @test formatted isa String
            @test occursin("fib", formatted)
        end
    end

    @testset "pipe chaining works" begin
        buf = IOBuffer()
        run_program("range(1, 3) | len | print"; output=buf)
        result = String(take!(buf))
        @test occursin("3", result)
    end
end
