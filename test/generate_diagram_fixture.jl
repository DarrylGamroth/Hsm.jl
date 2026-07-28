using Hsm

include("diagram_fixture.jl")
using .DiagramFixture: DiagramTestSm

length(ARGS) == 2 || error(
    "usage: julia --project=. test/generate_diagram_fixture.jl FORMAT OUTPUT",
)

format = Symbol(ARGS[1])
format in (:plantuml, :mermaid) ||
    error("FORMAT must be plantuml or mermaid")

output = abspath(ARGS[2])
mkpath(dirname(output))
open(output, "w") do io
    Hsm.diagram(io, DiagramTestSm; format=format)
end
