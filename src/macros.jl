# Custom exception types for better error reporting
struct HsmMacroError <: Exception
    msg::String
end
Base.showerror(io::IO, e::HsmMacroError) = print(io, "HsmMacroError: ", e.msg)

struct HsmStateError <: Exception
    msg::String
end
Base.showerror(io::IO, e::HsmStateError) = print(io, "HsmStateError: ", e.msg)

struct HsmEventError <: Exception
    msg::String
end
Base.showerror(io::IO, e::HsmEventError) = print(io, "HsmEventError: ", e.msg)

# Helper function to create consistent error messages with source location information
function format_error_message(error_prefix, message)
    return "$error_prefix: $message"
end

function unwrap_where_signature(signature)
    if signature isa Expr && signature.head == :where
        inner_signature, inner_parameters = unwrap_where_signature(signature.args[1])
        return inner_signature, Any[inner_parameters...; signature.args[2:end]...]
    end
    return signature, Any[]
end

# Helper function to process state machine and arguments in a consistent way
function process_macro_arguments(def, error_prefix, has_event=false)
    def isa Expr && def.head == :function ||
        throw(ArgumentError(format_error_message(error_prefix, "Must wrap a function definition")))

    fn_sig, where_clauses = unwrap_where_signature(def.args[1])
    body = def.args[2]

    # Extract arguments based on function signature type
    if fn_sig isa Expr && fn_sig.head == :call
        # Normal function: f(args...) - skip function name
        args = fn_sig.args[2:end]
    elseif fn_sig isa Expr && fn_sig.head == :tuple
        # Anonymous function with where clause: (args...)
        args = fn_sig.args
    else
        throw(ArgumentError(format_error_message(error_prefix, "Unexpected function signature format")))
    end

    # Validate argument count
    valid_counts = has_event ? (3, 4) : (2,)
    if !(length(args) in valid_counts)
        expected = has_event ? "3 or 4 arguments (state machine, state, event[, data])" :
                   "2 arguments (state machine and state)"
        throw(ArgumentError(format_error_message(
            error_prefix,
            "Function definition requires exactly $expected; got $(length(args))",
        )))
    end

    # Extract arguments
    sm_arg = args[1]
    state_arg = args[2]
    event_arg = has_event ? args[3] : nothing
    data_arg = (has_event && length(args) > 3) ? args[4] : gensym("unused")

    # Extract the state machine type and name
    if sm_arg isa Symbol
        smarg = sm_arg
        smtype = :Any
    elseif sm_arg isa Expr && sm_arg.head == :(::)
        smarg = sm_arg.args[1]
        smtype = sm_arg.args[2]
    else
        throw(ArgumentError(format_error_message(error_prefix, "Unexpected argument form for state machine parameter. Expected a symbol or typed parameter (e.g., sm or sm::MyStateMachine)")))
    end

    # Process arguments
    new_args = Expr[]
    injected = Expr[]

    # Process state argument
    state_args, state_injected, is_any_state, state_name = process_state_argument(state_arg, error_prefix)
    append!(new_args, state_args)
    append!(injected, state_injected)

    # Process event argument if needed
    is_any_event = false
    event_name = nothing # Default value when has_event is false
    if has_event
        event_args, event_injected, is_any_event, event_name = process_event_argument(event_arg, error_prefix)
        append!(new_args, event_args)
        append!(injected, event_injected)
    end

    # Process data argument
    if has_event
        if data_arg isa Symbol && startswith(string(data_arg), "#unused")
            # Case: not present - create an unused parameter expression with gensym
            push!(new_args, Expr(:(::), data_arg, :Any))
        elseif data_arg isa Expr && data_arg.head == :(::)
            # Case: name::Type
            push!(new_args, data_arg)
        else
            # Case: just name - should be a symbol without type annotation
            # We still need to create a proper argument expression with Any type
            push!(new_args, Expr(:(::), data_arg, :Any))
        end
    end

    # Push state machine arg to front
    pushfirst!(new_args, Expr(:(::), smarg, smtype))

    # Return collected results
    return (smarg, smtype, body, new_args, injected, event_arg, data_arg, is_any_event, event_name, is_any_state, state_name, where_clauses)
end

# Helper function to generate a consistent implementation for state handlers
function generate_state_handler_impl(
    handler_name,
    smarg,
    smtype,
    state_arg,
    full_body,
    is_any_state,
    state_name,
    method_where_clause=nothing,
)
    # Create the function name symbol
    func_name = Symbol(string(handler_name) * "!")

    if is_any_state
        # The ValSplit Symbol wrapper is generated once by @hsmdef. Generic
        # handlers specialize its fallback instead of overwriting the wrapper.
        fallback_name = Symbol("_", string(handler_name), "_fallback!")
        signature = Expr(:call, :(Hsm.$fallback_name),
            Expr(:(::), smarg, smtype),
            Expr(:(::), state_name, :Symbol))
    else
        # Normal case - specific state type
        signature = Expr(:call, :(Hsm.$func_name),
            Expr(:(::), smarg, smtype),
            state_arg)
    end

    if method_where_clause !== nothing
        where_args = method_where_clause isa Array ?
                     method_where_clause : [method_where_clause]
        signature = Expr(:where, signature, where_args...)
    end
    return Expr(:function, signature, full_body)
end

# Helper function to generate consistent implementation for event handlers
function generate_event_handler_impl(smarg, smtype, new_args, full_body, is_any_event, event_name, is_any_state, state_name, method_where_clause)
    if is_any_event
        return generate_any_event_handler(smarg, smtype, new_args, full_body, event_name, is_any_state, state_name, method_where_clause)
    else
        return generate_specific_event_handler(smarg, smtype, new_args, full_body, method_where_clause)
    end
end

function _qualified_function_name(expr, name::Symbol)
    if expr isa GlobalRef
        return expr.mod === (@__MODULE__) && expr.name === name ? :globalref : nothing
    elseif expr isa Expr &&
           expr.head == :. &&
           length(expr.args) == 2 &&
           expr.args[1] === :Hsm &&
           expr.args[2] == QuoteNode(name)
        return :hsm
    end
    return nothing
end

function _qualified_macro_name(expr, name::Symbol)
    macro_name = Symbol("@", name)
    if expr isa GlobalRef
        return expr.mod === (@__MODULE__) && expr.name === macro_name ?
               :globalref : nothing
    elseif expr isa Expr &&
           expr.head == :. &&
           length(expr.args) == 2 &&
           expr.args[1] === :Hsm &&
           expr.args[2] == QuoteNode(macro_name)
        return :hsm
    elseif expr === macro_name
        return :unqualified
    end
    return nothing
end

function transition_function_kind(expr)
    expr === :transition! && return (:transition, :unqualified)
    expr === :transition_history! && return (:history, :unqualified)

    qualifier = _qualified_function_name(expr, :transition!)
    qualifier !== nothing && return (:transition, qualifier)
    qualifier = _qualified_function_name(expr, :transition_history!)
    qualifier !== nothing && return (:history, qualifier)
    return (nothing, nothing)
end

is_transition_function(expr) = first(transition_function_kind(expr)) === :transition

literal_symbol(expr) = expr isa QuoteNode && expr.value isa Symbol ? expr.value : nothing

function val_expression(value::Symbol)
    return Expr(:call, Expr(:curly, GlobalRef(Base, :Val), QuoteNode(value)))
end

function _binding_names!(names::Set{Symbol}, binding)
    if binding isa Symbol
        push!(names, binding)
    elseif binding isa Expr
        if binding.head in (:(=), :(::), :kw, :(...), :(<:), :(>:))
            _binding_names!(names, binding.args[1])
        elseif binding.head in (:tuple, :vect, :parameters)
            for argument in binding.args
                _binding_names!(names, argument)
            end
        end
    end
    return names
end

function _scope_assignments!(names::Set{Symbol}, expr)
    expr isa Expr || return names
    expr.head in (:function, :(->), :quote, :macrocall, :struct, :module, :baremodule) &&
        return names

    if expr.head == :(=)
        _binding_names!(names, expr.args[1])
        _scope_assignments!(names, expr.args[2])
    elseif expr.head in (:local, :const)
        for binding in expr.args
            _binding_names!(names, binding)
        end
    else
        for argument in expr.args
            _scope_assignments!(names, argument)
        end
    end
    return names
end

function _history_kind_expression(expr)
    expr isa Expr && expr.head == :call && length(expr.args) == 1 || return nothing
    for kind in (:ShallowHistory, :DeepHistory)
        function_expr = expr.args[1]
        if function_expr === kind || _qualified_function_name(function_expr, kind) !== nothing
            return Expr(:call, GlobalRef(@__MODULE__, kind))
        end
    end
    return nothing
end

function _history_kind_symbol(expr)
    expr isa Expr && expr.head == :call && length(expr.args) == 1 || return nothing
    function_expr = expr.args[1]
    for (kind, key) in ((:ShallowHistory, :shallow), (:DeepHistory, :deep))
        if function_expr === kind || _qualified_function_name(function_expr, kind) !== nothing
            return key
        end
    end
    return nothing
end

function _history_kind_type_expression(expr)
    for kind in (:ShallowHistory, :DeepHistory)
        if expr === kind || _qualified_function_name(expr, kind) !== nothing
            return GlobalRef(@__MODULE__, kind)
        end
    end
    return nothing
end

mutable struct HandlerTransitionState
    initial_transition_count::Int
    history_owners::Set{Symbol}
end

HandlerTransitionState() = HandlerTransitionState(0, Set{Symbol}())

function _transition_macro_error(error_prefix, message)
    throw(HsmMacroError(format_error_message(error_prefix, message)))
end

