@testset "IO Monad" begin
    @testset "left identity: io_return(a) >>= f == f(a)" begin
        a = 42
        f = x -> IOAction(:pure, x * 2)
        lhs = run_io!(io_bind(io_return(a), f))
        rhs = run_io!(f(a))
        @test lhs == rhs
    end

    @testset "right identity: m >>= io_return == m" begin
        m = io_return(42)
        lhs = run_io!(io_bind(m, io_return))
        rhs = run_io!(m)
        @test lhs == rhs
    end

    @testset "associativity: (m >>= f) >>= g == m >>= (x -> f(x) >>= g)" begin
        m = io_return(5)
        f = x -> io_return(x + 1)
        g = x -> io_return(x * 2)

        lhs = run_io!(io_bind(io_bind(m, f), g))
        rhs = run_io!(io_bind(m, x -> io_bind(f(x), g)))
        @test lhs == rhs
    end

    @testset "IOPrint produces output" begin
        buf = IOBuffer()
        action = IOPrint("hello, world")
        run_io!(action; output=buf)
        @test String(take!(buf)) == "hello, world"
    end

    @testset "IOSequence runs actions in order" begin
        buf = IOBuffer()
        seq = IOSequence([
            IOPrint("first"),
            IOPrint(" "),
            IOPrint("second"),
        ])
        run_io!(seq; output=buf)
        @test String(take!(buf)) == "first second"
    end

    @testset "io_return wraps a pure value" begin
        action = io_return(99)
        @test run_io!(action) == 99
    end

    @testset "io_bind chains computations" begin
        action = io_bind(io_return(10), x -> io_return(x + 5))
        @test run_io!(action) == 15
    end
end
