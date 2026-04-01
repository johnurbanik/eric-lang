# The IO Monad
# "print is now pure. Side effects are sequenced. Referential transparency achieved."
#
# In a language whose original implementation was `eval()` on raw Python strings,
# we now enforce monadic purity for I/O operations.
# This is what the review feedback demanded. Probably.

abstract type IOAction end

struct IOReturn <: IOAction
    value::Any
end

struct IOBind <: IOAction
    action::IOAction
    f::Function  # value -> IOAction
end

struct IOPrint <: IOAction
    value::Any
end

struct IOReadLine <: IOAction end

struct IOSequence <: IOAction
    actions::Vector{IOAction}
end

# Monadic operations
io_return(x) = IOReturn(x)
io_bind(action::IOAction, f::Function) = IOBind(action, f)
io_print(x) = IOPrint(x)
io_readline() = IOReadLine()
io_sequence(actions...) = IOSequence(collect(actions))

# The >>= operator for style points
Base.:>>(a::IOAction, f::Function) = io_bind(a, f)

# Run the IO monad (the "unsafe" boundary — like Haskell's unsafePerformIO)
# "This is where purity goes to die, but at least it dies in one place."
function run_io!(action::IOAction, input_buffer::Vector{String}=String[])
    if action isa IOReturn
        return action.value
    elseif action isa IOPrint
        println(action.value)
        return nothing
    elseif action isa IOReadLine
        if isempty(input_buffer)
            return readline()
        else
            return popfirst!(input_buffer)
        end
    elseif action isa IOBind
        result = run_io!(action.action, input_buffer)
        next_action = action.f(result)
        return run_io!(next_action, input_buffer)
    elseif action isa IOSequence
        result = nothing
        for a in action.actions
            result = run_io!(a, input_buffer)
        end
        return result
    end
    error("Unknown IO action: $(typeof(action))")
end

# Verify monad laws (used in tests)
# Left identity:  io_return(a) >>= f  ≡  f(a)
# Right identity: m >>= io_return     ≡  m
# Associativity:  (m >>= f) >>= g    ≡  m >>= (x -> f(x) >>= g)
function verify_monad_laws(a, f, g, m)
    # We can't directly compare IOAction trees, but we can compare their results
    left_id_lhs = run_io!(io_bind(io_return(a), f))
    left_id_rhs = run_io!(f(a))

    right_id_lhs = run_io!(io_bind(m, x -> io_return(x)))
    right_id_rhs = run_io!(m)

    assoc_lhs = run_io!(io_bind(io_bind(m, f), g))
    assoc_rhs = run_io!(io_bind(m, x -> io_bind(f(x), g)))

    return (
        left_identity = left_id_lhs == left_id_rhs,
        right_identity = right_id_lhs == right_id_rhs,
        associativity = assoc_lhs == assoc_rhs
    )
end
