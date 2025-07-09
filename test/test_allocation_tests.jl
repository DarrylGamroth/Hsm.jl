using Pkg
Pkg.activate(".")

using Test
using Hsm
using ValSplit

# Helper function to print allocation results
function print_allocation_result(test_name, allocs)
    println("[$test_name] Allocations: $allocs bytes")
end

# Define a simple state machine for allocation testing
# Using type-stable fields to avoid allocation due to type instability
@hsmdef mutable struct AllocationTestSm
    counter::Int
    int_data::Int
    float_data::Float64
    bool_data::Bool
    symbol_data::Symbol
    char_data::Char
    string_data::String
    last_event::Symbol
end

# Define custom structs for allocation testing
struct CustomStruct
    value::Int
    name::String
end

struct NestedStruct
    inner::CustomStruct
    extra::Float64
end

# Define state hierarchy
@statedef AllocationTestSm :StateA :Root
@statedef AllocationTestSm :StateB :Root

# Define handlers
@on_initial function (sm::AllocationTestSm, ::Root)
    return Hsm.transition!(sm, :StateA)
end

# Custom struct and vector event handlers
@on_event function (sm::AllocationTestSm, ::StateA, ::StructEvent, arg::CustomStruct)
    sm.counter += 1
    sm.int_data = arg.value
    sm.last_event = :StructEvent
    return Hsm.EventHandled
end

@on_event function (sm::AllocationTestSm, ::StateA, ::VectorEvent, arg::Vector{Int})
    sm.counter += 1
    sm.int_data = length(arg)
    sm.last_event = :VectorEvent
    return Hsm.EventHandled
end

@on_event function (sm::AllocationTestSm, ::StateA, ::VectorAnyEvent, arg::Vector{Any})
    sm.counter += 1
    sm.int_data = length(arg)
    sm.last_event = :VectorAnyEvent
    return Hsm.EventHandled
end

@on_event function (sm::AllocationTestSm, ::StateA, ::NestedEvent, arg::NestedStruct)
    sm.counter += 1
    sm.int_data = arg.inner.value
    sm.last_event = :NestedEvent
    return Hsm.EventHandled
end

# Transition events with non-isbits types
@on_event function (sm::AllocationTestSm, ::StateA, ::StructTransitionEvent, arg::CustomStruct)
    sm.int_data = arg.value
    sm.last_event = :StructTransitionEvent
    return Hsm.transition!(sm, :StateB)
end

@on_event function (sm::AllocationTestSm, ::StateA, ::VectorTransitionEvent, arg::Vector{Int})
    sm.int_data = length(arg)
    sm.last_event = :VectorTransitionEvent
    return Hsm.transition!(sm, :StateB)
end

@on_event function (sm::AllocationTestSm, ::StateB, ::StructResetEvent, arg::CustomStruct)
    sm.counter = 0
    sm.int_data = arg.value
    sm.last_event = :StructResetEvent
    return Hsm.transition!(sm, :StateA)
end

@on_event function (sm::AllocationTestSm, ::StateB, ::VectorResetEvent, arg::Vector{Int})
    sm.counter = 0
    sm.int_data = length(arg)
    sm.last_event = :VectorResetEvent
    return Hsm.transition!(sm, :StateA)
end

@on_event function (sm::AllocationTestSm, ::StateA, ::TestEvent, arg::Int)
    sm.counter += 1
    sm.int_data = arg
    sm.last_event = :TestEvent
    return Hsm.EventHandled
end

@on_event function (sm::AllocationTestSm, ::StateA, ::TestEvent, arg::Float64)
    sm.counter += 1
    sm.float_data = arg
    sm.last_event = :TestEvent
    return Hsm.EventHandled
end

@on_event function (sm::AllocationTestSm, ::StateA, ::TestEvent, arg::Bool)
    sm.counter += 1
    sm.bool_data = arg
    sm.last_event = :TestEvent
    return Hsm.EventHandled
end

@on_event function (sm::AllocationTestSm, ::StateA, ::TestEvent, arg::Symbol)
    sm.counter += 1
    sm.symbol_data = arg
    sm.last_event = :TestEvent
    return Hsm.EventHandled
end

