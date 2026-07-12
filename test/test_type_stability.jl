using Test
using Hsm

@testset "Type stability and steady-state allocations" begin
    @hsmdef mutable struct TypeStableSm
        entries::Int
        exits::Int
        events::Int
    end

    @statedef TypeStableSm :StateA
    @statedef TypeStableSm :StateB

    @on_initial function (sm::TypeStableSm, ::Root)
        return Hsm.transition!(sm, :StateA)
    end

    @on_entry function (sm::TypeStableSm, state::Any)
        sm.entries += 1
        return nothing
    end

    @on_exit function (sm::TypeStableSm, state::Any)
        sm.exits += 1
        return nothing
    end

    @on_event function (sm::TypeStableSm, ::StateA, ::Ping, arg::Int)
        sm.events += arg
        return Hsm.EventHandled
    end

    @on_event function (sm::TypeStableSm, ::StateB, ::Ping, arg::Int)
        sm.events += arg
        return Hsm.EventHandled
    end

    @on_event function (sm::TypeStableSm, state::Any, event::Any, arg)
        return Hsm.EventNotHandled
    end

    dispatch_ping!(sm::TypeStableSm) = Hsm.dispatch!(sm, :Ping, 1)
    dispatch_unknown!(sm::TypeStableSm) = Hsm.dispatch!(sm, :Unknown, nothing)
    transition_other!(sm::TypeStableSm) =
        Hsm.transition!(sm, Hsm.current(sm) === :StateA ? :StateB : :StateA)

    dispatch_bytes(sm::TypeStableSm) = @allocated dispatch_ping!(sm)
    unknown_bytes(sm::TypeStableSm) = @allocated dispatch_unknown!(sm)
    transition_bytes(sm::TypeStableSm) = @allocated transition_other!(sm)

    sm = TypeStableSm(0, 0, 0)

    @test @inferred(Hsm.on_entry!(sm, :StateA)) === nothing
    @test @inferred(Hsm.on_exit!(sm, :StateA)) === nothing
    @test @inferred(dispatch_ping!(sm)) === Hsm.EventHandled
    @test @inferred(dispatch_unknown!(sm)) === Hsm.EventNotHandled
    @test Hsm.source(sm) === Hsm.current(sm)
    @test @inferred(transition_other!(sm)) === Hsm.EventHandled

    # Warm the measurement barriers before checking the steady-state budget.
    dispatch_bytes(sm)
    unknown_bytes(sm)
    transition_bytes(sm)

    @test dispatch_bytes(sm) == 0
    @test unknown_bytes(sm) == 0
    @test transition_bytes(sm) == 0
end
