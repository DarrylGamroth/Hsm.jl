module Hsm

using ValSplit

abstract type AbstractHsmStateMachine end
const StateType = Symbol

@enum EventReturn EventNotHandled EventHandled

function current(::AbstractHsmStateMachine) end
function current!(::AbstractHsmStateMachine, state::StateType) end
function source(::AbstractHsmStateMachine) end
function source!(::AbstractHsmStateMachine, state::StateType) end
function event(::AbstractHsmStateMachine) end

root(sm::AbstractHsmStateMachine) = :Root
initialize(sm::AbstractHsmStateMachine) = (current!(sm, root(sm)); source!(sm, root(sm)))

@valsplit function ancestor(sm::AbstractHsmStateMachine, Val(state::StateType))
    @error("No ancestor for state $state")
    return root(sm)
end

@valsplit on_initial!(sm::AbstractHsmStateMachine, Val(state::StateType)) = EventHandled
@valsplit on_entry!(sm::AbstractHsmStateMachine, Val(state::StateType)) = nothing
@valsplit on_exit!(sm::AbstractHsmStateMachine, Val(state::StateType)) = nothing

# Generic on_event! handler for unhandled events
@valsplit function on_event!(
    sm::AbstractHsmStateMachine,
    Val(state::StateType),
    Val(event::StateType),
)
    if state == root(sm)
        return EventHandled
    end
    return EventNotHandled
end

function do_entry!(sm, s, t)
    if s == t
        return
    end
    do_entry!(sm, s, ancestor(sm, t))
    on_entry!(sm, t)
    return
end

function do_exit!(sm, s, t)
    while s != t
        on_exit!(sm, s)
        s = ancestor(sm, s)
    end
    return
end

function transition!(sm::AbstractHsmStateMachine, t::StateType)
    return transition!(Returns(nothing), sm, t)
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

    return on_initial!(sm, t)
end

# Is 'a' an ancestor of 'b'
function isancestorof(sm, a, b)
    if a == root(sm)
        return false
    end
    while b != root(sm)
        if a == b
            return true
        end
        b = ancestor(sm, b)
    end
    return false
end

function find_lca(sm, s, t)
    # Handle case where main source is equal to target
    if s == t
        return ancestor(sm, s)
    end

    while s != root(sm) && t != root(sm)
        if s == t
            return s
        elseif isancestorof(sm, s, t)
            t = ancestor(sm, t)
        else
            s = ancestor(sm, s)
        end
    end
    return root(sm)
end

function dispatch!(sm::AbstractHsmStateMachine)
    s = current(sm)
    e = event(sm)
    # Find the main source state by calling on_event! until the event is handled
    while true
        source!(sm, s)
        if on_event!(sm, s, e) == EventHandled
            return
        end
        s = ancestor(sm, s)
    end
end

export AbstractHsmState, AbstractHsmMachine
export on_initial!, on_entry!, on_exit!, on_event!
export transition!, dispatch!
export EventHandled, EventNotHandled

end # module Hsm
