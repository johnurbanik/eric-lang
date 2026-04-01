@testset "Autodiff (Numeric Gradient)" begin
    @testset "gradient of x^2 at x=3 is approximately 6.0" begin
        f = x -> x^2
        result = numeric_gradient(f, 3.0)
        @test result.value isa Number
        @test isapprox(result.value, 6.0; atol=1e-5)
    end

    @testset "gradient of 2x+1 at x=0 is approximately 2.0" begin
        f = x -> 2x + 1
        result = numeric_gradient(f, 0.0)
        @test isapprox(result.value, 2.0; atol=1e-5)
    end

    @testset "gradient of constant function is approximately 0" begin
        f = x -> 7.0
        result = numeric_gradient(f, 5.0)
        @test isapprox(result.value, 0.0; atol=1e-5)
    end

    @testset "gradient of x^3 at x=2 is approximately 12.0" begin
        f = x -> x^3
        result = numeric_gradient(f, 2.0)
        @test isapprox(result.value, 12.0; atol=1e-4)
    end

    @testset "GradientResult formats nicely" begin
        result = numeric_gradient(x -> x^2, 3.0)
        s = format_gradient(result)
        @test s isa String
        @test length(s) > 0
        # Should contain the numeric value somewhere
        @test occursin("6", s) || occursin("gradient", lowercase(s))
    end
end
