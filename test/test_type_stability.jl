using Test
using Hsm

@testset "Type stability and steady-state allocations" begin
    @hsmdef mutable struct TypeStableSm
        entries::Int
        exits::Int
        events::Int
    end

    @statedef TypeStableSm :StableParent
    @statedef TypeStableSm :StableLeaf :StableParent
    @statedef TypeStableSm :StableOther

    @on_initial function (sm::TypeStableSm, ::Root)
        return Hsm.transition!(sm, :StableParent)
    end

    @on_initial function (sm::TypeStableSm, ::StableParent)
        return Hsm.transition!(sm, :StableLeaf)
    end

    @on_entry function (sm::TypeStableSm, state::Any)
        sm.entries += 1
        return nothing
    end

    @on_exit function (sm::TypeStableSm, state::Any)
        sm.exits += 1
        return nothing
    end

    @on_event function (sm::TypeStableSm, ::StableLeaf, ::StablePing, arg::Int)
        sm.events += arg
        return Hsm.EventHandled
    end

    @on_event function (
        sm::TypeStableSm,
        ::StableParent,
        ::StableAncestor,
        arg::Int,
    )
        sm.events += arg
        return Hsm.EventHandled
    end

    @on_event function (sm::TypeStableSm, ::StableLeaf, ::StableMove, arg)
        return Hsm.transition!(sm, :StableOther) do
            sm.events += 10
        end
    end

    @on_event function (sm::TypeStableSm, ::StableOther, ::StableSelf, arg)
        return Hsm.transition!(sm, :StableOther) do
            sm.events += 100
        end
    end

    @on_event function (sm::TypeStableSm, ::StableOther, ::StableReturn, arg)
        return Hsm.transition!(sm, :StableParent)
    end

    dispatch_ping!(sm::TypeStableSm) = Hsm.dispatch!(sm, :StablePing, 1)
    dispatch_ancestor!(sm::TypeStableSm) =
        Hsm.dispatch!(sm, :StableAncestor, 1)
    dispatch_unknown!(sm::TypeStableSm) =
        Hsm.dispatch!(sm, :StableUnknown, nothing)
    dispatch_move!(sm::TypeStableSm) = Hsm.dispatch!(sm, :StableMove, nothing)
    dispatch_self!(sm::TypeStableSm) = Hsm.dispatch!(sm, :StableSelf, nothing)
    dispatch_return!(sm::TypeStableSm) =
        Hsm.dispatch!(sm, :StableReturn, nothing)
    transition_other!(sm::TypeStableSm) = Hsm.transition!(
        sm,
        Hsm.current(sm) === :StableLeaf ? :StableOther : :StableParent,
    )

    allocated_call(f, sm::TypeStableSm) = @allocated f(sm)

    handlers = TypeStableSm(0, 0, 0)
    @test @inferred(Hsm.on_entry!(handlers, :StableLeaf)) === nothing
    @test @inferred(Hsm.on_exit!(handlers, :StableLeaf)) === nothing

    handled = TypeStableSm(0, 0, 0)
    @test @inferred(dispatch_ping!(handled)) === Hsm.EventHandled
    allocated_call(dispatch_ping!, handled)
    @test allocated_call(dispatch_ping!, handled) == 0

    ancestor = TypeStableSm(0, 0, 0)
    @test @inferred(dispatch_ancestor!(ancestor)) === Hsm.EventHandled
    allocated_call(dispatch_ancestor!, ancestor)
    @test allocated_call(dispatch_ancestor!, ancestor) == 0

    unhandled = TypeStableSm(0, 0, 0)
    @test @inferred(dispatch_unknown!(unhandled)) === Hsm.EventNotHandled
    allocated_call(dispatch_unknown!, unhandled)
    @test allocated_call(dispatch_unknown!, unhandled) == 0

    action = TypeStableSm(0, 0, 0)
    dispatch_move!(action)
    dispatch_return!(action)
    @test Hsm.current(action) === :StableLeaf
    @test @inferred(dispatch_move!(action)) === Hsm.EventHandled
    dispatch_return!(action)
    @test Hsm.current(action) === :StableLeaf
    @test allocated_call(dispatch_move!, action) == 0

    self_transition = TypeStableSm(0, 0, 0)
    dispatch_move!(self_transition)
    @test @inferred(dispatch_self!(self_transition)) === Hsm.EventHandled
    allocated_call(dispatch_self!, self_transition)
    @test allocated_call(dispatch_self!, self_transition) == 0

    nested_initial = TypeStableSm(0, 0, 0)
    dispatch_move!(nested_initial)
    dispatch_return!(nested_initial)
    dispatch_move!(nested_initial)
    @test @inferred(dispatch_return!(nested_initial)) === Hsm.EventHandled
    dispatch_move!(nested_initial)
    @test allocated_call(dispatch_return!, nested_initial) == 0
    @test Hsm.current(nested_initial) === :StableLeaf

    dynamic_target = TypeStableSm(0, 0, 0)
    @test @inferred(transition_other!(dynamic_target)) === Hsm.EventHandled
    @test @inferred(transition_other!(dynamic_target)) === Hsm.EventHandled
    allocated_call(transition_other!, dynamic_target)
    @test allocated_call(transition_other!, dynamic_target) == 0
end
