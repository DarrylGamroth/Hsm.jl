"""
    extract_sm_arg(argtuple, macro_name)

Internal helper function to extract state machine argument from macro function definitions.
- `argtuple`: The tuple of arguments from the function definition
- `macro_name`: Name of the macro for error reporting (including source location)

Returns a tuple of (smarg, smtype) where smarg is the argument name and smtype is its type.
"""
function extract_sm_arg(argtuple, macro_name)
    if !(argtuple isa Expr && argtuple.head == :tuple)
        error("$macro_name: Function definition must be of the form function(sm::Type, ...) ... end")
    end

    if isempty(argtuple.args)
        error("$macro_name: Function definition requires at least one argument")
    end

    smarg_expr = argtuple.args[1]
    if smarg_expr isa Symbol
        smarg = smarg_expr
        smtype = :Any
    elseif smarg_expr isa Expr && smarg_expr.head == :(::)
        smarg = smarg_expr.args[1]
        smtype = smarg_expr.args[2]
    else
        error("$macro_name: Unexpected argument form for state machine parameter")
    end

    return smarg, smtype
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
    :State_S => :State_Root
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
    @on_event state event function(sm::MyStateMachine, arg)
        # handler code
    end

    # Or with keyword arguments:
    @on_event state = :StateA event = :EventX function(sm::MyStateMachine, arg)
        # Access state and event values in the body
        println("Handling \$(event) in \$(state)")
        return Hsm.EventHandled
    end

Define an event handler for a specific state and event.

# Arguments
- `state`: The state symbol for which this handler is defined
- `event`: The event symbol this handler responds to, or `Any` to create a catch-all handler
- `function`: A function definition with the state machine as first argument

# Keyword Arguments Style
When using the keyword argument style, the specified variables will be available in the function body:
- `state = :StateA`: Makes `state` variable available in the function body with value `:StateA`
- `event = :EventX`: Makes `event` variable available in the function body with value `:EventX`

# Returns
The handler should return `Hsm.EventHandled` if the event was handled, or
`Hsm.EventNotHandled` if it should be passed to ancestor states.

