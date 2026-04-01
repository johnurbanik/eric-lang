# CPS Tree-Walking Interpreter for eric-lang
#
# "A stack-based language evaluated via continuation-passing style,
#  with Prolog-style unification for dispatch.  As one does."
#
# Depends on: continuations.jl, ast.jl, knowledge_base.jl, tabled_resolution.jl,
#             unification.jl, resolution.jl

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

const CPS_BUILTINS = Dict{String, Function}()

function register_cps_builtin!(name::String, f::Function)
    CPS_BUILTINS[name] = f
end

# Arithmetic
register_cps_builtin!("+",   (interp, args) -> args[1] + args[2])
register_cps_builtin!("-",   (interp, args) -> args[1] - args[2])
register_cps_builtin!("*",   (interp, args) -> args[1] * args[2])
register_cps_builtin!("/",   (interp, args) -> args[1] / args[2])
register_cps_builtin!("mod", (interp, args) -> mod(args[1], args[2]))

# Comparison
register_cps_builtin!("==",  (interp, args) -> args[1] == args[2])
register_cps_builtin!("!=",  (interp, args) -> args[1] != args[2])
register_cps_builtin!("<",   (interp, args) -> args[1] <  args[2])
register_cps_builtin!(">",   (interp, args) -> args[1] >  args[2])
register_cps_builtin!("<=",  (interp, args) -> args[1] <= args[2])
register_cps_builtin!(">=",  (interp, args) -> args[1] >= args[2])

# Stack operations
register_cps_builtin!("dup",  (interp, args) -> begin
    v = stack_peek(interp)
    stack_push!(interp, v)
    v
end)
register_cps_builtin!("drop", (interp, args) -> stack_pop!(interp))
register_cps_builtin!("swap", (interp, args) -> begin
    a = stack_pop!(interp)
    b = stack_pop!(interp)
    stack_push!(interp, a)
    stack_push!(interp, b)
    b
end)

# Collection operations
register_cps_builtin!("length", (interp, args) -> length(args[1]))
register_cps_builtin!("head",   (interp, args) -> first(args[1]))
register_cps_builtin!("tail",   (interp, args) -> args[1][2:end])
register_cps_builtin!("cons",   (interp, args) -> vcat([args[1]], args[2]))
register_cps_builtin!("append", (interp, args) -> vcat(args[1], args[2]))
register_cps_builtin!("range",  (interp, args) -> collect(args[1]:args[2]))

# IO (collected as actions AND printed to stdout -- pragmatism wins)
register_cps_builtin!("print", (interp, args) -> begin
    val = if isempty(args)
        isempty(interp.stack) ? nothing : stack_peek(interp)
    else
        args[1]
    end
    println(val)
    push!(interp.io_actions, (:print, val))
    val
end)
register_cps_builtin!("println", (interp, args) -> begin
    val = if isempty(args)
        isempty(interp.stack) ? nothing : stack_pop!(interp)
    else
        args[1]
    end
    println(val)
    push!(interp.io_actions, (:println, val))
    val
end)

# Type checks
register_cps_builtin!("is_number",  (interp, args) -> args[1] isa Number)
register_cps_builtin!("is_string",  (interp, args) -> args[1] isa AbstractString)
register_cps_builtin!("is_list",    (interp, args) -> args[1] isa AbstractVector)
register_cps_builtin!("is_tuple",   (interp, args) -> args[1] isa Tuple)
register_cps_builtin!("to_string",  (interp, args) -> string(args[1]))
register_cps_builtin!("to_number",  (interp, args) -> parse(Float64, string(args[1])))

