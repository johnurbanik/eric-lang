# eric-lang

*"This is my programming language. I like it because it's mine."*

A stack-based, pipeline-oriented programming language featuring Prolog-style
unification, Scheme-style first-class continuations, Haskell-style lazy
evaluation with monadic IO, and NiLang reversible computing with automatic
differentiation.

## Installation

```
git clone https://github.com/RegionSyx/eric-lang.git
cd eric-lang
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

## Quickstart

```
bin/eric run examples/fib.eric
```

## Architecture

eric-lang source passes through four paradigm layers:

```
Source → Tokenizer → Parser → AST
  ↓
Prolog Unification Engine
  Pattern dispatch via Robinson's algorithm with occurs check.
  fib(0) = 1 becomes a fact in the knowledge base.
  ↓
CPS Interpreter (Scheme)
  Every eval step takes an explicit continuation.
  call/cc is available as a built-in.
  ↓
Lazy Evaluation (Haskell)
  Every value is a Thunk. Nothing evaluates until forced.
  Side effects sequenced through an IO monad.
  ↓
Reversible Execution (NiLang)
  Programs can run backward. Automatic differentiation is free.
  ↓
Result
```

The expression `add(2, 3)` passes through all four layers to produce `5`.

## CLI Commands

| Command | Description |
|---------|-------------|
| `eric run file.eric` | Execute a program |
| `eric tokenize file.eric` | Dump the token stream (with source locations) |
| `eric format file.eric` | Pretty-print the AST |
| `eric reverse file.eric` | Run forward, then run backward |
| `eric grad file.eric --wrt x` | Compute ∂output/∂input |
| `eric prove file.eric` | Show the Prolog proof tree for dispatch |
| `eric lazy file.eric` | Execute without forcing final thunks |

## Examples

### Pipeline Data Transformation

```
stdin
split("\n\n")
    split("\n")
        int
    sum
max
print
```

### Pattern-Matched Fibonacci

```
fib(0) = 1
fib(1) = 1
fib(x) = add(fib(sub(x, 2)), fib(sub(x, 1)))

fib(10)
print
```

### Memoized Fibonacci (via XSB-Style Tabled Resolution)

```
mfib(0) = 1
mfib(1) = 1
mfib(x) =
    memoize(x)
        add(mfib(sub(x, 2)), mfib(sub(x, 1)))
    _

mfib(100)
print
```

## What Changed in v1.0.0

This release addresses all feedback from the [technical review](eric-lang-review.md):

| Issue | Resolution |
|-------|------------|
| Stdlib was 90% `pyeval()` | All 50+ stdlib functions reimplemented natively in Julia. Zero `eval()` calls. |
| Tokenizer couldn't handle escaped quotes | `\"` now supported. This was the one proportionate fix. |
| No line numbers in errors | `SourceLocation` threaded through every AST node, unification failure, continuation frame, and thunk force-site. |
| `tqdm` dependency undeclared | Replaced with `ProgressMeter.jl` (declared in Project.toml). |
| Global mutable memo with no eviction | Replaced with XSB-style tabled resolution backed by LRU cache. |
| Formatter crashed on `as` bindings | Fixed. `names` correctly handled as a list. |
| Memoization + parallelism incompatible | Julia threads share memory. `ReentrantLock` on the knowledge base. |
| No tests | 14 test files, 200+ assertions, including verification of the three monad laws. |
| O(n) tuple append | Collections are lazy cons-lists. `append` is O(1). |
| No exhaustiveness checking | `NoMatchingClauseError` with the full substitution environment and attempted clauses. |
| "Completes many programs within seconds" | JIT-compiled. Second run: 0.003s. |

### Bonus Features

- **Reversible execution**: Run any program backward via `eric reverse`
- **Automatic differentiation**: Compute gradients via `eric grad`
- **First-class continuations**: `call/cc` available as a built-in
- **Prolog queries**: Dispatch via SLD resolution with backtracking
- **`@eric_str` macro**: Embed eric-lang in Julia source code
- **Lazy infinite lists**: `range(1, inf)` works

## Performance

| Benchmark | Python (v0.0.5) | Julia (v1.0.0) |
|-----------|-----------------|-----------------|
| fib(30) | 47s | 0.02s* |
| fib(100) memoized | 0.01s | 0.003s* |
| Startup time | 0.05s | 58s |
| Lines of implementation | 621 | 3,613 |
| Paradigms | 0 | 4 |
| Monad laws verified | 0 | 3 |

*After JIT compilation. First run includes ~58 seconds of Julia startup and
compilation of the unification engine, continuation system, thunk allocator,
and reversibility trace recorder. Subsequent runs benefit from cached compilation.

## Dependencies

| Package | Purpose | Size |
|---------|---------|------|
| NiLang.jl | Reversible computing | ~5,000 lines |
| NiLangCore.jl | NiLang compiler | ~3,000 lines |
| LRUCache.jl | Tabled resolution eviction | ~200 lines |
| ProgressMeter.jl | Progress bars (declared!) | ~800 lines |

Total dependency footprint: ~9,000 lines. This is more than the original
eric-lang interpreter by a factor of 14.5x, but each line is *principled*.

## Philosophy

The original eric-lang philosophy was: *"This is my programming language.
I like it because it's mine."*

The v1.0.0 philosophy is: *"This is my programming language. It uses
Robinson's unification algorithm with occurs check, continuation-passing
style with first-class delimited continuations, lazy evaluation with
monadic IO sequencing, and trace-based reversible computing with
automatic differentiation. I like it because it's mine."*

## Developing

```
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. test/runtests.jl
```

## License

This is my programming language. I like it because it's mine.
