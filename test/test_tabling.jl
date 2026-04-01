@testset "Tabling (Memoization)" begin
    @testset "table lookup miss returns nothing" begin
        table = MemoTable(max_size=10)
        result = table_lookup(table, "fib", (10,))
        @test result === nothing
    end

    @testset "store then lookup returns the value" begin
        table = MemoTable(max_size=10)
        table_store!(table, "fib", (10,), 55)
        result = table_lookup(table, "fib", (10,))
        @test result == 55
    end

    @testset "different keys are independent" begin
        table = MemoTable(max_size=10)
        table_store!(table, "fib", (10,), 55)
        table_store!(table, "fib", (5,), 5)
        @test table_lookup(table, "fib", (10,)) == 55
        @test table_lookup(table, "fib", (5,)) == 5
    end

    @testset "LRU eviction works" begin
        table = MemoTable(max_size=3)
        table_store!(table, "f", (1,), 10)
        table_store!(table, "f", (2,), 20)
        table_store!(table, "f", (3,), 30)
        # This should evict the oldest entry (key 1)
        table_store!(table, "f", (4,), 40)
        @test table_lookup(table, "f", (1,)) === nothing  # evicted
        @test table_lookup(table, "f", (4,)) == 40        # present
    end

    @testset "stats tracking (hits and misses)" begin
        table = MemoTable(max_size=10)
        table_store!(table, "f", (1,), 10)

        # Miss
        table_lookup(table, "f", (999,))
        # Hit
        table_lookup(table, "f", (1,))

        stats = table_stats(table)
        @test stats.hits >= 1
        @test stats.misses >= 1
    end
end
