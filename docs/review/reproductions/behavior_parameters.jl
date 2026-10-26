using Hsm
@hsmdef mutable struct ParamBehaviorSm{T}
    value::T
end
@statedef ParamBehaviorSm :A
@finaldef ParamBehaviorSm{Float64} :A
@on_initial function (sm::ParamBehaviorSm, ::Root)
    Hsm.transition!(sm, :A)
end
@on_entry function (sm::ParamBehaviorSm{Int}, ::A)
    sm.value += 1
end
for value in (1, 1.0)
    try
        sm = ParamBehaviorSm(value)
        @show typeof(sm) sm.value Hsm.current(sm) Hsm.iscomplete(sm)
    catch e
        showerror(stdout, e)
        println()
    end
end

using Test
@test Hsm.iscomplete(ParamBehaviorSm(1.0))
