using Test
using Hsm

@testset "on_event macro with kwargs" begin
    # Define a simple state machine for testing the macro
    @hsmdef mutable struct KwargTestSm
        log::Vector{String}
        handled_events::Dict{Symbol,Symbol}
    end

    # Define state hierarchy
    @ancestor KwargTestSm begin
        :State_Top => Hsm.Root
        :State_S1 => :State_Top
        :State_S2 => :State_Top
    end

    @on_initial Hsm.Root function (sm::KwargTestSm)
        push!(sm.log, "Initial handler for Root")
        return Hsm.transition!(sm, :State_Top)
    end

    @on_initial :State_Top function (sm::KwargTestSm)
        push!(sm.log, "Initial handler for State_Top")
        return Hsm.transition!(sm, :State_S1)
    end

    # Test traditional syntax
    @on_event :State_S1 :Event_A function (sm::KwargTestSm)
        push!(sm.log, "Traditional handler: Event_A in State_S1")
        sm.handled_events[:Event_A] = :State_S1
        return Hsm.EventHandled
    end

    # Test kwargs syntax - accessing state and event values
    @on_event state = :State_S1 event = :Event_B function (sm::KwargTestSm)
        push!(sm.log, "Kwargs handler: $(event) in $(state)")
        sm.handled_events[event] = state
        return Hsm.EventHandled
    end

    # Test kwargs syntax with Any event
    @on_event state = :State_S2 event = Any function (sm::KwargTestSm, arg)
        push!(sm.log, "Default handler in $(state) for event: $(event)")
        sm.handled_events[event] = state
        return Hsm.EventHandled
    end

    # Create and initialize the state machine
    sm = KwargTestSm(String[], Dict{Symbol,Symbol}())
    Hsm.initialize!(sm)
    Hsm.current!(sm, :State_S1)

    # Test traditional handler
    Hsm.dispatch!(sm, :Event_A)
    @test sm.log[end] == "Traditional handler: Event_A in State_S1"
    @test sm.handled_events[:Event_A] == :State_S1

    # Test kwargs handler with explicit event
    Hsm.dispatch!(sm, :Event_B)
    @test sm.log[end] == "Kwargs handler: Event_B in State_S1"
    @test sm.handled_events[:Event_B] == :State_S1

    # Set current state to S2 to test default handler
    Hsm.current!(sm, :State_S2)

    # Test kwargs handler with default event handling
    Hsm.dispatch!(sm, :Event_C)
    @test sm.log[end] == "Default handler in State_S2 for event: Event_C"
    @test sm.handled_events[:Event_C] == :State_S2

    # Test another event with the default handler
    Hsm.dispatch!(sm, :Event_D)
    @test sm.log[end] == "Default handler in State_S2 for event: Event_D"
    @test sm.handled_events[:Event_D] == :State_S2
end
