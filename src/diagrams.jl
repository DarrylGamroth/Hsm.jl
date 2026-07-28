"""
    DiagramState

A state vertex in a format-neutral [`DiagramModel`](@ref).

`kind` is one of `:state`, `:composite`, or `:final`.
`behaviors` contains the statically registered State Behavior kinds.
"""
struct DiagramState
    name::Symbol
    parent::Symbol
    kind::Symbol
    behaviors::Vector{Symbol}
end

"""
    DiagramPseudostate

A transient control vertex in a format-neutral [`DiagramModel`](@ref).

`kind` is one of `:initial`, `:choice`, `:shallow_history`, `:deep_history`,
or `:terminate`. `owner` is the State whose implicit Region owns the vertex,
or `:Root` for a top-level Pseudostate.
"""
struct DiagramPseudostate
    name::Symbol
    owner::Symbol
    kind::Symbol
end

"""
    DiagramTransition

A statically discoverable edge in a format-neutral [`DiagramModel`](@ref).

Guard expressions and effect bodies remain executable handler code and are not
evaluated by diagram tooling. Choice guards are therefore represented by
stable `:guard_N` and `:else` labels, and `has_effect` records only whether an
effect was syntactically present. `trigger_kind` distinguishes `:event`,
`:initial`, `:completion`, `:guard`, and `:default` edges; `kind` distinguishes
`:external`, `:local`, `:initial`, `:completion`, `:history`, and `:choice`
Transition topology.
"""
struct DiagramTransition
    source::Symbol
    target::Symbol
    trigger::Union{Nothing,Symbol}
    trigger_kind::Symbol
    kind::Symbol
    guard::Union{Nothing,Symbol}
    has_effect::Bool
end

"""
    DiagramModel

A dependency-free, format-neutral description of the statically registered
portion of an Hsm.jl machine.

The model describes state hierarchy, UML control vertices, and every
statically named ordinary, history, choice, initial, and completion edge found
by Hsm handler macros. Arbitrary handler code is never executed or interpreted.
In particular, a handler without a `transition!` call cannot always be
classified statically as an internal Transition rather than an unhandled-event
path, so such handlers are not represented as edges.
"""
struct DiagramModel{T}
    machine::T
    states::Vector{DiagramState}
    pseudostates::Vector{DiagramPseudostate}
    transitions::Vector{DiagramTransition}
end

@inline function _diagram_pseudostate_name(kind::Symbol, owner::Symbol)
    return Symbol("__hsm_", kind, "_", owner)
end

@inline function _diagram_history_name(kind::Symbol, owner::Symbol)
    return _diagram_pseudostate_name(
        kind === :shallow ? :shallow_history : :deep_history,
        owner,
    )
end

function _diagram_transition_kind(
    source::Symbol,
    target::Symbol,
    parents::Dict{Symbol,Symbol},
)
    source === target && return :external
    return source in _static_ancestry(parents, target) ? :local : :external
end

function _diagram_registered_state(
    state::Symbol,
    registered::Set{Symbol},
    context::AbstractString,
)
    state === :Root && return nothing
    state in registered && return nothing
    throw(HsmStateError("$context references unregistered state $state"))
end

function _diagram_add_pseudostate!(
    pseudostates::Dict{Symbol,DiagramPseudostate},
    name::Symbol,
    owner::Symbol,
    kind::Symbol,
)
    candidate = DiagramPseudostate(name, owner, kind)
    existing = get(pseudostates, name, nothing)
    if existing !== nothing &&
       (existing.owner !== owner || existing.kind !== kind)
        throw(HsmStateError(
            "Diagram Pseudostate $name has conflicting registrations",
        ))
    end
    pseudostates[name] = candidate
    return name
end