@on_event function (sm::AllocationTestSm, ::StateA, ::TestEvent, arg::Char)
    sm.counter += 1
    sm.char_data = arg
    sm.last_event = :TestEvent
    return Hsm.EventHandled
end

@on_event function (sm::AllocationTestSm, ::StateA, ::TestEvent, arg::String)
    sm.counter += 1
    sm.string_data = arg
    sm.last_event = :TestEvent
    return Hsm.EventHandled
end

@on_event function (sm::AllocationTestSm, ::StateA, ::TestEvent, arg::UInt8)
    sm.counter += 1
    sm.int_data = Int(arg)  # Store as Int for simplicity
    sm.last_event = :TestEvent
    return Hsm.EventHandled
end

@on_event function (sm::AllocationTestSm, ::StateA, ::TestEvent, arg::Nothing)
    sm.counter += 1
    sm.last_event = :TestEvent
    return Hsm.EventHandled
end

# Catch-all handler for other types (will use int_data field)
@on_event function (sm::AllocationTestSm, ::StateA, ::TestEvent, arg)
    sm.counter += 1
    sm.int_data = sizeof(arg)
    sm.last_event = :TestEvent
    return Hsm.EventHandled
end

@on_event function (sm::AllocationTestSm, ::StateA, ::TransitionEvent, arg)
    return Hsm.transition!(sm, :StateB)
end

@on_event function (sm::AllocationTestSm, ::StateB, ::ResetEvent, arg)
    sm.counter = 0
    return Hsm.transition!(sm, :StateA)
end

# Default handler for any unhandled event
@on_event function (sm::AllocationTestSm, ::StateA, event::Any, arg)
    sm.counter += 100  # Marker for default handler
    return Hsm.EventHandled
end

# Custom struct handler
@on_event function (sm::AllocationTestSm, ::StateA, ::StructEvent, arg::CustomStruct)
    sm.counter += 1
    sm.int_data = arg.value
    sm.last_event = :StructEvent
    return Hsm.EventHandled
end

# Vector handlers
@on_event function (sm::AllocationTestSm, ::StateA, ::VectorEvent, arg::Vector{Int})
    sm.counter += 1
    sm.int_data = length(arg)
    sm.last_event = :VectorEvent
    return Hsm.EventHandled
end

@on_event function (sm::AllocationTestSm, ::StateA, ::VectorAnyEvent, arg::Vector{Any})
    sm.counter += 1
    sm.int_data = length(arg)
    sm.last_event = :VectorAnyEvent
    return Hsm.EventHandled
end

# Nested struct handler
@on_event function (sm::AllocationTestSm, ::StateA, ::NestedEvent, arg::NestedStruct)
    sm.counter += 1
    sm.int_data = arg.inner.value
    sm.last_event = :NestedEvent
    return Hsm.EventHandled
end

# Helper function to warmup the state machine with all dispatch types
function warmup_allocation_test_sm!(sm::AllocationTestSm)
    # Comprehensive warm up - ensure all method specializations are compiled
    for _ in 1:3  # Multiple rounds to ensure compilation is complete
        Hsm.dispatch!(sm, :TestEvent, 1)
        Hsm.dispatch!(sm, :TestEvent, 1.0)
        Hsm.dispatch!(sm, :TestEvent, true)
        Hsm.dispatch!(sm, :TestEvent, :sym)
        Hsm.dispatch!(sm, :TestEvent, 'x')
        Hsm.dispatch!(sm, :TestEvent, UInt8(1))

        # Warm up our new types and transitions
        test_struct = CustomStruct(42, "test")
        Hsm.dispatch!(sm, :StructEvent, test_struct)
        Hsm.dispatch!(sm, :StructTransitionEvent, test_struct)
        Hsm.dispatch!(sm, :StructResetEvent, test_struct)

        small_vec = [1, 2, 3]
        Hsm.dispatch!(sm, :VectorEvent, small_vec)
        Hsm.dispatch!(sm, :VectorTransitionEvent, small_vec)
        Hsm.dispatch!(sm, :VectorResetEvent, small_vec)

        mixed_vec = Any[1, "two", 3.0]
        Hsm.dispatch!(sm, :VectorAnyEvent, mixed_vec)

        inner = CustomStruct(99, "nested")
        nested = NestedStruct(inner, 3.14)
        Hsm.dispatch!(sm, :NestedEvent, nested)

        # Warm up our new types
        test_struct = CustomStruct(42, "test")
        Hsm.dispatch!(sm, :StructEvent, test_struct)

        small_vec = [1, 2, 3]
        Hsm.dispatch!(sm, :VectorEvent, small_vec)

        mixed_vec = Any[1, "two", 3.0]
        Hsm.dispatch!(sm, :VectorAnyEvent, mixed_vec)

        inner = CustomStruct(99, "nested")
        nested = NestedStruct(inner, 3.14)
        Hsm.dispatch!(sm, :NestedEvent, nested)
    end
    sm.counter = 0  # Reset counter after warmup
