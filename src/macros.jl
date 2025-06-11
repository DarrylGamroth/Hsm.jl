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
    args = fn_sig.args

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
    return (smarg, smtype, body, new_args, injected, event_arg, data_arg, is_any_event, event_name, is_any_state, state_name)
end

# Helper function to generate a consistent implementation for state handlers
function generate_state_handler_impl(handler_name, smarg, smtype, state_arg, full_body, is_any_state, state_name)
    # Use module and function name separately to avoid creating var"Hsm.handler_name!"
    mod = :Hsm
    func = Symbol(string(handler_name) * "!")

    if is_any_state
        # Special case for Any state - use ValSplit macro
        return quote
            @eval begin
                # Define the actual generic handler that accepts a state symbol
                ValSplit.@valsplit function $mod.$func(
                    $smarg::$smtype,
                    Val($(state_name)::Symbol)
                )
                    $full_body
                end
            end
        end
    else
        # Normal case - specific state type
        return quote
            @eval begin
                function $mod.$func(
                    $smarg::$smtype,
                    $state_arg
                )
                    $full_body
                end
            end
        end
    end
end

# Helper function to generate consistent implementation for event handlers
function generate_event_handler_impl(smarg, smtype, new_args, full_body, is_any_event, event_name, is_any_state, state_name)
    if is_any_event
        return _generate_any_event_handler(smarg, smtype, new_args, full_body, event_name, is_any_state, state_name)
    else
        return _generate_specific_event_handler(smarg, smtype, new_args, full_body)
    end
end

# Generate handler for Any event types using ValSplit macro
function _generate_any_event_handler(smarg, smtype, new_args, full_body, event_name, is_any_state, state_name)
    # Determine the state argument type for ValSplit dispatch
    state_arg = if is_any_state
        # Both state and event are Any - need Val() wrapping for both
        :(Val($(state_name)::Symbol))
    else
        # Only event is Any, state is specific
        new_args[2]
    end

    # Generate the default catch-all state argument for the fallback handler
    default_state_arg = if is_any_state
        :(::Val{$(QuoteNode(gensym("Any")))})
    else
        new_args[2]
    end

    return quote
        @eval begin
            # Main ValSplit handler for dynamic event dispatch
            ValSplit.@valsplit function Hsm.on_event!(
                $smarg::$smtype,
                $(state_arg),
                Val($(event_name)::Symbol),
                $(new_args[4])
            )
                $full_body
            end

            # Fallback handler that returns EventNotHandled for unhandled events
            function Hsm.on_event!(
                $smarg::$smtype,
                $(default_state_arg),
                ::Val{$(QuoteNode(gensym("Any")))},
                $(new_args[4])
            )
                return Hsm.EventNotHandled
            end
        end
    end
end

# Generate handler for specific event types
function _generate_specific_event_handler(smarg, smtype, new_args, full_body)
    return quote
        @eval begin
            function Hsm.on_event!(
                $smarg::$smtype,
                $(new_args[2]),
                $(new_args[3]),
                $(new_args[4])
            )
                $full_body
            end
        end
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

            # Always inject the event name assignment for consistency
            push!(injected, :($event_name = $event_sym))
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

            # Always inject the state name assignment for consistency
            push!(injected, :($state_name = $state_sym))
        end
    else
        throw(ArgumentError("$error_prefix: State argument must be of the form ::StateType or state::StateType"))
    end

    return new_args, injected, is_any_state, state_name
end

