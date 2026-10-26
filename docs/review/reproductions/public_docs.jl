using Test, Hsm
missing = [name for name in names(Hsm) if name ∉ (:Hsm, :ValSplit) && !Base.Docs.hasdoc(Hsm, name)]
@show missing
@test isempty(missing)
