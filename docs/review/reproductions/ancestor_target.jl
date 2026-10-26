using Hsm
@hsmdef mutable struct AncestorTargetSm
    log::Vector{Symbol}
end
@statedef AncestorTargetSm :Owner
@statedef AncestorTargetSm :Leaf :Owner
@statedef AncestorTargetSm :Done
@on_initial function (sm::AncestorTargetSm, ::Root)
    Hsm.transition!(sm, :Owner)
end
@on_initial function (sm::AncestorTargetSm, ::Owner)
    push!(sm.log, :default)
    Hsm.transition!(sm, :Leaf)
end
@on_event function (sm::AncestorTargetSm, ::Leaf, ::Up, arg)
    Hsm.transition!(sm, :Owner)
end
@on_completion function (sm::AncestorTargetSm, ::Owner)
    push!(sm.log, :completed)
    Hsm.transition!(sm, :Done)
end
sm=AncestorTargetSm(Symbol[])
empty!(sm.log)
println("result=",Hsm.dispatch!(sm,:Up)," current=",Hsm.current(sm)," log=",sm.log)

using Test
@test Hsm.current(sm) === :Done
@test sm.log == [:completed]
