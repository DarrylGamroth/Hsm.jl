using Test
using Hsm

module RuntimeRegressionFixtures
using Hsm

@hsmdef mutable struct HistorySm
    defaults::Int
    handled::Int
end
@statedef HistorySm :Outer
@statedef HistorySm :Initial :Outer
@statedef HistorySm :Branch :Outer
@statedef HistorySm :Leaf :Branch
@finaldef HistorySm :Finished :Branch
@statedef HistorySm :Outside
@historydef HistorySm :Outer
@historydef HistorySm :Branch
@on_initial function (sm::HistorySm, ::Root)
    Hsm.transition!(sm, :Outer)
end
@on_initial function (sm::HistorySm, ::Outer)
    Hsm.transition!(sm, :Initial)
end
@on_initial function (sm::HistorySm, ::Branch)
    sm.defaults += 1
    Hsm.transition!(sm, :Leaf)
end
@on_event function (sm::HistorySm, ::Initial, ::Start, arg)
    Hsm.transition!(sm, :Branch)
end
@on_event function (sm::HistorySm, ::Leaf, ::Finish, arg)
    Hsm.transition!(sm, :Finished)
end
@on_event function (sm::HistorySm, ::Leaf, ::Up, arg)
    Hsm.transition!(sm, :Branch)
end
@on_event function (sm::HistorySm, ::Branch, ::Tick, arg)
    sm.handled += 1
    Hsm.EventHandled
end
@on_event function (sm::HistorySm, ::Outer, ::Leave, arg)
    Hsm.transition!(sm, :Outside)
end
@on_event function (sm::HistorySm, ::Outer, ::ChooseOutside, arg)
    @choice sm :Root begin
        if true
            Hsm.transition!(sm, :Outside)
        else
            Hsm.transition!(sm, :Outside)
        end
    end
end
@on_event function (sm::HistorySm, ::Outside, ::Shallow, arg)
    Hsm.transition_history!(sm, :Outer, Hsm.ShallowHistory())
end
@on_event function (sm::HistorySm, ::Outside, ::Deep, arg)
    Hsm.transition_history!(sm, :Outer, Hsm.DeepHistory())
end
function prepare_history!(sm::HistorySm, complete::Symbol, leave::Symbol)
    Hsm.dispatch!(sm, :Start)
    Hsm.dispatch!(sm, complete)
    leave === :dynamic ? Hsm.transition!(sm, :Outside) : Hsm.dispatch!(sm, leave)
    return sm
end
shallow!(sm::HistorySm) = Hsm.dispatch!(sm, :Shallow)
deep!(sm::HistorySm) = Hsm.dispatch!(sm, :Deep)
dynamic_deep!(sm::HistorySm) = Hsm.transition_history!(sm, :Outer, Hsm.DeepHistory())

@hsmdef mutable struct ChoiceSm
    log::Vector{Symbol}
end
@statedef ChoiceSm :Owner
@statedef ChoiceSm :A :Owner
@statedef ChoiceSm :B :Owner
@on_initial function (sm::ChoiceSm, ::Root)
    Hsm.transition!(sm, :Owner)
end
@on_initial function (sm::ChoiceSm, ::Owner)
    @choice sm :Owner begin
        push!(sm.log, :initial_effect)
        if true
            Hsm.transition!(sm, :A)
        else
            Hsm.transition!(sm, :B)
        end
    end
end
@on_entry function (sm::ChoiceSm, state::Any)
    push!(sm.log, Symbol(:enter_, state))
end
@on_exit function (sm::ChoiceSm, state::Any)
    push!(sm.log, Symbol(:exit_, state))
end
@on_event function (sm::ChoiceSm, ::Owner, ::Choose, arg)
    @choice sm :Owner begin
        push!(sm.log, :incoming)
        if (push!(sm.log, :guard); true)
            Hsm.transition!(sm, :B) do
                push!(sm.log, :outgoing)
            end
        else
            Hsm.transition!(sm, :A)
        end
    end
end

@hsmdef mutable struct AncestorSm
    automatic::Bool
    defaults::Int
    entries::Int
    exits::Int
    completions::Int
    events::Int
