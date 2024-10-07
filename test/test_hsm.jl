using Revise
using JET
using BenchmarkTools

module Testing

include("../src/Hsm.jl")

using .Hsm
using ValSplit

# Define the state machine
mutable struct HsmTest <: Hsm.AbstractHsmStateMachine
    current::Symbol
    source::Symbol
    event::Symbol

    buf::Vector{UInt8}

    # Define state machine variables
    foo::Int

    function HsmTest()
        sm = new()
        Hsm.initialize(sm)
        sm.event = :Event_None
        Hsm.on_initial!(sm, :Top)
        #print"\n")
        return sm
    end
end

# Define state machine interface functions
Hsm.current(sm::HsmTest) = sm.current
Hsm.current!(sm::HsmTest, s::Symbol) = sm.current = s
Hsm.source(sm::HsmTest) = sm.source
Hsm.source!(sm::HsmTest, s::Symbol) = sm.source = s
Hsm.event(sm::HsmTest) = sm.event

# Define all states

# @state Top{TestHsm} nothing
# @state State_S{TestHsm} Top
# @state State_S1{TestHsm} State_S
# @state State_S11{TestHsm} State_S1
# @state State_S2{TestHsm} State_S
# @state State_S21{TestHsm} State_S2
# @state State_S211{TestHsm} State_S21
# Ancestor needs to know what state machine these are for
Hsm.ancestor(sm::HsmTest, ::Val{:Top}) = Hsm.root(sm)
Hsm.ancestor(sm::HsmTest, ::Val{:State_S}) = :Top
Hsm.ancestor(sm::HsmTest, ::Val{:State_S1}) = :State_S
Hsm.ancestor(sm::HsmTest, ::Val{:State_S11}) = :State_S1
Hsm.ancestor(sm::HsmTest, ::Val{:State_S2}) = :State_S
Hsm.ancestor(sm::HsmTest, ::Val{:State_S21}) = :State_S2
Hsm.ancestor(sm::HsmTest, ::Val{:State_S211}) = :State_S21

# Override default handlers - does not work with ValSplit
# function Hsm.on_entry!(sm::Hsm.AbstractHsmStateMachine, state::Val{S}) where {S<:Symbol}
#     #print"$(state)-ENTRY;")
# end

# function Hsm.on_exit!(sm::Hsm.AbstractHsmStateMachine, state::Val{S}) where {S<:Symbol}
#     #print"$(state)-EXIT;")
# end

# @valsplit Hsm.on_entry!(sm::Hsm.AbstractHsmStateMachine, Val(state::Symbol)) = #print"$(state)-ENTRY;")
# @valsplit Hsm.on_exit!(sm::Hsm.AbstractHsmStateMachine, Val(state::Symbol)) = #print"$(state)-EXIT;")

############

Hsm.on_initial!(sm::HsmTest, state::Val{:Top}) =
    Hsm.transition!(sm, :State_S2) do
        #print"$(state)-INIT;")
        sm.foo = 0
    end

##############

Hsm.on_initial!(sm::HsmTest, state::Val{:State_S}) =
    Hsm.transition!(sm, :State_S11) do
        #print"$(state)-INIT;")
    end

Hsm.on_event!(sm::HsmTest, state::Val{:State_S}, event::Val{:Event_E}) =
    Hsm.transition!(sm, :State_S11) do
        #print"$(state)-$(event);")
    end

function Hsm.on_event!(sm::HsmTest, state::Val{:State_S}, event::Val{:Event_I})
    if sm.foo == 1
        #print"$(state)-$(event);")
        sm.foo = 0
        return Hsm.EventHandled
    else
        return Hsm.EventNotHandled
    end
end

#########

Hsm.on_initial!(sm::HsmTest, state::Val{:State_S1}) =
    Hsm.transition!(sm, :State_S11) do
        #print"$(state)-INIT;")
    end

Hsm.on_event!(sm::HsmTest, state::Val{:State_S1}, event::Val{:Event_A}) =
    Hsm.transition!(sm, :State_S1) do
        #print"$(state)-$(event);")
    end

Hsm.on_event!(sm::HsmTest, state::Val{:State_S1}, event::Val{:Event_B}) =
    Hsm.transition!(sm, :State_S11) do
        #print"$(state)-$(event);")
    end

Hsm.on_event!(sm::HsmTest, state::Val{:State_S1}, event::Val{:Event_C}) =
    Hsm.transition!(sm, :State_S2) do
        #print"$(state)-$(event);")
    end

function Hsm.on_event!(sm::HsmTest, state::Val{:State_S1}, event::Val{:Event_D})
    if sm.foo == 0
        return Hsm.transition!(sm, :State_S1) do
            #print"$(state)-$(event);")
            sm.foo = 0
        end
    else
        return Hsm.EventNotHandled
    end