# Examples
```julia
# Handle EventX in StateA, with an explicit argument name
@on_event :StateA :EventX function(sm::MyStateMachine, data)
    # Use data parameter
    println("Received data: ", data)
    return Hsm.EventHandled
end

# Using keyword arguments to reference state and event in the body
@on_event state = :StateA event = :EventX function(sm::MyStateMachine, data)
    # Variables 'state' and 'event' are available here
    println("Handling \$(event) in \$(state) with data: ", data)
    return Hsm.EventHandled
end

# Catch-all handler for any event in StateB
@on_event :StateB Any function(sm::MyStateMachine, arg)
    println("Handling unspecified event in StateB: ", Hsm.event(sm))
    return Hsm.EventNotHandled
end

# With default argument name and state transition
@on_event :StateA :EventY function(sm::MyStateMachine)
    return Hsm.transition!(sm, :StateB) do
        sm.counter += 1
    end
end
```
"""
macro on_event(args...)
    # Add source location for better error messages
    line = __source__.line
    file = String(__source__.file)
    error_prefix = "@on_event (line $line in $file)"

    # Check if using keyword arguments style or positional style
    if length(args) == 3 && !(args[1] isa Expr && args[1].head == :(=))
        # Traditional style: state, event, def
        state, event, def = args
        using_kwargs = false
    elseif all(arg isa Expr && arg.head == :(=) for arg in args[1:end-1])
        # Keyword arguments style
        using_kwargs = true
        def = args[end]

        # Extract keyword arguments
        kwargs = Dict{Symbol,Any}()
        for arg in args[1:end-1]
            if arg.head == :(=)
                kwargs[arg.args[1]] = arg.args[2]
            end
        end

        # Ensure required kwargs are provided
        if !haskey(kwargs, :state)
            error("$error_prefix: Missing required keyword argument 'state'")
        end
        if !haskey(kwargs, :event)
            error("$error_prefix: Missing required keyword argument 'event'")
        end

        state = kwargs[:state]
        event = kwargs[:event]
    else
        error("$error_prefix: Invalid syntax. Use either positional arguments (@on_event state event function...) or keyword arguments (@on_event state=:State event=:Event function...)")
    end

    # Extract function body and arguments
    body = def.args[2]
    func_args = def.args[1]

    if !(func_args isa Expr && func_args.head == :tuple)
        error("$error_prefix: Function definition must be of the form function(sm::Type, ...) ... end")
    end

    if isempty(func_args.args)
        error("$error_prefix: Function definition requires at least one argument")
    end

    # Extract state machine parameter
    smarg_expr = func_args.args[1]
    if smarg_expr isa Symbol
        smarg = smarg_expr
        smtype = :Any
    elseif smarg_expr isa Expr && smarg_expr.head == :(::)
        smarg = smarg_expr.args[1]
        smtype = smarg_expr.args[2]
    else
        error("$error_prefix: Unexpected argument form for state machine parameter")
    end

    # Handle the optional argument for the event data
    argname = length(func_args.args) > 1 ? func_args.args[2] : :__unused

    # Special case for default event handler (catch-all) using `Any`
    if event == :Any
        # Extract event argument name and type (if present)
        if length(func_args.args) > 1
            evarg_expr = func_args.args[2]
            if evarg_expr isa Symbol
                evarg, evtype = evarg_expr, :Any
            elseif evarg_expr isa Expr && evarg_expr.head == :(::)
                evarg, evtype = evarg_expr.args[1], evarg_expr.args[2]
            else
                error("$error_prefix: Unexpected argument form for event argument")
            end
        else
            # Use '_unused' instead of '_' which is write-only and can't be used as a parameter
            evarg, evtype = :__unused, :Any
        end

        # Generate code based on kwargs usage
        if using_kwargs
            # With kwargs - add local state and event variables
            # Create a modified body that includes state and event bindings
            modified_body = quote
                local state = $(state)
                local event = __event
                $(body)
            end

            return quote
                ValSplit.@valsplit function Hsm.on_event!(
                    $(esc(smarg))::$(esc(smtype)),
                    $(esc(:__state))::$(esc(:Val)){$state},
                    Val($(esc(:__event))::$(esc(:Symbol))),
                    $(esc(evarg))::$(esc(evtype))
                )
                    $(esc(modified_body))
                end

                function Hsm.on_event!(
                    $(esc(smarg))::$(esc(smtype)),
                    ::$(esc(:Val)){$state},
                    ::$(esc(:Val)){:__dummy},
                    $(esc(evarg))::$(esc(evtype))
                )
                    return Hsm.EventNotHandled
                end
            end
        else
            # Traditional style without kwargs
            return quote
                ValSplit.@valsplit function Hsm.on_event!(
                    $(esc(smarg))::$(esc(smtype)),
                    $(esc(:__state))::$(esc(:Val)){$state},
                    Val($(esc(:__event))::$(esc(:Symbol))),
                    $(esc(evarg))::$(esc(evtype))
                )
                    $(esc(body))
                end

                function Hsm.on_event!(
                    $(esc(smarg))::$(esc(smtype)),
                    ::$(esc(:Val)){$state},
                    ::$(esc(:Val)){:__dummy},
                    $(esc(evarg))::$(esc(evtype))
                )
                    return Hsm.EventNotHandled
                end
            end
        end
    else
        # Regular event handler for specific event
        if using_kwargs
            # With kwargs - add local state and event variables
            # Create a modified body that includes state and event bindings
            modified_body = quote
                local state = $(state)
                local event = $(event)
                $(body)
            end

            return quote
                function Hsm.on_event!(
                    $(esc(smarg))::$(esc(smtype)),
                    ::$(esc(:Val)){$state},
                    ::$(esc(:Val)){$event},
                    $(esc(argname))
                )
                    $(esc(modified_body))
                end
            end
        else
            # Traditional style without kwargs
            return quote
                function Hsm.on_event!(
                    $(esc(smarg))::$(esc(smtype)),
                    ::$(esc(:Val)){$state},
                    ::$(esc(:Val)){$event},
                    $(esc(argname))
                )
                    $(esc(body))
                end
            end
        end
    end
end

"""
    @on_initial state function(sm::MyStateMachine)
        # initialization code
    end

Define an initial handler for a specific state. Initial handlers are called when a state becomes active
and typically transition to a child state or perform initialization logic.

# Arguments
- `state`: The state symbol for which this handler is defined
- `function`: A function definition with the state machine as the argument

# Returns
The handler should either return `Hsm.EventHandled` or perform a transition to a child state.

