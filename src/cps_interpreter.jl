# CPS Tree-Walking Interpreter for eric-lang
#
# "A stack-based language evaluated via continuation-passing style,
#  with Prolog-style unification for dispatch.  As one does."
#
# Depends on: continuations.jl, ast_nodes.jl, knowledge_base.jl, table_store.jl

# ---------------------------------------------------------------------------
# AST node types (stubs -- these would be defined in ast_nodes.jl)
# ---------------------------------------------------------------------------

abstract type ASTNode end

struct ModuleNode <: ASTNode
    blocks::Vector{ASTNode}
end

struct BlockNode <: ASTNode
    statements::Vector{ASTNode}
end

struct StatementNode <: ASTNode
    expr::ASTNode
    binding::Union{String, Nothing}       # the `as x` part
    indented_block::Union{ASTNode, Nothing}  # indented block under this statement
end

struct LiteralNode <: ASTNode
    value::Any
end

struct IdentifierNode <: ASTNode
    name::String
end

struct ExpressionNode <: ASTNode
    head::String              # function / special form name
    args::Vector{ASTNode}
    indented_block::Union{ASTNode, Nothing}
end

struct CollectionNode <: ASTNode
    items::Vector{ASTNode}
    is_spread::Vector{Bool}   # per-item: is this a ...spread?
end

struct AssignmentNode <: ASTNode
    name::String
    params::Vector{String}
    body::ASTNode
    guard::Union{ASTNode, Nothing}  # optional when-guard
end

struct SpreadNode <: ASTNode
    inner::ASTNode
end

# ---------------------------------------------------------------------------
# Errors
# ---------------------------------------------------------------------------

struct NoMatchingClauseError <: Exception
    name::String
    args::Vector{Any}
end

function Base.showerror(io::IO, e::NoMatchingClauseError)
    print(io, "NoMatchingClauseError: no clause matches $(e.name)($(join(e.args, ", ")))")
end

# ---------------------------------------------------------------------------
# Stub types for external modules (knowledge_base.jl, table_store.jl)
# Replace with real imports in the full project.
# ---------------------------------------------------------------------------

# A clause in the knowledge base: name, param patterns, guard, body
struct Clause
    name::String
    params::Vector{String}
    guard::Union{ASTNode, Nothing}
    body::ASTNode
end

# Minimal knowledge base backed by a Dict of clause lists
mutable struct KnowledgeBase
    clauses::Dict{String, Vector{Clause}}
    KnowledgeBase() = new(Dict{String, Vector{Clause}}())
end

function add_clause!(kb::KnowledgeBase, clause::Clause)
    clauses = get!(kb.clauses, clause.name, Clause[])
    push!(clauses, clause)
end

function lookup_clauses(kb::KnowledgeBase, name::String)::Vector{Clause}
    return get(kb.clauses, name, Clause[])
end

# Minimal table store (memoization cache)
mutable struct TableStore
    tables::Dict{String, Dict{UInt64, Any}}
    TableStore() = new(Dict{String, Dict{UInt64, Any}}())
end

function table_get(ts::TableStore, table::String, key::UInt64)
    t = get(ts.tables, table, nothing)
    t === nothing && return nothing
    return get(t, key, nothing)
end

function table_put!(ts::TableStore, table::String, key::UInt64, value)
    t = get!(ts.tables, table, Dict{UInt64, Any}())
    t[key] = value
end

# ---------------------------------------------------------------------------
# The Interpreter
# ---------------------------------------------------------------------------

"""
The CPS interpreter state.

Mutable because a stack-based language needs mutable state,
and we've already committed enough sins that one more won't matter.
"""
mutable struct CPSInterpreter
    knowledge_base::KnowledgeBase
    table_store::TableStore
    stack::Vector{Any}
    variables::Dict{String, Any}
    io_actions::Vector{Any}          # collected IO monad actions
end

function CPSInterpreter()
    return CPSInterpreter(
        KnowledgeBase(),
        TableStore(),
        Any[],
        Dict{String, Any}(),
        Any[],
    )
end

