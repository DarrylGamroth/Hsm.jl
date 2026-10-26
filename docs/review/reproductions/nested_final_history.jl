using Hsm
@hsmdef mutable struct NestedFinalHistorySm end
@statedef NestedFinalHistorySm :Outer
@statedef NestedFinalHistorySm :Initial :Outer
@statedef NestedFinalHistorySm :Branch :Outer
@statedef NestedFinalHistorySm :Leaf :Branch
@finaldef NestedFinalHistorySm :Finished :Branch
@statedef NestedFinalHistorySm :Outside
@historydef NestedFinalHistorySm :Outer
@historydef NestedFinalHistorySm :Branch
@on_initial function (sm::NestedFinalHistorySm, ::Root)
    Hsm.transition!(sm, :Outer)
end
@on_initial function (sm::NestedFinalHistorySm, ::Outer)
    Hsm.transition!(sm, :Initial)
end
@on_initial function (sm::NestedFinalHistorySm, ::Branch)
    Hsm.transition!(sm, :Leaf)
end
@on_event function (sm::NestedFinalHistorySm, ::Initial, ::Start, arg)
    Hsm.transition!(sm, :Branch)
end
@on_event function (sm::NestedFinalHistorySm, ::Leaf, ::Finish, arg)
    Hsm.transition!(sm, :Finished)
end
@on_event function (sm::NestedFinalHistorySm, ::Outer, ::Leave, arg)
    Hsm.transition!(sm, :Outside)
end
@on_event function (sm::NestedFinalHistorySm, ::Outside, ::Recall, arg)
    Hsm.transition_history!(sm, :Outer, Hsm.ShallowHistory())
end
sm=NestedFinalHistorySm()
for event in (:Start,:Finish,:Leave)
    println(event," => ",Hsm.dispatch!(sm,event)," ",Hsm.current(sm))
end
println("history_outer=",Hsm._history_value(sm,Val(:Outer))," history_branch=",Hsm._history_value(sm,Val(:Branch)))
println("Recall => ",Hsm.dispatch!(sm,:Recall)," ",Hsm.current(sm))

using Test
@test Hsm.current(sm) === :Leaf
