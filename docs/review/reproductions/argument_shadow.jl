using Hsm
@hsmdef mutable struct ArgShadowSm end
@statedef ArgShadowSm :A
@statedef ArgShadowSm :B
@on_initial function (sm::ArgShadowSm, ::Root)
    Hsm.transition!(sm, :A)
end
@on_event function (sm::ArgShadowSm, ::A, ::Tick, transition!)
    transition!(sm, :B)
end
calls = Ref(0)
callback = function (sm, target)
    calls[] += 1
    Hsm.EventHandled
end
sm = ArgShadowSm()
Hsm.dispatch!(sm, :Tick, callback)
@show calls[] Hsm.current(sm)

using Test
@test calls[] == 1
@test Hsm.current(sm) === :A
