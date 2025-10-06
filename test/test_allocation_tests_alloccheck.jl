using Test
using Hsm
using ValSplit
using AllocCheck

@check_allocs check_dispatch!(sm, event, arg=nothing) = Hsm.dispatch!(sm, event, arg)

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

# Helper function to warmup the state machine with all dispatch types
function warmup_allocation_test_sm!(sm::AllocationTestSm)
    # Comprehensive warm up - ensure all method specializations are compiled
    for _ in 1:3  # Multiple rounds to ensure compilation is complete
        check_dispatch!(sm, :TestEvent, 1)
        check_dispatch!(sm, :TestEvent, 1.0)
        check_dispatch!(sm, :TestEvent, true)
        check_dispatch!(sm, :TestEvent, :sym)
        check_dispatch!(sm, :TestEvent, 'x')
        check_dispatch!(sm, :TestEvent, UInt8(1))

        # Warm up our new types and transitions
        test_struct = CustomStruct(42, "test")
        check_dispatch!(sm, :StructEvent, test_struct)
        check_dispatch!(sm, :StructTransitionEvent, test_struct)
        check_dispatch!(sm, :StructResetEvent, test_struct)

        small_vec = [1, 2, 3]
        check_dispatch!(sm, :VectorEvent, small_vec)
        check_dispatch!(sm, :VectorTransitionEvent, small_vec)
        check_dispatch!(sm, :VectorResetEvent, small_vec)

        mixed_vec = Any[1, "two", 3.0]
        check_dispatch!(sm, :VectorAnyEvent, mixed_vec)

        inner = CustomStruct(99, "nested")
        nested = NestedStruct(inner, 3.14)
        check_dispatch!(sm, :NestedEvent, nested)
    end
    sm.counter = 0  # Reset counter after warmup
end

@testset "Int dispatch allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)
    warmup_allocation_test_sm!(sm)

    check_dispatch!(sm, :TestEvent, 42)
    @test sm.counter == 1
    @test sm.int_data == 42
end

@testset "Float64 dispatch allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)
    warmup_allocation_test_sm!(sm)

    check_dispatch!(sm, :TestEvent, 3.14)
    @test sm.counter == 1
    @test sm.float_data == 3.14
end

@testset "Bool dispatch allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)
    warmup_allocation_test_sm!(sm)

    check_dispatch!(sm, :TestEvent, true)
    @test sm.counter == 1
    @test sm.bool_data == true
end

@testset "Symbol dispatch allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)
    warmup_allocation_test_sm!(sm)

    check_dispatch!(sm, :TestEvent, :symbol_value)
    @test sm.counter == 1
    @test sm.symbol_data == :symbol_value
end

@testset "Char dispatch allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)
    warmup_allocation_test_sm!(sm)

    check_dispatch!(sm, :TestEvent, 'A')
    @test sm.counter == 1
    @test sm.char_data == 'A'
end

@testset "UInt8 dispatch allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)
    warmup_allocation_test_sm!(sm)

    check_dispatch!(sm, :TestEvent, UInt8(255))
    @test sm.counter == 1
    @test sm.int_data == 255  # Converted to Int
end

@testset "Nothing dispatch allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up with nothing
    for _ in 1:5
        check_dispatch!(sm, :TestEvent, nothing)
        check_dispatch!(sm, :TestEvent)
    end
    sm.counter = 0

    # Test with nothing (special isbits singleton)
    check_dispatch!(sm, :TestEvent, nothing)
    @test sm.counter == 1
    @test sm.last_event == :TestEvent
end

@testset "No argument dispatch allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up with nothing
    for _ in 1:5
        check_dispatch!(sm, :TestEvent, nothing)
        check_dispatch!(sm, :TestEvent)
    end
    sm.counter = 0

    # Test with no argument (defaults to nothing)
    check_dispatch!(sm, :TestEvent)
    @test sm.counter == 1
    @test sm.last_event == :TestEvent
end

@testset "Number abstract type dispatch allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up with abstract types
    int_val_warmup::Number = 1
    check_dispatch!(sm, :TestEvent, int_val_warmup)
    sm.counter = 0

    # Test with Number (abstract type through Int)
    int_val::Number = 123
    check_dispatch!(sm, :TestEvent, int_val)
    @test sm.counter == 1
    @test sm.int_data == 123
