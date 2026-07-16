using Test
using Hsm

@testset "Terminate Pseudostates" begin
    @hsmdef mutable struct TopTerminateSm
        log::Vector{Symbol}
    end

    @statedef TopTerminateSm :TopRunning
    @terminatedef TopTerminateSm :TopTerminate

    @on_initial function (sm::TopTerminateSm, ::Root)
        return Hsm.transition!(sm, :TopRunning)
    end

    @on_entry function (sm::TopTerminateSm, state::Any)
        push!(sm.log, Symbol(:enter_, state))
        return nothing
    end

    @on_exit function (sm::TopTerminateSm, state::Any)
        push!(sm.log, Symbol(:exit_, state))
        return nothing
    end

    @on_event function (sm::TopTerminateSm, ::TopRunning, ::Stop, arg)
        return Hsm.transition!(sm, :TopTerminate) do
            push!(sm.log, :stop_effect)
        end
    end

    top = TopTerminateSm(Symbol[])
    empty!(top.log)
    @test Hsm.dispatch!(top, :Stop) === Hsm.EventHandled
    @test Hsm.isterminated(top)
    @test !Hsm.isrunning(top)
    @test !Hsm.iscomplete(top)
    @test Hsm.current(top) === :Root
    @test top.log == [:exit_TopRunning, :stop_effect]
    @test_throws Hsm.HsmEventError Hsm.dispatch!(top, :Anything)
    @test_throws Hsm.HsmEventError Hsm.transition!(top, :TopRunning)

    @hsmdef mutable struct NestedTerminateSm
        log::Vector{Symbol}
    end

    @statedef NestedTerminateSm :Outside
    @statedef NestedTerminateSm :ShutdownRegion
    @terminatedef NestedTerminateSm :NestedTerminate :ShutdownRegion

    @on_initial function (sm::NestedTerminateSm, ::Root)
        return Hsm.transition!(sm, :Outside)
    end

    @on_entry function (sm::NestedTerminateSm, state::Any)
        push!(sm.log, Symbol(:enter_, state))
        return nothing
    end

    @on_exit function (sm::NestedTerminateSm, state::Any)
        push!(sm.log, Symbol(:exit_, state))
        return nothing
    end

    @on_event function (sm::NestedTerminateSm, ::Outside, ::NestedStop, arg)
        return Hsm.transition!(sm, :NestedTerminate) do
            push!(sm.log, :nested_effect)
        end
    end

    nested = NestedTerminateSm(Symbol[])
    empty!(nested.log)
    @test Hsm.dispatch!(nested, :NestedStop) === Hsm.EventHandled
    @test Hsm.isterminated(nested)
    @test Hsm.current(nested) === :Root
    @test nested.log == [
        :exit_Outside,
        :nested_effect,
        :enter_ShutdownRegion,
    ]

    @hsmdef mutable struct ChoiceTerminateSm
        choose_stop::Bool
        log::Vector{Symbol}
    end

    @statedef ChoiceTerminateSm :ChoiceStart
    @statedef ChoiceTerminateSm :ChoiceOwner
    @statedef ChoiceTerminateSm :ChoiceContinue :ChoiceOwner
    @terminatedef ChoiceTerminateSm :ChoiceStop :ChoiceOwner

    @on_initial function (sm::ChoiceTerminateSm, ::Root)
        return Hsm.transition!(sm, :ChoiceStart)
    end

    @on_entry function (sm::ChoiceTerminateSm, state::Any)
        push!(sm.log, Symbol(:enter_, state))
        return nothing
    end

    @on_exit function (sm::ChoiceTerminateSm, state::Any)
        push!(sm.log, Symbol(:exit_, state))
        return nothing
    end

    @on_event function (sm::ChoiceTerminateSm, ::ChoiceStart, ::Choose, arg)
        return @choice sm :ChoiceOwner begin
            push!(sm.log, :choice_incoming)
            if sm.choose_stop
                Hsm.transition!(sm, :ChoiceStop) do
                    push!(sm.log, :choice_stop_effect)
                end
            else
                Hsm.transition!(sm, :ChoiceContinue)
            end
        end
    end

    choice = ChoiceTerminateSm(true, Symbol[])
    empty!(choice.log)
    @test Hsm.dispatch!(choice, :Choose) === Hsm.EventHandled
    @test Hsm.isterminated(choice)
    @test Hsm.current(choice) === :Root
    @test choice.log == [
        :exit_ChoiceStart,
        :choice_incoming,
        :enter_ChoiceOwner,
        :choice_stop_effect,
    ]

    @hsmdef mutable struct DynamicTerminateSm end
    @statedef DynamicTerminateSm :DynamicReady
    @terminatedef DynamicTerminateSm :DynamicStop

    @on_initial function (sm::DynamicTerminateSm, ::Root)
        return Hsm.transition!(sm, :DynamicReady)
    end

    dynamic = DynamicTerminateSm()
    dynamic_target = Symbol("DynamicStop")
    @test Hsm.transition!(dynamic, dynamic_target) === Hsm.EventHandled
    @test Hsm.isterminated(dynamic)
    @test Hsm.current(dynamic) === :Root

    @hsmdef mutable struct InitialTerminateSm
        effect_ran::Bool
    end
    @terminatedef InitialTerminateSm :InitialTerminate

    @on_initial function (sm::InitialTerminateSm, ::Root)
        return Hsm.transition!(sm, :InitialTerminate) do
            sm.effect_ran = true
        end
    end

    initial = InitialTerminateSm(false)
    @test initial.effect_ran
    @test Hsm.isterminated(initial)
    @test Hsm.current(initial) === :Root

    @hsmdef mutable struct TerminatePerfSm end
    @statedef TerminatePerfSm :TerminatePerfReady
    @terminatedef TerminatePerfSm :TerminatePerfStop

    @on_initial function (sm::TerminatePerfSm, ::Root)
        return Hsm.transition!(sm, :TerminatePerfReady)
    end

    @on_event function (sm::TerminatePerfSm, ::TerminatePerfReady, ::PerfStop, arg)
        return Hsm.transition!(sm, :TerminatePerfStop)
    end

    terminate_bytes(sm::TerminatePerfSm) = @allocated Hsm.dispatch!(sm, :PerfStop)

    perf_warm = TerminatePerfSm()
    @test @inferred(Hsm.dispatch!(perf_warm, :PerfStop)) === Hsm.EventHandled
    perf_measure = TerminatePerfSm()
    terminate_bytes(perf_measure)
    perf_measure = TerminatePerfSm()
    @test terminate_bytes(perf_measure) == 0
    @test Hsm.isterminated(perf_measure)

    @hsmdef mutable struct InvalidTerminateSm end
    @terminatedef InvalidTerminateSm :InvalidTerminate
    @statedef InvalidTerminateSm :InvalidTerminateChild :InvalidTerminate
    @test_throws Hsm.HsmStateError InvalidTerminateSm()

    @hsmdef mutable struct InvalidTerminateBehaviorSm end
    @terminatedef InvalidTerminateBehaviorSm :TerminateWithBehavior

    @on_event function (
        sm::InvalidTerminateBehaviorSm,
        ::TerminateWithBehavior,
        ::Never,
        arg,
    )
        return Hsm.EventHandled
    end

    @test_throws Hsm.HsmStateError InvalidTerminateBehaviorSm()
end
