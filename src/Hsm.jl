module Hsm

using ValSplit

"""
    AbstractHsmStateMachine

Interface type for a hierarchical state machine.

Interface definition:

| Required Methods         | Description                                         |
|--------------------------|-----------------------------------------------------|
| `current(sm)`            | Get current state of state machine `sm`             |
| `current!(sm, state)`    | Set current state of state machine `sm` to `state`  |
| `source(sm)`             | Get source state of state machine `sm`              |
| `source!(sm, state)`     | Set source state of state machine `sm` to `state`   |

# Example
```julia
mutable struct HsmTest <: Hsm.AbstractHsmStateMachine
    # Variables used by the AbstractHsmStateMachine interface
    current::StateType
    source::StateType

    # `foo` is an example of a state machine specific variable
    foo::Int

    function HsmTest()
        sm = new()
        # Initialize the state machine
        Hsm.initialize!(sm)
        return sm
    end
end

# Implement the AbstractHsmStateMachine interface
Hsm.current(sm::HsmTest) = sm.current
Hsm.current!(sm::HsmTest, s::StateType) = sm.current = s
Hsm.source(sm::HsmTest) = sm.source
Hsm.source!(sm::HsmTest, s::StateType) = sm.source = s

# Define all states
const Top = Hsm.Root
const State_S = :State_S
const State_S1 = :State_S1
const State_S11 = :State_S11
const State_S2 = :State_S2
const State_S21 = :State_S21
const State_S211 = :State_S211

# Implement the AbstractHsmStateMachine ancestor interface for each state
Hsm.ancestor(sm::HsmTest, ::Val{State_S}) = Top
Hsm.ancestor(sm::HsmTest, ::Val{State_S1}) = State_S
Hsm.ancestor(sm::HsmTest, ::Val{State_S11}) = State_S1
Hsm.ancestor(sm::HsmTest, ::Val{State_S2}) = State_S
Hsm.ancestor(sm::HsmTest, ::Val{State_S21}) = State_S2
Hsm.ancestor(sm::HsmTest, ::Val{State_S211}) = State_S21
```
"""
abstract type AbstractHsmStateMachine end
const StateType = Symbol
const EventType = Symbol

"""
    EventReturn

Enumeration of the possible return values from [`on_event!`](@ref) function.

    Returns:
        EventNotHandled: The event was not handled by the state machine.
        EventHandled: The event was handled by the state machine.
"""
@enum EventReturn EventNotHandled EventHandled

"""
    Root

Root state of the state machine. Used by [`ancestor`](@ref) to specify the top most state.

# Example
```julia
const Top = Hsm.Root
```
"""
const Root = :Root

"""
    current(sm::AbstractHsmStateMachine)

Get current state of state machine `sm`.

# Implementation Example
```julia
Hsm.current(sm::HsmTest) = sm.current
```
"""
function current end

"""
    current!(sm::AbstractHsmStateMachine, state::StateType)

Set current state of state machine `sm` to `state`.

# Implementation Example
```julia
Hsm.current!(sm::HsmTest, state) = sm.current = state
```
"""
function current! end

"""
    source(sm::AbstractHsmStateMachine)

Get source state of state machine `sm`.

# Implementation Example
```julia
Hsm.source(sm::HsmTest) = sm.source
```
"""
function source end

"""
    source!(sm::AbstractHsmStateMachine, state::StateType)

Set source state of state machine `sm` to `state`.

# Implementation Example
```julia
Hsm.source!(sm::HsmTest, state) = sm.source = state
```
"""
function source! end

"""
    initialize!(sm::AbstractHsmStateMachine)

Initialize state machine `sm`.
"""
function initialize!(sm::AbstractHsmStateMachine)
    current!(sm, Root)
    source!(sm, Root)
    on_initial!(sm, Root)
end

"""
    ancestor(sm::AbstractHsmStateMachine, state::Val{STATE})

Get ancestor (superstate) of `state` in state machine `sm`. Ensure the top most state
ancestor is [`Root`](@ref).

# Implementaiton Example
To speficfy the ancestor for `sm`=HsmState State_S is [`Root`](@ref):
```julia
Hsm.ancestor(sm::HsmTest, ::Val{State_S}) = Root
```
"""
@valsplit function ancestor(sm::AbstractHsmStateMachine, Val(state::StateType))
    error("No ancestor for state $state")
    return Root
end

ancestor(::AbstractHsmStateMachine, ::Val{Root}) = Root

