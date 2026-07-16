module Hsm

using ValSplit

# Include the original macros file
include("macros.jl")

export EventHandled, EventNotHandled
export HistoryKind, ShallowHistory, DeepHistory
export current, current!, source, source!, ancestor
export isrunning, iscomplete, isterminated
export on_initial!, on_entry!, on_exit!, on_event!, on_completion!
export on_history_default!
export transition!, transition_history!, dispatch!
export @on_event, @on_initial, @on_entry, @on_exit, @on_completion
export @on_history_default
export @choice, @hsmdef, @abstracthsmdef, @statedef, @finaldef, @terminatedef
export @historydef, @super
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
    HistoryKind

Mode used by [`transition_history!`](@ref) when restoring a composite state's
previously active configuration.
"""
abstract type HistoryKind end

"""
    ShallowHistory()

Restore the direct child that was active when a composite state was last
exited, then follow that child's normal initial transition.
"""
struct ShallowHistory <: HistoryKind end

"""
    DeepHistory()

Restore the complete state path that was active when a composite state was
last exited without replaying intermediate initial transitions.
"""
struct DeepHistory <: HistoryKind end

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
An initial handler may select at most one unconditional outgoing transition.

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

Entry Behaviors execute inside an already selected transition and cannot
initiate another transition or recursively dispatch an event.

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

Exit Behaviors execute inside an already selected transition and cannot
initiate another transition or recursively dispatch an event.

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

"""
    on_completion!(sm, state::Val{STATE})

Handle the completion event generated by `state`. Completion transitions have
no explicit trigger and are scoped to the state that completed. Define them
with [`@on_completion`](@ref).
"""
@inline on_completion!(@nospecialize(sm), state::Val) = EventNotHandled

"""
    on_history_default!(sm, owner::Val, kind::HistoryKind)

Effect Behavior for an explicit default Transition outgoing from a history
Pseudostate. Define it with [`@on_history_default`](@ref). The default
implementation does nothing.
"""
@inline on_history_default!(@nospecialize(sm), owner::Val, kind::HistoryKind) = nothing

# Fallbacks used by the ValSplit-generated Symbol dispatch methods. Keeping the
# ValSplit wrapper stable lets downstream packages add generic handlers without
# overwriting a method during precompilation.
@inline _on_initial_fallback!(@nospecialize(sm), state::Symbol) = EventHandled
@inline _on_entry_fallback!(@nospecialize(sm), state::Symbol) = nothing
@inline _on_exit_fallback!(@nospecialize(sm), state::Symbol) = nothing
@inline _on_event_fallback!(@nospecialize(sm), state::Symbol, event::Symbol, arg) = EventNotHandled
@inline _on_event_fallback!(sm, ::Val{STATE}, event::Symbol, arg) where {STATE} =
    _on_event_fallback!(sm, STATE, event, arg)

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

"""
    trace_choice_begin(sm, from::Symbol, owner::Symbol)
    trace_choice_selected(sm, from::Symbol, target::Symbol)
    trace_choice_end(sm, from::Symbol, target::Symbol)

Tracing hooks for a compound Transition through a choice Pseudostate. `owner`
is the composite State owning the choice's implicit Region. Defaults are
no-ops.
"""
@inline function trace_choice_begin(@nospecialize(sm), from::Symbol, owner::Symbol) end
@inline function trace_choice_selected(@nospecialize(sm), from::Symbol, target::Symbol) end
@inline function trace_choice_end(@nospecialize(sm), from::Symbol, target::Symbol) end


function do_entry!(sm, s::Symbol, t::Symbol)
    if s == t
        return
    end
    do_entry!(sm, s, ancestor(sm, t))
    trace_entry(sm, t)
    _run_entry_behavior!(sm, t)
    return
end

function do_exit!(sm, s::Symbol, t::Symbol)
    current_state = s
    while s != t
        if s !== current_state
            _record_history_symbol!(sm, s, current_state)
        end
        trace_exit(sm, s)
        _run_exit_behavior!(sm, s)
        s = ancestor(sm, s)
    end
    return
end

# Transition execution phase. Machines created by `@hsmdef` provide concrete
# storage for this interface. The fallback preserves compatibility with
# manually implemented machines, which predate the generated runtime fields.
const _TRANSITION_IDLE = UInt8(0)
const _TRANSITION_EXECUTING = UInt8(1)
const _INITIAL_TRANSITION_ALLOWED = UInt8(2)
const _INITIAL_TRANSITION_CONSUMED = UInt8(3)
const _HANDLING_EVENT = UInt8(4)
const _EVENT_TRANSITION_CONSUMED = UInt8(5)
const _HANDLING_COMPLETION = UInt8(6)
const _COMPLETION_TRANSITION_CONSUMED = UInt8(7)

const _LIFECYCLE_RUNNING = UInt8(0)
const _LIFECYCLE_COMPLETED = UInt8(1)
const _LIFECYCLE_TERMINATED = UInt8(2)

@inline _transition_phase(@nospecialize(sm)) = _TRANSITION_IDLE
@inline _transition_phase!(@nospecialize(sm), phase::UInt8) = phase
@inline _lifecycle(@nospecialize(sm)) = _LIFECYCLE_RUNNING
@inline function _lifecycle!(@nospecialize(sm), status::UInt8)
    throw(HsmStateError(
        "Final and terminate semantics require a state machine defined with @hsmdef",
    ))
end
@inline _pending_completion(@nospecialize(sm)) = nothing
@inline function _pending_completion!(
    @nospecialize(sm),
    state::Union{Nothing,Symbol},
)
    state === nothing && return nothing
    throw(HsmStateError(
        "Completion transitions require a state machine defined with @hsmdef",
    ))
end

"""
    isrunning(sm) -> Bool

Return `true` while `sm` can accept events and transitions. A machine stops
running after it reaches a top-level FinalState or terminate Pseudostate.

# Example
```julia
Hsm.isrunning(sm) && Hsm.dispatch!(sm, :Next)
```
"""
@inline isrunning(sm) = _lifecycle(sm) === _LIFECYCLE_RUNNING

"""
    iscomplete(sm) -> Bool

Return `true` when `sm` has reached a top-level FinalState. Completed machines
reject subsequent calls to [`dispatch!`](@ref) and [`transition!`](@ref).

# Example
```julia
Hsm.dispatch!(sm, :Finish)
@assert Hsm.iscomplete(sm)
```
"""
@inline iscomplete(sm) = _lifecycle(sm) === _LIFECYCLE_COMPLETED

"""
    isterminated(sm) -> Bool

Return `true` when `sm` has reached a terminate Pseudostate. A terminated
machine retains its Julia object for inspection but rejects further execution.