end

@testset "Int dispatch allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)
    warmup_allocation_test_sm!(sm)

    allocs = @allocated(Hsm.dispatch!(sm, :TestEvent, 42))
    print_allocation_result("Int dispatch", allocs)
    @test allocs == 0  # Expect zero or minimal allocations
    @test sm.counter == 1
    @test sm.int_data == 42
end

@testset "Float64 dispatch allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)
    warmup_allocation_test_sm!(sm)

    allocs = @allocated(Hsm.dispatch!(sm, :TestEvent, 3.14))
    print_allocation_result("Float64 dispatch", allocs)
    @test allocs == 0  # Expect zero or minimal allocations
    @test sm.counter == 1
    @test sm.float_data == 3.14
end

@testset "Bool dispatch allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)
    warmup_allocation_test_sm!(sm)

    allocs = @allocated(Hsm.dispatch!(sm, :TestEvent, true))
    print_allocation_result("Bool dispatch", allocs)
    @test allocs == 0  # Expect zero or minimal allocations
    @test sm.counter == 1
    @test sm.bool_data == true
end

@testset "Symbol dispatch allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)
    warmup_allocation_test_sm!(sm)

    allocs = @allocated(Hsm.dispatch!(sm, :TestEvent, :symbol_value))
    print_allocation_result("Symbol dispatch", allocs)
    @test allocs == 0  # Expect zero or minimal allocations
    @test sm.counter == 1
    @test sm.symbol_data == :symbol_value
end

@testset "Char dispatch allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)
    warmup_allocation_test_sm!(sm)

    allocs = @allocated(Hsm.dispatch!(sm, :TestEvent, 'A'))
    print_allocation_result("Char dispatch", allocs)
    @test allocs == 0  # Expect zero or minimal allocations
    @test sm.counter == 1
    @test sm.char_data == 'A'
end

@testset "UInt8 dispatch allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)
    warmup_allocation_test_sm!(sm)

    allocs = @allocated(Hsm.dispatch!(sm, :TestEvent, UInt8(255)))
    print_allocation_result("UInt8 dispatch", allocs)
    @test allocs == 0  # Expect zero or minimal allocations
    @test sm.counter == 1
    @test sm.int_data == 255  # Converted to Int
end

@testset "Nothing dispatch allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up with nothing
    for _ in 1:5
        Hsm.dispatch!(sm, :TestEvent, nothing)
        Hsm.dispatch!(sm, :TestEvent)
    end
    sm.counter = 0

    # Test with nothing (special isbits singleton)
    allocs = @allocated(Hsm.dispatch!(sm, :TestEvent, nothing))
    print_allocation_result("Nothing dispatch", allocs)
    @test allocs == 0  # Expect zero or minimal allocations
    @test sm.counter == 1
    @test sm.last_event == :TestEvent
end

@testset "No argument dispatch allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up with nothing
    for _ in 1:5
        Hsm.dispatch!(sm, :TestEvent, nothing)
        Hsm.dispatch!(sm, :TestEvent)
    end
    sm.counter = 0

    # Test with no argument (defaults to nothing)
    allocs = @allocated(Hsm.dispatch!(sm, :TestEvent))
    print_allocation_result("No argument dispatch", allocs)
    @test allocs == 0  # Expect zero or minimal allocations
    @test sm.counter == 1
    @test sm.last_event == :TestEvent
end