end
@statedef AncestorSm :Owner
@statedef AncestorSm :Leaf :Owner
@statedef AncestorSm :Done
@on_initial function (sm::AncestorSm, ::Root)
    Hsm.transition!(sm, :Owner)
end
@on_initial function (sm::AncestorSm, ::Owner)
    sm.defaults += 1
    Hsm.transition!(sm, :Leaf)
end
@on_entry function (sm::AncestorSm, ::Owner)
    sm.entries += 1
end
@on_exit function (sm::AncestorSm, ::Owner)
    sm.exits += 1
end
@on_event function (sm::AncestorSm, ::Leaf, ::Up, arg)
    Hsm.transition!(sm, :Owner)
end
@on_event function (sm::AncestorSm, ::Leaf, ::RootUp, arg)
    Hsm.transition!(sm, :Root)
end
@on_completion function (sm::AncestorSm, ::Owner)
    sm.completions += 1
    if sm.automatic
        return Hsm.transition!(sm, :Done)
    end
    Hsm.EventNotHandled
end
@on_event function (sm::AncestorSm, ::Owner, ::Tick, arg)
    sm.events += 1
    Hsm.EventHandled
end
@on_event function (sm::AncestorSm, ::Owner, ::Reset, arg)
    Hsm.transition!(sm, :Leaf)
end
ancestor(automatic) = AncestorSm(automatic, 0, 0, 0, 0, 0)
up!(sm::AncestorSm) = Hsm.dispatch!(sm, :Up)
up_dynamic!(sm::AncestorSm) = Hsm.transition!(sm, :Owner)
root_up!(sm::AncestorSm) = Hsm.dispatch!(sm, :RootUp)
root_up_dynamic!(sm::AncestorSm) = Hsm.transition!(sm, :Root)

# Invalid initial targets are tested after construction has entered Owner;
# effects and exits must not run before the containment error is raised.
@hsmdef mutable struct EscapingSm
    exits::Base.RefValue{Int}
    effects::Base.RefValue{Int}
end
@statedef EscapingSm :Owner
@statedef EscapingSm :Leaf :Owner
@statedef EscapingSm :Outside
@on_initial function (sm::EscapingSm, ::Root)
    Hsm.transition!(sm, :Owner)
end
@on_initial function (sm::EscapingSm, ::Owner)
    Hsm.transition!(sm, :Outside) do
        sm.effects[] += 1
    end
end
@on_exit function (sm::EscapingSm, ::Owner)
    sm.exits[] += 1
end

@hsmdef mutable struct SelfInitialSm end
@statedef SelfInitialSm :Owner
@on_initial function (sm::SelfInitialSm, ::Root)
    Hsm.transition!(sm, :Owner)
end
@on_initial function (sm::SelfInitialSm, ::Owner)
    Hsm.transition!(sm, :Owner)
end

@hsmdef mutable struct AncestorInitialSm end
@statedef AncestorInitialSm :Owner
@statedef AncestorInitialSm :Child :Owner
@on_initial function (sm::AncestorInitialSm, ::Root)
    Hsm.transition!(sm, :Child)
end
@on_initial function (sm::AncestorInitialSm, ::Child)
    Hsm.transition!(sm, :Owner)
end

@hsmdef mutable struct ChoiceEscapeSm
    effects::Base.RefValue{Int}
end
@statedef ChoiceEscapeSm :Owner
@statedef ChoiceEscapeSm :OwnChild :Owner
@statedef ChoiceEscapeSm :Outside
@statedef ChoiceEscapeSm :OutsideChild :Outside
@on_initial function (sm::ChoiceEscapeSm, ::Root)
    Hsm.transition!(sm, :Owner)
end
@on_initial function (sm::ChoiceEscapeSm, ::Owner)
    @choice sm :Outside begin
        sm.effects[] += 1
        if true
            Hsm.transition!(sm, :OutsideChild)
        else
            Hsm.transition!(sm, :OutsideChild)
        end
    end
end

@hsmdef mutable struct HistoryEscapeSm
    effects::Base.RefValue{Int}