function _rewrite_direct_transition(
    call::Expr,
    do_body,
    smarg::Symbol,
    source_state,
    handler_kind::Symbol,
    error_prefix,
    assigned_names::Set{Symbol},
    conditional::Bool,
    state::HandlerTransitionState,
)
    call.head == :call || return nothing
    transition_kind, qualifier = transition_function_kind(call.args[1])
    transition_kind === nothing && return nothing

    if qualifier === :unqualified
        function_name = transition_kind === :transition ? :transition! : :transition_history!
        function_name in assigned_names && return nothing
    elseif qualifier === :hsm && :Hsm in assigned_names
        return nothing
    end

    if transition_kind === :transition
        if length(call.args) == 3
            action = nothing
            machine_index = 2
            target_index = 3
        elseif length(call.args) == 4 && do_body === nothing
            action = call.args[2]
            machine_index = 3
            target_index = 4
        else
            return nothing
        end
        kind_expression = nothing
    else
        if length(call.args) == 4
            action = nothing
            machine_index = 2
            target_index = 3
            kind_index = 4
        elseif length(call.args) == 5 && do_body === nothing
            action = call.args[2]
            machine_index = 3
            target_index = 4
            kind_index = 5
        else
            return nothing
        end
        kind_expression = _history_kind_expression(call.args[kind_index])
    end

    call.args[machine_index] === smarg || return nothing
    smarg in assigned_names && return nothing

    if handler_kind in (:entry, :exit, :history_default, :choice_effect)
        behavior = if handler_kind === :entry
            "entry"
        elseif handler_kind === :exit
            "exit"
        elseif handler_kind === :choice_effect
            "choice transition effect"
        else
            "default-history transition effect"
        end
        _transition_macro_error(
            error_prefix,
            "$behavior Behaviors cannot initiate transitions under UML run-to-completion semantics",
        )
    elseif source_state === nothing
        _transition_macro_error(
            error_prefix,
            "transitions require a concrete state handler; state::Any does not define a UML transition source",
        )
    end

    target = literal_symbol(call.args[target_index])
    target === nothing && _transition_macro_error(
        error_prefix,
        "handler transition targets must be literal Symbols so the transition edge is static",
    )

    if transition_kind === :history && kind_expression === nothing
        _transition_macro_error(
            error_prefix,
            "history kind must be written as ShallowHistory() or DeepHistory()",
        )
    end

    transition_kind === :history && push!(state.history_owners, target)

    if handler_kind === :initial
        conditional && _transition_macro_error(
            error_prefix,
            "an initial Pseudostate Transition cannot be guarded or conditional",
        )
        state.initial_transition_count += 1
    end

    internal_name = if handler_kind === :initial
        transition_kind === :transition ? :_initial_transition_from! :
        :_initial_transition_history_from!
    else
        transition_kind === :transition ? :_transition_from! :
        :_transition_history_from!
    end
    static_arguments = Any[smarg, val_expression(source_state), val_expression(target)]
    transition_kind === :history && push!(static_arguments, kind_expression)

    if do_body !== nothing
        static_call = Expr(:call, GlobalRef(@__MODULE__, internal_name), static_arguments...)
        return Expr(:do, static_call, do_body)
    elseif action === nothing
        return Expr(
            :call,
            GlobalRef(@__MODULE__, internal_name),
            Expr(:call, GlobalRef(Base, :Returns), nothing),
            static_arguments...,
        )
    end
    return Expr(:call, GlobalRef(@__MODULE__, internal_name), action, static_arguments...)
end

function _without_line_nodes(expr)
    if expr isa Expr && expr.head == :block
        return Any[arg for arg in expr.args if !(arg isa LineNumberNode)]
    elseif expr isa LineNumberNode
        return Any[]
    end
    return Any[expr]
end

function _choice_transition_effect(
    expression,
    smarg::Symbol,
    assigned_names::Set{Symbol},
    error_prefix,
)
    if expression isa Expr && expression.head == :return
        length(expression.args) == 1 || _transition_macro_error(
            error_prefix,
            "invalid return expression in @choice branch",
        )
        expression = expression.args[1]
    end

    do_body = nothing
    call = expression
    if expression isa Expr && expression.head == :do
        call = expression.args[1]
        do_body = expression.args[2]
    end
    call isa Expr && call.head == :call || _transition_macro_error(
        error_prefix,
        "each @choice branch must end in transition!(sm, :LiteralTarget)",
    )

    transition_kind, qualifier = transition_function_kind(call.args[1])
    transition_kind === :transition || _transition_macro_error(
        error_prefix,
        "@choice branches currently support ordinary transition! targets only",
    )
    if qualifier === :unqualified && :transition! in assigned_names
        _transition_macro_error(
            error_prefix,
            "@choice cannot use a shadowed transition! binding",
        )
    elseif qualifier === :hsm && :Hsm in assigned_names
        _transition_macro_error(
            error_prefix,
            "@choice cannot use a shadowed Hsm binding",
        )
    end

    if length(call.args) == 3
        action = nothing
        machine_index = 2
        target_index = 3
    elseif length(call.args) == 4 && do_body === nothing
        action = call.args[2]
        machine_index = 3
        target_index = 4
    else
        _transition_macro_error(error_prefix, "invalid transition! form in @choice branch")
    end
    call.args[machine_index] === smarg || _transition_macro_error(
        error_prefix,
        "@choice branch transitions must use the enclosing handler's state machine",
    )
    target = literal_symbol(call.args[target_index])
    target === nothing && _transition_macro_error(
        error_prefix,
        "@choice branch targets must be literal Symbols",
    )

    effect = if do_body !== nothing
        do_body isa Expr && do_body.head == :(->) || _transition_macro_error(
            error_prefix,
            "invalid do-block in @choice branch",
        )
        parameters = do_body.args[1]
        parameters isa Expr && parameters.head == :tuple && isempty(parameters.args) ||
            _transition_macro_error(
                error_prefix,
                "transition effects in @choice must not accept arguments",
            )
        do_body.args[2]
    elseif action === nothing
        nothing
    else
        Expr(:call, action)
    end
    return target, effect
end

function _parse_choice_branch(
    branch,
    smarg::Symbol,
    assigned_names::Set{Symbol},
    error_prefix,
)
    statements = _without_line_nodes(branch)
    isempty(statements) && _transition_macro_error(error_prefix, "empty @choice branch")
    target, terminal_effect = _choice_transition_effect(
        pop!(statements),
        smarg,
        assigned_names,
        error_prefix,
    )
    terminal_effect === nothing || push!(statements, terminal_effect)
    return target, Expr(:block, statements...)
end

function _collect_choice_branches!(
    guarded,
    expression,
    smarg::Symbol,
    assigned_names::Set{Symbol},
    error_prefix,
)
    expression isa Expr && expression.head in (:if, :elseif) ||
        _transition_macro_error(error_prefix, "@choice body must end in an if/elseif/else")
    length(expression.args) == 3 || _transition_macro_error(
        error_prefix,
        "@choice requires an else branch so the Pseudostate cannot become stable",
    )
    guard, then_branch, else_branch = expression.args
    target, effect = _parse_choice_branch(
        then_branch,
        smarg,
        assigned_names,
        error_prefix,
    )
    push!(guarded, (guard, target, effect))

    if else_branch isa Expr && else_branch.head == :elseif
        return _collect_choice_branches!(
            guarded,
            else_branch,
            smarg,
            assigned_names,
            error_prefix,
        )
    end
    return _parse_choice_branch(
        else_branch,
        smarg,
        assigned_names,
        error_prefix,
    )
end

function _validate_choice_effect(
    effect,
    smarg::Symbol,
    source_state,
    error_prefix,
    assigned_names::Set{Symbol},
)
    return _rewrite_handler_expr(
        effect,
        smarg,
        source_state,
        :choice_effect,
        error_prefix,
        assigned_names,
        false,
        HandlerTransitionState(),
    )
end

function _rewrite_choice_macro(
    expression::Expr,
    smarg::Symbol,
    source_state,
    handler_kind::Symbol,
    error_prefix,
    assigned_names::Set{Symbol},
    conditional::Bool,
    state::HandlerTransitionState,
)
    qualifier = _qualified_macro_name(expression.args[1], :choice)
    qualifier === nothing && return nothing
    length(expression.args) == 5 || _transition_macro_error(
        error_prefix,
        "@choice expects a state machine, owning composite state, and body",
    )
    qualifier === :hsm && :Hsm in assigned_names && return nothing
    expression.args[3] === smarg || _transition_macro_error(
        error_prefix,
        "@choice must use the enclosing handler's state machine",
    )
    handler_kind in (:entry, :exit, :history_default, :choice_effect) &&
        _transition_macro_error(
            error_prefix,
            "$handler_kind Behaviors cannot initiate a choice Transition",
        )
    source_state === nothing && _transition_macro_error(
        error_prefix,
        "@choice requires a concrete state handler",
    )

    owner = literal_symbol(expression.args[4])
    owner === nothing && _transition_macro_error(
        error_prefix,
        "@choice owner must be a literal Symbol",
    )
    body_statements = _without_line_nodes(expression.args[5])
    isempty(body_statements) && _transition_macro_error(
        error_prefix,
        "@choice requires an if/elseif/else selector",
    )
    selector_expression = pop!(body_statements)
    incoming_effect = Expr(:block, body_statements...)

    guarded = Any[]
    fallback_target, fallback_effect = _collect_choice_branches!(
        guarded,
        selector_expression,
        smarg,
        assigned_names,
        error_prefix,
    )
    incoming_effect = _validate_choice_effect(
        incoming_effect,
        smarg,
        source_state,
        error_prefix,
        assigned_names,
    )
    guarded = Any[
        (
            _validate_choice_effect(
                guard,
                smarg,
                source_state,
                error_prefix,
                assigned_names,
            ),
            target,
            _validate_choice_effect(
                effect,
                smarg,
                source_state,
                error_prefix,
                assigned_names,
            ),
        )
        for (guard, target, effect) in guarded
    ]
    fallback_effect = _validate_choice_effect(
        fallback_effect,
        smarg,
        source_state,
        error_prefix,
        assigned_names,
    )

    if handler_kind === :initial
        conditional && _transition_macro_error(
            error_prefix,
            "an initial Pseudostate Transition to a choice cannot be conditional",
        )
        state.initial_transition_count += 1
    end

    guard_bindings = Any[]
    guard_names = Symbol[]
    for (guard, _, _) in guarded
        name = gensym("choice_guard")
        push!(guard_names, name)
        push!(guard_bindings, :($name = $guard))
    end

    selected = Expr(:block, fallback_effect, QuoteNode(fallback_target))
    for index in reverse(eachindex(guarded))
        _, target, effect = guarded[index]
        selected = Expr(
            :if,
            guard_names[index],
            Expr(:block, effect, QuoteNode(target)),
            selected,
        )
    end
    selector_body = Expr(:block, guard_bindings..., selected)
    incoming_function = Expr(:(->), Expr(:tuple), incoming_effect)
    selector_function = Expr(:(->), Expr(:tuple), selector_body)
    targets = Tuple(unique(Symbol[
        [target for (_, target, _) in guarded]...,
        fallback_target,
    ]))
    targets_val = Expr(
        :call,
        Expr(:curly, GlobalRef(Base, :Val), QuoteNode(targets)),
    )
    return Expr(
        :call,
        GlobalRef(@__MODULE__, :_choice_from!),
        incoming_function,
        selector_function,
        smarg,
        val_expression(source_state),
        val_expression(owner),
        targets_val,
    )
