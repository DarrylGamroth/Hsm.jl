using Test
using Hsm

@testset "Static transition specialization" begin
    @hsmdef mutable struct StaticTransitionSm
        log::Vector{Symbol}
    end

    @statedef StaticTransitionSm :Parent
    @statedef StaticTransitionSm :Leaf :Parent
    @statedef StaticTransitionSm :Other

    @on_initial function (sm::StaticTransitionSm, ::Root)
        return Hsm.transition!(sm, :Parent)
    end

    @on_initial function (sm::StaticTransitionSm, ::Parent)
        return Hsm.transition!(sm, :Leaf)
    end

    @on_entry function (sm::StaticTransitionSm, state::Any)
        push!(sm.log, Symbol(:enter_, state))
        return nothing
    end

    @on_exit function (sm::StaticTransitionSm, state::Any)
        push!(sm.log, Symbol(:exit_, state))
        return nothing
    end

    # The active leaf is :Leaf, but the transition source is :Parent. This
    # exercises the Current/Source distinction from the static algorithm.
    @on_event function (sm::StaticTransitionSm, ::Parent, ::Move, arg)
        return Hsm.transition!(sm, :Other) do
            push!(sm.log, :move_action)
        end
    end

    @on_event function (sm::StaticTransitionSm, ::Other, ::Self, arg)
        return transition!(sm, :Other) do
            push!(sm.log, :self_action)
        end
    end

    sm = StaticTransitionSm(Symbol[])
    @test Hsm.current(sm) === :Leaf
    @test Hsm._history_storage(sm) === nothing
    @test sm.log == [:enter_Parent, :enter_Leaf]

    empty!(sm.log)
    @test Hsm.dispatch!(sm, :Move) === Hsm.EventHandled
    @test Hsm.current(sm) === :Other
    @test sm.log == [:exit_Leaf, :exit_Parent, :move_action, :enter_Other]

    empty!(sm.log)
    @test Hsm.dispatch!(sm, :Self) === Hsm.EventHandled
    @test Hsm.current(sm) === :Other
    @test sm.log == [:exit_Other, :self_action, :enter_Other]

    # A runtime-computed target remains supported through the public Symbol
    # fallback and preserves the same hierarchical ordering.
    empty!(sm.log)
    target = Hsm.current(sm) === :Other ? :Leaf : :Other
    @test Hsm.transition!(sm, target) === Hsm.EventHandled
    @test Hsm.current(sm) === :Leaf
    @test sm.log == [:exit_Other, :enter_Parent, :enter_Leaf]

    literal = :(Hsm.transition!(sm, :Other))
    rewritten = Hsm.rewrite_static_transitions(literal, :sm, :Leaf)
    @test rewritten.args[1] == GlobalRef(Hsm, :_transition_from!)

    action_first = :(Hsm.transition!(effect, sm, :Other))
    rewritten_action = Hsm.rewrite_static_transitions(action_first, :sm, :Leaf)
    @test rewritten_action.args[1] == GlobalRef(Hsm, :_transition_from!)
    @test rewritten_action.args[2] === :effect

    history_action_first = :(
        Hsm.transition_history!(effect, sm, :Parent, Hsm.DeepHistory())
    )
    rewritten_history =
        Hsm.rewrite_static_transitions(history_action_first, :sm, :Leaf)
    @test rewritten_history.args[1] == GlobalRef(Hsm, :_transition_history_from!)
    @test rewritten_history.args[2] === :effect

    dynamic = :(Hsm.transition!(sm, target))
    @test_throws Hsm.HsmMacroError Hsm.rewrite_static_transitions(dynamic, :sm, :Leaf)

    quoted = :(quote
        Hsm.transition!(sm, :Other)
    end)
    @test Hsm.rewrite_static_transitions(quoted, :sm, :Leaf) == quoted

    # Manually implemented hierarchies predate the static registration added
    # by @statedef. Literal handler transitions must retain that extension path.
    @hsmdef mutable struct ManualHierarchySm
    end

    Hsm.ancestor(::ManualHierarchySm, ::Val{:ManualA}) = :Root
    Hsm.ancestor(::ManualHierarchySm, ::Val{:ManualB}) = :Root

    @on_initial function (sm::ManualHierarchySm, ::Root)
        return Hsm.transition!(sm, :ManualA)
    end

    @on_event function (sm::ManualHierarchySm, ::ManualA, ::ManualMove, arg)
        return Hsm.transition!(sm, :ManualB)
    end

    manual = ManualHierarchySm()
    @test Hsm.current(manual) === :ManualA
    @test Hsm.dispatch!(manual, :ManualMove) === Hsm.EventHandled
    @test Hsm.current(manual) === :ManualB

    # Once a hierarchy is registered, an out-of-graph stored state is machine
    # corruption rather than a reason to re-enter the dynamic transition path.
    corrupt = StaticTransitionSm(Symbol[])
    Hsm.current!(corrupt, :Unregistered)
    @test_throws Hsm.HsmStateError Hsm._transition_from!(
        corrupt,
        Val(:Parent),
        Val(:Other),
    )

    @hsmdef mutable struct MissingParentSm end
    @statedef MissingParentSm :Orphan :Missing
    @test_throws Hsm.HsmStateError MissingParentSm()

    @hsmdef mutable struct CyclicHierarchySm end
    @statedef CyclicHierarchySm :CycleA :CycleB
    @statedef CyclicHierarchySm :CycleB :CycleA
    @test_throws Hsm.HsmStateError CyclicHierarchySm()
end