end
@statedef HistoryEscapeSm :Owner
@statedef HistoryEscapeSm :OwnChild :Owner
@statedef HistoryEscapeSm :Outside
@statedef HistoryEscapeSm :OutsideChild :Outside
@historydef HistoryEscapeSm :Outside Hsm.DeepHistory() :OutsideChild
@on_initial function (sm::HistoryEscapeSm, ::Root)
    Hsm.transition!(sm, :Owner)
end
@on_initial function (sm::HistoryEscapeSm, ::Owner)
    Hsm.transition_history!(sm, :Outside, Hsm.DeepHistory()) do
        sm.effects[] += 1
    end
end

@hsmdef mutable struct InitialHistorySm end
@statedef InitialHistorySm :Owner
@statedef InitialHistorySm :Leaf :Owner
@historydef InitialHistorySm :Owner Hsm.DeepHistory() :Leaf
@on_initial function (sm::InitialHistorySm, ::Root)
    Hsm.transition!(sm, :Owner)
end
@on_initial function (sm::InitialHistorySm, ::Owner)
    Hsm.transition_history!(sm, :Owner, Hsm.DeepHistory())
end

mutable struct ManualSm
    current::Symbol
    source::Symbol
    initials::Int
    exits::Int
end
Hsm.current(sm::ManualSm) = sm.current
Hsm.current!(sm::ManualSm, state::Symbol) = (sm.current = state)
Hsm.source(sm::ManualSm) = sm.source
Hsm.source!(sm::ManualSm, state::Symbol) = (sm.source = state)
Hsm.ancestor(::ManualSm, state::Symbol) = state === :Leaf ? :Owner : :Root
Hsm.on_entry!(::ManualSm, ::Symbol) = nothing
Hsm.on_exit!(sm::ManualSm, ::Symbol) = (sm.exits += 1; nothing)
Hsm.on_initial!(sm::ManualSm, ::Symbol) = (sm.initials += 1; Hsm.EventHandled)
end