# Examples
```julia
# Simple initial handler transitioning to a child state
@on_initial :State_S function(sm::MyStateMachine)
    return Hsm.transition!(sm, :State_S1)
end

# Initial handler with setup logic
@on_initial :State_Root function(sm::MyStateMachine)
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
macro on_initial(state, def)
    # Add source location for better error messages
    line = __source__.line
    file = String(__source__.file)

    body = def.args[2]
    smarg, smtype = extract_sm_arg(def.args[1], "@on_initial (line $line in $file)")

    return quote
        function Hsm.on_initial!($smarg::$(esc(smtype)), ::$(esc(:Val)){$state})
            $body
        end
    end
end

"""
    @on_entry state function(sm::MyStateMachine)
        # entry code
    end

Define an entry handler for a specific state. Entry handlers are executed when transitioning into a state.

# Arguments
- `state`: The state symbol for which this handler is defined
- `function`: A function definition with the state machine as the argument

# Examples
```julia
# Simple entry handler
@on_entry :State_Running function(sm::MyStateMachine)
    println("Entering Running state")
    sm.status = "running"
end

# Entry handler with logging
@on_entry :State_Error function(sm::MyStateMachine)
    @debug "Entering Error state"
    sm.error_count += 1
    sm.last_error_time = now()
end
```
"""
macro on_entry(state, def)
    # Add source location for better error messages
    line = __source__.line
    file = String(__source__.file)

    body = def.args[2]
    smarg, smtype = extract_sm_arg(def.args[1], "@on_entry (line $line in $file)")

    return quote
        function Hsm.on_entry!($smarg::$(esc(smtype)), ::$(esc(:Val)){$state})
            $body
        end
    end
end

"""
    @on_exit state function(sm::MyStateMachine)
        # exit code
    end

Define an exit handler for a specific state. Exit handlers are executed when transitioning out of a state.

# Arguments
- `state`: The state symbol for which this handler is defined
- `function`: A function definition with the state machine as the argument

# Examples
```julia
# Simple exit handler
@on_exit :State_Running function(sm::MyStateMachine)
    println("Exiting Running state")
    sm.running_time += now() - sm.start_time
end

# Exit handler with resource cleanup
@on_exit :State_Connected function(sm::MyStateMachine)
    @debug "Cleaning up connection resources"
    close(sm.connection)
    sm.connection = nothing
end
```
"""
macro on_exit(state, def)
    # Add source location for better error messages
    line = __source__.line
    file = String(__source__.file)

    body = def.args[2]
    smarg, smtype = extract_sm_arg(def.args[1], "@on_exit (line $line in $file)")

    return quote
        function Hsm.on_exit!($smarg::$(esc(smtype)), ::$(esc(:Val)){$state})
            $body
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
- Adds `_current`, `_source`, and `_event` fields automatically (initialized to `Hsm.Root` and `:None` for event)
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
            Hsm.on_initial!(sm, Hsm.Root)

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
            return $(esc(struct_name))(Root, Root, :None, args...)
        end

        # Add keyword constructor for named parameters
        function $(esc(struct_name))(; kwargs...)
            # Handle the case where there are no user fields
            # if $num_user_fields == 0
            #     # Create the instance which will call the internal constructor
            #     return $(esc(struct_name))(Root, Root, :None)
            # end

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
            return $(esc(struct_name))(Root, Root, :None, args...)
        end

        # Implement the Hsm interface methods
        Hsm.current(sm::$(esc(struct_name))) = sm._current
        Hsm.current!(sm::$(esc(struct_name)), state::Symbol) = (sm._current = state)
        Hsm.source(sm::$(esc(struct_name))) = sm._source
        Hsm.source!(sm::$(esc(struct_name)), state::Symbol) = (sm._source = state)
        Hsm.event(sm::$(esc(struct_name))) = sm._event
        Hsm.event!(sm::$(esc(struct_name)), event::Symbol) = (sm._event = event)

        # Add default state machine handlers with type-specific dispatch
        # This ensures each state machine has its own default handlers
        # and prevents method ambiguity between different state machines

        # Use @eval to properly create the handlers with the correct scope
        @eval begin
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
                return Hsm.Root
            end

            # Special case: Root state's ancestor is Root itself
            Hsm.ancestor(sm::$(struct_name), ::Val{Hsm.Root}) = Hsm.Root
        end
    end

    return result
end
