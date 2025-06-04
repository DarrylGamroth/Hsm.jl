using Pkg
Pkg.activate(".")

using Hsm
using ValSplit

# Define a simple state machine with auto-initialization. This version is just a regular struct
# without @kwdef, so we need to define a constructor.
@hsmdef mutable struct TestHsm
    foo::Int
    message::String
end

# Define state hierarchy
# should generate the following:
# Hsm.ancestor(::TestHsm, ::Val{:State1}) = :Root
# Hsm.ancestor(::TestHsm, ::Val{:State2}) = :State1
@ancestor TestHsm begin
    :State => :Root
    :State1 => :State
    :State2 => :State1
end

# Function signature = Hsm.on_initial!(sm::TestHsm, ::Val{:State})
@on_initial function(sm::TestHsm, ::State)
    println("Initializing State with foo = ", sm.foo)
    return Hsm.transition!(sm, :State1)
end

# Function signature = Hsm.on_entry!(sm::TestHsm, ::Val{:State})
@on_entry function(sm::TestHsm, ::State)
    println("Entering State with foo = ", sm.foo)
end

# Function signature = Hsm.on_exit!(sm::TestHsm, ::Val{:State})
@on_exit function(sm::TestHsm, ::State)
    println("Exiting State with foo = ", sm.foo)
end

# Function signature = Hsm.on_entry!(sm::TestHsm, ::Val{:State1}) 
@on_entry function(sm::TestHsm, ::State1)
    sm.foo = 0
    println("Entering State1 with foo = ", sm.foo)
end

# Function signature = Hsm.on_exit!(sm::TestHsm, ::Val{:State1})
@on_exit function(sm::TestHsm, ::State1)
    println("Exiting State1 with foo = ", sm.foo)
end

# Function signature = Hsm.on_event!(sm::TestHsm, ::Val{:State1}, ::Val{:Start}, arg)
@macroexpand @on_event function(sm::TestHsm, ::State1, ::Start, _)
    sm.foo += 1
    return Hsm.transition!(sm, :State2)
end

# Function signature = Hsm.on_initial!(sm::TestHsm, ::Val{:State1})
@on_entry function(sm::TestHsm, ::State2)
    println("Entering State2 with foo = ", sm.foo)
end

# Function signature = Hsm.on_exit!(sm::TestHsm, ::Val{:State2})
@on_exit function(sm::TestHsm, ::State2)
    println("Exiting State2 with foo = ", sm.foo)
end

# Function signature = Hsm.on_event!(sm::TestHsm, ::Val{:State2}, ::Val{:Stop}, arg)
@on_event function(sm::TestHsm, ::State2, ::Stop, _)
    return Hsm.transition!(sm, :State1)
end

# Default event handler for State - will handle any unhandled event
# Function signature uses ValSplit to handle any event
@on_event function(sm::TestHsm, ::State, ::Any, data)
    println("Default handler in State received event: $(Hsm.event(sm))")
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