"""Create a child interpreter sharing knowledge base and table store but with a fresh stack."""
function child_interpreter(parent::CPSInterpreter)
    return CPSInterpreter(
        parent.knowledge_base,
        parent.table_store,
        Any[],
        copy(parent.variables),
        parent.io_actions,
    )
end

# ---------------------------------------------------------------------------
# Stack helpers
# ---------------------------------------------------------------------------

function stack_push!(interp::CPSInterpreter, value)
    push!(interp.stack, value)
end

function stack_pop!(interp::CPSInterpreter)
    isempty(interp.stack) && error("Stack underflow! The stack is empty. " *
        "This is what happens when you use CPS for a stack language.")
    return pop!(interp.stack)
end

function stack_peek(interp::CPSInterpreter)
    isempty(interp.stack) && error("Stack underflow on peek!")
    return interp.stack[end]
end

# ---------------------------------------------------------------------------
# Built-in functions registry
# ---------------------------------------------------------------------------

const SPECIAL_FORMS = Set([
    "reduce", "filter", "parallel", "memoize", "if", "cond", "call_cc",
])

const BUILTINS = Dict{String, Function}()

function register_builtin!(name::String, f::Function)
    BUILTINS[name] = f
end

# Arithmetic
register_builtin!("+",   (interp, args) -> args[1] + args[2])
register_builtin!("-",   (interp, args) -> args[1] - args[2])
register_builtin!("*",   (interp, args) -> args[1] * args[2])
register_builtin!("/",   (interp, args) -> args[1] / args[2])
register_builtin!("mod", (interp, args) -> mod(args[1], args[2]))

# Comparison
register_builtin!("==",  (interp, args) -> args[1] == args[2])
register_builtin!("!=",  (interp, args) -> args[1] != args[2])
register_builtin!("<",   (interp, args) -> args[1] <  args[2])
register_builtin!(">",   (interp, args) -> args[1] >  args[2])
register_builtin!("<=",  (interp, args) -> args[1] <= args[2])
register_builtin!(">=",  (interp, args) -> args[1] >= args[2])

# Stack operations
register_builtin!("dup",  (interp, args) -> begin
    v = stack_peek(interp)
    stack_push!(interp, v)
    v
end)
register_builtin!("drop", (interp, args) -> stack_pop!(interp))
register_builtin!("swap", (interp, args) -> begin
    a = stack_pop!(interp)
    b = stack_pop!(interp)
    stack_push!(interp, a)
    stack_push!(interp, b)
    b
end)

# Collection operations
register_builtin!("length", (interp, args) -> length(args[1]))
register_builtin!("head",   (interp, args) -> first(args[1]))
register_builtin!("tail",   (interp, args) -> args[1][2:end])
register_builtin!("cons",   (interp, args) -> vcat([args[1]], args[2]))
register_builtin!("append", (interp, args) -> vcat(args[1], args[2]))
register_builtin!("range",  (interp, args) -> collect(args[1]:args[2]))

# IO (collected as actions, not executed -- we're pure, obviously)
register_builtin!("print", (interp, args) -> begin
    action = (:print, args[1])
    push!(interp.io_actions, action)
    args[1]
end)
register_builtin!("println", (interp, args) -> begin
    action = (:println, args[1])
    push!(interp.io_actions, action)
    args[1]
end)

# Type checks
register_builtin!("is_number",  (interp, args) -> args[1] isa Number)
register_builtin!("is_string",  (interp, args) -> args[1] isa AbstractString)
register_builtin!("is_list",    (interp, args) -> args[1] isa AbstractVector)
register_builtin!("is_tuple",   (interp, args) -> args[1] isa Tuple)
register_builtin!("to_string",  (interp, args) -> string(args[1]))
register_builtin!("to_number",  (interp, args) -> parse(Float64, string(args[1])))

# ---------------------------------------------------------------------------
# Core eval_node dispatch
# ---------------------------------------------------------------------------

# -- ModuleNode: evaluate each block in sequence ---------------------------

