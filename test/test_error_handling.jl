using Test
using Hsm

@testset "Error Handling" begin
    @testset "Custom Exception Types" begin
        # Test that our custom exception types work properly
        @test_throws Hsm.HsmMacroError throw(Hsm.HsmMacroError("Test error"))
        @test_throws Hsm.HsmStateError throw(Hsm.HsmStateError("Test error"))
        @test_throws Hsm.HsmEventError throw(Hsm.HsmEventError("Test error"))
    end

    @testset "@hsmdef Error Handling" begin
        # Test non-mutable struct error
        @test_throws LoadError try
            @eval @hsmdef struct NonMutableSm
                value::Int
            end
        catch e
            # Extract the original exception from the LoadError
            orig_e = e isa LoadError ? e.error : e
            @test occursin("must be explicitly declared as mutable", orig_e.msg)
            rethrow(e)
        end
    end

    @testset "@ancestor Error Handling" begin
        # Create a valid state machine for testing errors
        @hsmdef mutable struct ErrorTestSm
            value::Int
        end

        # Test with wrong number of arguments
        @test_throws LoadError try
            @eval @ancestor ErrorTestSm
        catch e
            # Extract the original exception from the LoadError
            orig_e = e isa LoadError ? e.error : e
            @test occursin("Expected exactly two arguments", orig_e.msg)
            rethrow(e)
        end

        # Test with invalid relationship format
        @test_throws LoadError try
            @eval @ancestor ErrorTestSm :StateA
        catch e
            # Extract the original exception from the LoadError
            orig_e = e isa LoadError ? e.error : e
            @test occursin("must be an expression with =>", orig_e.msg)
            rethrow(e)
        end

        # Test invalid statement in block
        @test_throws LoadError try
            @eval @ancestor ErrorTestSm begin
                :Invalid_Format
            end
        catch e
            # Extract the original exception from the LoadError
            orig_e = e isa LoadError ? e.error : e
            @test occursin("Invalid statement in block", orig_e.msg)
            rethrow(e)
        end

        # Test invalid relationship in block
        @test_throws LoadError try
            @eval @ancestor ErrorTestSm begin
                :StateA => :StateB => :StateC
            end
        catch e
            # Extract the original exception from the LoadError
            orig_e = e isa LoadError ? e.error : e
            @test occursin("Invalid relationship expression", orig_e.msg)
            rethrow(e)
        end
    end

    @testset "Process Arguments Error Handling" begin
        # Test macro with incorrect state argument form
        @test_throws LoadError try
            @eval @on_entry function (sm::ErrorTestSm, StateA)
                return nothing
            end
        catch e
            # Extract the original exception from the LoadError
            orig_e = e isa LoadError ? e.error : e
            @test occursin("State argument must be of the form", orig_e.msg)
            rethrow(e)
        end

        # Test macro with incorrect event argument form
        @test_throws LoadError try
            @eval @on_event function (sm::ErrorTestSm, ::StateA, EventX)
                return Hsm.EventHandled
            end
        catch e
            # Extract the original exception from the LoadError
            orig_e = e isa LoadError ? e.error : e
            @test occursin("Event argument must be of the form", orig_e.msg)
            rethrow(e)
        end

        # Test Any event without name
        @test_throws LoadError try
            @eval @on_event function (sm::ErrorTestSm, ::StateA, ::Any)
                return Hsm.EventHandled
            end
        catch e
            # Extract the original exception from the LoadError
            orig_e = e isa LoadError ? e.error : e
            @test occursin("When using ::Any for event type", orig_e.msg)
            rethrow(e)
        end
    end

    @testset "Ancestor Error for Undefined State" begin
        # Create a test state machine
        @hsmdef mutable struct AncestorErrorTestSm
            value::Int
        end

        # Define a partial ancestry
        @ancestor AncestorErrorTestSm :State_A => :Root

        sm = AncestorErrorTestSm(0)

        # Accessing an undefined state should raise HsmStateError
        # Don't need try/catch since we're testing if the function throws the correct exception
        @test_throws MethodError Hsm.ancestor(sm, Val(:Undefined_State))
    end
end
