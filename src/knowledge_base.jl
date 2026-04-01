# Knowledge Base for eric-lang Function Dispatch
# Stores function definitions as Prolog-style clauses.
# fib(0) = 1 becomes: clause(fib, [Atom(0)], Atom(1))
# "Issue response rate is effectively 100%"

struct Clause
    head_functor::String
    head_args::Vector{Term}
    body::Any  # The AST node for the function body
end

mutable struct KnowledgeBase
    clauses::Vector{Clause}
    lock::ReentrantLock  # Thread-safe for parallel dispatch (review issue #7)

    KnowledgeBase() = new(Clause[], ReentrantLock())
end

"""
    assert_clause!(kb, clause)

Assert a new clause (function definition) into the knowledge base.
"""
function assert_clause!(kb::KnowledgeBase, clause::Clause)
    lock(kb.lock) do
        push!(kb.clauses, clause)
    end
end

"""
    retract_clause!(kb, idx)

Retract a clause by index (for LRU eviction of tabled results).
"""
function retract_clause!(kb::KnowledgeBase, idx::Int)
    lock(kb.lock) do
        deleteat!(kb.clauses, idx)
    end
end

"""
    find_clauses(kb, functor, arity)

Find all clauses matching a given functor name and arity.
"""
function find_clauses(kb::KnowledgeBase, functor::String, arity::Int)::Vector{Clause}
    lock(kb.lock) do
        filter(c -> c.head_functor == functor && length(c.head_args) == arity, kb.clauses)
    end
end
