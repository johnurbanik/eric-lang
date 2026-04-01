# Haskell-Style Lazy Evaluation
# "Every value is a Thunk. Nothing evaluates until forced."
# "add(2,3) returns Thunk(() -> 5). print forces evaluation."
#
# Yes, even the number 5 is lazy. You're welcome.

mutable struct Thunk
    compute::Union{Function, Nothing}  # Nothing after evaluation
    value::Any
    evaluated::Bool

    Thunk(f::Function) = new(f, nothing, false)
    Thunk(v, ::Val{:eager}) = new(nothing, v, true)  # Pre-evaluated thunk
end

# Force a thunk — evaluate and cache
function force(t::Thunk)
    if !t.evaluated
        t.value = t.compute()
        t.compute = nothing  # Release closure for GC
        t.evaluated = true
    end
    return t.value
end

# Force anything that isn't a thunk (identity)
force(x) = x

# Convenience: wrap a value in a pre-evaluated thunk
eager_thunk(v) = Thunk(v, Val(:eager))

# Convenience: wrap a computation in a lazy thunk
lazy(f::Function) = Thunk(f)

# Pretty-print
function Base.show(io::IO, t::Thunk)
    if t.evaluated
        print(io, "Thunk($(repr(t.value)))")
    else
        print(io, "Thunk(<unevaluated>)")
    end
end

# Lazy cons-list (Haskell-style linked list)
# "Collections are now lazy cons-lists. append is O(1)."
abstract type LazyList end

struct Nil <: LazyList end

struct Cons <: LazyList
    head::Thunk
    tail::Thunk  # Thunk that evaluates to a LazyList
end

# Convert a Julia collection to a lazy cons-list
function to_lazy_list(items)
    result = Nil()
    for item in reverse(collect(items))
        val = item
        result = Cons(eager_thunk(val), eager_thunk(result))
    end
    return result
end

# Convert a lazy list back to a Julia tuple (forces everything)
function from_lazy_list(ll::LazyList)
    result = Any[]
    current = ll
    while current isa Cons
        push!(result, force(current.head))
        current = force(current.tail)
    end
    return Tuple(result)
end

# Lazy map over a lazy list
function lazy_map(f::Function, ll::LazyList)
    if ll isa Nil
        return Nil()
    end
    return Cons(
        lazy(() -> f(force(ll.head))),
        lazy(() -> lazy_map(f, force(ll.tail)))
    )
end

# Lazy filter
function lazy_filter(pred::Function, ll::LazyList)
    if ll isa Nil
        return Nil()
    end
    h = force(ll.head)
    if pred(h)
        return Cons(eager_thunk(h), lazy(() -> lazy_filter(pred, force(ll.tail))))
    else
        return lazy_filter(pred, force(ll.tail))
    end
end

# Take first n elements
function lazy_take(n::Int, ll::LazyList)
    if n <= 0 || ll isa Nil
        return Nil()
    end
    return Cons(ll.head, lazy(() -> lazy_take(n - 1, force(ll.tail))))
end

# Infinite range (because we can)
function lazy_range(start::Int, stop=nothing)
    if stop !== nothing && start >= stop
        return Nil()
    end
    return Cons(eager_thunk(start), lazy(() -> lazy_range(start + 1, stop)))
end
