@testset "Python Interop (pyeval)" begin
    if EricLang._PYCALL_AVAILABLE[]
        @test pyeval_bridge("1 + 2", Dict{String, Any}()) == 3
        @test pyeval_bridge("a + b", Dict{String, Any}("a" => 10, "b" => 20)) == 30
        @test pyeval_bridge("math.sqrt(16)", Dict{String, Any}()) == 4.0
        @test pyeval_bridge("len('hello')", Dict{String, Any}()) == 5
        @test pyeval_bridge("x ** 2", Dict{String, Any}("x" => 7)) == 49
    else
        @warn "Skipping Python bridge tests: PyCall not available"
        @test_skip pyeval_bridge("1 + 2", Dict{String, Any}()) == 3
    end
end
