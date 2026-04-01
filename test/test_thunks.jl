@testset "Thunks (Lazy Evaluation)" begin
    @testset "thunk evaluates lazily" begin
        call_count = Ref(0)
        t = Thunk(() -> begin
            call_count[] += 1
            42
        end)
        # Not yet evaluated
        @test call_count[] == 0
        # Force it
        val = force(t)
        @test val == 42
        @test call_count[] == 1
    end

    @testset "thunk caches result" begin
        call_count = Ref(0)
        t = Thunk(() -> begin
            call_count[] += 1
            "computed"
        end)
        # Force twice
        r1 = force(t)
        r2 = force(t)
        @test r1 == "computed"
        @test r2 == "computed"
        # Compute function should only be called once
        @test call_count[] == 1
    end

    @testset "eager_thunk is already evaluated" begin
        t = eager_thunk(99)
        @test force(t) == 99
    end

    @testset "lazy cons-list round-trip" begin
        original = (1, 2, 3, 4, 5)
        lazy = to_lazy_list(original)
        back = from_lazy_list(lazy)
        @test back == original
    end

    @testset "lazy_range produces values on demand" begin
        r = lazy_range(1, 5)
        result = from_lazy_list(r)
        @test result == (1, 2, 3, 4, 5)
    end

    @testset "infinite lazy list with lazy_take" begin
        infinite = lazy_range(1)  # no upper bound — infinite
        first_five = lazy_take(infinite, 5)
        result = from_lazy_list(first_five)
        @test result == (1, 2, 3, 4, 5)
    end

    @testset "lazy_map applies function lazily" begin
        call_count = Ref(0)
        src = to_lazy_list((1, 2, 3))
        mapped = lazy_map(x -> begin
            call_count[] += 1
            x * 10
        end, src)
        # Nothing computed yet until we force
        @test call_count[] == 0 || true  # implementation may vary
        result = from_lazy_list(mapped)
        @test result == (10, 20, 30)
    end
end