end

function _rewrite_handler_expr(
    expr,
    smarg::Symbol,
    source_state,
    handler_kind::Symbol,
    error_prefix,
    assigned_names::Set{Symbol},
    conditional::Bool,
    state::HandlerTransitionState,
)
    expr isa Expr || return expr
    if expr.head == :macrocall
        rewritten = _rewrite_choice_macro(
            expr,
            smarg,
            source_state,
            handler_kind,
            error_prefix,
            assigned_names,
            conditional,
            state,
        )
        rewritten !== nothing && return rewritten
        return expr
    end
    expr.head in (:function, :(->), :quote, :struct, :module, :baremodule) &&
        return expr

    if expr.head == :do
        call = expr.args[1]
        if call isa Expr
            rewritten = _rewrite_direct_transition(
                call,
                expr.args[2],
                smarg,
                source_state,
                handler_kind,
                error_prefix,
                assigned_names,
                conditional,
                state,
            )
            rewritten !== nothing && return rewritten
        end
        rewritten_call = _rewrite_handler_expr(
            call,
            smarg,
            source_state,
            handler_kind,
            error_prefix,
            assigned_names,
            conditional,
            state,
        )
        return Expr(:do, rewritten_call, expr.args[2])
    elseif expr.head == :call
        rewritten = _rewrite_direct_transition(
            expr,
            nothing,
            smarg,
            source_state,
            handler_kind,
            error_prefix,
            assigned_names,
            conditional,
            state,
        )
        rewritten !== nothing && return rewritten
    end

    child_conditional = conditional || expr.head in (:if, :&&, :||, :for, :while, :try, :catch)
    return Expr(
        expr.head,
        map(expr.args) do argument
            _rewrite_handler_expr(
                argument,
                smarg,
                source_state,
                handler_kind,
                error_prefix,
                assigned_names,
                child_conditional,
                state,
            )
        end...,
    )
end

function rewrite_static_transitions(expr, smarg::Symbol, source_state::Symbol)
    assigned_names = _scope_assignments!(Set{Symbol}(), expr)
    return _rewrite_handler_expr(
        expr,
        smarg,
        source_state,
        :event,
        "transition rewrite",
        assigned_names,
        false,
        HandlerTransitionState(),
    )
end

function static_state_parameter(state_arg)
    state_arg isa Expr && state_arg.head == :(::) || return nothing
    state_type = state_arg.args[2]
    state_type isa Expr && state_type.head == :curly || return nothing
    state_type.args[1] === :Val || return nothing
    parameter = state_type.args[2]
    return parameter isa QuoteNode && parameter.value isa Symbol ? parameter.value : nothing
end

function rewrite_handler_transitions(
    full_body,
    smarg,
    state_arg,
    is_any_state,
    handler_kind::Symbol,
    error_prefix,
)
    source_state = is_any_state ? nothing : static_state_parameter(state_arg)
    assigned_names = _scope_assignments!(Set{Symbol}(), full_body)
    state = HandlerTransitionState()
    rewritten = _rewrite_handler_expr(
        full_body,
        smarg,
        source_state,
        handler_kind,
        error_prefix,
        assigned_names,
        false,
        state,
    )
    if handler_kind === :initial && state.initial_transition_count > 1
        _transition_macro_error(
            error_prefix,
            "an initial Pseudostate may have at most one outgoing Transition",
        )
    end
    return rewritten, state.history_owners
end


function generate_history_owner_registrations(smtype, history_owners)
    registrations = Expr(:block)
    registration_type = smtype isa Expr && smtype.head == :curly ?
                        smtype.args[1] : smtype
    for owner in sort!(collect(history_owners); by=String)
        owner_node = QuoteNode(owner)
        token_node = QuoteNode(gensym("history_owner"))
        push!(registrations.args, quote
            @inline Hsm._history_owner_edge(
                ::$registration_type,
                ::Val{$owner_node},
                ::Val{$token_node},
            ) = nothing
        end)
    end
    return registrations
end

function generate_state_behavior_registration(
    smtype,
    state_arg,
    is_any_state,
    behavior_kind::Symbol,
)
    is_any_state && return Expr(:block)
    state = static_state_parameter(state_arg)
    state === nothing && return Expr(:block)
    registration_type = smtype isa Expr && smtype.head == :curly ?
                        smtype.args[1] : smtype
    state_node = QuoteNode(state)
    kind_node = QuoteNode(behavior_kind)
    token_node = QuoteNode(gensym("state_behavior"))
    return quote
        @inline Hsm._state_behavior_edge(
            ::$registration_type,
            ::Val{$state_node},
            ::Val{$kind_node},
            ::Val{$token_node},
        ) = nothing
    end
end

# Generate handler for Any event types using ValSplit macro
function generate_any_event_handler(smarg, smtype, new_args, full_body, event_name, is_any_state, state_name, method_where_clause)
    if is_any_state
        signature = Expr(:call, :(Hsm._on_event_fallback!),
            Expr(:(::), smarg, smtype),
            Expr(:(::), state_name, :Symbol),
            Expr(:(::), event_name, :Symbol),
            new_args[4])

        if method_where_clause !== nothing
            where_args = method_where_clause isa Array ? method_where_clause : [method_where_clause]
            signature = Expr(:where, signature, where_args...)
        end

        return Expr(:function, signature, full_body)
    end

    # Determine the state argument type for ValSplit dispatch
    state_arg = new_args[2]

    # Generate the default catch-all state argument for the fallback handler
    default_state_arg = new_args[2]

    # Main ValSplit handler for dynamic event dispatch
    main_handler = if method_where_clause !== nothing
        # Construct function expression with where clause
        where_args = if method_where_clause isa Array
            method_where_clause  # It's already an array
        else
            [method_where_clause]  # Single expression, wrap in array
        end

        func_expr = Expr(:function,
            Expr(:where,
                Expr(:call, :(Hsm.on_event!),
                    Expr(:(::), smarg, smtype),
                    state_arg,
                    Expr(:call, :Val, Expr(:(::), event_name, :Symbol)),
                    new_args[4]),
                where_args...),
            full_body)

        Expr(:macrocall,
            GlobalRef(ValSplit, Symbol("@valsplit")),
            LineNumberNode(@__LINE__, @__FILE__),
            func_expr)
    else
        Expr(:macrocall,
            GlobalRef(ValSplit, Symbol("@valsplit")),
            LineNumberNode(@__LINE__, @__FILE__),
            Expr(:function,
                Expr(:call, :(Hsm.on_event!),
                    Expr(:(::), smarg, smtype),
                    state_arg,
                    Expr(:call, :Val, Expr(:(::), event_name, :Symbol)),
                    new_args[4]),
                full_body
            )
        )
    end

    # Fallback handler that returns EventNotHandled for unhandled events
    fallback_handler = if method_where_clause !== nothing
        where_args = if method_where_clause isa Array
            method_where_clause  # It's already an array
        else
            [method_where_clause]  # Single expression, wrap in array
        end

        Expr(:function,
            Expr(:where,
                Expr(:call, :(Hsm.on_event!),
                    Expr(:(::), smarg, smtype),
                    default_state_arg,
                    Expr(:(::), Expr(:curly, :Val, QuoteNode(gensym("Any")))),
                    new_args[4]),
                where_args...),
            Expr(:return, :(Hsm.EventNotHandled)))
    else
        Expr(:function,
            Expr(:call, :(Hsm.on_event!),
                Expr(:(::), smarg, smtype),
                default_state_arg,
                Expr(:(::), Expr(:curly, :Val, QuoteNode(gensym("Any")))),
                new_args[4]),
            Expr(:return, :(Hsm.EventNotHandled))
        )
    end

    return Expr(:block, main_handler, fallback_handler)
end

# Generate handler for specific event types
function generate_specific_event_handler(smarg, smtype, new_args, full_body, method_where_clause)
    # Construct the complete function expression
    if method_where_clause !== nothing
        # With where clause - handle different forms of where clause
        where_args = if method_where_clause isa Array
            method_where_clause  # It's already an array
        else
            [method_where_clause]  # Single expression, wrap in array
        end

        Expr(:function,
            Expr(:where,
                Expr(:call, :(Hsm.on_event!),
                    Expr(:(::), smarg, smtype),
                    new_args[2], new_args[3], new_args[4]),
                where_args...),
            full_body)
    else
        # Without where clause
        Expr(:function,
            Expr(:call, :(Hsm.on_event!),
                Expr(:(::), smarg, smtype),
                new_args[2], new_args[3], new_args[4]),
            full_body)
    end
end

# Helper function to process event arguments and generate consistent code
function process_event_argument(event_arg, error_prefix)
    new_args = Expr[]
    injected = Expr[]
    is_any_event = false

    if event_arg isa Expr && event_arg.head == :(::)
        # Extract event type and decide if it needs a name
        event_type = if length(event_arg.args) == 1
            event_arg.args[1]
        else
            event_arg.args[2]
        end

        # Determine if we have a named or anonymous parameter
        has_name = length(event_arg.args) > 1 && event_arg.args[1] isa Symbol

        # Create a name if it's anonymous - this simplifies the logic
        event_name = has_name ? event_arg.args[1] : gensym("event")

        # Special case for Any event type - use ValSplit
        if event_type == :Any
            if !has_name
                throw(ArgumentError("$error_prefix: When using ::Any for event type, you must provide a named parameter (e.g., event::Any) to access the event value"))
            end
            is_any_event = true
            push!(new_args, Expr(:(::), event_name, :Val))
        else
            is_any_event = false
            event_sym = QuoteNode(Symbol(event_type))
            push!(new_args, Expr(:(::), event_name, Expr(:curly, :Val, event_sym)))

            # Only inject the event name assignment if this is a named parameter
            # This avoids creating unnecessary assignments for anonymous parameters
            if has_name
                push!(injected, :($event_name = $event_sym))
            end
        end
    else
        throw(ArgumentError("$error_prefix: Event argument must be of the form ::EventType or event::EventType"))
    end

    return new_args, injected, is_any_event, event_name
end

