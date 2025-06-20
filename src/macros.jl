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

# Helper function to process state machine and arguments in a consistent way
function process_macro_arguments(def, error_prefix, has_event=false)
    def.head == :function || throw(ArgumentError(format_error_message(error_prefix, "Must wrap a function definition")))

    fn_sig = def.args[1]
    body = def.args[2]

    # Handle where clauses
    where_clauses = []  # Always use an array for consistency
    if fn_sig.head == :where
        # Extract all where clause parameters
        push!(where_clauses, fn_sig.args[2])
        fn_sig = fn_sig.args[1]  # Get the actual function signature
    end

    # Extract arguments based on function signature type
    if fn_sig.head == :call
        # Normal function: f(args...) - skip function name
        args = fn_sig.args[2:end]
    elseif fn_sig.head == :tuple
        # Anonymous function with where clause: (args...)
        args = fn_sig.args
    else
        throw(ArgumentError(format_error_message(error_prefix, "Unexpected function signature format")))
    end

    # Validate argument count
    min_args = has_event ? 3 : 2
    if length(args) < min_args
        required_args = has_event ? "state machine, state, and event" : "state machine and state"
        throw(ArgumentError(format_error_message(error_prefix, "Function definition requires at least $min_args arguments: $required_args")))
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
function generate_state_handler_impl(handler_name, smarg, smtype, state_arg, full_body, is_any_state, state_name)
    # Create the function name symbol
    func_name = Symbol(string(handler_name) * "!")

    if is_any_state
        # Special case for Any state - use ValSplit macro
        return Expr(:macrocall,
            :(ValSplit.var"@valsplit"),
            LineNumberNode(@__LINE__, @__FILE__),
            Expr(:function,
                Expr(:call, :(Hsm.$func_name),
                    Expr(:(::), smarg, smtype),
                    Expr(:call, :Val, Expr(:(::), state_name, :Symbol))),
                full_body
            )
        )
    else
        # Normal case - specific state type
        return Expr(:function,
            Expr(:call, :(Hsm.$func_name),
                Expr(:(::), smarg, smtype),
                state_arg),
            full_body
        )
    end
end

# Helper function to generate consistent implementation for event handlers
function generate_event_handler_impl(smarg, smtype, new_args, full_body, is_any_event, event_name, is_any_state, state_name, method_where_clause)
    if is_any_event
        return generate_any_event_handler(smarg, smtype, new_args, full_body, event_name, is_any_state, state_name, method_where_clause)
    else
        return generate_specific_event_handler(smarg, smtype, new_args, full_body, method_where_clause)
    end
end

