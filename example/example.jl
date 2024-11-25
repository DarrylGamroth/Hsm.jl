"""
This file contains an example of a hierarchical state machine implemented using the Hsm.jl library.
See example.png for a graphical representation of the state machine.
"""

using Revise
using BenchmarkTools

module Testing

include("../src/Hsm.jl")

using .Hsm
using ValSplit

# Define the state machine
mutable struct HsmTest <: Hsm.AbstractHsmStateMachine
    # Variables used by the AbstractHsmStateMachine interface
    current::Symbol
    source::Symbol
    event::Symbol

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

# Implement the AbstractHsmStateMachine interface
Hsm.current(sm::HsmTest) = sm.current
Hsm.current!(sm::HsmTest, s::Symbol) = sm.current = s
Hsm.source(sm::HsmTest) = sm.source
Hsm.source!(sm::HsmTest, s::Symbol) = sm.source = s
Hsm.event(sm::HsmTest) = sm.event

# Define all states
const Top = Hsm.Root
const State_S = :State_S
const State_S1 = :State_S1
const State_S11 = :State_S11
const State_S2 = :State_S2
const State_S21 = :State_S21
const State_S211 = :State_S211

# Implement the AbstractHsmStateMachine ancestor interface for each state
Hsm.ancestor(sm::HsmTest, ::Val{State_S}) = Top
Hsm.ancestor(sm::HsmTest, ::Val{State_S1}) = State_S
Hsm.ancestor(sm::HsmTest, ::Val{State_S11}) = State_S1
Hsm.ancestor(sm::HsmTest, ::Val{State_S2}) = State_S
Hsm.ancestor(sm::HsmTest, ::Val{State_S21}) = State_S2
Hsm.ancestor(sm::HsmTest, ::Val{State_S211}) = State_S21

# Define a dispatch function. Custom dispatch functions can be defined for each state machine
function dispatch!(sm::HsmTest, event)
    #print("$(event) - ")
    sm.event = event
    Hsm.dispatch!(sm)
    #print("\n")
end

# Globally override default handlers
# @valsplit Hsm.on_entry!(sm::Hsm.AbstractHsmStateMachine, Val(state::Symbol)) = #print("$(state)-ENTRY;")
# @valsplit Hsm.on_exit!(sm::Hsm.AbstractHsmStateMachine, Val(state::Symbol)) = #print("$(state)-EXIT;")

############

function Hsm.on_initial!(sm::HsmTest, state::Val{Top})
    handled = Hsm.transition!(sm, State_S2) do
        # Do something on the transition
        #print("$(state)-INIT;")
        sm.foo = 0
    end
    #print("\n")
    return handled
end

##############

Hsm.on_initial!(sm::HsmTest, state::Val{State_S}) =
    Hsm.transition!(sm, State_S11) do
        #print("$(state)-INIT;")
    end

# Example of how to implement on_entry! for a state
# function Hsm.on_entry!(sm::HsmTest, state::Val{State_S})
#     # Do something when entering the state
# end

# Example of how to implement on_exit! for a state
# function Hsm.on_exit!(sm::HsmTest, state::Val{State_S})
#     # Do something when exiting the state
# end

Hsm.on_event!(sm::HsmTest, state::Val{State_S}, event::Val{:Event_E}) =
    # transition! returns EventHandled if the transition is successful
    Hsm.transition!(sm, State_S11) do
        #print("$(state)-$(event);")
    end

function Hsm.on_event!(sm::HsmTest, state::Val{State_S}, event::Val{:Event_I})
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

Hsm.on_initial!(sm::HsmTest, state::Val{State_S1}) =
    Hsm.transition!(sm, State_S11) do
        #print("$(state)-INIT;")
    end

Hsm.on_event!(sm::HsmTest, state::Val{State_S1}, event::Val{:Event_A}) =
    Hsm.transition!(sm, State_S1) do
        #print("$(state)-$(event);")
    end

Hsm.on_event!(sm::HsmTest, state::Val{State_S1}, event::Val{:Event_B}) =
    Hsm.transition!(sm, State_S11) do
        #print("$(state)-$(event);")
    end

Hsm.on_event!(sm::HsmTest, state::Val{State_S1}, event::Val{:Event_C}) =
    Hsm.transition!(sm, State_S2) do
        #print("$(state)-$(event);")
    end

