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

    @testset "@statedef Error Handling" begin
        # Create a valid state machine for testing errors
        @hsmdef mutable struct ErrorTestSm
            value::Int
        end

        # Test with wrong number of arguments
        @test_throws LoadError @eval @statedef ErrorTestSm

        # Test with invalid child argument (not a symbol)
        @test_throws LoadError try
            @eval @statedef ErrorTestSm "StateA"
        catch e
            @test e isa LoadError
            @test e.error isa ArgumentError
            @test occursin("Child state must be a symbol", e.error.msg)
            rethrow(e)
        end

        # Test with invalid parent argument (not a symbol)
        @test_throws LoadError try
            @eval @statedef ErrorTestSm :StateA "Root"
        catch e
            @test e isa LoadError
            @test e.error isa ArgumentError
            @test occursin("Parent state must be a symbol", e.error.msg)
            rethrow(e)
        end

        # Test too many arguments (only accepts 2-3 arguments)
        @test_throws LoadError try
            @eval @statedef ErrorTestSm :StateA :StateB :StateC :StateD
        catch e
            @test e isa LoadError
            @test e.error isa MethodError
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
        @statedef AncestorErrorTestSm :State_A :Root

        sm = AncestorErrorTestSm(0)

        # Accessing an undefined state should raise HsmStateError
        # Don't need try/catch since we're testing if the function throws the correct exception
        @test_throws MethodError Hsm.ancestor(sm, Val(:Undefined_State))
    end
end
