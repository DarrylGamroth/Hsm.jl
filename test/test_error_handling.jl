using Test
using Hsm

@testset "Error Handling" begin
    @testset "Basic Error Checks" begin
        # Simple test to make sure the testset runs
        @test true
        
        # Test that the error() function exists and works
        @test_throws ErrorException error("Test error")
    end
end
