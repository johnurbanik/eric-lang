@testset "Continuations" begin
    @testset "HaltContinuation returns its argument" begin
        k = HaltContinuation()
        @test invoke_continuation(k, 42) == 42
        @test invoke_continuation(k, "hello") == "hello"
    end

    @testset "Continuation wraps a function and calls it" begin
        k = Continuation(x -> x * 2)
        @test invoke_continuation(k, 5) == 10
        @test invoke_continuation(k, 0) == 0
    end

    @testset "Continuation composition" begin
        k1 = Continuation(x -> x + 1)
        k2 = Continuation(x -> x * 3)
        # Composing: first k1, then k2 applied to result
        composed = Continuation(x -> invoke_continuation(k2, invoke_continuation(k1, x)))
        @test invoke_continuation(composed, 2) == 9  # (2+1)*3
    end

    @testset "ReifiedContinuation can be invoked" begin
        captured_value = Ref{Any}(nothing)
        k = ReifiedContinuation(v -> begin
            captured_value[] = v
            v
        end)
        result = invoke_continuation(k, 99)
        @test result == 99
        @test captured_value[] == 99
    end

    @testset "call_cc captures current continuation" begin
        result = call_cc() do k
            # k is the current continuation; invoking it should
            # short-circuit and return the value
            invoke_continuation(k, 42)
            # This line should NOT be reached if call_cc is properly
            # implemented with short-circuit semantics
            return 0
        end
        @test result == 42
    end

    @testset "call_cc without early exit returns body value" begin
        result = call_cc() do k
            # Don't invoke k — just return normally
            100
        end
        @test result == 100
    end
end