function eval_node(interp::CPSInterpreter, node::ModuleNode, k::AbstractContinuation)
    if isempty(node.blocks)
        return continue_with(k, nothing)
    end

    # Build a continuation chain: block1 -> block2 -> ... -> k
    function eval_blocks(blocks, idx, k)
        if idx > length(blocks)
            return continue_with(k, nothing)
        end
        next_k = Continuation(
            _ -> eval_blocks(blocks, idx + 1, k),
            "module block $(idx + 1)"
        )
        return eval_node(interp, blocks[idx], next_k)
    end

    return eval_blocks(node.blocks, 1, k)
end

# -- BlockNode: evaluate statements in sequence ----------------------------

function eval_node(interp::CPSInterpreter, node::BlockNode, k::AbstractContinuation)
    if isempty(node.statements)
        return continue_with(k, nothing)
    end

    function eval_stmts(stmts, idx, k)
        if idx > length(stmts)
            # The "result" of a block is the top of stack (if any) or nothing
            result = isempty(interp.stack) ? nothing : stack_peek(interp)
            return continue_with(k, result)
        end
        next_k = Continuation(
            _ -> eval_stmts(stmts, idx + 1, k),
            "stmt $(idx + 1) of block"
        )
        return eval_node(interp, stmts[idx], next_k)
    end

    return eval_stmts(node.statements, 1, k)
end

# -- StatementNode: eval expr, handle `as` binding, handle indented blocks -

function eval_node(interp::CPSInterpreter, node::StatementNode, k::AbstractContinuation)
    # After evaluating the expression:
    after_expr = Continuation(
        function (value)
            # Handle `as` binding
            if node.binding !== nothing
                interp.variables[node.binding] = value
            end

            # Handle indented block (implicit map if not a special form)
            if node.indented_block !== nothing
                return eval_implicit_map(interp, value, node.indented_block, k)
            end

            return continue_with(k, value)
        end,
        "after statement expr"
    )

    return eval_node(interp, node.expr, after_expr)
end

# -- LiteralNode: push value, continue ------------------------------------

function eval_node(interp::CPSInterpreter, node::LiteralNode, k::AbstractContinuation)
    stack_push!(interp, node.value)
    return continue_with(k, node.value)
end

# -- IdentifierNode: look up variable or built-in -------------------------

function eval_node(interp::CPSInterpreter, node::IdentifierNode, k::AbstractContinuation)
    name = node.name

    # 1. Check simple variable bindings
    if haskey(interp.variables, name)
        value = interp.variables[name]
        stack_push!(interp, value)
        return continue_with(k, value)
    end

    # 2. Check if it's a known builtin (return as a callable)
    if haskey(BUILTINS, name)
        # Push the builtin function reference as a value
        stack_push!(interp, BUILTINS[name])
        return continue_with(k, BUILTINS[name])
    end

    # 3. Check knowledge base (zero-arg function)
    clauses = lookup_clauses(interp.knowledge_base, name)
    if !isempty(clauses)
        return try_clauses(interp, clauses, Any[], k)
    end

    error("Unbound identifier: $name")
end

# -- ExpressionNode: the big one -------------------------------------------

function eval_node(interp::CPSInterpreter, node::ExpressionNode, k::AbstractContinuation)
    head = node.head

    # Evaluate all arguments first (left to right, CPS-style)
    eval_args_cps(interp, node.args, Any[]) do evaluated_args
        # Now dispatch based on head
        if head in SPECIAL_FORMS
            return eval_special_form(interp, head, evaluated_args, node.indented_block, k)
        end

        # Check simple variable bindings (might be a lambda / reified continuation)
        if haskey(interp.variables, head)
            value = interp.variables[head]
            if value isa ReifiedContinuation
                # Invoking a captured continuation
                arg = isempty(evaluated_args) ? stack_pop!(interp) : evaluated_args[1]
                return continue_with(value, arg)
            elseif value isa Function
                result = value(evaluated_args...)
                stack_push!(interp, result)
                return continue_with(k, result)
            end
        end

        # Try knowledge base (Prolog-style unification dispatch)
        clauses = lookup_clauses(interp.knowledge_base, head)
        if !isempty(clauses)
            return try_clauses_with_implicit_first(interp, clauses, evaluated_args, k)
        end

        # Try built-in functions
        if haskey(BUILTINS, head)
            args_for_builtin = if isempty(evaluated_args) && !isempty(interp.stack)
                # Implicit: pop from stack
                [stack_pop!(interp)]
            else
                evaluated_args
            end
            result = BUILTINS[head](interp, args_for_builtin)
            stack_push!(interp, result)
            return continue_with(k, result)
        end

        throw(NoMatchingClauseError(head, evaluated_args))
    end