"""
    @ancestor smtype child => parent

Define an ancestor relationship between states in a hierarchical state machine.
This establishes the state hierarchy used for event propagation and state transitions.

# Arguments
- `smtype`: The state machine type for which the relationship is defined
- `child => parent`: A relationship where `child` is a symbol representing a state and `parent` is its ancestor

# Examples
```julia
# Single relationship
@ancestor MyStateMachine :State_S1 => :State_S

# Multiple relationships
@ancestor MyStateMachine begin
    :State_S1 => :State_S
    :State_S2 => :State_S
    :State_S11 => :State_S1
end

# Complete state hierarchy example
@ancestor MyStateMachine begin
    :State_S => :Root
    :State_S1 => :State_S
    :State_S2 => :State_S
    :State_S11 => :State_S1
    :State_S21 => :State_S2
end
```
"""
macro ancestor(args...)
    # Add source location for better error messages
    line = __source__.line
    file = String(__source__.file)
    source_info = "line $line in $file"

    if length(args) != 2
        throw(ArgumentError("@ancestor (at $(source_info)): Expected exactly two arguments: state machine type and state relationships"))
    end

    smtype, pair = args

    if !(pair isa Expr)
        throw(ArgumentError("@ancestor (at $(source_info)): Second argument must be an expression with => or a begin...end block"))
    end

    if pair.head == :block
        exs = []
        for stmt in pair.args
            if stmt isa Expr && stmt.head == :call && stmt.args[1] === Symbol("=>")
                if length(stmt.args) != 3
                    throw(ArgumentError("@ancestor (at $(source_info)): Invalid relationship expression. Use format: child => parent"))
                end

                # Check for nested relation which isn't allowed
                if stmt.args[3] isa Expr && stmt.args[3].head == :call && stmt.args[3].args[1] === Symbol("=>")
                    throw(ArgumentError("@ancestor (at $(source_info)): Invalid relationship expression. Nested relations like 'a => b => c' are not allowed."))
                end

                child = stmt.args[2]
                parent = stmt.args[3]
                push!(exs, :(Hsm.ancestor(::$(esc(smtype)), ::$(esc(:Val)){$child}) = $(parent)))
            elseif !(stmt isa LineNumberNode)
                throw(HsmStateError("@ancestor (at $(source_info)): Invalid statement in block. Expected format: child => parent"))
            end
        end
        return Expr(:block, exs...)
    elseif pair.head == :call && pair.args[1] === Symbol("=>")
        if length(pair.args) != 3
            throw(HsmStateError("@ancestor (at $(source_info)): Invalid relationship expression. Use format: child => parent"))
        end
        child = pair.args[2]
        parent = pair.args[3]
        return :(Hsm.ancestor(::$(esc(smtype)), ::$(esc(:Val)){$child}) = $(parent))
    else
        throw(HsmStateError("@ancestor (at $(source_info)): Expected => operator or begin...end block with relationships"))
    end
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
    smarg, smtype, body, new_args, injected, _, _, is_any_event, event_name, is_any_state, state_name = process_macro_arguments(def, error_prefix, true)

    # Construct the full function body with any injected parameter transformations
    full_body = isempty(injected) ? body : Expr(:block, injected..., body)

    # Generate the final function using a quote block with @eval for proper hygiene
    # This ensures correct handling of variables from the caller's context
    return generate_event_handler_impl(smarg, smtype, new_args, full_body, is_any_event, event_name, is_any_state, state_name)
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
    smarg, smtype, body, new_args, injected, _, _, _, _, is_any_state, state_name = process_macro_arguments(def, error_prefix)

    # Construct the full function body with any injected parameter transformations
    full_body = isempty(injected) ? body : Expr(:block, injected..., body)

    # Use helper function to generate the handler implementation
    return generate_state_handler_impl(:on_initial, smarg, smtype, new_args[2], full_body, is_any_state, state_name)
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
    smarg, smtype, body, new_args, injected, _, _, _, _, is_any_state, state_name = process_macro_arguments(def, error_prefix)

    # Construct the full function body with any injected parameter transformations
    full_body = isempty(injected) ? body : Expr(:block, injected..., body)

    # Use helper function to generate the handler implementation
    return generate_state_handler_impl(:on_entry, smarg, smtype, new_args[2], full_body, is_any_state, state_name)
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
    smarg, smtype, body, new_args, injected, _, _, _, _, is_any_state, state_name = process_macro_arguments(def, error_prefix)

    # Construct the full function body with any injected parameter transformations
    full_body = isempty(injected) ? body : Expr(:block, injected..., body)

    # Use helper function to generate the handler implementation
    return generate_state_handler_impl(:on_exit, smarg, smtype, new_args[2], full_body, is_any_state, state_name)
end

