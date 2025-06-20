"""
This file contains an example of a hierarchical state machine implemented using the Hsm.jl library, using macros for all boilerplate.
See example.png for a graphical representation of the state machine.
"""

using Revise
using BenchmarkTools
using Hsm
using ValSplit
using Logging

# Set the global log level to debug so @debug statements are shown
Logging.global_logger(ConsoleLogger(stderr, Logging.Debug))

# Define the state machine using the macro
@hsmdef mutable struct HsmTest
    buf::Vector{UInt8}
    foo::Int
end

# Define the ancestor relationships using the macro
@statedef HsmTest :State_S
@statedef HsmTest :State_S1 :State_S
@statedef HsmTest :State_S11 :State_S1
@statedef HsmTest :State_S2 :State_S
@statedef HsmTest :State_S21 :State_S2
@statedef HsmTest :State_S211 :State_S21

# Initial handler for Root
@on_initial function (sm::HsmTest, ::Root)
    @debug "Entering initial handler for Root"
    handled = Hsm.transition!(sm, :State_S2) do
        @debug "Transitioning from Root to State_S2 (initial)"
        sm.foo = 0
    end
    return handled
end

# Initial handler for State_S
@on_initial function (sm::HsmTest, ::State_S)
    @debug "Entering initial handler for State_S"
    Hsm.transition!(sm, :State_S11) do
        @debug "Transitioning from State_S to State_S11 (initial)"
    end
end

# Entry/exit for State_S
@on_entry function (sm::HsmTest, ::State_S)
    @debug "Entering State_S"
    # Do something when entering the state
end
@on_exit function (sm::HsmTest, ::State_S)
    @debug "Exiting State_S"
    # Do something when exiting the state
end

# Event handlers for State_S
@on_event function (sm::HsmTest, ::State_S, ::Event_E, arg)
    @debug "Handling Event_E in State_S"
    Hsm.transition!(sm, :State_S11) do
        @debug "Transitioning from State_S to State_S11 on Event_E"
    end
end

@on_event function (sm::HsmTest, ::State_S, ::Event_I, arg)
    @debug "Handling Event_I in State_S"
    if sm.foo == 1
        sm.foo = 0
        return Hsm.EventHandled
    else
        return Hsm.EventNotHandled
    end
end

# Initial handler for State_S1
@on_initial function (sm::HsmTest, ::State_S1)
    @debug "Entering initial handler for State_S1"
    Hsm.transition!(sm, :State_S11) do
        @debug "Transitioning from State_S1 to State_S11 (initial)"
    end
end

# Event handlers for State_S1
@on_event function (sm::HsmTest, ::State_S1, ::Event_A, arg)
    @debug "Handling Event_A in State_S1"
    Hsm.transition!(sm, :State_S1) do
        @debug "Transitioning from State_S1 to State_S1 on Event_A"
    end
end
@on_event function (sm::HsmTest, ::State_S1, ::Event_B, arg)
    @debug "Handling Event_B in State_S1"
    Hsm.transition!(sm, :State_S11) do
        @debug "Transitioning from State_S1 to State_S11 on Event_B"
    end
end
@on_event function (sm::HsmTest, ::State_S1, ::Event_C, arg)
    @debug "Handling Event_C in State_S1"
    Hsm.transition!(sm, :State_S2) do
        @debug "Transitioning from State_S1 to State_S2 on Event_C"
    end
end
@on_event function (sm::HsmTest, ::State_S1, ::Event_D, arg)
    @debug "Handling Event_D in State_S1"
    if sm.foo == 0
        return Hsm.transition!(sm, :State_S1) do
            @debug "Transitioning from State_S1 to State_S1 on Event_D (foo == 0)"
            sm.foo = 0
        end
    else
        return Hsm.EventNotHandled
    end
end
@on_event function (sm::HsmTest, ::State_S1, ::Event_F, arg)
    @debug "Handling Event_F in State_S1"
    Hsm.transition!(sm, :State_S211) do
        @debug "Transitioning from State_S1 to State_S211 on Event_F"
    end
end
@on_event function (sm::HsmTest, ::State_S1, ::Event_I, arg)
    @debug "Handling Event_I in State_S1"
    return Hsm.EventHandled
end

# Event handlers for State_S11
@on_event function (sm::HsmTest, ::State_S11, ::Event_D, arg)
    @debug "Handling Event_D in State_S11"
    if sm.foo == 1
        return Hsm.transition!(sm, :State_S1) do
            @debug "Transitioning from State_S11 to State_S1 on Event_D (foo == 1)"
            sm.foo = 0
        end
    else
        return Hsm.EventNotHandled
    end