end

# -- CollectionNode: evaluate items, handle spread -------------------------

function eval_node(interp::CPSInterpreter, node::CollectionNode, k::AbstractContinuation)
    eval_collection_items(interp, node.items, node.is_spread, 1, Any[]) do collected
        result = Tuple(collected)
        stack_push!(interp, result)
        return continue_with(k, result)
    end
end

function eval_collection_items(callback::Function, interp::CPSInterpreter,
                                items::Vector{ASTNode}, spreads::Vector{Bool},
                                idx::Int, acc::Vector{Any})
    if idx > length(items)
        return callback(acc)
    end

    item_k = Continuation(
        function (value)
            if spreads[idx]
                # Spread: splice the collection into the result
                if value isa AbstractVector || value isa Tuple
                    append!(acc, collect(value))
                else
                    error("Cannot spread non-collection: $value")
                end
            else
                push!(acc, value)
            end
            return eval_collection_items(callback, interp, items, spreads, idx + 1, acc)
        end,
        "collection item $idx"
    )

    return eval_node(interp, items[idx], item_k)
end

# -- AssignmentNode: define a function in the knowledge base ---------------

function eval_node(interp::CPSInterpreter, node::AssignmentNode, k::AbstractContinuation)
    clause = Clause(node.name, node.params, node.guard, node.body)
    add_clause!(interp.knowledge_base, clause)
    return continue_with(k, Symbol(node.name))
end

# -- SpreadNode: evaluate inner, mark as spread ----------------------------

function eval_node(interp::CPSInterpreter, node::SpreadNode, k::AbstractContinuation)
    return eval_node(interp, node.inner, k)
end

# ---------------------------------------------------------------------------
# Argument evaluation (CPS)
# ---------------------------------------------------------------------------

"""Evaluate a list of AST nodes left-to-right in CPS, collecting results."""
function eval_args_cps(callback::Function, interp::CPSInterpreter,
                       args::Vector{ASTNode}, acc::Vector{Any})
    if isempty(args)
        return callback(acc)
    end

    eval_args_cps_step(callback, interp, args, 1, acc)
end

function eval_args_cps_step(callback::Function, interp::CPSInterpreter,
                            args::Vector{ASTNode}, idx::Int, acc::Vector{Any})
    if idx > length(args)
        return callback(acc)
    end

    arg_k = Continuation(
        function (value)
            push!(acc, value)
            return eval_args_cps_step(callback, interp, args, idx + 1, acc)
        end,
        "arg $idx"
    )

    return eval_node(interp, args[idx], arg_k)
end

# ---------------------------------------------------------------------------
# Special forms
# ---------------------------------------------------------------------------

function eval_special_form(interp::CPSInterpreter, form::String,
                           args::Vector{Any}, block::Union{ASTNode, Nothing},
                           k::AbstractContinuation)
    if form == "reduce"
        return eval_reduce(interp, args, block, k)
    elseif form == "filter"
        return eval_filter(interp, args, block, k)
    elseif form == "parallel"
        return eval_parallel(interp, args, block, k)
    elseif form == "memoize"
        return eval_memoize(interp, args, block, k)
    elseif form == "if"
        return eval_if(interp, args, block, k)
    elseif form == "cond"
        return eval_cond(interp, args, block, k)
    elseif form == "call_cc"
        return eval_call_cc(interp, args, k)
    else
        error("Unknown special form: $form")
    end
end

# -- reduce(init) + block: fold over collection with accumulator -----------

