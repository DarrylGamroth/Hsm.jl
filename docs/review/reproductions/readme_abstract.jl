using Hsm

# Define an abstract state machine type with shared interface
@abstracthsmdef VehicleController

# Define shared state hierarchy (applies to all concrete types)
@statedef VehicleController :Stopped
@statedef VehicleController :Moving

# Define shared event handlers
@on_event function(sm::VehicleController, ::Stopped, ::Start, _)
    return Hsm.transition!(sm, :Moving)
end

# Create concrete types - they inherit the interface
@hsmdef mutable struct Car <: VehicleController
    speed::Float64
    fuel::Float64
end

@hsmdef mutable struct Truck <: VehicleController
    speed::Float64
    cargo::Float64
end

# Add type-specific behavior
@on_event function(sm::Car, ::Moving, ::Accelerate, amount::Float64)
    sm.speed += amount
    sm.fuel -= amount * 0.1
    return Hsm.EventHandled
end

@on_event function(sm::Truck, ::Moving, ::Accelerate, amount::Float64)
    sm.speed += amount / (1 + sm.cargo / 1000)
    sm.fuel -= amount * 0.2
    return Hsm.EventHandled
end

# Use polymorphically
vehicles = VehicleController[Car(0.0, 100.0), Truck(0.0, 5000.0)]
for vehicle in vehicles
    Hsm.dispatch!(vehicle, :Start)
    Hsm.dispatch!(vehicle, :Accelerate, 20.0)
end

initial_states = [Hsm.current(v) for v in vehicles]
@show initial_states
for v in vehicles
    Hsm.transition!(v, :Stopped)
    Hsm.dispatch!(v, :Start)
    try
        Hsm.dispatch!(v, :Accelerate, 20.0)
    catch error
        showerror(stdout, error)
        println()
    end
end

using Test
@test initial_states == [:Moving, :Moving]