end
@on_event function (sm::HsmTest, ::State_S11, ::Event_G, arg)
    @debug "Handling Event_G in State_S11"
    Hsm.transition!(sm, :State_S211) do
        @debug "Transitioning from State_S11 to State_S211 on Event_G"
    end
end
@on_event function (sm::HsmTest, ::State_S11, ::Event_H, arg)
    @debug "Handling Event_H in State_S11"
    Hsm.transition!(sm, :State_S) do
        @debug "Transitioning from State_S11 to State_S on Event_H"
    end
end

# Initial handler for State_S2
@on_initial function (sm::HsmTest, ::State_S2)
    @debug "Entering initial handler for State_S2"
    Hsm.transition!(sm, :State_S211) do
        @debug "Transitioning from State_S2 to State_S211 (initial)"
    end
end

# Event handlers for State_S2
@on_event function (sm::HsmTest, ::State_S2, ::Event_C, arg)
    @debug "Handling Event_C in State_S2"
    Hsm.transition!(sm, :State_S1) do
        @debug "Transitioning from State_S2 to State_S1 on Event_C"
    end
end
@on_event function (sm::HsmTest, ::State_S2, ::Event_F, arg)
    @debug "Handling Event_F in State_S2"
    Hsm.transition!(sm, :State_S11) do
        @debug "Transitioning from State_S2 to State_S11 on Event_F"
    end
end
@on_event function (sm::HsmTest, ::State_S2, ::Event_I, arg)
    @debug "Handling Event_I in State_S2"
    if sm.foo == 0
        sm.foo = 1
        return Hsm.EventHandled
    else
        return Hsm.EventNotHandled
    end
end

# Initial handler for State_S21
@on_initial function (sm::HsmTest, ::State_S21)
    @debug "Entering initial handler for State_S21"
    Hsm.transition!(sm, :State_S211) do
        @debug "Transitioning from State_S21 to State_S211 (initial)"
    end
end

# Event handlers for State_S21
@on_event function (sm::HsmTest, ::State_S21, ::Event_A, arg)
    @debug "Handling Event_A in State_S21"
    Hsm.transition!(sm, :State_S21) do
        @debug "Transitioning from State_S21 to State_S21 on Event_A"
    end
end
@on_event function (sm::HsmTest, ::State_S21, ::Event_B, arg)
    @debug "Handling Event_B in State_S21"
    Hsm.transition!(sm, :State_S211) do
        @debug "Transitioning from State_S21 to State_S211 on Event_B"
    end
end
@on_event function (sm::HsmTest, ::State_S21, ::Event_G, arg)
    @debug "Handling Event_G in State_S21"
    Hsm.transition!(sm, :State_S11) do
        @debug "Transitioning from State_S21 to State_S11 on Event_G"
    end
end

# Event handlers for State_S211
@on_event function (sm::HsmTest, ::State_S211, ::Event_D, arg)
    @debug "Handling Event_D in State_S211"
    Hsm.transition!(sm, :State_S21) do
        @debug "Transitioning from State_S211 to State_S21 on Event_D"
    end
end
@on_event function (sm::HsmTest, ::State_S211, ::Event_H, arg)
    @debug "Handling Event_H in State_S211"
    Hsm.transition!(sm, :State_S) do
        @debug "Transitioning from State_S211 to State_S on Event_H"
    end
end

# Test and random event functions
function test(sm::HsmTest)
    event_sequence = (
        :Event_A, :Event_B, :Event_D, :Event_E, :Event_I, :Event_F, :Event_I, :Event_I, :Event_F,
        :Event_A, :Event_B, :Event_D, :Event_D, :Event_E, :Event_G, :Event_H, :Event_H, :Event_C,
        :Event_G, :Event_C, :Event_C
    )
    for event in event_sequence
        Hsm.dispatch!(sm, event)
    end
end

function random_event()
    events = (:Event_A, :Event_B, :Event_C, :Event_D, :Event_E, :Event_F, :Event_G, :Event_H, :Event_I)
    return rand(events)
end

function test2(sm::HsmTest)
    for _ in 1:1000
        event = random_event()
        Hsm.dispatch!(sm, event)
    end
    nothing
end

hsm = HsmTest(buf=UInt8[], foo=0)
test(hsm)

function profile_test(hsm, n)
    for _ = 1:n
        test2(hsm)
    end
end
