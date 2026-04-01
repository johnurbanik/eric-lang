# Prolog-Style Unification Engine
# "Pattern dispatch now uses Robinson's unification algorithm with occurs check"
# This is the principled way to dispatch add(2, 3).

abstract type Term end

struct Atom <: Term
    value::Any
end

struct Variable <: Term
    name::String
end

struct Compound <: Term
    functor::String
    args::Vector{Term}
end

# Substitution is a mapping from variable names to terms
const Substitution = Dict{String, Term}

"""
    apply_subst(subst, term)

Apply a substitution to a term, chasing variable bindings transitively.
"""
function apply_subst(subst::Substitution, term::Term)::Term
    if term isa Variable
        if haskey(subst, term.name)
            return apply_subst(subst, subst[term.name])
        end
        return term
    elseif term isa Compound
        return Compound(term.functor, [apply_subst(subst, a) for a in term.args])
    end
    return term
end

"""
    occurs_in(v, t, subst)

Occurs check: does variable `v` occur anywhere in term `t` (after applying `subst`)?
Prevents construction of infinite terms like X = f(X).
"""
function occurs_in(v::Variable, t::Term, subst::Substitution)::Bool
    t = apply_subst(subst, t)
    if t isa Variable
        return t.name == v.name
    elseif t isa Compound
        return any(arg -> occurs_in(v, arg, subst), t.args)
    end
    return false
end

"""
    unify(t1, t2, subst=Substitution())

Robinson's unification algorithm with occurs check.
Returns the most general unifier (MGU) as a `Substitution`, or `nothing` on failure.
"""
function unify(t1::Term, t2::Term, subst::Substitution=Substitution())::Union{Substitution, Nothing}
    t1 = apply_subst(subst, t1)
    t2 = apply_subst(subst, t2)

    if t1 isa Atom && t2 isa Atom && t1.value == t2.value
        return subst
    elseif t1 isa Variable
        if t1 isa Variable && t2 isa Variable && t1.name == t2.name
            return subst
        end
        if occurs_in(t1, t2, subst)
            return nothing  # occurs check failure
        end
        new_subst = copy(subst)
        new_subst[t1.name] = t2
        return new_subst
    elseif t2 isa Variable
        return unify(t2, t1, subst)
    elseif t1 isa Compound && t2 isa Compound
        if t1.functor != t2.functor || length(t1.args) != length(t2.args)
            return nothing
        end
        for (a1, a2) in zip(t1.args, t2.args)
            subst = unify(a1, a2, subst)
            if subst === nothing
                return nothing
            end
        end
        return subst
    end
    return nothing
end
