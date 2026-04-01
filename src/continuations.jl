# Scheme-Style Continuations
# "Every eval step takes an explicit continuation."
# "call/cc exposed as a built-in. You can checkpoint mid-computation and resume later."
#
# This is necessary because a stack-based language that adds numbers
# clearly needs first-class delimited continuations.

# ---------------------------------------------------------------------------
# Abstract types
# ---------------------------------------------------------------------------

"""A continuation is a function from a value to "the rest of the computation"."""
abstract type AbstractContinuation end

# ---------------------------------------------------------------------------
# Concrete continuation types
# ---------------------------------------------------------------------------

"""Regular continuation wrapping a function and a debug label."""
struct Continuation <: AbstractContinuation
    fn::Function
    label::String  # For debugging: "what happens next"
end

"""The identity continuation -- "we're done, return the value"."""
struct HaltContinuation <: AbstractContinuation end

"""
Reified continuation -- captured by call/cc.
Can be invoked as a first-class value, but only once
(because we are *responsible* engineers who limit our footguns).
"""
mutable struct ReifiedContinuation
    continuation::AbstractContinuation
    invoked::Bool
    ReifiedContinuation(k::AbstractContinuation) = new(k, false)
end

# ---------------------------------------------------------------------------
# Labels (for pretty-printing the continuation chain)
# ---------------------------------------------------------------------------

label(k::Continuation)::String = k.label
label(::HaltContinuation)::String = "halt"
label(r::ReifiedContinuation)::String = "reified($(label(r.continuation)))"

# ---------------------------------------------------------------------------
# Invoking continuations
# ---------------------------------------------------------------------------

"""Invoke a regular continuation with a value."""
function continue_with(k::Continuation, value)
    return k.fn(value)
end

"""Invoking the halt continuation just returns the value."""
function continue_with(::HaltContinuation, value)
    return value
end

"""
Invoke a reified continuation (captured via call/cc).
Marks it as invoked so we can detect double-invocation if desired.
"""
function continue_with(r::ReifiedContinuation, value)
    if r.invoked
        error("ReifiedContinuation already invoked! " *
              "This is a stack-based language, not Haskell. " *
              "One-shot continuations only.")
    end
    r.invoked = true
    return continue_with(r.continuation, value)
end

# ---------------------------------------------------------------------------
# Continuation combinators
# ---------------------------------------------------------------------------

"""
Compose two continuations: first k1, then k2.
The resulting continuation feeds the output of k1 into k2.
"""
function compose_continuation(k1::AbstractContinuation, k2::AbstractContinuation)
    return Continuation(
        value -> continue_with(k2, continue_with(k1, value)),
        "$(label(k1)) then $(label(k2))"
    )
end

"""
Extend a continuation: run `f` on the value, then pass to `k`.
This is the bread-and-butter of CPS -- "do this thing, then continue".
"""
function extend_continuation(f::Function, k::AbstractContinuation, lbl::String="step")
    return Continuation(
        value -> continue_with(k, f(value)),
        "$lbl -> $(label(k))"
    )
end

"""
Create a continuation that ignores its argument and just continues with
a fixed value.  Useful for sequencing statements where the intermediate
result doesn't matter.
"""
function ignore_continuation(k::AbstractContinuation, fixed_value=nothing)
    return Continuation(
        _ -> continue_with(k, fixed_value),
        "ignore -> $(label(k))"
    )
end

"""
Sequence a list of CPS-transformed computations.
Each computation is a function `(k) -> result` that calls `k` when done.

    sequence_cps([comp1, comp2, comp3], final_k)

is equivalent to:

    comp1(v1 -> comp2(v2 -> comp3(v3 -> final_k(v3))))
"""
function sequence_cps(computations::Vector, k::AbstractContinuation)
    if isempty(computations)
        return continue_with(k, nothing)
    end
    # Build the chain from right to left
    folded = k
    for comp in reverse(computations)
        let c = comp, next_k = folded
            folded = Continuation(
                _ -> c(next_k),
                "seq -> $(label(next_k))"
            )
        end
    end
    # Kick off the chain
    return continue_with(folded, nothing)
end

# ---------------------------------------------------------------------------
# call/cc  (call-with-current-continuation)
# ---------------------------------------------------------------------------

"""
The crown jewel. Captures the current continuation and passes it to `f`.
`f` receives a ReifiedContinuation it can stash and invoke later.

Usage in the interpreter:
    call_cc(k) do escape
        # escape is a ReifiedContinuation wrapping k
        # invoking escape(value) jumps back to k with that value
    end
"""
function call_cc(f::Function, k::AbstractContinuation)
    reified = ReifiedContinuation(k)
    # Pass the reified continuation to f, along with the "real" continuation
    return f(reified, k)
end

# ---------------------------------------------------------------------------
# Prompt / Reset  (delimited continuations, because why not)
# ---------------------------------------------------------------------------

"""
A prompt tag for delimited continuations.
Because undelimited continuations are for people who don't read papers.
"""
struct PromptTag
    name::String
end

const DEFAULT_PROMPT = PromptTag("top-level")

"""
Reset (delimit) a continuation up to a prompt tag.
In Scheme terms: (reset (body))
"""
function reset_continuation(body::Function, tag::PromptTag=DEFAULT_PROMPT)
    return body(HaltContinuation())
end

"""
Shift (capture delimited continuation up to nearest reset).
In Scheme terms: (shift k (body k))
"""
function shift_continuation(f::Function, k::AbstractContinuation, tag::PromptTag=DEFAULT_PROMPT)
    # The delimited continuation is everything from here to the nearest reset
    # We wrap k so that invoking it re-installs the delimiter
    delimited_k = ReifiedContinuation(k)
    return f(delimited_k)
end

# ---------------------------------------------------------------------------
# Pretty printing
# ---------------------------------------------------------------------------

function Base.show(io::IO, k::Continuation)
    print(io, "Continuation($(k.label))")
end

function Base.show(io::IO, ::HaltContinuation)
    print(io, "HaltContinuation()")
end

function Base.show(io::IO, r::ReifiedContinuation)
    status = r.invoked ? "spent" : "live"
    print(io, "ReifiedContinuation($(label(r.continuation)), $status)")
end