end

@testset "Real abstract type dispatch allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up with abstract types
    float_val_warmup::Real = 1.0
    check_dispatch!(sm, :TestEvent, float_val_warmup)
    sm.counter = 0

    # Test with Real (abstract type through Float64)
    float_val::Real = 2.718
    check_dispatch!(sm, :TestEvent, float_val)
    @test sm.counter == 1
    @test sm.float_data == 2.718
end

@testset "Any type dispatch allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up with abstract types
    any_val_warmup::Any = 1
    check_dispatch!(sm, :TestEvent, any_val_warmup)
    sm.counter = 0

    # Test with Any type containing isbits value
    any_val::Any = 456
    check_dispatch!(sm, :TestEvent, any_val)
    @test sm.counter == 1
    @test sm.int_data == 456
end

@testset "String dispatch allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up with non-isbits types
    check_dispatch!(sm, :TestEvent, "warmup")
    sm.counter = 0

    # Test with String (non-isbits, heap allocated)
    check_dispatch!(sm, :TestEvent, "hello")
    @test sm.counter == 1
    @test sm.string_data == "hello"
end

@testset "Array dispatch allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up with non-isbits types
    check_dispatch!(sm, :TestEvent, [1])
    sm.counter = 0

    # Test with Array (non-isbits, heap allocated)
    arr = [1, 2, 3]
    check_dispatch!(sm, :TestEvent, arr)
    @test sm.counter == 1
    @test sm.int_data == sizeof(arr)  # Using catch-all handler
end

@testset "Dict dispatch allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up with non-isbits types
    check_dispatch!(sm, :TestEvent, Dict(:k => :v))
    sm.counter = 0

    # Test with Dict (non-isbits, heap allocated)
    dict = Dict(:key => :value)
    check_dispatch!(sm, :TestEvent, dict)
    @test sm.counter == 1
    @test sm.int_data == sizeof(dict)  # Using catch-all handler
end

@testset "State transition allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up state transitions
    check_dispatch!(sm, :TransitionEvent, 1)
    check_dispatch!(sm, :ResetEvent, 1)
    sm.counter = 0

    # Test transition with isbits argument
    check_dispatch!(sm, :TransitionEvent, 789)
    @test Hsm.current(sm) == :StateB
end

@testset "State reset transition allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up state transitions
    check_dispatch!(sm, :TransitionEvent, 1)  # Move from StateA to StateB

    # Verify we're in the right state
    @test Hsm.current(sm) == :StateB

    # Make sure the counter has a non-zero value to verify reset
    sm.counter = 100

    # Now test the ResetEvent which should trigger transition back to StateA
    check_dispatch!(sm, :ResetEvent, 999)
    @test Hsm.current(sm) == :StateA  # Should be back in StateA
    @test sm.counter == 0  # Counter should be reset by the handler
end

@testset "Default handler isbits allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up default handlers
    check_dispatch!(sm, :UnknownEvent, 1)
    sm.counter = 0

    # Test default handler with isbits type
    check_dispatch!(sm, :UnknownEvent, 123)
    @test sm.counter == 100  # Marker for default handler
end

@testset "Default handler nothing allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up default handlers
    check_dispatch!(sm, :AnotherUnknownEvent, nothing)
    sm.counter = 0

    # Test default handler with nothing
    check_dispatch!(sm, :AnotherUnknownEvent, nothing)
    @test sm.counter == 100  # Marker for default handler
end

@testset "Default handler non-isbits allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up default handlers
    check_dispatch!(sm, :YetAnotherEvent, "warmup")
    sm.counter = 0

    # Test default handler with non-isbits type
    check_dispatch!(sm, :YetAnotherEvent, "non-isbits")
    @test sm.counter == 100  # Marker for default handler
end

@testset "Stress test - isbits dispatches" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up for stress test
    for i in 1:5
        check_dispatch!(sm, :TestEvent, i)
    end
    sm.counter = 0

    # Measure single dispatch allocations and sum separately
    total_allocs = 0
    for i in 1:100
        check_dispatch!(sm, :TestEvent, i)
    end

    @test sm.counter == 100
