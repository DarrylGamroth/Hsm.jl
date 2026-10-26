using Hsm
@hsmdef Base.@kwdef mutable struct KwParamSm{T}
    x::T = one(T)
end
@statedef KwParamSm :A
@on_initial function (sm::KwParamSm, ::Root)
    Hsm.transition!(sm, :A)
end
for construct in (() -> KwParamSm(x=1), () -> KwParamSm{Int}())
    try
        sm = construct()
        @show typeof(sm) sm.x Hsm.current(sm)
    catch e
        showerror(stdout, e)
        println()
    end
end

using Test
@test Hsm.current(KwParamSm{Int}()) === :A
