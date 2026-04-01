# Built-in Functions
# These are the primitives that cannot be defined in eric-lang itself.
# Everything else lives in lazy_stdlib.jl.
#
# Original Python builtins: _, _1, _2, pyeval, stdin, split, int, print, sum,
#                           get, getd, set, remove, append
#
# New builtins: callcc, query, cut
# Removed builtins: pyeval (good riddance — review issue #1)

# Registry of built-in function implementations
# Each takes (interpreter, args) and returns a value
const BUILTIN_FUNCTIONS = Dict{String, Function}()

function register_builtin!(name::String, f::Function)
    BUILTIN_FUNCTIONS[name] = f
end

function is_builtin(name::String)::Bool
    return haskey(BUILTIN_FUNCTIONS, name)
end

# Identity / stack operations
register_builtin!("_", (interp, args) -> begin
    isempty(interp.stack) ? nothing : last(interp.stack)
end)

register_builtin!("_1", (interp, args) -> begin
    isempty(interp.stack) ? nothing : last(interp.stack)
end)

register_builtin!("_2", (interp, args) -> begin
    length(interp.stack) >= 2 ? interp.stack[end-1] : nothing
end)

# IO operations
register_builtin!("stdin", (interp, args) -> begin
    read(stdin, String)
end)

register_builtin!("print", (interp, args) -> begin
    val = isempty(args) ? (isempty(interp.stack) ? nothing : last(interp.stack)) : args[1]
    # In the monadic world, print produces an IOPrint action
    # But we also just print it because we're pragmatists
    println(val)
    push!(interp.io_actions, IOPrint(val))
    val
end)

# String operations
register_builtin!("split", (interp, args) -> begin
    if length(args) == 1
        data = pop!(interp.stack)
        delim = args[1]
    elseif length(args) == 2
        data = args[1]
        delim = args[2]
    else
        data = pop!(interp.stack)
        delim = pop!(interp.stack)
    end
    Tuple(split(string(data), string(delim)))
end)

# Type conversion
register_builtin!("int", (interp, args) -> begin
    val = isempty(args) ? pop!(interp.stack) : args[1]
    parse(Int, string(val))
end)

# Aggregation
register_builtin!("sum", (interp, args) -> begin
    coll = isempty(args) ? pop!(interp.stack) : args[1]
    sum(coll)
end)

# Collection access
register_builtin!("get", (interp, args) -> begin
    if length(args) == 2
        data, idx = args[1], args[2]
    else
        data = pop!(interp.stack)
        idx = args[1]
    end
    # eric-lang is 0-indexed (Python convention)
    if idx < 0
        data[end + idx + 1]
    else
        data[idx + 1]
    end
end)

register_builtin!("getd", (interp, args) -> begin
    if length(args) == 3
        data, idx, default = args[1], args[2], args[3]
    else
        data = pop!(interp.stack)
        idx, default = args[1], args[2]
    end
    actual_idx = idx < 0 ? length(data) + idx + 1 : idx + 1
    if actual_idx >= 1 && actual_idx <= length(data)
        data[actual_idx]
    else
        default
    end
end)

register_builtin!("set", (interp, args) -> begin
    if length(args) == 3
        data, idx, item = args[1], args[2], args[3]
    else
        data = pop!(interp.stack)
        idx, item = args[1], args[2]
    end
    actual_idx = idx < 0 ? length(data) + idx + 1 : idx + 1
    result = collect(data)
    result[actual_idx] = item
    Tuple(result)
end)

register_builtin!("remove", (interp, args) -> begin
    if length(args) == 2
        data, idx = args[1], args[2]
    else
        data = pop!(interp.stack)
        idx = args[1]
    end
    actual_idx = idx < 0 ? length(data) + idx + 1 : idx + 1
    result = collect(data)
    deleteat!(result, actual_idx)
    Tuple(result)
end)

register_builtin!("append", (interp, args) -> begin
    if length(args) == 2
        data, item = args[1], args[2]
    else
        data = pop!(interp.stack)
        item = args[1]
    end
    Tuple(vcat(collect(data), [item]))
end)

# New builtins for the principled rewrite
register_builtin!("callcc", (interp, args) -> begin
    # call/cc is handled specially in the CPS interpreter
    # This is a placeholder for direct invocation
    error("callcc must be used within the CPS interpreter")
end)

register_builtin!("query", (interp, args) -> begin
    # Prolog-style query against the knowledge base
    # query(fib(X, 8)) finds X where fib(X) = 8
    # This is handled specially in the interpreter
    error("query must be used within the interpreter")
end)
