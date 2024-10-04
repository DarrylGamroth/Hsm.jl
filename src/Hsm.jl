module Hsm

using ValSplit

abstract type AbstractHsmStateMachine end
@enum EventReturn EventNotHandled EventHandled

@valsplit on_initial!(sm::AbstractHsmStateMachine, Val(state::Symbol)) = EventHandled
@valsplit on_entry!(sm::AbstractHsmStateMachine, Val(state::Symbol)) = nothing
@valsplit on_exit!(sm::AbstractHsmStateMachine, Val(state::Symbol)) = nothing
# @valsplit on_entry!(sm::AbstractHsmStateMachine, Val(state::Symbol)) = print("$(state)-ENTRY;")
# @valsplit on_exit!(sm::AbstractHsmStateMachine, Val(state::Symbol)) = print("$(state)-EXIT;")

# Generic on_event! handler for unhandled events
# @valsplit on_event!(sm::AbstractHsmStateMachine, Val(state::Symbol), Val(event::Symbol)) = EventNotHandled
@valsplit function on_event!(sm::AbstractHsmStateMachine, Val(state::Symbol), Val(event::Symbol))
    if state === :Root
        return EventHandled
    end
    return EventNotHandled
end

# Event handler for Root state. Events are considered handled if they reach the Root state - Don't know if this works
# with valsplit
function on_event!(::AbstractHsmStateMachine, ::Val{:Root}, event::Symbol)
    @warn "Unhandled event $(event)"
    return EventHandled
end

@valsplit function ancestor(Val(state::Symbol))
    # @error("No ancestor for state $state")
    # while true
    #     sleep(1)
    # end
    return :NoAncestor
end

function do_entry!(sm::AbstractHsmStateMachine, s, t)
    if s == t
        return
    end
    do_entry!(sm, s, ancestor(t))
    on_entry!(sm, t)
    return
end

function do_exit!(sm::AbstractHsmStateMachine, s, t)
    while s !== t
        on_exit!(sm, s)
        s = ancestor(s)
    end
    return
end

function transition!(sm::AbstractHsmStateMachine, t)
    return transition!(Returns(nothing), sm, t)
end

function transition!(action::Function, sm::AbstractHsmStateMachine, t)
    c = current(sm)
    s = source(sm)
    lca = find_lca(s, t)

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


# Is 's' a child of 't', I think I need to flip this around
function isancestorof_recursive(s, t)
    if s == :Root || t == :Root
        return false
    elseif s == t
        return true
    end
    isancestorof_recursive(ancestor(s), t)
end

function find_lca_recursive(s, t)
    if s == :Root || t == :Root
        return s
    end

    if s == t
        return ancestor(s)
    end

    if isancestorof(s, t)
        return find_lca_recursive(ancestor(s), t)
    else
        return find_lca_recursive(s, ancestor(t))
    end
end

@inline function isancestorof(s, t)
    while s !== :Root
        if s == t
            return true
        end
        s = ancestor(s)
    end
    return false
end

# I think I need to flip this around
function find_lca_iterative(s, t)
    while s !== :Root && t !== :Root
        if s == t
            return ancestor(s)
        elseif isancestorof(s, t)
            s = ancestor(s)
        else
            t = ancestor(t)
        end
    end
    return :Root
end

const find_lca = find_lca_iterative

function current(::AbstractHsmStateMachine) end
function current!(::AbstractHsmStateMachine, state) end
function source(::AbstractHsmStateMachine) end
function source!(::AbstractHsmStateMachine, state) end
function event(::AbstractHsmStateMachine) end

function dispatch!(sm::AbstractHsmStateMachine)
    s = current(sm)
    e = event(sm)
    # Find the main source state by calling on_event! until the event is handled
    while true
        source!(sm, s)
        if on_event!(sm, s, e) == EventHandled
            return
        end
        s = ancestor(s)
    end
end

export AbstractHsmState, AbstractHsmMachine
export on_initial!, on_entry!, on_exit!, on_event!
export transition!, dispatch!
export EventHandled, EventNotHandled

end # module Hsm