@testset "Number abstract type dispatch allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up with abstract types
    int_val_warmup::Number = 1
    Hsm.dispatch!(sm, :TestEvent, int_val_warmup)
    sm.counter = 0

    # Test with Number (abstract type through Int)
    int_val::Number = 123
    allocs = @allocated(Hsm.dispatch!(sm, :TestEvent, int_val))
    print_allocation_result("Number abstract type", allocs)
    @test allocs == 0  # Expect zero or minimal allocations
    @test sm.counter == 1
    @test sm.int_data == 123
end

@testset "Real abstract type dispatch allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up with abstract types
    float_val_warmup::Real = 1.0
    Hsm.dispatch!(sm, :TestEvent, float_val_warmup)
    sm.counter = 0

    # Test with Real (abstract type through Float64)
    float_val::Real = 2.718
    allocs = @allocated(Hsm.dispatch!(sm, :TestEvent, float_val))
    print_allocation_result("Real abstract type", allocs)
    @test allocs == 0  # Expect zero or minimal allocations
    @test sm.counter == 1
    @test sm.float_data == 2.718
end

@testset "Any type dispatch allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up with abstract types
    any_val_warmup::Any = 1
    Hsm.dispatch!(sm, :TestEvent, any_val_warmup)
    sm.counter = 0

    # Test with Any type containing isbits value
    any_val::Any = 456
    allocs = @allocated(Hsm.dispatch!(sm, :TestEvent, any_val))
    print_allocation_result("Any type", allocs)
    @test allocs == 0
    @test sm.counter == 1
    @test sm.int_data == 456
end

@testset "String dispatch allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up with non-isbits types
    Hsm.dispatch!(sm, :TestEvent, "warmup")
    sm.counter = 0

    # Test with String (non-isbits, heap allocated)
    result = @allocated(Hsm.dispatch!(sm, :TestEvent, "hello"))
    print_allocation_result("String dispatch", result)
    @test result == 0  # Should not allocate for String
    @test sm.counter == 1
    @test sm.string_data == "hello"
end

@testset "Array dispatch allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up with non-isbits types
    Hsm.dispatch!(sm, :TestEvent, [1])
    sm.counter = 0

    # Test with Array (non-isbits, heap allocated)
    arr = [1, 2, 3]
    result = @allocated(Hsm.dispatch!(sm, :TestEvent, arr))
    print_allocation_result("Array dispatch", result)
    @test result == 0  # Should not allocate for Array
    @test sm.counter == 1
    @test sm.int_data == sizeof(arr)  # Using catch-all handler
end

@testset "Dict dispatch allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up with non-isbits types
    Hsm.dispatch!(sm, :TestEvent, Dict(:k => :v))
    sm.counter = 0

    # Test with Dict (non-isbits, heap allocated)
    dict = Dict(:key => :value)
    result = @allocated(Hsm.dispatch!(sm, :TestEvent, dict))
    print_allocation_result("Dict dispatch", result)
    @test result == 0  # Should not allocate for Dict
    @test sm.counter == 1
    @test sm.int_data == sizeof(dict)  # Using catch-all handler
end

@testset "State transition allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up state transitions
    Hsm.dispatch!(sm, :TransitionEvent, 1)
    Hsm.dispatch!(sm, :ResetEvent, 1)
    sm.counter = 0

    # Test transition with isbits argument
    allocs = @allocated(Hsm.dispatch!(sm, :TransitionEvent, 789))
    print_allocation_result("State transition", allocs)
    @test allocs == 0  # Allow for some allocation during transitions
    @test Hsm.current(sm) == :StateB
end

@testset "State reset transition allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up state transitions
    Hsm.dispatch!(sm, :TransitionEvent, 1)  # Move from StateA to StateB

    # Verify we're in the right state
    @test Hsm.current(sm) == :StateB

    # Make sure the counter has a non-zero value to verify reset
    sm.counter = 100

    # Now test the ResetEvent which should trigger transition back to StateA
    allocs = @allocated(Hsm.dispatch!(sm, :ResetEvent, 999))
    print_allocation_result("State reset transition", allocs)
    @test allocs == 0  # Allow for some allocation
    @test Hsm.current(sm) == :StateA  # Should be back in StateA
    @test sm.counter == 0  # Counter should be reset by the handler
