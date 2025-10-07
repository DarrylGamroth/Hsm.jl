using Test
using Hsm
using ValSplit

@testset "Hsm.jl" begin
    include("test_core.jl")
    include("test_macros.jl")
    include("test_macro_expansion.jl")
    include("test_hsmdef_edge_cases.jl")
    include("test_macro_helpers.jl")
    include("test_state_machine.jl")
    include("test_error_handling.jl")
    include("test_default_handlers.jl")
    include("test_on_event_kwargs.jl")
    include("test_any_state_handlers.jl")
    include("test_allocation_tests_alloccheck.jl")
    include("test_abstract_type.jl")
    include("test_docstrings.jl")
    include("test_super_macro.jl")
end
