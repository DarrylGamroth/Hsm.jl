module Hsm

using ValSplit

# Include the original macros file
include("macros.jl")

export EventHandled, EventNotHandled
export current, current!, source, source!, ancestor
export on_initial!, on_entry!, on_exit!, on_event!
export transition!, dispatch!
export @on_event, @on_initial, @on_entry, @on_exit, @hsmdef, @abstracthsmdef, @statedef, @super
export HsmMacroError, HsmStateError, HsmEventError
export ValSplit

"""
    EventReturn

Enumeration of the possible return values from [`on_event!`](@ref) function.

    Returns:
        EventNotHandled: The event was not handled by the state machine.
        EventHandled: The event was handled by the state machine.
"""
@enum EventReturn EventNotHandled EventHandled

"""
    current(sm)

Get current state of state machine `sm`.

# Implementation Example
```julia
Hsm.current(sm::HsmTest) = sm.current
```
"""
function current end

"""
    current!(sm, state::Symbol)

Set current state of state machine `sm` to `state`.

# Implementation Example
```julia
Hsm.current!(sm::HsmTest, state) = sm.current = state
```
"""
function current! end

"""
    source(sm)

Get source state of state machine `sm`.

# Implementation Example
```julia
Hsm.source(sm::HsmTest) = sm.source
```
"""
function source end

"""
    source!(sm, state::Symbol)

Set source state of state machine `sm` to `state`.

# Implementation Example
```julia
Hsm.source!(sm::HsmTest, state) = sm.source = state
```
"""
function source! end

"""
    ancestor(sm, state::Val{STATE})

Get ancestor (superstate) of `state` in state machine `sm`. Ensure the top most state
ancestor is [`:Root`](@ref).

# Implementaiton Example
To speficfy the ancestor for `sm`=HsmState State_S is [`:Root`](@ref):
```julia
Hsm.ancestor(sm::HsmTest, ::Val{State_S}) = :Root
```

Note: A default implementation is automatically added by the `@hsmdef` macro for each
state machine type, which reports an error for undefined states and handles the :Root state.
"""
function ancestor end

"""
    on_initial!(sm, state::Val{STATE})

Handle initial transition to `state` in state machine `sm`.

Initial transitions must transition to a child state of `state` and ultimately return
[`EventHandled`](@ref) when the transition is complete. Returning any other value will throw.

# Example
```julia
function Hsm.on_initial!(sm::HsmTest, state::Val{Top})
    handled = transition!(sm, State_S2) do
        # Do something on the transition
        sm.foo = 0
    end
    return handled
end
```
or
```julia
Hsm.on_initial!(sm::HsmTest, state::Val{State_S}) =
    Hsm.transition!(sm, State_S11) do
        # Do something on the transition
    end
```

Note: The default implementation of `on_initial!` is automatically defined by
the `@hsmdef` macro for each state machine type, which returns `EventHandled`.
"""
function on_initial! end

"""
    on_entry!(sm, state::Val{STATE})

Entry action for `state` in state machine `sm`.

# Example
```julia
function Hsm.on_entry!(sm::HsmTest, state::Val{State_S2})
    # Do something on entry
end
```

Note: The default implementation of `on_entry!` is automatically defined by
the `@hsmdef` macro for each state machine type, which does nothing.
"""
function on_entry! end

"""
    on_exit!(sm, state::Val{STATE})

Exit action for `state` in state machine `sm`.

# Example
```julia
function Hsm.on_exit!(sm::HsmTest, state::Val{State_S2})
    # Do something on exit
end
```

Note: The default implementation of `on_exit!` is automatically defined by
the `@hsmdef` macro for each state machine type, which does nothing.
"""
function on_exit! end

"""
    on_event!(sm, state::Val{STATE}, event::Val{:EVENT}, arg)

Handle `event` in `state` of state machine `sm`.

Return [`EventHandled`](@ref) if `event` was handled or [`EventNotHandled`](@ref) if `event` was not handled.

# Example
To define an event handler for `sm`=HsmTest, state=State_S1, `event`=:Event_D
```julia
function Hsm.on_event!(sm::HsmTest, state::Val{State_S1}, event::Val{:Event_D}, arg)
    if sm.foo == 0
        return Hsm.transition!(sm, State_S1) do
            sm.foo = 0
        end
    else
        return EventNotHandled
    end
end
```
Or if the `event` is an internal transition which does not change the state:
```julia
function Hsm.on_event!(sm::HsmTest, state::Val{State_S2}, event::Val{:Event_I}, arg)
    if sm.foo == 0
        sm.foo = 1
        return EventHandled
    else
        return EventNotHandled
    end
end
```

Note: The default implementation of `on_event!` is automatically defined by
the `@hsmdef` macro for each state machine type, which returns `EventNotHandled`.
"""
function on_event! end

# --- Tracing hooks (internal, opt-in via multiple dispatch) ---
# Default implementations are no-ops and get inlined away.
# Users may extend these for their state machine type, e.g.,
#   function Hsm.trace_entry(sm::MyMachine, state::Symbol); @info "enter" state; end