end

@testset "Default handler isbits allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up default handlers
    Hsm.dispatch!(sm, :UnknownEvent, 1)
    sm.counter = 0

    # Test default handler with isbits type
    allocs = @allocated(Hsm.dispatch!(sm, :UnknownEvent, 123))
    print_allocation_result("Default handler isbits", allocs)
    @test allocs == 0  # Allow for some allocation
    @test sm.counter == 100  # Marker for default handler
end

@testset "Default handler nothing allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up default handlers
    Hsm.dispatch!(sm, :AnotherUnknownEvent, nothing)
    sm.counter = 0

    # Test default handler with nothing
    allocs = @allocated(Hsm.dispatch!(sm, :AnotherUnknownEvent, nothing))
    print_allocation_result("Default handler nothing", allocs)
    @test allocs == 0  # Allow for some allocation
    @test sm.counter == 100  # Marker for default handler
end

@testset "Default handler non-isbits allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up default handlers
    Hsm.dispatch!(sm, :YetAnotherEvent, "warmup")
    sm.counter = 0

    # Test default handler with non-isbits type
    result = @allocated(Hsm.dispatch!(sm, :YetAnotherEvent, "non-isbits"))
    print_allocation_result("Default handler non-isbits", result)
    @test result == 0  # Should not allocate for String (default handler)
    @test sm.counter == 100  # Marker for default handler
end

@testset "Stress test - isbits dispatches" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up for stress test
    for i in 1:5
        Hsm.dispatch!(sm, :TestEvent, i)
    end
    sm.counter = 0

    # Measure single dispatch allocations and sum separately
    total_allocs = 0
    for i in 1:100
        alloc = @allocated Hsm.dispatch!(sm, :TestEvent, i)
        total_allocs += alloc
    end

    print_allocation_result("Stress test (100 isbits dispatches)", total_allocs)
    print_allocation_result("Average per dispatch", total_allocs / 100)
    @test total_allocs == 000  # Should not allocate in bulk operations
    @test sm.counter == 100
end

# Helper function to run a single non-isbits dispatch and measure allocations
function run_single_nonisbits_dispatch(sm, str)
    return @allocated Hsm.dispatch!(sm, :TestEvent, str)
end

# Helper function to run the entire stress test with non-isbits types
function run_nonisbits_stress_test(sm, test_strings)
    total_allocs = 0
    for i in 1:10
        total_allocs += run_single_nonisbits_dispatch(sm, test_strings[i])
    end
    return total_allocs
end

@testset "Stress test - non-isbits dispatches" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Prepare test strings outside the allocation measurement
    test_strings = ["string_$i" for i in 1:10]

    # Warm up for stress test with the precomputed strings
    for i in 1:2
        Hsm.dispatch!(sm, :TestEvent, test_strings[i])
    end

    # Now also warm up our helper functions
    run_single_nonisbits_dispatch(sm, test_strings[1])
    run_nonisbits_stress_test(sm, test_strings)

    sm.counter = 0

    # Run the actual test with the measurement
    total_allocs = run_nonisbits_stress_test(sm, test_strings)

    print_allocation_result("Stress test (10 non-isbits dispatches)", total_allocs)
    print_allocation_result("Average per dispatch (non-isbits)", total_allocs / 10)
    @test total_allocs == 0  # Now expected to be zero or minimal allocation
    @test sm.counter == 10
end

@testset "Large Int edge case allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up with edge cases
    Hsm.dispatch!(sm, :TestEvent, typemax(Int64))
    sm.counter = 0

    # Test with very large Int (still isbits)
    large_int = typemax(Int64)
    allocs = @allocated(Hsm.dispatch!(sm, :TestEvent, large_int))
    print_allocation_result("Large Int edge case", allocs)
    @test allocs == 0  # Allow for some allocation
    @test sm.counter == 1
    @test sm.int_data == large_int
end

@testset "Small Float edge case allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up with edge cases
    Hsm.dispatch!(sm, :TestEvent, nextfloat(0.0))
    sm.counter = 0

    # Test with very small Float64 (still isbits)
    small_float = nextfloat(0.0)
    allocs = @allocated(Hsm.dispatch!(sm, :TestEvent, small_float))
    print_allocation_result("Small Float edge case", allocs)
    @test allocs == 0  # Allow for some allocation
    @test sm.counter == 1
    @test sm.float_data == small_float
