using Test
using Hsm

module MacroRegressionFixtures
using Hsm

@hsmdef mutable struct BindingSm end
@statedef BindingSm :A
@statedef BindingSm :B
@on_initial function (sm::BindingSm, ::Root)
    Hsm.transition!(sm, :A)
end
@on_event function (sm::BindingSm, ::A, ::Callback, transition!)
    transition!(sm, :B)
end
@on_event function (sm::BindingSm, ::A, ::TypedCallback, transition!::F) where {F}
    transition!(sm, :B)
end
@on_event function (sm::BindingSm, ::A, ::HistoryCallback, transition_history!)
    transition_history!(sm, :B, Hsm.DeepHistory())
end
@on_event function (sm::BindingSm, ::A, ::ModuleCallback, Hsm)
    Hsm.transition!(sm, :B)
end
struct CallbackType end
CallbackType(sm::BindingSm, target) = Hsm.EventHandled
@on_event function (sm::BindingSm, ::A, ::TypeVariableCallback, data::transition!) where {transition!}
    transition!(sm, :B)
end
@on_event function (sm::BindingSm, ::A, ::Short, other)
    helper(sm) = Hsm.transition!(sm, :A)
    helper(other)
end
@on_event function (sm::BindingSm, ::A, ::ShortWhere, other)
    helper(sm::T) where {T} = Hsm.transition!(sm, :A)
    helper(other)
end
@on_event function (sm::BindingSm, ::A, ::ShortReturn, other)
    helper(sm)::Hsm.EventReturn = Hsm.transition!(sm, :A)
    helper(other)
end
@on_event function (sm::BindingSm, ::A, ::LongCallback, data)
    function transition!(machine, target)
        Hsm.EventHandled
    end
    transition!(sm, :B)
end
@on_event function (sm::BindingSm, ::A, ::LocalCallback, data)
    transition!(machine, target) = Hsm.EventHandled
    transition!(sm, :B)
end
@on_entry function (sm::BindingSm, ::A)
    helper() = Hsm.transition!(sm, :B)
    nothing
end

@hsmdef mutable struct CallableSm
    calls::Int
end
@statedef CallableSm :A
@statedef CallableSm :B
@on_initial function (sm::CallableSm, ::Root)
    Hsm.transition!(sm, :A)
end
function (sm::CallableSm)(machine, target)
    sm.calls += 1
    Hsm.EventHandled
end
@on_event function (transition!::CallableSm, ::A, ::CallMachine, arg)
    transition!(transition!, :B)
end
@on_event function (transition!::CallableSm, ::A, ::QualifiedTransition, arg)
    Hsm.transition!(transition!, :B)
end

@abstracthsmdef SuperFamily
@hsmdef mutable struct SuperSm <: SuperFamily
    seen::Int
end
@statedef SuperFamily :A
@on_initial function (sm::SuperFamily, ::Root)
    Hsm.transition!(sm, :A)
end
for (event, parameter) in ((:AbstractType, :abstract_type), (:StateType, :state_type),
                           (:EventType, :event_type), (:DataType, :data_type))
    @eval begin
        @on_event function (sm::SuperFamily, ::A, ::$event, arg)
            sm.seen = arg
            Hsm.EventHandled
        end
        @on_event function (sm::SuperSm, state::A, event::$event, $parameter)
            @super on_event sm state event $parameter
        end
    end
end
@on_entry function (sm::SuperFamily, ::A)
    sm.seen += 1
end
@on_entry function (abstract_type::SuperSm, state::A)
    @super on_entry abstract_type state
end

@hsmdef Base.@kwdef mutable struct KeywordSm{T<:Number,U}
    const value::T = one(T)
    label::U = "ready"
end
@statedef KeywordSm :A
@on_initial function (sm::KeywordSm, ::Root)
    Hsm.transition!(sm, :A)
end
@hsmdef mutable struct PositionalSm{T<:Number}
    value::T
end
@hsmdef mutable struct EmptyParametricSm{T} end

@hsmdef mutable struct ParameterSm{T}
    value::T
end
@statedef ParameterSm :A
@statedef ParameterSm :Parent
@statedef ParameterSm :Leaf :Parent
@finaldef ParameterSm{Float64} :A
@on_initial function (sm::ParameterSm, ::Root)
    Hsm.transition!(sm, :A)
end
@on_initial function (sm::ParameterSm{Int}, ::Parent)
    Hsm.transition!(sm, :Leaf)
end
@on_entry function (sm::ParameterSm{Int}, ::A)
    sm.value += 1
end
@on_event function (sm::ParameterSm{T}, ::A, ::Recall, arg::U) where {T<:Integer,U}
    Hsm.transition_history!(sm, :Parent, Hsm.DeepHistory())
end
@on_completion function (sm::ParameterSm{Int}, ::A)
    Hsm.EventNotHandled
end
@historydef ParameterSm{Int} :Parent Hsm.DeepHistory() :Leaf
@on_history_default function (sm::M, ::Parent, ::DeepHistory) where {M<:ParameterSm{Int}}
    sm.value += 10
end

@abstracthsmdef BoundedFamily
@hsmdef mutable struct BoundedSm <: BoundedFamily
    entries::Int
end
@statedef BoundedFamily :A
@on_initial function (sm::M, ::Root) where {M<:BoundedFamily}
    Hsm.transition!(sm, :A)
end
@on_entry function (sm::M, ::A) where {M<:BoundedFamily}
    sm.entries += 1
