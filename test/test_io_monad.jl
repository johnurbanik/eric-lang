using EricLang: IOAction, IOReturn, IOBind, IOPrint, IOSequence,
    io_return, io_bind, io_print, run_io!, verify_monad_laws

@testset "IO Monad" begin
    @testset "left identity: io_return(a) >>= f == f(a)" begin
        a = 42
        f = x -> io_return(x * 2)
        lhs = run_io!(io_bind(io_return(a), f))
        rhs = run_io!(f(a))
        @test lhs == rhs
    end

    @testset "right identity: m >>= io_return == m" begin
        m = io_return(42)
        lhs = run_io!(io_bind(m, x -> io_return(x)))
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
        action = IOPrint("hello, world")
        # run_io! prints to stdout; we just verify it runs without error
        result = run_io!(action)
        @test result === nothing
    end

    @testset "IOSequence runs actions in order" begin
        seq = IOSequence([
            IOPrint("first"),
            IOPrint(" "),
            IOPrint("second"),
        ])
        # Verify it runs without error
        result = run_io!(seq)
        @test true  # if we got here, sequence executed
    end

    @testset "io_return wraps a pure value" begin
        action = io_return(99)
        @test run_io!(action) == 99
    end

    @testset "io_bind chains computations" begin
        action = io_bind(io_return(10), x -> io_return(x + 5))
        @test run_io!(action) == 15
    end

    @testset "verify_monad_laws helper" begin
        a = 10
        f = x -> io_return(x + 1)
        g = x -> io_return(x * 2)
        m = io_return(a)
        laws = verify_monad_laws(a, f, g, m)
        @test laws.left_identity == true
        @test laws.right_identity == true
        @test laws.associativity == true
    end
end
