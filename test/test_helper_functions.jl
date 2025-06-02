using Test
using Hsm

@testset "Helper Functions" begin
    @testset "extract_sm_arg" begin
        # Access the internal function
        extract_sm_arg = getfield(Hsm, :extract_sm_arg)
        
        # Test with simple argument
        arg_tuple = Expr(:tuple, :sm)
        smarg, smtype = extract_sm_arg(arg_tuple, "Test")
        @test smarg === :sm
        @test smtype === :Any
        
        # Test with typed argument
        arg_tuple = Expr(:tuple, Expr(:(::), :sm, :TestType))
        smarg, smtype = extract_sm_arg(arg_tuple, "Test")
        @test smarg === :sm
        @test smtype === :TestType
    end
end
