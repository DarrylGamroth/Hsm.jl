"""
This file contains an example of a hierarchical state machine implemented using the Hsm.jl library.
See example.png for a graphical representation of the state machine.
"""

using Revise
using BenchmarkTools

using Hsm
using ValSplit

# Define the state machine
mutable struct HsmTest
    # Variables used by the  interface
    current::Symbol
    source::Symbol

    # State machine specific variables. For instance this buffer could be used to store the event data
    buf::Vector{UInt8}
    foo::Int

    function HsmTest()
        sm = new()

        # Initialize the state machine
        Hsm.initialize!(sm)
        return sm
    end
end

# Implement the interface
Hsm.current(sm::HsmTest) = sm.current
Hsm.current!(sm::HsmTest, s::Symbol) = sm.current = s
Hsm.source(sm::HsmTest) = sm.source
Hsm.source!(sm::HsmTest, s::Symbol) = sm.source = s

# Implement the ancestor interface for each state
Hsm.ancestor(::HsmTest, ::Val{:State_S}) = Hsm.Root
Hsm.ancestor(::HsmTest, ::Val{:State_S1}) = :State_S
Hsm.ancestor(::HsmTest, ::Val{:State_S11}) = :State_S1
Hsm.ancestor(::HsmTest, ::Val{:State_S2}) = :State_S
Hsm.ancestor(::HsmTest, ::Val{:State_S21}) = :State_S2
Hsm.ancestor(::HsmTest, ::Val{:State_S211}) = :State_S21

# Define a dispatch function. Custom dispatch functions can be defined for each state machine
function dispatch!(sm::HsmTest, event, arg=nothing)
    #print("$(event) - ")
    Hsm.dispatch!(sm, event, arg)
    #print("\n")
end

# Globally override default handlers
# @valsplit Hsm.on_entry!(sm, Val(state::Symbol)) = #print("$(state)-ENTRY;")
# @valsplit Hsm.on_exit!(sm, Val(state::Symbol)) = #print("$(state)-EXIT;")

############

function Hsm.on_initial!(sm::HsmTest, state::Val{Hsm.Root})
    handled = Hsm.transition!(sm, :State_S2) do
        # Do something on the transition
        #print("$(state)-INIT;")
        sm.foo = 0
    end
    #print("\n")
    return handled
end

##############

Hsm.on_initial!(sm::HsmTest, state::Val{:State_S}) =
    Hsm.transition!(sm, :State_S11) do
        #print("$(state)-INIT;")
    end

# Example of how to implement on_entry! for a state
function Hsm.on_entry!(sm::HsmTest, state::Val{:State_S})
    # Do something when entering the state
end

# Example of how to implement on_exit! for a state
function Hsm.on_exit!(sm::HsmTest, state::Val{:State_S})
    # Do something when exiting the state
end

Hsm.on_event!(sm::HsmTest, state::Val{:State_S}, event::Val{:Event_E}, arg) =
    # transition! returns EventHandled if the transition is successful
    Hsm.transition!(sm, :State_S11) do
        #print("$(state)-$(event);")
    end

function Hsm.on_event!(sm::HsmTest, state::Val{:State_S}, event::Val{:Event_I}, arg)
    # Depending on the guard condition foo, the event can be handled or not
    if sm.foo == 1
        #print("$(state)-$(event);")
        sm.foo = 0
        return Hsm.EventHandled
    else
        return Hsm.EventNotHandled
    end
end

#########

Hsm.on_initial!(sm::HsmTest, state::Val{:State_S1}) =
    Hsm.transition!(sm, :State_S11) do
        #print("$(state)-INIT;")
    end

Hsm.on_event!(sm::HsmTest, state::Val{:State_S1}, event::Val{:Event_A}, arg) =
    Hsm.transition!(sm, :State_S1) do
        #print("$(state)-$(event);")
    end

Hsm.on_event!(sm::HsmTest, state::Val{:State_S1}, event::Val{:Event_B}, arg) =
    Hsm.transition!(sm, :State_S11) do
        #print("$(state)-$(event);")
    end

Hsm.on_event!(sm::HsmTest, state::Val{:State_S1}, event::Val{:Event_C}, arg) =
    Hsm.transition!(sm, :State_S2) do
        #print("$(state)-$(event);")
    end

function Hsm.on_event!(sm::HsmTest, state::Val{:State_S1}, event::Val{:Event_D}, arg)
    if sm.foo == 0
        return Hsm.transition!(sm, :State_S1) do
            #print("$(state)-$(event);")
            sm.foo = 0
        end
    else
        return Hsm.EventNotHandled
    end