# Generate handler for Any event types using ValSplit macro
function generate_any_event_handler(smarg, smtype, new_args, full_body, event_name, is_any_state, state_name, method_where_clause)
    # Determine the state argument type for ValSplit dispatch
    state_arg = if is_any_state
        # Both state and event are Any - need Val() wrapping for both
        Expr(:call, :Val, Expr(:(::), state_name, :Symbol))
    else
        # Only event is Any, state is specific
        new_args[2]
    end

    # Generate the default catch-all state argument for the fallback handler
    default_state_arg = if is_any_state
        Expr(:(::), Expr(:curly, :Val, QuoteNode(gensym("Any"))))
    else
        new_args[2]
    end

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
            :(ValSplit.var"@valsplit"),
            LineNumberNode(@__LINE__, @__FILE__),
            func_expr)
    else
        Expr(:macrocall,
            :(ValSplit.var"@valsplit"),
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

    return :(Hsm.ancestor(::$(esc(smtype)), ::$(esc(:Val)){$(QuoteNode(child_sym))}) = $(QuoteNode(parent_sym)))
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

    # Generate the final function using proper Expr construction for better macro hygiene
    # This ensures correct handling of variables from the caller's context
    return esc(generate_event_handler_impl(smarg, smtype, new_args, full_body, is_any_event, event_name, is_any_state, state_name, method_where_clause))
end

"""
    @on_initial function(sm::MyStateMachine, ::StateS)
        # initialization code
        return Hsm.transition!(sm, :State_S1)
    end

Define an initial handler for a specific state. Initial handlers are called when a state becomes active
and typically transition to a child state or perform initialization logic.

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

    # Use helper function to generate the handler implementation
    return esc(generate_state_handler_impl(:on_initial, smarg, smtype, new_args[2], full_body, is_any_state, state_name))
end

"""
    @on_entry function(sm::MyStateMachine, ::StateRunning)
        # entry code
    end

    @on_entry function(sm::MyStateMachine, state::Any)
        # generic entry code for any state
    end

Define an entry handler for a specific state or for any state. Entry handlers are executed when transitioning into a state.

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

    # Use helper function to generate the handler implementation
    return esc(generate_state_handler_impl(:on_entry, smarg, smtype, new_args[2], full_body, is_any_state, state_name))
end

"""
    @on_exit function(sm::MyStateMachine, ::StateRunning)
        # exit code
    end

    @on_exit function(sm::MyStateMachine, state::Any)
        # generic exit code for any state
    end

Define an exit handler for a specific state or for any state. Exit handlers are executed when transitioning out of a state.

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

    # Use helper function to generate the handler implementation
    return esc(generate_state_handler_impl(:on_exit, smarg, smtype, new_args[2], full_body, is_any_state, state_name))
end

"""
    @hsmdef

A macro that inserts two fields (with generated unique names) into a struct
and adds a constructor that initializes these fields with :Root.

The macro works with both plain struct definitions and those using @kwdef.
The field names are generated using gensym() to avoid name collisions.

# Examples
```julia
@hsmdef struct MyStruct
    x::Int
end

@hsmdef @kwdef struct MyKwStruct
    x::Int = 1
    y::String = "default"
end
```

The macro will add two Symbol fields and create an additional constructor
that accepts the original fields and automatically sets the generated
fields to :Root.
"""
macro hsmdef(expr)
    # Generate unique field names to avoid collisions
    current_field = gensym("current")
    source_field = gensym("source")

    # Handle nested macro calls (like @kwdef)
    if expr.head == :macrocall
        # Extract the actual struct definition from the macro call
        struct_expr = expr.args[end]

        # Process the inner macro first to get its expansion
        inner_expanded = macroexpand(__module__, expr)

        # Extract struct definition and constructors from the expansion
        struct_def = nothing
        constructors = []
        other_items = []

        function extract_items(item)
            if item isa Expr
                if item.head == :struct
                    struct_def = item
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

        if struct_def !== nothing
            # Validate that the struct is mutable
            validate_mutable_struct(struct_def)

            # Add the two new fields to the struct
            modified_struct = add_fields_to_struct(struct_def, current_field, source_field)

            # Create the additional constructor
            struct_name = get_struct_name(struct_def)
            original_field_count = count_original_fields(struct_expr)
            additional_constructor = create_additional_constructor(struct_name, original_field_count)

            # Create the HSM interface methods
            hsm_interface = create_state_machine_interface(struct_name, current_field, source_field)

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
            push!(result.args, hsm_interface)

            return esc(result)
        end
    else
        # Handle direct struct definition
        if expr.head == :struct
            # Validate that the struct is mutable
            validate_mutable_struct(expr)

            # Add the two new fields
            modified_struct = add_fields_to_struct(expr, current_field, source_field)

            # Create additional constructor
            struct_name = get_struct_name(expr)
            original_field_count = count_original_fields(expr)
            additional_constructor = create_additional_constructor(struct_name, original_field_count)

            # Create the HSM interface methods
            hsm_interface = create_state_machine_interface(struct_name, current_field, source_field)

            return esc(quote
                $modified_struct
                $additional_constructor
                $hsm_interface
            end)
        end
    end

    # Fallback: return original expression if we can't process it
    return esc(expr)
end

function add_fields_to_struct(struct_expr, current_field, source_field)
    modified_struct = deepcopy(struct_expr)

    # Find the body of the struct (where fields are defined)
    body = modified_struct.args[3]

    # Add the two new fields with generated names
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
        # For empty structs, create a simple constructor that only accepts the two generated fields
        return Expr(:function,
            Expr(:call, struct_name),
            Expr(:block,
                Expr(:(=), :sm, Expr(:call, struct_name, QuoteNode(:Root), QuoteNode(:Root))),
                Expr(:call, :(Hsm.on_initial!), :sm, QuoteNode(:Root)),
                Expr(:return, :sm)
            )
        )
    else
        # Create function signature: MyStruct(args::Vararg{Any,n})
        # This constructor accepts exactly the original field count and appends :Root for the two new fields
        vararg_type = Expr(:curly, :Vararg, :Any, field_count)
        func_signature = Expr(:call, struct_name, Expr(:(::), :args, vararg_type))

        # Create function body: sm = MyStruct(args..., :Root, :Root); Hsm.on_initial!(sm, :Root); return sm
        func_body = Expr(:block,
            Expr(:(=), :sm, Expr(:call, struct_name, :(args...), QuoteNode(:Root), QuoteNode(:Root))),
            Expr(:call, :(Hsm.on_initial!), :sm, QuoteNode(:Root)),
            :sm
        )

        # Return function expression
        return Expr(:function, func_signature, func_body)
    end
end

"""
    create_state_machine_interface(struct_name, current_field, source_field)

Create Expr block defining the Hsm interface methods for a struct with generated field names.
This maintains proper macro hygiene by returning expressions instead of using @eval.
"""
function create_state_machine_interface(struct_name, current_field, source_field)
    # Create the interface methods as expressions
    interface_methods = Expr(:block)

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

    # Default initial handler
    push!(interface_methods.args,
        Expr(:macrocall,
            :(ValSplit.var"@valsplit"),
            LineNumberNode(@__LINE__, @__FILE__),
            Expr(:function,
                Expr(:call, :(Hsm.on_initial!),
                    Expr(:(::), :sm, struct_name),
                    Expr(:call, :Val, Expr(:(::), :state, :Symbol))),
                :(Hsm.EventHandled)
            )
        )
    )

    # Default entry handler
    push!(interface_methods.args,
        Expr(:macrocall,
            :(ValSplit.var"@valsplit"),
            LineNumberNode(@__LINE__, @__FILE__),
            Expr(:function,
                Expr(:call, :(Hsm.on_entry!),
                    Expr(:(::), :sm, struct_name),
                    Expr(:call, :Val, Expr(:(::), :state, :Symbol))),
                :nothing
            )
        )
    )

    # Default exit handler
    push!(interface_methods.args,
        Expr(:macrocall,
            :(ValSplit.var"@valsplit"),
            LineNumberNode(@__LINE__, @__FILE__),
            Expr(:function,
                Expr(:call, :(Hsm.on_exit!),
                    Expr(:(::), :sm, struct_name),
                    Expr(:call, :Val, Expr(:(::), :state, :Symbol))),
                :nothing
            )
        )
    )

    # Default event handler
    push!(interface_methods.args,
        Expr(:macrocall,
            :(ValSplit.var"@valsplit"),
            LineNumberNode(@__LINE__, @__FILE__),
            Expr(:function,
                Expr(:where,
                    Expr(:call, :(Hsm.on_event!),
                        Expr(:(::), :sm, struct_name),
                        Expr(:call, :Val, Expr(:(::), :state, :Symbol)),
                        Expr(:call, :Val, Expr(:(::), :event, :Symbol)),
                        Expr(:(::), :arg, :T)),
                    :T),
                :(Hsm.EventNotHandled)
            )
        )
    )

    # Default ancestor method with error
    push!(interface_methods.args,
        Expr(:macrocall,
            :(ValSplit.var"@valsplit"),
            LineNumberNode(@__LINE__, @__FILE__),
            Expr(:function,
                Expr(:call, :(Hsm.ancestor),
                    Expr(:(::), :sm, struct_name),
                    Expr(:call, :Val, Expr(:(::), :state, :Symbol))),
                Expr(:block,
                    Expr(:call, :throw,
                        Expr(:call, :HsmStateError,
                            Expr(:string, "No ancestor defined for state ", :state, " in ", struct_name, ". Use the @statedef macro to define state relationships."))),
                    Expr(:return, QuoteNode(:Root))
                )
            )
        )
    )

    # Special case: Root state's ancestor is Root itself
    # Hsm.ancestor(sm::$(struct_name), Val(:Root)) = Root
    push!(interface_methods.args,
        Expr(:function,
            Expr(:call, :(Hsm.ancestor),
                Expr(:(::), :sm, struct_name),
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
