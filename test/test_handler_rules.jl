using Test
using Hsm

module QualifiedMacroUse
    import Hsm

    Hsm.@hsmdef Base.@kwdef mutable struct QualifiedSm
        value::Int = 1
    end

    Hsm.@statedef QualifiedSm :QualifiedState

    Hsm.@on_initial function (sm::QualifiedSm, ::Root)
        return Hsm.transition!(sm, :QualifiedState)
    end
end

@testset "UML handler and macro rules" begin
    @hsmdef mutable struct HandlerRuleSm
        mode::Symbol
    end

    @statedef HandlerRuleSm :RuleA
    @statedef HandlerRuleSm :RuleB
    @statedef HandlerRuleSm :RuleC
    @statedef HandlerRuleSm :RuleD :RuleC
    @statedef HandlerRuleSm :RuleE :RuleC

    @on_initial function (sm::HandlerRuleSm, ::Root)
        return Hsm.transition!(sm, :RuleA)
    end

    reenter_rule!(sm::HandlerRuleSm, target::Symbol) = Hsm.transition!(sm, target)

    @on_entry function (sm::HandlerRuleSm, ::RuleB)
        if sm.mode === :entry
            reenter_rule!(sm, :RuleA)
        elseif sm.mode === :entry_dispatch
            Hsm.dispatch!(sm, :Inner)
        end
        return nothing
    end

    @on_exit function (sm::HandlerRuleSm, ::RuleA)
        sm.mode === :exit && reenter_rule!(sm, :RuleB)
        return nothing
    end

    @on_event function (sm::HandlerRuleSm, ::RuleA, ::Go, arg)
        return Hsm.transition!(sm, :RuleB) do
            sm.mode === :effect && reenter_rule!(sm, :RuleA)
        end
    end

    @on_event function (sm::HandlerRuleSm, ::RuleA, ::NestedDispatch, arg)
        return Hsm.dispatch!(sm, :Inner)
    end

    @on_event function (sm::HandlerRuleSm, ::RuleA, ::DynamicHelper, arg)
        return reenter_rule!(sm, :RuleB)
    end

    @on_initial function (sm::HandlerRuleSm, ::RuleC)
        reenter_rule!(sm, :RuleD)
        reenter_rule!(sm, :RuleE)
        return Hsm.EventHandled
    end

    for mode in (:exit, :effect, :entry, :entry_dispatch)
        sm = HandlerRuleSm(mode)
        @test_throws Hsm.HsmEventError Hsm.dispatch!(sm, :Go)
        @test Hsm._transition_phase(sm) == Hsm._TRANSITION_IDLE
    end


    nested_dispatch = HandlerRuleSm(:none)
    @test_throws Hsm.HsmEventError Hsm.dispatch!(nested_dispatch, :NestedDispatch)
    @test Hsm._transition_phase(nested_dispatch) == Hsm._TRANSITION_IDLE

    dynamic_helper = HandlerRuleSm(:none)
    @test_throws Hsm.HsmEventError Hsm.dispatch!(dynamic_helper, :DynamicHelper)
    @test Hsm._transition_phase(dynamic_helper) == Hsm._TRANSITION_IDLE

    initial = HandlerRuleSm(:none)
    @test_throws Hsm.HsmEventError Hsm.transition!(initial, :RuleC)
    @test Hsm._transition_phase(initial) == Hsm._TRANSITION_IDLE

    @hsmdef mutable struct RootInitialRuleSm end
    @statedef RootInitialRuleSm :RootRuleA
    @statedef RootInitialRuleSm :RootRuleB
    root_initial_step!(sm::RootInitialRuleSm, target::Symbol) =
        Hsm.transition!(sm, target)

    @on_initial function (sm::RootInitialRuleSm, ::Root)
        root_initial_step!(sm, :RootRuleA)
        root_initial_step!(sm, :RootRuleB)
        return Hsm.EventHandled
    end

    @test_throws Hsm.HsmEventError RootInitialRuleSm()

    entry_expr = :(
        Hsm.@on_entry function (sm::HandlerRuleSm, ::RuleA)
            Hsm.transition!(sm, :RuleB)
        end
    )
    @test_throws Hsm.HsmMacroError macroexpand(@__MODULE__, entry_expr)

    exit_expr = :(
        Hsm.@on_exit function (sm::HandlerRuleSm, ::RuleA)
            Hsm.transition!(sm, :RuleB)
        end
    )
    @test_throws Hsm.HsmMacroError macroexpand(@__MODULE__, exit_expr)

    history_default_expr = :(
        Hsm.@on_history_default function (
            sm::HandlerRuleSm,
            ::RuleC,
            ::DeepHistory,
        )
            Hsm.transition!(sm, :RuleD)
        end
    )
    @test_throws Hsm.HsmMacroError macroexpand(
        @__MODULE__,
        history_default_expr,
    )

    conditional_initial = :(
        Hsm.@on_initial function (sm::HandlerRuleSm, ::RuleC)
            if sm.mode === :first
                return Hsm.transition!(sm, :RuleD)
            end
            return Hsm.EventHandled
        end
    )
    @test_throws Hsm.HsmMacroError macroexpand(@__MODULE__, conditional_initial)

    multiple_initial = :(
        Hsm.@on_initial function (sm::HandlerRuleSm, ::RuleC)
            Hsm.transition!(sm, :RuleD)
            return Hsm.transition!(sm, :RuleE)
        end
    )
    @test_throws Hsm.HsmMacroError macroexpand(@__MODULE__, multiple_initial)

    computed_target = :(
        Hsm.@on_event function (sm::HandlerRuleSm, ::RuleA, ::Computed, target)
            return Hsm.transition!(sm, target)
        end
    )
    @test_throws Hsm.HsmMacroError macroexpand(@__MODULE__, computed_target)

    computed_history_kind = :(
        Hsm.@on_event function (sm::HandlerRuleSm, ::RuleA, ::History, kind)
            return Hsm.transition_history!(sm, :RuleC, kind)
        end
    )
    @test_throws Hsm.HsmMacroError macroexpand(
        @__MODULE__,
        computed_history_kind,
    )

    generic_source = :(
        Hsm.@on_event function (sm::HandlerRuleSm, state::Any, ::Generic, arg)
            return Hsm.transition!(sm, :RuleB)
        end
    )
    @test_throws Hsm.HsmMacroError macroexpand(@__MODULE__, generic_source)

    surplus_arguments = :(
        Hsm.@on_event function (sm::HandlerRuleSm, ::RuleA, ::Extra, arg, extra)
            return Hsm.EventHandled
        end
    )
    @test_throws ArgumentError macroexpand(@__MODULE__, surplus_arguments)

    quoted = :(quote
        Hsm.transition!(sm, :RuleB)
    end)
    @test Hsm.rewrite_static_transitions(quoted, :sm, :RuleA) == quoted

    nested = :(() -> Hsm.transition!(sm, :RuleB))
    @test Hsm.rewrite_static_transitions(nested, :sm, :RuleA) == nested

    shadowed = quote
        local transition! = identity
        transition!(sm, :RuleB)
    end
    @test Hsm.rewrite_static_transitions(shadowed, :sm, :RuleA) == shadowed

    @hsmdef mutable struct WhereHandlerSm{T,U}
        value::T
        other::U
    end

    @statedef WhereHandlerSm :WhereA

    @on_initial function (sm::WhereHandlerSm{T,U}, ::Root) where {T,U}
        return Hsm.transition!(sm, :WhereA)
    end

    @on_entry function (sm::WhereHandlerSm{T,U}, ::WhereA) where {T,U}
        sm.value += one(T)
        return nothing
    end

    @on_event function (
        sm::WhereHandlerSm{T,U},
        ::WhereA,
        ::WhereEvent,
        arg::T,
    ) where {T,U}
        sm.value = arg
        return Hsm.EventHandled
    end

    where_sm = WhereHandlerSm(1, "other")
    @test where_sm.value == 2
    @test Hsm.dispatch!(where_sm, :WhereEvent, 3) === Hsm.EventHandled
    @test where_sm.value == 3

    qualified = QualifiedMacroUse.QualifiedSm()
    @test Hsm.current(qualified) === :QualifiedState
    @test qualified.value == 1
end