end

@testset "Large Int edge case allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up with edge cases
    check_dispatch!(sm, :TestEvent, typemax(Int64))
    sm.counter = 0

    # Test with very large Int (still isbits)
    large_int = typemax(Int64)
    check_dispatch!(sm, :TestEvent, large_int)
    @test sm.counter == 1
    @test sm.int_data == large_int
end

@testset "Small Float edge case allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up with edge cases
    check_dispatch!(sm, :TestEvent, nextfloat(0.0))
    sm.counter = 0

    # Test with very small Float64 (still isbits)
    small_float = nextfloat(0.0)
    check_dispatch!(sm, :TestEvent, small_float)
    @test sm.counter == 1
    @test sm.float_data == small_float
end

@testset "Empty tuple edge case allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up with edge cases
    check_dispatch!(sm, :TestEvent, ())
    sm.counter = 0

    # Test with empty tuple (isbits)
    empty_tuple = ()
    check_dispatch!(sm, :TestEvent, empty_tuple)
    @test sm.counter == 1
    @test sm.int_data == sizeof(empty_tuple)  # Using catch-all handler
end

@testset "Custom struct allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)
    warmup_allocation_test_sm!(sm)

    # Warm up with this specific type
    test_struct = CustomStruct(42, "test")
    check_dispatch!(sm, :StructEvent, test_struct)
    sm.counter = 0

    check_dispatch!(sm, :StructEvent, test_struct)
    @test sm.counter == 1
    @test sm.int_data == 42
end

@testset "Small Vector{Int} allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)
    warmup_allocation_test_sm!(sm)

    # Warm up with this specific type
    small_vec = [1, 2, 3]
    check_dispatch!(sm, :VectorEvent, small_vec)
    sm.counter = 0

    check_dispatch!(sm, :VectorEvent, small_vec)
    @test sm.counter == 1
    @test sm.int_data == 3
end

@testset "Large Vector{Int} allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)
    warmup_allocation_test_sm!(sm)

    # Warm up with this specific type
    large_vec = collect(1:100)
    check_dispatch!(sm, :VectorEvent, large_vec)
    sm.counter = 0

    check_dispatch!(sm, :VectorEvent, large_vec)
    @test sm.counter == 1
    @test sm.int_data == 100
end

@testset "Vector{Any} allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)
    warmup_allocation_test_sm!(sm)

    # Warm up with this specific type
    mixed_vec = Any[1, "two", 3.0]
    check_dispatch!(sm, :VectorAnyEvent, mixed_vec)
    sm.counter = 0

    check_dispatch!(sm, :VectorAnyEvent, mixed_vec)
    @test sm.counter == 1
    @test sm.int_data == 3
end

@testset "Nested struct allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)
    warmup_allocation_test_sm!(sm)

    # Warm up with this specific type
    inner = CustomStruct(99, "nested")
    nested = NestedStruct(inner, 3.14)
    check_dispatch!(sm, :NestedEvent, nested)
    sm.counter = 0

    check_dispatch!(sm, :NestedEvent, nested)
    @test sm.counter == 1
    @test sm.int_data == 99
end

@testset "Struct transition allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up with this specific type and transition
    test_struct = CustomStruct(42, "test")
    check_dispatch!(sm, :StructTransitionEvent, test_struct)
    check_dispatch!(sm, :StructResetEvent, test_struct)
    sm.counter = 0

    # Test transition with struct
    check_dispatch!(sm, :StructTransitionEvent, test_struct)
    @test Hsm.current(sm) == :StateB
    @test sm.int_data == 42
end

@testset "Vector transition allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Warm up with this specific type and transition
    test_vec = [1, 2, 3, 4]
    check_dispatch!(sm, :VectorTransitionEvent, test_vec)
    check_dispatch!(sm, :VectorResetEvent, test_vec)
    sm.counter = 0

    # Test transition with vector
    check_dispatch!(sm, :VectorTransitionEvent, test_vec)
    @test Hsm.current(sm) == :StateB
    @test sm.int_data == 4
end

