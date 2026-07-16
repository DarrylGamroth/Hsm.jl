using Hsm

@hsmdef mutable struct CompileLatencySm end

@statedef CompileLatencySm :Idle
@statedef CompileLatencySm :Active
@statedef CompileLatencySm :ModeA :Active
@statedef CompileLatencySm :ModeA1 :ModeA
@statedef CompileLatencySm :ModeA2 :ModeA
@statedef CompileLatencySm :ModeB :Active
@statedef CompileLatencySm :ModeB1 :ModeB
@statedef CompileLatencySm :ModeB2 :ModeB

@on_initial function (sm::CompileLatencySm, ::Root)
    return Hsm.transition!(sm, :Idle)
end

@on_initial function (sm::CompileLatencySm, ::Active)
    return Hsm.transition!(sm, :ModeA)
end

@on_initial function (sm::CompileLatencySm, ::ModeA)
    return Hsm.transition!(sm, :ModeA1)
end

@on_initial function (sm::CompileLatencySm, ::ModeB)
    return Hsm.transition!(sm, :ModeB1)
end

@on_event function (sm::CompileLatencySm, ::Idle, ::Start, ::Nothing)
    return Hsm.transition!(sm, :Active)
end

@on_event function (sm::CompileLatencySm, ::ModeA1, ::Next, ::Nothing)
    return Hsm.transition!(sm, :ModeA2)
end

@on_event function (sm::CompileLatencySm, ::ModeA2, ::Switch, ::Nothing)
    return Hsm.transition!(sm, :ModeB)
end

@on_event function (sm::CompileLatencySm, ::ModeB1, ::Next, ::Nothing)
    return Hsm.transition!(sm, :ModeB2)
end

@on_event function (sm::CompileLatencySm, ::ModeB2, ::Stop, ::Nothing)
    return Hsm.transition!(sm, :Idle)
end

function compile_latency_cycle!(sm::CompileLatencySm)
    Hsm.dispatch!(sm, :Start, nothing)
    Hsm.dispatch!(sm, :Next, nothing)
    Hsm.dispatch!(sm, :Switch, nothing)
    Hsm.dispatch!(sm, :Next, nothing)
    result = Hsm.dispatch!(sm, :Stop, nothing)
    @assert result === Hsm.EventHandled
    @assert Hsm.current(sm) === :Idle
    return nothing
end

function compile_latency_cycle()
    sm = CompileLatencySm()
    compile_latency_cycle!(sm)
    return nothing
end

compile_latency_cycle_bytes(sm::CompileLatencySm) =
    @allocated compile_latency_cycle!(sm)

# Evaluate the first call at runtime so compilation occurs inside the timer on
# both Julia 1.10 and newer top-level execution implementations.
first_seconds = @elapsed Core.eval(Main, :(compile_latency_cycle()))
warm_sm = CompileLatencySm()
compile_latency_cycle!(warm_sm)
warm_iterations = 100_000
warm_seconds = @elapsed for _ in 1:warm_iterations
    compile_latency_cycle!(warm_sm)
end
warm_bytes = compile_latency_cycle_bytes(warm_sm)
@assert warm_bytes == 0

println("julia_version=", VERSION)
println("threads=", Threads.nthreads())
println("cpu_target=", get(ENV, "JULIA_CPU_TARGET", "<unset>"))
println("first_cycle_seconds=", first_seconds)
println("warm_iterations=", warm_iterations)
println("warm_total_seconds=", warm_seconds)
println("warm_nanoseconds_per_cycle=", warm_seconds * 1.0e9 / warm_iterations)
println("warm_bytes_per_cycle=", warm_bytes)