end

Hsm.on_event!(sm::HsmTest, state::Val{:State_S1}, event::Val{:Event_F}, arg) =
    Hsm.transition!(sm, :State_S211) do
        #print("$(state)-$(event);")
    end

function Hsm.on_event!(sm::HsmTest, state::Val{:State_S1}, event::Val{:Event_I}, arg)
    #print("$(state)-$(event);")
    return Hsm.EventHandled
end

#############

function Hsm.on_event!(sm::HsmTest, state::Val{:State_S11}, event::Val{:Event_D}, arg)
    if sm.foo == 1
        return Hsm.transition!(sm, :State_S1) do
            #print("$(state)-$(event);")
            sm.foo = 0
        end
    else
        return Hsm.EventNotHandled
    end
end

Hsm.on_event!(sm::HsmTest, state::Val{:State_S11}, event::Val{:Event_G}, arg) =
    Hsm.transition!(sm, :State_S211) do
        #print("$(state)-$(event);")
    end

Hsm.on_event!(sm::HsmTest, state::Val{:State_S11}, event::Val{:Event_H}, arg) =
    Hsm.transition!(sm, :State_S) do
        #print("$(state)-$(event);")
    end

######

Hsm.on_initial!(sm::HsmTest, state::Val{:State_S2}) =
    Hsm.transition!(sm, :State_S211) do
        #print("$(state)-INIT;")
    end

Hsm.on_event!(sm::HsmTest, state::Val{:State_S2}, event::Val{:Event_C}, arg) =
    Hsm.transition!(sm, :State_S1) do
        #print("$(state)-$(event);")
    end

Hsm.on_event!(sm::HsmTest, state::Val{:State_S2}, event::Val{:Event_F}, arg) =
    Hsm.transition!(sm, :State_S11) do
        #print("$(state)-$(event);")
    end

function Hsm.on_event!(sm::HsmTest, state::Val{:State_S2}, event::Val{:Event_I}, arg)
    if sm.foo == 0
        #print("$(state)-$(event);")
        sm.foo = 1
        return Hsm.EventHandled
    else
        return Hsm.EventNotHandled
    end
end

########

Hsm.on_initial!(sm::HsmTest, state::Val{:State_S21}) =
    Hsm.transition!(sm, :State_S211) do
        #print("$(state)-INIT;")
    end

Hsm.on_event!(sm::HsmTest, state::Val{:State_S21}, event::Val{:Event_A}, arg) =
    Hsm.transition!(sm, :State_S21) do
        #print("$(state)-$(event);")
    end

Hsm.on_event!(sm::HsmTest, state::Val{:State_S21}, event::Val{:Event_B}, arg) =
    Hsm.transition!(sm, :State_S211) do
        #print("$(state)-$(event);")
    end

Hsm.on_event!(sm::HsmTest, state::Val{:State_S21}, event::Val{:Event_G}, arg) =
    Hsm.transition!(sm, :State_S11) do
        #print("$(state)-$(event);")
    end

#############

Hsm.on_event!(sm::HsmTest, state::Val{:State_S211}, event::Val{:Event_D}, arg) =
    Hsm.transition!(sm, :State_S21) do
        #print("$(state)-$(event);")
    end

Hsm.on_event!(sm::HsmTest, state::Val{:State_S211}, event::Val{:Event_H}, arg) =
    Hsm.transition!(sm, :State_S) do
        #print("$(state)-$(event);")
    end

#############

function test(sm::HsmTest)
    event_sequence = (
        :Event_A, :Event_B, :Event_D, :Event_E, :Event_I, :Event_F, :Event_I, :Event_I, :Event_F,
        :Event_A, :Event_B, :Event_D, :Event_D, :Event_E, :Event_G, :Event_H, :Event_H, :Event_C,
        :Event_G, :Event_C, :Event_C
    )
    for event in event_sequence
        dispatch!(sm, event)
    end
end

function random_event()
    events = (:Event_A, :Event_B, :Event_C, :Event_D, :Event_E, :Event_F, :Event_G, :Event_H, :Event_I)
    return rand(events)
end

# Example usage of random_event function
function test2(sm::HsmTest)
    for _ in 1:1000
        event = random_event()
        dispatch!(sm, event)
    end
    nothing
end

hsm = HsmTest()
test(hsm)

function profile_test(hsm, n)
    for _ = 1:n
        test2(hsm)
    end
end