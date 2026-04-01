@testset "Unification" begin
    @testset "identical atoms unify" begin
        result = unify(Atom(1), Atom(1))
        @test result !== nothing
        @test result == Substitution()
    end

    @testset "different atoms fail to unify" begin
        result = unify(Atom(1), Atom(2))
        @test result === nothing
    end

    @testset "variable unifies with atom" begin
        result = unify(Variable("x"), Atom(5))
        @test result !== nothing
        @test result[Variable("x")] == Atom(5)
    end

    @testset "atom unifies with variable (symmetric)" begin
        result = unify(Atom(5), Variable("x"))
        @test result !== nothing
        @test result[Variable("x")] == Atom(5)
    end

    @testset "two compounds unify" begin
        lhs = Compound("f", [Atom(1)])
        rhs = Compound("f", [Variable("x")])
        result = unify(lhs, rhs)
        @test result !== nothing
        @test result[Variable("x")] == Atom(1)
    end

    @testset "compounds with different functors fail" begin
        lhs = Compound("f", [Atom(1)])
        rhs = Compound("g", [Atom(1)])
        result = unify(lhs, rhs)
        @test result === nothing
    end

    @testset "compounds with different arities fail" begin
        lhs = Compound("f", [Atom(1)])
        rhs = Compound("f", [Atom(1), Atom(2)])
        result = unify(lhs, rhs)
        @test result === nothing
    end

    @testset "occurs check prevents infinite types" begin
        # x cannot unify with f(x) — that would create a circular term
        result = unify(Variable("x"), Compound("f", [Variable("x")]))
        @test result === nothing
    end

    @testset "substitution application works transitively" begin
        # Unify x with y, then y with 5 — x should resolve to 5
        sub1 = unify(Variable("x"), Variable("y"))
        @test sub1 !== nothing
        sub2 = unify(apply(sub1, Variable("y")), Atom(5))
        @test sub2 !== nothing
        combined = compose(sub1, sub2)
        @test apply(combined, Variable("x")) == Atom(5)
    end
end