function eval_reduce(interp::CPSInterpreter, args::Vector{Any},
                     block::Union{ASTNode, Nothing}, k::AbstractContinuation)
    block === nothing && error("reduce requires an indented block")
    isempty(args) && error("reduce requires an initial value argument")

    init = args[1]
    collection = stack_pop!(interp)

    if !(collection isa AbstractVector || collection isa Tuple)
        error("reduce expects a collection on the stack, got: $(typeof(collection))")
    end

    items = collect(collection)

    function fold_step(acc, idx)
        if idx > length(items)
            stack_push!(interp, acc)
            return continue_with(k, acc)
        end

        sub = child_interpreter(interp)
        # Push accumulator and current element onto sub-interpreter stack
        stack_push!(sub, acc)
        stack_push!(sub, items[idx])

        fold_k = Continuation(
            function (_)
                new_acc = stack_pop!(sub)
                return fold_step(new_acc, idx + 1)
            end,
            "reduce step $idx"
        )

        return eval_node(sub, block, fold_k)
    end

    return fold_step(init, 1)
end

# -- filter + block: keep elements where block returns truthy --------------

function eval_filter(interp::CPSInterpreter, args::Vector{Any},
                     block::Union{ASTNode, Nothing}, k::AbstractContinuation)
    block === nothing && error("filter requires an indented block")

    collection = stack_pop!(interp)
    items = collect(collection)
    results = Any[]

    function filter_step(idx)
        if idx > length(items)
            result = Tuple(results)
            stack_push!(interp, result)
            return continue_with(k, result)
        end

        sub = child_interpreter(interp)
        stack_push!(sub, items[idx])

        step_k = Continuation(
            function (_)
                predicate_result = stack_pop!(sub)
                if _truthy(predicate_result)
                    push!(results, items[idx])
                end
                return filter_step(idx + 1)
            end,
            "filter step $idx"
        )

        return eval_node(sub, block, step_k)
    end

    return filter_step(1)
end

# -- parallel(N) + block: map with Julia threading -------------------------

function eval_parallel(interp::CPSInterpreter, args::Vector{Any},
                       block::Union{ASTNode, Nothing}, k::AbstractContinuation)
    block === nothing && error("parallel requires an indented block")

    num_workers = isempty(args) ? Threads.nthreads() : Int(args[1])
    collection = stack_pop!(interp)
    items = collect(collection)

    # Spawn tasks -- each gets its own child interpreter
    tasks = map(items) do item
        Threads.@spawn begin
            sub = child_interpreter(interp)
            stack_push!(sub, item)
            # Evaluate block synchronously within the spawned task
            result_holder = Ref{Any}(nothing)
            harvest_k = Continuation(
                function (_)
                    result_holder[] = isempty(sub.stack) ? nothing : stack_pop!(sub)
                    return result_holder[]
                end,
                "parallel harvest"
            )
            eval_node(sub, block, harvest_k)
            return result_holder[]
        end
    end

    # Collect results
    results = map(fetch, tasks)
    result = Tuple(results)
    stack_push!(interp, result)
    return continue_with(k, result)
end

# -- memoize(key) + block: check table_store, compute if miss, cache ------

function eval_memoize(interp::CPSInterpreter, args::Vector{Any},
                      block::Union{ASTNode, Nothing}, k::AbstractContinuation)
    block === nothing && error("memoize requires an indented block")
    isempty(args) && error("memoize requires a key argument")

    table_name = string(args[1])
    # Build a hash key from the current stack top (the input)
    input = isempty(interp.stack) ? nothing : stack_peek(interp)
    cache_key = hash(input)

    # Check cache
    cached = table_get(interp.table_store, table_name, cache_key)
    if cached !== nothing
        stack_push!(interp, cached)
        return continue_with(k, cached)
    end

    # Cache miss: evaluate block, then cache
    cache_k = Continuation(
        function (_)
            result = stack_pop!(interp)
            table_put!(interp.table_store, table_name, cache_key, result)
            stack_push!(interp, result)
            return continue_with(k, result)
        end,
        "memoize cache store"
    )

    return eval_node(interp, block, cache_k)