"""
    on_initial!(sm::AbstractHsmStateMachine, state::Val{STATE})

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
"""
@valsplit on_initial!(sm::AbstractHsmStateMachine, Val(state::StateType)) = EventHandled

"""
    on_entry!(sm::AbstractHsmStateMachine, state::Val{STATE})

Entry action for `state` in state machine `sm`.

# Example
```julia
function Hsm.on_entry!(sm::HsmTest, state::Val{State_S2})
    # Do something on entry
end
```
"""
@valsplit on_entry!(sm::AbstractHsmStateMachine, Val(state::StateType)) = nothing

"""
    on_exit!(sm::AbstractHsmStateMachine, state::Val{STATE})

Exit action for `state` in state machine `sm`.

# Example
```julia
function Hsm.on_exit!(sm::HsmTest, state::Val{State_S2})
    # Do something on exit
end
```
"""
@valsplit on_exit!(sm::AbstractHsmStateMachine, Val(state::StateType)) = nothing

"""
    on_event!(sm::AbstractHsmStateMachine, state::Val{STATE}, event::Val{:EVENT}, arg)

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
"""
@valsplit function on_event!(
    sm::AbstractHsmStateMachine,
    Val(state::StateType),
    Val(event::EventType),
    arg
)
    return EventNotHandled
end

function do_entry!(sm::AbstractHsmStateMachine, s::StateType, t::StateType)
    if s == t
        return
    end
    do_entry!(sm, s, ancestor(sm, t))
    on_entry!(sm, t)
    return
end

function do_exit!(sm::AbstractHsmStateMachine, s::StateType, t::StateType)
    while s != t
        on_exit!(sm, s)
        s = ancestor(sm, s)
    end
    return
end

"""
    transition!(sm::AbstractHsmStateMachine, t::StateType)
    transition!(action::Function, sm::AbstractHsmStateMachine, t::StateType)

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
function transition!(sm::AbstractHsmStateMachine, t::StateType)
    transition!(Returns(nothing), sm, t)
end

function transition!(action::Function, sm::AbstractHsmStateMachine, t::StateType)
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
    isancestorof(sm::AbstractHsmStateMachine, a, b)

Check if state `a` is an ancestor (superstate) of state `b` in state machine `sm`.

# Example
```julia
false == isancestorof(sm, State_S1, State_S2)
```
"""
function isancestorof(sm, a, b)
    if a == Root
        return false
    end
    while b != Root
        if a == b
            return true
        end
        b = ancestor(sm, b)
    end
    return false
end

"""
    find_lca(sm::AbstractHsmStateMachine, s::StateType, t::StateType)

Find the least common ancestor of states `s` and `t` in state machine `sm`.

Returns the least common ancestor of `s` and `t` or [`Root`](@ref) if no common ancestor is found.
"""
# function find_lca(sm::AbstractHsmStateMachine, s::StateType, t::StateType)
#     # Handle case where main source is equal to target
#     if s == t
#         return ancestor(sm, s)
#     end

#     while s != Root && t != Root
#         if s == t
#             return s
#         elseif isancestorof(sm, s, t)
#             t = ancestor(sm, t)
#         else
#             s = ancestor(sm, s)
#         end
#     end
#     return Root
# end

@inline function find_lca(sm::AbstractHsmStateMachine, s::StateType, t::StateType)
    # Handle case where main source is equal to target
    if s == t
        return ancestor(sm, s)
    end

    while s != Root
        t1 = t
        while t1 != Root
            if t1 == s
                return t1
            end
            t1 = ancestor(sm, t1)
        end
        s = ancestor(sm, s)
    end
    return Root
end

"""
    dispatch!(sm::AbstractHsmStateMachine, event::EventType, arg=nothing)

Dispatch the event in state machine `sm`.
"""
function dispatch!(sm::AbstractHsmStateMachine, event::EventType, arg=nothing)
    s = current(sm)

    # Find the main source state by calling on_event! until the event is handled
    while true
        source!(sm, s)
        if on_event!(sm, s, event, arg) == EventHandled
            return EventHandled
        end
        s != Root || break
        s = ancestor(sm, s)
    end

    return EventNotHandled
end

export AbstractHsmStateMachine
export EventHandled, EventNotHandled, Root
export current, current!, source, source!, ancestor
export initialize!
export on_initial!, on_entry!, on_exit!, on_event!
export transition!, dispatch!

end # module Hsm