# Helper function to process state arguments and generate consistent code
function process_state_argument(state_arg, error_prefix)
    new_args = Expr[]
    injected = Expr[]
    is_any_state = false

    if state_arg isa Expr && state_arg.head == :(::)
        # Extract state type and decide if it needs a name
        state_type = if length(state_arg.args) == 1
            state_arg.args[1]
        else
            state_arg.args[2]
        end

        # Determine if we have a named or anonymous parameter
        has_name = length(state_arg.args) > 1 && state_arg.args[1] isa Symbol

        # Create a name if it's anonymous - this simplifies the logic
        state_name = has_name ? state_arg.args[1] : gensym("state")

        # Special case for Any state type - use ValSplit
        if state_type == :Any
            if !has_name
                throw(ArgumentError("$error_prefix: When using ::Any for state type, you must provide a named parameter (e.g., state::Any) to access the state value"))
            end
            is_any_state = true
            push!(new_args, Expr(:(::), state_name, :Val))
        else
            is_any_state = false
            state_sym = QuoteNode(Symbol(state_type))
            push!(new_args, Expr(:(::), state_name, Expr(:curly, :Val, state_sym)))

            # Only inject the state name assignment if this is a named parameter
            # This avoids creating unnecessary assignments for anonymous parameters
            if has_name
                push!(injected, :($state_name = $state_sym))
            end
        end
    else
        throw(ArgumentError("$error_prefix: State argument must be of the form ::StateType or state::StateType"))
    end

    return new_args, injected, is_any_state, state_name
end

"""
    @choice sm :Owner begin
        # incoming Transition effect
        if guard_a
            Hsm.transition!(sm, :TargetA)
        elseif guard_b
            Hsm.transition!(sm, :TargetB) do
                # selected outgoing Transition effect
            end
        else
            Hsm.transition!(sm, :Fallback)
        end
    end

Model a choice Pseudostate inside an `@on_event`, `@on_initial`, or
`@on_completion` handler. `Owner` is the composite State whose implicit Region
owns the choice. All branch targets must be literal descendant vertices, and an
`else` branch is required. Statements before the final `if` form the incoming
Transition effect. After that effect and entry of `Owner`, every guard is
evaluated and the first enabled guarded edge in source order is selected. The
`else` edge is selected only when no guard is true. Only the selected edge's
effect executes.
"""
macro choice(args...)
    throw(HsmMacroError(
        "@choice must appear directly inside an Hsm handler macro so its " *
        "static transition source is known",
    ))
end

"""
    @statedef smtype child parent
    @statedef smtype child

Define a state in a hierarchical state machine.
This establishes the state hierarchy used for event propagation and state transitions.

# Arguments
- `smtype`: The state machine type for which the relationship is defined
- `child`: A state symbol representing the child state
- `parent`: A state symbol representing the parent state (optional, defaults to `:Root`)

# Examples
```julia
# Define relationships with explicit parents
@statedef MyStateMachine :State_S1 :State_S
@statedef MyStateMachine :State_S2 :State_S
@statedef MyStateMachine :State_S11 :State_S1

# Define relationships with implied :Root parent
@statedef MyStateMachine :State_S
@statedef MyStateMachine :State_A

# Complete state hierarchy example
@statedef MyStateMachine :State_S     # implies parent is :Root
@statedef MyStateMachine :State_S1 :State_S
@statedef MyStateMachine :State_S2 :State_S
@statedef MyStateMachine :State_S11 :State_S1
@statedef MyStateMachine :State_S21 :State_S2
```
"""
macro statedef(smtype, child, parent=:Root)
    # Add source location for better error messages
    line = __source__.line
    file = String(__source__.file)
    source_info = "line $line in $file"

    # Extract the child symbol value if it's a QuoteNode
    child_sym = child isa QuoteNode ? child.value : child
    parent_sym = parent isa QuoteNode ? parent.value : parent

    # Validate that child and parent are symbols
    if !(child_sym isa Symbol)
        throw(ArgumentError("@statedef (at $(source_info)): Child state must be a symbol (e.g., :StateA)"))
    end

    if !(parent_sym isa Symbol)
        throw(ArgumentError("@statedef (at $(source_info)): Parent state must be a symbol (e.g., :Root)"))
    end

    child_node = QuoteNode(child_sym)
    parent_node = QuoteNode(parent_sym)
    edge_token_node = QuoteNode(gensym("state_parent"))

    return esc(quote
        Base.@__doc__ Hsm.ancestor(::$smtype, ::Val{$child_node}) = $parent_node

        # Register the hierarchy and current state with the static-transition
        # path generated for literal transitions inside typed handlers.
        @inline Hsm._ancestor_val(::$smtype, ::Val{$child_node}) = Val{$parent_node}()
        @inline function Hsm._state_path(
            sm::$smtype,
            ::Val{$child_node},
        )
            parent_path = Hsm._state_path(sm, Val{$parent_node}())
            return Hsm._StatePath{$child_node,typeof(parent_path)}()
        end
        @inline Hsm._static_state_registered(::$smtype, ::Val{$child_node}) = true
        @inline Hsm._registered_state(::$smtype, ::Val{$child_node}) = nothing
        @inline Hsm._state_parent_edge(
            ::$smtype,
            ::Val{$child_node},
            ::Val{$parent_node},
            ::Val{$edge_token_node},
        ) = nothing

        @inline function Hsm._transition_from_current!(
            action::F,
            sm::$smtype,
            current::Val{$child_node},
            source::Val,
            target::Val,
        ) where {F<:Function}
            if !Hsm._static_isancestor(sm, source, current)
                throw(Hsm.HsmStateError(
                    "Transition source $(Hsm._val_parameter(source)) is not active " *
                    "below current state $(Hsm._val_parameter(current))",
                ))
            end
            return Hsm._transition_static!(action, sm, current, source, target)
        end
    end)
end

"""
    @finaldef smtype state parent
    @finaldef smtype state

Define a UML FinalState in the implicit Region owned by `parent`. Entering a
top-level FinalState completes the state-machine execution. Entering a nested
FinalState completes its owning composite State and makes that State's
completion Transition eligible.

A FinalState cannot own children or define entry, exit, initial, event, or
completion Behaviors.

# Example
```julia
@statedef Machine :Operating
@finaldef Machine :OperatingDone :Operating
@statedef Machine :Idle

@on_completion function(sm::Machine, ::Operating)
    return Hsm.transition!(sm, :Idle)
end
```
"""
macro finaldef(smtype, child, parent=:Root)
    child_sym = child isa QuoteNode ? child.value : child
    parent_sym = parent isa QuoteNode ? parent.value : parent
    child_sym isa Symbol || throw(ArgumentError(
        "@finaldef state must be a literal Symbol",
    ))
    parent_sym isa Symbol || throw(ArgumentError(
        "@finaldef parent must be a literal Symbol",
    ))
    child_sym === :Root && throw(ArgumentError(":Root cannot be a FinalState"))
    child_node = QuoteNode(child_sym)
    parent_node = QuoteNode(parent_sym)
    token_node = QuoteNode(gensym("final_state"))
    return esc(quote
        Hsm.@statedef $smtype $child_node $parent_node
        @inline Hsm._final_state_edge(
            ::$smtype,
            ::Val{$child_node},
            ::Val{$token_node},
        ) = nothing
    end)
end

"""
    @terminatedef smtype name parent
    @terminatedef smtype name

Define a named UML terminate Pseudostate in the implicit Region owned by
`parent`. A Transition targeting it follows the normal exit/effect/containing-
State entry path and then immediately terminates the entire state machine.
Terminate does not become a stable current State and does not execute exit
Behaviors for the configuration that exists when termination takes effect.

A terminate Pseudostate cannot own children or define State Behaviors.

# Example
```julia
@statedef Machine :Running
@terminatedef Machine :EmergencyStop

@on_event function(sm::Machine, ::Running, ::Emergency, arg)
    return Hsm.transition!(sm, :EmergencyStop)
end
```
"""
macro terminatedef(smtype, child, parent=:Root)
    child_sym = child isa QuoteNode ? child.value : child
    parent_sym = parent isa QuoteNode ? parent.value : parent
    child_sym isa Symbol || throw(ArgumentError(
        "@terminatedef name must be a literal Symbol",
    ))
    parent_sym isa Symbol || throw(ArgumentError(
        "@terminatedef parent must be a literal Symbol",
    ))
    child_sym === :Root && throw(ArgumentError(
        ":Root cannot be a terminate Pseudostate",
    ))
    child_node = QuoteNode(child_sym)
    parent_node = QuoteNode(parent_sym)
    token_node = QuoteNode(gensym("terminate_state"))
    return esc(quote
        Hsm.@statedef $smtype $child_node $parent_node
        @inline Hsm._terminate_state_edge(
            ::$smtype,
            ::Val{$child_node},
            ::Val{$token_node},
        ) = nothing
    end)
end

"""
    @historydef smtype owner
    @historydef smtype owner kind target

Declare that composite state `owner` owns a history Pseudostate. Direct
`transition_history!` calls outside handler macros require this declaration.
Handler macros register literal history owners automatically.

The four-argument form also declares the explicit default Transition used
when that history Pseudostate has no stored configuration. `kind` must be
`ShallowHistory()` or `DeepHistory()`, and `target` must be a literal descendant
state. Use [`@on_history_default`](@ref) to define its optional effect Behavior.

# Example
```julia
@statedef Machine :Operating
@statedef Machine :Idle :Operating
@historydef Machine :Operating Hsm.DeepHistory() :Idle
```
"""
macro historydef(smtype, owner, options...)
    owner_sym = owner isa QuoteNode ? owner.value : owner
    owner_sym isa Symbol || throw(ArgumentError(
        "@historydef owner must be a symbol (for example, :Operating)",
    ))
    length(options) in (0, 2) || throw(ArgumentError(
        "@historydef expects either (machine, owner) or " *
        "(machine, owner, history-kind, default-target)",
    ))
    owner_node = QuoteNode(owner_sym)
    token_node = QuoteNode(gensym("history_owner"))

    default_registration = Expr(:block)
    if length(options) == 2
        kind_key = _history_kind_symbol(options[1])
        kind_key === nothing && throw(ArgumentError(
            "@historydef kind must be ShallowHistory() or DeepHistory()",
        ))
        target_sym = literal_symbol(options[2])
        target_sym === nothing && throw(ArgumentError(
            "@historydef default target must be a literal Symbol",
        ))
        kind_node = QuoteNode(kind_key)
        target_node = QuoteNode(target_sym)
        default_token_node = QuoteNode(gensym("history_default"))
        default_registration = quote
            @inline Hsm._history_default_edge(
                ::$smtype,
                ::Val{$owner_node},
                ::Val{$kind_node},
                ::Val{$target_node},
                ::Val{$default_token_node},
            ) = nothing
        end
    end

    return esc(quote
        @inline Hsm._history_owner_edge(
            ::$smtype,
            ::Val{$owner_node},
            ::Val{$token_node},
        ) = nothing
        $default_registration
    end)
