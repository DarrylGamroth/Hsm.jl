using Test
using Hsm

module DiagramOverridesRepro
using Hsm
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

model = diagram_model(DiagramOverridesRepro.Concrete)
initial_targets = [edge.target for edge in model.transitions if edge.trigger_kind === :initial]
tick_targets = [edge.target for edge in model.transitions if edge.trigger === :Tick]
@show current(DiagramOverridesRepro.Concrete()) initial_targets tick_targets
# MAIN-012 was adjudicated as an inventory contract clarification. The original
# effective-graph oracle failed in the baseline log; inherited registrations are
# deliberately retained and documented in the repaired tooling contract.
@test current(DiagramOverridesRepro.Concrete()) === :B
@test Set(initial_targets) == Set((:A, :B))
@test Set(tick_targets) == Set((:A, :B))
@test occursin("overridden handlers", diagram(model; format=:plantuml))
@test occursin("overridden handlers", diagram(model; format=:mermaid))
