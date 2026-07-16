using Test
using Hsm

@testset "Choice Pseudostates" begin
    guard!(log, name, result) = (push!(log, name); result)

    @hsmdef mutable struct ChoiceTestSm
        log::Vector{Symbol}
        select_first::Bool
    end

    @statedef ChoiceTestSm :ChoiceA
    @statedef ChoiceTestSm :ChoiceB
    @statedef ChoiceTestSm :ChoiceC

    @on_initial function (sm::ChoiceTestSm, ::Root)
        return Hsm.transition!(sm, :ChoiceA)
    end

    @on_entry function (sm::ChoiceTestSm, state::Any)
        push!(sm.log, Symbol(:enter_, state))
        return nothing
    end

    @on_exit function (sm::ChoiceTestSm, state::Any)
        push!(sm.log, Symbol(:exit_, state))
        return nothing
    end

    @on_event function (sm::ChoiceTestSm, ::ChoiceA, ::Decide, arg)
        return Hsm.@choice sm :Root begin
            push!(sm.log, :incoming_effect)
            sm.select_first = arg
            if guard!(sm.log, :guard_a, sm.select_first)
                push!(sm.log, :branch_a)
                Hsm.transition!(sm, :ChoiceB) do
                    push!(sm.log, :outgoing_a)
                end
            elseif guard!(sm.log, :guard_b, true)
                Hsm.transition!(sm, :ChoiceC) do
                    push!(sm.log, :outgoing_b)
                end
            else
                Hsm.transition!(sm, :ChoiceA)
            end
        end
    end

    transition_from_choice_guard!(sm::ChoiceTestSm) =
        Hsm.transition!(sm, :ChoiceB)
    dispatch_from_choice_guard!(sm::ChoiceTestSm) =
        Hsm.dispatch!(sm, :Decide, false)

    @on_event function (sm::ChoiceTestSm, ::ChoiceA, ::BadGuardTransition, arg)
        return @choice sm :Root begin
            if transition_from_choice_guard!(sm) === Hsm.EventHandled
                Hsm.transition!(sm, :ChoiceB)
            else
                Hsm.transition!(sm, :ChoiceC)
            end
        end
    end

    @on_event function (sm::ChoiceTestSm, ::ChoiceA, ::BadGuardDispatch, arg)
        return @choice sm :Root begin
            if dispatch_from_choice_guard!(sm) === Hsm.EventHandled
                Hsm.transition!(sm, :ChoiceB)
            else
                Hsm.transition!(sm, :ChoiceC)
            end
        end
    end

    choice = ChoiceTestSm(Symbol[], false)
    empty!(choice.log)
    @test Hsm.dispatch!(choice, :Decide, true) === Hsm.EventHandled
    @test Hsm.current(choice) === :ChoiceB
    @test choice.log == [
        :exit_ChoiceA,
        :incoming_effect,
        :guard_a,
        :guard_b,
        :branch_a,
        :outgoing_a,
        :enter_ChoiceB,
    ]

    Hsm.transition!(choice, :ChoiceA)
    empty!(choice.log)
    @test Hsm.dispatch!(choice, :Decide, false) === Hsm.EventHandled
    @test Hsm.current(choice) === :ChoiceC
    @test choice.log == [
        :exit_ChoiceA,
        :incoming_effect,
        :guard_a,
        :guard_b,
        :outgoing_b,
        :enter_ChoiceC,
    ]

    for event in (:BadGuardTransition, :BadGuardDispatch)
        invalid_guard = ChoiceTestSm(Symbol[], false)
        @test_throws Hsm.HsmEventError Hsm.dispatch!(invalid_guard, event)
        @test Hsm.current(invalid_guard) === :ChoiceA
        @test Hsm._transition_phase(invalid_guard) == Hsm._TRANSITION_IDLE
    end

    @hsmdef mutable struct NestedChoiceSm
        log::Vector{Symbol}
        positive::Bool
    end

    @statedef NestedChoiceSm :ChoiceComposite
    @statedef NestedChoiceSm :ChoicePositive :ChoiceComposite
    @statedef NestedChoiceSm :ChoiceNegative :ChoiceComposite
    @statedef NestedChoiceSm :ChoiceOutside

    @on_initial function (sm::NestedChoiceSm, ::Root)
        return Hsm.transition!(sm, :ChoiceOutside)
    end

    @on_entry function (sm::NestedChoiceSm, state::Any)
        push!(sm.log, Symbol(:enter_, state))
        return nothing
    end

    @on_exit function (sm::NestedChoiceSm, state::Any)
        push!(sm.log, Symbol(:exit_, state))
        return nothing
    end

    @on_event function (sm::NestedChoiceSm, ::ChoiceOutside, ::EnterChoice, arg)
        return @choice sm :ChoiceComposite begin
            push!(sm.log, :incoming)
            if guard!(sm.log, :nested_guard, sm.positive)
                Hsm.transition!(sm, :ChoicePositive)
            else
                Hsm.transition!(sm, :ChoiceNegative)
            end
        end
    end

    nested = NestedChoiceSm(Symbol[], true)
    empty!(nested.log)
    @test Hsm.dispatch!(nested, :EnterChoice) === Hsm.EventHandled
    @test Hsm.current(nested) === :ChoicePositive
    @test nested.log == [
        :exit_ChoiceOutside,
        :incoming,
        :enter_ChoiceComposite,
        :nested_guard,
        :enter_ChoicePositive,
    ]

    @hsmdef mutable struct AncestorChoiceSm
        log::Vector{Symbol}
    end

    @statedef AncestorChoiceSm :ChoiceSource
    @statedef AncestorChoiceSm :ChoiceSourceLeaf :ChoiceSource
    @statedef AncestorChoiceSm :AncestorPositive
    @statedef AncestorChoiceSm :AncestorNegative

    @on_initial function (sm::AncestorChoiceSm, ::Root)
        return Hsm.transition!(sm, :ChoiceSource)
    end

    @on_initial function (sm::AncestorChoiceSm, ::ChoiceSource)
        return Hsm.transition!(sm, :ChoiceSourceLeaf)
    end

    @on_entry function (sm::AncestorChoiceSm, state::Any)
        push!(sm.log, Symbol(:enter_, state))
        return nothing
    end

    @on_exit function (sm::AncestorChoiceSm, state::Any)
        push!(sm.log, Symbol(:exit_, state))
        return nothing
    end

    @on_event function (sm::AncestorChoiceSm, ::ChoiceSource, ::AncestorChoose, arg)
        return @choice sm :Root begin
            push!(sm.log, :ancestor_incoming)
            if arg
                Hsm.transition!(sm, :AncestorPositive)
            else
                Hsm.transition!(sm, :AncestorNegative)
            end
        end
    end

    ancestor_choice = AncestorChoiceSm(Symbol[])
    empty!(ancestor_choice.log)
    @test Hsm.dispatch!(ancestor_choice, :AncestorChoose, true) === Hsm.EventHandled
    @test Hsm.current(ancestor_choice) === :AncestorPositive
    @test ancestor_choice.log == [
        :exit_ChoiceSourceLeaf,
        :exit_ChoiceSource,
        :ancestor_incoming,
        :enter_AncestorPositive,
    ]

    @hsmdef mutable struct InitialChoiceSm
        positive::Bool
    end

    @statedef InitialChoiceSm :InitialPositive
    @statedef InitialChoiceSm :InitialNegative

    @on_initial function (sm::InitialChoiceSm, ::Root)
        return @choice sm :Root begin
            if sm.positive
                Hsm.transition!(sm, :InitialPositive)
            else
                Hsm.transition!(sm, :InitialNegative)
            end
        end
    end

    @test Hsm.current(InitialChoiceSm(true)) === :InitialPositive
    @test Hsm.current(InitialChoiceSm(false)) === :InitialNegative

    @hsmdef mutable struct ChoicePerfSm
        choose_b::Bool
    end

    @statedef ChoicePerfSm :PerfChoiceA
    @statedef ChoicePerfSm :PerfChoiceB

    @on_initial function (sm::ChoicePerfSm, ::Root)
        return Hsm.transition!(sm, :PerfChoiceA)
    end

    @on_event function (sm::ChoicePerfSm, ::PerfChoiceA, ::PerfChoose, arg)
        return @choice sm :Root begin
            sm.choose_b = true
            if sm.choose_b
                Hsm.transition!(sm, :PerfChoiceB)
            else
                Hsm.transition!(sm, :PerfChoiceA)
            end
        end
    end

    @on_event function (sm::ChoicePerfSm, ::PerfChoiceB, ::PerfChoose, arg)
        return @choice sm :Root begin
            sm.choose_b = false
            if sm.choose_b
                Hsm.transition!(sm, :PerfChoiceB)
            else
                Hsm.transition!(sm, :PerfChoiceA)
            end
        end
    end

    function choice_cycle!(sm::ChoicePerfSm)
        Hsm.dispatch!(sm, :PerfChoose)
        return Hsm.dispatch!(sm, :PerfChoose)
    end

    choice_cycle_bytes(sm::ChoicePerfSm) = @allocated choice_cycle!(sm)

    perf = ChoicePerfSm(false)
    @test @inferred(choice_cycle!(perf)) === Hsm.EventHandled
    @test Hsm.current(perf) === :PerfChoiceA
    choice_cycle_bytes(perf)
    @test choice_cycle_bytes(perf) == 0

    no_else = :(
        Hsm.@on_event function (sm::ChoiceTestSm, ::ChoiceA, ::NoElse, arg)
            return Hsm.@choice sm :Root begin
                if arg
                    Hsm.transition!(sm, :ChoiceB)
                end
            end
        end
    )
    @test_throws Hsm.HsmMacroError macroexpand(@__MODULE__, no_else)

    computed_target = :(
        Hsm.@on_event function (sm::ChoiceTestSm, ::ChoiceA, ::Computed, target)
            return Hsm.@choice sm :Root begin
                if true
                    Hsm.transition!(sm, target)
                else
                    Hsm.transition!(sm, :ChoiceB)
                end
            end
        end
    )
    @test_throws Hsm.HsmMacroError macroexpand(@__MODULE__, computed_target)

    transition_guard = :(
        Hsm.@on_event function (sm::ChoiceTestSm, ::ChoiceA, ::BadGuard, arg)
            return Hsm.@choice sm :Root begin
                if Hsm.transition!(sm, :ChoiceB) === Hsm.EventHandled
                    Hsm.transition!(sm, :ChoiceB)
                else
                    Hsm.transition!(sm, :ChoiceC)
                end
            end
        end
    )
    @test_throws Hsm.HsmMacroError macroexpand(@__MODULE__, transition_guard)

    incoming_transition = :(
        Hsm.@on_event function (sm::ChoiceTestSm, ::ChoiceA, ::BadIncoming, arg)
            return Hsm.@choice sm :Root begin
                Hsm.transition!(sm, :ChoiceB)
                if true
                    Hsm.transition!(sm, :ChoiceB)
                else
                    Hsm.transition!(sm, :ChoiceC)
                end
            end
        end
    )
    @test_throws Hsm.HsmMacroError macroexpand(@__MODULE__, incoming_transition)

    outgoing_effect_transition = :(
        Hsm.@on_event function (sm::ChoiceTestSm, ::ChoiceA, ::BadEffect, arg)
            return Hsm.@choice sm :Root begin
                if true
                    Hsm.transition!(sm, :ChoiceB) do
                        Hsm.transition!(sm, :ChoiceC)
                    end
                else
                    Hsm.transition!(sm, :ChoiceC)
                end
            end
        end
    )
    @test_throws Hsm.HsmMacroError macroexpand(
        @__MODULE__,
        outgoing_effect_transition,
    )

    @test_throws Hsm.HsmMacroError macroexpand(
        @__MODULE__,
        :(Hsm.@choice choice :Root begin
            if true
                Hsm.transition!(choice, :ChoiceA)
            else
                Hsm.transition!(choice, :ChoiceB)
            end
        end),
    )
end
