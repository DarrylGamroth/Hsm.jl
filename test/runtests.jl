using Test
using Hsm

@testset "Hsm.jl" begin
    include("test_core.jl")
    include("test_macros.jl")
    include("test_macro_helpers.jl")
    include("test_state_machine.jl")
    include("test_error_handling.jl")
    include("test_default_handlers.jl")
    include("test_on_event_kwargs.jl")
    include("test_any_state_handlers.jl")
end