end

"""
    @on_history_default function(sm::Machine, ::Owner, ::DeepHistory)
        # optional default-history Transition effect
    end

Define the effect Behavior for an explicit default Transition declared by the
four-argument form of [`@historydef`](@ref). The Behavior executes after the
incoming history Transition effect and before entry of the default target. It
cannot initiate a transition or recursively dispatch an event.
"""
macro on_history_default(def)
    line = __source__.line
    file = String(__source__.file)
    error_prefix = "@on_history_default (line $line in $file)"

    def isa Expr && def.head == :function || throw(ArgumentError(
        "$error_prefix: Must wrap a function definition",
    ))
    signature, where_clauses = unwrap_where_signature(def.args[1])
    signature isa Expr || throw(ArgumentError(
        "$error_prefix: Unexpected function signature format",
    ))
    args = if signature.head == :call
        signature.args[2:end]
    elseif signature.head == :tuple
        signature.args
    else
        throw(ArgumentError(
            "$error_prefix: Unexpected function signature format",
        ))
    end
    length(args) == 3 || throw(ArgumentError(
        "$error_prefix: Function definition requires exactly 3 arguments " *
        "(state machine, history owner, history kind)",
    ))

    sm_arg, owner_arg, kind_arg = args
    if sm_arg isa Symbol
        smarg = sm_arg
        smtype = :Any
    elseif sm_arg isa Expr && sm_arg.head == :(::) && length(sm_arg.args) == 2
        smarg = sm_arg.args[1]
        smtype = sm_arg.args[2]
    else
        throw(ArgumentError(
            "$error_prefix: State machine parameter must be a symbol or typed parameter",
        ))
    end

    owner_args, owner_injected, is_any_owner, owner_name =
        process_state_argument(owner_arg, error_prefix)
    is_any_owner && throw(ArgumentError(
        "$error_prefix: history owner must be a concrete state",
    ))
    owner_state = static_state_parameter(only(owner_args))

    kind_arg isa Expr && kind_arg.head == :(::) || throw(ArgumentError(
        "$error_prefix: history kind must be typed as ::ShallowHistory or ::DeepHistory",
    ))
    kind_type = length(kind_arg.args) == 1 ? kind_arg.args[1] : kind_arg.args[2]
    qualified_kind = _history_kind_type_expression(kind_type)
    qualified_kind === nothing && throw(ArgumentError(
        "$error_prefix: history kind must be ShallowHistory or DeepHistory",
    ))
    normalized_kind_arg = if length(kind_arg.args) == 1
        Expr(:(::), qualified_kind)
    else
        Expr(:(::), kind_arg.args[1], qualified_kind)
    end

    body = isempty(owner_injected) ? def.args[2] :
           Expr(:block, owner_injected..., def.args[2])
    assigned_names = _scope_assignments!(Set{Symbol}(), body)
    transition_state = HandlerTransitionState()
    body = _rewrite_handler_expr(
        body,
        smarg,
        owner_state,
        :history_default,
        error_prefix,
        assigned_names,
        false,
        transition_state,
    )

    method_signature = Expr(
        :call,
        :(Hsm.on_history_default!),
        Expr(:(::), smarg, smtype),
        only(owner_args),
        normalized_kind_arg,
    )
    isempty(where_clauses) ||
        (method_signature = Expr(:where, method_signature, where_clauses...))
    return esc(Expr(:function, method_signature, body))
end

"""
    @on_event function(sm::MyStateMachine, ::StateA, ::EventX, data)
        # handler code
        return Hsm.EventHandled
    end

    @on_event function(sm::MyStateMachine, state::StateA, event::EventX, data)
        # handler code with named state and event parameters
        return Hsm.EventHandled
    end

Define an event handler for a specific state and event.

Transitions selected by a handler must name a literal `Symbol` target so the
edge can be specialized. Use ordinary control flow to choose among multiple
statically named transition calls.

# Arguments
- `function`: A function definition with the state machine as first argument, followed by state and event types

# Returns
The handler should return `Hsm.EventHandled` if the event was handled, or
`Hsm.EventNotHandled` if it should be passed to ancestor states.

# Examples
```julia
# Handle EventX in StateA with a data parameter
@on_event function(sm::MyStateMachine, ::StateA, ::EventX, data)
    # Use data parameter
    println("Received data: ", data)
    return Hsm.EventHandled
end

# Using named parameters for state and event
@on_event function(sm::MyStateMachine, state::StateA, event::EventX, data)
    # Variables 'state' and 'event' are available as parameters
    println("Handling event in state")
    return Hsm.EventHandled
end

# Without data parameter
@on_event function(sm::MyStateMachine, ::StateA, ::EventY)
    return Hsm.transition!(sm, :StateB) do
        sm.counter += 1
    end
end
```
"""
macro on_event(def)
    # Add source location for better error messages
    line = __source__.line
    file = String(__source__.file)
    error_prefix = "@on_event (line $line in $file)"

    # Process all arguments with helper function
    smarg, smtype, body, new_args, injected, _, _, is_any_event, event_name, is_any_state, state_name, where_clauses = process_macro_arguments(def, error_prefix, true)

    # Create where clause for method generation
    method_where_clause = if !isempty(where_clauses)
        # User provided where clause, use the array directly
        where_clauses
    else
        # No user where clause, don't add one
        nothing
    end

    # Construct the full function body with any injected parameter transformations
    full_body = isempty(injected) ? body : Expr(:block, injected..., body)
    full_body, history_owners = rewrite_handler_transitions(
        full_body,
        smarg,
        new_args[2],
        is_any_state,
        :event,
        error_prefix,
    )

    # Generate the final function using proper Expr construction for better macro hygiene
    # This ensures correct handling of variables from the caller's context
    handler_impl = generate_event_handler_impl(smarg, smtype, new_args, full_body, is_any_event, event_name, is_any_state, state_name, method_where_clause)
    history_registrations = generate_history_owner_registrations(smtype, history_owners)
    behavior_registration = generate_state_behavior_registration(
        smtype,
        new_args[2],
        is_any_state,
        :event,
    )

    return esc(quote
        $history_registrations
        $behavior_registration
        Base.@__doc__ $handler_impl
    end)
end

"""
    @on_initial function(sm::MyStateMachine, ::StateS)
        # initialization code
        return Hsm.transition!(sm, :State_S1)
    end

Define an initial handler for a specific state. It models the State's initial
Pseudostate and may contain at most one unconditional transition to a
statically named child state.

# Arguments
- `function`: A function definition with the state machine as first argument, followed by state type

# Returns
The handler should either return `Hsm.EventHandled` or perform a transition to a child state.

# Examples
```julia
# Simple initial handler transitioning to a child state
@on_initial function(sm::MyStateMachine, ::StateS)
    return Hsm.transition!(sm, :State_S1)
end

# With named state parameter
@on_initial function(sm::MyStateMachine, state::Root)
    # Initialize state machine
    sm.counter = 0
    sm.status = "ready"

    # Transition to initial state
    return Hsm.transition!(sm, :State_Ready) do
        println("Transitioning to Ready state")
    end
end
```
"""
macro on_initial(def)
    # Add source location for better error messages
    line = __source__.line
    file = String(__source__.file)
    error_prefix = "@on_initial (line $line in $file)"

    # Process all arguments with helper function
    smarg, smtype, body, new_args, injected, _, _, _, _, is_any_state, state_name, where_clauses = process_macro_arguments(def, error_prefix)

    # Construct the full function body with any injected parameter transformations
    full_body = isempty(injected) ? body : Expr(:block, injected..., body)
    full_body, history_owners = rewrite_handler_transitions(
        full_body,
        smarg,
        new_args[2],
        is_any_state,
        :initial,
        error_prefix,
    )

    # Use helper function to generate the handler implementation
    method_where_clause = isempty(where_clauses) ? nothing : where_clauses
    handler_impl = generate_state_handler_impl(
        :on_initial,
        smarg,
        smtype,
        new_args[2],
        full_body,
        is_any_state,
        state_name,
        method_where_clause,
    )
    history_registrations = generate_history_owner_registrations(smtype, history_owners)
    behavior_registration = generate_state_behavior_registration(
        smtype,
        new_args[2],
        is_any_state,
        :initial,
    )

    return esc(quote
        $history_registrations
        $behavior_registration
        Base.@__doc__ $handler_impl
    end)
end

"""
    @on_completion function(sm::Machine, ::State)
        return Hsm.transition!(sm, :Target)
    end

Define a triggerless completion Transition originating from `State`. Hsm.jl
generates completion events after synchronous entry of a simple State and
when a nested FinalState completes its owning composite State. Completion
events are scoped to the State that completed and processed before another
externally dispatched event. The handler may select one static ordinary,
history, or choice Transition.
"""
macro on_completion(def)
    line = __source__.line
    file = String(__source__.file)
    error_prefix = "@on_completion (line $line in $file)"

    smarg, smtype, body, new_args, injected, _, _, _, _, is_any_state,
        state_name, where_clauses = process_macro_arguments(
            def,
            error_prefix,
        )
    is_any_state && throw(ArgumentError(
        "$error_prefix: completion Transitions require a concrete source State",
    ))
    full_body = isempty(injected) ? body : Expr(:block, injected..., body)
    full_body, history_owners = rewrite_handler_transitions(
        full_body,
        smarg,
        new_args[2],
        false,
        :completion,
        error_prefix,
    )
    method_where_clause = isempty(where_clauses) ? nothing : where_clauses
    handler_impl = generate_state_handler_impl(
        :on_completion,
        smarg,
        smtype,
        new_args[2],
        full_body,
        false,
        state_name,
        method_where_clause,
    )
    completion_state = static_state_parameter(new_args[2])
    completion_state_node = QuoteNode(completion_state)
    token_node = QuoteNode(gensym("completion_state"))
    registration_type = smtype isa Expr && smtype.head == :curly ?
                        smtype.args[1] : smtype
    history_registrations = generate_history_owner_registrations(
        smtype,
        history_owners,
    )
    behavior_registration = generate_state_behavior_registration(
        smtype,
        new_args[2],
        false,
        :completion,
    )

    return esc(quote
        $history_registrations
        $behavior_registration
        @inline Hsm._completion_state_edge(
            ::$registration_type,
            ::Val{$completion_state_node},
            ::Val{$token_node},
        ) = nothing
        Base.@__doc__ $handler_impl
    end)