# eric-lang core builtins
register_cps_builtin!("_", (interp, args) -> begin
    isempty(interp.stack) ? nothing : stack_peek(interp)
end)
register_cps_builtin!("_1", (interp, args) -> begin
    isempty(interp.stack) ? nothing : stack_peek(interp)
end)
register_cps_builtin!("_2", (interp, args) -> begin
    length(interp.stack) >= 2 ? interp.stack[end-1] : nothing
end)
register_cps_builtin!("stdin", (interp, args) -> read(stdin, String))
register_cps_builtin!("split", (interp, args) -> begin
    if length(args) == 1
        data = stack_pop!(interp)
        delim = args[1]
    elseif length(args) >= 2
        data = args[1]
        delim = args[2]
    else
        error("split requires at least 1 argument")
    end
    Tuple(split(string(data), string(delim)))
end)
register_cps_builtin!("int", (interp, args) -> begin
    val = isempty(args) ? stack_pop!(interp) : args[1]
    result = parse(Int, string(val))
    stack_push!(interp, result)
    result
end)
register_cps_builtin!("sum", (interp, args) -> begin
    coll = isempty(args) ? stack_pop!(interp) : args[1]
    result = sum(coll)
    stack_push!(interp, result)
    result
end)
register_cps_builtin!("get", (interp, args) -> begin
    if length(args) == 2
        data, idx = args[1], args[2]
    elseif length(args) == 1
        data = stack_pop!(interp)
        idx = args[1]
    else
        error("get requires 1-2 arguments")
    end
    idx < 0 ? data[end + idx + 1] : data[idx + 1]  # 0-indexed
end)
register_cps_builtin!("set", (interp, args) -> begin
    if length(args) == 3
        data, idx, item = args[1], args[2], args[3]
    else
        data = stack_pop!(interp)
        idx, item = args[1], args[2]
    end
    result = collect(data)
    result[idx < 0 ? end + idx + 1 : idx + 1] = item
    Tuple(result)
end)

# Python interop — the triumphant return of pyeval
# "We removed eval() as the headline fix. Then we added it back,
#  but through PyCall.jl, adding one more language boundary."
register_cps_builtin!("pyeval", (interp, args) -> begin
    code = if isempty(args)
        string(stack_pop!(interp))
    else
        string(args[1])
    end
    pyeval_bridge(code, interp.variables)
end)

# ---------------------------------------------------------------------------
# Helper: convert AST arg node to a Term for Clause construction
# ---------------------------------------------------------------------------

"""Convert an AST node (from an assignment's left-hand side args) to a Term."""
function ast_arg_to_term(node::ASTNode)::Term
    if node isa LiteralNode
        return Atom(node.value)
    elseif node isa IdentifierNode
        name = node.name
        if startswith(name, "_")
            # Wildcard variable -- use unique name so each wildcard is independent
            return Variable(name)
        else
            return Variable(name)
        end
    else
        # Fallback: treat as a variable with a string representation
        return Variable(string(node))
    end
end

"""Extract runtime value from a Term after unification."""
function term_to_value(t::Term)
    if t isa Atom
        return t.value
    elseif t isa Variable
        return nothing  # unbound variable
    elseif t isa Compound
        return t  # leave compounds as-is
    end
    return nothing
end

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
    if isempty(node.stmts)
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

    return eval_stmts(node.stmts, 1, k)
end

# -- StatementNode: eval expr, handle `as` binding, handle indented blocks -

function eval_node(interp::CPSInterpreter, node::StatementNode, k::AbstractContinuation)
    # Determine the block for special forms -- the block lives on the StatementNode,
    # not on the ExpressionNode
    stmt_block = node.block

    # After evaluating the expression:
    after_expr = Continuation(
        function (value)
            # Handle `as` binding (node.names is a Vector{IdentifierNode})
            if !isempty(node.names)
                if length(node.names) == 1
                    # Single name: bind the whole value
                    interp.variables[node.names[1].name] = value
                else
                    # Multiple names: destructure a tuple/collection
                    items = if value isa Tuple
                        collect(value)
                    elseif value isa AbstractVector
                        value
                    else
                        error("Cannot destructure non-collection with multiple `as` bindings, got: $(typeof(value))")
                    end
                    for (i, id_node) in enumerate(node.names)
                        if i <= length(items)
                            interp.variables[id_node.name] = items[i]
                        else
                            interp.variables[id_node.name] = nothing
                        end
                    end
                end
            end

            # Handle indented block (implicit map if not a special form)
            if stmt_block !== nothing && !_is_special_form_expr(node.expr)
                return eval_implicit_map(interp, value, stmt_block, k)
            end

            return continue_with(k, value)
        end,
        "after statement expr"
    )

    # For special forms, we need to pass the statement's block down
    if node.expr isa ExpressionNode && node.expr.identifier.name in SPECIAL_FORMS && stmt_block !== nothing
        return eval_node_with_block(interp, node.expr, stmt_block, after_expr)
    end

    # Also handle bare IdentifierNode special forms (e.g., `filter` with no args)
    if node.expr isa IdentifierNode && node.expr.name in SPECIAL_FORMS && stmt_block !== nothing
        return eval_special_form(interp, node.expr.name, Any[], stmt_block, after_expr)
    end

    return eval_node(interp, node.expr, after_expr)