# Example
```julia
Hsm.dispatch!(sm, :Abort)
@assert Hsm.isterminated(sm)
```
"""
@inline isterminated(sm) = _lifecycle(sm) === _LIFECYCLE_TERMINATED

@inline function _ensure_running(sm)
    status = _lifecycle(sm)
    status === _LIFECYCLE_RUNNING && return nothing
    description = status === _LIFECYCLE_COMPLETED ? "completed" : "terminated"
    throw(HsmEventError("Cannot execute a $description state machine"))
end

@inline _begin_transition!(sm) = _begin_transition!(sm, Val(false))

@inline function _begin_transition!(sm, ::Val{INTERNAL}) where {INTERNAL}
    _ensure_running(sm)
    previous = _transition_phase(sm)
    if previous === _TRANSITION_IDLE ||
       (INTERNAL && (previous === _HANDLING_EVENT ||
                     previous === _INITIAL_TRANSITION_ALLOWED ||
                     previous === _HANDLING_COMPLETION))
        _transition_phase!(sm, _TRANSITION_EXECUTING)
        return previous
    end

    context = if previous === _INITIAL_TRANSITION_CONSUMED
        "an initial Pseudostate has already taken its outgoing transition"
    elseif previous === _EVENT_TRANSITION_CONSUMED
        "the active event handler has already taken a transition"
    elseif previous === _COMPLETION_TRANSITION_CONSUMED
        "the active completion handler has already taken a transition"
    elseif previous === _HANDLING_EVENT ||
           previous === _INITIAL_TRANSITION_ALLOWED ||
           previous === _HANDLING_COMPLETION
        "handler transitions must be statically named and lowered by an Hsm handler macro"
    else
        "another transition is already executing"
    end
    throw(HsmEventError("Cannot initiate transition: $context"))
end

@inline function _begin_dispatch!(sm)
    _ensure_running(sm)
    previous = _transition_phase(sm)
    if previous !== _TRANSITION_IDLE
        throw(HsmEventError(
            "Cannot dispatch an event while another run-to-completion step is active",
        ))
    end
    _transition_phase!(sm, _HANDLING_EVENT)
    return previous
end

@inline function _begin_completion_dispatch!(sm)
    _ensure_running(sm)
    previous = _transition_phase(sm)
    previous === _TRANSITION_IDLE || throw(HsmEventError(
        "Cannot process a completion event while another run-to-completion step is active",
    ))
    _transition_phase!(sm, _HANDLING_COMPLETION)
    return previous
end

@inline function _finish_dispatch!(sm, previous::UInt8)
    _transition_phase!(sm, previous)
    return nothing
end

@inline _allow_initial_transition!(sm) =
    _transition_phase!(sm, _INITIAL_TRANSITION_ALLOWED)

@inline function _finish_transition!(sm, previous::UInt8)
    restored = if previous === _INITIAL_TRANSITION_ALLOWED
        _INITIAL_TRANSITION_CONSUMED
    elseif previous === _HANDLING_EVENT
        _EVENT_TRANSITION_CONSUMED
    elseif previous === _HANDLING_COMPLETION
        _COMPLETION_TRANSITION_CONSUMED
    else
        previous
    end
    _transition_phase!(sm, restored)
    return nothing
end

# State registration and per-instance history storage. `@statedef` contributes
# one `_registered_state` method per state. ValSplit turns the finite runtime
# Symbol boundary back into statically specialized code.
@inline _registered_state(sm, ::Val{:Root}) = nothing
function _state_parent_edge end
function _final_state_edge end
function _terminate_state_edge end
function _completion_state_edge end
function _state_behavior_edge end
function _history_owner_edge end
function _history_default_edge end
@inline _history_storage(@nospecialize(sm)) = nothing
@inline _history_storage!(@nospecialize(sm), storage::Vector{Symbol}) = storage

@inline function _registered_states(::Type{SM}) where {SM}
    return ValSplit.valarg_params(
        _registered_state,
        Tuple{SM,Val},
        2,
        Symbol,
    )
end

@inline function _state_parent_pairs(::Type{SM}) where {SM}
    return ValSplit.valarg_params(
        _state_parent_edge,
        Tuple{SM,Val,Val,Val},
        (2, 3),
        Tuple{Symbol,Symbol},
    )
end

@inline function _registered_composite_states(::Type{SM}) where {SM}
    return ValSplit.valarg_params(
        _state_parent_edge,
        Tuple{SM,Val,Val,Val},
        3,
        Symbol,
    )
end

@inline function _registered_final_states(::Type{SM}) where {SM}
    return ValSplit.valarg_params(
        _final_state_edge,
        Tuple{SM,Val,Val},
        2,
        Symbol,
    )
end

@inline function _registered_terminate_states(::Type{SM}) where {SM}
    return ValSplit.valarg_params(
        _terminate_state_edge,
        Tuple{SM,Val,Val},
        2,
        Symbol,
    )
end

@inline function _registered_completion_states(::Type{SM}) where {SM}
    return ValSplit.valarg_params(
        _completion_state_edge,
        Tuple{SM,Val,Val},
        2,
        Symbol,
    )
end

@inline function _registered_state_behaviors(::Type{SM}) where {SM}
    return ValSplit.valarg_params(
        _state_behavior_edge,
        Tuple{SM,Val,Val,Val},
        (2, 3),
        Tuple{Symbol,Symbol},
    )
end

@inline function _registered_history_owners(::Type{SM}) where {SM}
    return ValSplit.valarg_params(
        _history_owner_edge,
        Tuple{SM,Val,Val},
        2,
        Symbol,
    )
end

@inline function _registered_history_defaults(::Type{SM}) where {SM}
    return ValSplit.valarg_params(
        _history_default_edge,
        Tuple{SM,Val,Val,Val,Val},
        (2, 3, 4),
        Tuple{Symbol,Symbol,Symbol},
    )
end

@inline _history_kind_key(::ShallowHistory) = Val(:shallow)
@inline _history_kind_key(::DeepHistory) = Val(:deep)

@generated function _history_default_target(
    ::Val{DEFAULTS},
    ::Val{OWNER},
    ::Val{KIND},
) where {DEFAULTS,OWNER,KIND}
    targets = Tuple(
        target for (owner, kind, target) in DEFAULTS
        if owner === OWNER && kind === KIND
    )
    unique_targets = unique(targets)
    if length(unique_targets) > 1
        message = "History Pseudostate $KIND for $OWNER has conflicting default targets $(unique_targets)"
        return :(throw(HsmStateError($message)))
    elseif isempty(unique_targets)
        return :(nothing)
    end
    target = QuoteNode(only(unique_targets))
    return :(Val{$target}())
end

@inline function _history_default_target(sm::SM, owner::Val, kind::HistoryKind) where {SM}
    return _history_default_target(
        Val(_registered_history_defaults(SM)),
        owner,
        _history_kind_key(kind),
    )
end

@generated function _history_owner_registered(
    ::Val{OWNERS},
    ::Val{OWNER},
) where {OWNERS,OWNER}
    return OWNER in OWNERS ? :(true) : :(false)
end

@generated function _state_in_tuple(
    ::Val{STATES},
    ::Val{STATE},
) where {STATES,STATE}
    return STATE in STATES ? :(true) : :(false)
end

@inline function _is_final_state(sm::SM, state::Val) where {SM}
    return _state_in_tuple(Val(_registered_final_states(SM)), state)
end

@inline function _is_terminate_state(sm::SM, state::Val) where {SM}
    return _state_in_tuple(Val(_registered_terminate_states(SM)), state)
end

@inline function _has_completion_transition(sm::SM, state::Val) where {SM}
    return _state_in_tuple(Val(_registered_completion_states(SM)), state)
end

@generated function _is_final_state_symbol(
    ::Val{FINAL_STATES},
    state::Symbol,
) where {FINAL_STATES}
    fallback = :(false)
    return foldr(FINAL_STATES; init=fallback) do final_state, next
        state_node = QuoteNode(final_state)
        :((state === $state_node) || $next)
    end
end

@inline function _is_final_state_symbol(sm::SM, state::Symbol) where {SM}
    return _is_final_state_symbol(Val(_registered_final_states(SM)), state)
end

@inline function _is_terminate_state_symbol(sm::SM, state::Symbol) where {SM}
    return _is_final_state_symbol(Val(_registered_terminate_states(SM)), state)
end

@generated function _run_static_entry_behavior!(
    ::Val{FINAL_STATES},
    sm,
    state::Val{STATE},
) where {FINAL_STATES,STATE}
    return STATE in FINAL_STATES ? :(nothing) : :(on_entry!(sm, state))
end

@generated function _run_static_exit_behavior!(
    ::Val{FINAL_STATES},
    sm,
    state::Val{STATE},
) where {FINAL_STATES,STATE}
    return STATE in FINAL_STATES ? :(nothing) : :(on_exit!(sm, state))
end

@generated function _record_static_history!(
    ::Val{FINAL_STATES},
    sm,
    owner::Val,
    current::Val{CURRENT},
) where {FINAL_STATES,CURRENT}
    remembered = CURRENT in FINAL_STATES ? :Root : CURRENT
    return :(_set_history!(sm, owner, $(QuoteNode(remembered))))
end

@inline function _run_entry_behavior!(sm, state::Symbol)
    _is_final_state_symbol(sm, state) || on_entry!(sm, state)
    return nothing
end

@inline function _run_exit_behavior!(sm, state::Symbol)
    _is_final_state_symbol(sm, state) || on_exit!(sm, state)
    return nothing
end

@inline function _record_history_symbol!(
    sm,
    owner::Symbol,
    active_leaf::Symbol,
)
    remembered = _is_final_state_symbol(sm, active_leaf) ? :Root : active_leaf
    _set_history_symbol!(sm, owner, remembered)
    return nothing
end

@inline function _schedule_completion!(sm, state::Val{STATE}) where {STATE}
    if _has_completion_transition(sm, state)
        _pending_completion!(sm, STATE)
    end
    return nothing
end

@inline function _schedule_simple_completion!(
    sm,
    state::Val{STATE},
) where {STATE}
    if current(sm) === STATE && !_static_state_has_children(sm, state)
        _schedule_completion!(sm, state)
    end
    return nothing
end

@inline function _enter_final!(sm, state::Val)
    parent = _ancestor_val(sm, state)
    _set_history!(sm, parent, :Root)
    if _val_parameter(parent) === :Root
        _pending_completion!(sm, nothing)
        _lifecycle!(sm, _LIFECYCLE_COMPLETED)
    else
        _schedule_completion!(sm, parent)
    end
    return nothing
end

@inline function _enter_terminate!(sm)
    _pending_completion!(sm, nothing)
    current!(sm, :Root)
    source!(sm, :Root)
    _lifecycle!(sm, _LIFECYCLE_TERMINATED)
    return nothing
end

@inline function _activate_target!(sm, state::Val{STATE}) where {STATE}
    if _is_terminate_state(sm, state)
        _enter_terminate!(sm)
        return nothing
    end

    current!(sm, STATE)
    source!(sm, STATE)
    if _is_final_state(sm, state)
        _enter_final!(sm, state)
        return nothing
    end

    trace_initial(sm, STATE)
    _allow_initial_transition!(sm)
    result = on_initial!(sm, state)
    result === EventHandled || throw(HsmEventError(
        "on_initial! must return EventHandled after transitioning to $STATE",
    ))
    _schedule_simple_completion!(sm, state)
    return nothing
end

@generated function _activate_target_symbol_switch!(
    ::Val{STATES},
    sm,
    target::Symbol,
) where {STATES}
    fallback = if STATES == (:Root,)
        :(_activate_unregistered_target!(sm, target))
    else
        quote
            throw(HsmStateError(
                "Transition target $target is not registered for $(typeof(sm))",
            ))
        end
    end
    return foldr(STATES; init=fallback) do state, next
        state_node = QuoteNode(state)
        quote
            if target === $state_node
                return _activate_target!(sm, Val{$state_node}())
            end
            $next
        end
    end
end

@inline function _activate_unregistered_target!(sm, target::Symbol)
    current!(sm, target)
    source!(sm, target)
    trace_initial(sm, target)
    _allow_initial_transition!(sm)
    result = on_initial!(sm, target)
    result === EventHandled || throw(HsmEventError(
        "on_initial! must return EventHandled after transitioning to $target",
    ))
    return nothing
end

@inline function _activate_target!(sm::SM, target::Symbol) where {SM}
    return _activate_target_symbol_switch!(
        Val(_registered_states(SM)),
        sm,
        target,
    )
end

@generated function _completion_state_switch!(
    ::Val{STATES},
    sm,
    state::Symbol,
) where {STATES}
    fallback = :(EventNotHandled)
    return foldr(STATES; init=fallback) do completion_state, next
        state_node = QuoteNode(completion_state)
        quote
            if state === $state_node
                return on_completion!(sm, Val{$state_node}())
            end
            $next
        end
    end
end

function _drain_completion_events!(sm::SM) where {SM}
    while isrunning(sm)
        completed_state = _pending_completion(sm)
        completed_state === nothing && return nothing
        _pending_completion!(sm, nothing)
        previous_phase = _begin_completion_dispatch!(sm)
        try
            source!(sm, completed_state)
            result = _completion_state_switch!(
                Val(_registered_completion_states(SM)),
                sm,
                completed_state,
            )
            result in (EventHandled, EventNotHandled) || throw(HsmEventError(
                "on_completion! for $completed_state returned an invalid result",
            ))
        finally
            source!(sm, current(sm))
            _finish_dispatch!(sm, previous_phase)
        end
    end
    return nothing
end

@generated function _static_state_has_children(
    ::Val{COMPOSITES},
    ::Val{STATE},
) where {COMPOSITES,STATE}
    return STATE in COMPOSITES ? :(true) : :(false)
end

@inline function _static_state_has_children(sm::SM, state::Val) where {SM}
    return _static_state_has_children(
        Val(_registered_composite_states(SM)),
        state,
    )
end

@inline function _history_owner_registered(sm::SM, owner::Val) where {SM}
    return _history_owner_registered(Val(_registered_history_owners(SM)), owner)
end

function _initialize_history_storage!(sm, ::Nothing, owners)
    isempty(owners) && return nothing
    storage = Vector{Symbol}(undef, length(owners))
    fill!(storage, :Root)
    _history_storage!(sm, storage)
    return nothing
end

function _initialize_history_storage!(sm, storage::Vector{Symbol}, owners)
    resize!(storage, length(owners))
    fill!(storage, :Root)
    return nothing
end

function _initialize_history!(sm::SM) where {SM}
    _initialize_history_storage!(
        sm,
        _history_storage(sm),
        _registered_history_owners(SM),
    )
    return sm
end

function _initialize_machine!(sm)
    _validate_static_hierarchy!(sm)
    _initialize_history!(sm)
    _lifecycle!(sm, _LIFECYCLE_RUNNING)
    _pending_completion!(sm, nothing)
    _transition_phase!(sm, _INITIAL_TRANSITION_ALLOWED)
    try
        result = on_initial!(sm, :Root)
        if result !== EventHandled
            throw(HsmEventError(
                "on_initial! must return EventHandled while initializing :Root",
            ))
        end
    finally
        _transition_phase!(sm, _TRANSITION_IDLE)
    end
    _drain_completion_events!(sm)
    return sm
end

@generated function _history_slot(
    ::Val{STATES},
    ::Val{OWNER},
) where {STATES,OWNER}
    slot = findfirst(==(OWNER), STATES)
    return slot === nothing ? :(0) : :($slot)
end

@inline function _history_slot(sm::SM, owner::Val) where {SM}
    return _history_slot(Val(_registered_history_owners(SM)), owner)
end

@inline function _history_value(storage::Vector{Symbol}, sm, owner::Val{OWNER}) where {OWNER}
    slot = _history_slot(sm, owner)
    if slot == 0 || slot > length(storage)
        throw(HsmStateError(
            "State $OWNER is not available in this machine's initialized history storage",
        ))
    end
    return @inbounds storage[slot]
end

@inline function _history_value(::Nothing, sm, ::Val{OWNER}) where {OWNER}
    throw(HsmStateError(
        "History for state $OWNER requires a state machine defined with @hsmdef",
    ))
end

@inline _history_value(sm, owner::Val) =
    _history_value(_history_storage(sm), sm, owner)

@inline function _set_history!(
    storage::Vector{Symbol},
    sm,
    owner::Val{OWNER},
    remembered::Symbol,
) where {OWNER}
    slot = _history_slot(sm, owner)
    if slot == 0 || slot > length(storage)
        # Recording history must not make an otherwise valid transition fail
        # for a manually extended or not-yet-closed hierarchy. Explicit
        # history restoration still validates its owner through `_history_value`.
        return nothing
    end
    @inbounds storage[slot] = remembered
    return nothing
end

@inline _set_history!(::Nothing, sm, owner::Val, remembered::Symbol) = nothing

@inline _set_history!(sm, owner::Val, remembered::Symbol) =
    _set_history!(_history_storage(sm), sm, owner, remembered)

@generated function _is_composite_state_switch(
    ::Val{STATES},
    sm,
    ::Val{OWNER},
) where {STATES,OWNER}
    checks = Any[]
    for state in STATES
        state === :Root && continue
        state_node = QuoteNode(state)
        push!(checks, :(
            _val_parameter(_ancestor_val(sm, Val{$state_node}())) === $(QuoteNode(OWNER))
        ))
    end
    isempty(checks) && return :(false)
    return foldr((check, rest) -> :($check || $rest), checks; init=:(false))
end

@inline function _is_composite_state(sm::SM, owner::Val) where {SM}
    return _is_composite_state_switch(Val(_registered_states(SM)), sm, owner)
end

@generated function _set_history_symbol_switch!(
    ::Val{STATES},
    storage::Vector{Symbol},
    sm,
    owner::Symbol,
    remembered::Symbol,
) where {STATES}
    fallback = :(return nothing)
    return foldr(STATES; init=fallback) do state, next
        state === :Root && return next
        state_node = QuoteNode(state)
        quote
            if owner === $state_node
                return _set_history!(
                    storage,
                    sm,
                    Val{$state_node}(),
                    remembered,
                )
            end
            $next
        end
    end
end

@inline _set_history_symbol!(::Nothing, sm, owner::Symbol, remembered::Symbol) = nothing

@inline function _set_history_symbol!(
    storage::Vector{Symbol},
    sm::SM,
    owner::Symbol,
    remembered::Symbol,
) where {SM}
    return _set_history_symbol_switch!(
        Val(_registered_history_owners(SM)),
        storage,
        sm,
        owner,
        remembered,
    )
end

@inline _set_history_symbol!(sm, owner::Symbol, remembered::Symbol) =
    _set_history_symbol!(_history_storage(sm), sm, owner, remembered)

# Static transition machinery
#
# Handler macros carry literal source and target states as Val parameters.
# `@statedef` supplies the concrete current-state methods used when an ancestor
# handles an event. Runtime Symbols remain the stored/public representation.

@inline _val_parameter(::Val{T}) where {T} = T

struct _StatePath{STATE,PARENT} end

@inline _state_path(sm, ::Val{:Root}) = _StatePath{:Root,Nothing}()
@inline function _state_path(sm, ::Val{STATE}) where {STATE}
    throw(HsmStateError("No static path registered for state $STATE"))
end

@inline _ancestor_val(sm, ::Val{:Root}) = Val(:Root)
@inline function _ancestor_val(sm, ::Val{STATE}) where {STATE}
    throw(HsmStateError("No static parent registered for state $STATE"))
end
@inline _static_state_registered(sm, ::Val) = false
@inline _static_state_registered(sm, ::Val{:Root}) = true

@inline function _initial_transition_from!(
    sm,
    source_state::Val,
    target::Val,
)
    return _initial_transition_from!(
        Returns(nothing),
        sm,
        source_state,
        target,
    )
end

@inline function _initial_transition_from!(
    action::F,
    sm,
    source_state::Val{SOURCE},
    target::Val,
) where {F<:Function,SOURCE}
    if !_static_state_registered(sm, source_state) ||
       !_static_state_registered(sm, target)
        return _transition_dynamic_from_handler!(
            action,
            sm,
            _val_parameter(target),
        )
    end
    current(sm) === SOURCE || throw(HsmStateError(
        "Initial transition source $SOURCE is not the active state",
    ))
    return _transition_static!(
        action,
        sm,
        source_state,
        source_state,
        target,
    )
end

@inline function _initial_transition_history_from!(
    sm,
    source_state::Val,
    owner::Val,
    kind::HistoryKind,
)
    return _initial_transition_history_from!(
        Returns(nothing),
        sm,
        source_state,
        owner,
        kind,
    )
end

@inline function _initial_transition_history_from!(
    action::F,
    sm,
    source_state::Val{SOURCE},
    owner::Val,
    kind::HistoryKind,
) where {F<:Function,SOURCE}
    current(sm) === SOURCE || throw(HsmStateError(
        "Initial transition source $SOURCE is not the active state",
    ))
    return _transition_history_from!(action, sm, source_state, owner, kind)
end

@inline function _transition_from!(sm, source_state::Val, target::Val)
    return _transition_from!(Returns(nothing), sm, source_state, target)
end

@inline function _transition_from!(
    action::F,
    sm,
    source_state::Val{S},
    target::Val,
) where {F<:Function,S}
    if !_static_state_registered(sm, source_state) ||
       !_static_state_registered(sm, target)
        return _transition_dynamic_from_handler!(
            action,
            sm,
            _val_parameter(target),
        )
    end

    current_state = current(sm)
    if current_state === S
        return _transition_static!(action, sm, source_state, source_state, target)
    end
    if !_static_state_has_children(sm, source_state)
        throw(HsmStateError(
            "Transition source $S is not active below current state $current_state",
        ))
    end
    return _split_transition_from_current!(
        action,
        sm,
        current_state,
        source_state,
        target,
    )
end

@inline function _transition_from_current_fallback!(
    action::F,
    sm,
    current_state::Symbol,
    source_state::Val,
    target::Val,
) where {F<:Function}
    throw(HsmStateError(
        "Current state $current_state is not an active descendant of transition " *
        "source $(_val_parameter(source_state))",
    ))
end

@generated function _transition_from_current_switch!(
    ::Val{STATES},
    action::F,
    sm::SM,
    current_state::Symbol,
    source_state::S,
    target::T,
) where {STATES,F<:Function,SM,S<:Val,T<:Val}
    fallback = quote
        return _transition_from_current_fallback!(
            action,
            sm,
            current_state,
            source_state,
            target,
        )
    end

    return foldr(STATES; init=fallback) do state, next
        state_node = QuoteNode(state)
        quote
            if current_state === $state_node
                return _transition_from_current!(
                    action,
                    sm,
                    Val{$state_node}(),
                    source_state,
                    target,
                )
            end
            $next
        end
    end
end

@generated function _static_descendant_states(
    ::Val{STATES},
    ::Val{PARENT_PAIRS},
    ::Val{SOURCE},
) where {STATES,PARENT_PAIRS,SOURCE}
    try
        parents = _static_parent_map(PARENT_PAIRS)
        descendants = Tuple(
            state for state in STATES
            if state !== SOURCE && SOURCE in _static_ancestry(parents, state)
        )
        return QuoteNode(descendants)
    catch error
        message = sprint(showerror, error)
        return :(throw(HsmStateError($message)))
    end
end

@inline function _split_transition_from_current!(
    action::F,
    sm::SM,
    current_state::Symbol,
    source_state::S,
    target::T,
) where {F<:Function,SM,S<:Val,T<:Val}
    registered_current_states = ValSplit.valarg_params(
        _transition_from_current!,
        Tuple{F,SM,Val,S,T},
        3,
        Symbol,
    )
    current_states = _static_descendant_states(
        Val(registered_current_states),
        Val(_state_parent_pairs(SM)),
        source_state,
    )
    return _transition_from_current_switch!(
        Val(current_states),
        action,
        sm,
        current_state,
        source_state,
        target,
    )
end

@inline function _transition_from_current!(
    action::F,
    sm,
    current_state::Val{:Root},
    source_state::Val,
    target::Val,
) where {F<:Function}
    if !_static_isancestor(sm, source_state, current_state)
        throw(HsmStateError(
            "Transition source $(_val_parameter(source_state)) is not active " *
            "below current state :Root",
        ))
    end
    return _transition_static!(action, sm, current_state, source_state, target)
end

function _static_parent_map(parent_pairs)
    parents = Dict{Symbol,Symbol}(:Root => :Root)
    for (child, parent) in parent_pairs
        if haskey(parents, child) && parents[child] !== parent
            throw(HsmStateError(
                "State $child has conflicting parents $(parents[child]) and $parent",
            ))
        end
        parents[child] = parent
    end
    return parents
end

function _static_ancestry(parents, state::Symbol)
    path = Symbol[]
    seen = Set{Symbol}()
    while true
        state in seen && throw(HsmStateError("Cycle detected at state $state"))
        push!(seen, state)
        push!(path, state)
        state === :Root && return path
        haskey(parents, state) || throw(HsmStateError(
            "No static parent registered for state $state",
        ))
        state = parents[state]
    end
end

function _validate_static_parent_pairs(parent_pairs)
    parents = _static_parent_map(parent_pairs)
    for state in keys(parents)
        _static_ancestry(parents, state)
    end
    return nothing
end

function _validate_history_default_edges(parent_pairs, defaults)
    parents = _static_parent_map(parent_pairs)
    seen = Dict{Tuple{Symbol,Symbol},Symbol}()
    for (owner, kind, target) in defaults
        kind in (:shallow, :deep) || throw(HsmStateError(
            "Unknown history kind $kind for default edge owned by $owner",
        ))
        owner === :Root && throw(HsmStateError(
            ":Root cannot own a history Pseudostate",
        ))
        haskey(parents, owner) || throw(HsmStateError(
            "History owner $owner is not a registered state",
        ))
        any(==(owner), values(parents)) || throw(HsmStateError(
            "History owner $owner is not a composite state",
        ))
        haskey(parents, target) || throw(HsmStateError(
            "Default history target $target is not a registered state",
        ))
        target === owner && throw(HsmStateError(
            "Default history target must be below owner $owner",
        ))
        owner in _static_ancestry(parents, target) || throw(HsmStateError(
            "Default history target $target is not below owner $owner",
        ))

        key = (owner, kind)
        if haskey(seen, key) && seen[key] !== target
            throw(HsmStateError(
                "History Pseudostate $kind for $owner has conflicting default " *
                "targets $(seen[key]) and $target",
            ))
        end
        seen[key] = target
    end
    return nothing
end

function _validate_terminal_vertices(
    parent_pairs,
    final_states,
    terminate_states,
    state_behaviors,
)
    parents = _static_parent_map(parent_pairs)
    for state in final_states
        state === :Root && throw(HsmStateError(":Root cannot be a FinalState"))
        haskey(parents, state) || throw(HsmStateError(
            "FinalState $state is not registered in the state hierarchy",
        ))
        any(==(state), values(parents)) && throw(HsmStateError(
            "FinalState $state cannot own child states",
        ))
        behaviors = Tuple(kind for (owner, kind) in state_behaviors if owner === state)
        isempty(behaviors) || throw(HsmStateError(
            "FinalState $state cannot define State Behaviors $(unique(behaviors))",
        ))
    end
    for state in terminate_states
        state === :Root && throw(HsmStateError(
            ":Root cannot be a terminate Pseudostate",
        ))
        haskey(parents, state) || throw(HsmStateError(
            "Terminate Pseudostate $state is not registered in the state hierarchy",
        ))
        any(==(state), values(parents)) && throw(HsmStateError(
            "Terminate Pseudostate $state cannot own child states",
        ))
        state in final_states && throw(HsmStateError(
            "$state cannot be both a FinalState and a terminate Pseudostate",
        ))
        behaviors = Tuple(kind for (owner, kind) in state_behaviors if owner === state)
        isempty(behaviors) || throw(HsmStateError(
            "Terminate Pseudostate $state cannot define State Behaviors " *
            "$(unique(behaviors))",
        ))
    end
    return nothing
end

@generated function _validate_static_hierarchy!(
    ::Val{PARENT_PAIRS},
    ::Val{HISTORY_DEFAULTS},
    ::Val{FINAL_STATES},
    ::Val{TERMINATE_STATES},
    ::Val{STATE_BEHAVIORS},
) where {PARENT_PAIRS,HISTORY_DEFAULTS,FINAL_STATES,TERMINATE_STATES,STATE_BEHAVIORS}
    try
        _validate_static_parent_pairs(PARENT_PAIRS)
        _validate_history_default_edges(PARENT_PAIRS, HISTORY_DEFAULTS)
        _validate_terminal_vertices(
            PARENT_PAIRS,
            FINAL_STATES,
            TERMINATE_STATES,
            STATE_BEHAVIORS,
        )
    catch error
        message = sprint(showerror, error)
        return :(throw(HsmStateError($message)))
    end
    return :(nothing)
end

@inline function _validate_static_hierarchy!(sm::SM) where {SM}
    return _validate_static_hierarchy!(
        Val(_state_parent_pairs(SM)),
        Val(_registered_history_defaults(SM)),
        Val(_registered_final_states(SM)),
        Val(_registered_terminate_states(SM)),
        Val(_registered_state_behaviors(SM)),
    )
end

@inline function _static_isancestor(
    sm,
    ancestor_state::Val,
    state::Val,
)
    return _static_isancestor(sm, ancestor_state, state, Val(()))
end

@inline function _static_isancestor(
    sm,
    ancestor_state::Val{ANCESTOR},
    state::Val{STATE},
    ::Val{SEEN},
) where {ANCESTOR,STATE,SEEN}
    ANCESTOR === STATE && return true
    STATE === :Root && return false
    STATE in SEEN && throw(HsmStateError("Cycle detected at state $STATE"))
    return _static_isancestor(
        sm,
        ancestor_state,
        _ancestor_val(sm, state),
        Val((SEEN..., STATE)),
    )
end

function _state_path_symbols(path_type)
    path = Symbol[]
    seen = Set{Symbol}()
    while path_type <: _StatePath
        state = path_type.parameters[1]
        parent_type = path_type.parameters[2]
        state isa Symbol || throw(HsmStateError(
            "Static state path contains non-Symbol state $state",
        ))
        state in seen && throw(HsmStateError("Cycle detected at state $state"))
        push!(seen, state)
        push!(path, state)
        if state === :Root
            parent_type === Nothing || throw(HsmStateError(
                "Static :Root path must terminate the hierarchy",
            ))
            return Tuple(path)
        end
        path_type = parent_type
    end
    throw(HsmStateError("Static state path does not terminate at :Root"))
end

function _static_transition_paths_from_types(
    current_path_type,
    source_path_type,
    target_path_type,
)
    current_path = _state_path_symbols(current_path_type)
    source_path = _state_path_symbols(source_path_type)
    target_path = _state_path_symbols(target_path_type)
    current = first(current_path)
    source = first(source_path)
    target = first(target_path)

    lca = if source === target
        length(source_path) == 1 ? :Root : source_path[2]
    else
        index = findfirst(state -> state in target_path, source_path)
        index === nothing && throw(HsmStateError(
            "Transition target $target does not share an ancestor with source $source",
        ))
        source_path[index]
    end

    current_lca_index = findfirst(==(lca), current_path)
    current_lca_index === nothing && throw(HsmStateError(
        "Transition source $source is not active below current state $current",
    ))
    exits = current_path[1:(current_lca_index - 1)]

    target_lca_index = findfirst(==(lca), target_path)
    target_lca_index === nothing && throw(HsmStateError(
        "Transition target $target does not descend from least common ancestor $lca",
    ))
    entries = reverse(target_path[1:(target_lca_index - 1)])
    return current, target, lca, exits, entries
end

@inline function _transition_static!(
    action::F,
    sm::SM,
    current_state::C,
    source_state::S,
    target::T,
) where {F<:Function,SM,C<:Val,S<:Val,T<:Val}
    history_owners = _registered_history_owners(SM)
    Base.@inline _execute_static_transition!(
        Val(history_owners),
        Val(_registered_final_states(SM)),
        Val(_registered_terminate_states(SM)),
        action,
        sm,
        _state_path(sm, current_state),
        _state_path(sm, source_state),
        _state_path(sm, target),
    )
    return EventHandled
end

@inline function _execute_static_transition!(
    history_owners::H,
    final_states::R,
    terminate_states::Q,
    action::F,
    sm::SM,
    current_path::C,
    source_path::S,
    target_path::T,
) where {H<:Val,R<:Val,Q<:Val,F<:Function,SM,C<:_StatePath,S<:_StatePath,T<:_StatePath}
    previous_phase = _begin_transition!(sm, Val(true))
    try
        _execute_static_transition_body!(
            history_owners,
            final_states,
            terminate_states,
            action,
            sm,
            current_path,
            source_path,
            target_path,
        )
    finally
        _finish_transition!(sm, previous_phase)
    end
    return nothing
end

@generated function _execute_static_transition_body!(
    ::Val{HISTORY_OWNERS},
    ::Val{FINAL_STATES},
    ::Val{TERMINATE_STATES},
    action::F,
    sm,
    current_path::C,
    source_path::S,
    target_path::T,
) where {HISTORY_OWNERS,FINAL_STATES,TERMINATE_STATES,F<:Function,C<:_StatePath,S<:_StatePath,T<:_StatePath}
    current, target, lca, exits, entries = try
        _static_transition_paths_from_types(C, S, T)
    catch error
        message = sprint(showerror, error)
        return :(throw(HsmStateError($message)))
    end

    body = Expr(:block)
    push!(body.args, :(trace_transition_begin(
        sm,
        $(QuoteNode(current)),
        $(QuoteNode(target)),
        $(QuoteNode(lca)),
    )))

    for state in exits
        state_node = QuoteNode(state)
        if state !== current && state in HISTORY_OWNERS
            remembered = current in FINAL_STATES ? :Root : current
            push!(body.args, :(_set_history!(
                sm,
                Val{$state_node}(),
                $(QuoteNode(remembered)),
            )))
        end
        push!(body.args, :(trace_exit(sm, $state_node)))
        state in FINAL_STATES ||
            push!(body.args, :(on_exit!(sm, Val{$state_node}())))
    end

    push!(body.args, :(trace_transition_action(
        sm,
        $(QuoteNode(current)),
        $(QuoteNode(target)),
    )))
    push!(body.args, :(action()))

    for state in entries
        state in TERMINATE_STATES && continue
        state_node = QuoteNode(state)
        push!(body.args, :(trace_entry(sm, $state_node)))
        state in FINAL_STATES ||
            push!(body.args, :(on_entry!(sm, Val{$state_node}())))
    end

    target_node = QuoteNode(target)
    append!(body.args, [
        :(_activate_target!(sm, Val{$target_node}())),
        :(trace_transition_end(
            sm,
            $(QuoteNode(current)),
            $target_node,
        )),
        :(nothing),
    ])
    return body
end

# Choice Pseudostates
#
# `@choice` lowers an incoming effect and a finite selector separately. The
# incoming effect runs after exit processing; the selector evaluates all
# guards only after the choice's owning composite has been entered. The
# selector returns a runtime Symbol, which is split once over literal targets
# before entering the statically specialized target path.

@generated function _choice_targets_registered(
    sm,
    ::Val{TARGETS},
) where {TARGETS}
    checks = [
        :(_static_state_registered(sm, Val{$(QuoteNode(target))}()))
        for target in TARGETS
    ]
    return foldr((check, rest) -> :($check && $rest), checks; init=:(true))
end

@inline function _choice_from!(
    incoming::FI,
    selector::FS,
    sm,
    source_state::Val{SOURCE},
    owner::Val,
    targets::Val,
) where {FI<:Function,FS<:Function,SOURCE}
    if !_static_state_registered(sm, source_state) ||
       !_static_state_registered(sm, owner) ||
       !_choice_targets_registered(sm, targets)
        throw(HsmStateError(
            "Choice sources, owners, and targets must be registered with @statedef",
        ))
    end

    current_state = current(sm)
    if current_state === SOURCE
        return _choice_static!(
            incoming,
            selector,
            sm,
            source_state,
            source_state,
            owner,
            targets,
        )
    end
    if !_static_state_has_children(sm, source_state)
        throw(HsmStateError(
            "Choice source $SOURCE is not active below current state $current_state",
        ))
    end
    return _split_choice_from_current!(
        incoming,
        selector,
        sm,
        current_state,
        source_state,
        owner,
        targets,
    )
end

@inline function _split_choice_from_current!(
    incoming::FI,
    selector::FS,
    sm::SM,
    current_state::Symbol,
    source_state::S,
    owner::O,
    targets::T,
) where {FI<:Function,FS<:Function,SM,S<:Val,O<:Val,T<:Val}
    current_states = _static_descendant_states(
        Val(_registered_states(SM)),
        Val(_state_parent_pairs(SM)),
        source_state,
    )
    return _choice_current_switch!(
        Val(current_states),
        incoming,
        selector,
        sm,
        current_state,
        source_state,
        owner,
        targets,
    )
end

@generated function _choice_current_switch!(
    ::Val{STATES},
    incoming::FI,
    selector::FS,
    sm,
    current_state::Symbol,
    source_state::S,
    owner::O,
    targets::T,
) where {STATES,FI<:Function,FS<:Function,S<:Val,O<:Val,T<:Val}
    fallback = quote
        throw(HsmStateError(
            "Current state $current_state is not an active descendant of choice " *
            "source $(_val_parameter(source_state))",
        ))
    end
    return foldr(STATES; init=fallback) do state, next
        state_node = QuoteNode(state)
        quote
            if current_state === $state_node
                return _choice_static!(
                    incoming,
                    selector,
                    sm,
                    Val{$state_node}(),
                    source_state,
                    owner,
                    targets,
                )
            end
            $next
        end
    end
end

@inline function _choice_static!(
    incoming::FI,
    selector::FS,
    sm::SM,
    current_state::C,
    source_state::S,
    owner::O,
    targets::T,
) where {FI<:Function,FS<:Function,SM,C<:Val,S<:Val,O<:Val,T<:Val}
    _execute_static_choice!(
        Val(_registered_history_owners(SM)),
        Val(_registered_final_states(SM)),
        Val(_registered_terminate_states(SM)),
        incoming,
        selector,
        sm,
        _state_path(sm, current_state),
        _state_path(sm, source_state),
        _state_path(sm, owner),
        targets,
    )
    return EventHandled
end

@inline function _execute_static_choice!(
    history_owners::H,
    final_states::R,
    terminate_states::Q,
    incoming::FI,
    selector::FS,
    sm,
    current_path::C,
    source_path::S,
    owner_path::O,
    targets::T,
) where {H<:Val,R<:Val,Q<:Val,FI<:Function,FS<:Function,C<:_StatePath,S<:_StatePath,O<:_StatePath,T<:Val}
    previous_phase = _begin_transition!(sm, Val(true))
    try
        _execute_static_choice_body!(
            history_owners,
            final_states,
            terminate_states,
            incoming,
            selector,
            sm,
            current_path,
            source_path,
            owner_path,
            targets,
        )
    finally
        _finish_transition!(sm, previous_phase)
    end
    return nothing
end

@generated function _execute_static_choice_body!(
    ::Val{HISTORY_OWNERS},
    final_states::R,
    terminate_states::Q,
    incoming::FI,
    selector::FS,
    sm,
    current_path::C,
    source_path::S,
    owner_path::O,
    ::Val{TARGETS},
) where {HISTORY_OWNERS,R<:Val,Q<:Val,FI<:Function,FS<:Function,C<:_StatePath,S<:_StatePath,O<:_StatePath,TARGETS}
    current, owner, _, exits, owner_entries = try
        _static_transition_paths_from_types(C, S, O)
    catch error
        message = sprint(showerror, error)
        return :(throw(HsmStateError($message)))
    end

    body = Expr(:block)
    push!(body.args, :(trace_choice_begin(
        sm,
        $(QuoteNode(current)),
        $(QuoteNode(owner)),
    )))
    for state in exits
        state_node = QuoteNode(state)
        if state !== current && state in HISTORY_OWNERS
            push!(body.args, :(_record_static_history!(
                final_states,
                sm,
                Val{$state_node}(),
                Val{$(QuoteNode(current))}(),
            )))
        end
        push!(body.args, :(trace_exit(sm, $state_node)))
        push!(body.args, :(_run_static_exit_behavior!(
            final_states,
            sm,
            Val{$state_node}(),
        )))
    end

    push!(body.args, :(incoming()))
    for state in owner_entries
        state_node = QuoteNode(state)
        push!(body.args, :(trace_entry(sm, $state_node)))
        push!(body.args, :(_run_static_entry_behavior!(
            final_states,
            sm,
            Val{$state_node}(),
        )))
    end

    selected = gensym("choice_target")
    push!(body.args, :($selected = selector()))
    push!(body.args, :(trace_choice_selected(
        sm,
        $(QuoteNode(current)),
        $selected,
    )))
    push!(body.args, :(_choice_target_switch!(
        Val{$(QuoteNode(TARGETS))}(),
        sm,
        $selected,
        owner_path,
        Val{$(QuoteNode(current))}(),
        final_states,
        terminate_states,
    )))
    push!(body.args, :(nothing))
    return body
end

@generated function _choice_target_switch!(
    ::Val{TARGETS},
    sm,
    selected::Symbol,
    owner_path::O,
    ::Val{CURRENT},
    final_states::R,
    terminate_states::Q,
) where {TARGETS,O<:_StatePath,CURRENT,R<:Val,Q<:Val}
    fallback = quote
        throw(HsmStateError(
            "Choice selector returned undeclared target $selected",
        ))
    end
    return foldr(TARGETS; init=fallback) do target, next
        target_node = QuoteNode(target)
        quote
            if selected === $target_node
                return _finish_static_choice!(
                    sm,
                    owner_path,
                    _state_path(sm, Val{$target_node}()),
                    Val{$(QuoteNode(CURRENT))}(),
                    final_states,
                    terminate_states,
                )
            end
            $next
        end
    end
end

@generated function _finish_static_choice!(
    sm,
    owner_path::O,
    target_path::T,
    ::Val{CURRENT},
    ::Val{FINAL_STATES},
    ::Val{TERMINATE_STATES},
) where {O<:_StatePath,T<:_StatePath,CURRENT,FINAL_STATES,TERMINATE_STATES}
    owner_symbols = try
        _state_path_symbols(O)
    catch error
        message = sprint(showerror, error)
        return :(throw(HsmStateError($message)))
    end
    target_symbols = try
        _state_path_symbols(T)
    catch error
        message = sprint(showerror, error)
        return :(throw(HsmStateError($message)))
    end
    owner = first(owner_symbols)
    target = first(target_symbols)
    target === owner && return :(throw(HsmStateError(
        "Choice target $target must be below its owner $owner",
    )))
    owner_index = findfirst(==(owner), target_symbols)
    owner_index === nothing && return :(throw(HsmStateError(
        "Choice target $target is not below its owner $owner",
    )))
    entries = reverse(target_symbols[1:(owner_index - 1)])

    body = Expr(:block)
    for state in entries
        state in TERMINATE_STATES && continue
        state_node = QuoteNode(state)
        push!(body.args, :(trace_entry(sm, $state_node)))
        state in FINAL_STATES ||
            push!(body.args, :(on_entry!(sm, Val{$state_node}())))
    end
    target_node = QuoteNode(target)
    append!(body.args, [
        :(_activate_target!(sm, Val{$target_node}())),
        :(trace_choice_end(sm, $(QuoteNode(CURRENT)), $target_node)),
        :(nothing),
    ])
    return body
end

@inline function _validate_history_owner(sm, owner::Val{OWNER}) where {OWNER}
    if OWNER === :Root ||
       !_static_state_registered(sm, owner) ||
       !_history_owner_registered(sm, owner) ||
       !_is_composite_state(sm, owner)
        throw(HsmStateError(
            "History owner $OWNER must be declared for a registered composite state",
        ))
    end
    return nothing
end

@inline function _descends_or_equals(
    sm,
    state::Val{STATE},
    owner::Val{OWNER},
) where {STATE,OWNER}
    if STATE === OWNER
        return true
    elseif STATE === :Root
        return false
    end
    return _descends_or_equals(sm, _ancestor_val(sm, state), owner)
end

@inline function _validate_history_descendant(
    sm,
    remembered::Val{REMEMBERED},
    owner::Val{OWNER},
) where {REMEMBERED,OWNER}
    if REMEMBERED === OWNER || !_descends_or_equals(sm, remembered, owner)
        throw(HsmStateError(
            "Remembered state $REMEMBERED is not a descendant of history owner $OWNER",
        ))
    end
    return nothing
end

@inline function _direct_history_child(
    sm,
    state::Val{STATE},
    owner::Val{OWNER},
) where {STATE,OWNER}
    parent = _ancestor_val(sm, state)
    return _direct_history_child(sm, state, parent, owner)
end

@inline function _direct_history_child(
    sm,
    child::Val,
    parent::Val{PARENT},
    owner::Val{OWNER},
) where {PARENT,OWNER}
    if PARENT === OWNER
        return child
    elseif PARENT === :Root
        throw(HsmStateError(
            "Remembered state $(_val_parameter(child)) is not below history owner $OWNER",
        ))
    end
    return _direct_history_child(sm, parent, owner)
end

@inline function _history_target(
    sm,
    remembered::Val,
    owner::Val,
    ::DeepHistory,
)
    _validate_history_descendant(sm, remembered, owner)
    return remembered
end

@inline function _history_target(
    sm,
    remembered::Val,
    owner::Val,
    ::ShallowHistory,
)
    _validate_history_descendant(sm, remembered, owner)
    return _direct_history_child(sm, remembered, owner)
end

struct _HistoryDefaultAction{F<:Function,SM,O<:Val,K<:HistoryKind} <: Function
    incoming::F
    sm::SM
    owner::O
    kind::K
end

@inline function (action::_HistoryDefaultAction)()
    action.incoming()
    on_history_default!(action.sm, action.owner, action.kind)
    return nothing
end

@inline function _transition_history_default!(
    action::F,
    sm,
    source_state::Val,
    owner::Val,
    kind::HistoryKind,
    target::Val,
) where {F<:Function}
    _validate_history_descendant(sm, target, owner)
    combined = _HistoryDefaultAction(action, sm, owner, kind)
    return _transition_from!(combined, sm, source_state, target)
end

@inline function _transition_history_without_memory!(
    action::F,
    sm,
    source_state::Val,
    owner::Val,
    kind::HistoryKind,
    ::Nothing,
) where {F<:Function}
    # No explicit default edge: preserve the normal default entry through the
    # composite State's initial Pseudostate.
    return _transition_from!(action, sm, source_state, owner)
end

@inline function _transition_history_without_memory!(
    action::F,
    sm,
    source_state::Val,
    owner::Val,
    kind::HistoryKind,
    target::Val,
) where {F<:Function}
    return _transition_history_default!(
        action,
        sm,
        source_state,
        owner,
        kind,
        target,
    )
end

@inline function _transition_history_target!(
    action::F,
    sm,
    remembered::Val,
    source_state::Val,
    owner::Val,
    kind::HistoryKind,
) where {F<:Function}
    target = _history_target(sm, remembered, owner, kind)
    return _transition_from!(action, sm, source_state, target)
end

@generated function _transition_history_target_switch!(
    ::Val{STATES},
    action::F,
    sm,
    remembered::Symbol,
    source_state::Val,
    owner::Val,
    kind::K,
) where {STATES,F<:Function,K<:HistoryKind}
    fallback = quote
        throw(HsmStateError(
            "Remembered history state $remembered is not registered for $(typeof(sm))",
        ))
    end
    return foldr(STATES; init=fallback) do state, next
        state === :Root && return next
        state_node = QuoteNode(state)
        quote
            if remembered === $state_node
                return _transition_history_target!(
                    action,
                    sm,
                    Val{$state_node}(),
                    source_state,
                    owner,
                    kind,
                )
            end
            $next
        end
    end
end

@inline function _transition_history_from!(
    sm,
    source_state::Val,
    owner::Val,
    kind::HistoryKind,
)
    return _transition_history_from!(
        Returns(nothing),
        sm,
        source_state,
        owner,
        kind,
    )
end

@inline function _transition_history_from!(
    action::F,
    sm::SM,
    source_state::Val,
    owner::Val{OWNER},
    kind::HistoryKind,
) where {F<:Function,SM,OWNER}
    if !_static_state_registered(sm, source_state) ||
       !_static_state_registered(sm, owner)
        return _transition_history_owner_switch!(
            Val(_registered_states(SM)),
            action,
            sm,
            OWNER,
            kind,
            Val(true),
        )
    end

    _validate_history_owner(sm, owner)
    remembered = _history_value(sm, owner)
    if remembered === :Root
        return _transition_history_without_memory!(
            action,
            sm,
            source_state,
            owner,
            kind,
            _history_default_target(sm, owner, kind),
        )
    end
    return _transition_history_target_switch!(
        Val(_registered_states(SM)),
        action,
        sm,
        remembered,
        source_state,
        owner,
        kind,
    )
end

@generated function _history_target_symbol_switch(
    ::Val{STATES},
    sm,
    remembered::Symbol,
    owner::Val,
    kind::K,
) where {STATES,K<:HistoryKind}
    fallback = quote
        throw(HsmStateError(
            "Remembered history state $remembered is not registered for $(typeof(sm))",
        ))
    end
    return foldr(STATES; init=fallback) do state, next
        state === :Root && return next
        state_node = QuoteNode(state)
        quote
            if remembered === $state_node
                target = _history_target(sm, Val{$state_node}(), owner, kind)
                return _val_parameter(target)
            end
            $next
        end
    end
end

@inline function _transition_history_dynamic_owner!(
    action::F,
    sm::SM,
    owner::Val{OWNER},
    kind::HistoryKind,
    ::Val{INTERNAL},
) where {F<:Function,SM,OWNER,INTERNAL}
    _validate_history_owner(sm, owner)
    remembered = _history_value(sm, owner)
    if remembered === :Root
        default_target = _history_default_target(sm, owner, kind)
        if default_target !== nothing
            _validate_history_descendant(sm, default_target, owner)
            target = _val_parameter(default_target)
            combined = _HistoryDefaultAction(action, sm, owner, kind)
            if INTERNAL
                return _transition_dynamic_from_handler!(combined, sm, target)
            end
            return _transition_dynamic!(combined, sm, target)
        end
        if INTERNAL
            return _transition_dynamic_from_handler!(action, sm, OWNER)
        end
        return _transition_dynamic!(action, sm, OWNER)
    end
    target = _history_target_symbol_switch(
        Val(_registered_states(SM)),
        sm,
        remembered,
        owner,
        kind,
    )
    if INTERNAL
        return _transition_dynamic_from_handler!(action, sm, target)
    end
    return _transition_dynamic!(action, sm, target)
end

@generated function _transition_history_owner_switch!(
    ::Val{STATES},
    action::F,
    sm,
    owner::Symbol,
    kind::K,
    internal::I,
) where {STATES,F<:Function,K<:HistoryKind,I<:Val}
    fallback = quote
        throw(HsmStateError(
            "History owner $owner is not a registered state for $(typeof(sm))",
        ))
    end
    return foldr(STATES; init=fallback) do state, next
        state === :Root && return next
        state_node = QuoteNode(state)
        quote
            if owner === $state_node
                return _transition_history_dynamic_owner!(
                    action,
                    sm,
                    Val{$state_node}(),
                    kind,
                    internal,
                )
            end
            $next
        end
    end
end

"""
    transition_history!(sm, owner::Symbol, kind::HistoryKind)
    transition_history!(action::Function, sm, owner::Symbol, kind::HistoryKind)