@testset "Runtime semantic regressions" begin
    fixtures = RuntimeRegressionFixtures
    @testset "Nested completion preserves enclosing history" begin
        for complete in (:Finish, :Up), leave in (:Leave, :ChooseOutside, :dynamic)
            for restore in (fixtures.shallow!, fixtures.deep!, fixtures.dynamic_deep!)
                sm = fixtures.prepare_history!(fixtures.HistorySm(0, 0), complete, leave)
                @test Hsm.current(sm) === :Outside
                @test Hsm._history_value(sm, Val(:Outer)) === (complete === :Finish ? :Branch : :Leaf)
                @test Hsm._history_value(sm, Val(:Branch)) === (complete === :Finish ? :Root : :Leaf)
                defaults = sm.defaults
                @test restore(sm) === Hsm.EventHandled
                if restore === fixtures.shallow!
                    @test Hsm.current(sm) === :Leaf
                    @test sm.defaults == defaults + 1
                else
                    @test Hsm.current(sm) === (complete === :Finish ? :Branch : :Leaf)
                    @test sm.defaults == defaults
                    @test Hsm.dispatch!(sm, :Tick) === Hsm.EventHandled
                    @test sm.handled == 1
                end
            end
        end
    end
    @testset "Choice preserves its active owner" begin
        sm = fixtures.ChoiceSm(Symbol[])
        @test sm.log == [:enter_Owner, :initial_effect, :enter_A]
        empty!(sm.log)
        @test Hsm.dispatch!(sm, :Choose) === Hsm.EventHandled
        @test Hsm.current(sm) === :B
        @test sm.log == [:exit_A, :incoming, :guard, :outgoing, :enter_B]
    end
    @testset "Ancestor targets complete their source Region" begin
        for automatic in (true, false), up in (fixtures.up!, fixtures.up_dynamic!)
            sm = fixtures.ancestor(automatic)
            @test up(sm) === Hsm.EventHandled
            @test sm.defaults == 1
            @test sm.entries == 1
            @test sm.completions == 1
            @test Hsm.current(sm) === (automatic ? :Done : :Owner)
            @test sm.exits == (automatic ? 1 : 0)
            @test Hsm.source(sm) === Hsm.current(sm)
            @test Hsm._transition_phase(sm) === Hsm._TRANSITION_IDLE
            if !automatic
                @test Hsm.dispatch!(sm, :Tick) === Hsm.EventHandled
                @test sm.events == 1
                @test Hsm.dispatch!(sm, :Reset) === Hsm.EventHandled
                @test Hsm.current(sm) === :Leaf
                @test sm.defaults == 1
            end
        end
    end
    @testset "Initial containment precedes effects" begin
        exits, effects = Ref(0), Ref(0)
        @test_throws Hsm.HsmStateError fixtures.EscapingSm(exits, effects)
        @test exits[] == 0
        @test effects[] == 0
        @test_throws Hsm.HsmStateError fixtures.SelfInitialSm()
        @test_throws Hsm.HsmStateError fixtures.AncestorInitialSm()
        @test_throws Hsm.HsmStateError fixtures.ChoiceEscapeSm(effects)
        @test_throws Hsm.HsmStateError fixtures.HistoryEscapeSm(effects)
        @test effects[] == 0
        @test Hsm.current(fixtures.InitialHistorySm()) === :Leaf
    end
    @testset "Root ancestor targets complete the machine" begin
        for up in (fixtures.root_up!, fixtures.root_up_dynamic!)
            sm = fixtures.ancestor(false)
            @test up(sm) === Hsm.EventHandled
            @test Hsm.iscomplete(sm)
            @test Hsm.current(sm) === :Root
            @test Hsm.source(sm) === :Root
            @test Hsm._transition_phase(sm) === Hsm._TRANSITION_IDLE
            @test sm.defaults == 1
            @test sm.entries == 1
            @test sm.exits == 1
            @test sm.completions == 0
            @test_throws Hsm.HsmEventError Hsm.dispatch!(sm, :Tick)
            @test_throws Hsm.HsmEventError Hsm.transition!(sm, :Leaf)
        end
    end
    @testset "Manual Symbol interfaces retain dynamic transitions" begin
        sm = fixtures.ManualSm(:Leaf, :Leaf, 0, 0)
        @test Hsm.transition!(sm, :Owner) === Hsm.EventHandled
        @test Hsm.current(sm) === :Owner
        @test Hsm.source(sm) === :Owner
        @test sm.exits == 1
        @test sm.initials == 0
        # History's dynamic endpoint activation uses the same manual fallback
        # and must not replay an initial Behavior.
        Hsm._restore_target_symbol_switch!(Val((:Root,)), sm, :Leaf)
        @test Hsm.current(sm) === :Leaf
        @test sm.initials == 0
        @test Hsm.transition!(sm, :Outside) === Hsm.EventHandled
        @test Hsm.current(sm) === :Outside
        @test sm.initials == 1
    end
    @testset "Concrete warmed runtime paths" begin
        # Construction and mutable setup are outside each measured expression.
        # The exact function/machine signature is warmed before measurement.
        for up in (fixtures.up!, fixtures.up_dynamic!)
            sm = fixtures.ancestor(true)
            up(sm)
            sm = fixtures.ancestor(true)
            @test @inferred(up(sm)) === Hsm.EventHandled
            sm = fixtures.ancestor(true)
            @test @allocated(up(sm)) == 0
            @test Hsm.current(sm) === :Done
            sm = fixtures.ancestor(true)
            @test @allocations(up(sm)) == 0
            @test Hsm.current(sm) === :Done
        end
        for restore in (fixtures.shallow!, fixtures.deep!, fixtures.dynamic_deep!)
            setup() = fixtures.prepare_history!(fixtures.HistorySm(0, 0), :Finish, :Leave)
            restore(setup())
            sm = setup()
            @test @inferred(restore(sm)) === Hsm.EventHandled
            sm = setup()
            @test @allocated(restore(sm)) == 0
            @test Hsm.current(sm) === (restore === fixtures.shallow! ? :Leaf : :Branch)
            sm = setup()
            @test @allocations(restore(sm)) == 0
            @test Hsm.current(sm) === (restore === fixtures.shallow! ? :Leaf : :Branch)
        end
    end
    @test haskey(Base.Docs.meta(Hsm), Base.Docs.Binding(Hsm, :EventHandled))
    @test haskey(Base.Docs.meta(Hsm), Base.Docs.Binding(Hsm, :EventNotHandled))
end