"""
    trace_dispatch_start(sm, event::Symbol, arg)

Tracing hook called at the beginning of event dispatch, before any state handlers are tried.

# Arguments
- `sm`: The state machine instance
- `event::Symbol`: The event being dispatched
- `arg`: The argument passed with the event

# Default Behavior
The default implementation is a no-op that gets completely inlined away at compile time.

# Example
```julia
function Hsm.trace_dispatch_start(sm::MyStateMachine, event::Symbol, arg)
    @info "Dispatching event" event arg
end
```

Note: This is an internal tracing hook. Override it for your specific state machine type
to add custom instrumentation without affecting other state machines.
"""
@inline function trace_dispatch_start(@nospecialize(sm), event::Symbol, arg) end

"""
    trace_dispatch_attempt(sm, state::Symbol, event::Symbol)

Tracing hook called before attempting to handle an event in a specific state.

# Arguments
- `sm`: The state machine instance
- `state::Symbol`: The state whose handler will be tried
- `event::Symbol`: The event being handled

# Default Behavior
The default implementation is a no-op that gets completely inlined away at compile time.

# Example
```julia
function Hsm.trace_dispatch_attempt(sm::MyStateMachine, state::Symbol, event::Symbol)
    @info "Trying handler" state event
end
```

Note: This hook is called for each state in the hierarchy during event propagation,
from the current state up to `:Root`, until a handler returns `EventHandled`.
"""
@inline function trace_dispatch_attempt(@nospecialize(sm), state::Symbol, event::Symbol) end

"""
    trace_dispatch_result(sm, state::Symbol, event::Symbol, result)

Tracing hook called after a state's event handler returns a result.

# Arguments
- `sm`: The state machine instance
- `state::Symbol`: The state whose handler was tried
- `event::Symbol`: The event that was handled
- `result`: The return value from the handler (`EventHandled`, `EventNotHandled`, or transition result)

# Default Behavior
The default implementation is a no-op that gets completely inlined away at compile time.

# Example
```julia
function Hsm.trace_dispatch_result(sm::MyStateMachine, state::Symbol, event::Symbol, result)
    @info "Handler result" state event result
end
```

Note: This hook is useful for tracking which state handled an event and how.
"""
@inline function trace_dispatch_result(@nospecialize(sm), state::Symbol, event::Symbol, result) end

"""
    trace_transition_begin(sm, from::Symbol, to::Symbol, lca::Symbol)

Tracing hook called at the start of a state transition.

# Arguments
- `sm`: The state machine instance
- `from::Symbol`: The current state before transition
- `to::Symbol`: The target state for the transition
- `lca::Symbol`: The least common ancestor of `from` and `to`

# Default Behavior
The default implementation is a no-op that gets completely inlined away at compile time.

# Example
```julia
function Hsm.trace_transition_begin(sm::MyStateMachine, from::Symbol, to::Symbol, lca::Symbol)
    @info "Transition starting" from to lca
end
```

Note: This is the first hook called during a transition, before any exit handlers.
"""
@inline function trace_transition_begin(@nospecialize(sm), from::Symbol, to::Symbol, lca::Symbol) end

"""
    trace_transition_action(sm, from::Symbol, to::Symbol)

Tracing hook called just before the transition action function executes.

# Arguments
- `sm`: The state machine instance
- `from::Symbol`: The source state of the transition
- `to::Symbol`: The target state of the transition

# Default Behavior
The default implementation is a no-op that gets completely inlined away at compile time.

# Example
```julia
function Hsm.trace_transition_action(sm::MyStateMachine, from::Symbol, to::Symbol)
    @info "Transition action executing" from to
end
```

Note: This hook is called after all exit handlers and before any entry handlers.
The transition action (if provided) runs immediately after this hook.
"""
@inline function trace_transition_action(@nospecialize(sm), from::Symbol, to::Symbol) end

"""
    trace_transition_end(sm, from::Symbol, to::Symbol)

Tracing hook called when a state transition completes.

# Arguments
- `sm`: The state machine instance
- `from::Symbol`: The original state before transition
- `to::Symbol`: The direct target state requested by the transition (not the final state after initial transitions)

# Default Behavior
The default implementation is a no-op that gets completely inlined away at compile time.

# Example
```julia
function Hsm.trace_transition_end(sm::MyStateMachine, from::Symbol, to::Symbol)
    @info "Transition complete" from to
    sm.transition_count += 1
end
```

Note: This is the last hook called during a transition, after all entry and initial handlers.
"""
@inline function trace_transition_end(@nospecialize(sm), from::Symbol, to::Symbol) end

"""
    trace_entry(sm, state::Symbol)

Tracing hook called before entering a state (before `on_entry!` is called).

# Arguments
- `sm`: The state machine instance
- `state::Symbol`: The state being entered

# Default Behavior
The default implementation is a no-op that gets completely inlined away at compile time.

# Example
```julia
function Hsm.trace_entry(sm::MyStateMachine, state::Symbol)
    @info "Entering state" state
    push!(sm.state_history, state)
end
```

Note: During hierarchical transitions, this hook is called for each state from the
least common ancestor down to the target state.
"""
@inline function trace_entry(@nospecialize(sm), state::Symbol) end