end

"""
    @on_entry function(sm::MyStateMachine, ::StateRunning)
        # entry code
    end

    @on_entry function(sm::MyStateMachine, state::Any)
        # generic entry code for any state
    end

Define an entry handler for a specific state or for any state. Entry handlers
are executed as part of an already selected transition and cannot initiate a
transition or recursively dispatch an event.

# Arguments
- `function`: A function definition with the state machine as first argument, followed by state type

# Special Handlers
- Use `state::Any` to define a generic handler that applies to any state without a more specific handler.
  This is useful for common entry behavior like logging or state tracking.
- When using `::Any`, you must provide a named parameter to access the state value.
- In a hierarchical state machine, when transitioning to a state, specific handlers take precedence over generic `::Any` handlers.
- When entering a state, all entry handlers for parent states are executed in hierarchical order (from root to the target state)
  unless entry handlers for those states are overridden by more specific handlers.

# Examples
```julia
# Simple entry handler for a specific state
@on_entry function(sm::MyStateMachine, ::StateRunning)
    println("Entering Running state")
    sm.start_time = now()
end

# Generic handler for any state - will apply to all states without specific handlers
@on_entry function(sm::MyStateMachine, state::Any)
    @info "Entering state \$(state)"
    sm.state_history[end+1] = state
end
```
"""
macro on_entry(def)
    # Add source location for better error messages
    line = __source__.line
    file = String(__source__.file)
    error_prefix = "@on_entry (line $line in $file)"

    # Process all arguments with helper function
    smarg, smtype, body, new_args, injected, _, _, _, _, is_any_state, state_name, where_clauses = process_macro_arguments(def, error_prefix)

    # Construct the full function body with any injected parameter transformations
    full_body = isempty(injected) ? body : Expr(:block, injected..., body)
    full_body, history_owners = rewrite_handler_transitions(
        full_body,
        smarg,
        new_args[2],
        is_any_state,
        :entry,
        error_prefix,
    )

    # Use helper function to generate the handler implementation
    method_where_clause = isempty(where_clauses) ? nothing : where_clauses
    handler_impl = generate_state_handler_impl(
        :on_entry,
        smarg,
        smtype,
        new_args[2],
        full_body,
        is_any_state,
        state_name,
        method_where_clause,
    )
    history_registrations = generate_history_owner_registrations(smtype, history_owners)
    behavior_registration = generate_state_behavior_registration(
        smtype,
        new_args[2],
        is_any_state,
        :entry,
    )

    return esc(quote
        $history_registrations
        $behavior_registration
        Base.@__doc__ $handler_impl
    end)
end

"""
    @on_exit function(sm::MyStateMachine, ::StateRunning)
        # exit code
    end

    @on_exit function(sm::MyStateMachine, state::Any)
        # generic exit code for any state
    end

Define an exit handler for a specific state or for any state. Exit handlers
are executed as part of an already selected transition and cannot initiate a
transition or recursively dispatch an event.

# Arguments
- `function`: A function definition with the state machine as first argument, followed by state type

# Special Handlers
- Use `state::Any` to define a generic handler that applies to any state without a more specific handler.
  This is useful for common exit behavior like cleanup or state history tracking.
- When using `::Any`, you must provide a named parameter to access the state value.
- In hierarchical transitions, exit handlers are executed from the most specific state up to the common ancestor.
- When transitioning between states with a common parent, exit handlers for all states in the exit path are called,
  with specific handlers taking precedence over generic `::Any` handlers for each state in the path.

# Examples
```julia
# Simple exit handler for a specific state
@on_exit function(sm::MyStateMachine, ::StateRunning)
    println("Exiting Running state")
    sm.running_time += now() - sm.start_time
end

# With named state parameter for a specific state
@on_exit function(sm::MyStateMachine, state::StateConnected)
    @debug "Cleaning up connection resources"
    close(sm.connection)
    sm.connection = nothing
end

# Generic handler for any state - will apply to all states without specific handlers
@on_exit function(sm::MyStateMachine, state::Any)
    @info "Exiting state \$(state)"
    push!(sm.state_history, (state, now()))
end
```
"""
macro on_exit(def)
    # Add source location for better error messages
    line = __source__.line
    file = String(__source__.file)
    error_prefix = "@on_exit (line $line in $file)"

    # Process all arguments with helper function
    smarg, smtype, body, new_args, injected, _, _, _, _, is_any_state, state_name, where_clauses = process_macro_arguments(def, error_prefix)

    # Construct the full function body with any injected parameter transformations
    full_body = isempty(injected) ? body : Expr(:block, injected..., body)
    full_body, history_owners = rewrite_handler_transitions(
        full_body,
        smarg,
        new_args[2],
        is_any_state,
        :exit,
        error_prefix,
    )

    # Use helper function to generate the handler implementation
    method_where_clause = isempty(where_clauses) ? nothing : where_clauses
    handler_impl = generate_state_handler_impl(
        :on_exit,
        smarg,
        smtype,
        new_args[2],
        full_body,
        is_any_state,
        state_name,
        method_where_clause,
    )
    history_registrations = generate_history_owner_registrations(smtype, history_owners)
    behavior_registration = generate_state_behavior_registration(
        smtype,
        new_args[2],
        is_any_state,
        :exit,
    )

    return esc(quote
        $history_registrations
        $behavior_registration
        Base.@__doc__ $handler_impl
    end)
end

"""
    @abstracthsmdef AbstractType
    @abstracthsmdef AbstractType{T}
    @abstracthsmdef AbstractType{T,C}

Define an abstract type and create the abstract HSM interface methods for it.
This macro should be called once for an abstract type before defining concrete types that inherit from it.

The macro defines the abstract type and generates default handlers (on_initial!, on_entry!, on_exit!, on_event!) 
and ancestor methods that will be shared across all concrete state machine types that inherit from the abstract type.

Supports both simple and parametric abstract types.

# Arguments
- `AbstractType`: The abstract type name to define (with optional type parameters)

# Examples
```julia
# Define a simple abstract type and its interface
@abstracthsmdef MyStateMachine

# Define a parametric abstract type with one parameter
@abstracthsmdef MyStateMachine{T}

# Define a parametric abstract type with multiple parameters
@abstracthsmdef MyStateMachine{T,C}

# Now create concrete types - they will only get field accessors
@hsmdef mutable struct ConcreteSM1 <: MyStateMachine
    x::Int
end

@hsmdef mutable struct ConcreteSM2{T} <: MyStateMachine{T}
    value::T
end

# Define state hierarchy on the abstract type (shared across all concrete types)
@statedef MyStateMachine :StateA
@statedef MyStateMachine :StateB :StateA
```
"""
macro abstracthsmdef(abstract_type)
    # Extract the base type name (handle both simple and parametric types)
    base_type = if abstract_type isa Symbol
        abstract_type
    elseif abstract_type isa Expr && abstract_type.head == :curly
        # Parametric type like MyType{T} or MyType{T,C}
        abstract_type.args[1]
    else
        error("@abstracthsmdef: Expected a type name or parametric type expression, got: $abstract_type")
    end
    
    # Create both the abstract type definition and the interface
    # Note: We use base_type for the interface methods (without parameters)
    return esc(quote
        Base.@__doc__ abstract type $abstract_type end
        $(create_state_machine_abstract_interface(base_type))
    end)
end