function _diagram_raw_edge_transition(
    edge,
    parents::Dict{Symbol,Symbol},
    registered::Set{Symbol},
    pseudostates::Dict{Symbol,DiagramPseudostate},
)
    source, source_kind, target, target_kind, trigger_kind, trigger, owner,
        effect = edge

    source_id = if source_kind === :choice
        _diagram_add_pseudostate!(
            pseudostates,
            source,
            owner,
            :choice,
        )
    else
        _diagram_registered_state(source, registered, "Diagram edge source")
        source
    end

    target_id = if target_kind === :state
        _diagram_registered_state(target, registered, "Diagram edge target")
        target
    elseif target_kind === :choice
        _diagram_add_pseudostate!(
            pseudostates,
            target,
            owner,
            :choice,
        )
    elseif target_kind === :shallow_history
        _diagram_registered_state(
            owner,
            registered,
            "Shallow-history owner",
        )
        _diagram_add_pseudostate!(
            pseudostates,
            _diagram_history_name(:shallow, owner),
            owner,
            :shallow_history,
        )
    elseif target_kind === :deep_history
        _diagram_registered_state(owner, registered, "Deep-history owner")
        _diagram_add_pseudostate!(
            pseudostates,
            _diagram_history_name(:deep, owner),
            owner,
            :deep_history,
        )
    else
        throw(HsmStateError("Unknown diagram target kind $target_kind"))
    end

    if trigger_kind === :initial
        initial = _diagram_add_pseudostate!(
            pseudostates,
            _diagram_pseudostate_name(:initial, source),
            source,
            :initial,
        )
        return DiagramTransition(
            initial,
            target_id,
            nothing,
            :initial,
            :initial,
            nothing,
            effect === :effect,
        )
    end

    guard = trigger_kind === :guard ? trigger : nothing
    transition_trigger =
        trigger_kind === :event ? trigger : nothing
    kind = if trigger_kind === :completion
        :completion
    elseif trigger_kind === :guard || source_kind === :choice ||
           target_kind === :choice
        :choice
    elseif target_kind in (:shallow_history, :deep_history)
        :history
    else
        _diagram_transition_kind(source, target, parents)
    end
    return DiagramTransition(
        source_id,
        target_id,
        transition_trigger,
        trigger_kind,
        kind,
        guard,
        effect === :effect,
    )
end

function _diagram_state_sort_key(
    state::DiagramState,
    parents::Dict{Symbol,Symbol},
)
    ancestry = reverse(_static_ancestry(parents, state.name))
    return join(String.(ancestry), "\0")
end

function _diagram_transition_sort_key(transition::DiagramTransition)
    return (
        String(transition.source),
        String(transition.target),
        String(transition.trigger_kind),
        transition.trigger === nothing ? "" : String(transition.trigger),
        transition.guard === nothing ? "" : String(transition.guard),
        String(transition.kind),
        transition.has_effect,
    )
end

"""
    diagram_model(machine::Type)

Build a [`DiagramModel`](@ref) without constructing or executing `machine`.

Only hierarchy and Transition edges registered by Hsm macros are included.
Machine-specific methods that manually bypass those macros are outside the
discoverable model.
"""
function diagram_model(machine::Type{SM}) where {SM}
    parent_pairs = unique(_state_parent_pairs(SM))
    _validate_static_parent_pairs(parent_pairs)
    parents = _static_parent_map(parent_pairs)
    registered = Set{Symbol}(_registered_states(SM))
    delete!(registered, :Root)

    final_states = Set{Symbol}(_registered_final_states(SM))
    terminate_states = Set{Symbol}(_registered_terminate_states(SM))
    composite_states = Set{Symbol}(
        parent for (_, parent) in parent_pairs if parent !== :Root
    )
    behavior_map = Dict{Symbol,Vector{Symbol}}()
    for (state, behavior) in unique(_registered_state_behaviors(SM))
        push!(get!(behavior_map, state, Symbol[]), behavior)
    end

    states = DiagramState[]
    for state in registered
        state in terminate_states && continue
        kind = if state in final_states
            :final
        elseif state in composite_states
            :composite
        else
            :state
        end
        behaviors = sort!(unique(get(behavior_map, state, Symbol[])); by=String)
        push!(states, DiagramState(state, parents[state], kind, behaviors))
    end
    sort!(states; by=state -> _diagram_state_sort_key(state, parents))

    pseudostate_map = Dict{Symbol,DiagramPseudostate}()
    for state in terminate_states
        _diagram_add_pseudostate!(
            pseudostate_map,
            state,
            parents[state],
            :terminate,
        )
    end
    transitions = DiagramTransition[]
    for edge in unique(_registered_diagram_edges(SM))
        push!(
            transitions,
            _diagram_raw_edge_transition(
                edge,
                parents,
                registered,
                pseudostate_map,
            ),
        )
    end

    history_default_behaviors =
        Set{Tuple{Symbol,Symbol}}(_registered_history_default_behaviors(SM))
    for (owner, history_kind, target) in
        unique(_registered_history_defaults(SM))
        _diagram_registered_state(owner, registered, "History owner")
        _diagram_registered_state(target, registered, "History default")
        history_name = _diagram_add_pseudostate!(
            pseudostate_map,
            _diagram_history_name(history_kind, owner),
            owner,
            history_kind === :shallow ? :shallow_history : :deep_history,
        )
        push!(
            transitions,
            DiagramTransition(
                history_name,
                target,
                nothing,
                :default,
                :history,
                :default,
                (owner, history_kind) in history_default_behaviors,
            ),
        )
    end

    pseudostates = sort!(
        collect(values(pseudostate_map));
        by=pseudostate -> (
            String(pseudostate.owner),
            String(pseudostate.kind),
            String(pseudostate.name),
        ),
    )
    transitions = unique(transitions)
    sort!(transitions; by=_diagram_transition_sort_key)
    return DiagramModel(machine, states, pseudostates, transitions)
