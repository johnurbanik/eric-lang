# eric-lang Standard Library — Native Julia Edition
# "No more eval(). No more pyeval(). Every function is a real function."
#
# This file replaces the entire Python-backed stdlib with pure Julia
# implementations that integrate with the Thunk/Force lazy evaluation system.
#
# All functions accept already-forced values and return plain values.
# The interpreter is responsible for forcing thunks before calling these
# and wrapping results back in thunks if needed.

using ProgressMeter: @showprogress, Progress, next!

# ============================================================================
# Arithmetic
# ============================================================================

_eric_add(a, b) = a + b
_eric_sub(a, b) = a - b
_eric_mul(a, b) = a * b
_eric_div(a, b) = a / b
_eric_idiv(a, b) = fld(a, b)
_eric_mod(a, b) = mod(a, b)
_eric_neg(a) = -a
_eric_inc(a) = a + 1
_eric_abs(a) = abs(a)
_eric_ceil(a) = Int(ceil(a))
_eric_floor(a) = Int(floor(a))
_eric_sqrt(a) = sqrt(a)
_eric_gcd(a, b) = gcd(a, b)

# ============================================================================
# Comparison
# ============================================================================

_eric_lt(a, b) = a < b
_eric_gt(a, b) = a > b
_eric_lte(a, b) = a <= b
_eric_gte(a, b) = a >= b
_eric_eq(a, b) = a == b

# ============================================================================
# Logic
# ============================================================================

_eric_and(a, b) = a && b
_eric_or(a, b) = a || b
_eric_not(a) = !a

function _eric_all(coll)
    for item in coll
        if !item
            return false
        end
    end
    return true
end

function _eric_any(coll)
    for item in coll
        if item
            return true
        end
    end
    return false
end

# ============================================================================
# String
# ============================================================================

function _eric_join(sep, coll)
    # coll may be a tuple or vector; sep is a string
    return Base.join(coll, sep)
end

_eric_replace(s, old, new_str) = replace(s, old => new_str)

# strip with 1 arg: strip whitespace; with 2 args: strip specific chars
_eric_strip(s) = strip(s)
_eric_strip(s, chars) = strip(s, collect(chars))

_eric_isdigit(s) = all(isdigit, s)
_eric_ord(s) = Int(first(s))
_eric_splitlines(s) = collect(split(s, r"\r?\n"))

# ============================================================================
# Collection
# ============================================================================

_eric_first(coll) = coll[1]
_eric_second(coll) = coll[2]
_eric_third(coll) = coll[3]
_eric_last(coll) = coll[end]
_eric_index(coll, i) = coll[i]

function _eric_range(args...)
    if length(args) == 1
        return collect(0:args[1]-1)
    elseif length(args) == 2
        return collect(args[1]:args[2]-1)
    elseif length(args) == 3
        return collect(args[1]:args[3]:args[2]-1)
    end
    error("range expects 1-3 arguments, got $(length(args))")
end

_eric_len(coll) = length(coll)

function _eric_slice(coll, start, stop)
    # Python-style slicing: 0-indexed, exclusive end
    # eric-lang uses 0-indexed slicing; Julia is 1-indexed
    return coll[start+1:stop]
end

_eric_distinct(coll) = unique(coll)

function _eric_intersect(a, b)
    set_b = Set(b)
    return [x for x in a if x in set_b]
end

_eric_enumerate(coll) = collect(enumerate(coll))

function _eric_flatten(coll)
    result = Any[]
    _flatten_into!(result, coll)
    return result
end

function _flatten_into!(result, item)
    if item isa AbstractVector || item isa Tuple
        for x in item
            _flatten_into!(result, x)
        end
    else
        push!(result, item)
    end
end

_eric_sort(coll) = sort(collect(coll))

function _eric_sort(coll, key)
    return sort(collect(coll); by=key)
end

_eric_reverse(coll) = reverse(collect(coll))

function _eric_append(coll, item)
    result = collect(coll)
    push!(result, item)
    return result
end

function _eric_prepend(coll, item)
    result = collect(coll)
    pushfirst!(result, item)
    return result
end

function _eric_extend(a, b)
    result = collect(a)
    append!(result, b)
    return result
end

_eric_tail(coll) = coll[2:end]

# list() — convert anything iterable into a vector
_eric_list(coll) = collect(coll)

function _eric_transpose(matrix)
    # matrix is a collection of collections (rows)
    rows = [collect(row) for row in matrix]
    n_rows = length(rows)
    n_cols = length(rows[1])
    return [Any[rows[r][c] for r in 1:n_rows] for c in 1:n_cols]
end

_eric_contains(coll, item) = item in coll

function _eric_max(args...)
    if length(args) == 1
        return maximum(args[1])
    else
        return maximum(args)
    end
end

function _eric_min(args...)
    if length(args) == 1
        return minimum(args[1])
    else
        return minimum(args)
    end
end

# ============================================================================
# Map (dictionary) emulation
# "Maps are just lists of pairs. This is fine."
# ============================================================================

function _eric_map_build(keys, values)
    return Dict(zip(keys, values))
