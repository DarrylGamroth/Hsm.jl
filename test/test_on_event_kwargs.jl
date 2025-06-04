using Test
using Hsm

@testset "on_event macro with function-based syntax" begin
    # Define a simple state machine for testing the macro
    @hsmdef mutable struct KwargTestSm
        log::Vector{String}
        handled_events::Dict{Symbol,Symbol}
    end

    # Define state hierarchy
    @ancestor KwargTestSm begin
        :State_Top => :Root
        :State_S1 => :State_Top
        :State_S2 => :State_Top
    end

    @on_initial function (sm::KwargTestSm, ::Root)
        push!(sm.log, "Initial handler for Root")
        return Hsm.transition!(sm, :State_Top)
    end

    @on_initial function (sm::KwargTestSm, ::State_Top)
        push!(sm.log, "Initial handler for State_Top")
        return Hsm.transition!(sm, :State_S1)
    end

    # Test with unnamed parameters
    @on_event function (sm::KwargTestSm, ::State_S1, ::Event_A)
        push!(sm.log, "Handler with unnamed parameters: Event_A in State_S1")
        sm.handled_events[:Event_A] = :State_S1
        return Hsm.EventHandled
    end

    # Test with named parameters
    @on_event function (sm::KwargTestSm, state::State_S1, event::Event_B)
        push!(sm.log, "Handler with named parameters: $(event) in $(state)")
        sm.handled_events[event] = state
        return Hsm.EventHandled
    end

    # Test with Any event (must use named parameter)
    @on_event function (sm::KwargTestSm, ::State_S2, event::Any, arg)
        push!(sm.log, "Default handler in State_S2 for event: $(event)")
        sm.handled_events[event] = :State_S2
        return Hsm.EventHandled
    end

    # Create and initialize the state machine
    sm = KwargTestSm(String[], Dict{Symbol,Symbol}())
    Hsm.current!(sm, :State_S1)

    # Test handler with unnamed parameters
    Hsm.dispatch!(sm, :Event_A)
    @test sm.log[end] == "Handler with unnamed parameters: Event_A in State_S1"
    @test sm.handled_events[:Event_A] == :State_S1

    # Test handler with named parameters
    Hsm.dispatch!(sm, :Event_B)
    @test sm.log[end] == "Handler with named parameters: Event_B in State_S1"
    @test sm.handled_events[:Event_B] == :State_S1

    # Set current state to S2 to test default handler
    Hsm.current!(sm, :State_S2)

    # Test handler with Any event type
    Hsm.dispatch!(sm, :Event_C)
    @test sm.log[end] == "Default handler in State_S2 for event: Event_C"
    @test sm.handled_events[:Event_C] == :State_S2

    # Test another event with the default handler
    Hsm.dispatch!(sm, :Event_D)
    @test sm.log[end] == "Default handler in State_S2 for event: Event_D"
    @test sm.handled_events[:Event_D] == :State_S2
end
