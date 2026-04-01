using EricLang: AbstractContinuation, Continuation, HaltContinuation,
    ReifiedContinuation, continue_with, call_cc

@testset "Continuations" begin
    @testset "HaltContinuation returns its argument" begin
        k = HaltContinuation()
        @test continue_with(k, 42) == 42
        @test continue_with(k, "hello") == "hello"
    end

    @testset "Continuation wraps a function and calls it" begin
        k = Continuation(x -> x * 2, "double")
        @test continue_with(k, 5) == 10
        @test continue_with(k, 0) == 0
    end

    @testset "Continuation composition" begin
        k1 = Continuation(x -> x + 1, "inc")
        k2 = Continuation(x -> x * 3, "triple")
        # Composing: first k1, then k2 applied to result
        composed = Continuation(x -> continue_with(k2, continue_with(k1, x)), "composed")
        @test continue_with(composed, 2) == 9  # (2+1)*3
    end

    @testset "ReifiedContinuation can be invoked" begin
        inner_k = Continuation(v -> v, "identity")
        reified = ReifiedContinuation(inner_k)
        result = continue_with(reified, 99)
        @test result == 99
    end

    @testset "call_cc captures current continuation" begin
        # call_cc takes (f, k) where f receives (reified_k, real_k)
        halt = HaltContinuation()
        result = call_cc(halt) do reified_k, real_k
            # Invoking reified_k should pass the value to the halt continuation
            continue_with(reified_k, 42)
        end
        @test result == 42
    end

    @testset "call_cc without early exit returns body value" begin
        halt = HaltContinuation()
        result = call_cc(halt) do reified_k, real_k
            # Don't invoke reified_k — just continue normally
            continue_with(real_k, 100)
        end
        @test result == 100
    end
end
