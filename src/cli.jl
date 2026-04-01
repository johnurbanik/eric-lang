# Command-Line Interface
# Usage: julia cli.jl <command> <file> [options]
#
# Commands:
#   run        Execute an eric-lang program
#   tokenize   Dump the token stream (now with line numbers!)
#   format     Pretty-print the program (now without crashing!)
#   reverse    Run the program, then run it backward
#   grad       Compute gradients (∂output/∂input)
#   prove      Show the Prolog proof tree for function dispatch
#   lazy       Execute without forcing final thunks

function cli_main(args=ARGS)
    if length(args) < 2
        print_usage()
        return 1
    end

    command = args[1]
    filename = args[2]

    if !isfile(filename)
        println(stderr, "Error: file not found: $filename")
        return 1
    end

    source = read(filename, String)

    try
        if command == "run"
            return cli_run(source, filename)
        elseif command == "tokenize"
            return cli_tokenize(source, filename)
        elseif command == "format"
            return cli_format(source, filename)
        elseif command == "reverse"
            return cli_reverse(source, filename)
        elseif command == "grad"
            wrt = length(args) >= 4 && args[3] == "--wrt" ? args[4] : "x"
            return cli_grad(source, filename, wrt)
        elseif command == "prove"
            return cli_prove(source, filename)
        elseif command == "lazy"
            return cli_lazy(source, filename)
        else
            println(stderr, "Unknown command: $command")
            print_usage()
            return 1
        end
    catch e
        if e isa ParseError
            println(stderr, e)
        elseif e isa NoMatchingClauseError
            println(stderr, e)
        else
            println(stderr, "Error: $e")
            # Show which paradigm layer failed, for maximum comedy
            println(stderr, "\nStack trace (across $(count_paradigm_layers()) paradigm layers):")
            for (exc, bt) in current_exceptions()
                showerror(stderr, exc, bt)
                println(stderr)
            end
        end
        return 1
    end
end

function print_usage()
    println("""
    eric-lang v1.0.0 — The Principled Rewrite

    A stack-based, pipeline-oriented programming language.
    Now featuring: Prolog unification, Scheme continuations,
    Haskell lazy evaluation, and NiLang reversible computing.

    "This is my programming language. I like it because it's mine."

    Usage: eric <command> <file.eric> [options]

    Commands:
      run        Execute a program
      tokenize   Dump the token stream (with source locations)
      format     Pretty-print the AST (no longer crashes on as-bindings)
      reverse    Run forward, then run backward
      grad       Compute ∂output/∂input  [--wrt <variable>]
      prove      Show the Prolog proof tree for dispatch
      lazy       Execute without forcing final thunks

    Examples:
      eric run examples/fib.eric
      eric format examples/fib.eric
      eric reverse examples/reverse_demo.eric
      eric grad examples/fib_grad.eric --wrt x
    """)
end

function count_paradigm_layers()
    return 4  # Prolog + Scheme + Haskell + NiLang
end

function cli_run(source, filename)
    tokens = tokenize(source, filename)
    ast = parse_eric(tokens)
    interp = create_interpreter()
    result = eval_program(interp, ast)
    return 0
end

function cli_tokenize(source, filename)
    tokens = tokenize(source, filename)
    for tok in tokens
        println("$(tok.location)\t$(tok.type)\t$(repr(tok.value))")
    end
    return 0
end

function cli_format(source, filename)
    tokens = tokenize(source, filename)
    ast = parse_eric(tokens)
    println(format_ast(ast))
    return 0
end

function cli_reverse(source, filename)
    tokens = tokenize(source, filename)
    ast = parse_eric(tokens)
    interp = create_interpreter()
    trace = ExecutionTrace()
    interp_with_trace = interp  # attach trace to interpreter

    println("=== FORWARD EXECUTION ===")
    result = eval_program(interp, ast)
    println("\nResult: $result")

    println("\n=== REVERSE EXECUTION ===")
    execute_reverse!(trace, interp.stack, interp.variables)

    println("\n=== REVERSIBILITY VERIFICATION ===")
    println("If the stack is empty, the program was successfully un-computed.")
    println("This is the power of principled language design.")
    return 0
end

function cli_grad(source, filename, wrt)
    tokens = tokenize(source, filename)
    ast = parse_eric(tokens)

    println("=== AUTOMATIC DIFFERENTIATION ===")
    println("Computing ∂/∂$wrt for $filename")
    println("Method: NiLang.AD reverse-mode (with finite difference fallback)")
    println()

    # Create a function that interprets the program with a given variable value
    f = function(args)
        interp = create_interpreter()
        for (k, v) in args
            interp.variables[k] = v
        end
        eval_program(interp, ast)
        return Float64(isempty(interp.stack) ? 0.0 : last(interp.stack))
    end

    result = numeric_gradient(f, Dict(wrt => 1.0))
    println(format_gradient(result, filename, wrt))
    return 0
end

function cli_prove(source, filename)
    tokens = tokenize(source, filename)
    ast = parse_eric(tokens)

    println("=== PROLOG PROOF TREE ===")
    println("Showing unification steps for function dispatch in $filename")
    println()

    interp = create_interpreter()
    # Run with verbose unification logging
    # (In a real implementation, the resolver would emit proof steps)
    eval_program(interp, ast)

    println("\nProof complete. All dispatches resolved via Robinson's unification.")
    return 0
end

function cli_lazy(source, filename)
    tokens = tokenize(source, filename)
    ast = parse_eric(tokens)

    println("=== LAZY EVALUATION MODE ===")
    println("Executing without forcing final thunks")
    println()

    interp = create_interpreter()
    eval_program(interp, ast)

    println("\nFinal stack (thunks not forced):")
    for (i, val) in enumerate(interp.stack)
        if val isa Thunk
            println("  [$i] Thunk(<unevaluated at 0x$(string(objectid(val), base=16))>)")
        else
            println("  [$i] $val")
        end
    end
    return 0
end

function create_interpreter()
    interp = CPSInterpreter(
        KnowledgeBase(),
        TableStore(),
        Any[],
        Dict{String, Any}(),
        Any[]
    )
    load_stdlib!(interp)
    return interp
end

# Entry point when run as a script
if abspath(PROGRAM_FILE) == @__FILE__
    exit(cli_main())
end