end

"""Check if an expression node is a special form."""
function _is_special_form_expr(expr::ASTNode)::Bool
    if expr isa ExpressionNode
        return expr.identifier.name in SPECIAL_FORMS
    elseif expr isa IdentifierNode
        return expr.name in SPECIAL_FORMS
    end
    return false
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

    # 2. Check if it's a known builtin — execute it as a zero-arg call
    #    The builtin itself handles stack operations (pop/push).
    if haskey(CPS_BUILTINS, name)
        result = CPS_BUILTINS[name](interp, Any[])
        # Don't push again — the builtin already manages the stack
        return continue_with(k, result)
    end

    # 3. Check knowledge base (zero-arg function)
    clauses = find_clauses(interp.knowledge_base, name, 0)
    if !isempty(clauses)
        return try_clauses(interp, clauses, Any[], k)
    end

    error("Unbound identifier: $name")
end

# -- ExpressionNode: the big one -------------------------------------------

function eval_node(interp::CPSInterpreter, node::ExpressionNode, k::AbstractContinuation)
    head = node.identifier.name

    # Evaluate all arguments first (left to right, CPS-style)
    eval_args_cps(interp, node.args, Any[]) do evaluated_args
        # Now dispatch based on head
        # Note: special forms with blocks are handled at the StatementNode level
        # via eval_node_with_block. If we get here for a special form, it has no block.
        if head in SPECIAL_FORMS
            return eval_special_form(interp, head, evaluated_args, nothing, k)
        end

        # Clean up stack from arg evaluation side-effects
        # (each arg was pushed by eval_node during evaluation)
        for _ in 1:length(evaluated_args)
            if !isempty(interp.stack)
                stack_pop!(interp)
            end
        end

        # Check simple variable bindings (might be a lambda / reified continuation)
        if haskey(interp.variables, head)
            value = interp.variables[head]
            if value isa ReifiedContinuation
                # Invoking a captured continuation
                arg = isempty(evaluated_args) ? stack_pop!(interp) : evaluated_args[1]
                return continue_with(value, arg)
            elseif value isa Function
                # Check if this is a stdlib function that needs implicit first arg
                call_args = evaluated_args
                if haskey(STDLIB_ARITIES, head)
                    min_arity = minimum(STDLIB_ARITIES[head])
                    if length(evaluated_args) < min_arity && !isempty(interp.stack)
                        implicit_first = stack_pop!(interp)
                        call_args = vcat([implicit_first], evaluated_args)
                    end
                end
                result = value(call_args...)
                stack_push!(interp, result)
                return continue_with(k, result)
            end
        end

        # Try knowledge base (Prolog-style unification dispatch)
        clauses = find_clauses(interp.knowledge_base, head, length(evaluated_args))
        if !isempty(clauses)
            return try_clauses_with_implicit_first(interp, clauses, head, evaluated_args, k)
        end

        # Also try with implicit first arg (one more param than provided args)
        clauses_plus = find_clauses(interp.knowledge_base, head, length(evaluated_args) + 1)
        if !isempty(clauses_plus)
            return try_clauses_with_implicit_first(interp, clauses_plus, head, evaluated_args, k)
        end

        # Try built-in functions
        if haskey(CPS_BUILTINS, head)
            args_for_builtin = if isempty(evaluated_args) && !isempty(interp.stack)
                # Implicit: pop from stack
                [stack_pop!(interp)]
            else
                evaluated_args
            end
            result = CPS_BUILTINS[head](interp, args_for_builtin)
            stack_push!(interp, result)
            return continue_with(k, result)
        end

        throw(NoMatchingClauseError(head, evaluated_args, Clause[], node.location))
    end
end