"""
    @hsmdef

A macro that inserts private runtime fields (with generated unique names) into
a struct and adds a constructor that initializes the state machine at :Root.

The macro works with both plain struct definitions and those using @kwdef.
The field names are generated using gensym() to avoid name collisions.

If the struct inherits from an abstract type, only the concrete interface (field accessors)
is generated. Use @abstracthsmdef on the abstract type first to create the shared interface.

If the struct does not inherit from an abstract type, both concrete and abstract interfaces
are generated on the concrete type.

# Examples
```julia
# Standalone state machine (no inheritance)
@hsmdef mutable struct MyStruct
    x::Int
end

# With @kwdef
@hsmdef @kwdef mutable struct MyKwStruct
    x::Int = 1
    y::String = "default"
end

# With abstract type inheritance
@abstracthsmdef MyAbstractSM  # Create abstract type and interface

@hsmdef mutable struct ConcreteSM1 <: MyAbstractSM
    counter::Int
end

@hsmdef mutable struct ConcreteSM2 <: MyAbstractSM
    value::String
end
```

The macro adds private history, transition-phase, lifecycle,
pending-completion, current-state, and source-state fields. Its additional
constructor accepts the original fields, initializes the generated runtime
storage, and starts the machine at `:Root`.
"""
macro hsmdef(expr)
    # Generate unique field names to avoid collisions
    history_field = gensym("history")
    transition_phase_field = gensym("transition_phase")
    lifecycle_field = gensym("lifecycle")
    pending_completion_field = gensym("pending_completion")
    current_field = gensym("current")
    source_field = gensym("source")

    expr isa Expr || throw(HsmMacroError("@hsmdef must wrap a mutable struct definition"))

    # Handle the explicitly supported Base.@kwdef composition.
    if expr.head == :macrocall
        macro_name = expr.args[1]
        is_kwdef = macro_name === Symbol("@kwdef") ||
                   (macro_name isa Expr &&
                    macro_name.head == :. &&
                    macro_name.args[1] === :Base &&
                    macro_name.args[2] == QuoteNode(Symbol("@kwdef")))
        is_kwdef || throw(HsmMacroError(
            "@hsmdef only supports a direct mutable struct or Base.@kwdef mutable struct",
        ))

        # Extract the actual struct definition from the macro call
        struct_expr = expr.args[end]
        struct_expr isa Expr && struct_expr.head == :struct || throw(HsmMacroError(
            "@hsmdef could not find the mutable struct wrapped by Base.@kwdef",
        ))

        # Process the inner macro first to get its expansion
        inner_expanded = macroexpand(__module__, expr)

        # Extract struct definition and constructors from the expansion
        struct_defs = Expr[]
        constructors = Any[]
        other_items = Any[]

        function extract_items(item)
            if item isa Expr
                if item.head == :struct
                    push!(struct_defs, item)
                elseif item.head == :function
                    push!(constructors, item)
                elseif item.head == :block
                    # Handle nested blocks
                    for subitem in item.args
                        extract_items(subitem)
                    end
                else
                    push!(other_items, item)
                end
            elseif item !== nothing && !(item isa LineNumberNode)
                push!(other_items, item)
            end
        end

        if inner_expanded.head == :block
            for item in inner_expanded.args
                extract_items(item)
            end
        else
            extract_items(inner_expanded)
        end

        length(struct_defs) == 1 || throw(HsmMacroError(
            "unrecognized Base.@kwdef expansion: expected exactly one struct definition, found $(length(struct_defs))",
        ))
        struct_def = only(struct_defs)

        # Validate that the struct is mutable
        validate_mutable_struct(struct_def)

        # Add the generated runtime fields to the struct
        modified_struct = add_fields_to_struct(
            struct_def,
            history_field,
            transition_phase_field,
            lifecycle_field,
            pending_completion_field,
            current_field,
            source_field,
        )

        # Create the additional constructor
        struct_name = get_struct_name(struct_def)
        original_field_count = count_original_fields(struct_expr)
        additional_constructor = create_additional_constructor(struct_name, original_field_count)

        # Create the HSM interface methods
        # Concrete interface: field accessors must use concrete type (unique gensym'd fields)
        concrete_interface = create_state_machine_concrete_interface(
            struct_name,
            history_field,
            transition_phase_field,
            lifecycle_field,
            pending_completion_field,
            current_field,
            source_field,
        )

        # Abstract interface: only generate if there's NO abstract parent
        # If there's an abstract parent, assume @abstracthsmdef was used to define the interface
        abstract_type = get_abstract_type(struct_def)
        abstract_interface = if abstract_type === nothing
            # No parent - generate abstract interface on the concrete type
            create_state_machine_abstract_interface(struct_name)
        else
            # Has abstract parent - skip (should be defined with @abstracthsmdef)
            Expr(:block)
        end

        # Return the modified expansion with all components
        result = Expr(:block)
        for item in other_items
            push!(result.args, item)
        end
        push!(result.args, modified_struct)
        for constructor in constructors
            push!(result.args, constructor)
        end
        push!(result.args, additional_constructor)
        push!(result.args, concrete_interface)
        push!(result.args, abstract_interface)

        return esc(result)
    elseif expr.head == :struct
        # Handle direct struct definition
        # Validate that the struct is mutable
        validate_mutable_struct(expr)

        # Add the generated runtime fields
        modified_struct = add_fields_to_struct(
            expr,
            history_field,
            transition_phase_field,
            lifecycle_field,
            pending_completion_field,
            current_field,
            source_field,
        )

        # Create additional constructor
        struct_name = get_struct_name(expr)
        original_field_count = count_original_fields(expr)
        additional_constructor = create_additional_constructor(struct_name, original_field_count)

        # Create the HSM interface methods
        # Concrete interface: field accessors must use concrete type (unique gensym'd fields)
        concrete_interface = create_state_machine_concrete_interface(
            struct_name,
            history_field,
            transition_phase_field,
            lifecycle_field,
            pending_completion_field,
            current_field,
            source_field,
        )

        # Abstract interface: only generate if there's NO abstract parent
        # If there's an abstract parent, assume @abstracthsmdef was used to define the interface
        abstract_type = get_abstract_type(expr)
        abstract_interface = if abstract_type === nothing
            # No parent - generate abstract interface on the concrete type
            create_state_machine_abstract_interface(struct_name)
        else
            # Has abstract parent - skip (should be defined with @abstracthsmdef)
            Expr(:block)
        end

        return esc(quote
            Base.@__doc__ $modified_struct
            $additional_constructor
            $concrete_interface
            $abstract_interface
        end)
    end

    throw(HsmMacroError("@hsmdef must wrap a mutable struct definition"))
end

function add_fields_to_struct(
    struct_expr,
    history_field,
    transition_phase_field,
    lifecycle_field,
    pending_completion_field,
    current_field,
    source_field,
)
    modified_struct = deepcopy(struct_expr)

    # Find the body of the struct (where fields are defined)
    body = modified_struct.args[3]

    # Keep current/source last for compatibility with code that inspects the
    # historical generated field order.
    push!(body.args, Expr(
        :(::),
        history_field,
        :(Union{Nothing,Vector{Symbol}}),
    ))
    push!(body.args, Expr(:(::), transition_phase_field, :UInt8))
    push!(body.args, Expr(:(::), lifecycle_field, :UInt8))
    push!(body.args, Expr(
        :(::),
        pending_completion_field,
        :(Union{Nothing,Symbol}),
    ))
    push!(body.args, Expr(:(::), current_field, :Symbol))
    push!(body.args, Expr(:(::), source_field, :Symbol))

    return modified_struct
end

function get_struct_name(struct_expr)
    name_expr = struct_expr.args[2]

    if name_expr isa Symbol
        return name_expr
    elseif name_expr isa Expr
        # Handle parametric types like MyStruct{T,C}
        if name_expr.head == :curly
            return name_expr.args[1]
        elseif name_expr.head == :<:
            # Handle inheritance like MyStruct <: AbstractType or MyStruct{T,C} <: AbstractType
            left_side = name_expr.args[1]
            if left_side isa Symbol
                return left_side
            elseif left_side isa Expr && left_side.head == :curly
                return left_side.args[1]
            end
        end
    end

    error("Could not extract struct name from: $name_expr")
end

function get_abstract_type(struct_expr)
    name_expr = struct_expr.args[2]
    
    if name_expr isa Expr && name_expr.head == :<:
        # Extract the right side (abstract type)
        abstract_type = name_expr.args[2]
        
        # If it's parametric like AbstractType{T,C}, extract just the base name
        if abstract_type isa Expr && abstract_type.head == :curly
            return abstract_type.args[1]  # Returns AbstractType
        else
            return abstract_type  # Returns AbstractType
        end
    end
    
    return nothing  # No inheritance
end

function count_original_fields(struct_expr)
    body = struct_expr.args[3]
    field_count = 0

    for arg in body.args
        if arg isa Symbol || (arg isa Expr && (arg.head == :(::) || arg.head == :(=)))
            field_count += 1
        end
    end

    return field_count
end

function create_additional_constructor(struct_name, field_count)
    if field_count == 0
        # For empty structs, create a zero-argument initialized constructor.
        return Expr(:function,
            Expr(:call, struct_name),
            Expr(:block,
                Expr(:(=), :sm, Expr(:call,
                    struct_name,
                    nothing,
                    :(Base.UInt8(0)),
                    :(Base.UInt8(0)),
                    nothing,
                    QuoteNode(:Root),
                    QuoteNode(:Root))),
                Expr(:call, :(Hsm._initialize_machine!), :sm),
                Expr(:return, :sm)
            )
        )
    else
        # Create function signature: MyStruct(args::Vararg{Any,n})
        # This constructor accepts exactly the original field count and appends
        # initialized values for the generated runtime fields.
        vararg_type = Expr(:curly, :Vararg, :Any, field_count)
        func_signature = Expr(:call, struct_name, Expr(:(::), :args, vararg_type))

        # Initialize history before the Root initial transition, since that
        # transition may immediately enter a registered composite state.
        func_body = Expr(:block,
            Expr(:(=), :sm, Expr(:call,
                struct_name,
                :(args...),
                nothing,
                :(Base.UInt8(0)),
                :(Base.UInt8(0)),
                nothing,
                QuoteNode(:Root),
                QuoteNode(:Root))),
            Expr(:call, :(Hsm._initialize_machine!), :sm),
            :sm
        )

        # Return function expression
        return Expr(:function, func_signature, func_body)
    end
end

"""
    create_state_machine_concrete_interface(
        struct_name,
        history_field,
        transition_phase_field,
        lifecycle_field,
        pending_completion_field,
        current_field,
        source_field,
    )

Create Expr block defining the Hsm concrete interface methods that access struct-specific fields.
These methods must be defined on the concrete type because each struct has unique gensym'd field names.
"""
function create_state_machine_concrete_interface(
    struct_name,
    history_field,
    transition_phase_field,
    lifecycle_field,
    pending_completion_field,
    current_field,
    source_field,
)
    # Create the interface methods as expressions
    interface_methods = Expr(:block)

    # Internal concrete storage used for history and reentrancy enforcement.
    push!(interface_methods.args,
        Expr(:function,
            Expr(:call, :(Hsm._history_storage), Expr(:(::), :sm, struct_name)),
            Expr(:call, :getfield, :sm, QuoteNode(history_field))
        )
    )

    push!(interface_methods.args,
        Expr(:function,
            Expr(:call, :(Hsm._history_storage!),
                Expr(:(::), :sm, struct_name),
                Expr(:(::), :storage, :(Vector{Symbol}))),
            Expr(:call, :setfield!, :sm, QuoteNode(history_field), :storage)
        )
    )

    push!(interface_methods.args,
        Expr(:function,
            Expr(:call, :(Hsm._transition_phase), Expr(:(::), :sm, struct_name)),
            Expr(:call, :getfield, :sm, QuoteNode(transition_phase_field))
        )
    )

    push!(interface_methods.args,
        Expr(:function,
            Expr(:call, :(Hsm._transition_phase!),
                Expr(:(::), :sm, struct_name),
                Expr(:(::), :phase, :UInt8)),
            Expr(:call, :setfield!, :sm, QuoteNode(transition_phase_field), :phase)
        )
    )

    push!(interface_methods.args,
        Expr(:function,
            Expr(:call, :(Hsm._lifecycle), Expr(:(::), :sm, struct_name)),
            Expr(:call, :getfield, :sm, QuoteNode(lifecycle_field))
        )
    )

    push!(interface_methods.args,
        Expr(:function,
            Expr(:call, :(Hsm._lifecycle!),
                Expr(:(::), :sm, struct_name),
                Expr(:(::), :status, :UInt8)),
            Expr(:call, :setfield!, :sm, QuoteNode(lifecycle_field), :status)
        )
    )

    push!(interface_methods.args,
        Expr(:function,
            Expr(:call, :(Hsm._pending_completion), Expr(:(::), :sm, struct_name)),
            Expr(:call, :getfield, :sm, QuoteNode(pending_completion_field))
        )
    )

    push!(interface_methods.args,
        Expr(:function,
            Expr(:call, :(Hsm._pending_completion!),
                Expr(:(::), :sm, struct_name),
                Expr(:(::), :state, :(Union{Nothing,Symbol}))),
            Expr(:call, :setfield!, :sm, QuoteNode(pending_completion_field), :state)
        )
    )

    # Hsm.current(sm::StructName) = getfield(sm, :generated_current_field)
    push!(interface_methods.args,
        Expr(:function,
            Expr(:call, :(Hsm.current), Expr(:(::), :sm, struct_name)),
            Expr(:call, :getfield, :sm, QuoteNode(current_field))
        )
    )

    # Hsm.current!(sm::StructName, state::Symbol) = setfield!(sm, :generated_current_field, state)
    push!(interface_methods.args,
        Expr(:function,
            Expr(:call, :(Hsm.current!),
                Expr(:(::), :sm, struct_name),
                Expr(:(::), :state, :Symbol)),
            Expr(:call, :setfield!, :sm, QuoteNode(current_field), :state)
        )
    )

    # Hsm.source(sm::StructName) = getfield(sm, :generated_source_field)
    push!(interface_methods.args,
        Expr(:function,
            Expr(:call, :(Hsm.source), Expr(:(::), :sm, struct_name)),
            Expr(:call, :getfield, :sm, QuoteNode(source_field))
        )
    )

    # Hsm.source!(sm::StructName, state::Symbol) = setfield!(sm, :generated_source_field, state)
    push!(interface_methods.args,
        Expr(:function,
            Expr(:call, :(Hsm.source!),
                Expr(:(::), :sm, struct_name),
                Expr(:(::), :state, :Symbol)),
            Expr(:call, :setfield!, :sm, QuoteNode(source_field), :state)
        )
    )

    return interface_methods
