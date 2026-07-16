# Hsm.jl - Hierarchical State Machine Library

[![CI](https://github.com/DarrylGamroth/Hsm.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/DarrylGamroth/Hsm.jl/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/DarrylGamroth/Hsm.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/DarrylGamroth/Hsm.jl)

A zero-allocation, statically specialized hierarchical state machine library for Julia.

The supported UML/PSSM subset and requirement-to-test mapping are recorded in
[SEMANTICS.md](SEMANTICS.md).

## Overview

Hsm.jl provides a framework for implementing hierarchical state machines (HSMs) in Julia. The library is designed for performance-critical applications where allocations and dynamic dispatch must be avoided.

> **IMPORTANT**: Always use the `@hsmdef` macro to define state machines. The macro automatically generates type-specific default handlers that are required for proper functionality.
> **NOTE**: `on_initial!` handlers must ultimately return `EventHandled`. Returning anything else will throw.

## Features

- **Zero-allocation steady state**: Warmed transitions and event processing do not allocate when user callbacks do not allocate
- **Specialized transition kernels**: Runtime `Symbol` values are finitely split before entering compile-time-specialized handlers and transitions
- **Static transition edges**: Handler targets are validated and specialized at macro expansion time
- **UML history support**: Explicit shallow and deep history transitions for composite states
- **Static UML control vertices**: Choice, FinalState/completion, and terminate support without changing the `Symbol` API
- **Run-to-completion enforcement**: Reentrant dispatch and transitions are rejected
- **Clean macro-based syntax**: Simple macros for defining state machine behavior
- **Automatic initialization**: State machines are auto-initialized when created
- **Abstract type support**: Define state machine families with shared interfaces using `@abstracthsmdef`
- **Modular organization**: Support for distributing state handlers across multiple files
- **Default event handlers**: Support for catch-all handlers that process any unhandled event
- **Event tracking**: Automatic tracking of the current event being processed
- **Type-safe default handlers**: Each state machine gets its own set of type-specific default handlers
- **Polymorphism**: Multiple concrete state machine types can share a common abstract interface
- **Zero-cost tracing**: Optional tracing hooks for debugging and instrumentation with no overhead when unused

## Installation

Hsm.jl supports Julia 1.10 and later.

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
- `pseudostates_example.jl`: Complete history, choice, FinalState/completion,
  terminate, and lifecycle example with self-checking assertions

Run any example from the repository root using the package environment:

```sh
julia --startup-file=no --project=. example/pseudostates_example.jl
```

The examples use only Hsm.jl and Julia standard libraries and are smoke-tested
on the minimum and current supported Julia releases.

## Advanced Features

- Entry and exit actions for states
- Initial transitions for hierarchical initialization
- Explicit shallow/deep history and default-history transitions
- Runtime choice among statically named transition edges
- FinalState and completion transitions
- Terminate pseudostates and lifecycle inspection
- Event handling with arguments
- Complex state hierarchies with nested states
- Default event handlers with the `Any` keyword
- Generic entry/exit handlers using `::Any` state type
- Abstract state machine types with `@abstracthsmdef`
- Shared state hierarchies and handlers across multiple concrete types
- Type-specific specialization of event handlers
- Calling abstract parent handlers with `@super` to extend behavior
- Zero-cost tracing hooks for debugging and instrumentation

## Behavior Notes

- Self transitions are treated as external transitions (exit/entry actions run).
- `trace_transition_end` reports the direct transition target; nested initial transitions may enter deeper states.
- A literal transition target inside a concrete-state handler, such as
  `Hsm.transition!(sm, :Running)`, uses a statically specialized entry/exit
  path. Transition targets inside handler macros must be literal `Symbol`s;
  computed targets and transitions from generic `state::Any` handlers are
  rejected. Direct calls outside handler macros retain the dynamic `Symbol`
  hierarchy walk.
- `@on_entry` and `@on_exit` Behaviors cannot initiate transitions. The macros
  reject direct attempts, and the runtime guard catches indirect attempts.
- An `@on_initial` handler models an initial Pseudostate: it may contain at
  most one unconditional outgoing transition.
- `@choice` is the explicit conditional control vertex; its runtime guards
  choose among compile-time-known transition edges.
- `dispatch!` is run-to-completion. Queue an event for later processing instead
  of calling `dispatch!` recursively from a handler or transition callback.

## History Transitions

History is explicit and does not change the meaning of `transition!`. Pass the
composite state that owns the implicit Region and a statically named history
mode:

```julia
@on_event function(sm::Machine, ::Outside, ::Resume, arg)
    return Hsm.transition_history!(sm, :Operating, Hsm.DeepHistory())
end
```

Literal owners used by handler macros are declared automatically. If history
is reached only through direct API calls outside a handler, declare its owner
explicitly with `@historydef Machine :Operating`.

- `DeepHistory()` restores the former active leaf and enters the complete path
  without replaying intermediate initial transitions.
- `ShallowHistory()` restores the former direct child, then follows that
  child's normal initial transition.
- If the composite has no recorded history, its declared explicit default
  history edge is taken when present; otherwise its `@on_initial` handler
  selects the normal default state.
- To model an explicit default edge from the history Pseudostate, declare its
  kind and target. Its optional effect is separate from the incoming history
  Transition effect:

  ```julia
  @historydef Machine :Operating Hsm.DeepHistory() :Idle

  @on_history_default function(
      sm::Machine,
      ::Operating,
      ::DeepHistory,
  )
      sm.resumed_from_default = true
  end
  ```

- An optional `do` block is the incoming history transition's effect and runs
  between exit and entry Behaviors.

For machines that declare history, `@hsmdef` allocates concrete per-instance
history storage during construction. Machines without history do not allocate
that storage. Reading, recording, and restoring history are allocation-free
after warmup. Declare all states before constructing an instance; the state
graph is treated as closed for that instance.

## Choice Pseudostates

Use `@choice` when runtime data selects among a finite set of static edges:

```julia
@on_event function(sm::Machine, ::Waiting, ::Classify, item)
    return @choice sm :Processing begin
        sm.last_item = item                 # incoming Transition effect
        if ispriority(item)
            Hsm.transition!(sm, :Priority) do
                sm.priority_count += 1      # selected outgoing effect
            end
        elseif isvalid(item)
            Hsm.transition!(sm, :Normal)
        else
            Hsm.transition!(sm, :Rejected)
        end
    end
end
```

The owner and targets must be literal registered `Symbol`s, and an `else`
edge is required. Hsm.jl enters the owner's path before evaluating every
guard, then deterministically selects the first enabled guarded edge in source
order. Only the selected edge's effect runs. This deterministic selection is a
documented choice-strategy specialization of PSSM.

## Final States and Completion Transitions

Declare a FinalState in a composite State's implicit Region and handle that
composite's completion event with `@on_completion`:

```julia
@statedef Machine :Processing
@finaldef Machine :ProcessingDone :Processing
@statedef Machine :Idle

@on_completion function(sm::Machine, ::Processing)
    return Hsm.transition!(sm, :Idle)
end
```

Entering a nested FinalState completes its owner and clears that Region's
history. Entering a top-level FinalState completes the whole machine.
Completion transitions run before another external event and may use ordinary
static transitions, history, or `@choice`. FinalStates cannot own children or
define State Behaviors.

Use `isrunning(sm)`, `iscomplete(sm)`, and `isterminated(sm)` to inspect the
lifecycle. Completed machines reject subsequent dispatches and transitions.

## Terminate Pseudostates

`@terminatedef` declares a named terminate target without overloading
`transition!`:

```julia
@terminatedef Machine :EmergencyStop

@on_event function(sm::Machine, ::Running, ::Emergency, arg)
    return Hsm.transition!(sm, :EmergencyStop)
end
```

The incoming transition performs its normal exits and effect and enters any
required containing States. Reaching terminate then stops the entire machine
without executing cleanup exits for the remaining active configuration. The
pseudostate never becomes `current`; Hsm.jl stores `:Root` and marks the
machine terminated. Further dispatches and transitions are rejected.

Hsm.jl models one active leaf in one implicit Region. Junctions, entry/exit
connection-point Pseudostates, fork/join, orthogonal Regions, `doActivity`, and
deferred events are not currently implemented.

## Tracing Hooks

Hsm.jl provides a set of lightweight tracing hooks that allow you to observe the internal lifecycle of your state machine without affecting performance. By default, these hooks are no-op functions that get completely inlined away at compile time, resulting in zero overhead.

### Available Trace Hooks

You can override any of these functions for your specific state machine type to add custom instrumentation:

```julia
# Event dispatch lifecycle
Hsm.trace_dispatch_start(sm, event::Symbol, arg)           # Before dispatch begins
Hsm.trace_dispatch_attempt(sm, state::Symbol, event::Symbol) # Before trying state's handler
Hsm.trace_dispatch_result(sm, state::Symbol, event::Symbol, result) # After handler returns

# State transition lifecycle
Hsm.trace_transition_begin(sm, from::Symbol, to::Symbol, lca::Symbol) # Transition starts
Hsm.trace_transition_action(sm, from::Symbol, to::Symbol)  # Before action function runs
Hsm.trace_transition_end(sm, from::Symbol, to::Symbol)     # Transition completes (direct target)

# State entry/exit/initial
Hsm.trace_entry(sm, state::Symbol)    # Before on_entry! is called
Hsm.trace_exit(sm, state::Symbol)     # Before on_exit! is called
Hsm.trace_initial(sm, state::Symbol)  # Before on_initial! is called

# Choice lifecycle
Hsm.trace_choice_begin(sm, from::Symbol, owner::Symbol)
Hsm.trace_choice_selected(sm, from::Symbol, target::Symbol)
Hsm.trace_choice_end(sm, from::Symbol, target::Symbol)
```

### Example: Logging State Machine Activity

```julia
using Hsm

@hsmdef mutable struct MonitoredSm
    log::Vector{String}
end

@statedef MonitoredSm :StateA
@statedef MonitoredSm :StateB

# Override trace hooks for logging
Hsm.trace_entry(sm::MonitoredSm, state::Symbol) = 
    push!(sm.log, "Entering: $state")

Hsm.trace_exit(sm::MonitoredSm, state::Symbol) = 
    push!(sm.log, "Exiting: $state")

Hsm.trace_dispatch_start(sm::MonitoredSm, event::Symbol, arg) = 
    push!(sm.log, "Dispatch: $event")

# Use the state machine - trace hooks will log activity
sm = MonitoredSm(String[])
Hsm.dispatch!(sm, :SomeEvent)
println(sm.log)  # See all logged activity
```

### Performance Characteristics

- **Default (no override)**: Zero cost - hooks are inlined and optimized away completely
- **With override**: Only the specific state machine type you override incurs the tracing overhead
- **Other types**: Unaffected - they continue to use the zero-cost default implementations

This design allows you to add detailed instrumentation during development and debugging without affecting production performance when tracing is not needed.

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

### Precompiling a Downstream Machine

Hsm specializes dispatch and transition paths for each concrete state machine.
If first-use latency matters, a downstream package can add a deterministic
`PrecompileTools` workload after declaring all states and handlers:

```julia
using PrecompileTools

@setup_workload begin
    @compile_workload begin
        sm = MyMachine()
        Hsm.dispatch!(sm, :RepresentativeEvent, nothing)
    end
end
```

Replace the placeholders with representative event sequences and argument
types used by the application. Include history, choice, completion, or
termination paths only when the machine uses them. Keep workloads bounded and
deterministic; precompiling one event signature does not compile unrelated
argument types or transition paths.

This workload belongs in the downstream package because Hsm cannot know its
state graph in advance. For an application image or sysimage, exercise the same
representative workload while building the image. Broader workloads can reduce
first-use latency but increase precompile time and cache size, so measure that
tradeoff for the application.

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

## License

MIT