Transition through the shallow or deep history Pseudostate owned by composite
state `owner`. If no history has been recorded, a default Transition declared
with [`@historydef`](@ref) is taken when available; otherwise the composite is
entered normally and its [`on_initial!`](@ref) handler supplies the default
state. Define an explicit default edge's optional effect with
[`@on_history_default`](@ref).

History is recorded when a composite state is exited. `ShallowHistory()`
restores its former direct child and then follows that child's normal initial
transition. `DeepHistory()` restores the former active leaf without replaying
intermediate initial transitions.

As with [`transition!`](@ref), an optional `do` block is the incoming
transition's effect and runs between exit and entry Behaviors.

# Example
```julia
@historydef Machine :Operating Hsm.DeepHistory() :Idle

@on_event function(sm::Machine, ::Outside, ::Resume, arg)
    return Hsm.transition_history!(sm, :Operating, Hsm.DeepHistory())
end
```
"""
function transition_history!(
    sm,
    owner::Symbol,
    kind::HistoryKind,
)
    return transition_history!(Returns(nothing), sm, owner, kind)
end

function transition_history!(
    action::F,
    sm::SM,
    owner::Symbol,
    kind::HistoryKind,
) where {F<:Function,SM}
    return _transition_history_owner_switch!(
        Val(_registered_states(SM)),
        action,
        sm,
        owner,
        kind,
        Val(false),
    )
end

"""
    transition!(sm, t::Symbol)
    transition!(action::Function, sm, t::Symbol)

