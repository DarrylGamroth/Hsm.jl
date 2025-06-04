# This file originally contained helper functions for extracting arguments from macro function definitions.
# The implementation has been simplified by directly processing arguments within each macro.

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
        error("@ancestor (at $(source_info)): Expected exactly two arguments: state machine type and state relationships")
    end

    smtype, pair = args

    if !(pair isa Expr)
        error("@ancestor (at $(source_info)): Second argument must be an expression with => or a begin...end block")
    end

    if pair.head == :block
        exs = []
        for stmt in pair.args
            if stmt isa Expr && stmt.head == :call && stmt.args[1] === Symbol("=>")
                if length(stmt.args) != 3
                    error("@ancestor (at $(source_info)): Invalid relationship expression. Use format: child => parent")
                end
                child = stmt.args[2]
                parent = stmt.args[3]
                push!(exs, :(Hsm.ancestor(::$(esc(smtype)), ::$(esc(:Val)){$child}) = $(parent)))
            elseif !(stmt isa LineNumberNode)
                error("@ancestor (at $(source_info)): Invalid statement in block. Expected format: child => parent")
            end
        end
        return Expr(:block, exs...)
    elseif pair.head == :call && pair.args[1] === Symbol("=>")
        if length(pair.args) != 3
            error("@ancestor (at $(source_info)): Invalid relationship expression. Use format: child => parent")
        end
        child = pair.args[2]
        parent = pair.args[3]
        return :(Hsm.ancestor(::$(esc(smtype)), ::$(esc(:Val)){$child}) = $(parent))
    else
        error("@ancestor (at $(source_info)): Expected => operator or begin...end block with relationships")
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
    def.head == :function || error("@on_event must wrap a function definition")

    fn_sig = def.args[1]
    body = def.args[2]
    args = fn_sig.args

    # Add source location for better error messages
    line = __source__.line
    file = String(__source__.file)
    error_prefix = "@on_event (line $line in $file)"

    if length(args) < 3
        error("$error_prefix: Function definition requires at least three arguments: state machine, state, and event")
    end

    sm_arg = args[1]
    state_arg = args[2]
    event_arg = args[3]
    data_arg = length(args) > 3 ? args[4] : gensym("unused")

    # Extract the state machine type and name
    if sm_arg isa Symbol
        smarg = sm_arg
        smtype = :Any
    elseif sm_arg isa Expr && sm_arg.head == :(::)
        smarg = sm_arg.args[1]
        smtype = sm_arg.args[2]
    else
        error("$error_prefix: Unexpected argument form for state machine parameter")
    end

    new_args = Expr[]
    injected = Expr[]

    # Process state argument
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

        state_sym = QuoteNode(Symbol(state_type))
        push!(new_args, Expr(:(::), state_name, Expr(:curly, :Val, state_sym)))

        # Always inject the state name assignment for consistency
        push!(injected, :($state_name = $state_sym))
    end

    # Process event argument
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
                error("$error_prefix: When using ::Any for event type, you must provide a named parameter (e.g., event::Any) to access the event value")
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
        error("$error_prefix: Event argument must be of the form ::EventType or event::EventType")
    end

    # Push state machine arg to front and data arg at the end
    pushfirst!(new_args, Expr(:(::), smarg, smtype))

    # Process data argument
    if data_arg isa Symbol && startswith(String(data_arg), "#unused")
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

    # Construct the full function body with any injected parameter transformations
    full_body = isempty(injected) ? body : Expr(:block, injected..., body)

    # Generate the final function using a quote block with @eval for proper hygiene
    # This ensures correct handling of variables from the caller's context
    if @isdefined(is_any_event) && is_any_event
        # Special case for Any event - use ValSplit macro
        return quote
            @eval begin
                ValSplit.@valsplit function Hsm.on_event!(
                    $smarg::$smtype,
                    $(new_args[2]),
                    Val($(event_name)::Symbol),
                    $(new_args[4])
                )
                    $full_body
                end

                function Hsm.on_event!(
                    $smarg::$smtype,
                    $(new_args[2]),
                    ::Val{$(QuoteNode(gensym("Any")))},
                    $(new_args[4])
                )
                    return Hsm.EventNotHandled
                end                
            end
        end
    else
        # Normal case - specific event type
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
    def.head == :function || error("@on_initial must wrap a function definition")

    fn_sig = def.args[1]
    body = def.args[2]
    args = fn_sig.args

    # Add source location for better error messages
    line = __source__.line
    file = String(__source__.file)
    error_prefix = "@on_initial (line $line in $file)"

    if length(args) < 2
        error("$error_prefix: Function definition requires at least two arguments: state machine and state")
    end

    sm_arg = args[1]
    state_arg = args[2]

    # Extract the state machine type and name
    if sm_arg isa Symbol
        smarg = sm_arg
        smtype = :Any
    elseif sm_arg isa Expr && sm_arg.head == :(::)
        smarg = sm_arg.args[1]
        smtype = sm_arg.args[2]
    else
        error("$error_prefix: Unexpected argument form for state machine parameter")
    end

    new_args = Expr[]
    injected = Expr[]

    # Process state argument
    if state_arg isa Expr && state_arg.head == :(::)
        if length(state_arg.args) == 1 || !(state_arg.args[1] isa Symbol)
            # Anonymous: ::StateA → ::Val{:StateA}
            state_type = length(state_arg.args) == 1 ? state_arg.args[1] : state_arg.args[2]
            state_sym = QuoteNode(Symbol(state_type))
            push!(new_args, Expr(:(::), Expr(:curly, :Val, state_sym)))
        else
            # Named: state::StateA → state::Val{:StateA}
            state_name = state_arg.args[1]
            state_type = state_arg.args[2]
            state_sym = QuoteNode(Symbol(state_type))
            push!(new_args, Expr(:(::), state_name, Expr(:curly, :Val, state_sym)))
            push!(injected, :($state_name = $state_sym))
        end
    else
        error("$error_prefix: State argument must be of the form ::StateType or state::StateType")
    end

    # Push state machine arg to front
    pushfirst!(new_args, Expr(:(::), smarg, smtype))

    # Construct the full function body with any injected parameter transformations
    full_body = isempty(injected) ? body : Expr(:block, injected..., body)

    # Generate the final function using a quote block with @eval for proper hygiene
    # This ensures correct handling of variables from the caller's context
    return quote
        @eval begin
            function Hsm.on_initial!(
                $smarg::$smtype,
                $(new_args[2])
            )
                $full_body
            end
        end
    end