end

function _diagram_machine_name(model::DiagramModel)
    machine_type = Base.unwrap_unionall(model.machine)
    return string(nameof(machine_type))
end

function _diagram_aliases(model::DiagramModel)
    aliases = Dict{Symbol,String}()
    for (index, state) in pairs(model.states)
        aliases[state.name] = "state_$index"
    end
    for (index, pseudostate) in pairs(model.pseudostates)
        aliases[pseudostate.name] = "pseudo_$index"
    end
    return aliases
end

function _diagram_children(model::DiagramModel)
    children = Dict{Symbol,Vector{DiagramState}}()
    for state in model.states
        push!(get!(children, state.parent, DiagramState[]), state)
    end
    return children
end

function _diagram_owned_pseudostates(model::DiagramModel)
    owned = Dict{Symbol,Vector{DiagramPseudostate}}()
    for pseudostate in model.pseudostates
        push!(
            get!(owned, pseudostate.owner, DiagramPseudostate[]),
            pseudostate,
        )
    end
    return owned
end

function _diagram_initial_transitions(model::DiagramModel)
    initial_owner = Dict(
        pseudostate.name => pseudostate.owner
        for pseudostate in model.pseudostates
        if pseudostate.kind === :initial
    )
    grouped = Dict{Symbol,Vector{DiagramTransition}}()
    for transition in model.transitions
        haskey(initial_owner, transition.source) || continue
        push!(
            get!(grouped, initial_owner[transition.source], DiagramTransition[]),
            transition,
        )
    end
    return grouped
end

function _plantuml_escape(value::Symbol)
    text = replace(String(value), '\\' => "\\\\")
    text = replace(text, '"' => "\\\"")
    return replace(text, '\n' => "\\n")
end

function _mermaid_escape(value::Symbol)
    text = replace(String(value), '&' => "&amp;")
    text = replace(text, '"' => "&quot;")
    text = replace(text, '<' => "&lt;", '>' => "&gt;")
    return replace(text, '\n' => "<br/>")
end

function _diagram_guard_label(guard::Symbol)
    guard === :else && return "else"
    text = String(guard)
    startswith(text, "guard_") || return text
    return "guard " * text[(length("guard_") + 1):end]
end

function _diagram_transition_label(transition::DiagramTransition)
    parts = String[]
    if transition.trigger !== nothing
        push!(parts, String(transition.trigger))
    elseif transition.trigger_kind === :completion
        push!(parts, "completion")
    elseif transition.trigger_kind === :default
        push!(parts, "[default]")
    elseif transition.guard !== nothing
        push!(parts, "[" * _diagram_guard_label(transition.guard) * "]")
    end
    transition.has_effect && push!(parts, "/ effect")
    return join(parts, " ")
end

function _plantuml_pseudostate(
    io::IO,
    pseudostate::DiagramPseudostate,
    alias::String,
    indent::String,
)
    pseudostate.kind === :initial && return nothing
    if pseudostate.kind === :choice
        println(io, indent, "state ", alias, " <<choice>>")
    elseif pseudostate.kind === :shallow_history
        println(io, indent, "state \"H\" as ", alias, " <<history>>")
    elseif pseudostate.kind === :deep_history
        println(io, indent, "state \"H*\" as ", alias, " <<history*>>")
    elseif pseudostate.kind === :terminate
        label = _plantuml_escape(pseudostate.name)
        println(io, indent, "state \"", label, " (terminate)\" as ", alias)
    end
    return nothing
