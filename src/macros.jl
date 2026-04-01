# @eric_str String Macro
# "eric-lang embedded in Julia goes through: parsing → unification compilation →
#  CPS transform → thunk wrapping → NiLang reversible compilation → Julia JIT.
#  Six compilation stages for 1 + 2."

macro eric_str(source)
    quote
        let
            tokens = tokenize($(esc(source)))
            ast = parse_eric(tokens)
            interp = CPSInterpreter(
                KnowledgeBase(),
                TableStore(),
                Any[],
                Dict{String, Any}(),
                Any[]
            )
            # Load stdlib definitions
            load_stdlib!(interp)
            result = eval_program(interp, ast)
            result
        end
    end
end

# Load the eric-lang stdlib into an interpreter
function load_stdlib!(interp::CPSInterpreter)
    # Register all native stdlib functions
    for (name, func) in STDLIB_FUNCTIONS
        interp.variables[name] = func
    end
end
