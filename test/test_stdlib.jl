@testset "Standard Library" begin
    @testset "arithmetic" begin
        @test STDLIB_FUNCTIONS["add"](2, 3) == 5
        @test STDLIB_FUNCTIONS["sub"](5, 3) == 2
        @test STDLIB_FUNCTIONS["mul"](2, 3) == 6
        @test STDLIB_FUNCTIONS["div"](6, 2) == 3
    end

    @testset "comparison" begin
        @test STDLIB_FUNCTIONS["lt"](1, 2) == true
        @test STDLIB_FUNCTIONS["lt"](2, 1) == false
        @test STDLIB_FUNCTIONS["eq"](1, 1) == true
        @test STDLIB_FUNCTIONS["eq"](1, 2) == false
    end

    @testset "string operations" begin
        split_fn = STDLIB_FUNCTIONS["split"]
        @test split_fn("a\nb\nc", "\n") == ["a", "b", "c"]

        join_fn = STDLIB_FUNCTIONS["join"]
        @test join_fn(["a", "b", "c"], ",") == "a,b,c"

        strip_fn = STDLIB_FUNCTIONS["strip"]
        @test strip_fn("  hello  ") == "hello"
    end

    @testset "collection operations" begin
        @test STDLIB_FUNCTIONS["first"]((10, 20, 30)) == 10
        @test STDLIB_FUNCTIONS["last"]((10, 20, 30)) == 30
        @test STDLIB_FUNCTIONS["len"]((1, 2, 3)) == 3
        @test STDLIB_FUNCTIONS["sort"]((3, 1, 2)) == (1, 2, 3)
        @test STDLIB_FUNCTIONS["reverse"]((1, 2, 3)) == (3, 2, 1)
        @test STDLIB_FUNCTIONS["flatten"](((1, 2), (3,), (4, 5))) == (1, 2, 3, 4, 5)
        @test STDLIB_FUNCTIONS["range"](1, 4) == (1, 2, 3, 4)
    end

    @testset "no eval() in stdlib (meta-test)" begin
        # Ensure nobody snuck eval() into the standard library
        fn_names = keys(STDLIB_FUNCTIONS)
        @test !("eval" in fn_names)
    end
end
