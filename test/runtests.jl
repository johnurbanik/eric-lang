using Test
using EricLang

@testset "EricLang — The Principled Test Suite" begin
    include("test_tokenizer.jl")
    include("test_parser.jl")
    include("test_unification.jl")
    include("test_resolution.jl")
    include("test_tabling.jl")
    include("test_continuations.jl")
    include("test_thunks.jl")
    include("test_io_monad.jl")
    include("test_reversibility.jl")
    include("test_autodiff.jl")
    include("test_stdlib.jl")
    include("test_formatter.jl")
    include("test_integration.jl")
    include("test_python_bridge.jl")
end
