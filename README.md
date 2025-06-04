# Hsm.jl - Hierarchical State Machine Library

A zero-allocation, dynamic dispatch-free hierarchical state machine library for Julia.

## Overview

Hsm.jl provides a framework for implementing hierarchical state machines (HSMs) in Julia. The library is designed for performance-critical applications where allocations and dynamic dispatch must be avoided.

> **IMPORTANT**: Always use the `@hsmdef` macro to define state machines. The macro automatically generates type-specific default handlers that are required for proper functionality.

## Features

- **Zero-allocation design**: No allocations during state transitions and event processing
- **No dynamic dispatch**: All event handlers use compile-time dispatch via Val types
- **Clean macro-based syntax**: Simple macros for defining state machine behavior
- **Automatic initialization**: State machines are auto-initialized when created
- **Modular organization**: Support for distributing state handlers across multiple files
- **Default event handlers**: Support for catch-all handlers that process any unhandled event
- **Event tracking**: Automatic tracking of the current event being processed
- **Type-safe default handlers**: Each state machine gets its own set of type-specific default handlers

## Installation

```julia
using Pkg
Pkg.add("Hsm")
```

## Basic Example

```julia
using Hsm

# Define state machine using the simplified approach
@hsmdef mutable struct LightSwitch
    power_on::Bool
end

# Define the state hierarchy (using block syntax for multiple states)
@ancestor LightSwitch begin
    :Off => Hsm.Root
    :On => Hsm.Root
end

@on_initial :Root function(sm::LightSwitch)
    return Hsm.transition!(sm, :Off)
end

# Define event handlers
@on_event :Off :Toggle function(sm::LightSwitch, arg)
    sm.power_on = true
    return Hsm.transition!(sm, :On)
end

@on_event :On :Toggle function(sm::LightSwitch, arg)
    sm.power_on = false
    return Hsm.transition!(sm, :Off)
end

# Define a default event handler for any unhandled event
@on_event :Off Any function(sm::LightSwitch, arg)
    println("Unhandled event in Off state: $(Hsm.event(sm))")
    return Hsm.EventNotHandled
end

# Initialize and use the state machine
sm = LightSwitch(power_on=false)
Hsm.initialize!(sm)
Hsm.dispatch!(sm, :Toggle)  # Transitions to On
Hsm.dispatch!(sm, :UnknownEvent)  # Will be caught by the default handler
```

## Examples

The `example/` directory contains various examples demonstrating different approaches:

- `example.jl`: Traditional approach example
- `simplest_example.jl`: Simplified approach example

## Advanced Features

- Entry and exit actions for states
- Initial transitions for hierarchical initialization
- Event handling with arguments
- Complex state hierarchies with nested states
- Default event handlers with the `Any` keyword

## Default Event Handlers

The library supports default event handlers that can process any unhandled event in a specific state:

```julia
# Define a default event handler for State_A
@on_event :State_A Any function(sm::MyStateMachine, arg)
    println("Default handler for State_A received: $(Hsm.event(sm))")
    return Hsm.EventHandled
end
```

Default handlers are useful for:

- Logging unhandled events
- Implementing fallback behavior
- Building diagnostic tools
- Creating more flexible state machines

## Multiple State Machine Considerations

Hsm.jl supports using multiple state machine types in the same Julia session. Each state machine defined with the `@hsmdef` macro gets its own type-specific default handlers, ensuring no method dispatch ambiguities between different state machine types.

### Best Practices for Multiple State Machines

1. **Always use @hsmdef**: Define all state machines using the `@hsmdef` macro to ensure proper handler generation.
2. **Be consistent**: Either define ALL necessary handlers for your state machines, or define NONE and rely on defaults.
3. **Document dependencies**: Make it clear in your state machine documentation whether it requires explicit handlers or relies on defaults.

## License

MIT
