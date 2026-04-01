# SLD Resolution Engine
# "For the principled dispatch of add(2, 3)"

struct NoMatchingClauseError <: Exception
    functor::String
    args::Vector{Any}
    attempted::Vector{Clause}
    location::Any  # SourceLocation
end

function Base.showerror(io::IO, e::NoMatchingClauseError)
    print(io, "NoMatchingClauseError at $(e.location): no clause matches $(e.functor)(")
    join(io, e.args, ", ")
    print(io, ")\n  Attempted $(length(e.attempted)) clause(s):")
    for (i, c) in enumerate(e.attempted)
        print(io, "\n    [$i] $(c.head_functor)(")
        join(io, [term_to_string(a) for a in c.head_args], ", ")
        print(io, ")")
    end
end

"""
    term_to_string(t)

Pretty-print a Term for error messages.
"""
function term_to_string(t::Term)::String
    if t isa Atom
        return repr(t.value)
    elseif t isa Variable
        return t.name
    elseif t isa Compound
        args = join([term_to_string(a) for a in t.args], ", ")
        return "$(t.functor)($args)"
    end
    return "?"
end

"""
    value_to_term(val)

Convert eric-lang runtime values to Terms for unification.
"""
function value_to_term(val)::Term
    if val isa String || val isa Number || val isa Bool
        return Atom(val)
    end
    return Atom(val)
end

"""
    resolve(kb, functor, args, location)

Find the first matching clause via unification (SLD resolution).
Returns `(clause, substitution)` or throws `NoMatchingClauseError`.
"""
function resolve(kb::KnowledgeBase, functor::String, args::Vector, location)
    arg_terms = [value_to_term(a) for a in args]
    goal = Compound(functor, arg_terms)

    candidates = find_clauses(kb, functor, length(args))

    # Also try with one fewer arg (implicit stack argument)
    if isempty(candidates)
        candidates = find_clauses(kb, functor, length(args) + 1)
    end

    for clause in candidates
        # Create fresh variables for this clause (rename to avoid capture)
        fresh_clause = freshen_variables(clause)
        head = Compound(fresh_clause.head_functor, fresh_clause.head_args)

        subst = unify(goal, head)
        if subst !== nothing
            return (fresh_clause, subst)
        end
    end

    # No match found — this is what review issue #10 asked for
    throw(NoMatchingClauseError(functor, args, candidates, location))
end

# Variable freshening counter (global, atomic via Ref)
const _fresh_counter = Ref(0)

"""
    freshen_variables(clause)

Alpha-rename all variables in a clause to avoid capture during unification.
Each call produces a unique suffix via a global counter.
"""
function freshen_variables(clause::Clause)::Clause
    _fresh_counter[] += 1
    suffix = "_$(_fresh_counter[])"

    function freshen(t::Term)::Term
        if t isa Variable
            return Variable(t.name * suffix)
        elseif t isa Compound
            return Compound(t.functor, [freshen(a) for a in t.args])
        end
        return t
    end

    return Clause(
        clause.head_functor,
        [freshen(a) for a in clause.head_args],
        clause.body
    )
end