end

function _plantuml_state(
    io::IO,
    state::DiagramState,
    aliases::Dict{Symbol,String},
    children::Dict{Symbol,Vector{DiagramState}},
    pseudostates::Dict{Symbol,Vector{DiagramPseudostate}},
    initial::Dict{Symbol,Vector{DiagramTransition}},
    indent::String,
)
    alias = aliases[state.name]
    label = _plantuml_escape(state.name)
    state_children = get(children, state.name, DiagramState[])
    owned = get(pseudostates, state.name, DiagramPseudostate[])
    if state.kind === :composite
        println(io, indent, "state \"", label, "\" as ", alias, " {")
        child_indent = indent * "  "
        for child in state_children
            _plantuml_state(
                io,
                child,
                aliases,
                children,
                pseudostates,
                initial,
                child_indent,
            )
        end
        for pseudostate in owned
            _plantuml_pseudostate(
                io,
                pseudostate,
                aliases[pseudostate.name],
                child_indent,
            )
        end
        for transition in get(initial, state.name, DiagramTransition[])
            label_text = _diagram_transition_label(transition)
            suffix = isempty(label_text) ? "" : " : " * label_text
            println(
                io,
                child_indent,
                "[*] --> ",
                aliases[transition.target],
                suffix,
            )
        end
        println(io, indent, "}")
    else
        stereotype = state.kind === :final ? " <<end>>" : ""
        println(
            io,
            indent,
            "state \"",
            label,
            "\" as ",
            alias,
            stereotype,
        )
    end
    return nothing
end

function _plantuml(io::IO, model::DiagramModel)
    aliases = _diagram_aliases(model)
    children = _diagram_children(model)
    pseudostates = _diagram_owned_pseudostates(model)
    initial = _diagram_initial_transitions(model)

    println(io, "@startuml")
    println(io, "hide empty description")
    println(io, "title ", _diagram_machine_name(model))
    println(
        io,
        "' Generated from statically registered Hsm.jl edges; handlers without",
    )
    println(io, "' transition! calls are not inferred as internal Transitions.")
    println(
        io,
        "' PlantUML has no terminate Pseudostate; terminate uses a labeled state.",
    )
    for state in get(children, :Root, DiagramState[])
        _plantuml_state(
            io,
            state,
            aliases,
            children,
            pseudostates,
            initial,
            "",
        )
    end
    for pseudostate in get(pseudostates, :Root, DiagramPseudostate[])
        _plantuml_pseudostate(
            io,
            pseudostate,
            aliases[pseudostate.name],
            "",
        )
    end
    for transition in get(initial, :Root, DiagramTransition[])
        label_text = _diagram_transition_label(transition)
        suffix = isempty(label_text) ? "" : " : " * label_text
        println(io, "[*] --> ", aliases[transition.target], suffix)
    end
    initial_names = Set(
        pseudostate.name for pseudostate in model.pseudostates
        if pseudostate.kind === :initial
    )
    for transition in model.transitions
        transition.source in initial_names && continue
        label_text = _diagram_transition_label(transition)
        suffix = isempty(label_text) ? "" : " : " * label_text
        println(
            io,
            aliases[transition.source],
            " --> ",
            aliases[transition.target],
            suffix,
        )
    end
    println(io, "@enduml")
    return nothing
end

function _mermaid_pseudostate(
    io::IO,
    pseudostate::DiagramPseudostate,
    alias::String,
    indent::String,
)
    pseudostate.kind === :initial && return nothing
    if pseudostate.kind === :choice
        println(io, indent, "state ", alias, " <<choice>>")
    elseif pseudostate.kind === :shallow_history
        println(io, indent, "state \"H (shallow history)\" as ", alias)
    elseif pseudostate.kind === :deep_history
        println(io, indent, "state \"H* (deep history)\" as ", alias)
    elseif pseudostate.kind === :terminate
        label = _mermaid_escape(pseudostate.name)
        println(io, indent, "state \"", label, " (terminate)\" as ", alias)
    end
    return nothing
end

