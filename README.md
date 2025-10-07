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
- **Abstract type support**: Define state machine families with shared interfaces using `@abstracthsmdef`
- **Modular organization**: Support for distributing state handlers across multiple files
- **Default event handlers**: Support for catch-all handlers that process any unhandled event
- **Event tracking**: Automatic tracking of the current event being processed
- **Type-safe default handlers**: Each state machine gets its own set of type-specific default handlers
- **Polymorphism**: Multiple concrete state machine types can share a common abstract interface

## Installation

```julia
using Pkg
Pkg.add("Hsm")
```

## Quick Start

### Simple State Machine

```julia
using Hsm

# Define a state machine with @hsmdef
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

### Abstract State Machines

Define families of related state machines that share common structure:

```julia
using Hsm

# Define an abstract state machine type with shared interface
@abstracthsmdef VehicleController

# Define shared state hierarchy (applies to all concrete types)
@statedef VehicleController :Stopped
@statedef VehicleController :Moving

# Define shared event handlers
@on_event function(sm::VehicleController, ::Stopped, ::Start, _)
    return Hsm.transition!(sm, :Moving)
end

# Create concrete types - they inherit the interface
@hsmdef mutable struct Car <: VehicleController
    speed::Float64
    fuel::Float64
end

@hsmdef mutable struct Truck <: VehicleController
    speed::Float64
    cargo::Float64
end

# Add type-specific behavior
@on_event function(sm::Car, ::Moving, ::Accelerate, amount::Float64)
    sm.speed += amount
    sm.fuel -= amount * 0.1
    return Hsm.EventHandled
end

@on_event function(sm::Truck, ::Moving, ::Accelerate, amount::Float64)
    sm.speed += amount / (1 + sm.cargo / 1000)
    sm.fuel -= amount * 0.2
    return Hsm.EventHandled
end

# Use polymorphically
vehicles = VehicleController[Car(0.0, 100.0), Truck(0.0, 5000.0)]
for vehicle in vehicles
    Hsm.dispatch!(vehicle, :Start)
    Hsm.dispatch!(vehicle, :Accelerate, 20.0)
end
```

## Examples

The `example/` directory contains various examples:

- `simplest_example.jl`: Basic state machine with a simple hierarchy
- `abstract_example.jl`: Using `@abstracthsmdef` to create a family of related state machines
- `example.jl`: More complex hierarchical state machine example

## Advanced Features

- Entry and exit actions for states
- Initial transitions for hierarchical initialization
- Event handling with arguments
- Complex state hierarchies with nested states
- Default event handlers with the `Any` keyword
- Generic entry/exit handlers using `::Any` state type
- Abstract state machine types with `@abstracthsmdef`
- Shared state hierarchies and handlers across multiple concrete types
- Type-specific specialization of event handlers
- Calling abstract parent handlers with `@super` to extend behavior

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

## Extending Abstract Handlers with `@super`

When using abstract state machines, concrete types can extend the behavior of their abstract parent handlers using the `@super` macro. This allows you to:

- Call the parent handler first, then add type-specific logic
- Reuse common behavior defined in the abstract type
- Build layered functionality across the type hierarchy

### Usage

```julia
@abstracthsmdef AbstractVehicle

# Define abstract handler
@on_event function(sm::AbstractVehicle, state::Stopped, event::StartEngine, data)
    sm.engine_running = true
    println("Engine started")
    return Hsm.EventHandled
end

@hsmdef mutable struct Car <: AbstractVehicle
    engine_running::Bool
    wheels::Int
end

# Concrete handler extends abstract behavior
@on_event function(sm::Car, state::Stopped, event::StartEngine, data)
    # Call the abstract handler first
    result = @super on_event sm state event data
    
    # Add car-specific logic
    println("Car has $(sm.wheels) wheels ready")
    sm.wheels = data
    return result
end
```

### Syntax

The `@super` macro has different forms depending on the handler type:

```julia
# For event handlers
@super on_event sm state event data

# For state handlers (on_initial, on_entry, on_exit)
@super on_initial sm state
@super on_entry sm state
@super on_exit sm state
```

### Notes

- The `state` and `event` variables must be the parameter names from your handler definition
- Only calls the immediate parent type's handler (not grandparent types)
- Works with all handler types: `on_event`, `on_initial`, `on_entry`, `on_exit`

## Defining State Machines

Hsm.jl provides two macros for defining state machines:

### `@hsmdef` - Standalone State Machines

Use `@hsmdef` for standalone state machines:

```julia
@hsmdef mutable struct MyStateMachine
    counter::Int
    status::String
end
```

This macro:
- Adds hidden fields for state tracking (using `gensym` to avoid name collisions)
- Generates field accessor methods (`current`, `source`, etc.)
- Generates default HSM interface methods

### `@abstracthsmdef` - State Machine Families

Use `@abstracthsmdef` to create families of related state machines:

```julia
# Define the abstract type and shared interface
@abstracthsmdef AbstractController

# Define shared state hierarchy
@statedef AbstractController :Idle
@statedef AbstractController :Active

# Create concrete implementations
@hsmdef mutable struct Controller1 <: AbstractController
    value::Int
end

@hsmdef mutable struct Controller2 <: AbstractController
    data::String
end
```

Key differences:
- `@abstracthsmdef` defines an abstract type and creates the HSM interface **once**
- `@hsmdef` with inheritance (`<: AbstractType`) only adds field accessors
- Concrete types inherit the interface from the abstract type
- All concrete types share the same state hierarchy and base event handlers
- Each concrete type can add specialized event handlers

Benefits of abstract state machines:
- **Code reuse**: Define state hierarchy and common handlers once
- **Polymorphism**: Store different concrete types in the same collection
- **Maintainability**: Changes to shared behavior happen in one place
- **Type safety**: All concrete types conform to the same interface

### Best Practices

1. **Always use @hsmdef or @abstracthsmdef**: These macros ensure proper handler generation
2. **Choose the right macro**: 
   - Use `@hsmdef` for standalone state machines
   - Use `@abstracthsmdef` when you need multiple related types
3. **State machines must be mutable**: Use `mutable struct`, not `struct`
4. **Document state hierarchies**: Make state relationships clear in comments or documentation

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