end

function _eric_map_append(d, key, value)
    result = copy(d)
    result[key] = value
    return result
end

_eric_map_get(d, key) = d[key]

function _eric_map_get(d, key, default)
    return get(d, key, default)
end

_eric_map_contains(d, key) = haskey(d, key)

# ============================================================================
# Other
# ============================================================================

function _eric_progress(coll)
    items = collect(coll)
    p = Progress(length(items); showspeed=true)
    result = Any[]
    for item in items
        push!(result, item)
        next!(p)
    end
    return result
end

# ============================================================================
# STDLIB_FUNCTIONS registry
# "One Dict to rule them all, one Dict to find them,
#  one Dict to bring them all, and in the laziness bind them."
# ============================================================================

const STDLIB_FUNCTIONS = Dict{String, Function}(
    # Arithmetic
    "add"   => _eric_add,
    "sub"   => _eric_sub,
    "mul"   => _eric_mul,
    "div"   => _eric_div,
    "idiv"  => _eric_idiv,
    "mod"   => _eric_mod,
    "neg"   => _eric_neg,
    "inc"   => _eric_inc,
    "abs"   => _eric_abs,
    "ceil"  => _eric_ceil,
    "floor" => _eric_floor,
    "sqrt"  => _eric_sqrt,
    "gcd"   => _eric_gcd,

    # Comparison
    "lt"    => _eric_lt,
    "gt"    => _eric_gt,
    "lte"   => _eric_lte,
    "gte"   => _eric_gte,
    "eq"    => _eric_eq,

    # Logic
    "and"   => _eric_and,
    "or"    => _eric_or,
    "not"   => _eric_not,
    "all"   => _eric_all,
    "any"   => _eric_any,

    # String
    "join"       => _eric_join,
    "replace"    => _eric_replace,
    "strip"      => _eric_strip,
    "isdigit"    => _eric_isdigit,
    "ord"        => _eric_ord,
    "splitlines" => _eric_splitlines,

    # Collection
    "first"     => _eric_first,
    "second"    => _eric_second,
    "third"     => _eric_third,
    "last"      => _eric_last,
    "index"     => _eric_index,
    "range"     => _eric_range,
    "len"       => _eric_len,
    "slice"     => _eric_slice,
    "distinct"  => _eric_distinct,
    "intersect" => _eric_intersect,
    "enumerate" => _eric_enumerate,
    "flatten"   => _eric_flatten,
    "sort"      => _eric_sort,
    "reverse"   => _eric_reverse,
    "append"    => _eric_append,
    "prepend"   => _eric_prepend,
    "extend"    => _eric_extend,
    "tail"      => _eric_tail,
    "list"      => _eric_list,
    "transpose" => _eric_transpose,
    "contains"  => _eric_contains,
    "max"       => _eric_max,
    "min"       => _eric_min,

    # Map emulation
    "map_build"    => _eric_map_build,
    "map_append"   => _eric_map_append,
    "map_get"      => _eric_map_get,
    "map_contains" => _eric_map_contains,

    # Other
    "progress" => _eric_progress,
)

# ============================================================================
# STDLIB_ARITIES — accepted argument counts for each function
# "Because variadic functions are the enemy of static analysis,
#  and we pretend to care about that now."
# ============================================================================

const STDLIB_ARITIES = Dict{String, Vector{Int}}(
    # Arithmetic
    "add"   => [2],
    "sub"   => [2],
    "mul"   => [2],
    "div"   => [2],
    "idiv"  => [2],
    "mod"   => [2],
    "neg"   => [1],
    "inc"   => [1],
    "abs"   => [1],
    "ceil"  => [1],
    "floor" => [1],
    "sqrt"  => [1],
    "gcd"   => [2],

    # Comparison
    "lt"    => [2],
    "gt"    => [2],
    "lte"   => [2],
    "gte"   => [2],
    "eq"    => [2],

    # Logic
    "and"   => [2],
    "or"    => [2],
    "not"   => [1],
    "all"   => [1],
    "any"   => [1],

    # String
    "join"       => [2],
    "replace"    => [3],
    "strip"      => [1, 2],
    "isdigit"    => [1],
    "ord"        => [1],
    "splitlines" => [1],

    # Collection
    "first"     => [1],
    "second"    => [1],
    "third"     => [1],
    "last"      => [1],
    "index"     => [2],
    "range"     => [1, 2, 3],
    "len"       => [1],
    "slice"     => [3],
    "distinct"  => [1],
    "intersect" => [2],
    "enumerate" => [1],
    "flatten"   => [1],
    "sort"      => [1, 2],
    "reverse"   => [1],
    "append"    => [2],
    "prepend"   => [2],
    "extend"    => [2],
    "tail"      => [1],
    "list"      => [1],
    "transpose" => [1],
    "contains"  => [2],
    "max"       => [1, 2],
    "min"       => [1, 2],

    # Map emulation
    "map_build"    => [2],
    "map_append"   => [3],
    "map_get"      => [2, 3],
    "map_contains" => [2],

    # Other
    "progress" => [1],
)