@testset "Struct reset transition allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Move to StateB first
    test_struct = CustomStruct(99, "reset")
    check_dispatch!(sm, :StructTransitionEvent, test_struct)

    # Verify we're in the right state
    @test Hsm.current(sm) == :StateB

    # Set non-zero counter to verify reset
    sm.counter = 100

    # Test reset with struct
    check_dispatch!(sm, :StructResetEvent, test_struct)
    @test Hsm.current(sm) == :StateA
    @test sm.counter == 0
    @test sm.int_data == 99
end

@testset "Vector reset transition allocation test" begin
    sm = AllocationTestSm(0, 0, 0.0, false, :default, ' ', "", :none)

    # Move to StateB first
    test_vec = [5, 6, 7, 8, 9]
    check_dispatch!(sm, :VectorTransitionEvent, test_vec)

    # Verify we're in the right state
    @test Hsm.current(sm) == :StateB

    # Set non-zero counter to verify reset
    sm.counter = 100

    # Test reset with vector
    check_dispatch!(sm, :VectorResetEvent, test_vec)
    @test Hsm.current(sm) == :StateA
    @test sm.counter == 0
    @test sm.int_data == 5
end

# Abstract state machine inheritance tests
@abstracthsmdef AbstractVehicleController

@hsmdef mutable struct CarController <: AbstractVehicleController
    speed::Float64
    gear::Int
    counter::Int
end

@hsmdef mutable struct TruckController <: AbstractVehicleController
    speed::Float64
    load::Float64
    counter::Int
end

# Define state hierarchy for vehicles
@statedef AbstractVehicleController :Idle :Root
@statedef AbstractVehicleController :Moving :Root
@statedef AbstractVehicleController :Stopped :Root

# Shared handlers for all vehicle types
@on_initial function (sm::AbstractVehicleController, ::Root)
    return Hsm.transition!(sm, :Idle)
end

@on_event function (sm::AbstractVehicleController, ::Idle, ::StartEngine, arg::Int)
    sm.counter += 1
    return Hsm.transition!(sm, :Moving)
end

@on_event function (sm::AbstractVehicleController, ::Moving, ::StopEngine, arg::Int)
    sm.counter += 1
    return Hsm.transition!(sm, :Stopped)
end

@on_event function (sm::AbstractVehicleController, ::Stopped, ::RestartEngine, arg::Int)
    sm.counter = 0
    return Hsm.transition!(sm, :Idle)
end

# Car-specific handlers
@on_event function (sm::CarController, ::Moving, ::ShiftGear, arg::Int)
    sm.gear = arg
    sm.counter += 1
    return Hsm.EventHandled
end

@on_event function (sm::CarController, ::Moving, ::Accelerate, arg::Float64)
    sm.speed += arg
    sm.counter += 1
    return Hsm.EventHandled
end

# Truck-specific handlers
@on_event function (sm::TruckController, ::Moving, ::AdjustLoad, arg::Float64)
    sm.load = arg
    sm.counter += 1
    return Hsm.EventHandled
end

@on_event function (sm::TruckController, ::Moving, ::Accelerate, arg::Float64)
    # Trucks accelerate slower with load
    sm.speed += arg / (1 + sm.load / 100)
    sm.counter += 1
    return Hsm.EventHandled
end

# Helper function for warming up abstract vehicle controllers
function warmup_vehicle_controller!(sm::AbstractVehicleController)
    for _ in 1:3
        check_dispatch!(sm, :StartEngine, 1)
        check_dispatch!(sm, :StopEngine, 1)
        check_dispatch!(sm, :RestartEngine, 1)
    end
    sm.counter = 0
end

function warmup_car_controller!(sm::CarController)
    warmup_vehicle_controller!(sm)
    for _ in 1:3
        check_dispatch!(sm, :StartEngine, 1)
        check_dispatch!(sm, :ShiftGear, 3)
        check_dispatch!(sm, :Accelerate, 10.0)
        check_dispatch!(sm, :StopEngine, 1)
        check_dispatch!(sm, :RestartEngine, 1)
    end
    sm.counter = 0
end

function warmup_truck_controller!(sm::TruckController)
    warmup_vehicle_controller!(sm)
    for _ in 1:3
        check_dispatch!(sm, :StartEngine, 1)
        check_dispatch!(sm, :AdjustLoad, 50.0)
        check_dispatch!(sm, :Accelerate, 10.0)
        check_dispatch!(sm, :StopEngine, 1)
        check_dispatch!(sm, :RestartEngine, 1)
    end
    sm.counter = 0