end

# -- if(cond, then, else) -------------------------------------------------

function eval_if(interp::CPSInterpreter, args::Vector{Any},
                 block::Union{ASTNode, Nothing}, k::AbstractContinuation)
    length(args) < 3 && error("if requires 3 arguments: condition, then-value, else-value")

    condition, then_val, else_val = args[1], args[2], args[3]

    result = _truthy(condition) ? then_val : else_val
    stack_push!(interp, result)
    return continue_with(k, result)
end

# -- cond(pairs...) -------------------------------------------------------

function eval_cond(interp::CPSInterpreter, args::Vector{Any},
                   block::Union{ASTNode, Nothing}, k::AbstractContinuation)
    # args come in pairs: [cond1, val1, cond2, val2, ...]
    # last unpaired element is the default
    i = 1
    while i + 1 <= length(args)
        if _truthy(args[i])
            result = args[i + 1]
            stack_push!(interp, result)
            return continue_with(k, result)
        end
        i += 2
    end

    # Default case (odd argument = default value)
    if i <= length(args)
        result = args[i]
        stack_push!(interp, result)
        return continue_with(k, result)
    end

    # No match, no default
    stack_push!(interp, nothing)
    return continue_with(k, nothing)
end

# -- call/cc: capture current continuation ---------------------------------

function eval_call_cc(interp::CPSInterpreter, args::Vector{Any},
                      k::AbstractContinuation)
    # call/cc captures the current continuation k and makes it a first-class value.
    # The argument should be a variable name to bind the reified continuation to.
    call_cc(k) do reified_k, real_k
        if !isempty(args) && args[1] isa String
            # Bind the reified continuation to the named variable
            interp.variables[args[1]] = reified_k
        end
        # Push the reified continuation onto the stack too
        stack_push!(interp, reified_k)
        return continue_with(real_k, reified_k)
    end
end

# ---------------------------------------------------------------------------
# Implicit map (indented block under a statement that isn't a special form)
# ---------------------------------------------------------------------------

"""
When a statement has an indented block and the result is a collection,
iterate over the collection, run the block for each element in a
child interpreter, and collect results as a tuple.
"""
function eval_implicit_map(interp::CPSInterpreter, value,
                           block::ASTNode, k::AbstractContinuation)
    if !(value isa AbstractVector || value isa Tuple)
        # Not a collection -- just evaluate the block with value on stack
        sub = child_interpreter(interp)
        stack_push!(sub, value)
        block_k = Continuation(
            function (_)
                result = isempty(sub.stack) ? nothing : stack_pop!(sub)
                stack_push!(interp, result)
                return continue_with(k, result)
            end,
            "single implicit map"
        )
        return eval_node(sub, block, block_k)
    end

    items = collect(value)
    results = Any[]

    function map_step(idx)
        if idx > length(items)
            result = Tuple(results)
            stack_push!(interp, result)
            return continue_with(k, result)
        end

        sub = child_interpreter(interp)
        stack_push!(sub, items[idx])

        step_k = Continuation(
            function (_)
                r = isempty(sub.stack) ? nothing : stack_pop!(sub)
                push!(results, r)
                return map_step(idx + 1)
            end,
            "implicit map step $idx"
        )

        return eval_node(sub, block, step_k)
    end

    return map_step(1)
end

# ---------------------------------------------------------------------------
# Clause resolution (Prolog-style dispatch)
# ---------------------------------------------------------------------------

"""
Try to match args against clauses. First matching clause wins.
"""
function try_clauses(interp::CPSInterpreter, clauses::Vector{Clause},
                     args::Vector{Any}, k::AbstractContinuation)
    for clause in clauses
        bindings = try_unify(clause.params, args)
        bindings === nothing && continue

        # Check guard if present
        if clause.guard !== nothing
            guard_interp = child_interpreter(interp)
            merge!(guard_interp.variables, bindings)
            guard_result = eval_node_sync(guard_interp, clause.guard)
            _truthy(guard_result) || continue
        end

        # Match! Evaluate body with bindings
        body_interp = child_interpreter(interp)
        merge!(body_interp.variables, bindings)

        body_k = Continuation(
            function (_)
                result = isempty(body_interp.stack) ? nothing : stack_pop!(body_interp)
                stack_push!(interp, result)
                return continue_with(k, result)
            end,
            "clause body for $(clause.name)"
        )

        return eval_node(body_interp, clause.body, body_k)
    end

    throw(NoMatchingClauseError(
        isempty(clauses) ? "?" : clauses[1].name,
        args
    ))
