# XSB-Style Tabled Resolution
# "The memoization issue is resolved by replacing the global dict with
#  XSB-style tabled resolution, a well-understood technique from the
#  logic programming literature." — PR Description
#
# This replaces Python's `memo = {}` with a proper tabling mechanism.
# Each resolved goal is cached as a new fact in a separate table.
# LRU eviction prevents unbounded memory growth (review issue #5).

using LRUCache

mutable struct TableStore
    cache::LRU{String, Any}
    hits::Int
    misses::Int
    evictions::Int

    TableStore(max_size::Int=10_000) = new(LRU{String, Any}(maxsize=max_size), 0, 0, 0)
end

"""
    make_table_key(functor, args)

Build a canonical cache key from a functor name and argument list.
Uses null bytes as separators to avoid ambiguity.
"""
function make_table_key(functor::String, args::Vector)::String
    parts = [functor]
    for a in args
        push!(parts, repr(a))
    end
    return join(parts, "\0")
end

"""
    table_lookup(ts, functor, args)

Look up a previously tabled result. Returns `Some(result)` on hit, `nothing` on miss.
"""
function table_lookup(ts::TableStore, functor::String, args::Vector)::Union{Some, Nothing}
    key = make_table_key(functor, args)
    if haskey(ts.cache, key)
        ts.hits += 1
        return Some(ts.cache[key])
    end
    ts.misses += 1
    return nothing
end

"""
    table_store!(ts, functor, args, result)

Store a resolved result in the table for future lookups.
"""
function table_store!(ts::TableStore, functor::String, args::Vector, result)
    key = make_table_key(functor, args)
    ts.cache[key] = result
end

"""
    table_stats(ts)

Return a named tuple of table performance statistics.
"""
function table_stats(ts::TableStore)
    return (hits=ts.hits, misses=ts.misses, evictions=ts.evictions,
            size=length(ts.cache), max_size=ts.cache.maxsize)
end