"""
    @hsmdef struct MyStateMachine
        # Your fields here
        field1::Type1
        field2::Type2
    end

A macro that adds the necessary fields to a struct to make it a proper
hierarchical state machine. It adds `_current`, `_source`, and `_event` fields and implements the
required methods for `Hsm.current`, `Hsm.current!`, `Hsm.source`, `Hsm.source!`, `Hsm.event`, and `Hsm.event!`.

# Features
- Adds `_current`, `_source`, and `_event` fields automatically (initialized to `:Root` and `:None` for event)
- Implements the required Hsm interface methods
- Provides convenient constructors for positional and keyword arguments

# Notes
- Must be the outermost macro and applied directly to a struct definition
- The struct must be explicitly declared as `mutable struct` (required for state transitions)
- Field names `_current`, `_source`, and `_event` are reserved and cannot be used
- This macro automatically adds type-specific default handlers for all required methods
- Using this macro is the only supported way to define a state machine

# Examples
```julia
# Basic usage - must be declared as mutable
@hsmdef mutable struct MyStateMachine
    counter::Int
    status::String
end

# With more complex fields
@hsmdef mutable struct MyDynamicStateMachine
    counter::Int
    status::String
    data::Vector{Float64}
end

# Creating an instance with the constructor
sm = MyStateMachine(0, "idle")
```
"""
macro hsmdef(struct_expr)
    # Add source location for better error messages
    line = __source__.line
    file = String(__source__.file)
    source_info = "line $line in $file"

    # Only allow direct struct definitions (no macrocall wrappers)
    if struct_expr.head != :struct
        throw(HsmMacroError("@hsmdef (at $(source_info)): Must be the outermost macro and applied directly to a struct definition."))
    end

    # Extract struct name and body
    mutable_flag = struct_expr.args[1]
    # Check if the struct is explicitly declared as mutable
    if !mutable_flag
        throw(HsmMacroError("@hsmdef (at $(source_info)): State machine structs must be explicitly declared as mutable. Use `mutable struct` instead of `struct`."))
    end
    struct_name = struct_expr.args[2]
    struct_body = struct_expr.args[3]

    # Separate fields from inner constructors (assignment or function form)
    fields = []
    for x in struct_body.args
        if x isa Symbol || (x isa Expr && (x.head == :(::) || x.head == :(=)))
            push!(fields, x)
        end
    end

    # Create unique internal field names using gensym
    current_field = gensym("current")
    source_field = gensym("source")
    event_field = gensym("event")

    # Add internal fields with unique generated names
    push!(fields, Expr(:(::), current_field, :Symbol))
    push!(fields, Expr(:(::), source_field, :Symbol))
    push!(fields, Expr(:(::), event_field, :Symbol))

    # Calculate number of user fields (without internal state machine fields)
    num_user_fields = length(fields) - 3

    # Add an internal constructor to initialize the state machine
    internal_constructor = quote
        function $(struct_name)(current, source, event, args::Vararg{Any,$num_user_fields})
            # Ensure the correct number of arguments
            sm = new(args..., current, source, event)

            # Call on_initial! to properly initialize the state machine
            Hsm.on_initial!(sm, :Root)

            return sm
        end
    end

    # Create the new struct definition with the additional fields and internal constructor
    new_struct_body = Expr(:block, fields..., internal_constructor)
    new_struct_def = Expr(:struct, mutable_flag, struct_name, new_struct_body)

    # Generate the implementation
    result = quote
        # Define the struct with the added fields and internal constructor
        $(esc(new_struct_def))

        function $(esc(struct_name))(args::Vararg{Any,$num_user_fields})
            return $(esc(struct_name))(:Root, :Root, :None, args...)
        end

        # Add keyword constructor for named parameters
        function $(esc(struct_name))(; kwargs...)
            # Extract field names (excluding internal fields)
            field_symbols = $(Expr(:vect, [x isa Symbol ? QuoteNode(x) : QuoteNode(x.args[1]) for x in fields[1:num_user_fields]]...))

            # Collect arguments in the correct order
            args = []
            for field_name in field_symbols
                if haskey(kwargs, field_name)
                    push!(args, kwargs[field_name])
                else
                    throw(ArgumentError("Missing required field: $field_name"))
                end
            end

            # Create the instance which will call the internal constructor
            return $(esc(struct_name))(:Root, :Root, :None, args...)
        end

        # Add default state machine handlers with type-specific dispatch
        # This ensures each state machine has its own default handlers
        # and prevents method ambiguity between different state machines

        # Use @eval to properly create the handlers with the correct scope
        @eval begin
            # Implement the Hsm interface methods with the generated field names
            Hsm.current(sm::$(struct_name)) = getfield(sm, $(QuoteNode(current_field)))
            Hsm.current!(sm::$(struct_name), state::Symbol) = setfield!(sm, $(QuoteNode(current_field)), state)
            Hsm.source(sm::$(struct_name)) = getfield(sm, $(QuoteNode(source_field)))
            Hsm.source!(sm::$(struct_name), state::Symbol) = setfield!(sm, $(QuoteNode(source_field)), state)
            Hsm.event(sm::$(struct_name)) = getfield(sm, $(QuoteNode(event_field)))
            Hsm.event!(sm::$(struct_name), event::Symbol) = setfield!(sm, $(QuoteNode(event_field)), event)

            # Default initial handler (returns EventHandled)
            ValSplit.@valsplit Hsm.on_initial!(sm::$(struct_name), Val(state::Symbol)) = Hsm.EventHandled

            # Default entry handler (does nothing)
            ValSplit.@valsplit Hsm.on_entry!(sm::$(struct_name), Val(state::Symbol)) = nothing

            # Default exit handler (does nothing)
            ValSplit.@valsplit Hsm.on_exit!(sm::$(struct_name), Val(state::Symbol)) = nothing

            # Default event handler (returns EventNotHandled to propagate events up)
            ValSplit.@valsplit Hsm.on_event!(
                sm::$(struct_name),
                Val(state::Symbol),
                Val(event::Symbol),
                arg
            ) = Hsm.EventNotHandled

            # Default ancestor method with error for undefined states
            ValSplit.@valsplit function Hsm.ancestor(
                sm::$(struct_name),
                Val(state::Symbol)
            )
                throw(HsmStateError("No ancestor defined for state \$(state) in $($(struct_name)). Use the @ancestor macro to define state relationships."))
                return :Root  # For type-stability, return :Root for unknown states
            end

            # Special case: Root state's ancestor is Root itself
            Hsm.ancestor(sm::$(struct_name), ::Val{:Root}) = :Root
        end
    end

    return result
end