end

@testset "Empty tuple edge case allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up with edge cases
    Hsm.dispatch!(sm, :TestEvent, ())
    sm.counter = 0

    # Test with empty tuple (isbits)
    empty_tuple = ()
    allocs = @allocated(Hsm.dispatch!(sm, :TestEvent, empty_tuple))
    print_allocation_result("Empty tuple edge case", allocs)
    @test allocs == 0  # Allow for some allocation with the catch-all handler
    @test sm.counter == 1
    @test sm.int_data == sizeof(empty_tuple)  # Using catch-all handler
end

@testset "Custom struct allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)
    warmup_allocation_test_sm!(sm)

    # Warm up with this specific type
    test_struct = CustomStruct(42, "test")
    Hsm.dispatch!(sm, :StructEvent, test_struct)
    sm.counter = 0

    allocs = @allocated(Hsm.dispatch!(sm, :StructEvent, test_struct))
    print_allocation_result("Custom struct", allocs)
    @test allocs == 0
    @test sm.counter == 1
    @test sm.int_data == 42
end

@testset "Small Vector{Int} allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)
    warmup_allocation_test_sm!(sm)

    # Warm up with this specific type
    small_vec = [1, 2, 3]
    Hsm.dispatch!(sm, :VectorEvent, small_vec)
    sm.counter = 0

    allocs = @allocated(Hsm.dispatch!(sm, :VectorEvent, small_vec))
    print_allocation_result("Small Vector{Int}", allocs)
    @test allocs == 0
    @test sm.counter == 1
    @test sm.int_data == 3
end

@testset "Large Vector{Int} allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)
    warmup_allocation_test_sm!(sm)

    # Warm up with this specific type
    large_vec = collect(1:100)
    Hsm.dispatch!(sm, :VectorEvent, large_vec)
    sm.counter = 0

    allocs = @allocated(Hsm.dispatch!(sm, :VectorEvent, large_vec))
    print_allocation_result("Large Vector{Int}", allocs)
    @test allocs == 0
    @test sm.counter == 1
    @test sm.int_data == 100
end

@testset "Vector{Any} allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)
    warmup_allocation_test_sm!(sm)

    # Warm up with this specific type
    mixed_vec = Any[1, "two", 3.0]
    Hsm.dispatch!(sm, :VectorAnyEvent, mixed_vec)
    sm.counter = 0

    allocs = @allocated(Hsm.dispatch!(sm, :VectorAnyEvent, mixed_vec))
    print_allocation_result("Vector{Any}", allocs)
    @test allocs == 0
    @test sm.counter == 1
    @test sm.int_data == 3
end

@testset "Nested struct allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)
    warmup_allocation_test_sm!(sm)

    # Warm up with this specific type
    inner = CustomStruct(99, "nested")
    nested = NestedStruct(inner, 3.14)
    Hsm.dispatch!(sm, :NestedEvent, nested)
    sm.counter = 0

    allocs = @allocated(Hsm.dispatch!(sm, :NestedEvent, nested))
    print_allocation_result("Nested struct", allocs)
    @test allocs == 0
    @test sm.counter == 1
    @test sm.int_data == 99
end

@testset "Custom struct dispatch allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)
    warmup_allocation_test_sm!(sm)

    # Warm up with this specific type
    test_struct = CustomStruct(42, "test")
    Hsm.dispatch!(sm, :StructEvent, test_struct)
    sm.counter = 0

    allocs = @allocated(Hsm.dispatch!(sm, :StructEvent, test_struct))
    print_allocation_result("Custom struct", allocs)
    @test allocs == 0
    @test sm.counter == 1
    @test sm.int_data == 42
end

@testset "Small Vector{Int} allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)
    warmup_allocation_test_sm!(sm)

    # Warm up with this specific type
    small_vec = [1, 2, 3]
    Hsm.dispatch!(sm, :VectorEvent, small_vec)
    sm.counter = 0

    allocs = @allocated(Hsm.dispatch!(sm, :VectorEvent, small_vec))
    print_allocation_result("Small Vector{Int}", allocs)
    @test allocs == 0
    @test sm.counter == 1
    @test sm.int_data == 3
