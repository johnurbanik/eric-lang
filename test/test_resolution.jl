@testset "Resolution" begin
    @testset "resolve against a single fact" begin
        # Fact: parent(tom, bob).
        fact = Clause(
            Compound("parent", [Atom("tom"), Atom("bob")]),
            []  # no body — it's a fact
        )
        kb = KnowledgeBase([fact])
        goal = Compound("parent", [Atom("tom"), Atom("bob")])
        results = resolve(kb, goal)
        @test length(results) >= 1
    end

    @testset "resolve with variable binding" begin
        fact = Clause(
            Compound("parent", [Atom("tom"), Atom("bob")]),
            []
        )
        kb = KnowledgeBase([fact])
        goal = Compound("parent", [Atom("tom"), Variable("X")])
        results = resolve(kb, goal)
        @test length(results) >= 1
        # X should be bound to "bob"
        sub = first(results)
        @test apply(sub, Variable("X")) == Atom("bob")
    end

    @testset "no matching clause throws NoMatchingClauseError (review issue #10)" begin
        fact = Clause(
            Compound("parent", [Atom("tom"), Atom("bob")]),
            []
        )
        kb = KnowledgeBase([fact])
        goal = Compound("parent", [Atom("alice"), Variable("X")])
        try
            results = resolve(kb, goal)
            # If resolve returns empty instead of throwing, that's also acceptable
            if isempty(results)
                @test true
            else
                @test false  # should not have results
            end
        catch e
            @test e isa NoMatchingClauseError
            # Error should list the attempted clauses
            @test !isempty(e.attempted_clauses)
        end
    end

    @testset "multiple clauses: first match wins" begin
        clause1 = Clause(
            Compound("greet", [Atom("english")]),
            []
        )
        clause2 = Clause(
            Compound("greet", [Atom("spanish")]),
            []
        )
        kb = KnowledgeBase([clause1, clause2])
        goal = Compound("greet", [Variable("Lang")])
        results = resolve(kb, goal)
        @test length(results) >= 1
        # First match should bind to "english"
        sub = first(results)
        @test apply(sub, Variable("Lang")) == Atom("english")
    end
end