"""
Evaluate an ExpressionNode that has an indented block (from the enclosing StatementNode).
Special forms need access to this block.
"""
function eval_node_with_block(interp::CPSInterpreter, node::ExpressionNode,
                               block::ASTNode, k::AbstractContinuation)
    head = node.identifier.name

    # Evaluate all arguments first
    eval_args_cps(interp, node.args, Any[]) do evaluated_args
        if head in SPECIAL_FORMS
            # Each arg evaluation pushes a value onto the stack via eval_node.
            # Pop those values so the stack is in the same state it was before
            # arg evaluation -- special forms like reduce expect the collection
            # (pushed by a prior statement) to be on top of the stack.
            for _ in 1:length(evaluated_args)
                stack_pop!(interp)
            end
            return eval_special_form(interp, head, evaluated_args, block, k)
        end

        # Non-special-form with a block -- evaluate normally, block handled by StatementNode
        # Check variable bindings
        if haskey(interp.variables, head)
            value = interp.variables[head]
            if value isa ReifiedContinuation
                arg = isempty(evaluated_args) ? stack_pop!(interp) : evaluated_args[1]
                return continue_with(value, arg)
            elseif value isa Function
                # Check if this is a stdlib function that needs implicit first arg
                call_args = evaluated_args
                if haskey(STDLIB_ARITIES, head)
                    min_arity = minimum(STDLIB_ARITIES[head])
                    if length(evaluated_args) < min_arity && !isempty(interp.stack)
                        implicit_first = stack_pop!(interp)
                        call_args = vcat([implicit_first], evaluated_args)
                    end
                end
                result = value(call_args...)
                stack_push!(interp, result)
                return continue_with(k, result)
            end
        end

        # Try knowledge base
        clauses = find_clauses(interp.knowledge_base, head, length(evaluated_args))
        if !isempty(clauses)
            return try_clauses_with_implicit_first(interp, clauses, head, evaluated_args, k)
        end
        clauses_plus = find_clauses(interp.knowledge_base, head, length(evaluated_args) + 1)
        if !isempty(clauses_plus)
            return try_clauses_with_implicit_first(interp, clauses_plus, head, evaluated_args, k)
        end

        # Try builtins
        if haskey(CPS_BUILTINS, head)
            args_for_builtin = if isempty(evaluated_args) && !isempty(interp.stack)
                [stack_pop!(interp)]
            else
                evaluated_args
            end
            result = CPS_BUILTINS[head](interp, args_for_builtin)
            stack_push!(interp, result)
            return continue_with(k, result)
        end

        throw(NoMatchingClauseError(head, evaluated_args, Clause[], node.location))
    end
end

# -- CollectionNode: evaluate items, handle spread -------------------------

function eval_node(interp::CPSInterpreter, node::CollectionNode, k::AbstractContinuation)
    eval_collection_items(interp, node.items, 1, Any[]) do collected
        result = Tuple(collected)
        stack_push!(interp, result)
        return continue_with(k, result)
    end
end

function eval_collection_items(callback::Function, interp::CPSInterpreter,
                                items::Vector{CollectionItemNode},
                                idx::Int, acc::Vector{Any})
    if idx > length(items)
        return callback(acc)
    end

    ci = items[idx]

    item_k = Continuation(
        function (value)
            if ci.expand
                # Spread: splice the collection into the result
                if value isa AbstractVector || value isa Tuple
                    append!(acc, collect(value))
                else
                    error("Cannot spread non-collection: $value")
                end
            else
                push!(acc, value)
            end
            return eval_collection_items(callback, interp, items, idx + 1, acc)
        end,
        "collection item $idx"
    )

    return eval_node(interp, ci.item, item_k)
end

# -- AssignmentNode: define a function in the knowledge base ---------------

