# Run from this worktree with julia --project=. docs/review/reproduce.jl.
# Expected failures are version-specific; see docs/REVIEW.md for the evidence matrix.
using Hsm

function main(args)
    project = pkgdir(Hsm)
    repro_dir = joinpath(@__DIR__, "reproductions")
    files = isempty(args) ? sort(filter(name -> endswith(name, ".jl"), readdir(repro_dir))) : args
    println("Review reproduction run: Julia ", VERSION, ", ", Sys.MACHINE, ", threads=", Threads.nthreads())
    failures = 0
    for name in files
        path = joinpath(repro_dir, name)
        isfile(path) || error("Unknown reproduction: $name")
        println("\nREPRODUCTION ", name)
        flush(stdout)
        command = `$(Base.julia_cmd()) --startup-file=no --project=$project $path`
        process = run(ignorestatus(command))
        println("EXIT ", process.exitcode, " ", name)
        failures += !success(process)
    end
    println("\nReproductions with failing assertions: ", failures, "/", length(files))
end

main(ARGS)
