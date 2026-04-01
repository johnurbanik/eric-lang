# NiLang-Inspired Reversible Execution Engine
# "Every eval step can be undone. Programs run backward."
#
# Since wrapping an arbitrary tree-walker with @i is... challenging,
# we implement trace-based reversibility: record every state-changing
# operation during forward execution, then replay the inverse operations
# in reverse order.
#
# This is spiritually equivalent to NiLang's approach, in the same way
# that eric-lang is spiritually equivalent to a production language.

using NiLang
using NiLangCore

# --- Reversible Operation Types ---

abstract type ReversibleOp end

struct PushOp <: ReversibleOp
    value::Any
end

struct PopOp <: ReversibleOp
    value::Any
end

struct AssignOp <: ReversibleOp
    key::String
    old_value::Union{Any, Nothing}
    new_value::Any
end

struct PrintOp <: ReversibleOp
    value::Any
end

struct MemoStoreOp <: ReversibleOp
    key::String
    value::Any
end

# --- Execution Trace ---

mutable struct ExecutionTrace
    ops::Vector{ReversibleOp}
    ExecutionTrace() = new(ReversibleOp[])
end

function record!(trace::ExecutionTrace, op::ReversibleOp)
    push!(trace.ops, op)
end

# --- Reverse a single operation ---

function reverse_op(op::PushOp)
    return PopOp(op.value)
end

function reverse_op(op::PopOp)
    return PushOp(op.value)
end

function reverse_op(op::AssignOp)
    return AssignOp(op.key, op.new_value, op.old_value)
end

function reverse_op(op::PrintOp)
    return PrintOp(op.value)  # "un-printing" just prints again with [REVERSE] prefix
end

function reverse_op(op::MemoStoreOp)
    return MemoStoreOp(op.key, nothing)  # un-memoize
end

# --- Execute the trace in reverse ---

function execute_reverse!(trace::ExecutionTrace, stack::Vector{Any}, variables::Dict{String, Any})
    println("\n=== REVERSIBLE EXECUTION: RUNNING BACKWARD ===")
    println("Replaying $(length(trace.ops)) operations in reverse...\n")

    for op in reverse(trace.ops)
        rev = reverse_op(op)
        apply_reversed_op!(rev, stack, variables)
    end

    println("\n=== REVERSE EXECUTION COMPLETE ===")
    println("Stack restored to: $stack")
end

function apply_reversed_op!(op::PushOp, stack, variables)
    push!(stack, op.value)
    println("  [REVERSE] push $(op.value)")
end

function apply_reversed_op!(op::PopOp, stack, variables)
    if !isempty(stack)
        pop!(stack)
    end
    println("  [REVERSE] pop")
end

function apply_reversed_op!(op::AssignOp, stack, variables)
    if op.new_value === nothing
        delete!(variables, op.key)
        println("  [REVERSE] undefine $(op.key)")
    else
        variables[op.key] = op.new_value
        println("  [REVERSE] restore $(op.key)")
    end
end

function apply_reversed_op!(op::PrintOp, stack, variables)
    println("  [REVERSE] un-print: $(op.value)")
end

function apply_reversed_op!(op::MemoStoreOp, stack, variables)
    println("  [REVERSE] un-memoize: $(op.key)")
end

# --- NiLang integration ---
# Demonstrate that basic eric-lang arithmetic can be expressed as
# reversible NiLang operations using the @i macro.

# Reversible addition using NiLang's @i macro
@i function reversible_add(out!::T, a::T, b::T) where T<:Number
    out! += a + b
end

# Reversible subtraction
@i function reversible_sub(out!::T, a::T, b::T) where T<:Number
    out! += a - b
end

# Reversible multiplication
@i function reversible_mul(out!::T, a::T, b::T) where T<:Number
    out! += a * b
end

# --- Demo ---

# Demonstrate reversibility of basic operations
function demo_reversibility()
    println("=== NiLang Reversible Arithmetic Demo ===")

    # Forward: compute 3 + 5
    out = 0
    out, a, b = reversible_add(out, 3, 5)
    println("Forward:  reversible_add(0, 3, 5) = $out")

    # Reverse: un-compute
    out, a, b = (~reversible_add)(out, 3, 5)
    println("Reverse: ~reversible_add($out, 3, 5) = $out")
    println("State restored: out = $out (should be 0)")
end

# Demonstrate the trace-based reversibility system
function demo_trace_reversibility()
    println("\n=== Trace-Based Reversible Execution Demo ===")

    trace = ExecutionTrace()
    stack = Any[]
    variables = Dict{String, Any}()

    # Simulate a small eric-lang program:
    #   push 42
    #   push 8
    #   set x = 50
    #   print "hello"

    record!(trace, PushOp(42))
    push!(stack, 42)

    record!(trace, PushOp(8))
    push!(stack, 8)

    record!(trace, AssignOp("x", nothing, 50))
    variables["x"] = 50

    record!(trace, PrintOp("hello"))

    println("After forward execution:")
    println("  stack = $stack")
    println("  variables = $variables")

    # Now reverse it
    execute_reverse!(trace, stack, variables)
end