end

"""
    @on_entry function(sm::MyStateMachine, ::StateRunning)
        # entry code
    end

Define an entry handler for a specific state. Entry handlers are executed when transitioning into a state.

# Arguments
- `function`: A function definition with the state machine as first argument, followed by state type

# Examples
```julia
# Simple entry handler
@on_entry function(sm::MyStateMachine, ::StateRunning)
    println("Entering Running state")
    sm.status = "running"
end

# With named state parameter
@on_entry function(sm::MyStateMachine, state::StateError)
    @debug "Entering Error state"
    sm.error_count += 1
    sm.last_error_time = now()
end
```
"""
macro on_entry(def)
    def.head == :function || error("@on_entry must wrap a function definition")

    fn_sig = def.args[1]
    body = def.args[2]
    args = fn_sig.args

    # Add source location for better error messages
    line = __source__.line
    file = String(__source__.file)
    error_prefix = "@on_entry (line $line in $file)"

    if length(args) < 2
        error("$error_prefix: Function definition requires at least two arguments: state machine and state")
    end

    sm_arg = args[1]
    state_arg = args[2]

    # Extract the state machine type and name
    if sm_arg isa Symbol
        smarg = sm_arg
        smtype = :Any
    elseif sm_arg isa Expr && sm_arg.head == :(::)
        smarg = sm_arg.args[1]
        smtype = sm_arg.args[2]
    else
        error("$error_prefix: Unexpected argument form for state machine parameter")
    end

    new_args = Expr[]
    injected = Expr[]

    # Process state argument
    if state_arg isa Expr && state_arg.head == :(::)
        if length(state_arg.args) == 1 || !(state_arg.args[1] isa Symbol)
            # Anonymous: ::StateA → ::Val{:StateA}
            state_type = length(state_arg.args) == 1 ? state_arg.args[1] : state_arg.args[2]
            state_sym = QuoteNode(Symbol(state_type))
            push!(new_args, Expr(:(::), Expr(:curly, :Val, state_sym)))
        else
            # Named: state::StateA → state::Val{:StateA}
            state_name = state_arg.args[1]
            state_type = state_arg.args[2]
            state_sym = QuoteNode(Symbol(state_type))
            push!(new_args, Expr(:(::), state_name, Expr(:curly, :Val, state_sym)))
            push!(injected, :($state_name = $state_sym))
        end
    else
        error("$error_prefix: State argument must be of the form ::StateType or state::StateType")
    end

    # Push state machine arg to front
    pushfirst!(new_args, Expr(:(::), smarg, smtype))

    # Construct the full function body with any injected parameter transformations
    full_body = isempty(injected) ? body : Expr(:block, injected..., body)

    # Generate the final function using a quote block with @eval for proper hygiene
    # This ensures correct handling of variables from the caller's context
    return quote
        @eval begin
            function Hsm.on_entry!(
                $smarg::$smtype,
                $(new_args[2])
            )
                $full_body
            end
        end
    end
end

