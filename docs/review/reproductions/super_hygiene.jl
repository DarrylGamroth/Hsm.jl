using Hsm
@abstracthsmdef AbstractSuperSm
@hsmdef mutable struct SuperSm <: AbstractSuperSm
    seen::Any
end
@statedef AbstractSuperSm :A
@on_initial function (sm::AbstractSuperSm, ::Root)
    Hsm.transition!(sm, :A)
end
@on_event function (sm::AbstractSuperSm, ::A, ::Tick, arg)
    sm.seen = arg
    Hsm.EventHandled
end
@on_event function (sm::SuperSm, state::A, event::Tick, abstract_type)
    @super on_event sm state event abstract_type
end
sm = SuperSm(nothing)
Hsm.dispatch!(sm, :Tick, 123)
@show sm.seen

using Test
@test sm.seen === 123
