using Test
using Hsm

@testset "Abstract machine feature matrix" begin
    @abstracthsmdef AbstractFeatureSm

    @hsmdef mutable struct AbstractFeatureA <: AbstractFeatureSm
        log::Vector{Symbol}
        choose_first::Bool
        branch_initials::Int
    end

    @hsmdef mutable struct AbstractFeatureB <: AbstractFeatureSm
        log::Vector{Symbol}
        choose_first::Bool
        branch_initials::Int
    end

    @statedef AbstractFeatureSm :AbstractIdle
    @statedef AbstractFeatureSm :AbstractComposite
    @statedef AbstractFeatureSm :AbstractBranch :AbstractComposite
    @statedef AbstractFeatureSm :AbstractLeaf1 :AbstractBranch
    @statedef AbstractFeatureSm :AbstractLeaf2 :AbstractBranch
    @statedef AbstractFeatureSm :AbstractAlternate :AbstractComposite
    @finaldef AbstractFeatureSm :AbstractFinal :AbstractComposite
    @statedef AbstractFeatureSm :AbstractCompleted
    @statedef AbstractFeatureSm :AbstractShutdown
    @terminatedef AbstractFeatureSm :AbstractTerminate :AbstractShutdown
    @historydef AbstractFeatureSm :AbstractComposite Hsm.DeepHistory() :AbstractAlternate
    @historydef AbstractFeatureSm :AbstractComposite Hsm.ShallowHistory() :AbstractBranch

    @on_initial function (sm::AbstractFeatureSm, ::Root)
        return Hsm.transition!(sm, :AbstractIdle)
    end

    @on_initial function (sm::AbstractFeatureSm, ::AbstractComposite)
        return Hsm.transition!(sm, :AbstractBranch)
    end

    @on_initial function (sm::AbstractFeatureSm, ::AbstractBranch)
        sm.branch_initials += 1
        return Hsm.transition!(sm, :AbstractLeaf1)
    end

    @on_entry function (sm::AbstractFeatureSm, state::Any)
        push!(sm.log, Symbol(:enter_, state))
        return nothing
    end

    @on_exit function (sm::AbstractFeatureSm, state::Any)
        push!(sm.log, Symbol(:exit_, state))
        return nothing
    end

    @on_history_default function (
        sm::AbstractFeatureSm,
        ::AbstractComposite,
        ::DeepHistory,
    )
        push!(sm.log, :deep_default_effect)
        return nothing
    end

    @on_history_default function (
        sm::AbstractFeatureSm,
        ::AbstractComposite,
        ::ShallowHistory,
    )
        push!(sm.log, :shallow_default_effect)
        return nothing
    end

    @on_event function (sm::AbstractFeatureSm, ::AbstractIdle, ::Begin, arg)
        return Hsm.transition!(sm, :AbstractComposite)
    end

    @on_event function (sm::AbstractFeatureSm, ::AbstractLeaf1, ::Next, arg)
        return Hsm.transition!(sm, :AbstractLeaf2)
    end

    @on_event function (sm::AbstractFeatureSm, ::AbstractComposite, ::Leave, arg)
        return Hsm.transition!(sm, :AbstractIdle)
    end

    @on_event function (sm::AbstractFeatureSm, ::AbstractIdle, ::RecallDeep, arg)
        return Hsm.transition_history!(
            sm,
            :AbstractComposite,
            Hsm.DeepHistory(),
        )
    end

    @on_event function (sm::AbstractFeatureSm, ::AbstractIdle, ::RecallShallow, arg)
        return Hsm.transition_history!(
            sm,
            :AbstractComposite,
            Hsm.ShallowHistory(),
        )
    end

    @on_event function (sm::AbstractFeatureSm, ::AbstractIdle, ::Decide, arg)
        return @choice sm :AbstractComposite begin
            push!(sm.log, :choice_incoming)
            if (push!(sm.log, :choice_guard); sm.choose_first)
                Hsm.transition!(sm, :AbstractLeaf2) do
                    push!(sm.log, :first_effect)
                end
            else
                Hsm.transition!(sm, :AbstractAlternate) do
                    push!(sm.log, :else_effect)
                end
            end
        end
    end

    @on_event function (sm::AbstractFeatureSm, ::AbstractLeaf2, ::Finish, arg)
        return Hsm.transition!(sm, :AbstractFinal) do
            push!(sm.log, :finish_effect)
        end
    end

    @on_completion function (sm::AbstractFeatureSm, ::AbstractComposite)
        return Hsm.transition!(sm, :AbstractCompleted) do
            push!(sm.log, :completion_effect)
        end
    end

    @on_event function (sm::AbstractFeatureSm, ::AbstractIdle, ::Stop, arg)
        return Hsm.transition!(sm, :AbstractTerminate) do
            push!(sm.log, :terminate_effect)
        end
    end

    @testset "history registrations are inherited" begin
        deep = AbstractFeatureA(Symbol[], true, 0)
        @test length(Hsm._history_storage(deep)) == 1
        @test @inferred(Hsm.dispatch!(deep, :Begin)) === Hsm.EventHandled
        @test @inferred(Hsm.dispatch!(deep, :Next)) === Hsm.EventHandled
        @test @inferred(Hsm.dispatch!(deep, :Leave)) === Hsm.EventHandled
        empty!(deep.log)
        initial_count = deep.branch_initials

        @test @inferred(Hsm.dispatch!(deep, :RecallDeep)) === Hsm.EventHandled
        @test Hsm.current(deep) === :AbstractLeaf2
        @test deep.branch_initials == initial_count
        @test deep.log == [
            :exit_AbstractIdle,
            :enter_AbstractComposite,
            :enter_AbstractBranch,
            :enter_AbstractLeaf2,
        ]

        shallow = AbstractFeatureB(Symbol[], false, 0)
        Hsm.dispatch!(shallow, :Begin)
        Hsm.dispatch!(shallow, :Next)
        Hsm.dispatch!(shallow, :Leave)
        empty!(shallow.log)
        initial_count = shallow.branch_initials

        @test @inferred(Hsm.dispatch!(shallow, :RecallShallow)) === Hsm.EventHandled
        @test Hsm.current(shallow) === :AbstractLeaf1
        @test shallow.branch_initials == initial_count + 1
        @test shallow.log == [
            :exit_AbstractIdle,
            :enter_AbstractComposite,
            :enter_AbstractBranch,
            :enter_AbstractLeaf1,
        ]

        default_history = AbstractFeatureA(Symbol[], true, 0)
        empty!(default_history.log)
        @test @inferred(Hsm.dispatch!(default_history, :RecallDeep)) ===
              Hsm.EventHandled
        @test Hsm.current(default_history) === :AbstractAlternate
        @test default_history.log == [
            :exit_AbstractIdle,
            :deep_default_effect,
            :enter_AbstractComposite,
            :enter_AbstractAlternate,
        ]
    end

    @testset "choice registrations are inherited" begin
        first = AbstractFeatureA(Symbol[], true, 0)
        empty!(first.log)
        @test @inferred(Hsm.dispatch!(first, :Decide)) === Hsm.EventHandled
        @test Hsm.current(first) === :AbstractLeaf2
        @test first.log == [
            :exit_AbstractIdle,
            :choice_incoming,
            :enter_AbstractComposite,
            :choice_guard,
            :first_effect,
            :enter_AbstractBranch,
            :enter_AbstractLeaf2,
        ]

        otherwise = AbstractFeatureB(Symbol[], false, 0)
        empty!(otherwise.log)
        @test @inferred(Hsm.dispatch!(otherwise, :Decide)) === Hsm.EventHandled
        @test Hsm.current(otherwise) === :AbstractAlternate
        @test otherwise.log == [
            :exit_AbstractIdle,
            :choice_incoming,
            :enter_AbstractComposite,
            :choice_guard,
            :else_effect,
            :enter_AbstractAlternate,
        ]
    end

    @testset "final, completion, and terminate registrations are inherited" begin
        completed = AbstractFeatureA(Symbol[], true, 0)
        Hsm.dispatch!(completed, :Begin)
        Hsm.dispatch!(completed, :Next)
        empty!(completed.log)

        @test @inferred(Hsm.dispatch!(completed, :Finish)) === Hsm.EventHandled
        @test Hsm.current(completed) === :AbstractCompleted
        @test Hsm.isrunning(completed)
        @test completed.log == [
            :exit_AbstractLeaf2,
            :exit_AbstractBranch,
            :finish_effect,
            :exit_AbstractComposite,
            :completion_effect,
            :enter_AbstractCompleted,
        ]

        terminated = AbstractFeatureB(Symbol[], false, 0)
        empty!(terminated.log)
        @test @inferred(Hsm.dispatch!(terminated, :Stop)) === Hsm.EventHandled
        @test Hsm.isterminated(terminated)
        @test Hsm.current(terminated) === :Root
        @test terminated.log == [
            :exit_AbstractIdle,
            :terminate_effect,
            :enter_AbstractShutdown,
        ]
    end

    @abstracthsmdef AbstractParametricFeatureSm{T}

    @hsmdef mutable struct ParametricFeatureSm{T} <: AbstractParametricFeatureSm{T}
        value::T
    end

    @statedef AbstractParametricFeatureSm :ParametricA
    @statedef AbstractParametricFeatureSm :ParametricB

    @on_initial function (
        sm::AbstractParametricFeatureSm{T},
        ::Root,
    ) where {T}
        return Hsm.transition!(sm, :ParametricA)
    end

    @on_event function (
        sm::AbstractParametricFeatureSm{T},
        ::ParametricA,
        ::ParametricMove,
        arg::T,
    ) where {T}
        sm.value = arg
        return Hsm.transition!(sm, :ParametricB)
    end

    parametric = ParametricFeatureSm(1)
    @test Hsm.current(parametric) === :ParametricA
    @test @inferred(Hsm.dispatch!(parametric, :ParametricMove, 2)) ===
          Hsm.EventHandled
    @test Hsm.current(parametric) === :ParametricB
    @test parametric.value == 2
end