"""
    @on_exit function(sm::MyStateMachine, ::StateRunning)
        # exit code
    end

Define an exit handler for a specific state. Exit handlers are executed when transitioning out of a state.

# Arguments
- `function`: A function definition with the state machine as first argument, followed by state type

# Examples
```julia
# Simple exit handler
@on_exit function(sm::MyStateMachine, ::StateRunning)
    println("Exiting Running state")
    sm.running_time += now() - sm.start_time
end

# With named state parameter
@on_exit function(sm::MyStateMachine, state::StateConnected)
    @debug "Cleaning up connection resources"
    close(sm.connection)
    sm.connection = nothing
end
```
"""
macro on_exit(def)
    def.head == :function || error("@on_exit must wrap a function definition")

    fn_sig = def.args[1]
    body = def.args[2]
    args = fn_sig.args

    # Add source location for better error messages
    line = __source__.line
    file = String(__source__.file)
    error_prefix = "@on_exit (line $line in $file)"

    if length(args) < 2
        error("$error_prefix: Function definition requires at least two arguments: state machine and state")
    end

    sm_arg = args[1]
    state_arg = args[2]

    # Extract the state machine type and name
    if sm_arg isa Symbol
        smarg = sm_arg
        smtype = :Any
    elseif sm_arg isa Expr && sm_arg.head == :(::)
        smarg = sm_arg.args[1]
        smtype = sm_arg.args[2]
    else
        error("$error_prefix: Unexpected argument form for state machine parameter")
    end

    new_args = Expr[]
    injected = Expr[]

    # Process state argument
    if state_arg isa Expr && state_arg.head == :(::)
        if length(state_arg.args) == 1 || !(state_arg.args[1] isa Symbol)
            # Anonymous: ::StateA → ::Val{:StateA}
            state_type = length(state_arg.args) == 1 ? state_arg.args[1] : state_arg.args[2]
            state_sym = QuoteNode(Symbol(state_type))
            push!(new_args, Expr(:(::), Expr(:curly, :Val, state_sym)))
        else
            # Named: state::StateA → state::Val{:StateA}
            state_name = state_arg.args[1]
            state_type = state_arg.args[2]
            state_sym = QuoteNode(Symbol(state_type))
            push!(new_args, Expr(:(::), state_name, Expr(:curly, :Val, state_sym)))
            push!(injected, :($state_name = $state_sym))
        end
    else
        error("$error_prefix: State argument must be of the form ::StateType or state::StateType")
    end

    # Push state machine arg to front
    pushfirst!(new_args, Expr(:(::), smarg, smtype))

    # Construct the full function body with any injected parameter transformations
    full_body = isempty(injected) ? body : Expr(:block, injected..., body)

    # Generate the final function using a quote block with @eval for proper hygiene
    # This ensures correct handling of variables from the caller's context
    return quote
        @eval begin
            function Hsm.on_exit!(
                $smarg::$smtype,
                $(new_args[2])
            )
                $full_body
            end
        end
    end
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
        error("@hsmdef (at $(source_info)): Must be the outermost macro and applied directly to a struct definition.")
    end

    # Extract struct name and body
    mutable_flag = struct_expr.args[1]
    # Check if the struct is explicitly declared as mutable
    if !mutable_flag
        error("@hsmdef (at $(source_info)): State machine structs must be explicitly declared as mutable. Use `mutable struct` instead of `struct`.")
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

    # Check for reserved field names
    if any(x -> (x == :_current) || (x isa Expr && x.args[1] == :_current), fields)
        error("@hsmdef (at $(source_info)): The field name '_current' is reserved and cannot be used in your struct.")
    end
    if any(x -> (x == :_source) || (x isa Expr && x.args[1] == :_source), fields)
        error("@hsmdef (at $(source_info)): The field name '_source' is reserved and cannot be used in your struct.")
    end
    if any(x -> (x == :_event) || (x isa Expr && x.args[1] == :_event), fields)
        error("@hsmdef (at $(source_info)): The field name '_event' is reserved and cannot be used in your struct.")
    end

    # Add _current, _source, and _event fields
    push!(fields, :(_current::Symbol))
    push!(fields, :(_source::Symbol))
    push!(fields, :(_event::Symbol))

    # Calculate number of user fields (without _current, _source, and _event)
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
            # Extract field names (excluding reserved fields)
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
            # Implement the Hsm interface methods

            Hsm.current(sm::$(struct_name)) = sm._current
            Hsm.current!(sm::$(struct_name), state::Symbol) = sm._current = state
            Hsm.source(sm::$(struct_name)) = sm._source
            Hsm.source!(sm::$(struct_name), state::Symbol) = sm._source = state
            Hsm.event(sm::$(struct_name)) = sm._event
            Hsm.event!(sm::$(struct_name), event::Symbol) = sm._event = event

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
                error("No ancestor for state \$state in $($(struct_name))")
                return :Root
            end

            # Special case: Root state's ancestor is Root itself
            Hsm.ancestor(sm::$(struct_name), ::Val{:Root}) = :Root
        end
    end

    return result
end