end

"""
Try clauses with the implicit first argument rule:
if a function has N params but we have N-1 args, pop the stack top as arg 1.
"""
function try_clauses_with_implicit_first(interp::CPSInterpreter,
                                          clauses::Vector{Clause},
                                          args::Vector{Any},
                                          k::AbstractContinuation)
    # First try direct match
    for clause in clauses
        if length(clause.params) == length(args)
            bindings = try_unify(clause.params, args)
            if bindings !== nothing
                return try_clauses(interp, [clause], args, k)
            end
        end
    end

    # Try implicit first argument
    for clause in clauses
        if length(clause.params) == length(args) + 1 && !isempty(interp.stack)
            implicit_first = stack_pop!(interp)
            full_args = vcat([implicit_first], args)
            bindings = try_unify(clause.params, full_args)
            if bindings !== nothing
                return try_clauses(interp, [clause], full_args, k)
            end
            # Didn't match, put it back
            stack_push!(interp, implicit_first)
        end
    end

    # Fall through to error
    return try_clauses(interp, clauses, args, k)
end

# ---------------------------------------------------------------------------
# Unification (simplified pattern matching)
# ---------------------------------------------------------------------------

"""
Try to unify parameter names with argument values.
Returns a Dict of bindings on success, nothing on failure.

This is a simplified version -- real Prolog unification would handle
nested terms, but this is a stack language that adds numbers, so...
"""
function try_unify(params::Vector{String}, args::Vector{Any})
    length(params) != length(args) && return nothing

    bindings = Dict{String, Any}()

    for (param, arg) in zip(params, args)
        if startswith(param, "_")
            # Wildcard -- matches anything, no binding
            continue
        elseif startswith(param, ":")
            # Literal match -- param `:foo` must equal the symbol :foo
            expected = Symbol(param[2:end])
            arg == expected || return nothing
        else
            # Variable -- bind it
            if haskey(bindings, param)
                # Already bound -- must match
                bindings[param] == arg || return nothing
            else
                bindings[param] = arg
            end
        end
    end

    return bindings
end

# ---------------------------------------------------------------------------
# Synchronous eval (for guards and simple expressions)
# ---------------------------------------------------------------------------

"""Evaluate a node synchronously (blocks until done). Used for guards."""
function eval_node_sync(interp::CPSInterpreter, node::ASTNode)
    result = Ref{Any}(nothing)
    harvest = Continuation(
        v -> begin result[] = v; v end,
        "sync harvest"
    )
    eval_node(interp, node, harvest)
    return result[]
end

# ---------------------------------------------------------------------------
# Truthiness
# ---------------------------------------------------------------------------

function _truthy(value)::Bool
    value === nothing && return false
    value === false && return false
    value == 0 && return false
    value == "" && return false
    if value isa Tuple && isempty(value)
        return false
    end
    return true
end

# ---------------------------------------------------------------------------
# Top-level entry point
# ---------------------------------------------------------------------------

"""
Run an eric-lang program.

Returns the final value and any collected IO actions,
because side effects are for people without continuations.
"""
function run_program(ast::ModuleNode)
    interp = CPSInterpreter()

    result = eval_node(interp, ast, HaltContinuation())

    return (
        result = result,
        stack = copy(interp.stack),
        io_actions = copy(interp.io_actions),
        variables = copy(interp.variables),
    )
end

"""
Run a program with a pre-configured interpreter (for REPL use).
"""
function run_program(interp::CPSInterpreter, ast::ASTNode)
    return eval_node(interp, ast, HaltContinuation())
end
