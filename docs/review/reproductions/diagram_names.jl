using Test
using Hsm
module DiagramNamesRepro
using Hsm
@hsmdef mutable struct Machine end
@statedef Machine :__hsm_initial_Root
@statedef Machine :B
@on_initial function(sm::Machine, ::Root)
    transition!(sm, :__hsm_initial_Root)
end
@on_event function(sm::Machine, ::__hsm_initial_Root, ::Go, arg)
    transition!(sm, :B)
end
end
model = diagram_model(DiagramNamesRepro.Machine)
text = diagram(model)
@show text
@test count(line -> occursin("[*] -->", line), split(text, Char(10))) == 1
@test length([edge for edge in model.transitions if edge.source == edge.target]) == 0