function Hsm.on_event!(sm::HsmTest, state::Val{State_S1}, event::Val{:Event_D})
    if sm.foo == 0
        return Hsm.transition!(sm, State_S1) do
            #print("$(state)-$(event);")
            sm.foo = 0
        end
    else
        return Hsm.EventNotHandled
    end
end

Hsm.on_event!(sm::HsmTest, state::Val{State_S1}, event::Val{:Event_F}) =
    Hsm.transition!(sm, State_S211) do
        #print("$(state)-$(event);")
    end

function Hsm.on_event!(sm::HsmTest, state::Val{State_S1}, event::Val{:Event_I})
    #print("$(state)-$(event);")
    return Hsm.EventHandled
end

#############

function Hsm.on_event!(sm::HsmTest, state::Val{State_S11}, event::Val{:Event_D})
    if sm.foo == 1
        return Hsm.transition!(sm, State_S1) do
            #print("$(state)-$(event);")
            sm.foo = 0
        end
    else
        return Hsm.EventNotHandled
    end
end

Hsm.on_event!(sm::HsmTest, state::Val{State_S11}, event::Val{:Event_G}) =
    Hsm.transition!(sm, State_S211) do
        #print("$(state)-$(event);")
    end

Hsm.on_event!(sm::HsmTest, state::Val{State_S11}, event::Val{:Event_H}) =
    Hsm.transition!(sm, State_S) do
        #print("$(state)-$(event);")
    end

######

Hsm.on_initial!(sm::HsmTest, state::Val{State_S2}) =
    Hsm.transition!(sm, State_S211) do
        #print("$(state)-INIT;")
    end

Hsm.on_event!(sm::HsmTest, state::Val{State_S2}, event::Val{:Event_C}) =
    Hsm.transition!(sm, State_S1) do
        #print("$(state)-$(event);")
    end

Hsm.on_event!(sm::HsmTest, state::Val{State_S2}, event::Val{:Event_F}) =
    Hsm.transition!(sm, State_S11) do
        #print("$(state)-$(event);")
    end

function Hsm.on_event!(sm::HsmTest, state::Val{State_S2}, event::Val{:Event_I})
    if sm.foo == 0
        #print("$(state)-$(event);")
        sm.foo = 1
        return Hsm.EventHandled
    else
        return Hsm.EventNotHandled
    end
end

########

Hsm.on_initial!(sm::HsmTest, state::Val{State_S21}) =
    Hsm.transition!(sm, State_S211) do
        #print("$(state)-INIT;")
    end

Hsm.on_event!(sm::HsmTest, state::Val{State_S21}, event::Val{:Event_A}) =
    Hsm.transition!(sm, State_S21) do
        #print("$(state)-$(event);")
    end

Hsm.on_event!(sm::HsmTest, state::Val{State_S21}, event::Val{:Event_B}) =
    Hsm.transition!(sm, State_S211) do
        #print("$(state)-$(event);")
    end

Hsm.on_event!(sm::HsmTest, state::Val{State_S21}, event::Val{:Event_G}) =
    Hsm.transition!(sm, State_S11) do
        #print("$(state)-$(event);")
    end

#############

Hsm.on_event!(sm::HsmTest, state::Val{State_S211}, event::Val{:Event_D}) =
    Hsm.transition!(sm, State_S21) do
        #print("$(state)-$(event);")
    end

Hsm.on_event!(sm::HsmTest, state::Val{State_S211}, event::Val{:Event_H}) =
    Hsm.transition!(sm, State_S) do
        #print("$(state)-$(event);")
    end

#############

function test(sm::HsmTest)
    dispatch!(sm, :Event_A)
    dispatch!(sm, :Event_B)
    dispatch!(sm, :Event_D)
    dispatch!(sm, :Event_E)
    dispatch!(sm, :Event_I)
    dispatch!(sm, :Event_F)
    dispatch!(sm, :Event_I)
    dispatch!(sm, :Event_I)
    dispatch!(sm, :Event_F)
    dispatch!(sm, :Event_A)
    dispatch!(sm, :Event_B)
    dispatch!(sm, :Event_D)
    dispatch!(sm, :Event_D)
    dispatch!(sm, :Event_E)
    dispatch!(sm, :Event_G)
    dispatch!(sm, :Event_H)
    dispatch!(sm, :Event_H)
    dispatch!(sm, :Event_C)
    dispatch!(sm, :Event_G)
    dispatch!(sm, :Event_C)
    dispatch!(sm, :Event_C)
end

hsm = HsmTest()
test(hsm)

function profile_test(hsm, n)
    for _ = 1:n
        test(hsm)
    end
end

end