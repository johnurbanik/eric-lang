# Python Interoperability via PyCall.jl
#
# The call chain: eric-lang → Julia CPS → Prolog unification → PyCall → Python eval()
#
# We removed eval() as the headline fix. Then we added it back,
# but through an additional language boundary. Progress.

const _PYCALL_AVAILABLE = Ref(false)

# Stub that gets replaced if PyCall loads
function _pyeval_impl end

try
    @eval begin
        using PyCall

        function _pyeval_impl(code::String, bindings::Dict{String, Any})
            py_math = pyimport("math")
            py_builtins = pyimport("builtins")

            locals_dict = Dict{String, Any}("math" => py_math)
            for (name, value) in bindings
                value isa Function || (locals_dict[name] = value)
            end

            result = pyeval(code, py_builtins.__dict__, locals_dict)

            # Convert back to Julia
            if result isa PyObject
                for T in (Int, Float64, String, Bool)
                    try; return convert(T, result); catch; end
                end
                try; return Tuple(convert(Vector, result)); catch; end
            end
            return result
        end
    end
    _PYCALL_AVAILABLE[] = true
catch
    @warn "PyCall not available. pyeval will be disabled."
end

function pyeval_bridge(code::String, bindings::Dict{String, Any})
    _PYCALL_AVAILABLE[] || error("PyCall is not installed. pyeval requires: ] add PyCall")
    return _pyeval_impl(code, bindings)
end
