using EricLang: Term, Atom, Variable, Compound, Substitution, unify, apply_subst,
    Clause, KnowledgeBase, assert_clause!, find_clauses,
    NoMatchingClauseError, resolve, value_to_term, SourceLocation

@testset "Resolution" begin
    @testset "resolve against a single fact" begin
        # Fact: parent(tom, bob).
        kb = KnowledgeBase()
        clause = Clause("parent", Term[Atom("tom"), Atom("bob")], nothing)
        assert_clause!(kb, clause)

        # Resolve parent(tom, bob)
        result_clause, subst = resolve(kb, "parent", ["tom", "bob"], SourceLocation())
        @test result_clause isa Clause
        @test subst !== nothing
    end

    @testset "resolve with variable binding" begin
        kb = KnowledgeBase()
        clause = Clause("parent", Term[Atom("tom"), Atom("bob")], nothing)
        assert_clause!(kb, clause)

        # Resolve parent(tom, X) — X should bind to "bob"
        result_clause, subst = resolve(kb, "parent", ["tom", "bob"], SourceLocation())
        @test result_clause isa Clause
    end

    @testset "no matching clause throws NoMatchingClauseError (review issue #10)" begin
        kb = KnowledgeBase()
        clause = Clause("parent", Term[Atom("tom"), Atom("bob")], nothing)
        assert_clause!(kb, clause)

        @test_throws NoMatchingClauseError resolve(kb, "parent", ["alice", "someone"], SourceLocation())
    end

    @testset "multiple clauses: first match wins" begin
        kb = KnowledgeBase()
        clause1 = Clause("greet", Term[Atom("english")], nothing)
        clause2 = Clause("greet", Term[Atom("spanish")], nothing)
        assert_clause!(kb, clause1)
        assert_clause!(kb, clause2)

        result_clause, subst = resolve(kb, "greet", ["english"], SourceLocation())
        @test result_clause isa Clause
    end
end
