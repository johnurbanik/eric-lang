using EricLang: TableStore, table_lookup, table_store!, table_stats, make_table_key

@testset "Tabling (Memoization)" begin
    @testset "table lookup miss returns nothing" begin
        ts = TableStore(10)
        result = table_lookup(ts, "fib", Any[10])
        @test result === nothing
    end

    @testset "store then lookup returns the value" begin
        ts = TableStore(10)
        table_store!(ts, "fib", Any[10], 55)
        result = table_lookup(ts, "fib", Any[10])
        @test result !== nothing
        @test something(result) == 55
    end

    @testset "different keys are independent" begin
        ts = TableStore(10)
        table_store!(ts, "fib", Any[10], 55)
        table_store!(ts, "fib", Any[5], 5)
        r1 = table_lookup(ts, "fib", Any[10])
        r2 = table_lookup(ts, "fib", Any[5])
        @test something(r1) == 55
        @test something(r2) == 5
    end

    @testset "LRU eviction works" begin
        ts = TableStore(3)
        table_store!(ts, "f", Any[1], 10)
        table_store!(ts, "f", Any[2], 20)
        table_store!(ts, "f", Any[3], 30)
        # This should evict the oldest entry (key 1)
        table_store!(ts, "f", Any[4], 40)
        @test table_lookup(ts, "f", Any[1]) === nothing  # evicted
        r4 = table_lookup(ts, "f", Any[4])
        @test r4 !== nothing
        @test something(r4) == 40
    end

    @testset "stats tracking (hits and misses)" begin
        ts = TableStore(10)
        table_store!(ts, "f", Any[1], 10)

        # Miss
        table_lookup(ts, "f", Any[999])
        # Hit
        table_lookup(ts, "f", Any[1])

        stats = table_stats(ts)
        @test stats.hits >= 1
        @test stats.misses >= 1
    end
end
