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
        :StateA => Hsm.Root
        :StateB => :StateA
        :StateC => :StateA
    end

    # Initialize to StateB
    @on_initial :Root function(sm::DefaultHandlerTestSm)
        return Hsm.transition!(sm, :StateB) do
            push!(sm.log, "Initial transition to StateB")
        end
    end

    # Default handler for StateB - should handle any event
    @on_event :StateB Any function(sm::DefaultHandlerTestSm, arg)
        push!(sm.log, "Default handler for StateB received: $(Hsm.event(sm))")
        sm.handled = true
        return Hsm.EventHandled
    end

    # Regular handler for specific event in StateB
    @on_event :StateB :SpecificEvent function(sm::DefaultHandlerTestSm, arg)
        push!(sm.log, "Specific handler for SpecificEvent in StateB")
        return Hsm.EventHandled
    end

    # Default handler for StateA - should only be called if child states don't handle
    @on_event :StateA Any function(sm::DefaultHandlerTestSm, arg)
        push!(sm.log, "Default handler for StateA received: $(Hsm.event(sm))")
        sm.handled = true
        return Hsm.EventHandled
    end

    # StateC has no handlers, so events should propagate to StateA

    # Test 1: Basic default handler in current state
    @testset "Default handler in current state" begin
        sm = DefaultHandlerTestSm(String[], false)
        Hsm.initialize!(sm)
        
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
        Hsm.initialize!(sm)
        
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
        Hsm.initialize!(sm)
        
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
        Hsm.initialize!(sm)
        
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
