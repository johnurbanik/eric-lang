using EricLang: GradientResult, numeric_gradient, format_gradient

@testset "Autodiff (Numeric Gradient)" begin
    @testset "gradient of x^2 at x=3 is approximately 6.0" begin
        f = function(args::Dict{String, Float64})
            x = args["x"]
            return x^2
        end
        result = numeric_gradient(f, Dict("x" => 3.0))
        @test result.value isa Number
        @test isapprox(result.value, 9.0; atol=1e-5)  # f(3) = 9
        @test isapprox(result.gradient["x"], 6.0; atol=1e-5)
    end

    @testset "gradient of 2x+1 at x=0 is approximately 2.0" begin
        f = function(args::Dict{String, Float64})
            x = args["x"]
            return 2x + 1
        end
        result = numeric_gradient(f, Dict("x" => 0.0))
        @test isapprox(result.gradient["x"], 2.0; atol=1e-5)
    end

    @testset "gradient of constant function is approximately 0" begin
        f = function(args::Dict{String, Float64})
            return 7.0
        end
        result = numeric_gradient(f, Dict("x" => 5.0))
        @test isapprox(result.gradient["x"], 0.0; atol=1e-5)
    end

    @testset "gradient of x^3 at x=2 is approximately 12.0" begin
        f = function(args::Dict{String, Float64})
            x = args["x"]
            return x^3
        end
        result = numeric_gradient(f, Dict("x" => 2.0))
        @test isapprox(result.gradient["x"], 12.0; atol=1e-4)
    end

    @testset "GradientResult formats nicely" begin
        f = function(args::Dict{String, Float64})
            x = args["x"]
            return x^2
        end
        result = numeric_gradient(f, Dict("x" => 3.0))
        s = format_gradient(result, "test.eric", "x")
        @test s isa String
        @test length(s) > 0
        @test occursin("gradient", lowercase(s)) || occursin("Differentiation", s)
    end
end
