using EricLang: ReversibleOp, PushOp, PopOp, AssignOp, PrintOp, MemoStoreOp,
    ExecutionTrace, record!, reverse_op, execute_reverse!, apply_reversed_op!

@testset "Reversibility" begin
    @testset "ExecutionTrace records ops" begin
        trace = ExecutionTrace()
        @test length(trace.ops) == 0
        record!(trace, PushOp(42))
        @test length(trace.ops) == 1
    end

    @testset "PushOp reverses to PopOp" begin
        op = PushOp(42)
        rev = reverse_op(op)
        @test rev isa PopOp
        @test rev.value == 42
    end

    @testset "PopOp reverses to PushOp" begin
        op = PopOp(42)
        rev = reverse_op(op)
        @test rev isa PushOp
        @test rev.value == 42
    end

    @testset "AssignOp reverses correctly (restores old value)" begin
        op = AssignOp("x", 5, 10)  # key, old_value, new_value
        rev = reverse_op(op)
        @test rev isa AssignOp
        @test rev.key == "x"
        # Reversed: old_value and new_value swap
        @test rev.old_value == 10
        @test rev.new_value == 5
    end

    @testset "full trace reverse: push then pop restores empty stack" begin
        trace = ExecutionTrace()
        stack = Any[]
        variables = Dict{String, Any}()

        # Forward: push 42
        push!(stack, 42)
        record!(trace, PushOp(42))

        @test stack == Any[42]

        # Reverse the trace using execute_reverse!
        # execute_reverse! prints output, so we just verify it doesn't error
        execute_reverse!(trace, stack, variables)

        # After reversing a PushOp, the reversed PopOp should pop from the stack
        # execute_reverse! applies reversed ops, so PushOp -> PopOp removes from stack
        @test isempty(stack)
    end

    @testset "reverse_op produces correct inverse for each op type" begin
        # Test all op types
        @test reverse_op(PushOp(1)) isa PopOp
        @test reverse_op(PopOp(1)) isa PushOp
        @test reverse_op(AssignOp("k", nothing, 5)) isa AssignOp
        @test reverse_op(PrintOp("hi")) isa PrintOp
        @test reverse_op(MemoStoreOp("k", 1)) isa MemoStoreOp
    end
end
