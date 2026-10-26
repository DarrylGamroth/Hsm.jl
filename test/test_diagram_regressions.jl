using Test, Hsm

module DiagramNameFixtures
using Hsm

@hsmdef mutable struct CollisionSm end
@statedef CollisionSm :__hsm_initial_Root
@statedef CollisionSm :__hsm_initial_Root_1
@statedef CollisionSm :Owner
@statedef CollisionSm :Inside :Owner
@statedef CollisionSm :__hsm_shallow_history_Owner
@statedef CollisionSm :__hsm_deep_history_Owner
@historydef CollisionSm :Owner DeepHistory() :Inside
@historydef CollisionSm :Owner ShallowHistory() :Inside
@on_initial function(sm::CollisionSm, ::Root)
    transition!(sm, :__hsm_initial_Root)
end
@on_initial function(sm::CollisionSm, ::Owner)
    transition!(sm, :Inside)
end
@on_event function(sm::CollisionSm, ::__hsm_initial_Root, ::Go, arg)
    transition!(sm, :Owner)
end
@on_event function(sm::CollisionSm, ::Inside, ::Deep, arg)
    transition_history!(sm, :Owner, DeepHistory())
end
@on_event function(sm::CollisionSm, ::Inside, ::Shallow, arg)
    transition_history!(sm, :Owner, ShallowHistory())
end

@hsmdef mutable struct TerminateCollisionSm end
@statedef TerminateCollisionSm :Start
@terminatedef TerminateCollisionSm :__hsm_initial_Root
@on_initial function(sm::TerminateCollisionSm, ::Root)
    transition!(sm, :Start)
end
@on_event function(sm::TerminateCollisionSm, ::Start, ::Stop, arg)
    transition!(sm, :__hsm_initial_Root)
end

@abstracthsmdef Family
@statedef Family :A
@statedef Family :B
@on_initial function(sm::Family, ::Root)
    transition!(sm, :A)
end
@on_event function(sm::Family, ::A, ::Tick, arg)
    transition!(sm, :B)
end
@hsmdef mutable struct Concrete <: Family end
@on_initial function(sm::Concrete, ::Root)
    transition!(sm, :B)
end
@on_event function(sm::Concrete, ::A, ::Tick, arg)
    transition!(sm, :A)
end
end

@testset "Diagram vertex identity and registration inventory" begin
    for machine in (DiagramNameFixtures.CollisionSm, DiagramNameFixtures.TerminateCollisionSm)
        model = diagram_model(machine)
        state_names = Set(state.name for state in model.states)
        pseudo_names = Set(vertex.name for vertex in model.pseudostates)
        @test isempty(intersect(state_names, pseudo_names))
        @test length(pseudo_names) == length(model.pseudostates)
        names = union(state_names, pseudo_names)
        @test all(edge -> edge.source in names && edge.target in names, model.transitions)
        aliases = Hsm._diagram_aliases(model)
        for format in (:plantuml, :mermaid)
            text = diagram(model; format)
            for edge in model.transitions
                edge.trigger_kind === :event || continue
                @test occursin("$(aliases[edge.source]) --> $(aliases[edge.target]) : $(edge.trigger)", text)
            end
        end
    end
    model = diagram_model(DiagramNameFixtures.CollisionSm)
    for (trigger, kind) in ((:Deep, :deep_history), (:Shallow, :shallow_history))
        incoming = only(edge for edge in model.transitions if edge.trigger === trigger)
        vertex = only(vertex for vertex in model.pseudostates if vertex.kind === kind)
        default = only(edge for edge in model.transitions if edge.source === vertex.name && edge.trigger_kind === :default)
        @test incoming.target === vertex.name
        @test default.target === :Inside
    end
    terminated = diagram_model(DiagramNameFixtures.TerminateCollisionSm)
    @test only(vertex for vertex in terminated.pseudostates if vertex.kind === :terminate).name === :__hsm_initial_Root

    # The documented model is a registration inventory, including overridden
    # declarations. Execution still uses Julia's concrete handler dispatch.
    inventory = diagram_model(DiagramNameFixtures.Concrete)
    @test current(DiagramNameFixtures.Concrete()) === :B
    @test Set(edge.target for edge in inventory.transitions if edge.trigger_kind === :initial) == Set((:A, :B))
    @test Set(edge.target for edge in inventory.transitions if edge.trigger === :Tick) == Set((:A, :B))
    for format in (:plantuml, :mermaid)
        @test occursin("overridden handlers", diagram(inventory; format))
    end
end