end
end

@testset "Macro regression contracts" begin
    fixtures = MacroRegressionFixtures
    @testset "handler bindings and nested functions" begin
        calls = Ref(0)
        callback = function (sm, target, rest...)
            calls[] += 1
            Hsm.EventHandled
        end
        for event in (:Callback, :TypedCallback, :HistoryCallback)
            sm = fixtures.BindingSm()
            @test Hsm.dispatch!(sm, event, callback) === Hsm.EventHandled
            @test Hsm.current(sm) === :A
        end
        @test calls[] == 3
        sm = fixtures.BindingSm()
        @test Hsm.dispatch!(sm, :ModuleCallback, (; transition! = callback)) === Hsm.EventHandled
        @test calls[] == 4
        @test Hsm.current(sm) === :A
        @test Hsm.dispatch!(sm, :TypeVariableCallback, fixtures.CallbackType()) === Hsm.EventHandled
        @test Hsm.current(sm) === :A
        for event in (:LocalCallback, :LongCallback)
            @test Hsm.dispatch!(sm, event) === Hsm.EventHandled
            @test Hsm.current(sm) === :A
        end
        for event in (:Short, :ShortWhere, :ShortReturn)
            source, other = fixtures.BindingSm(), fixtures.BindingSm()
            Hsm.transition!(other, :B)
            @test Hsm.dispatch!(source, event, other) === Hsm.EventHandled
            @test Hsm.current(other) === :A
            @test Hsm.current(source) === :A
        end
    end
    @testset "machine parameter bindings" begin
        sm = fixtures.CallableSm(0)
        @test Hsm.dispatch!(sm, :CallMachine) === Hsm.EventHandled
        @test sm.calls == 1
        @test Hsm.current(sm) === :A
        @test Hsm.dispatch!(sm, :QualifiedTransition) === Hsm.EventHandled
        @test Hsm.current(sm) === :B
    end
    @testset "super hygiene" begin
        sm = fixtures.SuperSm(0)
        @test sm.seen == 1
        for (index, event) in enumerate((:AbstractType, :StateType, :EventType, :DataType))
            @test Hsm.dispatch!(sm, event, index + 100) === Hsm.EventHandled
            @test sm.seen == index + 100
        end
    end
    @testset "parameterized construction" begin
        for sm in (fixtures.KeywordSm{Int,String}(),
                   fixtures.KeywordSm{Int,String}(value=3, label="set"),
                   fixtures.KeywordSm(value=2, label="inferred"))
            @test Hsm.current(sm) === :A
            @test Hsm.source(sm) === :A
        end
        @test fixtures.KeywordSm{Int,String}().value === 1
        @test fixtures.KeywordSm{Int,String}(label="set").label == "set"
        @test fixtures.PositionalSm{Int}(2).value === 2
        @test Hsm.current(fixtures.EmptyParametricSm{Int}()) === :Root
    end
    @testset "parameter-specific registrations" begin
        int_type = fixtures.ParameterSm{Int}
        float_type = fixtures.ParameterSm{Float64}
        @test fixtures.ParameterSm(1).value === 2
        @test Hsm.iscomplete(fixtures.ParameterSm(1.0))
        @test (:A, :entry) in Hsm._registered_state_behaviors(int_type)
        @test (:A, :entry) ∉ Hsm._registered_state_behaviors(float_type)
        @test Hsm._registered_history_owners(int_type) === (:Parent,)
        @test Hsm._registered_history_owners(float_type) === ()
        @test Hsm._registered_completion_states(int_type) === (:A,)
        @test Hsm._registered_completion_states(float_type) === ()
        @test (:Parent, :deep) in Hsm._registered_history_default_behaviors(int_type)
        @test Hsm._registered_history_default_behaviors(float_type) === ()
        @test any(edge -> edge[6] === :Recall, Hsm._registered_diagram_edges(int_type))
        @test all(edge -> edge[6] !== :Recall, Hsm._registered_diagram_edges(float_type))
        @test fixtures.BoundedSm(0).entries == 1
        @test (:A, :entry) in Hsm._registered_state_behaviors(fixtures.BoundedSm)
    end
    @testset "inner constructor rejection" begin
        for definition in (
            :(Hsm.@hsmdef mutable struct ShortInnerSm
                value::Int
                ShortInnerSm(value::Int) = new(value)
            end),
            :(Hsm.@hsmdef mutable struct LongInnerSm
                value::Int
                function LongInnerSm(value::Int)
                    new(value)
                end
            end),
            :(Hsm.@hsmdef mutable struct InlineInnerSm
                value::Int
                @inline InlineInnerSm(value::Int) = new(value)
            end),
            :(Hsm.@hsmdef mutable struct DocumentedInnerSm
                value::Int
                "Construct an instance."
                DocumentedInnerSm(value::Int) = new(value)
            end),
            :(Hsm.@hsmdef Base.@kwdef mutable struct KeywordInnerSm
                value::Int = 1
                KeywordInnerSm(value::Int) = new(value)
            end),
        )
            error = try
                macroexpand(@__MODULE__, definition)
                nothing
            catch error
                error
            end
            @test error isa Hsm.HsmMacroError
            @test occursin("inner constructors", sprint(showerror, error))
        end
    end
    @testset "exception help" begin
        @test all(name -> haskey(Base.Docs.meta(Hsm), Base.Docs.Binding(Hsm, name)),
                  (:HsmMacroError, :HsmStateError, :HsmEventError))
    end
end