Transition state machine `sm` to state `t`.
The `action` function will be called, if specified, during the transition when the main source state has
    exited before entering the target state. This returns [`EventHandled`](@ref) and throws if `on_initial!`
    returns anything else.

Literal targets inside concrete-state handler macros use a statically specialized
transition path. Handler macros reject computed targets; direct calls made outside
those macros retain the dynamic `Symbol` path.

Targets declared with [`@finaldef`](@ref) and [`@terminatedef`](@ref) retain
their UML lifecycle semantics. Completed and terminated machines reject later
transitions.

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

function transition!(action::F, sm, t::Symbol) where {F<:Function}
    return _transition_dynamic!(action, sm, t)
end

function _transition_dynamic!(action::F, sm, t::Symbol) where {F<:Function}
    _execute_dynamic_transition!(action, sm, t, Val(false))
    _drain_completion_events!(sm)
    return EventHandled
end

@inline function _transition_dynamic_from_handler!(
    action::F,
    sm,
    t::Symbol,
) where {F<:Function}
    _execute_dynamic_transition!(action, sm, t, Val(true))
    return EventHandled
end

function _execute_dynamic_transition!(
    action::F,
    sm,
    t::Symbol,
    internal::Val{INTERNAL},
) where {F<:Function,INTERNAL}
    previous_phase = _begin_transition!(sm, internal)
    try
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

        # A terminate Pseudostate is transient. Enter only its containing
        # State path, then let `_activate_target!` end execution.
        if _is_terminate_state_symbol(sm, t)
            do_entry!(sm, lca, ancestor(sm, t))
        else
            do_entry!(sm, lca, t)
        end

        _activate_target!(sm, t)
        trace_transition_end(sm, c, t)
    finally
        _finish_transition!(sm, previous_phase)
    end
    return nothing
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

