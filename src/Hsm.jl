module Hsm

using ValSplit

# Include the original macros file
include("macros.jl")

export EventHandled, EventNotHandled
export current, current!, source, source!, event, event!, ancestor
export on_initial!, on_entry!, on_exit!, on_event!
export transition!, dispatch!
export @on_event, @on_initial, @ancestor, @on_entry, @on_exit, @hsmdef
export HsmMacroError, HsmStateError, HsmEventError
export @valsplit

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
    event(sm)

Get current event of state machine `sm`. This is useful in default event handlers
to determine which event triggered the handler.

# Example
```julia
@on_event :StateA Any function(sm::MyStateMachine, arg)
    println("Default handler called with event: ", Hsm.event(sm))
    return Hsm.EventHandled
end
```

# Implementation Example
```julia
Hsm.event(sm::HsmTest) = sm.event
```
"""
function event end

"""
    event!(sm, event::Symbol)

Set current event of state machine `sm` to `event`. This is called automatically
by the dispatch! function before processing an event.

# Implementation Example
```julia
Hsm.event!(sm::HsmTest, event) = sm.event = event
```
"""
function event! end

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

Initial transitions must transition to a child state of `state` or return [`EventHandled`](@ref)
when the transition is complete.

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

function do_entry!(sm, s::Symbol, t::Symbol)
    if s == t
        return
    end
    do_entry!(sm, s, ancestor(sm, t))
    on_entry!(sm, t)
    return
end

function do_exit!(sm, s::Symbol, t::Symbol)
    while s != t
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
    exited before entering the target state. [`transition!`](@ref) will always return [`EventHandled`](@ref).

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

    # Perform exit transitions from the current state
    do_exit!(sm, c, lca)

    # Call action function
    action()

    # Perform entry transitions to the target state
    do_entry!(sm, lca, t)

    # Set the source to current for initial transition
    current!(sm, t)
    source!(sm, t)

    on_initial!(sm, t)
end

"""
    isancestorof(sm, a, b)

Check if state `a` is an ancestor (superstate) of state `b` in state machine `sm`.

# Example
```julia
false == isancestorof(sm, State_S1, State_S2)
```
"""
function isancestorof(sm, a, b)
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
    s = current(sm)

    # Store the current event being dispatched
    event!(sm, event)

    # Find the main source state by calling on_event! until the event is handled
    while true
        source!(sm, s)
        if on_event!(sm, s, event, arg) == EventHandled
            return EventHandled
        end
        s != :Root || break
        s = ancestor(sm, s)
    end

    return EventNotHandled
end

end # module Hsm
