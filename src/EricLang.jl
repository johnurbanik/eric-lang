module EricLang

# Dependencies
using LRUCache
using ProgressMeter
# NiLang imports are deferred to avoid startup cost when not needed

# --- Frontend ---
include("tokens.jl")
include("tokenizer.jl")
include("ast.jl")
include("parser.jl")

# --- Prolog Layer ---
include("unification.jl")
include("knowledge_base.jl")
include("resolution.jl")
include("tabled_resolution.jl")

# --- Python Bridge (conditional on PyCall) ---
include("python_bridge.jl")

# --- Scheme Layer ---
include("continuations.jl")
include("cps_interpreter.jl")

# --- Haskell Layer ---
include("thunks.jl")
include("io_monad.jl")
include("lazy_stdlib.jl")

# --- NiLang Layer ---
include("reversible.jl")
include("autodiff.jl")

# --- Infrastructure ---
include("builtins.jl")
include("formatter.jl")
include("macros.jl")
include("cli.jl")

# Public API
export tokenize, parse_eric, format_ast
export CPSInterpreter, eval_program, run_program
export KnowledgeBase, TableStore
export Thunk, force, lazy, eager_thunk
export IOAction, io_return, io_bind, io_print, run_io!
export ExecutionTrace, execute_reverse!
export eric_gradient, numeric_gradient
export cli_main, create_interpreter, load_stdlib!
export @eric_str
export pyeval_bridge

# Convenience function for running a file
function run(filename::String)
    source = read(filename, String)
    cli_run(source, filename)
end

# Convenience function for evaluating a string
function eval_string(source::String)
    tokens = tokenize(source)
    ast = parse_eric(tokens)
    interp = create_interpreter()
    eval_program(interp, ast)
    return isempty(interp.stack) ? nothing : last(interp.stack)
end

end # module EricLang
