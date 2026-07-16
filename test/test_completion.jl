using Test
using Hsm

@testset "Final states and completion transitions" begin
    @hsmdef mutable struct TopFinalSm
        log::Vector{Symbol}
    end

    @statedef TopFinalSm :TopWorking
    @finaldef TopFinalSm :TopDone

    @on_initial function (sm::TopFinalSm, ::Root)
        return Hsm.transition!(sm, :TopWorking)
    end

    @on_entry function (sm::TopFinalSm, state::Any)
        push!(sm.log, Symbol(:enter_, state))
        return nothing
    end

    @on_exit function (sm::TopFinalSm, state::Any)
        push!(sm.log, Symbol(:exit_, state))
        return nothing
    end

    @on_event function (sm::TopFinalSm, ::TopWorking, ::Finish, arg)
        return Hsm.transition!(sm, :TopDone) do
            push!(sm.log, :finish_effect)
        end
    end

    top = TopFinalSm(Symbol[])
    empty!(top.log)
    @test Hsm.isrunning(top)
    @test Hsm.dispatch!(top, :Finish) === Hsm.EventHandled
    @test Hsm.current(top) === :TopDone
    @test Hsm.iscomplete(top)
    @test !Hsm.isrunning(top)
    @test !Hsm.isterminated(top)
    @test top.log == [:exit_TopWorking, :finish_effect]
    @test_throws Hsm.HsmEventError Hsm.dispatch!(top, :Anything)
    @test_throws Hsm.HsmEventError Hsm.transition!(top, :TopWorking)

    @hsmdef mutable struct NestedFinalSm
        log::Vector{Symbol}
    end

    @statedef NestedFinalSm :NestedActive
    @statedef NestedFinalSm :NestedLeaf :NestedActive
    @finaldef NestedFinalSm :NestedFinal :NestedActive
    @statedef NestedFinalSm :NestedOutside

    @on_initial function (sm::NestedFinalSm, ::Root)
        return Hsm.transition!(sm, :NestedActive)
    end

    @on_initial function (sm::NestedFinalSm, ::NestedActive)
        return Hsm.transition!(sm, :NestedLeaf)
    end

    @on_entry function (sm::NestedFinalSm, state::Any)
        push!(sm.log, Symbol(:enter_, state))
        return nothing
    end

    @on_exit function (sm::NestedFinalSm, state::Any)
        push!(sm.log, Symbol(:exit_, state))
        return nothing
    end

    @on_event function (sm::NestedFinalSm, ::NestedLeaf, ::CompleteRegion, arg)
        return Hsm.transition!(sm, :NestedFinal) do
            push!(sm.log, :region_effect)
        end
    end

    @on_completion function (sm::NestedFinalSm, ::NestedActive)
        return Hsm.transition!(sm, :NestedOutside) do
            push!(sm.log, :completion_effect)
        end
    end

    nested = NestedFinalSm(Symbol[])
    empty!(nested.log)
    @test Hsm.dispatch!(nested, :CompleteRegion) === Hsm.EventHandled
    @test Hsm.current(nested) === :NestedOutside
    @test Hsm.isrunning(nested)
    @test nested.log == [
        :exit_NestedLeaf,
        :region_effect,
        :exit_NestedActive,
        :completion_effect,
        :enter_NestedOutside,
    ]

    @hsmdef mutable struct SimpleCompletionSm
        log::Vector{Symbol}
    end

    @statedef SimpleCompletionSm :Transient
    @statedef SimpleCompletionSm :Stable

    @on_initial function (sm::SimpleCompletionSm, ::Root)
        return Hsm.transition!(sm, :Transient)
    end

    @on_entry function (sm::SimpleCompletionSm, state::Any)
        push!(sm.log, Symbol(:enter_, state))
        return nothing
    end

    @on_exit function (sm::SimpleCompletionSm, state::Any)
        push!(sm.log, Symbol(:exit_, state))
        return nothing
    end

    @on_completion function (sm::SimpleCompletionSm, ::Transient)
        return Hsm.transition!(sm, :Stable) do
            push!(sm.log, :simple_completion)
        end
    end

    simple = SimpleCompletionSm(Symbol[])
    @test Hsm.current(simple) === :Stable
    @test simple.log == [
        :enter_Transient,
        :exit_Transient,
        :simple_completion,
        :enter_Stable,
    ]

    @hsmdef mutable struct LostCompletionSm end
    @statedef LostCompletionSm :LostState

    @on_initial function (sm::LostCompletionSm, ::Root)
        return Hsm.transition!(sm, :LostState)
    end

    @on_completion function (sm::LostCompletionSm, ::LostState)
        return Hsm.EventNotHandled
    end

    lost = LostCompletionSm()
    @test Hsm.current(lost) === :LostState
    @test Hsm.isrunning(lost)
    @test Hsm._pending_completion(lost) === nothing

    @hsmdef mutable struct CompletionPerfSm end
    @statedef CompletionPerfSm :PerfReady
    @statedef CompletionPerfSm :PerfTransient
    @statedef CompletionPerfSm :PerfStable

    @on_initial function (sm::CompletionPerfSm, ::Root)
        return Hsm.transition!(sm, :PerfReady)
    end

    @on_event function (sm::CompletionPerfSm, ::PerfReady, ::PerfStart, arg)
        return Hsm.transition!(sm, :PerfTransient)
    end

    @on_completion function (sm::CompletionPerfSm, ::PerfTransient)
        return Hsm.transition!(sm, :PerfStable)
    end

    @on_event function (sm::CompletionPerfSm, ::PerfStable, ::PerfReset, arg)
        return Hsm.transition!(sm, :PerfReady)
    end

    function completion_cycle!(sm::CompletionPerfSm)
        Hsm.dispatch!(sm, :PerfStart)
        return Hsm.dispatch!(sm, :PerfReset)
    end

    completion_cycle_bytes(sm::CompletionPerfSm) = @allocated completion_cycle!(sm)

    completion_perf = CompletionPerfSm()
    @test @inferred(completion_cycle!(completion_perf)) === Hsm.EventHandled
    @test Hsm.current(completion_perf) === :PerfReady
    completion_cycle_bytes(completion_perf)
    @test completion_cycle_bytes(completion_perf) == 0

    @hsmdef mutable struct InvalidFinalSm end
    @finaldef InvalidFinalSm :InvalidFinal
    @statedef InvalidFinalSm :InvalidFinalChild :InvalidFinal
    @test_throws Hsm.HsmStateError InvalidFinalSm()

    @hsmdef mutable struct InvalidFinalBehaviorSm end
    @finaldef InvalidFinalBehaviorSm :FinalWithBehavior

    @on_entry function (sm::InvalidFinalBehaviorSm, ::FinalWithBehavior)
        return nothing
    end

    @test_throws Hsm.HsmStateError InvalidFinalBehaviorSm()

    # A nested FinalState is transient for event dispatch and clears its
    # Region's remembered history. The next event is offered to its owning
    # composite State, and a later history recall follows normal initial entry.
    @hsmdef mutable struct FinalHistorySm
        generic_event_ran::Bool
    end

    @statedef FinalHistorySm :FinalHistoryOwner
    @statedef FinalHistorySm :FinalHistoryLeaf :FinalHistoryOwner
    @finaldef FinalHistorySm :FinalHistoryDone :FinalHistoryOwner
    @statedef FinalHistorySm :FinalHistoryOutside
    @historydef FinalHistorySm :FinalHistoryOwner

    @on_initial function (sm::FinalHistorySm, ::Root)
        return Hsm.transition!(sm, :FinalHistoryOwner)
    end

    @on_initial function (sm::FinalHistorySm, ::FinalHistoryOwner)
        return Hsm.transition!(sm, :FinalHistoryLeaf)
    end

    @on_event function (
        sm::FinalHistorySm,
        state::Any,
        event::Any,
        arg,
    )
        sm.generic_event_ran = true
        return Hsm.EventHandled
    end

    @on_event function (sm::FinalHistorySm, ::FinalHistoryLeaf, ::FinishNested, arg)
        return Hsm.transition!(sm, :FinalHistoryDone)
    end

    @on_event function (sm::FinalHistorySm, ::FinalHistoryOwner, ::LeaveFinal, arg)
        return Hsm.transition!(sm, :FinalHistoryOutside)
    end

    @on_event function (sm::FinalHistorySm, ::FinalHistoryOutside, ::RecallFinal, arg)
        return Hsm.transition_history!(
            sm,
            :FinalHistoryOwner,
            Hsm.DeepHistory(),
        )
    end

    final_history = FinalHistorySm(false)
    @test Hsm.dispatch!(final_history, :FinishNested) === Hsm.EventHandled
    @test Hsm.current(final_history) === :FinalHistoryDone
    @test Hsm.dispatch!(final_history, :LeaveFinal) === Hsm.EventHandled
    @test !final_history.generic_event_ran
    @test Hsm.current(final_history) === :FinalHistoryOutside
    @test Hsm.dispatch!(final_history, :RecallFinal) === Hsm.EventHandled
    @test Hsm.current(final_history) === :FinalHistoryLeaf
end
