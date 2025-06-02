# Hsm.jl - Hierarchical State Machine Library

A zero-allocation, dynamic dispatch-free hierarchical state machine library for Julia.

## Overview

Hsm.jl provides a framework for implementing hierarchical state machines (HSMs) in Julia. The library is designed for performance-critical applications where allocations and dynamic dispatch must be avoided.

## Features

- **Zero-allocation design**: No allocations during state transitions and event processing
- **No dynamic dispatch**: All event handlers use compile-time dispatch via Val types
- **Clean macro-based syntax**: Simple macros for defining state machine behavior
- **Automatic initialization**: State machines are auto-initialized when created
- **Modular organization**: Support for distributing state handlers across multiple files

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

# Initialize and use the state machine
sm = LightSwitch(power_on=false)
Hsm.initialize!(sm)
Hsm.dispatch!(sm, :Toggle)  # Transitions to On
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

## License

MIT