end

Hsm.on_event!(sm::HsmTest, state::Val{:State_S1}, event::Val{:Event_F}) =
    Hsm.transition!(sm, :State_S211) do
        #print"$(state)-$(event);")
    end

function Hsm.on_event!(sm::HsmTest, state::Val{:State_S1}, event::Val{:Event_I})
    #print"$(state)-$(event);")
    return Hsm.EventHandled
end

#############

# Warning, this style can allocate
function Hsm.on_event!(sm::HsmTest, state::Val{:State_S11}, event::Val{:Event_D})
    if sm.foo == 1
        return Hsm.transition!(sm, :State_S1) do
            #print"$(state)-$(event);")
            sm.foo = 0
        end
    else
        return Hsm.EventNotHandled
    end
end

Hsm.on_event!(sm::HsmTest, state::Val{:State_S11}, event::Val{:Event_G}) =
    Hsm.transition!(sm, :State_S211) do
        #print"$(state)-$(event);")
    end

Hsm.on_event!(sm::HsmTest, state::Val{:State_S11}, event::Val{:Event_H}) =
    Hsm.transition!(sm, :State_S) do
        #print"$(state)-$(event);")
    end

######

Hsm.on_initial!(sm::HsmTest, state::Val{:State_S2}) =
    Hsm.transition!(sm, :State_S211) do
        #print"$(state)-INIT;")
    end

Hsm.on_event!(sm::HsmTest, state::Val{:State_S2}, event::Val{:Event_C}) =
    Hsm.transition!(sm, :State_S1) do
        #print"$(state)-$(event);")
    end

Hsm.on_event!(sm::HsmTest, state::Val{:State_S2}, event::Val{:Event_F}) =
    Hsm.transition!(sm, :State_S11) do
        #print"$(state)-$(event);")
    end

function Hsm.on_event!(sm::HsmTest, state::Val{:State_S2}, event::Val{:Event_I})
    if sm.foo == 0
        #print"$(state)-$(event);")
        sm.foo = 1
        return Hsm.EventHandled
    else
        return Hsm.EventNotHandled
    end
end

########

Hsm.on_initial!(sm::HsmTest, state::Val{:State_S21}) =
    Hsm.transition!(sm, :State_S211) do
        #print"$(state)-INIT;")
    end

function Hsm.on_event!(sm::HsmTest, state::Val{:State_S21}, event::Val{:Event_A})
    # Ok when this transition fires we need the SBE event message information
    Hsm.transition!(sm, :State_S21) do

        #print"$(state)-$(event);")
    end
end

Hsm.on_event!(sm::HsmTest, state::Val{:State_S21}, event::Val{:Event_B}) =
    Hsm.transition!(sm, :State_S211) do
        #print"$(state)-$(event);")
    end

Hsm.on_event!(sm::HsmTest, state::Val{:State_S21}, event::Val{:Event_G}) =
    Hsm.transition!(sm, :State_S11) do
        #print"$(state)-$(event);")
    end

#############

Hsm.on_event!(sm::HsmTest, state::Val{:State_S211}, event::Val{:Event_D}) =
    Hsm.transition!(sm, :State_S21) do
        #print"$(state)-$(event);")
    end

Hsm.on_event!(sm::HsmTest, state::Val{:State_S211}, event::Val{:Event_H}) =
    Hsm.transition!(sm, :State_S) do
        #print"$(state)-$(event);")
    end

function dispatch!(sm, event)
    #print"$(event) - ")
    sm.event = event
    Hsm.dispatch!(sm)
    #print"\n")
end

function test(hsm)
    dispatch!(hsm, :Event_A)
    dispatch!(hsm, :Event_B)
    dispatch!(hsm, :Event_D)
    dispatch!(hsm, :Event_E)
    dispatch!(hsm, :Event_I)
    dispatch!(hsm, :Event_F)
    dispatch!(hsm, :Event_I)
    dispatch!(hsm, :Event_I)
    dispatch!(hsm, :Event_F)
    dispatch!(hsm, :Event_A)
    dispatch!(hsm, :Event_B)
    dispatch!(hsm, :Event_D)
    dispatch!(hsm, :Event_D)
    dispatch!(hsm, :Event_E)
    dispatch!(hsm, :Event_G)
    dispatch!(hsm, :Event_H)
    dispatch!(hsm, :Event_H)
    dispatch!(hsm, :Event_C)
    dispatch!(hsm, :Event_G)
    dispatch!(hsm, :Event_C)
    dispatch!(hsm, :Event_C)
    # dispatch!(hsm, :Event_K)
end

hsm = HsmTest()
test(hsm)

function profile_test(hsm, n)
    for _ = 1:n
        test(hsm)
    end
end

end