"""
    trace_exit(sm, state::Symbol)

Tracing hook called before exiting a state (before `on_exit!` is called).

# Arguments
- `sm`: The state machine instance
- `state::Symbol`: The state being exited

# Default Behavior
The default implementation is a no-op that gets completely inlined away at compile time.

# Example
```julia
function Hsm.trace_exit(sm::MyStateMachine, state::Symbol)
    @info "Exiting state" state
    sm.exit_count[state] = get(sm.exit_count, state, 0) + 1
end
```

Note: During hierarchical transitions, this hook is called for each state from the
current state up to the least common ancestor.
"""
@inline function trace_exit(@nospecialize(sm), state::Symbol) end

"""
    trace_initial(sm, state::Symbol)

Tracing hook called before an initial transition handler (before `on_initial!` is called).

# Arguments
- `sm`: The state machine instance
- `state::Symbol`: The state whose initial handler will be called

# Default Behavior
The default implementation is a no-op that gets completely inlined away at compile time.

# Example
```julia
function Hsm.trace_initial(sm::MyStateMachine, state::Symbol)
    @info "Initial transition" state
end
```

Note: Initial transitions allow hierarchical states to transition to a default child state.
This hook is called during state machine initialization and after transitions to parent states.
"""
@inline function trace_initial(@nospecialize(sm), state::Symbol) end


function do_entry!(sm, s::Symbol, t::Symbol)
    if s == t
        return
    end
    do_entry!(sm, s, ancestor(sm, t))
    trace_entry(sm, t)
    on_entry!(sm, t)
    return
end

function do_exit!(sm, s::Symbol, t::Symbol)
    while s != t
        trace_exit(sm, s)
        on_exit!(sm, s)
        s = ancestor(sm, s)
    end
    return
end

"""
    transition!(sm, t::Symbol)
    transition!(action::Function, sm, t::Symbol)

Transition state machine `sm` to state `t`.
The `action` function will be called, if specified, during the transition when the main source state has
    exited before entering the target state. This returns [`EventHandled`](@ref) and throws if `on_initial!`
    returns anything else.

# Example
```julia
transition!(sm, State_S2) do
    # Do something on the transition
    sm.foo = 0
end
```
"""
function transition!(sm, t::Symbol)
    transition!(Returns(nothing), sm, t)
end

function transition!(action::Function, sm, t::Symbol)
    c = current(sm)
    s = source(sm)
    lca = find_lca(sm, s, t)

    # Trace transition lifecycle
    trace_transition_begin(sm, c, t, lca)

    # Perform exit transitions from the current state
    do_exit!(sm, c, lca)

    # Call action function
    trace_transition_action(sm, c, t)
    action()

    # Perform entry transitions to the target state
    do_entry!(sm, lca, t)

    # Set the source to current for initial transition
    current!(sm, t)
    source!(sm, t)
    trace_initial(sm, t)
    result = on_initial!(sm, t)

    # Transition complete
    trace_transition_end(sm, c, t)
    if result !== EventHandled
        throw(HsmEventError("on_initial! must return EventHandled after transitioning to $t"))
    end
    return EventHandled
end

"""
    isancestorof(sm, a::Symbol, b::Symbol)

Check if state `a` is an ancestor (superstate) of state `b` in state machine `sm`.

# Example
```julia
false == isancestorof(sm, State_S1, State_S2)
```
"""
function isancestorof(sm, a::Symbol, b::Symbol)
    # :Root is an ancestor of everything (including itself)
    if a == :Root
        return true
    end

    # A state is not its own ancestor (except :Root)
    if a == b
        return false
    end

    # Traverse up the hierarchy from b
    while b != :Root
        b = ancestor(sm, b)
        if a == b
            return true
        end
    end

    return false
end

"""
    find_lca(sm, s::Symbol, t::Symbol)

Find the least common ancestor of states `s` and `t` in state machine `sm`.

Returns the least common ancestor of `s` and `t` or [`:Root`](@ref) if no common ancestor is found.
Self transitions are treated as external transitions, so when `s == t` this returns the ancestor of `s`.
"""

@inline function find_lca(sm, s::Symbol, t::Symbol)
    # Handle case where main source is equal to target
    if s == t
        return ancestor(sm, s)
    end

    while s != :Root
        t1 = t
        while t1 != :Root
            if t1 == s
                return t1
            end
            t1 = ancestor(sm, t1)
        end
        s = ancestor(sm, s)
    end
    return :Root
end

"""
    dispatch!(sm, event::Symbol, arg=nothing)

Dispatch the event in state machine `sm`.
"""
function dispatch!(sm, event::Symbol, arg=nothing)
    trace_dispatch_start(sm, event, arg)
    s = current(sm)

    # Find the main source state by calling on_event! until the event is handled
    while true
        source!(sm, s)
        trace_dispatch_attempt(sm, s, event)
        result = on_event!(sm, s, event, arg)
        trace_dispatch_result(sm, s, event, result)
        if result == EventHandled
            return EventHandled
        end
        s != :Root || break
        s = ancestor(sm, s)
    end

    return EventNotHandled
end

end # module Hsm
