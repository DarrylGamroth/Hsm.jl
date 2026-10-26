using Test
using Hsm
@abstracthsmdef WhereFamily
@hsmdef mutable struct WhereSm <: WhereFamily end
@statedef WhereFamily :A
@on_entry function(sm::M, ::A) where {M<:WhereFamily}
    nothing
end
@test Hsm.on_entry!(WhereSm(), Val(:A)) === nothing
