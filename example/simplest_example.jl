using Pkg
Pkg.activate(".")

using Hsm
using ValSplit

@hsmdef mutable struct TestHsm
    foo::Int
    message::String
end

# Define state hierarchy
@ancestor TestHsm begin
    :State => :Root
    :State1 => :State
    :State2 => :State1
end

@on_initial function(sm::TestHsm, ::Root)
    println("Initializing State with foo = ", sm.foo)
    return Hsm.transition!(sm, :State)
end

@on_initial function(sm::TestHsm, ::State)
    println("Initializing State with foo = ", sm.foo)
    return Hsm.transition!(sm, :State1)
end

@on_entry function(sm::TestHsm, state::Any)
    println("Entering $state with foo = ", sm.foo)
end

@on_exit function(sm::TestHsm, state::Any)
    println("Exiting $state with foo = ", sm.foo)
end

@on_event function(sm::TestHsm, ::State1, ::Start, _)
    sm.foo += 1
    return Hsm.transition!(sm, :State2)
end

@on_event function(sm::TestHsm, ::State2, ::Stop, _)
    return Hsm.transition!(sm, :State1)
end

# Default event handler for State - will handle any unhandled event
@on_event function(sm::TestHsm, ::State, event::Any, data)
    println("Default handler in State received event: $event")
    println("With data: $data")
    return Hsm.EventHandled
end

function main(ARGS)
# Create and initialize a state machine
    sm = TestHsm(foo=0, message="Hello")
    @show sm
    println("State machine initialized. Current state: ", Hsm.current(sm))
    
    # Test the specific event handlers
    Hsm.dispatch!(sm, :Start)
    println("After Start event, current state: ", Hsm.current(sm))
    Hsm.dispatch!(sm, :Stop)
    println("After Stop event, current state: ", Hsm.current(sm))
    
    # Test the default event handler
    Hsm.dispatch!(sm, :UnknownEvent, "Some data")
    println("After UnknownEvent, current state: ", Hsm.current(sm))
end