end

@testset "Abstract inheritance - Car shared handler allocation test" begin
    sm = CarController(0.0, 1, 0)
    warmup_car_controller!(sm)

    check_dispatch!(sm, :StartEngine, 1)
    @test Hsm.current(sm) == :Moving
    @test sm.counter == 1
end

@testset "Abstract inheritance - Car specific handler allocation test" begin
    sm = CarController(0.0, 1, 0)
    warmup_car_controller!(sm)
    
    # Move to Moving state first
    check_dispatch!(sm, :StartEngine, 1)
    sm.counter = 0

    check_dispatch!(sm, :ShiftGear, 5)
    @test sm.gear == 5
    @test sm.counter == 1
end

@testset "Abstract inheritance - Car accelerate allocation test" begin
    sm = CarController(0.0, 1, 0)
    warmup_car_controller!(sm)
    
    # Move to Moving state first
    check_dispatch!(sm, :StartEngine, 1)
    sm.counter = 0
    sm.speed = 0.0

    check_dispatch!(sm, :Accelerate, 25.5)
    @test sm.speed == 25.5
    @test sm.counter == 1
end

@testset "Abstract inheritance - Truck shared handler allocation test" begin
    sm = TruckController(0.0, 0.0, 0)
    warmup_truck_controller!(sm)

    check_dispatch!(sm, :StartEngine, 1)
    @test Hsm.current(sm) == :Moving
    @test sm.counter == 1
end

@testset "Abstract inheritance - Truck specific handler allocation test" begin
    sm = TruckController(0.0, 0.0, 0)
    warmup_truck_controller!(sm)
    
    # Move to Moving state first
    check_dispatch!(sm, :StartEngine, 1)
    sm.counter = 0

    check_dispatch!(sm, :AdjustLoad, 75.0)
    @test sm.load == 75.0
    @test sm.counter == 1
end

@testset "Abstract inheritance - Truck accelerate with load allocation test" begin
    sm = TruckController(0.0, 50.0, 0)
    warmup_truck_controller!(sm)
    
    # Move to Moving state first
    check_dispatch!(sm, :StartEngine, 1)
    sm.counter = 0
    sm.speed = 0.0

    # With 50.0 load: acceleration = 20.0 / (1 + 50/100) = 20.0 / 1.5 ≈ 13.333...
    check_dispatch!(sm, :Accelerate, 20.0)
    @test sm.speed ≈ 20.0 / 1.5
    @test sm.counter == 1
end

@testset "Abstract inheritance - Polymorphic dispatch allocation test" begin
    car = CarController(0.0, 1, 0)
    truck = TruckController(0.0, 0.0, 0)
    
    warmup_car_controller!(car)
    warmup_truck_controller!(truck)

    # Test polymorphic dispatch - same event, different implementations
    vehicles = AbstractVehicleController[car, truck]
    
    for vehicle in vehicles
        check_dispatch!(vehicle, :StartEngine, 1)
        @test Hsm.current(vehicle) == :Moving
    end
    
    @test car.counter == 1
    @test truck.counter == 1
end

@testset "Abstract inheritance - State transition allocation test" begin
    sm = CarController(0.0, 1, 0)
    warmup_car_controller!(sm)

    check_dispatch!(sm, :StartEngine, 1)
    @test Hsm.current(sm) == :Moving
    
    check_dispatch!(sm, :StopEngine, 1)
    @test Hsm.current(sm) == :Stopped
    @test sm.counter == 2
end

@testset "Abstract inheritance - Reset transition allocation test" begin
    sm = TruckController(0.0, 100.0, 0)
    warmup_truck_controller!(sm)

    check_dispatch!(sm, :StartEngine, 1)
    check_dispatch!(sm, :StopEngine, 1)
    @test Hsm.current(sm) == :Stopped
    @test sm.counter == 2

    check_dispatch!(sm, :RestartEngine, 1)
    @test Hsm.current(sm) == :Idle
    @test sm.counter == 0
end
