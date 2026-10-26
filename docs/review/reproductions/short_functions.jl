using Hsm
@hsmdef mutable struct ScopeSm end
@statedef ScopeSm :A
@statedef ScopeSm :B
@on_initial function (sm::ScopeSm, ::Root)
    Hsm.transition!(sm, :A)
end
@on_event function (sm::ScopeSm, ::A, ::Short, other)
    helper(sm) = Hsm.transition!(sm, :A)
    helper(other)
end
@on_event function (sm::ScopeSm, ::A, ::Long, other)
    function helper(sm)
        Hsm.transition!(sm, :A)
    end
    helper(other)
end
for event in (:Short, :Long)
    sm, other = ScopeSm(), ScopeSm()
    Hsm.transition!(other, :B)
    try
        Hsm.dispatch!(sm, event, other)
        @show event Hsm.current(other)
    catch e
        showerror(stdout, e)
        println()
    end
end

using Test
source, other = ScopeSm(), ScopeSm()
Hsm.transition!(other, :B)
@test Hsm.dispatch!(source, :Short, other) === Hsm.EventHandled
@test Hsm.current(other) === :A