function eval_node(interp::CPSInterpreter, node::AssignmentNode, k::AbstractContinuation)
    # Extract functor name and args from the left-hand side
    if node.left isa ExpressionNode
        functor = node.left.identifier.name
        head_args = [ast_arg_to_term(a) for a in node.left.args]
    elseif node.left isa IdentifierNode
        functor = node.left.name
        head_args = Term[]
    else
        error("AssignmentNode left side must be ExpressionNode or IdentifierNode, got: $(typeof(node.left))")
    end

    clause = Clause(functor, head_args, node.right)
    assert_clause!(interp.knowledge_base, clause)
    return continue_with(k, Symbol(functor))
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
        # Push (accumulator, element) as a tuple onto sub-interpreter stack
        # so that `as acc, d` can destructure it
        stack_push!(sub, (acc, items[idx]))

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

    # Fall back to sequential map when only 1 Julia thread is available,
    # which avoids thread-safety issues with shared interpreter state.
    if Threads.nthreads() <= 1
        results = Any[]

        function seq_step(idx)
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
                    return seq_step(idx + 1)
                end,
                "parallel(sequential) step $idx"
            )

            return eval_node(sub, block, step_k)
        end

        return seq_step(1)
    end

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
    # Build a key from the current stack top (the input)
    input = isempty(interp.stack) ? nothing : stack_peek(interp)
    cache_args = Any[input]

    # Check cache using table_lookup (returns Union{Some, Nothing})
    cached = table_lookup(interp.table_store, table_name, cache_args)
    if cached !== nothing
        value = something(cached)
        stack_push!(interp, value)
        return continue_with(k, value)
    end

    # Cache miss: evaluate block, then cache
    cache_k = Continuation(
        function (_)
            result = stack_pop!(interp)
            table_store!(interp.table_store, table_name, cache_args, result)
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
# Clause resolution (Prolog-style dispatch via unification)
# ---------------------------------------------------------------------------

"""
Try to match args against clauses using real unification.
First matching clause wins.
"""
function try_clauses(interp::CPSInterpreter, clauses::Vector{Clause},
                     args::Vector{Any}, k::AbstractContinuation)
    # Convert runtime args to Terms for unification
    arg_terms = [value_to_term(a) for a in args]

    for clause in clauses
        # Freshen variables to avoid capture
        fresh = freshen_variables(clause)

        # Unify each arg term with the corresponding head_arg
        if length(fresh.head_args) != length(arg_terms)
            continue
        end

        subst = Substitution()
        match_failed = false
        for (pattern, arg_term) in zip(fresh.head_args, arg_terms)
            result = unify(pattern, arg_term, subst)
            if result === nothing
                match_failed = true
                break
            end
            subst = result
        end
        match_failed && continue

        # Extract bindings from substitution: map variable names to runtime values
        bindings = Dict{String, Any}()
        for (var_name, term) in subst
            resolved = apply_subst(subst, term)
            bindings[var_name] = term_to_value(resolved)
        end

        # Also extract the original (un-freshened) variable names for user code
        # We need to map fresh variable names back to original names
        user_bindings = extract_user_bindings(clause, fresh, subst)

        # Match! Evaluate body with bindings
        body_interp = child_interpreter(interp)
        merge!(body_interp.variables, user_bindings)

        body_k = Continuation(
            function (_)
                result = isempty(body_interp.stack) ? nothing : stack_pop!(body_interp)
                stack_push!(interp, result)
                return continue_with(k, result)
            end,
            "clause body for $(clause.head_functor)"
        )

        return eval_node(body_interp, clause.body, body_k)
    end

    throw(NoMatchingClauseError(
        isempty(clauses) ? "?" : clauses[1].head_functor,
        args,
        clauses,
        SourceLocation()
    ))
end

"""
Extract user-facing variable bindings by mapping original clause variable names
to the values they were unified with.
"""
function extract_user_bindings(original::Clause, freshened::Clause, subst::Substitution)::Dict{String, Any}
    bindings = Dict{String, Any}()
    for (orig_term, fresh_term) in zip(original.head_args, freshened.head_args)
        if orig_term isa Variable && fresh_term isa Variable
            # Look up the freshened variable name in the substitution
            resolved = apply_subst(subst, fresh_term)
            bindings[orig_term.name] = term_to_value(resolved)
        end
    end
    return bindings
end

"""
Try clauses with the implicit first argument rule:
if a function has N params but we have N-1 args, pop the stack top as arg 1.
"""
function try_clauses_with_implicit_first(interp::CPSInterpreter,
                                          clauses::Vector{Clause},
                                          functor::String,
                                          args::Vector{Any},
                                          k::AbstractContinuation)
    # First try direct match (clauses with same arity as args)
    direct_clauses = filter(c -> length(c.head_args) == length(args), clauses)
    if !isempty(direct_clauses)
        # Try unification on direct match candidates
        try
            return try_clauses(interp, direct_clauses, args, k)
        catch e
            e isa NoMatchingClauseError || rethrow(e)
            # Fall through to implicit first arg
        end
    end

    # Try implicit first argument (clauses with arity = length(args) + 1)
    implicit_clauses = filter(c -> length(c.head_args) == length(args) + 1, clauses)
    if !isempty(implicit_clauses) && !isempty(interp.stack)
        implicit_first = stack_pop!(interp)
        full_args = vcat([implicit_first], args)
        try
            return try_clauses(interp, implicit_clauses, full_args, k)
        catch e
            if e isa NoMatchingClauseError
                # Didn't match, put it back
                stack_push!(interp, implicit_first)
            else
                rethrow(e)
            end
        end
    end

    # Fall through to error with all clauses
    throw(NoMatchingClauseError(functor, args, clauses, SourceLocation()))
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

"""
Alias for run_program, used by the CLI and macro system.
"""
eval_program(interp::CPSInterpreter, ast::ASTNode) = run_program(interp, ast)
