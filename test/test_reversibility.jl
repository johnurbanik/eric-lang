@testset "Reversibility" begin
    @testset "ExecutionTrace records ops" begin
        trace = ExecutionTrace()
        @test length(trace.ops) == 0
        record!(trace, PushOp(:stack, 42))
        @test length(trace.ops) == 1
    end

    @testset "PushOp reverses to PopOp" begin
        op = PushOp(:stack, 42)
        rev = reverse_op(op)
        @test rev isa PopOp
        @test rev.target == :stack
        @test rev.value == 42
    end

    @testset "PopOp reverses to PushOp" begin
        op = PopOp(:stack, 42)
        rev = reverse_op(op)
        @test rev isa PushOp
        @test rev.target == :stack
        @test rev.value == 42
    end

    @testset "AssignOp reverses correctly (restores old value)" begin
        op = AssignOp(:x, 10, 5)  # assigned 10 to :x, old value was 5
        rev = reverse_op(op)
        @test rev isa AssignOp
        @test rev.target == :x
        @test rev.new_value == 5   # restores old value
        @test rev.old_value == 10  # records what we're undoing
    end

    @testset "full trace reverse: push then pop restores empty stack" begin
        trace = ExecutionTrace()
        stack = Int[]

        # Forward: push 42
        push!(stack, 42)
        record!(trace, PushOp(:stack, 42))

        @test stack == [42]

        # Reverse the trace
        reversed_ops = reverse_trace(trace)
        for op in reversed_ops
            if op isa PopOp
                val = pop!(stack)
                @test val == op.value
            end
        end

        @test isempty(stack)
    end

    @testset "reverse_trace produces ops in reverse order" begin
        trace = ExecutionTrace()
        record!(trace, PushOp(:a, 1))
        record!(trace, PushOp(:b, 2))
        record!(trace, PushOp(:c, 3))

        reversed = reverse_trace(trace)
        @test length(reversed) == 3
        # Should be in reverse order and each op reversed
        @test reversed[1] isa PopOp && reversed[1].value == 3
        @test reversed[2] isa PopOp && reversed[2].value == 2
        @test reversed[3] isa PopOp && reversed[3].value == 1
    end
end
