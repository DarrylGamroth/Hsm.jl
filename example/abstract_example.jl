# Abstract State Machine Example
#
# This example demonstrates the use of @abstracthsmdef to create a family of
# related state machines that share a common interface and state hierarchy.
#
# Key concepts:
# 1. @abstracthsmdef VehicleController
#    - Defines the abstract type AND creates the HSM interface methods
#    - Only needs to be called once for the abstract type
#
# 2. Shared state hierarchy and handlers
#    - @statedef, @on_initial, @on_entry, @on_exit, @on_event defined on VehicleController
#    - All concrete types (Car, Truck, Motorcycle) inherit these definitions
#
# 3. Concrete types using @hsmdef with inheritance
#    - @hsmdef mutable struct Car <: VehicleController
#    - Only generates field accessors (current, source, etc.)
#    - Does NOT regenerate the interface methods (they're inherited)
#
# 4. Specialized behavior per concrete type
#    - Each concrete type can override or add specific event handlers
#    - Car, Truck, Motorcycle each have different acceleration/coasting behavior
#
# 5. Polymorphism
#    - All concrete types are VehicleControllers
#    - Can be stored in arrays and processed uniformly
#    - Each maintains its own independent state
#
# Compare with simplest_example.jl which uses a single concrete type without inheritance.

using Pkg
Pkg.activate(".")

using Hsm
using ValSplit

# Define an abstract state machine type with shared interface
# This creates both the abstract type and the HSM interface methods
@abstracthsmdef VehicleController

# Define state hierarchy on the abstract type (shared by all vehicles)
@statedef VehicleController :Stopped
@statedef VehicleController :Moving
@statedef VehicleController :Running :Moving
@statedef VehicleController :Coasting :Moving

# Shared initial handler for all vehicle types
@on_initial function (sm::VehicleController, ::Root)
    println("Initializing $(typeof(sm))")
    return Hsm.transition!(sm, :Stopped)
end

# Shared entry/exit handlers
@on_entry function (sm::VehicleController, state::Any)
    println("  [$(typeof(sm))] Entering state: $state")
end

@on_exit function (sm::VehicleController, state::Any)
    println("  [$(typeof(sm))] Exiting state: $state")
end

# Shared event handlers for all vehicles
@on_event function (sm::VehicleController, ::Stopped, ::Accelerate, _)
    println("  Starting to move...")
    return Hsm.transition!(sm, :Running)
end

@on_event function (sm::VehicleController, ::Running, ::Coast, _)
    println("  Coasting...")
    return Hsm.transition!(sm, :Coasting)
end

@on_event function (sm::VehicleController, ::Moving, ::Stop, _)
    println("  Stopping...")
    return Hsm.transition!(sm, :Stopped)
end

# Now define concrete vehicle types - they only need field accessors
# The HSM interface is inherited from VehicleController

@hsmdef mutable struct Car <: VehicleController
    speed::Float64
    fuel::Float64
    passengers::Int
end

@hsmdef mutable struct Truck <: VehicleController
    speed::Float64
    fuel::Float64
    cargo_weight::Float64
end

@hsmdef mutable struct Motorcycle <: VehicleController
    speed::Float64
    fuel::Float64
end

# Car-specific event handlers
@on_event function (sm::Car, ::Running, ::Accelerate, amount::Float64)
    sm.speed += amount
    sm.fuel -= amount * 0.1 * (1 + 0.05 * sm.passengers)  # More passengers = more fuel
    println("  Car accelerating to $(sm.speed) km/h (fuel: $(sm.fuel))")
    return Hsm.EventHandled
end

@on_event function (sm::Car, ::Coasting, event::Any, data)
    sm.speed = max(0, sm.speed - 5)
    println("  Car coasting at $(sm.speed) km/h")
    return Hsm.EventHandled
end

# Truck-specific event handlers
@on_event function (sm::Truck, ::Running, ::Accelerate, amount::Float64)
    weight_factor = 1 + sm.cargo_weight / 1000
    sm.speed += amount / weight_factor
    sm.fuel -= amount * 0.2 * weight_factor  # Heavier = more fuel
    println("  Truck accelerating to $(sm.speed) km/h (fuel: $(sm.fuel), cargo: $(sm.cargo_weight) kg)")
    return Hsm.EventHandled
end

@on_event function (sm::Truck, ::Coasting, event::Any, data)
    sm.speed = max(0, sm.speed - 3)
    println("  Truck coasting at $(sm.speed) km/h")
    return Hsm.EventHandled
end

# Motorcycle-specific event handlers
@on_event function (sm::Motorcycle, ::Running, ::Accelerate, amount::Float64)
    sm.speed += amount * 1.5  # Motorcycles accelerate faster
    sm.fuel -= amount * 0.05  # More fuel efficient
    println("  Motorcycle accelerating to $(sm.speed) km/h (fuel: $(sm.fuel))")
    return Hsm.EventHandled
end

@on_event function (sm::Motorcycle, ::Coasting, event::Any, data)
    sm.speed = max(0, sm.speed - 8)  # Slow down faster
    println("  Motorcycle coasting at $(sm.speed) km/h")
    return Hsm.EventHandled
end

# Generic function that works with any VehicleController
function run_vehicle_scenario(vehicle::VehicleController, name::String)
    println("\n=== Testing $name ===")
    println("Initial state: $(Hsm.current(vehicle))")
    
    # Start moving
    Hsm.dispatch!(vehicle, :Accelerate)
    
    # Accelerate a few times
    for i in 1:3
        Hsm.dispatch!(vehicle, :Accelerate, 20.0)
    end
    
    # Coast
    Hsm.dispatch!(vehicle, :Coast)
    
    # Coast for a bit
    for i in 1:2
        Hsm.dispatch!(vehicle, :CoastUpdate)
    end
    
    # Note: We're intentionally leaving vehicles in Coasting state 
    # to demonstrate that different concrete types maintain independent state
    # Uncomment the next line to stop the vehicle:
    # Hsm.dispatch!(vehicle, :Stop)
    
    println("Final state: $(Hsm.current(vehicle))")
end

function (@main)(ARGS)
    println("=== Abstract State Machine Example ===")
    println("Demonstrating @abstracthsmdef with shared interface\n")
    
    # Create different vehicle instances
    car = Car(0.0, 100.0, 4)
    truck = Truck(0.0, 200.0, 5000.0)
    motorcycle = Motorcycle(0.0, 50.0)
    
    # All vehicles share the same state hierarchy and base event handlers
    # But each has specialized behavior for certain events
    
    run_vehicle_scenario(car, "Family Car")
    run_vehicle_scenario(truck, "Delivery Truck")
    run_vehicle_scenario(motorcycle, "Sport Motorcycle")
    
    # Demonstrate polymorphism - all are VehicleControllers
    println("\n=== Polymorphic Array ===")
    vehicles = VehicleController[car, truck, motorcycle]
    
    for (i, vehicle) in enumerate(vehicles)
        println("\nVehicle $i: $(typeof(vehicle))")
        println("  Current state: $(Hsm.current(vehicle))")
        println("  Speed: $(vehicle.speed) km/h")
        println("  Fuel: $(vehicle.fuel) L")
    end
end