Dispatch is run-to-completion. Calling `dispatch!` recursively while another
dispatch or transition is active throws [`HsmEventError`](@ref). Completion
events generated during the step are processed before this call returns and
before another external event can be dispatched. Completed or terminated
machines reject dispatch with `HsmEventError`.
"""
function dispatch!(sm, event::Symbol, arg=nothing)
    previous_phase = _begin_dispatch!(sm)
    dispatch_result = EventNotHandled

    try
        trace_dispatch_start(sm, event, arg)
        s = current(sm)

        # Find the main source state by calling on_event! until the event is handled.
        # source(sm) is dispatch-local transition context; outside dispatch it must
        # track current(sm) so a direct transition starts from the active leaf.
        while true
            source!(sm, s)
            trace_dispatch_attempt(sm, s, event)
            result = if _is_final_state_symbol(sm, s)
                EventNotHandled
            else
                on_event!(sm, s, event, arg)
            end
            trace_dispatch_result(sm, s, event, result)
            if result == EventHandled
                dispatch_result = EventHandled
                break
            end
            s != :Root || break
            s = ancestor(sm, s)
        end
    finally
        source!(sm, current(sm))
        _finish_dispatch!(sm, previous_phase)
    end
    _drain_completion_events!(sm)
    return dispatch_result
end

end # module Hsm
