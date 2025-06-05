using Test
using Hsm

@testset "Default Event Handlers" begin
    # Define a simple state machine for testing default handlers
    @hsmdef mutable struct DefaultHandlerTestSm
        log::Vector{String}
        handled::Bool
    end

    # Define state hierarchy
    @ancestor DefaultHandlerTestSm begin
        :StateA => :Root
        :StateB => :StateA
        :StateC => :StateA
    end

    # Initialize to StateB
    @on_initial function (sm::DefaultHandlerTestSm, ::Root)
        return Hsm.transition!(sm, :StateB) do
            push!(sm.log, "Initial transition to StateB")
        end
    end

    # Add on_initial handler for StateA (non-leaf state)
    @on_initial function (sm::DefaultHandlerTestSm, ::StateA)
        return Hsm.transition!(sm, :StateB) do
            push!(sm.log, "StateA initial handler transitions to StateB")
        end
    end

    # Default handler for StateB - should handle any event
    @on_event function (sm::DefaultHandlerTestSm, ::StateB, event::Any, arg)
        push!(sm.log, "Default handler for StateB received: $(event)")
        sm.handled = true
        return Hsm.EventHandled
    end

    # Regular handler for specific event in StateB
    @on_event function (sm::DefaultHandlerTestSm, ::StateB, ::SpecificEvent, arg)
        push!(sm.log, "Specific handler for SpecificEvent in StateB")
        return Hsm.EventHandled
    end

    # Default handler for StateA - should only be called if child states don't handle
    @on_event function (sm::DefaultHandlerTestSm, ::StateA, event::Any, arg)
        push!(sm.log, "Default handler for StateA received: $(event)")
        sm.handled = true
        return Hsm.EventHandled
    end

    # StateC has no handlers, so events should propagate to StateA

    # Test 1: Basic default handler in current state
    @testset "Default handler in current state" begin
        sm = DefaultHandlerTestSm(String[], false)

        # Clear log after initialization
        sm.log = String[]
        sm.handled = false

        # Send an arbitrary event that has no specific handler
        result = Hsm.dispatch!(sm, :UnknownEvent)

        @test result == Hsm.EventHandled
        @test sm.handled == true
        @test length(sm.log) == 1
        @test sm.log[1] == "Default handler for StateB received: UnknownEvent"
    end

    # Test 2: Specific handler should take precedence over default
    @testset "Specific handler precedence" begin
        sm = DefaultHandlerTestSm(String[], false)

        # Clear log after initialization
        sm.log = String[]
        sm.handled = false

        # Send event that has a specific handler
        result = Hsm.dispatch!(sm, :SpecificEvent)

        @test result == Hsm.EventHandled
        @test sm.handled == false # Specific handler doesn't set this flag
        @test length(sm.log) == 1
        @test sm.log[1] == "Specific handler for SpecificEvent in StateB"
    end

    # Test 3: Default handler in parent state
    @testset "Default handler in parent state" begin
        sm = DefaultHandlerTestSm(String[], false)

        # Transition to StateC which has no handlers
        Hsm.transition!(sm, :StateC)

        # Clear log after transition
        sm.log = String[]
        sm.handled = false

        # Send event - should be handled by StateA's default handler
        result = Hsm.dispatch!(sm, :AnotherEvent)

        @test result == Hsm.EventHandled
        @test sm.handled == true
        @test length(sm.log) == 1
        @test sm.log[1] == "Default handler for StateA received: AnotherEvent"
    end

    # Test 4: Multiple event types with default handler
    @testset "Multiple event types with default handler" begin
        sm = DefaultHandlerTestSm(String[], false)

        # Send three different events to the same state
        events = [:Event1, :Event2, :Event3]

        for event in events
            # Clear log before each dispatch
            sm.log = String[]
            sm.handled = false

            result = Hsm.dispatch!(sm, event)

            @test result == Hsm.EventHandled
            @test sm.handled == true
            @test length(sm.log) == 1
            @test sm.log[1] == "Default handler for StateB received: $event"
        end
    end
end