function _mermaid_state(
    io::IO,
    state::DiagramState,
    aliases::Dict{Symbol,String},
    children::Dict{Symbol,Vector{DiagramState}},
    pseudostates::Dict{Symbol,Vector{DiagramPseudostate}},
    initial::Dict{Symbol,Vector{DiagramTransition}},
    indent::String,
)
    alias = aliases[state.name]
    label = _mermaid_escape(state.name)
    state_children = get(children, state.name, DiagramState[])
    owned = get(pseudostates, state.name, DiagramPseudostate[])
    rendered_label =
        state.kind === :final ? label * " (FinalState)" : label
    println(io, indent, "state \"", rendered_label, "\" as ", alias)
    if state.kind === :composite
        println(io, indent, "state ", alias, " {")
        child_indent = indent * "  "
        for child in state_children
            _mermaid_state(
                io,
                child,
                aliases,
                children,
                pseudostates,
                initial,
                child_indent,
            )
        end
        for pseudostate in owned
            _mermaid_pseudostate(
                io,
                pseudostate,
                aliases[pseudostate.name],
                child_indent,
            )
        end
        for transition in get(initial, state.name, DiagramTransition[])
            label_text = _diagram_transition_label(transition)
            suffix = isempty(label_text) ? "" : " : " * label_text
            println(
                io,
                child_indent,
                "[*] --> ",
                aliases[transition.target],
                suffix,
            )
        end
        println(io, indent, "}")
    end
    return nothing
end

function _mermaid(io::IO, model::DiagramModel)
    aliases = _diagram_aliases(model)
    children = _diagram_children(model)
    pseudostates = _diagram_owned_pseudostates(model)
    initial = _diagram_initial_transitions(model)

    println(io, "stateDiagram-v2")
    println(io, "%% ", _diagram_machine_name(model))
    println(
        io,
        "%% Hsm.jl adaptation: Mermaid has no shallow/deep history notation;",
    )
    println(io, "%% history, FinalState, and terminate vertices use labeled states.")
    println(
        io,
        "%% Mermaid may not render edges crossing composite-state boundaries;",
    )
    println(io, "%% all statically registered edges are retained in this source.")
    println(
        io,
        "%% Handlers without transition! calls are not inferred as internal Transitions.",
    )
    for state in get(children, :Root, DiagramState[])
        _mermaid_state(
            io,
            state,
            aliases,
            children,
            pseudostates,
            initial,
            "",
        )
    end
    for pseudostate in get(pseudostates, :Root, DiagramPseudostate[])
        _mermaid_pseudostate(
            io,
            pseudostate,
            aliases[pseudostate.name],
            "",
        )
    end
    for transition in get(initial, :Root, DiagramTransition[])
        label_text = _diagram_transition_label(transition)
        suffix = isempty(label_text) ? "" : " : " * label_text
        println(io, "[*] --> ", aliases[transition.target], suffix)
    end
    initial_names = Set(
        pseudostate.name for pseudostate in model.pseudostates
        if pseudostate.kind === :initial
    )
    for transition in model.transitions
        transition.source in initial_names && continue
        label_text = _diagram_transition_label(transition)
        suffix = isempty(label_text) ? "" : " : " * label_text
        println(
            io,
            aliases[transition.source],
            " --> ",
            aliases[transition.target],
            suffix,
        )
    end
    return nothing
end

"""
    diagram([io::IO,] model::DiagramModel; format=:plantuml)
    diagram([io::IO,] machine::Type; format=:plantuml)

Serialize a statically registered state-machine diagram as dependency-free
PlantUML (`format=:plantuml`) or Mermaid (`format=:mermaid`) text.

The `IO` methods return `nothing`. Methods without an `IO` return a `String`.
No renderer or external executable is invoked.
"""
function diagram(io::IO, model::DiagramModel; format::Symbol=:plantuml)
    if format === :plantuml
        return _plantuml(io, model)
    elseif format === :mermaid
        return _mermaid(io, model)
    end
    throw(ArgumentError(
        "unsupported diagram format $format; expected :plantuml or :mermaid",
    ))
end

function diagram(model::DiagramModel; format::Symbol=:plantuml)
    return sprint(io -> diagram(io, model; format=format))
end

function diagram(io::IO, machine::Type; format::Symbol=:plantuml)
    return diagram(io, diagram_model(machine); format=format)
end

function diagram(machine::Type; format::Symbol=:plantuml)
    return diagram(diagram_model(machine); format=format)
end
