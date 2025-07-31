# Hsm.jl - Hierarchical State Machine Library

[![CI](https://github.com/DarrylGamroth/Hsm.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/DarrylGamroth/Hsm.jl/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/DarrylGamroth/Hsm.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/DarrylGamroth/Hsm.jl)

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

# Define the state hierarchy
@statedef LightSwitch :Off
@statedef LightSwitch :On

@on_initial function(sm::LightSwitch, ::Root)
    return Hsm.transition!(sm, :Off)
end

# Define event handlers
@on_event function(sm::LightSwitch, ::Off, ::Toggle, arg)
    sm.power_on = true
    return Hsm.transition!(sm, :On)
end

@on_event function(sm::LightSwitch, ::On, ::Toggle, arg)
    sm.power_on = false
    return Hsm.transition!(sm, :Off)
end

# Define a default event handler for any unhandled event (requires named parameter)
@on_event function(sm::LightSwitch, ::Off, event::Any, arg)
    println("Unhandled event in Off state: $(event)")
    return Hsm.EventNotHandled
end

# Create and use the state machine - initialization is automatic
sm = LightSwitch(false)
Hsm.dispatch!(sm, :Toggle)  # Transitions to On
Hsm.dispatch!(sm, :UnknownEvent)  # Will be caught by the default handler
```

## Examples

The `example/` directory contains various examples:

- `example.jl`: Traditional approach example
- `simplest_example.jl`: Simplified example

## Advanced Features

- Entry and exit actions for states
- Initial transitions for hierarchical initialization
- Event handling with arguments
- Complex state hierarchies with nested states
- Default event handlers with the `Any` keyword
- Generic entry/exit handlers using `::Any` state type

## Generic Handlers with `Any`

### Default Event Handlers

The library supports default event handlers that can process any unhandled event in a specific state:

```julia
# Define a default event handler for State_A
@on_event function(sm::MyStateMachine, state::State_A, event::Any, arg)
    println("Default handler for $(state) received: $(event)")
    return Hsm.EventHandled
end
```

Default handlers are useful for:

- Logging unhandled events
- Implementing fallback behavior
- Building diagnostic tools
- Creating more flexible state machines

### Generic Entry/Exit Handlers

Similarly, you can define generic entry and exit handlers that apply to any state without a more specific handler:

```julia
# Generic entry handler for any state
@on_entry function(sm::MyStateMachine, state::Any)
    println("Entering state: $(state)")
    sm.state_history[end+1] = state
end

# Generic exit handler for any state
@on_exit function(sm::MyStateMachine, state::Any)
    println("Exiting state: $(state)")
    sm.timestamps[state] = now()
end
```

Key points about generic entry/exit handlers:

- Must use a named parameter (e.g., `state::Any`) to access the state value
- Specific state handlers take precedence over generic handlers
- In hierarchical transitions, handlers are called in the appropriate order (exit: specific to generic, entry: generic to specific)
- Useful for logging, state tracking, and centralized state management

## Multiple State Machine Considerations

Hsm.jl supports using multiple state machine types in the same Julia session. Each state machine defined with the `@hsmdef` macro gets its own type-specific default handlers, ensuring no method dispatch ambiguities between different state machine types.

### Best Practices for Multiple State Machines

1. **Always use @hsmdef**: Define all state machines using the `@hsmdef` macro to ensure proper handler generation.
2. **Be consistent**: Either define ALL necessary handlers for your state machines, or define NONE and rely on defaults.
3. **Document dependencies**: Make it clear in your state machine documentation whether it requires explicit handlers or relies on defaults.

## Error Handling

Hsm.jl includes a comprehensive error handling system with custom exception types to help diagnose issues:

- `HsmMacroError`: Indicates incorrect usage of macros (e.g., using struct instead of mutable struct)
- `HsmStateError`: Indicates errors related to state definitions or transitions
- `HsmEventError`: Indicates errors related to event handling

These exception types provide more specific error information than generic errors, making debugging easier.

### Common Errors

- **Non-mutable State Machine**: State machines must be declared with `mutable struct`
- **State Argument Format**: State arguments must be of the form `::StateName` or `state::StateName`
- **Event Argument Format**: Event arguments must be of the form `::EventName` or `event::EventName`
- **Ancestor Errors**: Undefined state relationships or invalid relationship expressions

```

## License

MIT
