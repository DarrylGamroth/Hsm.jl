using Test
using Hsm

include("diagram_fixture.jl")
using .DiagramFixture: DiagramTestSm

@testset "Dependency-free diagram model and serializers" begin
    # The model is built from type metadata and does not construct the machine,
    # whose user field intentionally has no zero-argument default.
    model = Hsm.diagram_model(DiagramTestSm)
    @test model.machine === DiagramTestSm
    @test length(model.states) == 5

    states = Dict(state.name => state for state in model.states)
    @test states[:Operating].kind === :composite
    @test states[:Done].kind === :final
    @test !haskey(states, :Stopped)
    @test states[:Idle].parent === :Operating

    pseudostate_kinds =
        Set(pseudostate.kind for pseudostate in model.pseudostates)
    @test pseudostate_kinds ==
          Set((:initial, :choice, :shallow_history, :deep_history, :terminate))
    terminate = only(
        pseudostate for pseudostate in model.pseudostates
        if pseudostate.kind === :terminate
    )
    @test terminate.name === :Stopped
    @test terminate.owner === :Root

    transition_for(trigger) = only(
        transition for transition in model.transitions
        if transition.trigger === trigger
    )
    @test transition_for(:Reset).kind === :local
    @test transition_for(:Retry).kind === :external
    @test transition_for(:Work).has_effect
    @test transition_for(:Recall).kind === :history
    @test transition_for(:Stop).target === :Stopped
    @test !any(
        transition.trigger === :Ping for transition in model.transitions
    )
    @test any(
        transition.trigger_kind === :completion &&
        transition.source === :Operating &&
        transition.target === :Outside
        for transition in model.transitions
    )
    @test Set(
        transition.guard for transition in model.transitions
        if transition.guard !== nothing &&
           transition.trigger_kind === :guard
    ) == Set((:guard_1, :else))

    history_defaults = [
        transition for transition in model.transitions
        if transition.trigger_kind === :default
    ]
    @test length(history_defaults) == 2
    @test count(transition -> transition.has_effect, history_defaults) == 1

    plantuml = Hsm.diagram(model; format=:plantuml)
    @test startswith(plantuml, "@startuml\n")
    @test endswith(plantuml, "@enduml\n")
    @test occursin("<<choice>>", plantuml)
    @test occursin("<<history>>", plantuml)
    @test occursin("<<history*>>", plantuml)
    @test occursin("<<end>>", plantuml)
    @test !occursin("<<terminate>>", plantuml)
    @test occursin("Stopped (terminate)", plantuml)
    @test occursin("terminate Pseudostate; terminate uses a labeled state", plantuml)
    @test occursin(" : Reset", plantuml)
    @test occursin(" : Work / effect", plantuml)
    @test occursin(" : [guard 1] / effect", plantuml)
    @test plantuml == Hsm.diagram(DiagramTestSm; format=:plantuml)

    mermaid = Hsm.diagram(model; format=:mermaid)
    @test startswith(mermaid, "stateDiagram-v2\n")
    @test occursin("<<choice>>", mermaid)
    @test occursin("H (shallow history)", mermaid)
    @test occursin("H* (deep history)", mermaid)
    @test occursin("(FinalState)", mermaid)
    @test occursin("(terminate)", mermaid)
    @test occursin("Mermaid may not render edges crossing", mermaid)
    @test occursin(" : Recall", mermaid)
    @test mermaid == Hsm.diagram(DiagramTestSm; format=:mermaid)

    io = IOBuffer()
    @test Hsm.diagram(io, model; format=:plantuml) === nothing
    @test String(take!(io)) == plantuml
    @test_throws ArgumentError Hsm.diagram(model; format=:dot)

    escaped_model = Hsm.DiagramModel(
        DiagramTestSm,
        [
            Hsm.DiagramState(
                Symbol("Quoted \"state\" & value"),
                :Root,
                :state,
                Symbol[],
            ),
        ],
        Hsm.DiagramPseudostate[],
        Hsm.DiagramTransition[],
    )
    @test occursin(
        "Quoted \\\"state\\\" & value",
        Hsm.diagram(escaped_model; format=:plantuml),
    )
    @test occursin(
        "Quoted &quot;state&quot; &amp; value",
        Hsm.diagram(escaped_model; format=:mermaid),
    )

    @abstracthsmdef AbstractDiagramFamily
    @statedef AbstractDiagramFamily :SharedA
    @statedef AbstractDiagramFamily :SharedB

    @on_initial function (sm::AbstractDiagramFamily, ::Root)
        return Hsm.transition!(sm, :SharedA)
    end

    @on_event function (sm::AbstractDiagramFamily, ::SharedA, ::SharedGo, _)
        return Hsm.transition!(sm, :SharedB)
    end

    @hsmdef mutable struct ConcreteDiagramMachine <: AbstractDiagramFamily end

    abstract_model = Hsm.diagram_model(AbstractDiagramFamily)
    concrete_model = Hsm.diagram_model(ConcreteDiagramMachine)
    state_projection(model) = [
        (state.name, state.parent, state.kind, state.behaviors)
        for state in model.states
    ]
    @test state_projection(abstract_model) == state_projection(concrete_model)
    @test abstract_model.pseudostates == concrete_model.pseudostates
    @test abstract_model.transitions == concrete_model.transitions
    @test only(
        transition for transition in concrete_model.transitions
        if transition.trigger === :SharedGo
    ).target === :SharedB

    @hsmdef mutable struct InvalidDiagramTargetSm end
    @statedef InvalidDiagramTargetSm :OnlyState

    @on_initial function (sm::InvalidDiagramTargetSm, ::Root)
        return Hsm.transition!(sm, :OnlyState)
    end

    @on_event function (sm::InvalidDiagramTargetSm, ::OnlyState, ::Bad, _)
        return Hsm.transition!(sm, :MissingState)
    end

    @test_throws Hsm.HsmStateError Hsm.diagram_model(InvalidDiagramTargetSm)
end