end

"""
    create_state_machine_abstract_interface(interface_type)

Create Expr block defining the Hsm abstract interface methods (default handlers and ancestor).
These methods can be defined on an abstract type to be shared across multiple concrete implementations.
"""
function create_state_machine_abstract_interface(interface_type)
    # Create the interface methods as expressions
    interface_methods = Expr(:block)

    # Static transition kernels already carry the state as a concrete Val.
    # These generic Val fallbacks let them bypass the runtime Symbol switch
    # while preserving state::Any handlers and the library defaults.
    for (handler_name, fallback_name) in (
        (:on_initial!, :_on_initial_fallback!),
        (:on_entry!, :_on_entry_fallback!),
        (:on_exit!, :_on_exit_fallback!),
    )
        state_parameter = gensym("STATE")
        push!(interface_methods.args,
            Expr(:function,
                Expr(:where,
                    Expr(:call,
                        GlobalRef(@__MODULE__, handler_name),
                        Expr(:(::), :sm, interface_type),
                        Expr(
                            :(::),
                            :state,
                            Expr(:curly, :Val, state_parameter),
                        )),
                    state_parameter),
                Expr(:call,
                    GlobalRef(@__MODULE__, fallback_name),
                    :sm,
                    state_parameter)
            )
        )
    end

    # Default initial handler
    push!(interface_methods.args,
        Expr(:macrocall,
            GlobalRef(ValSplit, Symbol("@valsplit")),
            LineNumberNode(@__LINE__, @__FILE__),
            Expr(:function,
                Expr(:call, :(Hsm.on_initial!),
                    Expr(:(::), :sm, interface_type),
                    Expr(:call, :Val, Expr(:(::), :state, :Symbol))),
                :(Hsm._on_initial_fallback!(sm, state))
            )
        )
    )

    # Default entry handler
    push!(interface_methods.args,
        Expr(:macrocall,
            GlobalRef(ValSplit, Symbol("@valsplit")),
            LineNumberNode(@__LINE__, @__FILE__),
            Expr(:function,
                Expr(:call, :(Hsm.on_entry!),
                    Expr(:(::), :sm, interface_type),
                    Expr(:call, :Val, Expr(:(::), :state, :Symbol))),
                :(Hsm._on_entry_fallback!(sm, state))
            )
        )
    )

    # Default exit handler
    push!(interface_methods.args,
        Expr(:macrocall,
            GlobalRef(ValSplit, Symbol("@valsplit")),
            LineNumberNode(@__LINE__, @__FILE__),
            Expr(:function,
                Expr(:call, :(Hsm.on_exit!),
                    Expr(:(::), :sm, interface_type),
                    Expr(:call, :Val, Expr(:(::), :state, :Symbol))),
                :(Hsm._on_exit_fallback!(sm, state))
            )
        )
    )

    # Default event handler
    push!(interface_methods.args,
        Expr(:macrocall,
            GlobalRef(ValSplit, Symbol("@valsplit")),
            LineNumberNode(@__LINE__, @__FILE__),
            Expr(:function,
                Expr(:where,
                    Expr(:call, :(Hsm.on_event!),
                        Expr(:(::), :sm, interface_type),
                        Expr(:call, :Val, Expr(:(::), :state, :Symbol)),
                        Expr(:call, :Val, Expr(:(::), :event, :Symbol)),
                        Expr(:(::), :arg, :T)),
                    :T),
                :(Hsm._on_event_fallback!(sm, state, event, arg))
            )
        )
    )

    # Default ancestor method with error
    push!(interface_methods.args,
        Expr(:macrocall,
            GlobalRef(ValSplit, Symbol("@valsplit")),
            LineNumberNode(@__LINE__, @__FILE__),
            Expr(:function,
                Expr(:call, :(Hsm.ancestor),
                    Expr(:(::), :sm, interface_type),
                    Expr(:call, :Val, Expr(:(::), :state, :Symbol))),
                Expr(:block,
                    Expr(:call, :throw,
                        Expr(:call, GlobalRef(@__MODULE__, :HsmStateError),
                            Expr(:string, "No ancestor defined for state ", :state, " in ", interface_type, ". Use the @statedef macro to define state relationships."))),
                    Expr(:return, QuoteNode(:Root))
                )
            )
        )
    )

    # Special case: Root state's ancestor is Root itself
    # Hsm.ancestor(sm::InterfaceType, Val(:Root)) = Root
    push!(interface_methods.args,
        Expr(:function,
            Expr(:call, :(Hsm.ancestor),
                Expr(:(::), :sm, interface_type),
                Expr(:(::), Expr(:curly, :Val, QuoteNode(:Root)))),
            QuoteNode(:Root)
        )
    )

    return interface_methods
end

"""
    validate_mutable_struct(struct_expr)

Validates that a struct expression represents a mutable struct.
Throws an error if the struct is not mutable, since HSM requires mutability for state changes.
"""
function validate_mutable_struct(struct_expr)
    if struct_expr.head != :struct
        error("Expected a struct definition, got: $(struct_expr.head)")
    end

    # struct expressions have the form: Expr(:struct, mutable_flag, name, body)
    # The second argument (index 1) is the mutability flag
    is_mutable = struct_expr.args[1]

    if !is_mutable
        struct_name = get_struct_name(struct_expr)
        error("must be explicitly declared as mutable")
    end
end

"""
    @super on_event sm state event data
    @super on_initial sm state
    @super on_entry sm state
    @super on_exit sm state

Invoke the parent (abstract) type's handler for the current state/event.
This allows concrete types to extend the behavior of their abstract parent handlers.

The macro automatically determines the abstract parent type using `supertype(typeof(sm))`
and invokes the corresponding handler method defined on that type.

# Arguments
- `handler_kind`: The kind of handler to invoke (`on_event`, `on_initial`, `on_entry`, or `on_exit`)
- `sm`: The state machine instance
- `state`: The state symbol variable (already bound by the handler macro, e.g., `state::Stopped` → `state = :Stopped`)
- `event`: The event symbol variable (only for `on_event`)
- `data`: The event data argument (only for `on_event`)

# Examples
```julia
@abstracthsmdef AbstractVehicle

# Abstract handler
@on_event function(sm::AbstractVehicle, state::Stopped, event::StartEngine, data)
    sm.engine_running = true
    return Hsm.EventHandled
end

@hsmdef mutable struct Car <: AbstractVehicle
    engine_running::Bool
    wheels::Int
end

# Concrete handler that extends abstract behavior
@on_event function(sm::Car, state::Stopped, event::StartEngine, data)
    # Call the abstract handler first
    result = @super on_event sm state event data
    
    # Add car-specific logic
    println("Car has \$(sm.wheels) wheels ready")
    return result
end

# Entry handler example
@on_entry function(sm::AbstractVehicle, state::Running)
    println("Vehicle entering Running state")
end

@on_entry function(sm::Car, state::Running)
    @super on_entry sm state  # Call abstract handler
    println("Car-specific entry logic")
end
```

# Notes
- The state and event variables are already bound to Symbol values by the handler macros
- If no abstract handler is defined, Julia will throw a MethodError
- The macro only invokes the immediate parent type's handler (no chaining through multiple levels)
"""
macro super(handler_kind, args...)
    # Add source location for better error messages
    line = __source__.line
    file = String(__source__.file)
    error_prefix = "@super (line $line in $file)"

    # Validate handler kind
    if !(handler_kind isa Symbol)
        throw(ArgumentError("$error_prefix: First argument must be a handler kind symbol (on_event, on_initial, on_entry, or on_exit)"))
    end

    valid_handlers = [:on_event, :on_initial, :on_entry, :on_exit]
    if !(handler_kind in valid_handlers)
        throw(ArgumentError("$error_prefix: Unknown handler kind :$handler_kind. Must be one of: $(join(valid_handlers, ", "))"))
    end

    # Determine handler function name
    handler_func = Symbol(string(handler_kind) * "!")

    # Parse arguments based on handler kind
    if handler_kind == :on_event
        # Expect: sm state event data
        if length(args) != 4
            throw(ArgumentError("$error_prefix: on_event requires 4 arguments (sm, state, event, data), got $(length(args))"))
        end
        sm_var = args[1]
        state_var = args[2]
        event_var = args[3]
        data_var = args[4]

        return esc(quote
            let abstract_type = supertype(typeof($sm_var)),
                state_type = typeof(Val($state_var)),
                event_type = typeof(Val($event_var)),
                data_type = typeof($data_var)
                Base.invoke(
                    Hsm.$handler_func,
                    Tuple{abstract_type, state_type, event_type, data_type},
                    $sm_var, Val($state_var), Val($event_var), $data_var
                )
            end
        end)
    elseif handler_kind in [:on_initial, :on_entry, :on_exit]
        # Expect: sm state
        if length(args) != 2
            throw(ArgumentError("$error_prefix: $handler_kind requires 2 arguments (sm, state), got $(length(args))"))
        end
        sm_var = args[1]
        state_var = args[2]

        return esc(quote
            let abstract_type = supertype(typeof($sm_var)),
                state_type = typeof(Val($state_var))
                Base.invoke(
                    Hsm.$handler_func,
                    Tuple{abstract_type, state_type},
                    $sm_var, Val($state_var)
                )
            end
        end)
    else
        throw(ArgumentError("$error_prefix: Internal error - unhandled handler kind :$handler_kind"))
    end
end