end

@testset "Large Vector{Int} allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)
    warmup_allocation_test_sm!(sm)

    # Warm up with this specific type
    large_vec = collect(1:100)
    Hsm.dispatch!(sm, :VectorEvent, large_vec)
    sm.counter = 0

    allocs = @allocated(Hsm.dispatch!(sm, :VectorEvent, large_vec))
    print_allocation_result("Large Vector{Int}", allocs)
    @test allocs == 0
    @test sm.counter == 1
    @test sm.int_data == 100
end

@testset "Vector{Any} allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)
    warmup_allocation_test_sm!(sm)

    # Warm up with this specific type
    mixed_vec = Any[1, "two", 3.0]
    Hsm.dispatch!(sm, :VectorAnyEvent, mixed_vec)
    sm.counter = 0

    allocs = @allocated(Hsm.dispatch!(sm, :VectorAnyEvent, mixed_vec))
    print_allocation_result("Vector{Any}", allocs)
    @test allocs == 0
    @test sm.counter == 1
    @test sm.int_data == 3
end

@testset "Nested struct allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)
    warmup_allocation_test_sm!(sm)

    # Warm up with this specific type
    inner = CustomStruct(99, "nested")
    nested = NestedStruct(inner, 3.14)
    Hsm.dispatch!(sm, :NestedEvent, nested)
    sm.counter = 0

    allocs = @allocated(Hsm.dispatch!(sm, :NestedEvent, nested))
    print_allocation_result("Nested struct", allocs)
    @test allocs == 0
    @test sm.counter == 1
    @test sm.int_data == 99
end

@testset "Struct transition allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up with this specific type and transition
    test_struct = CustomStruct(42, "test")
    Hsm.dispatch!(sm, :StructTransitionEvent, test_struct)
    Hsm.dispatch!(sm, :StructResetEvent, test_struct)
    sm.counter = 0

    # Test transition with struct
    allocs = @allocated(Hsm.dispatch!(sm, :StructTransitionEvent, test_struct))
    print_allocation_result("Struct transition", allocs)
    @test allocs == 0
    @test Hsm.current(sm) == :StateB
    @test sm.int_data == 42
end

@testset "Vector transition allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up with this specific type and transition
    test_vec = [1, 2, 3, 4]
    Hsm.dispatch!(sm, :VectorTransitionEvent, test_vec)
    Hsm.dispatch!(sm, :VectorResetEvent, test_vec)
    sm.counter = 0

    # Test transition with vector
    allocs = @allocated(Hsm.dispatch!(sm, :VectorTransitionEvent, test_vec))
    print_allocation_result("Vector transition", allocs)
    @test allocs == 0
    @test Hsm.current(sm) == :StateB
    @test sm.int_data == 4
end

@testset "Struct reset transition allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Move to StateB first
    test_struct = CustomStruct(99, "reset")
    Hsm.dispatch!(sm, :StructTransitionEvent, test_struct)

    # Verify we're in the right state
    @test Hsm.current(sm) == :StateB

    # Set non-zero counter to verify reset
    sm.counter = 100

    # Test reset with struct
    allocs = @allocated(Hsm.dispatch!(sm, :StructResetEvent, test_struct))
    print_allocation_result("Struct reset transition", allocs)
    @test allocs == 0
    @test Hsm.current(sm) == :StateA
    @test sm.counter == 0
    @test sm.int_data == 99
end

@testset "Vector reset transition allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Move to StateB first
    test_vec = [5, 6, 7, 8, 9]
    Hsm.dispatch!(sm, :VectorTransitionEvent, test_vec)

    # Verify we're in the right state
    @test Hsm.current(sm) == :StateB

    # Set non-zero counter to verify reset
    sm.counter = 100

    # Test reset with vector
    allocs = @allocated(Hsm.dispatch!(sm, :VectorResetEvent, test_vec))
    print_allocation_result("Vector reset transition", allocs)
    @test allocs == 0
    @test Hsm.current(sm) == :StateA
    @test sm.counter == 0
    @test sm.int_data == 5
end
